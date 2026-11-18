// fw_rt_val.svh: signal values (layer 2, semantics/processes.md "Signal
// values"). Each net has one value cell, typed by the signal class that first
// reads or writes it; every member's __fw_rt_obj points to the net. A write
// stores a pending value (request-update); the kernel makes pending values
// visible with __fw_rt_val::update() at its update points.

typedef class __fw_rt_proc;

// A net's value: the members' type is not known here, so the cell is typed
// by its subclass.
virtual class __fw_rt_cell;
    bit pend;               // a write waits for the next update
    pure virtual function bit commit();     // pending -> visible; 1 if changed
    pure virtual function void drop();      // forgets the pending write
    pure virtual function string ival();    // the visible value, decimal
endclass

class __fw_rt_cell_t #(type T = int) extends __fw_rt_cell;
    T cur;
    T nxt;

    virtual function bit commit();
        bit ch = (cur !== nxt);
        cur = nxt;
        pend = 0;
        return ch;
    endfunction

    virtual function void drop();
        nxt = cur;
        pend = 0;
    endfunction

    virtual function string ival();
        logic [$bits(T)-1:0] v = cur;
        return $sformatf("%0d", v);
    endfunction

    // The cell of h's net, created on first use; null before the nets are
    // formed or if h has no record.
    static function __fw_rt_cell_t #(T) of(fw_object h);
        __fw_rt_net n = __fw_rt_val::net_of(h);
        __fw_rt_cell_t #(T) c;
        if (n == null) return null;
        if (n.val == null) begin
            c = new;
            if (n.tied) begin
                logic [$bits(T)-1:0] tv;
                void'($sscanf(n.tie, "'h%h", tv));
                c.cur = T'(tv);
                c.nxt = c.cur;
            end
            n.val = c;
            return c;
        end
        void'($cast(c, n.val));
        return c;
    endfunction
endclass

// A net: the signals one connect() chain joins, across all scopes.
class __fw_rt_net;
    __fw_rt_obj   members[$];
    bit           tied;
    string        tie;          // 'h<hex>, as fw_signal::tie records it
    __fw_rt_cell  val;
    __fw_rt_proc  writer;       // the first block that wrote it (processes.md)
    bit           multi;        // FW-E-WRITE-MULTI reported
endclass

class __fw_rt_val;
    static bit           formed;
    static __fw_rt_cell  pending[$];
    static int           par[int];      // union-find over __fw_rt_obj.seq

    static function int find(int k);
        while (par[k] != k) begin
            par[k] = par[par[k]];
            k = par[k];
        end
        return k;
    endfunction

    // Joins every connection of every scope into global nets; a signal with
    // no connection is a net of its own. Called once, after resolve.
    static function void form_nets();
        __fw_rt_net by_root[int];
        foreach (__fw_rt::objs[i])
            if (__fw_rt::objs[i].is_signal()) par[__fw_rt::objs[i].seq] = __fw_rt::objs[i].seq;
        foreach (__fw_rt::conns[i]) begin
            __fw_rt_conn c = __fw_rt::conns[i];
            if (c.b == null || !par.exists(c.a.seq) || !par.exists(c.b.seq)) continue;
            par[find(c.a.seq)] = find(c.b.seq);
        end
        foreach (__fw_rt::objs[i]) begin
            __fw_rt_obj o = __fw_rt::objs[i];
            int r;
            if (!o.is_signal()) continue;
            r = find(o.seq);
            if (!by_root.exists(r)) by_root[r] = new;
            by_root[r].members.push_back(o);
            o.net = by_root[r];
        end
        foreach (__fw_rt::conns[i]) begin
            __fw_rt_conn c = __fw_rt::conns[i];
            if (c.b != null || c.a.net == null) continue;
            c.a.net.tied = 1;
            c.a.net.tie = c.tie;
        end
        formed = 1;
    endfunction

    static function __fw_rt_net net_of(fw_object h);
        __fw_rt_obj o = __fw_rt::impl(h);
        if (!formed || o == null) return null;
        return o.net;
    endfunction

    // Checks a write to h: 0 (and FW-E-WRITE-IN) if h is an effective input.
    static function bit may_write(fw_object h);
        __fw_rt_obj o = __fw_rt::impl(h);
        if (o == null || o.net == null) return 0;
        if (o.kind == __FW_K_PORT && o.eff_dir() == __FW_D_IN) begin
            __fw_rt::diag("FW-E-WRITE-IN", o.path, "write to an input; ignored");
            return 0;
        end
        return 1;
    endfunction

    static function void request(__fw_rt_cell c);
        if (c.pend) return;
        c.pend = 1;
        pending.push_back(c);
    endfunction

    // Makes every pending write visible; returns 1 if a value changed.
    static function bit update();
        bit ch = 0;
        foreach (pending[i]) ch |= pending[i].commit();
        pending.delete();
        return ch;
    endfunction
endclass
