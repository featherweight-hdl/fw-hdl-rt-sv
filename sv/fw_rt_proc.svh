// fw_rt_proc.svh: processes (layer 2, semantics/processes.md). Discovery
// after elaboration, writer learning ("Register or wire", FW-E-WRITE-MULTI),
// the clock domain of a step block ("Domain of a process",
// FW-E-STEP-DOMAINS), and where a write waits: a comb write for the
// settle's next pass (update_wires), a step or reset_state write for its
// clock domain's commit (commit). The edge loop that calls them is the
// kernel's.
//
// Kernel contract: call() a step block only at edges of its clk (null:
// no clock). A block of a component with interfaces in more than one clock
// starts in the component's clock; when a call's writes show another, the
// call's signal writes are dropped, clk moves and call() returns 0 (field
// writes of that one call stay: rt-sv cannot undo them).

typedef enum { __FW_PK_COMB, __FW_PK_STEP, __FW_PK_RUN, __FW_PK_RESET } __fw_rt_pkind_e;

class __fw_rt_proc;
    __fw_rt_pkind_e   kind;
    string            name;     // the macro's method; "" for the component's own
    __fw_rt_obj       comp;
    fw_comb_if        cb;
    fw_step_if        sb;
    fw_run_if         rb;
    fw_reset_state_if rsb;
    __fw_rt_obj       clk;      // step: its clock domain (tentative until learned)
    bit               learned;  // step: clk is final
    bit               bad;      // step: FW-E-STEP-DOMAINS reported; not called again
    process           ph;       // run: the forked run() task

    function string label();
        return name == "" ? comp.path : {comp.path, ".", name};
    endfunction
endclass

// A block a macro registered while its component was being constructed.
class __fw_rt_preg;
    fw_object   comp;
    fw_comb_if  cb;
    fw_step_if  sb;
    string      name;
endclass

