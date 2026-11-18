// fw_pin_bridge (core-layer2.md §8) on a clock domain: the RTL clock drives
// the class clock's edges. A class step counter (a register) is read by an
// RTL flop; an RTL counter flop is read by a class step; a class comb reads
// the counter. Beside them runs the same design in RTL (m*); at each posedge
// and negedge the RTL checks that the class side shows the same values:
// register writes change in the posedge's time step, after its NBA region,
// so the edges number as in all-RTL.
`include "fw_hdl_macros.svh"

package pin_bridge_clock_pkg;
    import fw_hdl_pkg::*;

    class top_c extends fw_component implements fw_step_if, fw_comb_if;
        `fw_component_utils(top_c)
        fw_clock_domain        clk;
        fw_input  #(bit [7:0]) rin;
        fw_output #(bit [7:0]) cnt, seen, cnt1;
        virtual function void build();
            clk  = fw_clock_domain::create("clk", this, fw_clock_kind::root(10ns));
            fw_clock_domain::set(this, clk);
            rin  = fw_input  #(bit [7:0])::create("rin", this);
            cnt  = fw_output #(bit [7:0])::create("cnt", this);
            seen = fw_output #(bit [7:0])::create("seen", this);
            cnt1 = fw_output #(bit [7:0])::create("cnt1", this);
        endfunction
        virtual function void step();
            cnt.write(cnt.read() + 8'd1);
            seen.write(rin.read());
        endfunction
        virtual function void comb();
            cnt1.write(cnt.read() + 8'd1);
        endfunction
    endclass
endpackage

module pin_bridge_clock;
    import fw_hdl_pkg::*;
    import pin_bridge_clock_pkg::*;

    bit clk;
    always #5 clk = ~clk;

    bit [7:0] cnt, seen, cnt1, rc, rq;     // class pins; RTL flops
    bit [7:0] mcnt, mseen, mrq;            // the all-RTL model
    int       cyc, bad;

    fw_pin_bridge #(bit, "top.clk")         b_clk(.i(clk), .o());
    fw_pin_bridge #(bit [7:0], "top.rin")   b_rin(.i(rc), .o());
    fw_pin_bridge #(bit [7:0], "top.cnt")   b_cnt(.i(8'd0), .o(cnt));
    fw_pin_bridge #(bit [7:0], "top.seen")  b_seen(.i(8'd0), .o(seen));
    fw_pin_bridge #(bit [7:0], "top.cnt1")  b_cnt1(.i(8'd0), .o(cnt1));

    initial begin
        top_c t = top_c::create("top", null);
        void'(__fw_rt::elaborate(t));
    end

    always @(negedge clk)
        if (cnt !== mcnt || seen !== mseen || cnt1 !== mcnt + 8'd1 || rq !== mrq) bad++;

    always @(posedge clk) begin
        cyc++;
        if (cnt !== mcnt || seen !== mseen || cnt1 !== mcnt + 8'd1 || rq !== mrq) bad++;
        rc    <= rc + 8'd3;         // RTL flop read by the class step
        rq    <= cnt;               // RTL flop reading the class register
        mcnt  <= mcnt + 8'd1;
        mseen <= rc;
        mrq   <= mcnt;
        if (cyc == 30) begin
            $display("R cyc %0d cnt %0d seen %0d rq %0d bad %0d", cyc, cnt, seen, rq, bad);
            foreach (__fw_rt::diags[i]) $display("D %s %s", __fw_rt::diags[i].id, __fw_rt::diags[i].path);
            $finish;
        end
    end
endmodule
