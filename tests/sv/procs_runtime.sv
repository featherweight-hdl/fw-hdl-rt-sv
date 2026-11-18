// Processes (processes.md "Register or wire", "Domain of a process"):
// discovery by $cast and by the macros; a comb write is visible after the
// settle's update, a step write after its clock's commit; a second writer is
// FW-E-WRITE-MULTI; a step block learns its clock from what it writes; one
// that writes two clocks is FW-E-STEP-DOMAINS. Blocks are called directly,
// before the edge loop exists.
`include "fw_hdl_macros.svh"

package procs_runtime_pkg;
    import fw_hdl_pkg::*;

    class inc extends fw_component implements fw_comb_if;
        `fw_component_utils(inc)
        fw_input  #(bit [7:0]) a;
        fw_output #(bit [7:0]) y;
        virtual function void build();
            a = fw_input  #(bit [7:0])::create("a", this);
            y = fw_output #(bit [7:0])::create("y", this);
        endfunction
        virtual function void comb();
            y.write(a.read() + 8'd1);
        endfunction
    endclass

    // Two step blocks: one per clock; s1 writes only a field.
    class two extends fw_component;
        `fw_component_utils(two)
        fw_output #(bit [7:0]) o;       // clk
        fw_output #(bit [7:0]) q;       // clk_b
        int n;
        virtual function void build();
            o = fw_output #(bit [7:0])::create("o", this);
            q = fw_output #(bit [7:0])::create("q", this);
            fw_clock_domain::set(q, fw_clock_domain::get(this, "b"));
        endfunction
        `fw_step(s0)
        `fw_step(s1)
        `fw_step(s2)
        function void s0(); o.write(8'h11); endfunction
        function void s1(); n++; endfunction
        function void s2(); q.write(8'h22); endfunction
    endclass

    class both extends fw_component implements fw_step_if, fw_reset_state_if;
        `fw_component_utils(both)
        fw_output #(bit) o0, o1;
        virtual function void build();
            o0 = fw_output #(bit)::create("o0", this);
            o1 = fw_output #(bit)::create("o1", this);
            fw_clock_domain::set(o1, fw_clock_domain::get(this, "b"));
        endfunction
        virtual function void step();
            o0.write(1);
            o1.write(1);
        endfunction
        virtual function void reset_state();
            o0.write(1);
            o1.write(1);
        endfunction
    endclass

    class multi extends fw_component;
        `fw_component_utils(multi)
        fw_output #(bit) x;
        virtual function void build();
            x = fw_output #(bit)::create("x", this);
        endfunction
        `fw_step(st)
        `fw_comb(cb)
        function void st(); x.write(1); endfunction
        function void cb(); x.write(0); endfunction
    endclass

    class top extends fw_component;
        `fw_component_utils(top)
        fw_clock_domain clk, clk_b;
        inc   i;
        two   t;
        both  b;
        multi m;
        virtual function void build();
            clk   = fw_clock_domain::create("clk", this, fw_clock_kind::root(10ns));
            clk_b = fw_clock_domain::create("clk_b", this, fw_clock_kind::root(17ns));
            fw_clock_domain::set(this, clk);
            i = inc::create("i", this);
            t = two::create("t", this);
            b = both::create("b", this);
            m = multi::create("m", this);
            fw_clock_domain::set(t, clk_b, "b");
            fw_clock_domain::set(b, clk_b, "b");
        endfunction
        virtual function void connect();
            i.a.connect(t.o);
        endfunction
    endclass
endpackage

module procs_runtime;
    import fw_hdl_pkg::*;
    import procs_runtime_pkg::*;
    function automatic __fw_rt_proc find(string l);
        foreach (__fw_rt_procs::procs[k]) if (__fw_rt_procs::procs[k].label() == l) return __fw_rt_procs::procs[k];
        return null;
    endfunction
    function automatic string cname(__fw_rt_proc p);
        return p.clk == null ? "-" : p.clk.path;
    endfunction
    initial begin
        top t = top::create("top", null);
        int n = __fw_rt::elaborate(t);
        __fw_rt_obj ck = __fw_rt::impl(t.clk), ckb = __fw_rt::impl(t.clk_b);
        foreach (__fw_rt_procs::procs[k])
            $display("R proc %s %s %s %0d", __fw_rt_procs::procs[k].label(),
                     __fw_rt_procs::procs[k].kind.name(), cname(__fw_rt_procs::procs[k]),
                     __fw_rt_procs::procs[k].learned);
        // step s0 at clk: o waits for clk's commit
        $display("R s0 %0d", __fw_rt_procs::call(find("top.t.s0"), ck));
        $display("R o %h %0d", t.t.o.read(), __fw_rt_procs::commit(ckb));
        $display("R o %h %0d", t.t.o.read(), __fw_rt_procs::commit(ck));
        // comb: visible after the settle's update
        $display("R comb %0d", __fw_rt_procs::call(find("top.i"), null));
        $display("R y %h %0d", t.i.y.read(), __fw_rt_procs::update_wires());
        $display("R y %h", t.i.y.read());
        // s2 first called at clk (tentative): learns clk_b, write dropped
        $display("R s2 %s %0d %s", cname(find("top.t.s2")), __fw_rt_procs::call(find("top.t.s2"), ck),
                 cname(find("top.t.s2")));
        $display("R q %h %0d", t.t.q.read(), __fw_rt_procs::commit(ck));
        $display("R s2 %0d %0d", __fw_rt_procs::call(find("top.t.s2"), ckb), __fw_rt_procs::commit(ckb));
        $display("R q %h", t.t.q.read());
        // s1 writes only a field: stays in the component's clock
        $display("R s1 %0d %s %0d", __fw_rt_procs::call(find("top.t.s1"), ck), cname(find("top.t.s1")), t.t.n);
        // two clocks: STEP-DOMAINS, writes dropped, not called again
        $display("R both %0d %0d", __fw_rt_procs::call(find("top.b"), ck), __fw_rt_procs::commit(ck));
        // reset_state: its part for clk_b only
        foreach (__fw_rt_procs::procs[k])
            if (__fw_rt_procs::procs[k].kind == __FW_PK_RESET) void'(__fw_rt_procs::call(__fw_rt_procs::procs[k], ckb));
        void'(__fw_rt_procs::commit(ckb));
        $display("R rst %b%b", t.b.o0.read(), t.b.o1.read());
        // second writer
        void'(__fw_rt_procs::call(find("top.m.st"), ck));
        void'(__fw_rt_procs::call(find("top.m.cb"), null));
        void'(__fw_rt_procs::call(find("top.m.cb"), null));
        $display("R x %0d %0d", __fw_rt_procs::commit(ck), __fw_rt_procs::update_wires());
        $display("R x %b", t.m.x.read());
        foreach (__fw_rt::diags[i]) $display("D %s %s", __fw_rt::diags[i].id, __fw_rt::diags[i].path);
        $finish;
    end
endmodule
