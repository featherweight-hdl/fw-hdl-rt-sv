// Two class UART models joined by the test UART's sinking kit channel
// uart_txrx_chan (protocol-kit prep §3.5). Each model's socket carries the
// configuration its registers hold: a register write updates the model's
// cfg and sets it on the socket. ua sends three bytes, ub two, back to
// back; each takes its transfer time under the sender's configuration
// (10 bits at 10 Mbaud: 1000 ns). +baud_b=N writes ub's baud register;
// when it differs from ua's, every byte arrives with frame_err set. No
// RTL: the root clock's period drives the run (+fw_edges).
`include "fw_hdl_macros.svh"

package two_uart_pkg;
    import fw_hdl_pkg::*;
    import fw_hdl_std_pkg::*;
    `include "test_uart_chan.svh"

    class uart_model extends fw_component implements uart_put_if, fw_run_if;
        `fw_component_utils(uart_model)
        fw_socket_cfg_src #(uart_put_if, uart_put_if, uart_cfg_t) s;
        uart_cfg_t  cfg;        // the configuration registers
        bit [7:0]   tx[$];      // bytes to send
        string      got[$];

        virtual function void build();
            s = fw_socket_cfg_src #(uart_put_if, uart_put_if, uart_cfg_t)::create("s", this);
            s.set_imp(this);
            write_reg(0, 10_000_000);
            write_reg(1, 0);
            write_reg(2, 1);
        endfunction

        // A register write: 0 baud, 1 parity, 2 stop bits.
        function void write_reg(int addr, int unsigned v);
            case (addr)
                0: cfg.baud = v;
                1: cfg.parity = v[0];
                2: cfg.stop_bits = v[1:0];
            endcase
            s.set(cfg);
        endfunction

        virtual task run();
            uart_put_if i = s.get_if();
            foreach (tx[k]) i.put('{data: tx[k], frame_err: 0});
        endtask

        virtual task put(uart_char_t c);
            string err = "";
            if (c.frame_err) err = "!";
            got.push_back($sformatf("%0h%s@%0d", c.data, err, int'(fw_time::now() / 1ns)));
        endtask
    endclass

    class top_c extends fw_component;
        `fw_component_utils(top_c)
        fw_clock_domain clk;
        uart_model      ua;
        uart_txrx_chan  x;
        uart_model      ub;
        virtual function void build();
            clk = fw_clock_domain::create("clk", this, fw_clock_kind::root(10ns));
            fw_clock_domain::set(this, clk);
            ua = uart_model::create("ua", this);
            x  = uart_txrx_chan::create("x", this);
            ub = uart_model::create("ub", this);
            ua.tx = '{8'h41, 8'h42, 8'h43};
            ub.tx = '{8'h61, 8'h62};
        endfunction
        virtual function void connect();
            int unsigned baud_b;
            if ($value$plusargs("baud_b=%d", baud_b)) ub.write_reg(0, baud_b);
            x.a.connect(ua.s);
            x.b.connect(ub.s);
        endfunction
    endclass
endpackage

module two_uart;
    import fw_hdl_pkg::*;
    import two_uart_pkg::*;

    top_c t;

    initial begin
        string s;
        int nerr;
        t = top_c::create("top", null);
        nerr = __fw_rt::elaborate(t);
        if (nerr == 0) __fw_rt_kern::run();
        s = "";
        foreach (t.ub.got[i]) s = {s, " ", t.ub.got[i]};
        $display("R b got%s", s);
        s = "";
        foreach (t.ua.got[i]) s = {s, " ", t.ua.got[i]};
        $display("R a got%s", s);
        foreach (__fw_rt::diags[i]) $display("D %s %s", __fw_rt::diags[i].id, __fw_rt::diags[i].path);
        $finish;
    end
endmodule
