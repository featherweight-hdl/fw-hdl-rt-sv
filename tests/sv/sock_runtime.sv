// A socket pair (K9.M2): fw_socket #(OUT, IN) connects to its mirror image
// fw_socket #(IN, OUT), linked both ways. Each side's get_if() reaches the
// peer's IN implementation, across a connect_up chain on one side; an
// unconnected socket is reported unbound.
`include "fw_hdl_macros.svh"

package sock_runtime_pkg;
    import fw_hdl_pkg::*;

    interface class req_if;
        pure virtual function int req(int x);
    endclass
    interface class rsp_if;
        pure virtual function void rsp(int x);
    endclass

    // The requester: sends req, takes rsp.
    class host extends fw_component implements rsp_if;
        `fw_component_utils(host)
        fw_socket #(req_if, rsp_if) s;
        int got;
        virtual function void build();
            s = fw_socket #(req_if, rsp_if)::create("s", this);
        endfunction
        virtual function void rsp(int x);
            got = x;
        endfunction
    endclass

    // The responder: serves req, answers through its own OUT side.
    class dev extends fw_component implements req_if;
        `fw_component_utils(dev)
        fw_socket #(rsp_if, req_if) s;
        virtual function void build();
            s = fw_socket #(rsp_if, req_if)::create("s", this);
        endfunction
        virtual function int req(int x);
            s.get_if().rsp(x + 100);
            return 2 * x;
        endfunction
    endclass

    // Forwards its inner dev's socket outward.
    class wrap extends fw_component;
        `fw_component_utils(wrap)
        fw_socket #(rsp_if, req_if) s;
        dev d;
        virtual function void build();
            s = fw_socket #(rsp_if, req_if)::create("s", this);
            d = dev::create("d", this);
        endfunction
        virtual function void connect();
            d.s.connect_up(s);
        endfunction
    endclass

    class top extends fw_component;
        `fw_component_utils(top)
        host h, lone;
        wrap w;
        virtual function void build();
            h = host::create("h", this);
            lone = host::create("lone", this);
            w = wrap::create("w", this);
        endfunction
        virtual function void connect();
            h.s.connect(w.s);
        endfunction
    endclass
endpackage

module sock_runtime;
    import fw_hdl_pkg::*;
    import sock_runtime_pkg::*;
    initial begin
        top t = top::create("top", null);
        void'(__fw_rt::elaborate(t));
        $display("R req %0d got %0d", t.h.s.get_if().req(5), t.h.got);
        foreach (__fw_rt::diags[i]) $display("D %s %s", __fw_rt::diags[i].id, __fw_rt::diags[i].path);
        $finish;
    end
endmodule
