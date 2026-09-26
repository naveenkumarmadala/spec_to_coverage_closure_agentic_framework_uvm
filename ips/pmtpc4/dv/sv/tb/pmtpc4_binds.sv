// White-box SVA / coverage binds, kept in their OWN top-level module (elaborated as a
// second top next to pmtpc4_tb_top) instead of inside the testbench top.
//
// Why a separate top: on Vivado xsim 2025.1 a DUT net that a bound checker observes
// LOSES its code-toggle coverage (measured 2026-09-26: int_status_val, int_en_val,
// cpuif_addr, cpuif_wr_data, compare_shadow all read 0% toggle with the binds present and
// toggle normally without them). The binds are read-only observers, so the DUT executes
// identically with or without them. xsim_flow.sh therefore elaborates two snapshots:
//   <ip>_sim  = pmtpc4_tb_top + pmtpc4_binds : assertions, functional coverage, stmt/branch/cond
//   <ip>_tcov = pmtpc4_tb_top only            : DUT code-TOGGLE measurement
// run_regression.py runs the union test on both and checks they executed identically.
// Connections resolve in the target module's scope (standard `bind` semantics).
module pmtpc4_binds;
    bind pmtpc4 pmtpc4_apb_sva u_apb_sva (
        .pclk(pclk), .presetn(presetn), .psel(psel), .penable(penable),
        .pready(pready), .pslverr(pslverr), .pwrite(pwrite), .paddr(paddr));
    bind pmtpc4 pmtpc4_top_sva u_top_sva (
        .pclk(pclk), .presetn(presetn), .module_en(module_en),
        .int_status_val(int_status_val), .int_en_val(int_en_val),
        .global_ie(global_ie), .global_int_status(global_int_status),
        .irq(irq), .pwm_out(pwm_out),
        .ch_state0(ch_state[0]), .ch_state1(ch_state[1]),
        .ch_state2(ch_state[2]), .ch_state3(ch_state[3]),
        .psel(psel), .penable(penable),
        .ch_expiry({ch_expiry[3], ch_expiry[2], ch_expiry[1], ch_expiry[0]}),
        .cpuif_req(cpuif_req), .cpuif_req_is_wr(cpuif_req_is_wr),
        .cpuif_addr(cpuif_addr), .cpuif_wr_data(cpuif_wr_data),
        .soft_reset(soft_rst_pulse),
        .ch_busy({ch_busy[3], ch_busy[2], ch_busy[1], ch_busy[0]}),
        .status_busy_val(hwif_in.STATUS.BUSY.next),
        .status_ready_val(hwif_in.STATUS.READY.next));
    bind pmtpc4_channel pmtpc4_channel_sva u_ch_sva (
        .pclk(pclk), .presetn(presetn), .soft_reset(soft_reset), .module_en(module_en),
        .tick_en(tick_en), .ch_en(ch_en), .ch_mode(ch_mode), .pwm_en(pwm_en),
        .ch_start(ch_start), .ch_pause(ch_pause),
        .count(count), .compare(compare), .compare_shadow(compare_shadow), .period(period),
        // bind the white-box state input to the registered FSM reg `state`, not the
        // combinational output alias `state_o`: on xsim the preponed sample of a
        // continuous-assign net (assign state_o = state) reads X every clock even though
        // its settled value is correct, spuriously firing the valid-state assertion.
        .state_o(state), .expiry(expiry), .pwm(pwm_q));
    // VP-PRESC-RATIO: shared-prescaler tick-spacing checker + coverage (bound once,
    // not per-channel -- this is a property of the ONE shared prescaler).
    bind pmtpc4 pmtpc4_presc_sva u_presc_sva (
        .pclk(pclk), .presetn(presetn), .soft_reset(soft_rst_pulse), .module_en(module_en),
        .prescaler_val(hwif_out.PRESCALER.PRESCALER_VAL.value), .tick_en(tick_en));
    // VP-PWM-DUTY: independent PWM duty covergroup + companion checkers, predicting from
    // the `compare`/`period` input PORTS (never from the DUT's own compare_shadow) — that
    // independence is what catches a `compare_shadow <= '0` mutation that the white-box
    // a_pwm_rule (above) cannot.
    bind pmtpc4_channel pmtpc4_pwm_cov u_pwm_cov (
        .pclk(pclk), .presetn(presetn), .soft_reset(soft_reset), .module_en(module_en),
        .tick_en(tick_en), .ch_en(ch_en), .ch_mode(ch_mode), .pwm_en(pwm_en),
        .ch_start(ch_start), .ch_pause(ch_pause),
        .period(period), .compare(compare), .count(count),
        .state_o(state), .pwm(pwm_q));
endmodule
