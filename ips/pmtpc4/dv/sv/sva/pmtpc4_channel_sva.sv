// Per-channel white-box assertions + FSM coverage — bound into pmtpc4_channel.
//
// VP-PWM-SHADOW / VP-CH-COUNT-VALUE (2026-09-16, verification-reviewer mutation audit):
// a_shadow_latches_input / a_count_loads_period / a_count_decrements / a_count_retained
// predict compare_shadow/count from the channel's `compare`/`period` INPUT PORTS (mirrored
// through this module's own always_ff, never $past'd across the bind — see the existing
// a_pwm_rule comment on the xsim preponed-region X issue on bound-module ports), NOT from
// compare_shadow/count's own registered values. That independence is what a_pwm_rule (which
// rebuilds its expectation from the DUT's own compare_shadow) structurally lacks, and is what
// catches a deliberately seeded `compare_shadow <= '0` / `count <= period + 1` at the LOAD
// entry that survived a full green regression with only a_pwm_rule in place.
//
// cg_fsm gets `option.per_instance = 1` (so ch0-3 report independently instead of the TYPE
// score merging them) plus cp_frozen_state (VP-FREEZE-STATES) and cp_mode_at_expiry /
// cp_mode_changed_run (VP-CH-MODE-LIVE, errata 12.2) with a_mode_live to check the outcome.
module pmtpc4_channel_sva (
    input logic        pclk, presetn, soft_reset, module_en, tick_en,
    input logic        ch_en, ch_mode, pwm_en, ch_start, ch_pause,
    input logic [15:0] count, compare, compare_shadow, period,
    input logic [2:0]  state_o,
    input logic        expiry, pwm
);
    typedef enum logic [2:0] {
        S_IDLE, S_LOAD, S_RUN, S_PAUSED, S_EXP
    } ch_state_e;

    a_valid_state: assert property (@(posedge pclk) disable iff (!presetn)
        state_o inside {S_IDLE, S_LOAD, S_RUN, S_PAUSED, S_EXP});
    a_expiry_in_expired: assert property (@(posedge pclk) disable iff (!presetn)
        expiry |-> (state_o == S_EXP));
    // Registered PWM waveform rule -- derived from design_spec.md SPEC-PWM-1 (2026-09-19
    // corrected text, see that file's own history note): pwm is registered (pwm_q <=
    // pwm_level), high while PWM_EN && (state != IDLE) && (COUNT > the *shadowed* COMPARE),
    // updated only while module_en, and forced low by reset/soft_reset. This is now the
    // SPEC's own formula, independently re-derived from spec text (not copied from the
    // RTL) -- state != IDLE is correct because REQ-CORE-3 itself carries no state qualifier
    // ("output high while COUNT > COMPARE"), and EXPIRED is included for uniformity only
    // (COUNT==0 there by construction, so the comparison is never true regardless).
    // Operands read in the active region -- xsim samples bound module *ports* as X in the
    // preponed region, so we can't use $sampled/$past on count/pwm across the port -- and
    // compare against the DUT's registered pwm. `pwm` is bound to the internal pwm_q reg.
    logic pwm_exp;
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn)         pwm_exp <= 1'b0;
        else if (soft_reset)  pwm_exp <= 1'b0;
        else if (module_en)   pwm_exp <= pwm_en & (state_o != S_IDLE) & (count > compare_shadow);
    end
    a_pwm_rule: assert property (@(posedge pclk) disable iff (!presetn)
        (pwm == pwm_exp));
    // freeze: state + count hold while module disabled (errata 12.3)
    a_freeze_hold: assert property (@(posedge pclk) disable iff (!presetn || soft_reset)
        (!module_en) |=> ($stable(count) && $stable(state_o)));

    // -------------------------------------------------------------------------------------
    // VP-CH-COUNT-VALUE / VP-PWM-SHADOW: predict compare_shadow/count from the `compare`/
    // `period` PORTS, independently of the DUT's own compare_shadow/count registers.
    //
    // Mirror `state_o` one cycle back (used to detect the exact LOAD-entry / EXPIRED->LOAD
    // edge without $past on a port) and independently reconstruct `start_trig`
    // (ch_en_rise | (ch_start & ch_en)) from the ch_en/ch_start ports, mirroring the DUT's
    // own ch_en_q register with our own — this is a parallel re-derivation from the PORTS,
    // not a read of the DUT's internal register, so it stays independent of the mutation
    // class this checker targets.
    // -------------------------------------------------------------------------------------
    logic [2:0]  state_prev;
    logic        ch_en_q_mirror;
    logic        ch_start_pending_mirror;
    logic        start_trig_mirror;

    // F4 fix companions (2026-09-19): this module's independent re-derivation of
    // start_trig must track the CORRECTED intended semantics (a CH_EN rising edge or a
    // CH_START pulse arriving during a freeze is HELD, not lost -- see pmtpc4_channel.sv's
    // F4 fix comment for the full incident) so this checker predicts the FIXED DUT's
    // behavior, not the pre-fix one. Re-derived independently from the ch_en/ch_start
    // PORTS with the same corrected gating, never by reading the DUT's own
    // ch_en_q/ch_start_pending registers -- that would defeat the whole point of an
    // independent checker.
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            state_prev              <= S_IDLE;
            ch_en_q_mirror          <= 1'b0;
            ch_start_pending_mirror <= 1'b0;
        end else begin
            state_prev <= state_o;
            if (module_en) ch_en_q_mirror <= ch_en;   // held across a freeze, matching the fix
            if (ch_start) ch_start_pending_mirror <= 1'b1;
            else if (module_en && start_trig_mirror) ch_start_pending_mirror <= 1'b0;
        end
    end
    assign start_trig_mirror = (ch_en & ~ch_en_q_mirror) | (ch_start_pending_mirror & ch_en);

    // LOAD-entry decision cycle (combinational, current cycle): either IDLE->LOAD via
    // start_trig, or EXPIRED->LOAD via a live, periodic CH_MODE at the tick_en evaluation.
    // Both gated by module_en/!soft_reset/!ch_en-disable, matching the RTL's priority order
    // (reset > soft_reset > freeze > ch_en-disable > normal case).
    wire load_decision = module_en && !soft_reset &&
                          ((state_o == S_IDLE && start_trig_mirror) ||
                           (state_o == S_EXP  && ch_en && tick_en && ch_mode));

    logic [15:0] compare_r, period_r;
    logic        load_entry_r;     // registered: was `load_decision` true LAST cycle?
    logic [15:0] count_prev;       // registered: count as of LAST cycle
    logic        dec_cond_r;       // registered: did LAST cycle satisfy the decrement condition?
    logic        retain_cond_r;    // registered: did LAST cycle guarantee count is UNCHANGED now?
    logic        exp_eval_cond_r;  // registered: was LAST cycle an EXPIRED tick_en evaluation?
    logic        mode_live_r;      // registered: ch_mode as sampled LAST cycle (live at eval)

    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            compare_r       <= '0;
            period_r        <= '0;
            load_entry_r    <= 1'b0;
            count_prev      <= '0;
            dec_cond_r      <= 1'b0;
            retain_cond_r   <= 1'b0;
            exp_eval_cond_r <= 1'b0;
            mode_live_r     <= 1'b0;
        end else begin
            compare_r    <= compare;
            period_r     <= period;
            load_entry_r <= load_decision;
            count_prev   <= count;

            dec_cond_r <= module_en && !soft_reset && ch_en &&
                          (state_o == S_RUN) && !ch_pause && tick_en && (count != '0);

            // retain_cond_r: LAST cycle guaranteed count is UNCHANGED this cycle -- covers
            // soft-disable (untouched), LOAD (never touches count), PAUSED (always held),
            // RUNNING-but-not-decrementing, EXPIRED-not-reloading, and IDLE-not-starting.
            retain_cond_r <= module_en && !soft_reset &&
                             ( (!ch_en && state_o != S_IDLE) ||
                               (ch_en &&
                                 ( (state_o == S_LOAD) ||
                                   (state_o == S_PAUSED) ||
                                   (state_o == S_RUN  && (ch_pause || !tick_en || count == '0)) ||
                                   (state_o == S_EXP  && !(tick_en && ch_mode)) ||
                                   (state_o == S_IDLE && !start_trig_mirror) ) ) );

            exp_eval_cond_r <= module_en && !soft_reset && ch_en && (state_o == S_EXP) && tick_en;
            mode_live_r     <= ch_mode;
        end
    end

    // ---------------------------------------------------------------------------------------
    // xsim samples a BOUND-MODULE PORT inside a concurrent-assertion property using the
    // *preponed* region, and that preponed sample of a wide port (count/compare/period/
    // compare_shadow/state_o) on this bind is unreliable (this is the same issue the existing
    // a_pwm_rule comment documents for count/pwm; empirically re-confirmed this session: a
    // property mixing a bare port with a same-module local register produced false failures
    // even for known-good RTL). The fix used throughout this file: NEVER reference a bound
    // port bare inside a property. Every port is mirrored, at least once, into a local
    // register (a plain procedural read — verified correct against a ground-truth $display
    // trace) and an extra register stage is added to the condition signals above so that
    // ALL operands compared inside a property are LOCAL registers, never a bare port.
    // ---------------------------------------------------------------------------------------
    logic [15:0] cshadow_prev;      // compare_shadow as of LAST cycle (safe local mirror)
    logic [15:0] compare_r2, period_r2, count_prev2;
    logic        load_entry_r2, dec_cond_r2, retain_cond_r2, exp_eval_cond_r2, mode_live_r2;

    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            cshadow_prev     <= '0;
            compare_r2       <= '0;
            period_r2        <= '0;
            count_prev2      <= '0;
            load_entry_r2    <= 1'b0;
            dec_cond_r2      <= 1'b0;
            retain_cond_r2   <= 1'b0;
            exp_eval_cond_r2 <= 1'b0;
            mode_live_r2     <= 1'b0;
        end else begin
            cshadow_prev     <= compare_shadow;
            compare_r2       <= compare_r;
            period_r2        <= period_r;
            count_prev2      <= count_prev;
            load_entry_r2    <= load_entry_r;
            dec_cond_r2      <= dec_cond_r;
            retain_cond_r2   <= retain_cond_r;
            exp_eval_cond_r2 <= exp_eval_cond_r;
            mode_live_r2     <= mode_live_r;
        end
    end

    // a_shadow_latches_input: the cycle after a LOAD-entry decision, compare_shadow must
    // equal the `compare` PORT value sampled at the decision cycle — NOT the DUT's own
    // compare_shadow. Catches `compare_shadow <= '0` immediately. (All-local-operand form:
    // cshadow_prev/compare_r2 are one-cycle-older mirrors than compare_shadow/compare_r, and
    // load_entry_r2 is load_entry_r delayed to match — see comment above.)
    a_shadow_latches_input: assert property (@(posedge pclk) disable iff (!presetn)
        load_entry_r2 |-> (cshadow_prev == compare_r2));

    // a_count_loads_period: same transition, count must equal the `period` PORT value
    // sampled at the decision cycle — NOT period+anything. Catches `count <= period + 1`.
    a_count_loads_period: assert property (@(posedge pclk) disable iff (!presetn)
        load_entry_r2 |-> (count_prev == period_r2));

    // a_count_decrements: in RUNNING with tick_en && count!=0, count == count-1.
    a_count_decrements: assert property (@(posedge pclk) disable iff (!presetn)
        dec_cond_r2 |-> (count_prev == count_prev2 - 16'd1));

    // a_count_retained: on cycles without tick_en, while paused/frozen/soft-disabled/LOAD-
    // holding, count must be exactly unchanged (not merely "didn't glitch").
    a_count_retained: assert property (@(posedge pclk) disable iff (!presetn)
        retain_cond_r2 |-> (count_prev == count_prev2));

    // VP-PWM-SHADOW-DEFER (Design 7.4): a PERIOD or COMPARE write while RUNNING or
    // PAUSED takes effect only at the NEXT LOAD, never immediately -- compare_shadow
    // (mirrored via cshadow_prev, never the bare port) must be STABLE throughout
    // RUN/PAUSED. Under today's correct RTL this is true by construction (nothing in
    // S_RUNNING/S_PAUSED ever touches compare_shadow), which is exactly why it is a
    // real regression guard against a future edit that applied the shadow early --
    // and why the scenario needs deliberate mid-run COMPARE/PERIOD writes to be a
    // non-vacuous exercise of the antecedent, not just a trivially-true check.
    a_shadow_holds_midrun: assert property (@(posedge pclk) disable iff (!presetn)
        (state_prev inside {S_RUN, S_PAUSED}) |-> $stable(cshadow_prev));

    // VP-CH-MODE-LIVE / errata 12.2: at the EXPIRED evaluation tick, the next state follows
    // the LIVE ch_mode sampled at that exact evaluation, not any latched/earlier value.
    a_mode_live: assert property (@(posedge pclk) disable iff (!presetn)
        exp_eval_cond_r2 |-> (state_prev == (mode_live_r2 ? S_LOAD : S_IDLE)));

    // F1/F14 fix companion (2026-09-19): pwm must read 0 whenever the channel was IDLE
    // last cycle. This is a DEDICATED PROPERTY, not covergroup-based -- see
    // pmtpc4_pwm_cov.sv's header and reports/coverage_waivers.md for why
    // cg_pwm.cp_pwm_by_state.idle_high's covergroup sampling proved unreliable (confirmed
    // empirically: a temporary Active-region diagnostic never saw {state==IDLE, pwm_q==1}
    // in the exact same run where the covergroup credited a hit, even after two extra
    // register-mirror stages) even though the RTL itself is proven correct. `pwm` is read
    // bare here deliberately, matching a_pwm_rule's own already-proven-reliable pattern
    // (a property comparing a bare bound port against a local register works reliably in
    // this file; it is specifically this file's *covergroups* that don't sample bound ports
    // the same way). This assertion is the real regression guard for REQ-OUT-1 / SPEC-PWM-1's
    // "forced low ... channel IDLE" clause; the covergroup bin stays for visibility but is no
    // longer the only thing standing behind this invariant.
    a_pwm_low_in_idle: assert property (@(posedge pclk) disable iff (!presetn)
        (state_prev == S_IDLE) |-> !pwm);

    // -------------------------------------------------------------------------------------
    // VP-CH-MODE-LIVE coverage: sticky "CH_MODE changed since this run's LOAD" bit, cleared
    // at LOAD entry and set if ch_mode ever differs from its LOAD-entry value while
    // RUNNING/PAUSED, sampled at the RUNNING->EXPIRED edge.
    // -------------------------------------------------------------------------------------
    logic mode_at_load;
    logic mode_changed_sticky;
    wire  load_entry_now = (state_prev != S_LOAD) && (state_o == S_LOAD);

    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            mode_at_load         <= 1'b0;
            mode_changed_sticky  <= 1'b0;
        end else if (load_entry_now) begin
            mode_at_load        <= ch_mode;
            mode_changed_sticky <= 1'b0;
        end else if (state_o == S_RUN || state_o == S_PAUSED) begin
            if (ch_mode != mode_at_load) mode_changed_sticky <= 1'b1;
        end
    end
    wire run_to_exp_edge = (state_prev == S_RUN) && (state_o == S_EXP);

    covergroup cg_fsm @(posedge pclk);
        option.per_instance = 1;   // ch0-3 report independently instead of merging the TYPE score
        cp_state: coverpoint state_o iff (presetn) {
            bins idle={S_IDLE}; bins load={S_LOAD}; bins run={S_RUN};
            bins paused={S_PAUSED}; bins exp={S_EXP};
        }
        cp_trans: coverpoint state_o iff (presetn) {
            bins idle_load   = (S_IDLE  => S_LOAD);
            bins load_run    = (S_LOAD  => S_RUN);
            bins load_paused = (S_LOAD  => S_PAUSED);
            bins run_paused  = (S_RUN   => S_PAUSED);
            bins run_exp     = (S_RUN   => S_EXP);
            bins run_idle    = (S_RUN   => S_IDLE);
            bins paused_run  = (S_PAUSED=> S_RUN);
            bins paused_idle = (S_PAUSED=> S_IDLE);
            bins exp_idle    = (S_EXP   => S_IDLE);
            bins exp_load    = (S_EXP   => S_LOAD);
        }
        // VP-FREEZE-STATES: which state the freeze (module_en=0) happened from.
        cp_frozen_state: coverpoint state_o iff (presetn && !module_en) {
            bins idle    = {S_IDLE};
            bins load    = {S_LOAD};
            bins running = {S_RUN};
            bins paused  = {S_PAUSED};
            bins expired = {S_EXP};
        }
        // VP-CH-MODE-LIVE / errata 12.2: sampled only at the RUNNING->EXPIRED edge.
        cp_mode_at_expiry: coverpoint ch_mode iff (presetn && run_to_exp_edge) {
            bins oneshot  = {1'b0};
            bins periodic = {1'b1};
        }
        cp_mode_changed_run: coverpoint mode_changed_sticky iff (presetn && run_to_exp_edge) {
            bins changed_midrun = {1'b1};
            bins unchanged      = {1'b0};
        }
        // F15 fix (2026-09-20 audit -- see reports/coverage_waivers.md "Tier 3"): a `cross`
        // with no `iff` of its own samples at the COVERGROUP's own sample event (every
        // posedge pclk), NOT gated by its constituent coverpoints' individual iff guards --
        // same bug class found and fixed across pmtpc4_pwm_cov.sv's crosses, confirmed there
        // empirically via a ~560x hit-count discrepancy between a gated coverpoint and its
        // ungated cross. Fixed by giving the cross the same iff its coverpoints already have.
        x_mode_live: cross cp_mode_at_expiry, cp_mode_changed_run iff (presetn && run_to_exp_edge);
    endgroup
    cg_fsm fsm_cov = new();
endmodule
