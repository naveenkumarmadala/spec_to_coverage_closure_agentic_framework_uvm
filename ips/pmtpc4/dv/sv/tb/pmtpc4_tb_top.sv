// Top-level testbench: DUT + APB IF + reset IF + PWM IF + SVA binds + UVM run_test.
module pmtpc4_tb_top;
    import uvm_pkg::*;
    import pmtpc4_test_pkg::*;

    logic pclk = 0;
    always #5 pclk = ~pclk;              // 100 MHz

    // ---- reset ---------------------------------------------------------------
    // PRESETn is owned by the reusable reset_if (vip/common/sv/reset_if.sv) instead
    // of a bare `initial` block, so a virtual sequence can assert reset at ANY point
    // in a running simulation (VP-RST-ASYNC), not just at power-on. Parameters are
    // left at their defaults so a plain `virtual reset_if` handle matches this
    // instance's type in the config_db.
    reset_if #(.ACTIVE_LOW(1'b1), .POR_CYCLES(5)) rst_if (.clk(pclk));
    wire presetn = rst_if.rst;

    apb_if #(.ADDR_WIDTH(8), .DATA_WIDTH(32)) apb (.pclk(pclk), .presetn(presetn));

    logic [3:0] pwm_out;
    logic       irq;

    // ---- black-box PWM observation (VP-PWM-BLACKBOX) --------------------------
    // Passive by construction: pwm is an interface INPUT port, so the UVC cannot
    // drive the DUT outputs even by accident.
    pwm_if #(.NUM_PINS(PMTPC4_NUM_PWM)) pwm_ivf (
        .clk(pclk), .rst_n(presetn), .pwm(pwm_out));

    pmtpc4 dut (
        .pclk    (pclk),      .presetn (presetn),
        .psel    (apb.psel),  .penable (apb.penable), .pwrite (apb.pwrite),
        .paddr   (apb.paddr), .pwdata  (apb.pwdata),  .prdata (apb.prdata),
        .pready  (apb.pready),.pslverr (apb.pslverr),
        .pwm_out (pwm_out),   .irq     (irq)
    );

    // ---- APB completer-phase coverage (VP-APB-FSM-B2B) ------------------------
    // Reusable VIP module; reconstructs IDLE/SETUP/ACCESS from the pins and covers
    // the transitions, including ACCESS->SETUP back-to-back (PSEL held).
    apb_fsm_cov u_apb_fsm_cov (
        .pclk(pclk), .presetn(presetn), .psel(apb.psel), .penable(apb.penable));

    // ---- SVA binds (connections resolve in the target module's scope) ----
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

    // Power-on reset: same shape as before (low for 5 pclk edges), now issued through
    // the reset interface so mid-simulation assertions use the identical driver.
    initial rst_if.power_on_reset();

    initial begin
        uvm_config_db#(virtual apb_if)::set(null, "*", "vif", apb);
        uvm_config_db#(virtual reset_if)::set(null, "*", "reset_vif", rst_if);
        // Use the package typedef on both sides so the parameterized virtual-interface
        // specialization used as the config_db key is identical.
        uvm_config_db#(pmtpc4_pwm_vif_t)::set(null, "*", "pwm_vif", pwm_ivf);
        run_test();
    end

    initial begin
        $dumpfile("pmtpc4.fst");
        $dumpvars(0, pmtpc4_tb_top);
    end
endmodule
