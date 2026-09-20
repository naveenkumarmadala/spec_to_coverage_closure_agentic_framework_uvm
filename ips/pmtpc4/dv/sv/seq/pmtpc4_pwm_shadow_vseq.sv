// VP-PWM-SHADOW-DEFER: start a periodic channel, write COMPARE (then, separately,
// PERIOD) mid-RUNNING, and let several periods elapse -- on ALL FOUR channels (a
// 2026-09-18 functional-coverage-report audit found the first revision of this
// vseq only ever touched channel 0, leaving cp_cmp_write_timing/cp_per_write_timing
// stuck at 50% -- "no_write_this_period" only -- on channels 1-3). This vseq only
// creates the scenario; the checking is entirely by assertion —
// sva/pmtpc4_channel_sva.sv::a_shadow_holds_midrun (compare_shadow provably didn't
// move early) and sva/pmtpc4_pwm_cov.sv::a_duty_matches_cmp / a_pwm_matches_independent
// (the duty for the remainder of THIS period still reflects the OLD value; the next
// period reflects the new one) — none of it is asserted by this vseq itself.
// Coverage (cp_cmp_write_timing/cp_per_write_timing) is sampled by the bound SVA
// from the same mid-run writes, not by this vseq.
class pmtpc4_pwm_shadow_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_pwm_shadow_vseq)
    function new(string name="pmtpc4_pwm_shadow_vseq"); super.new(name); endfunction

    localparam bit [31:0] EN=1, MODE=2, PWM=4, PAUSE=16;
    localparam bit [15:0] P = 16'd40;

    task compare_deferral(int ch);
        reg_wr(chan(ch).CH_PERIOD, P);
        reg_wr(chan(ch).CH_COMPARE, 16'd10);
        reg_wr(chan(ch).CH_CTRL, EN|MODE|PWM);   // periodic, PWM on
        cyc(20);                                  // mid-period
        reg_wr(chan(ch).CH_COMPARE, 16'd30);      // mid-run write: must defer to the NEXT LOAD
        cyc(120);                                  // several more periods
        reg_wr(chan(ch).CH_CTRL, 0);
        cyc(4);
    endtask

    task period_deferral(int ch);
        reg_wr(chan(ch).CH_PERIOD, P);
        reg_wr(chan(ch).CH_COMPARE, 16'd10);
        reg_wr(chan(ch).CH_CTRL, EN|MODE|PWM);
        cyc(20);
        reg_wr(chan(ch).CH_PERIOD, 16'd80);       // mid-run write: must defer to the NEXT LOAD
        cyc(200);
        reg_wr(chan(ch).CH_CTRL, 0);
        cyc(4);
    endtask

    // ---------------------------------------------------------------------------
    // The mid-run COMPARE write above always happens on a channel loaded with
    // 0 < COMPARE < PERIOD, so cg_pwm's x_cmp_write_duty cross only ever landed in
    // (write_midrun_effect_deferred, compare_lt_period). The deferral rule of
    // Design 7.4 is not specific to that duty class, so the other four classes need
    // the same exercise -- with the write landing while the channel is genuinely in
    // RUN/PAUSED, which is what cp_cmp_write_timing keys on.
    //
    // Landing the write inside RUN/PAUSED is made DETERMINISTIC by starting the
    // channel with CH_PAUSE already asserted: errata 12.1 takes IDLE -> LOAD ->
    // PAUSED on the first tick and the channel then sits in PAUSED indefinitely, so
    // the COMPARE write cannot miss its window (a plain mid-RUN write races the
    // period, and for the PERIOD=0 class the RUN state is one tick wide). Releasing
    // CH_PAUSE afterwards lets the channel run to a natural EXPIRED, which is where
    // cg_pwm samples (run_to_exp_edge) -- with per_at_load/cmp_at_load still holding
    // the LOAD-time pair that classifies the duty, and cmp_written_midrun sticky.
    //
    // per=0 -> period_zero, cmp=0/per!=0 -> compare_zero, cmp==per -> compare_eq_period,
    // cmp>per -> compare_gt_period (classify_duty() in sva/pmtpc4_pwm_cov.sv).
    task compare_write_while_paused(int ch, bit [15:0] per, bit [15:0] cmp_at_load,
                                    bit [15:0] cmp_new);
        uvm_reg_data_t c1, c2;
        reg_wr(p_sequencer.ral.PRESCALER, 0);
        reg_wr(chan(ch).CH_PERIOD,  per);
        reg_wr(chan(ch).CH_COMPARE, cmp_at_load);
        reg_wr(chan(ch).CH_CTRL, EN|MODE|PWM|PAUSE);   // IDLE -> LOAD -> PAUSED
        cyc(10);
        reg_rd(chan(ch).CH_COUNT, c1);
        chk(c1 == per,
            $sformatf("CH%0d: COUNT must hold the loaded PERIOD (0x%0h) while parked in PAUSED (got 0x%0h)",
                      ch, per, c1));
        reg_wr(chan(ch).CH_COMPARE, cmp_new);          // the deferred-effect write
        cyc(10);
        reg_rd(chan(ch).CH_COUNT, c2);
        chk(c1 == c2,
            $sformatf("CH%0d: a COMPARE write while PAUSED must not disturb COUNT", ch));
        reg_wr(chan(ch).CH_CTRL, EN|MODE|PWM);          // release: PAUSED -> RUN -> EXPIRED
        cyc(3*int'(per) + 60);                          // several full periods at PRESCALER=0
        reg_wr(chan(ch).CH_CTRL, 0);
        reg_wr(chan(ch).CH_COMPARE, 0);
        cyc(4);
    endtask

    task body();
        enable_module(0);
        for (int ch = 0; ch < 4; ch++) begin
            compare_deferral(ch);
            period_deferral(ch);
            // x_cmp_write_duty: the four duty classes the mid-run-write cross was
            // missing, on every channel (the cross is option.per_instance).
            compare_write_while_paused(ch, 16'd0,  16'd5,  16'd9);   // period_zero
            compare_write_while_paused(ch, P,      16'd0,  16'd7);   // compare_zero
            compare_write_while_paused(ch, P,      P,      16'd7);   // compare_eq_period
            compare_write_while_paused(ch, P,      P+16'd20, 16'd7); // compare_gt_period
        end
    endtask
endclass
