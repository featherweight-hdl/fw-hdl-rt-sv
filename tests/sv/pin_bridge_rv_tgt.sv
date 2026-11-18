// The std rv target transactor (protocol-kit prep §6, Inbound) against an
// RTL initiator through fw_pin_bridge (core-layer2.md §8): the RTL offers
// 1..30 with pseudo-random valid gaps and holds each beat until ready; an
// fw_rv_target passes each beat to a class sink through its port. The sink
// blocks two cycles on every fifth put, so ready drops while it blocks. The
// RTL counts what it sent and the cycles ready was low; the sink checks the
// data and order.
`include "fw_hdl_macros.svh"

package pin_bridge_rv_tgt_pkg;
    import fw_hdl_pkg::*;
    import fw_hdl_std_pkg::*;

    typedef bit [7:0] byte_t;

    // A domain operation names the running component, so the sink blocks
    // its caller through its own run() rather than ticking in put.
    class sink_c extends fw_component implements fw_put_if #(byte_t), fw_run_if;
        `fw_component_utils(sink_c)
        fw_export #(fw_put_if #(byte_t)) e;
        int n_got, bad;
        mailbox #(bit) req = new(1), done = new(1);
        virtual function void build();
            e = fw_export #(fw_put_if #(byte_t))::create("e", this);
        endfunction
        virtual task put(input byte_t d);
            if (d != byte_t'(n_got + 1)) bad++;
            n_got++;
            if (n_got % 5 == 0) begin
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

    class top_c extends fw_component;
        `fw_component_utils(top_c)
        fw_clock_domain                   clk;
        fw_mirror #(fw_rv_if #(byte_t))   inp;
        fw_rv_target #(byte_t)            xt;
        sink_c                            s;
        virtual function void build();
            clk = fw_clock_domain::create("clk", this, fw_clock_kind::root(10ns));
            fw_clock_domain::set(this, clk);
            inp = fw_mirror #(fw_rv_if #(byte_t))::create("inp", this);
            xt  = fw_rv_target #(byte_t)::create("xt", this);
            s   = sink_c::create("s", this);
        endfunction
        virtual function void connect();
            xt.pins.connect_up(inp);
            xt.p.connect(s.e);
        endfunction
    endclass
endpackage

module pin_bridge_rv_tgt;
    import fw_hdl_pkg::*;
    import pin_bridge_rv_tgt_pkg::*;

    bit clk;
    always #5 clk = ~clk;

    bit       valid, ready;
    byte_t    data;
    bit [7:0] lf = 8'h5a;
    int       cyc, sent, stall, low;
    top_c     t;

    fw_pin_bridge #(bit, "top.clk")         b_clk(.i(clk), .o());
    fw_pin_bridge #(bit, "top.inp.valid")   b_v(.i(valid), .o());
    fw_pin_bridge #(byte_t, "top.inp.data") b_d(.i(data), .o());
    fw_pin_bridge #(bit, "top.inp.ready")   b_r(.i(1'b0), .o(ready));

    initial begin
        t = top_c::create("top", null);
        void'(__fw_rt::elaborate(t));
    end

    always @(posedge clk) begin
        cyc++;
        lf <= {lf[6:0], lf[7] ^ lf[5] ^ lf[4] ^ lf[3]};
        if (cyc > 2 && !ready) low++;
        if (valid && ready) sent++;
        if (valid && !ready) stall++;
        if (!valid || ready) begin
            if (sent < 30 && lf[0]) begin
                valid <= 1;
                data  <= byte_t'(sent + 1);
            end else valid <= 0;
        end
        if (cyc == 150) begin
            $display("R sent %0d got %0d bad %0d", sent, t.s.n_got, t.s.bad);
            $display("R ready low %0d stall %0d", low, stall);
            foreach (__fw_rt::diags[i]) $display("D %s %s", __fw_rt::diags[i].id, __fw_rt::diags[i].path);
            $finish;
        end
    end
endmodule
