// Class-level back-to-back ready/valid (protocol-kit prep §6): a source puts
// 1..8 through its port into an fw_rv_initiator, whose pins connect straight
// to an fw_rv_target; the target puts each beat into a sink, which blocks
// two cycles on beat 4 (ready drops, beat 5 stalls) and otherwise returns at
// once (one beat per cycle). An fw_rv_monitor taps the link: as a listener
// it logs each pre/post call in order, and as a transaction recorder it
// keeps one entry per transfer (data@first-handshake cycle). No RTL: the root clock's `period` drives the run (+fw_edges).
`include "fw_hdl_macros.svh"

package rv_b2b_pkg;
    import fw_hdl_pkg::*;
    import fw_hdl_std_pkg::*;

    typedef bit [7:0] byte_t;

    function automatic int cyc();
        return int'($time / 10ns);
    endfunction

    class src_c extends fw_component implements fw_run_if;
        `fw_component_utils(src_c)
        fw_port #(fw_put_if #(byte_t)) p;
        int n_done;
        virtual function void build();
            p = fw_port #(fw_put_if #(byte_t))::create("p", this);
        endfunction
        virtual task run();
            fw_put_if #(byte_t) i = p.get_if();
            for (int k = 1; k <= 8; k++) begin
                i.put(byte_t'(k));
                n_done++;
            end
        endtask
    endclass

    // A domain operation names the running component, so the sink blocks
    // its caller through its own run().
    class sink_c extends fw_component implements fw_put_if #(byte_t), fw_run_if;
        `fw_component_utils(sink_c)
        fw_export #(fw_put_if #(byte_t)) e;
        int at[$];
        byte_t got[$];
        mailbox #(bit) req = new(1), done = new(1);
        virtual function void build();
            e = fw_export #(fw_put_if #(byte_t))::create("e", this);
        endfunction
        virtual task put(input byte_t d);
            got.push_back(d);
            at.push_back(cyc());
            if (d == 4) begin
                bit b;
                req.put(1);
                done.get(b);
            end
        endtask
        virtual task run();
            bit b;
            forever begin
                req.get(b);
                repeat (2) fw_clock_domain::tick(this);
                done.put(1);
            end
        endtask
    endclass

    class mon_c extends fw_rv_monitor #(byte_t);
        `fw_component_utils(mon_c)
        string log[$];          // the listener: pre/post calls in order
        string txns[$];         // the recorder: one entry per transfer
        int start;
        virtual function void pre(byte_t d);
            log.push_back($sformatf("pre %0d", d));
            start = cyc();
        endfunction
        virtual function void post(byte_t d);
            log.push_back($sformatf("post %0d", d));
            txns.push_back($sformatf("%0d@%0d-%0d", d, start, cyc()));
        endfunction
    endclass

    class top_c extends fw_component;
        `fw_component_utils(top_c)
        fw_clock_domain             clk;
        src_c                       s;
        fw_rv_initiator #(byte_t)   xi;
        fw_rv_target #(byte_t)      xt;
        sink_c                      k;
        mon_c                       m;
        virtual function void build();
            clk = fw_clock_domain::create("clk", this, fw_clock_kind::root(10ns));
            fw_clock_domain::set(this, clk);
            s  = src_c::create("s", this);
            xi = fw_rv_initiator #(byte_t)::create("xi", this);
            xt = fw_rv_target #(byte_t)::create("xt", this);
            k  = sink_c::create("k", this);
            m  = mon_c::create("m", this);
        endfunction
        virtual function void connect();
            s.p.connect(xi.t);
            xi.pins.connect(xt.pins);
            xt.p.connect(k.e);
            m.p.connect(xi.pins);
        endfunction
    endclass
endpackage

module rv_b2b;
    import fw_hdl_pkg::*;
    import rv_b2b_pkg::*;

    top_c t;

    initial begin
        string s;
        int nerr;
        t = top_c::create("top", null);
        nerr = __fw_rt::elaborate(t);
        if (nerr == 0) __fw_rt_kern::run();
        $display("R done %0d got %0d", t.s.n_done, t.k.got.size());
        s = "";
        foreach (t.k.got[i]) s = {s, $sformatf(" %0d@%0d", t.k.got[i], t.k.at[i])};
        $display("R sink%s", s);
        s = "";
        foreach (t.m.log[i]) s = {s, " ", t.m.log[i]};
        $display("R log%s", s);
        s = "";
        foreach (t.m.txns[i]) s = {s, " ", t.m.txns[i]};
        $display("R txns%s", s);
        foreach (__fw_rt::diags[i]) $display("D %s %s", __fw_rt::diags[i].id, __fw_rt::diags[i].path);
        $finish;
    end
endmodule