class __fw_rt_procs;
    static __fw_rt_preg  regs[$];
    static __fw_rt_proc  procs[$];  // components in creation order, then macro blocks
    static __fw_rt_proc  cur;       // the block call() is running
    static __fw_rt_cell  wires[$];  // comb writes, for the settle's next pass
    static __fw_rt_obj   wobj[$];   //   and the signal each was written through
    static __fw_rt_obj   changed[$]; // signals update_wires() last changed
    static __fw_rt_cell  calls[$];  // register writes of the running call
    static __fw_rt_obj   cobj[$];   //   and the signal each was written through

    static function void add(fw_object comp, fw_comb_if cb, fw_step_if sb, string name);
        __fw_rt_preg r = new;
        r.comp = comp;
        r.cb = cb;
        r.sb = sb;
        r.name = name;
        regs.push_back(r);
    endfunction

    static function __fw_rt_obj clock_of(__fw_rt_obj o);
        return __fw_rt_dom::get(o, fw_clock_kind::get_type().name(), "", 0);
    endfunction

    // A signal's clock domain: its interface's, else its component's.
    static function __fw_rt_obj sig_clock(__fw_rt_obj s);
        if (!s.sclk_done) begin
            s.sclk = clock_of(s);
            s.sclk_done = 1;
        end
        return s.sclk;
    endfunction

    static function __fw_rt_proc mk(__fw_rt_obj o, __fw_rt_pkind_e k, string name);
        __fw_rt_proc p = new;
        p.kind = k;
        p.name = name;
        p.comp = o;
        if (k == __FW_PK_STEP) begin
            p.clk = clock_of(o);
            p.learned = 1;
            foreach (__fw_rt::objs[i])
                if (__fw_rt::objs[i].is_signal() && __fw_rt::objs[i].scope() == o
                    && sig_clock(__fw_rt::objs[i]) != p.clk) p.learned = 0;
        end
        procs.push_back(p);
        return p;
    endfunction

    // Finds every block: components that implement a process interface, by
    // $cast, and the macro blocks. Called by elaborate() after the nets.
    static function void discover();
        foreach (__fw_rt::objs[i]) begin
            __fw_rt_obj o = __fw_rt::objs[i];
            fw_comb_if cb;
            fw_step_if sb;
            fw_run_if rb;
            fw_reset_state_if rsb;
            __fw_rt_proc p;
            if (o.kind != __FW_K_COMPONENT || o.detached) continue;
            if ($cast(cb, o.h)) begin p = mk(o, __FW_PK_COMB, ""); p.cb = cb; end
            if ($cast(sb, o.h)) begin p = mk(o, __FW_PK_STEP, ""); p.sb = sb; end
            if ($cast(rb, o.h)) begin p = mk(o, __FW_PK_RUN, ""); p.rb = rb; end
            if ($cast(rsb, o.h)) begin p = mk(o, __FW_PK_RESET, ""); p.rsb = rsb; end
            foreach (regs[j]) begin
                if (regs[j].comp != o.h) continue;
                if (regs[j].cb != null) begin
                    p = mk(o, __FW_PK_COMB, regs[j].name);
                    p.cb = regs[j].cb;
                end else begin
                    p = mk(o, __FW_PK_STEP, regs[j].name);
                    p.sb = regs[j].sb;
                end
            end
        end
        regs.delete();
    endfunction

    // The running block: cur inside call(), else the run() task of the
    // calling process (run() waits, so cur cannot span it); null for none.
    static function __fw_rt_proc running();
        process s;
        if (cur != null) return cur;
        s = process::self();
        foreach (procs[i])
            if (procs[i].kind == __FW_PK_RUN && procs[i].ph == s) return procs[i];
        return null;
    endfunction

    // A write to h by the running block: learns the net's writer; 0 drops
    // the write (a second writer: FW-E-WRITE-MULTI, once per net).
    // reset_state() writes registers its component's step blocks own, so
    // it is not a writer.
    static function bit wrote(fw_object h);
        __fw_rt_obj o = __fw_rt::impl(h);
        __fw_rt_proc rp = running();
        __fw_rt_net n;
        if (rp == null || o == null || o.net == null || rp.kind == __FW_PK_RESET) return 1;
        n = o.net;
        if (n.writer == null) n.writer = rp;
        else if (n.writer != rp) begin
            if (!n.multi)
                __fw_rt::diag("FW-E-WRITE-MULTI", o.path,
                              {"written by ", n.writer.label(), " and ", rp.label()});
            n.multi = 1;
            return 0;
        end
        return 1;
    endfunction

    // Queues a write: outside a block for __fw_rt_val::update(), from a comb
    // block for update_wires(), from run() for its signal's clock domain's
    // commit, from any other for the end of the call.
    static function void request(fw_object h, __fw_rt_cell c);
        __fw_rt_proc rp = running();
        __fw_rt_obj d;
        if (rp == null) begin
            __fw_rt_val::request(c);
            return;
        end
        if (c.pend) return;
        if (rp.kind == __FW_PK_RUN) begin
            d = __fw_rt::impl(h);
            d = d == null ? null : sig_clock(d);
            if (d == null) __fw_rt_val::request(c);
            else begin
                c.pend = 1;
                d.dpend.push_back(c);
            end
            return;
        end
        c.pend = 1;
        if (rp.kind == __FW_PK_COMB) begin
            wires.push_back(c);
            wobj.push_back(__fw_rt::impl(h));
        end else begin
            calls.push_back(c);
            cobj.push_back(__fw_rt::impl(h));
        end
    endfunction

    static function void step_domains(__fw_rt_proc p, string what);
        if (!p.bad)
            __fw_rt::diag("FW-E-STEP-DOMAINS", p.comp.path,
                          {p.label(), " writes signals of ", what});
        p.bad = 1;
    endfunction

    // A step call's clock domain from what it wrote; 0 if its writes must be
    // dropped (another domain than at's, or two).
    static function bit learn(__fw_rt_proc p, __fw_rt_obj at);
        __fw_rt_obj ds[$];
        foreach (cobj[i]) begin
            __fw_rt_obj d = sig_clock(cobj[i]);
            bit seen = (d == null);
            foreach (ds[j]) if (ds[j] == d) seen = 1;
            if (!seen) ds.push_back(d);
        end
        if (ds.size() > 1) begin
            step_domains(p, {"clocks ", ds[0].path, " and ", ds[1].path});
            return 0;
        end
        if (ds.size() == 0) return 1;
        if (!p.learned) begin
            p.learned = 1;
            p.clk = ds[0];
            return at == null || at == p.clk;
        end
        if (ds[0] != p.clk) begin
            step_domains(p, {"clocks ", p.clk.path, " and ", ds[0].path});
            return 0;
        end
        return 1;
    endfunction

    // Runs block p for an edge of clock domain at (null: no edge, for a
    // test). A step's writes wait for its clk's commit; a reset_state()'s
    // for at's, and only those to signals of at's clock are kept (its
    // part for that domain). Returns 0 if a step's writes were dropped.
    static function bit call(__fw_rt_proc p, __fw_rt_obj at);
        bit ok = 1;
        if (p.bad) return 0;
        calls.delete();
        cobj.delete();
        cur = p;
        case (p.kind)
            __FW_PK_COMB:  p.cb.comb();
            __FW_PK_STEP:  p.sb.step();
            __FW_PK_RESET: p.rsb.reset_state();
            default: ;      // run() is forked by the kernel
        endcase
        cur = null;
        if (p.kind == __FW_PK_STEP) ok = learn(p, at);
        foreach (calls[i]) begin
            __fw_rt_obj d = (p.kind == __FW_PK_STEP) ? p.clk : at;
            if (p.kind == __FW_PK_RESET && at != null && sig_clock(cobj[i]) != at) d = null;
            if (!ok || (p.kind == __FW_PK_RESET && d == null && at != null)) calls[i].drop();
            else if (d == null) begin
                calls[i].pend = 0;
                __fw_rt_val::request(calls[i]);
            end else d.dpend.push_back(calls[i]);
        end
        calls.delete();
        cobj.delete();
        return ok;
    endfunction

    // Makes the comb writes visible; 1 if a wire changed. The signals that
    // changed are left in changed (for FW-E-COMB-LOOP).
    static function bit update_wires();
        changed.delete();
        foreach (wires[i]) if (wires[i].commit()) changed.push_back(wobj[i]);
        wires.delete();
        wobj.delete();
        return changed.size() != 0;
    endfunction

    // Commits clock domain d's register writes; 1 if a value changed.
    static function bit commit(__fw_rt_obj d);
        bit ch = 0;
        foreach (d.dpend[i]) ch |= d.dpend[i].commit();
        d.dpend.delete();
        return ch;
    endfunction
endclass
