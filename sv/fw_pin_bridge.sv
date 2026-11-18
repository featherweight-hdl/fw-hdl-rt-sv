// fw_pin_bridge #(type T, PATH): moves a value between the class signal at
// PATH ("top.in.valid") and a module pin (core-layer2.md §8). No protocol
// knowledge; a testbench generator places one per pin.
//
// - RTL -> class (the signal is an effective input port of the top
//   component): each change of i is written to the signal and the comb
//   blocks settle at once, so a class comb() that reads it updates in the
//   same time step.
// - class -> RTL (any other signal): o follows the signal after each settle.
//   o also shows an input's value.
//
// - RTL clock -> class clock (PATH names a clock domain): each posedge of i
//   is an edge of the domain: its step blocks run in the active region; its
//   register writes commit, and the comb blocks settle, after the NBA region
//   of that time step. A register (and a comb output that reads one) so
//   changes after the RTL flops at that edge sampled, as an RTL flop's
//   output does, and the edges number as in an all-RTL design. The edge
//   loop does not tick a bridged domain. o is unused. The first clock
//   bridge starts the run() tasks; they resume at an edge after its steps,
//   and their register writes commit with the steps'.
//
// Elaboration must have run (fw_hdl_pkg::__fw_rt::elaborate) before the
// pins move; the bridge waits for it.
module fw_pin_bridge #(type T = bit, parameter string PATH = "") (
    input  T i,
    output T o
);
    import fw_hdl_pkg::*;

    initial begin
        __fw_rt_obj s;
        __fw_rt_cell_t #(T) c;
        // PATH "": not placed by a generator (an extra top): nothing to do
        if (PATH != "") begin
            wait (__fw_rt::phase == __FW_P_DONE);
            s = __fw_rt_kern::pin_sig(PATH);
        end
        if (s != null && __fw_rt_kern::is_clock(s)) begin
            bit nba;
            __fw_rt_kern::pin_clks[s] = 1;
            __fw_rt_kern::pin_start();
            __fw_rt_kern::start_runs();
            forever begin
                @(posedge i);
                __fw_rt_kern::pin_edge(s);
                nba <= ~nba;
                @(nba);
                __fw_rt_kern::pin_commit(s);
            end
        end else if (s != null) begin
            c = __fw_rt_cell_t #(T)::of(s.h);
            __fw_rt_kern::pin_start();
            if (__fw_rt_kern::pin_in(s)) begin
                forever begin
                    c.nxt = i;
                    __fw_rt_kern::pin_write(c);
                    o = c.cur;
                    @(i);
                end
            end else begin
                forever begin
                    o = c.cur;
                    @(__fw_rt_kern::settled);
                end
            end
        end
    end
endmodule
