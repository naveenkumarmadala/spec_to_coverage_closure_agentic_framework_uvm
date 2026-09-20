// Formal harness for the channel FSM (SymbiYosys + open-source Yosys).
// Uses simple immediate assertions (Yosys's SV frontend supports these without
// Verific). Inputs left undriven are treated as free stimulus by the prover.
module pmtpc4_channel_fv (input logic pclk, input logic presetn);
    logic        soft_reset, module_en, tick_en;
    logic        ch_en, ch_mode, pwm_en, ch_start, ch_pause;
    logic [15:0] period, compare, count;
    logic        busy, expiry, ch_en_clr, pwm;
    logic [2:0]  state_o;

    pmtpc4_channel #(.CW(16)) dut (
        .pclk, .presetn, .soft_reset, .module_en, .tick_en,
        .ch_en, .ch_mode, .pwm_en, .ch_start, .ch_pause,
        .period, .compare, .count, .busy, .expiry, .ch_en_clr, .state_o, .pwm
    );

    localparam logic [2:0] S_EXP = 3'd4;

    // P1: state is always one of the 5 legal encodings (no illegal FSM state)
    always @(posedge pclk) if (presetn) assert (state_o <= 3'd4);

    // P2: freeze — while MODULE_EN=0 (and not soft-reset), COUNT holds (errata 12.3)
    logic [15:0] count_q;
    logic        valid_q;
    always @(posedge pclk) begin count_q <= count; valid_q <= presetn; end
    always @(posedge pclk)
        if (presetn && valid_q && !module_en && !soft_reset)
            assert (count == count_q);

    // P3: expiry pulse only in EXPIRED
    always @(posedge pclk) if (presetn) if (expiry) assert (state_o == S_EXP);

    // C1: prove the EXPIRED state is reachable (no dead FSM)
    always @(posedge pclk) if (presetn) cover (state_o == S_EXP);
endmodule
