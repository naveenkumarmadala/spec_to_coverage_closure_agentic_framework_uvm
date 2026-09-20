// =============================================================================
// apb_fsm_cov — reusable, clock-sampled APB completer-phase coverage.
//
// The transaction-level covergroup in apb_coverage.sv cannot see bus PHASES: it is
// fed one item per COMPLETED transfer, so IDLE/SETUP/ACCESS and the edges between
// them (in particular ACCESS -> SETUP, i.e. back-to-back with PSEL held) have no
// coverage point there. This module reconstructs the completer-side phase from the
// pins and covers the phase and its transitions.
//
// Plain module, instantiated (not bound) from the testbench top next to the DUT:
//     apb_fsm_cov u_apb_fsm_cov (.pclk(pclk), .presetn(presetn),
//                                .psel(apb.psel), .penable(apb.penable));
//
// access_setup_b2b is only reachable when the APB driver's back-to-back mode is
// enabled (apb_agent_cfg.b2b_enable + apb_item.back_to_back); with the default
// one-transfer-per-item driving it is a legitimately unhit bin.
// =============================================================================
module apb_fsm_cov (
    input logic pclk,
    input logic presetn,
    input logic psel,
    input logic penable
);
    typedef enum logic [1:0] {
        APB_IDLE   = 2'b00,
        APB_SETUP  = 2'b01,
        APB_ACCESS = 2'b10
    } apb_phase_e;

    apb_phase_e phase;
    always_comb begin
        if      (!psel)    phase = APB_IDLE;
        else if (!penable) phase = APB_SETUP;
        else               phase = APB_ACCESS;
    end

    covergroup cg_apb_fsm @(posedge pclk);
        option.per_instance = 1;
        cp_state: coverpoint phase iff (presetn === 1'b1) {
            bins IDLE   = {APB_IDLE};
            bins SETUP  = {APB_SETUP};
            bins ACCESS = {APB_ACCESS};
        }
        cp_trans: coverpoint phase iff (presetn === 1'b1) {
            bins idle_setup       = (APB_IDLE   => APB_SETUP);
            bins setup_access     = (APB_SETUP  => APB_ACCESS);
            bins access_setup_b2b = (APB_ACCESS => APB_SETUP);
            bins access_idle      = (APB_ACCESS => APB_IDLE);
        }
    endgroup

    cg_apb_fsm cov_inst = new();
endmodule
