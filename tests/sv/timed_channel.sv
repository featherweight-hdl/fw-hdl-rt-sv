// A hand-built timed channel over fw_timed_channel (protocol-kit prep §3.5):
// device a puts bytes through its configured port into the channel, which
// times each one by a's bit time (10 bits per frame) and delivers it to
// device b. Sinking, b's differing bit time sets frame_err; forwarding
// (sinking cleared) delivers as sent. Byte 3 is sent after a's bit time
// doubles (mismatch), byte 4 after b's follows; a's change back during
// byte 4 does not stretch it (sampled at the start). No RTL: the root
// clock's period drives the run (+fw_edges).
`include "fw_hdl_macros.svh"

package timed_channel_pkg;
    import fw_hdl_pkg::*;
    import fw_hdl_std_pkg::*;

    typedef struct packed {
        int unsigned bit_ns;
    } cfg_t;

    typedef struct packed {
        bit       frame_err;
        bit [7:0] data;
    } byte_t;

    interface class put_if;
        pure virtual task put(input byte_t b);
    endclass

    class dev_a extends fw_component implements fw_run_if;
        `fw_component_utils(dev_a)
        fw_port_cfg_src #(put_if, cfg_t) p;
        bit sinking = 1;
        virtual function void build();
            p = fw_port_cfg_src #(put_if, cfg_t)::create("p", this);
            p.set('{bit_ns: 10});
        endfunction
        virtual task run();
            put_if i = p.get_if();
            i.put('{frame_err: 0, data: 1});
            i.put('{frame_err: 0, data: 2});
            p.set('{bit_ns: 20});
            i.put('{frame_err: 0, data: 3});
            fork
                begin
                    fw_time::delay(50ns);
                    p.set('{bit_ns: 10});
                end
            join_none
            i.put('{frame_err: 0, data: 4});
            sinking = 0;
            i.put('{frame_err: 0, data: 5});
        endtask
    endclass

    class dev_b extends fw_component implements put_if;
        `fw_component_utils(dev_b)
        fw_export_cfg_src #(put_if, cfg_t) e;
        string got[$];
        virtual function void build();
            e = fw_export_cfg_src #(put_if, cfg_t)::create("e", this);
            e.set_imp(this);
            e.set('{bit_ns: 10});
        endfunction
        virtual task put(input byte_t b);
            string err = "";
            if (b.frame_err) err = "!";
            got.push_back($sformatf("%0d%s@%0d", b.data, err, int'(fw_time::now() / 1ns)));
            if (b.data == 3) e.set('{bit_ns: 20});
        endtask
    endclass

    class chan extends fw_timed_channel #(cfg_t, byte_t) implements put_if;
        `fw_component_utils(chan)
        fw_export_cfg_sink #(put_if, cfg_t) a;
        fw_port_cfg_sink #(put_if, cfg_t)   b;
        dev_a src;      // to read src.sinking
        virtual function void build();
            a = fw_export_cfg_sink #(put_if, cfg_t)::create("a", this);
            b = fw_port_cfg_sink #(put_if, cfg_t)::create("b", this);
            a.set_imp(this);
        endfunction
        virtual function time xfer_time(cfg_t cfg, byte_t t);
            return 10 * cfg.bit_ns * 1ns;
        endfunction
        virtual function byte_t mismatch(cfg_t tx_cfg, cfg_t rx_cfg, byte_t t);
            if (tx_cfg.bit_ns != rx_cfg.bit_ns) t.frame_err = 1;
            return t;
        endfunction
        virtual task put(input byte_t t);
            byte_t rx = t;
            if (src.sinking) xfer_sink(a.cfg, b.cfg, t, rx);
            else xfer_fwd(a.cfg, t);
            b.get_if().put(rx);
        endtask
    endclass

    class top_c extends fw_component;
        `fw_component_utils(top_c)
        fw_clock_domain clk;
        dev_a da;
        chan  c;
        dev_b db;
        virtual function void build();
            clk = fw_clock_domain::create("clk", this, fw_clock_kind::root(10ns));
            fw_clock_domain::set(this, clk);
            da = dev_a::create("da", this);
            c  = chan::create("c", this);
            db = dev_b::create("db", this);
        endfunction
        virtual function void connect();
            da.p.connect(c.a);
            c.b.connect(db.e);
            c.src = da;
        endfunction
    endclass
endpackage

module timed_channel;
    import fw_hdl_pkg::*;
    import timed_channel_pkg::*;

    top_c t;

    initial begin
        string s;
        int nerr;
        t = top_c::create("top", null);
        nerr = __fw_rt::elaborate(t);
        if (nerr == 0) __fw_rt_kern::run();
        s = "";
        foreach (t.db.got[i]) s = {s, " ", t.db.got[i]};
        $display("R got%s", s);
        foreach (__fw_rt::diags[i]) $display("D %s %s", __fw_rt::diags[i].id, __fw_rt::diags[i].path);
        $finish;
    end
endmodule
