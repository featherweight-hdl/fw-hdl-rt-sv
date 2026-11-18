// A configured source connected to a configured source: connect() takes
// only the opposite role, so this must not compile.
`include "fw_hdl_macros.svh"

package cfg_ep_bad_pkg;
    import fw_hdl_pkg::*;

    interface class put_if;
        pure virtual task put(byte b);
    endclass

    class top extends fw_component;
        `fw_component_utils(top)
        fw_port_cfg_src #(put_if, int) a;
        fw_export_cfg_src #(put_if, int) b;
        virtual function void build();
            a = fw_port_cfg_src #(put_if, int)::create("a", this);
            b = fw_export_cfg_src #(put_if, int)::create("b", this);
        endfunction
        virtual function void connect();
            a.connect(b);
        endfunction
    endclass
endpackage

module cfg_ep_bad;
    import fw_hdl_pkg::*;
    import cfg_ep_bad_pkg::*;
    initial begin
        top t = top::create("top", null);
        void'(__fw_rt::elaborate(t));
        $finish;
    end
endmodule
