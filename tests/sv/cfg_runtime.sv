// Configuration at run time (protocols.md "Configuration"): a set() before
// bind reaches the consumer, a set() after bind is pushed, and a client
// write to a consumer's copy is FW-E-CFG-WRITE at the next push.
`include "fw_hdl_macros.svh"

package cfg_runtime_pkg;
    import fw_hdl_pkg::*;

    typedef struct packed {
        int unsigned baud;
        bit [1:0]    stop_bits;
    } cfg_t;

    class owner extends fw_component;
        `fw_component_utils(owner)
        fw_cfg_src #(cfg_t) p;
        virtual function void build();
            p = fw_cfg_src #(cfg_t)::create("p", this);
            p.set('{baud: 9600, stop_bits: 1});
        endfunction
    endclass

    class reader extends fw_component;
        `fw_component_utils(reader)
        fw_cfg_sink #(cfg_t) c;
        virtual function void build();
            c = fw_cfg_sink #(cfg_t)::create("c", this);
        endfunction
    endclass

    class top extends fw_component;
        `fw_component_utils(top)
        owner  o;
        reader r;
        virtual function void build();
            o = owner::create("o", this);
            r = reader::create("r", this);
        endfunction
        virtual function void connect();
            r.c.connect(o.p);
        endfunction
    endclass
endpackage

module cfg_runtime;
    import fw_hdl_pkg::*;
    import cfg_runtime_pkg::*;
    initial begin
        top t = top::create("top", null);
        int n = __fw_rt::elaborate(t);
        $display("R bind %0d %0d", n, t.r.c.cfg.baud);
        t.o.p.set('{baud: 19200, stop_bits: 2});
        $display("R set %0d %0d %0d", t.r.c.cfg.baud, t.r.c.cfg.stop_bits, t.o.p.get().baud);
        $display("R ndiag %0d", __fw_rt::diags.size());
        t.r.c.cfg.baud = 1;
        t.o.p.set('{baud: 38400, stop_bits: 1});
        $display("R write %0d", t.r.c.cfg.baud);
        foreach (__fw_rt::diags[i]) $display("D %s %s", __fw_rt::diags[i].id, __fw_rt::diags[i].path);
        $finish;
    end
endmodule
