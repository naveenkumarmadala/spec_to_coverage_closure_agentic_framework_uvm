// Top-level testbench: DUT + APB IF + reset IF + PWM IF + UVM run_test (binds: pmtpc4_binds.sv).
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

    // ---- SVA / coverage binds live in tb/pmtpc4_binds.sv (module pmtpc4_binds) ----
    // Elaborated as a SECOND top in the normal snapshot and deliberately left out of the
    // code-toggle snapshot: on xsim a bound checker makes the DUT nets it observes lose
    // their toggle coverage. See the header of pmtpc4_binds.sv.

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

    // Waveform dump lives in tb/pmtpc4_dump.sv (module pmtpc4_dump, +DUMP only), NOT here:
    // on xsim the mere presence of $dumpvars in the elaborated design stops code-toggle
    // recording on some DUT nets, even if it never executes. The code-toggle snapshot
    // leaves that top out entirely.
endmodule
