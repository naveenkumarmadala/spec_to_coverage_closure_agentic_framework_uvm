// VP-PWM-DUTY: directed COMPARE sweep against a fixed PERIOD, PWM_EN=1, on every channel,
// closing cg_pwm's cp_duty_class x cp_pwm_en cross and every cp_measured_duty bin. This
// sequence only CREATES the scenario (per-channel COMPARE/PERIOD programming + enough run
// time to complete >=1 period); the self-checking is done by the monitor-side assertions in
// dv/sv/sva/pmtpc4_pwm_cov.sv (a_duty_compare_zero / a_duty_full_low / a_duty_matches_cmp /
// a_pwm_off) and by cg_pwm sampling on the RUNNING->EXPIRED edge it observes — this
// sequence never samples coverage or eyeballs waves itself.
//
// CH_CTRL bits: CH_EN=1 CH_MODE=2 PWM_EN=4 CH_START=8 CH_PAUSE=16.
class pmtpc4_pwm_duty_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_pwm_duty_vseq)
    function new(string name="pmtpc4_pwm_duty_vseq"); super.new(name); endfunction

    localparam bit [31:0] EN=1, MODE=2, PWM=4;
    localparam bit [15:0] P = 16'd32;   // fixed nonzero PERIOD for the compare sweep

    // Program PERIOD/COMPARE, (re)start the channel periodic with the requested PWM_EN,
    // and run long enough to complete several periods, then stop.
    task run_case(int ch, bit [15:0] per_v, bit [15:0] cmp_v, bit pwm_on, int cycles);
        reg_wr(chan(ch).CH_CTRL, 0);   // CH_EN low before reconfiguring
        reg_wr(chan(ch).CH_PERIOD, per_v);
        reg_wr(chan(ch).CH_COMPARE, cmp_v);
        // periodic; CH_EN rising -> start_trig
        reg_wr(chan(ch).CH_CTRL, EN | MODE | (pwm_on ? PWM : 32'h0));
        cyc(cycles);
        reg_wr(chan(ch).CH_CTRL, 0);                                 // stop
        cyc(4);
    endtask

    task body();
        bit [15:0] cmps[9];
        cmps = '{16'd0, 16'd1, P/4, P/2, (P*3)/4, P-16'd1, P, P+16'd1, 16'hFFFF};

        enable_module(0);   // PRESCALER=0 (div-1): tick_en every pclk, MODULE_EN=1

        for (int ch = 0; ch < 4; ch++) begin
            // cp_duty_class.period_zero x cp_pwm_en.on
            run_case(ch, 16'd0, 16'd3, 1, 10);

            // cp_duty_class.{compare_zero, compare_lt_period, compare_eq_period,
            // compare_gt_period} x cp_pwm_en.on — also spreads cp_measured_duty across
            // zero_pct/low/mid/high/full.
            foreach (cmps[k]) run_case(ch, P, cmps[k], 1, 120);

            // cp_pwm_en.off leg: proves the PWM_EN gate itself (a_pwm_off), and closes
            // x_duty_class_pwm_en's remaining {compare_eq_period, compare_gt_period,
            // period_zero} x off cells (compare_lt_period x off already covered by the
            // P/2 case below).
            run_case(ch, P, P/2, 0, 60);
            run_case(ch, P, P, 0, 60);
            run_case(ch, P, P+16'd1, 0, 60);
            run_case(ch, 16'd0, 16'd3, 0, 10);
        end
    endtask
endclass
