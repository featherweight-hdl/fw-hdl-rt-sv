// fw_rt_kern.svh: the edge loop (layer 2, semantics/processes.md "The edge").
// Root clock domains with a `period` and no driver are ticked here; derived
// ones from their source (period * div / mul). At each edge of a clock
// domain: commit its register writes, settle the comb blocks, run its step
// blocks (or reset_state() while a block's reset is asserted), then resume
// the run() tasks waiting on it: each run() is forked at the start of run()
// and waits on edge_ev, raised after the edges at one time.
//
// Settle runs every comb block in every settle (not only the ones that read
// the domain's signals): the result is the same, at some cost.
//
// A run is asked for with +fw_edges=<n> (edges of +fw_trace_clock=<path>,
// default "top.clk"); +fw_trace=<file> writes, per edge, the values of the
// signals in +fw_trace_sigs=<path>,<path>,... after the settle.

class __fw_rt_kern;
    static bit           stop;          // a run-stopping error was reported
    static __fw_rt_obj   tclk;          // the trace clock
    static __fw_rt_obj   tsigs[$];
    static string        tnames[$];
    static string        rows[$];
    static int           nedges;        // edges of tclk so far
    static event         edge_ev;       // raised after the edges at one time
    static event         settled;       // raised after each settle (fw_pin_bridge)

    static function bit is_clock(__fw_rt_obj o);
        return o != null && o.kind == __FW_K_DOMAIN && !o.detached
            && o.dkind == fw_clock_kind::get_type();
    endfunction

    // A clock domain's period: its root's `period`, through div/mul of each
    // derivation; 0 for none (driven clocks are not ticked by rt-sv yet).
    static function time period(__fw_rt_obj c);
        __fw_rt_held #(fw_clock_kind::params_t) h;
        __fw_rt_obj src;
        time t;
        if (c == null || !$cast(h, c.dheld) || c.drv_keys.size() != 0) return 0;
        if (h.v.deriv == fw_clock_kind::ROOT) return h.v.period;
        if (h.v.from.size() == 0) return 0;
        src = __fw_rt::impl(h.v.from[0]);
        t = period(src);
        if (h.v.deriv == fw_clock_kind::DERIVED && h.v.mul != 0) t = t * h.v.div / h.v.mul;
        return t;
    endfunction

    // 1 while reset domain r is asserted: its driver's value against the
    // driver's polarity; a derived reset follows its source.
    static function bit asserted(__fw_rt_obj r);
        __fw_rt_net n;
        if (r == null) return 0;
        if (r.dsig == null) return r.dfrom.size() != 0 && asserted(r.dfrom[0]);
        n = r.dsig.net;
        if (n == null || n.val == null) return r.dlow;  // the type default, 0
        return (n.val.ival() == "0") == r.dlow;
    endfunction

    static function __fw_rt_obj reset_of(__fw_rt_obj o);
        return __fw_rt_dom::get(o, fw_reset_kind::get_type().name(), "", 0);
    endfunction

    // Settles the comb blocks: whole passes until no wire changes; after 64,
    // FW-E-COMB-LOOP on each signal changed in the last pass.
    static function void settle();
        for (int pass = 0; pass < 64; pass++) begin
            foreach (__fw_rt_procs::procs[i])
                if (__fw_rt_procs::procs[i].kind == __FW_PK_COMB)
                    void'(__fw_rt_procs::call(__fw_rt_procs::procs[i], null));
            if (!__fw_rt_procs::update_wires()) begin
                ->settled;
                return;
            end
        end
        foreach (__fw_rt_procs::changed[i])
            __fw_rt::diag("FW-E-COMB-LOOP", __fw_rt_procs::changed[i].path,
                          "comb blocks still change after 64 passes");
        stop = 1;
        ->settled;
    endfunction

    // fw_pin_bridge (core-layer2.md §8): the signal or clock domain at path;
    // null after FW-E-PIN-PATH on path if there is none.
    static function __fw_rt_obj pin_sig(string path);
        foreach (__fw_rt::objs[i])
            if (__fw_rt::objs[i].path == path && (is_clock(__fw_rt::objs[i])
                || __fw_rt::objs[i].is_signal() && __fw_rt::objs[i].net != null))
                return __fw_rt::objs[i];
        __fw_rt::diag("FW-E-PIN-PATH", path, "fw_pin_bridge: no signal at this path");
        return null;
    endfunction

    // 1 if the RTL drives s: s is an effective input port of the top
    // component. Otherwise the class tree drives the pin.
    static function bit pin_in(__fw_rt_obj s);
        return s.kind == __FW_K_PORT && s.scope() == __fw_rt::top
            && s.eff_dir() == __FW_D_IN;
    endfunction

    // An RTL pin wrote input cell c: visible at once, then settle, so a
    // comb that reads it updates in the same time step.
    static function void pin_write(__fw_rt_cell c);
        if (c.commit() && !stop) settle();
    endfunction

    // Clock domains whose edges an RTL clock drives (fw_pin_bridge); the
    // edge loop does not tick them.
    static bit pin_clks[__fw_rt_obj];

    // An RTL clock pin's posedge, for clock domain dom: the edge's step
    // blocks (edge_of), as at an edge of the loop.
    static function void pin_edge(__fw_rt_obj dom);
        if (stop) return;
        edge_of(dom);
        ->edge_ev;
    endfunction

    // After the NBA region of that posedge: commit dom's register writes and
    // settle, so the registers (and the comb blocks that read them) change
    // after the RTL flops sampled, as RTL flops do. edge_of's own commit at
    // the next edge then finds nothing. It settles even when no register
    // changed: a step that wrote only component state (a field a comb block
    // reads) changes the comb outputs too.
    static function void pin_commit(__fw_rt_obj dom);
        if (stop) return;
        void'(__fw_rt_procs::commit(dom));
        void'(__fw_rt_val::update());
        settle();
    endfunction

    // A bridge starts: the first one settles the comb blocks once, so the
    // pins show their values before any input changes.
    static bit pin_started;
    static function void pin_start();
        if (pin_started || stop) return;
        pin_started = 1;
        settle();
    endfunction

    static function void sample();
        string r = "[";
        foreach (tsigs[i]) begin
            string v = "0";
            if (tsigs[i] != null && tsigs[i].net != null && tsigs[i].net.val != null)
                v = tsigs[i].net.val.ival();
            r = {r, i ? ", " : "", v};
        end
        rows.push_back({r, "]"});
    endfunction

    // One edge of clock domain dom.
    static function void edge_of(__fw_rt_obj dom);
        void'(__fw_rt_procs::commit(dom));
        void'(__fw_rt_val::update());
        settle();
        if (stop) return;
        if (dom == tclk) begin
            nedges++;
            if (tnames.size() != 0) sample();
        end
        foreach (__fw_rt_procs::procs[i]) begin
            __fw_rt_proc p = __fw_rt_procs::procs[i];
            __fw_rt_obj r = reset_of(p.comp);
            if (p.kind == __FW_PK_RESET && asserted(r)) void'(__fw_rt_procs::call(p, dom));
            else if (p.kind == __FW_PK_STEP && p.clk == dom && !(has_reset_state(p.comp) && asserted(r)))
                void'(__fw_rt_procs::call(p, dom));
        end
        dom.dedges++;
    endfunction

    // 0 after FW-E-DOM-KIND on obj if an operation for kind want is used on k.
    static function bit kind_ok(fw_object obj, fw_domain_kind_type k,
                                fw_domain_kind_type want, string op);
        __fw_rt_obj o = __fw_rt::impl(obj);
        if (k == want) return 1;
        __fw_rt::diag("FW-E-DOM-KIND", o == null ? "" : o.path,
                      {op, " on a domain that is not a ", want.name(), " domain"});
        return 0;
    endfunction

    // The domain of kind k a domain operation's obj resolves to; null after
    // FW-E-DOM-OBJ (obj not of the calling run()'s component) or
    // FW-E-DOM-NONE, each on obj.
    static function __fw_rt_obj dom_op(fw_object obj, fw_domain_kind_type k, string op);
        __fw_rt_obj o = __fw_rt::impl(obj);
        __fw_rt_proc rp = __fw_rt_procs::running();
        __fw_rt_obj c, d;
        if (o == null) return null;
        c = o.kind == __FW_K_COMPONENT ? o : o.scope();
        if (rp != null && c != rp.comp) begin
            __fw_rt::diag("FW-E-DOM-OBJ", o.path, {op, " on an object of another component"});
            return null;
        end
        d = __fw_rt_dom::get(o, k.name(), "", 0);
        if (d == null) __fw_rt::diag("FW-E-DOM-NONE", o.path, {op, ": no ", k.name(), " domain"});
        return d;
    endfunction

    // Waits for n edges of clock domain d; FW-E-CLOCK-NONE on obj (and the
    // caller waits for ever) if d has no edges.
    static task tick(__fw_rt_obj d, string path, int n);
        int want = d.dedges + n;
        if (period(d) == 0 && !pin_clks.exists(d)) begin
            __fw_rt::diag("FW-E-CLOCK-NONE", path, {"tick on ", d.path, ", which has no edges"});
            stop = 1;
            @(edge_ev);     // never: the run stops
        end
        while (d.dedges < want) @(edge_ev);
    endtask

    // Waits until reset domain r is deasserted (at once if it is) or, for
    // asserted, asserted at a later edge. Checked after any clock's edges
    // (a guess: the reset's own clock would do).
    static task wait_reset(__fw_rt_obj r, bit want);
        if (!want && !asserted(r)) return;
        do @(edge_ev); while (asserted(r) != want);
    endtask

    static function bit has_reset_state(__fw_rt_obj c);
        foreach (__fw_rt_procs::procs[i])
            if (__fw_rt_procs::procs[i].comp == c && __fw_rt_procs::procs[i].kind == __FW_PK_RESET)
                return 1;
        return 0;
    endfunction

    // Forks the run() tasks, once: from run() or from the first clock bridge.
    static bit runs_started;
    static task start_runs();
        if (runs_started || stop) return;
        runs_started = 1;
        foreach (__fw_rt_procs::procs[i])
            if (__fw_rt_procs::procs[i].kind == __FW_PK_RUN) begin
                automatic __fw_rt_proc p = __fw_rt_procs::procs[i];
                fork
                    begin
                        p.ph = process::self();
                        p.rb.run();
                    end
                join_none
            end
    endtask

    // Runs the edge loop until +fw_edges edges of the trace clock, or a
    // run-stopping error. Writes +fw_trace when given.
    static task run();
        int want;
        string tc = "top.clk", ts, tf;
        __fw_rt_obj cl[$];
        __fw_rt_obj byp[string];
        time per[$], nxt[$];
        if (!$value$plusargs("fw_edges=%d", want)) return;
        void'($value$plusargs("fw_trace_clock=%s", tc));
        if ($value$plusargs("fw_trace_sigs=%s", ts)) begin
            int s = 0;
            for (int i = 0; i <= ts.len(); i++)
                if (i == ts.len() || ts[i] == ",") begin
                    if (i > s) tnames.push_back(ts.substr(s, i - 1));
                    s = i + 1;
                end
        end
        foreach (__fw_rt::objs[i]) begin
            __fw_rt_obj o = __fw_rt::objs[i];
            if (o.is_signal()) byp[o.path] = o;
            if (o.path == tc && is_clock(o)) tclk = o;
            if (is_clock(o) && period(o) > 0 && !pin_clks.exists(o)) begin
                cl.push_back(o);
                per.push_back(period(o));
                nxt.push_back(period(o));
            end
        end
        foreach (tnames[j]) tsigs.push_back(byp.exists(tnames[j]) ? byp[tnames[j]] : null);
        start_runs();
        while (!stop && nedges < want && tclk != null && cl.size() != 0) begin
            time t = nxt[0];
            foreach (nxt[i]) if (nxt[i] < t) t = nxt[i];
            #(t - $time);
            foreach (cl[i])
                if (!stop && nxt[i] == t) begin
                    edge_of(cl[i]);
                    nxt[i] += per[i];
                end
            ->edge_ev;
        end
        if ($value$plusargs("fw_trace=%s", tf)) begin
            int fd = $fopen(tf, "w");
            $fwrite(fd, "{\"clock\": %s, \"edges\": %0d, \"signals\": [",
                    __fw_rt_str::jstr(tc), nedges);
            foreach (tnames[i]) $fwrite(fd, "%s%s", i ? ", " : "", __fw_rt_str::jstr(tnames[i]));
            $fwrite(fd, "], \"rows\": [");
            foreach (rows[i]) $fwrite(fd, "%s%s", i ? ", " : "", rows[i]);
            $fwrite(fd, "]}\n");
            $fclose(fd);
        end
    endtask
endclass
