// Coverage-closure sequence: systematically exercises ALL FOUR channels through
// every FSM state/transition (cg_fsm) and sweeps the config coverpoints (cg_cfg).
// The directed scenario vseqs only touch channel 0; this closes ch1..ch3 (0% before)
// and the remaining ch0 transitions + config bins.
class pmtpc4_cov_close_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_cov_close_vseq)
    function new(string name="pmtpc4_cov_close_vseq"); super.new(name); endfunction

    // CH_CTRL bit fields
    localparam bit [31:0] EN=1, MODE=2, PWM=4, START=8, PAUSE=16;

    // Drive one channel through all 10 FSM transitions + all 5 states.
    task exercise_channel(int ch);
        // fast ticks so short periods expire quickly
        reg_wr(p_sequencer.ral.PRESCALER, 0);
        reg_wr(p_sequencer.ral.CTRL, EN);            // MODULE_EN=1
        // --- one-shot: IDLE->LOAD->RUN->EXPIRED->IDLE (idle_load, load_run, run_exp, exp_idle) ---
        reg_wr(chan(ch).CH_PERIOD, 3);
        reg_wr(chan(ch).CH_COMPARE, 1);
        reg_wr(chan(ch).CH_CTRL, EN|PWM);            // one-shot (MODE=0), CH_EN rising => start_trig
        cyc(30);
        // --- periodic: EXPIRED->LOAD reload (exp_load) + repeated load_run ---
        reg_wr(chan(ch).CH_PERIOD, 3);
        reg_wr(chan(ch).CH_CTRL, EN|MODE|PWM);       // periodic
        cyc(40);
        // --- run_paused / paused_run on a long period so it stays RUNNING ---
        reg_wr(chan(ch).CH_PERIOD, 16'h00FF);
        reg_wr(chan(ch).CH_CTRL, EN|MODE|PWM);       // (re)start running
        cyc(10);
        reg_wr(chan(ch).CH_CTRL, EN|MODE|PWM|PAUSE); // RUN->PAUSED
        cyc(10);
        reg_wr(chan(ch).CH_CTRL, EN|MODE|PWM);       // PAUSED->RUN
        cyc(10);
        // --- run_idle: soft-disable while RUNNING ---
        reg_wr(chan(ch).CH_CTRL, 0);                 // CH_EN=0 => RUN->IDLE
        cyc(5);
        // --- load_paused (errata 12.1): start with CH_PAUSE set => LOAD->PAUSED ---
        reg_wr(chan(ch).CH_CTRL, EN|START|PAUSE);    // IDLE->LOAD then LOAD->PAUSED
        cyc(5);
        // --- paused_idle: soft-disable while PAUSED ---
        reg_wr(chan(ch).CH_CTRL, 0);                 // CH_EN=0 while PAUSED => PAUSED->IDLE
        cyc(5);
        // --- COUNT upper-byte toggle closure (all channels, not just ch0) ---
        // count <= period at LOAD entry (channel.sv:86), so a large PERIOD
        // immediately makes count's upper bits nonzero without waiting out a
        // full countdown; a following small-PERIOD LOAD brings them back to
        // zero (soft-disable alone does not clear count -- it is retained).
        reg_wr(chan(ch).CH_PERIOD, 16'hFFFF);        // every bit set, for one-shot full-bit coverage
        reg_wr(chan(ch).CH_CTRL, EN|START);          // IDLE->LOAD: count <= 'hFFFF
        cyc(4);
        reg_wr(chan(ch).CH_CTRL, 0);                 // back to IDLE, count retained at 'hFFFF
        cyc(4);
        reg_wr(chan(ch).CH_PERIOD, 16'h0003);
        reg_wr(chan(ch).CH_CTRL, EN|START);          // IDLE->LOAD: count <= 'h0003 (upper bits -> 0)
        cyc(4);
        reg_wr(chan(ch).CH_CTRL, 0);
        cyc(4);
        // --- cp_period_at_load.{one,largep} on EVERY channel: run PERIOD=1 and a
        // large PERIOD to a NATURAL EXPIRED completion (not soft-disabled early).
        // Every other scenario above either soft-disables before expiry or uses a
        // small/zero PERIOD, so these two bins were never hit on ANY channel
        // (confirmed via the functional coverage report -- a real, closable gap,
        // not a tool artifact).
        reg_wr(chan(ch).CH_PERIOD, 16'h0001);
        reg_wr(chan(ch).CH_CTRL, EN);                 // one-shot, PERIOD=1: 3 ticks to EXPIRED
        cyc(10);
        reg_wr(chan(ch).CH_CTRL, 0);
        cyc(2);
        reg_wr(chan(ch).CH_PERIOD, 16'h0200);
        reg_wr(chan(ch).CH_CTRL, EN);                 // one-shot, large PERIOD, run to completion
        cyc(16'h0200 + 10);
        reg_wr(chan(ch).CH_CTRL, 0);
        cyc(4);
    endtask

    // Hit every cg_cfg bin (prescaler/period/compare extremes, mode/pwm/pause,
    // gie, inten none/some/all, moduleen).
    task sweep_config();
        reg_wr(p_sequencer.ral.CTRL, EN);
        // prescaler: zero / one / mid / max
        reg_wr(p_sequencer.ral.PRESCALER, 16'h0000);
        reg_wr(p_sequencer.ral.PRESCALER, 16'h0001);
        reg_wr(p_sequencer.ral.PRESCALER, 16'h8000);
        reg_wr(p_sequencer.ral.PRESCALER, 16'hFFFF);
        reg_wr(p_sequencer.ral.PRESCALER, 0);
        // global IE: dis / en
        reg_wr(p_sequencer.ral.GLOBAL_IE, 0);
        reg_wr(p_sequencer.ral.GLOBAL_IE, 1);
        // INT_ENABLE: none / some / all
        reg_wr(p_sequencer.ral.INT_ENABLE, 4'h0);
        reg_wr(p_sequencer.ral.INT_ENABLE, 4'h7);
        reg_wr(p_sequencer.ral.INT_ENABLE, 4'hF);
        // per-channel period/compare extremes + mode/pwm/pause bins (on ch0)
        reg_wr(chan(0).CH_PERIOD, 16'h0000);
        reg_wr(chan(0).CH_PERIOD, 16'h0001);
        reg_wr(chan(0).CH_PERIOD, 16'h8000);
        reg_wr(chan(0).CH_PERIOD, 16'hFFFF);
        reg_wr(chan(0).CH_COMPARE, 16'h0000);
        reg_wr(chan(0).CH_COMPARE, 16'h8000);
        reg_wr(chan(0).CH_COMPARE, 16'hFFFF);
        reg_wr(chan(0).CH_CTRL, EN|MODE|PWM|PAUSE);  // mode=1, pwm=1, pause=1
        reg_wr(chan(0).CH_CTRL, 0);                  // mode=0, pwm=0, pause=0
        // moduleen: dis / en
        reg_wr(p_sequencer.ral.CTRL, 0);
        reg_wr(p_sequencer.ral.CTRL, EN);
    endtask

    // RTL corners for code coverage: PERIOD=0 (expire-next-tick), SOFT_RESET path
    // (channel/prescaler/regblock soft_reset branches), and a prescaler running long
    // enough for its counter bits to toggle.
    task rtl_corners();
        // PERIOD=0: one-shot expires on the very next tick (no lockup)
        reg_wr(p_sequencer.ral.PRESCALER, 0);
        reg_wr(p_sequencer.ral.CTRL, EN);
        reg_wr(chan(0).CH_PERIOD, 16'h0000);
        reg_wr(chan(0).CH_CTRL, EN);                 // one-shot, period 0
        cyc(6);
        // prescaler running: mid divide value, run long so cnt[] toggles
        reg_wr(p_sequencer.ral.PRESCALER, 16'h003F);
        reg_wr(chan(1).CH_PERIOD, 16'h0010);
        reg_wr(chan(1).CH_CTRL, EN|MODE|PWM);        // periodic, keep it running
        cyc(200);
        // SOFT_RESET pulse while running -> covers soft_reset branches everywhere
        reg_wr(p_sequencer.ral.CTRL, EN | 2);        // MODULE_EN=1, SOFT_RESET=1 (singlepulse)
        cyc(4);
        // tidy up
        reg_wr(p_sequencer.ral.PRESCALER, 0);
        reg_wr(chan(1).CH_CTRL, 0);
    endtask

    // NOTE: an earlier revision of this file added a close_compare_shadow_toggle(ch)
    // task here, intended to exercise compare_shadow's value-latching behavior.
    // Removed after verification-reviewer found it structurally unobservable (every
    // CH_CTRL write in it used PWM=0, so pwm_level -- the only signal that reads
    // compare_shadow -- was identically 0 throughout) AND redundant with
    // pmtpc4_toggle_vseq, which already sweeps CH_COMPARE against a nonzero PERIOD
    // with PWM_EN on, across all 4 channels -- the real Design-7.4 latch exercise.
    // Deliberate mutation testing (compare_shadow <= compare, changed to <= live
    // compare, and <= '0 at both latch points) survived a full regression with this
    // task present, confirming it added no verification value; see
    // reports/coverage_waivers.md and the verification review this session for the
    // full trace. compare_shadow's toggle-coverage 0/0 report remains a confirmed
    // tool artifact (empirically proven via a temporary RTL $display trace before
    // this task was written) and stays waived in dv/pmtpc4_cov_exclusions.txt
    // (`signal -compare_shadow`) independent of this task's removal.

    task body();
        sweep_config();
        for (int ch = 0; ch < 4; ch++) exercise_channel(ch);
        rtl_corners();
    endtask
endclass
