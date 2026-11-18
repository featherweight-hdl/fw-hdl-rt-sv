// Signal values (processes.md "Signal values"): a write is pending until the
// update; a net has one value; a tie reads as its constant; a write to an
// input is FW-E-WRITE-IN and ignored; the last write before the update wins.
`include "fw_hdl_macros.svh"

package values_runtime_pkg;
    import fw_hdl_pkg::*;

    class child extends fw_component;
        `fw_component_utils(child)
        fw_output #(bit [7:0]) o;
        fw_input  #(bit [7:0]) i;
        virtual function void build();
            o = fw_output #(bit [7:0])::create("o", this);
            i = fw_input  #(bit [7:0])::create("i", this);
        endfunction
    endclass

    class top extends fw_component;
        `fw_component_utils(top)
        child                   c;
        fw_signal #(bit [7:0])  s;
        fw_signal #(bit [11:0]) t;
        virtual function void build();
            c = child::create("c", this);
            s = fw_signal #(bit [7:0])::create("s", this);
            t = fw_signal #(bit [11:0])::create("t", this);
        endfunction
        virtual function void connect();
            s.connect(c.o);
            c.i.connect(s);
            t.tie(12'h5a3);
        endfunction
    endclass
endpackage

module values_runtime;
    import fw_hdl_pkg::*;
    import values_runtime_pkg::*;
    initial begin
        top t = top::create("top", null);
        int n = __fw_rt::elaborate(t);
        $display("R elab %0d", n);
        t.c.o.write(8'h11);
        t.c.o.write(8'hab);
        $display("R pending %h %h %0d", t.c.o.read(), t.s.read(), __fw_rt_val::pending.size());
        $display("R update %0d", __fw_rt_val::update());
        $display("R net %h %h %h", t.c.o.read(), t.s.read(), t.c.i.read());
        $display("R again %0d", __fw_rt_val::update());
        $display("R tie %h", t.t.read());
        t.c.i.write(8'h00);
        void'(__fw_rt_val::update());
        $display("R in %h", t.c.i.read());
        foreach (__fw_rt::diags[i]) $display("D %s %s", __fw_rt::diags[i].id, __fw_rt::diags[i].path);
        $finish;
    end
endmodule
