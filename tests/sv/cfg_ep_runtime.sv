// Configured endpoints at run time: the source's value reaches the sink
// (through a connect_up) on bind, and each push calls the listener.
`include "fw_hdl_macros.svh"

package cfg_ep_runtime_pkg;
    import fw_hdl_pkg::*;

    typedef struct packed {
        int unsigned baud;
        bit [1:0]    stop_bits;
    } cfg_t;

    interface class put_if;
        pure virtual task put(byte b);
    endclass

    class dev extends fw_component;
        `fw_component_utils(dev)
        fw_port_cfg_src #(put_if, cfg_t) p;
        virtual function void build();
            p = fw_port_cfg_src #(put_if, cfg_t)::create("p", this);
            p.set('{baud: 9600, stop_bits: 1});
        endfunction
    endclass

    class xtor extends fw_component implements put_if, fw_cfg_listener_if #(cfg_t);
        `fw_component_utils(xtor)
        fw_export_cfg_sink #(put_if, cfg_t) e;
        int n;
        virtual function void build();
            e = fw_export_cfg_sink #(put_if, cfg_t)::create("e", this);
            e.set_imp(this);
            e.add_listener(this);
        endfunction
        virtual task put(byte b);
        endtask
        virtual function void changed(cfg_t v);
            n++;
        endfunction
    endclass

    class wrap extends fw_component;
        `fw_component_utils(wrap)
        xtor x;
        fw_export_cfg_sink #(put_if, cfg_t) e;
        virtual function void build();
            x = xtor::create("x", this);
            e = fw_export_cfg_sink #(put_if, cfg_t)::create("e", this);
        endfunction
        virtual function void connect();
            x.e.connect_up(e);
        endfunction
    endclass

    class top extends fw_component;
        `fw_component_utils(top)
        dev  d;
        wrap w;
        virtual function void build();
            d = dev::create("d", this);
            w = wrap::create("w", this);
        endfunction
        virtual function void connect();
            d.p.connect(w.e);
        endfunction
    endclass
endpackage

module cfg_ep_runtime;
    import fw_hdl_pkg::*;
    import cfg_ep_runtime_pkg::*;
    initial begin
        top t = top::create("top", null);
        int n = __fw_rt::elaborate(t);
        $display("R bind %0d %0d %0d", n, t.w.x.e.cfg.baud, t.w.x.n);
        t.d.p.set('{baud: 19200, stop_bits: 2});
        $display("R set %0d %0d %0d", t.w.x.e.cfg.baud, t.w.x.n, t.d.p.get().baud);
        foreach (__fw_rt::diags[i]) $display("D %s %s", __fw_rt::diags[i].id, __fw_rt::diags[i].path);
        $finish;
    end
endmodule
