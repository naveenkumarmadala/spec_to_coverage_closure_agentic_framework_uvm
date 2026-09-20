// VP-PWM-DUTY: PWM duty-cycle coverage + companion checkers — bound into pmtpc4_channel.
//
// Predicts duty entirely from the channel's `period`/`compare` INPUT PORTS, latched at
// LOAD entry into this module's OWN registers (per_at_load / cmp_at_load) — never from the
// DUT's compare_shadow. That independence is the whole point (per the vplan): a deliberately
// seeded `compare_shadow <= '0` at the LOAD-entry latch forces the DUT's actual `pwm` output
// high for (almost) the entire period regardless of COMPARE, while this module's prediction
// (built from `compare`/`period` ports, and `count` — a port, but NOT compare_shadow) still
// expects the real, non-degenerate duty — so a_pwm_matches_independent fails immediately.
//
// Two independent things are checked/measured here, deliberately kept separate:
//   1. a_pwm_matches_independent: a CONTINUOUS, per-cycle check (same technique as
//      pmtpc4_channel_sva.sv's a_pwm_rule) that the DUT's actual registered `pwm` output
//      tracks pwm_exp_local, an independently-rebuilt copy of the SAME register that uses
//      cmp_at_load (latched from the `compare` PORT) instead of the DUT's compare_shadow.
//      This is the mutation-catching checker — it is sensitive to compare_shadow holding
//      the wrong VALUE regardless of prescaler/tick timing.
//   2. hi_ticks/per_ticks/duty_pct: a prescaler-independent duty MEASUREMENT for coverage,
//      built from the LIVE `count`/cmp_at_load comparison at each genuine RUN tick (the
//      tick whose decision would carry the FSM to EXPIRED is excluded — that tick belongs
//      to "count==0 -> EXPIRED", not a duty-bearing RUN sample, matching the vplan's own
//      "COUNT==0 tick is the EXPIRED entry" language). a_duty_compare_zero / a_duty_full_low
//      / a_duty_matches_cmp assert exact relationships on this measurement; because it reads
//      `count` live (not the DUT's registered `pwm`, whose apparent value at a tick_en
//      instant depends on how much settling time the prescaler gives it between ticks),
//      these three are prescaler-independent by construction.
//
// Sampling model:
//   - At the LOAD-entry DECISION cycle (state_o==IDLE with start_trig, or state_o==EXP with
//     a live periodic reload — the SAME cycle the DUT itself samples period/compare for its
//     count<=period / compare_shadow<=compare, one cycle before state_o is first OBSERVED as
//     LOAD), latch per_at_load <= period, cmp_at_load <= compare, reset the accumulators.
//   - On every tick_en while module_en && state_o==S_RUN && count!=0: per_ticks++,
//     hi_ticks++ if count > cmp_at_load.
//   - At the RUNNING->EXPIRED edge, duty_pct = hi_ticks*100/per_ticks (guard 0); cg_pwm's
//     period-close coverpoints sample once.
//   - cp_pwm_by_state samples every pclk (the {state,level} pair directly).
module pmtpc4_pwm_cov (
    input logic        pclk, presetn, soft_reset, module_en, tick_en,
    input logic        ch_en, ch_mode, pwm_en, ch_start, ch_pause,
    input logic [15:0] period, compare, count,
    input logic [2:0]  state_o,
    input logic        pwm
);
    typedef enum logic [2:0] {
        S_IDLE, S_LOAD, S_RUN, S_PAUSED, S_EXP
    } ch_state_e;

    typedef enum logic [2:0] {
        DUTY_PERIOD_ZERO, DUTY_CMP_ZERO, DUTY_CMP_LT, DUTY_CMP_EQ, DUTY_CMP_GT
    } duty_class_e;

    function automatic duty_class_e classify_duty(logic [15:0] per_v, logic [15:0] cmp_v);
        if (per_v == '0)             return DUTY_PERIOD_ZERO;
        else if (cmp_v == '0)        return DUTY_CMP_ZERO;
        else if (cmp_v < per_v)      return DUTY_CMP_LT;
        else if (cmp_v == per_v)     return DUTY_CMP_EQ;
        else                         return DUTY_CMP_GT;
    endfunction

    logic [2:0]  state_prev;
    logic [15:0] per_at_load, cmp_at_load;
    int unsigned hi_ticks, per_ticks;
    int unsigned duty_pct;
    duty_class_e duty_class;

    wire run_to_exp_edge = (state_prev == S_RUN)  && (state_o == S_EXP);
    // VP-CH-PERIOD0: any entry into EXPIRED (today's RTL only ever reaches it from
    // S_RUN, but written against the general "entered EXPIRED" condition so it stays
    // correct if that ever changes) -- used to measure ticks-from-LOAD-entry.
    wire exp_entry_edge  = (state_prev != S_EXP)  && (state_o == S_EXP);
    // Excludes the count==0 tick: that tick's decision carries the FSM to EXPIRED (the
    // vplan's own "COUNT==0 tick is the EXPIRED entry" framing) rather than being a genuine
    // duty-bearing RUN sample. Using the LIVE `count` port (not the registered `pwm` output)
    // makes this prescaler-independent: no reliance on how much settling time pwm_q got
    // between ticks.
    wire tick_in_run     = module_en && !soft_reset && (state_o == S_RUN) &&
                            tick_en && (count != '0);

    // -------------------------------------------------------------------------------------
    // Latch per_at_load/cmp_at_load at the exact DECISION cycle (state_o==IDLE with
    // start_trig, or state_o==EXP with a live periodic reload), matching the DUT's OWN
    // `count<=period` / `compare_shadow<=compare` NBA timing exactly (see
    // pmtpc4_channel_sva.sv's load_decision) — NOT one cycle later when state_o is first
    // OBSERVED as LOAD. Latching on the "observed LOAD" cycle instead races against an
    // in-flight PERIOD/COMPARE APB write: if the write commits on the cycle in between the
    // real decision and the observed-LOAD cycle, this module would grab a newer PERIOD/
    // COMPARE than the DUT's `count`/`compare_shadow` actually used, panicking on a totally
    // legitimate scenario (a mid-run PERIOD write picked up by the NEXT periodic reload).
    // Empirically confirmed this session: the naive "state transition to LOAD" trigger
    // produced spurious failures under exactly this race.
    // -------------------------------------------------------------------------------------
    // F4 fix companion (2026-09-19): held across a freeze (module_en gating) and CH_START
    // latched sticky, matching pmtpc4_channel.sv's corrected intended semantics -- see
    // pmtpc4_channel_sva.sv's identical fix for the full incident. Without this, this
    // module's own load_decision desyncs from the DUT's actual (now-fixed) LOAD entries
    // after any freeze-during-CH_EN/CH_START scenario, corrupting ticks_since_load/
    // per_at_load and firing spurious a_period0_expires / x_period0 violations.
    logic ch_en_q_mirror, ch_start_pending_mirror, start_trig_mirror;
    always_ff @(posedge pclk or negedge presetn)
        if (!presetn) begin
            ch_en_q_mirror          <= 1'b0;
            ch_start_pending_mirror <= 1'b0;
        end else begin
            if (module_en) ch_en_q_mirror <= ch_en;
            if (ch_start) ch_start_pending_mirror <= 1'b1;
            else if (module_en && start_trig_mirror) ch_start_pending_mirror <= 1'b0;
        end
    assign start_trig_mirror = (ch_en & ~ch_en_q_mirror) | (ch_start_pending_mirror & ch_en);

    wire load_decision = module_en && !soft_reset &&
                          ((state_o == S_IDLE && start_trig_mirror) ||
                           (state_o == S_EXP  && ch_en && tick_en && ch_mode));

    // VP-PWM-SHADOW-DEFER coverage: did a PERIOD/COMPARE write actually land while
    // this channel was RUN/PAUSED THIS period (as opposed to no write happening at
    // all, which would make the deferral claim vacuous). Sticky, cleared at the next
    // LOAD-entry decision, sampled at period close (run_to_exp_edge) alongside
    // cp_duty_class. The CHECK that the write's effect was actually deferred is
    // a_shadow_holds_midrun in pmtpc4_channel_sva.sv; this is coverage only.
    logic [15:0] compare_prev_val, period_prev_val;
    logic        cmp_written_midrun, per_written_midrun;
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            compare_prev_val   <= '0;
            period_prev_val    <= '0;
            cmp_written_midrun <= 1'b0;
            per_written_midrun <= 1'b0;
        end else begin
            if (load_decision) begin
                cmp_written_midrun <= 1'b0;
                per_written_midrun <= 1'b0;
            end else if (state_o == S_RUN || state_o == S_PAUSED) begin
                if (compare != compare_prev_val) cmp_written_midrun <= 1'b1;
                if (period  != period_prev_val)  per_written_midrun <= 1'b1;
            end
            compare_prev_val <= compare;
            period_prev_val  <= period;
        end
    end

    // VP-CH-PERIOD0: count tick_en pulses from the LOAD-entry decision (inclusive of
    // the LOAD->RUN tick itself) until EXPIRED is entered. Counting is active exactly
    // while the channel is in LOAD or RUN, matching the vplan's "ticks from LOAD entry
    // to EXPIRED" definition.
    int unsigned ticks_since_load;
    wire counting_active = module_en && !soft_reset && (state_o == S_LOAD || state_o == S_RUN);

    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            state_prev       <= S_IDLE;
            per_at_load      <= '0;
            cmp_at_load      <= '0;
            hi_ticks         <= '0;
            per_ticks        <= '0;
            ticks_since_load <= '0;
        end else begin
            state_prev <= state_o;
            if (load_decision) begin
                per_at_load      <= period;
                cmp_at_load      <= compare;
                hi_ticks         <= '0;
                per_ticks        <= '0;
                ticks_since_load <= '0;
            end else begin
                if (tick_in_run) begin
                    per_ticks <= per_ticks + 1;
                    if (count > cmp_at_load) hi_ticks <= hi_ticks + 1;
                end
                if (counting_active && tick_en) ticks_since_load <= ticks_since_load + 1;
            end
        end
    end

    always_comb begin
        duty_class = classify_duty(per_at_load, cmp_at_load);
        duty_pct   = (per_ticks == 0) ? 0 : (hi_ticks * 100) / per_ticks;
    end

    // -------------------------------------------------------------------------------------
    // a_pwm_matches_independent: the mutation-catching checker. Derived from design_spec.md
    // SPEC-PWM-1 (2026-09-19 corrected text — pwm high while PWM_EN && state!=IDLE &&
    // COUNT>COMPARE; see that file's history note and reports/coverage_waivers.md "Tier 2"
    // for the full reasoning), substituting cmp_at_load (latched from the `compare` PORT,
    // independent of the DUT's compare_shadow) for the spec's COMPARE — that substitution
    // is what makes this checker independent of pmtpc4_channel_sva.sv's a_pwm_rule, not the
    // state condition (both correctly implement the same spec formula and are expected to
    // agree on that part). `count` is a port here (safe to read procedurally, unlike inside
    // a property — see below).
    // -------------------------------------------------------------------------------------
    logic pwm_exp_local;
    wire  ch_active = (state_o != S_IDLE);
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn)         pwm_exp_local <= 1'b0;
        else if (soft_reset)  pwm_exp_local <= 1'b0;
        else if (module_en)   pwm_exp_local <= pwm_en & ch_active & (count > cmp_at_load);
    end

    // ---------------------------------------------------------------------------------------
    // xsim samples a BOUND-MODULE PORT inside a concurrent-assertion property via the
    // *preponed* region, and that preponed sample is unreliable for this bind (same issue
    // documented/re-confirmed in pmtpc4_channel_sva.sv). Fix: never reference a bare port
    // (state_o, pwm) inside a property — mirror everything into local registers first (plain
    // procedural reads, safe) and add a matching extra register stage so every operand
    // compared inside a property is a LOCAL register, never a bare port.
    // ---------------------------------------------------------------------------------------
    logic         run_to_exp_edge_r;
    duty_class_e  duty_class_r;
    int unsigned  hi_ticks_r, duty_pct_r;
    logic [15:0]  per_at_load_r, cmp_at_load_r;
    logic         pwm_exp_local_mirror, pwm_mirror;
    logic         pwm_en_prev, pwm_en_prev2;
    logic         exp_entry_edge_r;
    int unsigned  ticks_since_load_r;

    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            run_to_exp_edge_r    <= 1'b0;
            duty_class_r         <= DUTY_PERIOD_ZERO;
            hi_ticks_r           <= '0;
            duty_pct_r           <= '0;
            per_at_load_r        <= '0;
            cmp_at_load_r        <= '0;
            pwm_exp_local_mirror <= 1'b0;
            pwm_mirror           <= 1'b0;
            pwm_en_prev          <= 1'b0;
            pwm_en_prev2         <= 1'b0;
            exp_entry_edge_r     <= 1'b0;
            ticks_since_load_r   <= '0;
        end else begin
            run_to_exp_edge_r    <= run_to_exp_edge;
            duty_class_r         <= duty_class;
            hi_ticks_r           <= hi_ticks;
            duty_pct_r           <= duty_pct;
            per_at_load_r        <= per_at_load;
            cmp_at_load_r        <= cmp_at_load;
            pwm_exp_local_mirror <= pwm_exp_local;
            pwm_mirror           <= pwm;
            pwm_en_prev          <= pwm_en;
            pwm_en_prev2         <= pwm_en_prev;
            exp_entry_edge_r     <= exp_entry_edge;
            ticks_since_load_r   <= ticks_since_load;
        end
    end

    // The mutation-catching checker (see header comment): continuous, every cycle, both
    // operands local registers (never a bare port), so no dependence on the xsim
    // preponed-sampling issue and no dependence on prescaler settling time either — it
    // mirrors the DUT's OWN one-cycle-registered timing exactly, just with an independent
    // compare source.
    a_pwm_matches_independent: assert property (@(posedge pclk) disable iff (!presetn)
        (pwm_mirror == pwm_exp_local_mirror));

    // ---- Duty-VALUE checkers (prescaler-independent measurement — see header). ----
    a_duty_compare_zero: assert property (@(posedge pclk) disable iff (!presetn)
        (run_to_exp_edge_r && duty_class_r == DUTY_CMP_ZERO) |-> (duty_pct_r == 100));

    a_duty_full_low: assert property (@(posedge pclk) disable iff (!presetn)
        (run_to_exp_edge_r && (duty_class_r inside {DUTY_CMP_EQ, DUTY_CMP_GT})) |->
        (hi_ticks_r == 0));

    a_duty_matches_cmp: assert property (@(posedge pclk) disable iff (!presetn)
        (run_to_exp_edge_r && duty_class_r == DUTY_CMP_LT) |->
        (hi_ticks_r == (per_at_load_r - cmp_at_load_r)));

    // a_pwm_off: with PWM_EN off (as of the cycle whose comparison pwm's CURRENT registered
    // value reflects — pwm is one cycle behind its inputs, same reasoning as a_pwm_rule),
    // pwm must read low. (Already implied transitively by a_pwm_matches_independent, since
    // pwm_exp_local is itself gated by pwm_en — stated explicitly here for VP-PWM-DUTY
    // traceability.) Gated on module_en: per errata 12.3, pwm_q FREEZES (holds its last
    // value, doesn't re-evaluate pwm_en) while module_en=0, so writing PWM_EN=0 during a
    // freeze with pwm already latched high is legal behavior, not a violation -- not
    // currently reachable by any test, but this closes the gap before someone writes one.
    a_pwm_off: assert property (@(posedge pclk) disable iff (!presetn || !module_en)
        !pwm_en_prev2 |-> !pwm_mirror);

    // VP-CH-PAUSE-PWM: DIRECT checker for "while PAUSED, pwm_out holds its frozen
    // LEVEL" (Design 7.3). Prior to this, the hold was only proven INDIRECTLY via
    // a_pwm_matches_independent tracking pwm_exp_local, which itself goes stable
    // once ch_active/count go stable in PAUSED — never a property that states the
    // PAUSED-hold invariant on its own. Stated directly here, on the DUT's own `pwm`
    // (mirrored, per this file's bare-port rule): state_o==S_PAUSED && module_en
    // implies pwm does not change on the next edge. Gated on module_en per the same
    // errata-12.3 freeze reasoning as a_pwm_off (module_en=0 stops re-evaluation of
    // pwm entirely, a different, already-covered invariant — a_freeze_hold).
    //
    // ANTECEDENT NARROWED 2026-09-18 (needs TWO consecutive PAUSED cycles, not one).
    // Found by new stimulus, not by inspection: pmtpc4_pwm_shadow_vseq's
    // compare_write_while_paused() parks a channel in PAUSED by entering it straight
    // from LOAD (errata 12.1, CH_EN|CH_PAUSE written together) instead of from
    // RUNNING, which is the only entry path any earlier test used. `pwm` is pwm_q,
    // registered one cycle behind pwm_level, and S_LOAD lasts exactly one cycle -- so
    // on the FIRST PAUSED cycle pwm_q still carries the value computed while the FSM
    // was in S_IDLE (ch_active=0 => low), and it settles to the level implied by the
    // frozen COUNT on the second. That one-cycle settle is the SAME registration
    // artifact this file already documents for cp_pwm_by_state.load_high, not a change
    // of the level being frozen: the invariant Design 7.3 states is about the level
    // being HELD, and the level is not established until pwm_q has had its one cycle.
    // Requiring two consecutive PAUSED cycles expresses exactly that and costs no
    // sensitivity -- any pwm change during a sustained PAUSED still fires, including
    // the seeded PAUSED-state re-evaluation this assertion was written to catch.
    logic is_paused_prev, is_paused_prev2;
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            is_paused_prev  <= 1'b0;
            is_paused_prev2 <= 1'b0;
        end else begin
            is_paused_prev  <= (state_o == S_PAUSED);
            is_paused_prev2 <= is_paused_prev;
        end
    end
    a_pwm_stable_in_paused: assert property (@(posedge pclk) disable iff (!presetn)
        (is_paused_prev && is_paused_prev2 && module_en) |-> $stable(pwm_mirror));

    // VP-CH-PERIOD0: PERIOD=0 loads COUNT=0 and expires on the very next tick — no
    // lock-up (Design 4, SPEC-CH-1). ticks_since_load_r counts the LOAD->RUN tick and
    // the RUN->EXPIRED tick, so a healthy PERIOD=0 channel reaches EXPIRED in exactly 2.
    a_period0_expires: assert property (@(posedge pclk) disable iff (!presetn)
        (exp_entry_edge_r && per_at_load_r == 16'h0000) |-> (ticks_since_load_r <= 2));

    covergroup cg_pwm @(posedge pclk);
        option.per_instance = 1;

        cp_duty_class: coverpoint duty_class iff (presetn && run_to_exp_edge) {
            bins period_zero       = {DUTY_PERIOD_ZERO};
            bins compare_zero      = {DUTY_CMP_ZERO};
            bins compare_lt_period = {DUTY_CMP_LT};
            bins compare_eq_period = {DUTY_CMP_EQ};
            bins compare_gt_period = {DUTY_CMP_GT};
        }
        // Sampled at the same instant as cp_duty_class so the cross reflects one coherent
        // period's (duty_class, pwm_en) pair.
        cp_pwm_en: coverpoint pwm_en iff (presetn && run_to_exp_edge) {
            bins off = {1'b0};
            bins on  = {1'b1};
        }
        cp_measured_duty: coverpoint duty_pct iff (presetn && run_to_exp_edge) {
            bins zero_pct = {0};
            bins low      = {[1:24]};
            bins mid      = {[25:74]};
            bins high     = {[75:99]};
            bins full     = {100};
        }
        // Every pclk: the {state, pwm level} pair, incl. paused_high for the frozen-level
        // requirement (VP-CH-PAUSE-PWM).
        //
        // SAMPLED FROM {state_prev, pwm_mirror}, NOT the bare bound ports {state_o, pwm}
        // (2026-09-19 fix): a real, if incomplete, improvement -- routing through these
        // already-existing one-cycle mirrors (also used by a_pwm_matches_independent,
        // a_pwm_stable_in_paused) is more correct than the original bare-port form, even
        // though it did not, on its own, fully resolve idle_high below (see that bin's note).
        //
        // idle_high/exp_high/load_high classifications, each independently investigated
        // 2026-09-19, not assumed from one another:
        //
        //   idle_high: `ignore_bins`, NOT illegal_bins (downgraded 2026-09-19). The RTL
        //     itself is proven correct by a direct, independent method: a temporary
        //     Active-region diagnostic inside pmtpc4_channel.sv (checking
        //     state==S_IDLE && pwm_q directly, no covergroup involved) recorded ZERO hits
        //     across the identical regression run where THIS covergroup's idle_high bin
        //     still credited one -- proven not just once but after trying both a single
        //     mirror stage (state_prev/pwm_mirror) and a second, doubly-registered stage,
        //     neither of which stopped the covergroup from crediting it. This points at a
        //     genuine SystemVerilog scheduling-region difference (a covergroup with an
        //     explicit clocking event samples in the Observed region, which runs after this
        //     same edge's NBA updates commit, differently from any Active-region procedural
        //     reader of the identical signals) rather than a code mistake -- but the exact
        //     xsim mechanics were not fully pinned down, so this is downgraded on the
        //     strength of the independent RTL proof, not a full explanation. The real
        //     regression guard is now `a_pwm_low_in_idle` in pmtpc4_channel_sva.sv (a
        //     dedicated property, which -- like the already-reliable a_pwm_rule in the same
        //     file -- reads the bare `pwm` port directly rather than through this
        //     covergroup's sampling path). See reports/coverage_waivers.md for the full
        //     investigation trail.
        //   exp_high: stays `illegal_bins`. count==0 throughout S_EXP by construction
        //     (EXPIRED is entered only when count hits 0, and nothing touches count again
        //     until the next LOAD), so count>compare_shadow is false regardless of
        //     compare_shadow's value -- NOT re-investigated for the same covergroup-sampling
        //     question idle_high had, since it has never been observed to fire (unlike
        //     idle_high, which was proven to fire despite the RTL being correct); revisit if
        //     it ever does.
        //   load_high: RESOLVED 2026-09-19 -- no longer illegal. design_spec.md SPEC-PWM-1
        //     was corrected (the Tier 2 spec-vs-RTL question): pwm high while state!=IDLE
        //     (not just RUNNING||PAUSED), because REQ-CORE-3 itself carries no state
        //     qualifier and COUNT already holds the just-reloaded PERIOD during LOAD, making
        //     COUNT>COMPARE a real, meaningful, legitimately-true comparison there. `load_high`
        //     is therefore a genuine, expected, positively-covered bin now, not a violation --
        //     see design_spec.md's own history note and reports/coverage_waivers.md "Tier 2"
        //     for the full audit trail that reached this conclusion.
        cp_pwm_by_state: coverpoint {state_prev, pwm_mirror} iff (presetn) {
            bins idle_low    = {{S_IDLE,    1'b0}};
            bins load_low    = {{S_LOAD,    1'b0}};
            bins load_high   = {{S_LOAD,    1'b1}};
            bins run_high    = {{S_RUN,     1'b1}};
            bins run_low     = {{S_RUN,     1'b0}};
            bins paused_high = {{S_PAUSED,  1'b1}};
            bins paused_low  = {{S_PAUSED,  1'b0}};
            bins exp_low     = {{S_EXP,     1'b0}};
            ignore_bins  idle_high = {{S_IDLE, 1'b1}};
            illegal_bins exp_high  = {{S_EXP,  1'b1}};
        }
        // F15 fix (2026-09-20 audit -- see reports/coverage_waivers.md "Tier 3"): a `cross`
        // with no `iff` of its own samples at the COVERGROUP's sample event (every posedge
        // pclk here), NOT gated by its constituent coverpoints' individual iff guards --
        // confirmed empirically: before this fix, this cross's total cell hit count was
        // 102510 across a regression where cp_duty_class's own (correctly gated) total was
        // only 183, a ~560x discrepancy. The cross was silently combining whatever
        // duty_class/pwm_en held on EVERY cycle, not just at run_to_exp_edge as the adjacent
        // coverpoints' own comment ("sampled at the same instant... so the cross reflects one
        // coherent period's pair") already intended -- its "100% covered" was never proof
        // every combination was seen AT an actual expiry, just that clock-rate noise
        // eventually filled every cell. Fixed by giving the cross its own matching iff.
        x_duty_class_pwm_en: cross cp_duty_class, cp_pwm_en iff (presetn && run_to_exp_edge);

        // VP-CH-PERIOD0: PERIOD value latched at LOAD entry x how many ticks it took
        // to reach EXPIRED. period=0 must land in two_ticks per a_period0_expires
        // above (one_tick is structurally impossible -- see cp_expired_after).
        cp_period_at_load: coverpoint per_at_load iff (presetn && exp_entry_edge) {
            bins zero    = {16'h0000};
            bins one     = {16'h0001};
            bins smallp  = {[16'h0002:16'h00FF]};
            bins largep  = {[16'h0100:16'hFFFF]};
        }
        // one_tick is STRUCTURALLY UNREACHABLE, not under-stimulated: EXPIRED can
        // only be entered from S_RUNNING (the RTL's case statement has no other
        // path to S_EXPIRED), and S_RUNNING can only be entered by S_LOAD consuming
        // one tick_en first. So ticks_since_load (which starts counting at the
        // LOAD-entry decision, inclusive of that LOAD->RUN tick) is AT LEAST 2 by
        // construction -- even PERIOD=0 needs that first LOAD->RUN tick plus one
        // more RUN tick to observe count==0. Confirmed empirically this session:
        // 0 hits after the PERIOD=1/large-PERIOD natural-completion stimulus added
        // to pmtpc4_cov_close_vseq closed cp_period_at_load's other two bins.
        cp_expired_after: coverpoint ticks_since_load iff (presetn && exp_entry_edge) {
            illegal_bins one_tick = {1};
            bins two_ticks        = {2};
            bins many             = {[3:$]};
        }
        // Two of this cross's eight cells are STRUCTURALLY UNREACHABLE, for the same
        // reason cp_expired_after.one_tick is (the tick accounting below), not because
        // nothing has stimulated them yet, and BOTH are backed by a live checker the
        // same way one_tick is -- so both are `illegal_bins` (a real assertion-style
        // violation if ever sampled), not `ignore_bins` (silently discards the sample
        // and gives up the free detection). [2026-09-19: a verification-reviewer audit
        // found the nonzero cell using ignore_bins was an unmotivated asymmetry with
        // one_tick's illegal_bins for the identical reasoning -- fixed by matching it,
        // and the zero/many cell converted alongside it for the same reason.] Kept in
        // the covergroup rather than dv/pmtpc4_cov_exclusions.txt -- that file is for
        // CODE coverage; functional-coverage impossibilities belong here. See
        // reports/coverage_waivers.md ("Functional ignore_bins") for the sign-off record.
        //
        //   (zero, many): a_period0_expires (above) asserts per_at_load==0 |->
        //     ticks_since_load <= 2, and one_tick is already illegal_bins, so PERIOD=0
        //     reaches EXPIRED in EXACTLY 2 ticks. "many" ({[3:$]}) with PERIOD=0 would
        //     be an a_period0_expires FAILURE first; this illegal_bin is the matching
        //     coverage-side statement of the same fact.
        //
        //   ({one,smallp,largep}, two_ticks): a full expiry costs exactly (PERIOD+2)
        //     ticks by RTL construction (pmtpc4_channel.sv): S_LOAD consumes one tick
        //     to reach S_RUNNING without touching COUNT, then S_RUNNING needs
        //     (PERIOD+1) more ticks to walk COUNT from PERIOD down to 0 and observe
        //     count=='0. So ticks_since_load == PERIOD+2 >= 3 for every nonzero PERIOD;
        //     only PERIOD==0 can ever land in two_ticks. (Same (PERIOD+2) accounting
        //     used by pmtpc4_prescaler_vseq::time_expiry's bound.) Backed by
        //     a_count_loads_period / a_count_decrements (sva/pmtpc4_channel_sva.sv),
        //     which a mutation seeding `count<='0` at LOAD entry confirms fire.
        // F15 fix (2026-09-20 audit): same missing-iff bug as x_duty_class_pwm_en above --
        // this cross has no iff of its own, so it was sampling every posedge pclk instead of
        // only at exp_entry_edge like cp_period_at_load/cp_expired_after themselves.
        x_period0: cross cp_period_at_load, cp_expired_after iff (presetn && exp_entry_edge) {
            illegal_bins zero_is_never_many =
                binsof(cp_period_at_load.zero) && binsof(cp_expired_after.many);
            illegal_bins nonzero_is_never_two_ticks =
                (binsof(cp_period_at_load.one)    ||
                 binsof(cp_period_at_load.smallp) ||
                 binsof(cp_period_at_load.largep)) && binsof(cp_expired_after.two_ticks);
        }

        // VP-PWM-SHADOW-DEFER coverage.
        cp_cmp_write_timing: coverpoint cmp_written_midrun iff (presetn && run_to_exp_edge) {
            bins no_write_this_period          = {1'b0};
            bins write_midrun_effect_deferred  = {1'b1};
        }
        cp_per_write_timing: coverpoint per_written_midrun iff (presetn && run_to_exp_edge) {
            bins no_write_this_period          = {1'b0};
            bins write_midrun_effect_deferred  = {1'b1};
        }
        // F15 fix (2026-09-20 audit): same missing-iff bug.
        x_cmp_write_duty: cross cp_cmp_write_timing, cp_duty_class iff (presetn && run_to_exp_edge);
    endgroup
    cg_pwm pwm_cov = new();
endmodule
