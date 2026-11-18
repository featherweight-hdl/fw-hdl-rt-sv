// The std zero-latency rv transactor and monitor (protocol-kit prep §6)
// against an RTL target through fw_pin_bridge (core-layer2.md §8): the
// class clock is the RTL clock; a class run() puts 1..N through
// fw_rv_initiator; an RTL target takes them with a stalling comb ready. The
// RTL checks the data, that valid never drops between puts (back-to-back,
// no FIFO) and that each put takes one cycle plus the cycles ready was low;
// an fw_rv_monitor on the link counts pre/post calls and checks the data.
`include "fw_hdl_macros.svh"

package pin_bridge_rv_pkg;
    import fw_hdl_pkg::*;
    import fw_hdl_std_pkg::*;

    typedef bit [7:0] byte_t;

    class mon_c extends fw_rv_monitor #(byte_t);
        `fw_component_utils(mon_c)
        int n_pre, n_post, bad;
        virtual function void pre(byte_t d);
            if (d != byte_t'(n_pre + 1)) bad++;
            n_pre++;
        endfunction
        virtual function void post(byte_t d);
            if (d != byte_t'(n_post + 1)) bad++;
            n_post++;
        endfunction
    endclass

    class top_c extends fw_component implements fw_run_if;
        `fw_component_utils(top_c)
        fw_clock_domain                   clk;
        fw_bundle #(fw_rv_if #(byte_t))   out;
        fw_rv_initiator #(byte_t)         xi;
        mon_c                             m;
        int                               n_done;
        virtual function void build();
            clk = fw_clock_domain::create("clk", this, fw_clock_kind::root(10ns));
            fw_clock_domain::set(this, clk);
            out = fw_bundle #(fw_rv_if #(byte_t))::create("out", this);
            xi  = fw_rv_initiator #(byte_t)::create("xi", this);
            m   = mon_c::create("m", this);
        endfunction
        virtual function void connect();
            xi.pins.connect_up(out);
            m.p.connect(xi.pins);
        endfunction
        virtual task run();
            for (int i = 1; i <= 20; i++) begin
                xi.put(byte_t'(i));
                n_done++;
            end
        endtask
    endclass
endpackage

module pin_bridge_rv;
    import fw_hdl_pkg::*;
    import pin_bridge_rv_pkg::*;

    bit clk;
    always #5 clk = ~clk;

    bit       valid, ready;
    byte_t    data;
    bit [3:0] rc;                          // RTL stall pattern
    int       cyc, got, first, last, stall, drops, bad;
    top_c     t;

    assign ready = (rc != 4'd3) && (rc != 4'd7) && (rc != 4'd8);

    fw_pin_bridge #(bit, "top.clk")         b_clk(.i(clk), .o());
    fw_pin_bridge #(bit, "top.out.valid")   b_v(.i(1'b0), .o(valid));
    fw_pin_bridge #(byte_t, "top.out.data") b_d(.i(8'd0), .o(data));
    fw_pin_bridge #(bit, "top.out.ready")   b_r(.i(ready), .o());

    initial begin
        t = top_c::create("top", null);
        void'(__fw_rt::elaborate(t));
    end

    always @(posedge clk) begin
        cyc++;
        rc <= rc + 4'd1;
        if (valid) begin
            if (got == 0 && first == 0) first = cyc;
            if (!ready) stall++;
            else begin
                if (data != byte_t'(got + 1)) bad++;
                got++;
                last = cyc;
            end
        end else if (got > 0 && got < 20) drops++;
        if (cyc == 40) begin
            // 20 puts in 20 cycles plus the stalls, valid high throughout
            $display("R got %0d span %0d stall %0d drops %0d bad %0d", got,
                     last - first + 1, stall, drops, bad);
            $display("R done %0d mon %0d %0d bad %0d", t.n_done, t.m.n_pre, t.m.n_post, t.m.bad);
            foreach (__fw_rt::diags[i]) $display("D %s %s", __fw_rt::diags[i].id, __fw_rt::diags[i].path);
            $finish;
        end
    end
endmodule
