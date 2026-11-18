// fw_pin_bridge (core-layer2.md §8): an RTL ready/valid source against a
// class comb ready, zero latency. The RTL drives valid, busy and data into
// the top component's inputs; the class comb drives ready = valid && !busy
// and dout = data + 1 back. At each posedge the RTL checks that both already
// reflect this cycle's inputs, and counts the transfers. A bridge to a path
// with no signal is FW-E-PIN-PATH. No edge loop: the class tree has only a
// comb block, settled by the bridges.
`include "fw_hdl_macros.svh"

package pin_bridge_runtime_pkg;
    import fw_hdl_pkg::*;

    class top_c extends fw_component implements fw_comb_if;
        `fw_component_utils(top_c)
        fw_input  #(bit)       valid, busy;
        fw_input  #(bit [7:0]) data;
        fw_output #(bit)       ready;
        fw_output #(bit [7:0]) dout;
        virtual function void build();
            valid = fw_input  #(bit)::create("valid", this);
            busy  = fw_input  #(bit)::create("busy", this);
            data  = fw_input  #(bit [7:0])::create("data", this);
            ready = fw_output #(bit)::create("ready", this);
            dout  = fw_output #(bit [7:0])::create("dout", this);
        endfunction
        virtual function void comb();
            ready.write(valid.read() && !busy.read());
            dout.write(data.read() + 8'd1);
        endfunction
    endclass
endpackage

module pin_bridge_runtime;
    import fw_hdl_pkg::*;
    import pin_bridge_runtime_pkg::*;

    bit clk = 1;
    always #5 clk = ~clk;

    bit       valid, busy, ready;
    bit [7:0] data, dout, nope;
    int       cyc, n, bad, last;

    fw_pin_bridge #(bit, "top.valid")       b_valid(.i(valid), .o());
    fw_pin_bridge #(bit, "top.busy")        b_busy(.i(busy), .o());
    fw_pin_bridge #(bit [7:0], "top.data")  b_data(.i(data), .o());
    fw_pin_bridge #(bit, "top.ready")       b_ready(.i(1'b0), .o(ready));
    fw_pin_bridge #(bit [7:0], "top.dout")  b_dout(.i(8'd0), .o(dout));
    fw_pin_bridge #(bit [7:0], "top.nope")  b_nope(.i(8'd0), .o(nope));

    initial begin
        top_c t = top_c::create("top", null);
        void'(__fw_rt::elaborate(t));
    end

    // The rv source: holds data while valid && !ready; busy is a pattern.
    always @(posedge clk) begin
        cyc++;
        if (ready !== (valid && !busy) || dout !== data + 8'd1) bad++;
        if (valid && ready) begin
            if (data != last) bad++;
            n++;
            last = last + 1;
        end
        if (!valid || ready) begin
            valid <= (cyc % 4 != 3);
            if (valid) data <= data + 8'd1;
        end
        busy <= (cyc % 5 == 2) || (cyc % 7 == 4);
        if (cyc == 40) begin
            $display("R xfers %0d bad %0d", n, bad);
            foreach (__fw_rt::diags[i]) $display("D %s %s", __fw_rt::diags[i].id, __fw_rt::diags[i].path);
            $finish;
        end
    end
endmodule
