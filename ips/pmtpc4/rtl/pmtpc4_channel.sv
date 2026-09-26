// pmtpc4_channel — one timer/PWM channel core (SPEC-CH-1 / REQ-CORE-1..8).
// FSM: IDLE -> LOAD -> RUNNING -> (PAUSED) -> EXPIRED -> IDLE|LOAD.
// Implements errata 12.1 (CH_PAUSE level-sensitive, LOAD->PAUSED),
// 12.2 (CH_MODE live-sampled at EXPIRED), and 12.3 (MODULE_EN freeze).
module pmtpc4_channel #(
    parameter int CW = 16
)(
    input  logic           pclk,
    input  logic           presetn,     // async active-low
    input  logic           soft_reset,  // 1-cycle sync pulse (clears this channel)
    input  logic           module_en,   // 0 = freeze (hold all state), pwm forced low upstream
    input  logic           tick_en,     // prescaled tick (already gated by module_en)
    // configuration (regblock hwif_out)
    input  logic           ch_en,
    input  logic           ch_mode,     // 0=one-shot, 1=periodic
    input  logic           pwm_en,
    input  logic           ch_start,    // singlepulse (1 cycle)
    input  logic           ch_pause,
    input  logic [CW-1:0]  period,
    input  logic [CW-1:0]  compare,
    // outputs
    output logic [CW-1:0]  count,
    output logic           busy,        // RUNNING/LOAD/PAUSED (unmasked)
    output logic           expiry,      // 1-cycle pulse into the interrupt aggregator
    output logic           ch_en_clr,   // 1-cycle pulse -> regblock CH_EN.hwclr
                                         // (one-shot self-clear)
    output logic [2:0]     state_o,     // FSM state (for coverage/monitor)
    output logic           pwm          // raw PWM level (top masks with module_en)
);
    typedef enum logic [2:0] {
        S_IDLE    = 3'd0,
        S_LOAD    = 3'd1,
        S_RUNNING = 3'd2,
        S_PAUSED  = 3'd3,
        S_EXPIRED = 3'd4
    } state_e;

    state_e        state;
    logic          ch_en_q;
    logic          pwm_q;
    logic [CW-1:0] compare_shadow;  // latched at LOAD entry -- see Design 7.4 below
    // F4 fix (2026-09-19 audit): CH_START is a 1-cycle singlepulse field from the regblock;
    // while module_en==0 the FSM case statement (which is the only consumer of start_trig)
    // is entirely skipped, so a pulse arriving during a freeze was simply lost -- by the time
    // the freeze lifted, the source field had already self-cleared. Latch it here so it
    // survives the freeze window, cleared exactly where it's consumed (S_IDLE's start_trig
    // branch below), not on a separate/approximate condition.
    logic          ch_start_pending;

    wire ch_en_rise = ch_en & ~ch_en_q;
    // start_trig/pwm_level (2026-09-20, item 3 of the toggle-coverage residual audit -- see
    // reports/coverage_waivers.md "Tier 3"/item 3): TRIED inlining these at their one use
    // site each and deleting the wires, matching the technique that fixed cpuif_rd_data_pad.
    // REVERTED after measuring the actual effect: pmtpc4_channel's DUT toggle score dropped
    // from 100% to 40%, not an improvement. Root cause: unlike cpuif_rd_data_pad (which split
    // one wire into two separately-DECLARED, still-NAMED signals), inlining here replaced a
    // named wire with a bare anonymous expression -- xcrg appears to track sub-expression
    // toggle points for inline boolean expressions separately, and unlike a named signal,
    // an anonymous expression cannot be waived by name in the exclusion file. The two
    // existing `signal -start_trig` / `signal -pwm_level` waivers (still in
    // dv/pmtpc4_toggle_waivers.txt) match nothing once the wires are gone -- worse than the
    // net-zero effect that sounds like, since the waiver was hiding a 0/0 that no longer
    // exists while new, unwaived anonymous points appeared instead. Restored as named wires.
    wire start_trig = ch_en_rise | (ch_start_pending & ch_en);
    // A channel drives its PWM output in every non-IDLE state, per design_spec.md
    // SPEC-PWM-1 (2026-09-19 corrected text -- see that file's own history note for the
    // full reasoning, and reports/coverage_waivers.md "Tier 2" for the audit that found
    // it). REQ-CORE-3 itself carries no state qualifier ("output high while COUNT >
    // COMPARE") -- LOAD is included because COUNT already holds the just-reloaded PERIOD
    // there (the same value software reads back via CHx_COUNT that very cycle), so
    // COUNT > COMPARE is a real, meaningful comparison, not a don't-care. (An earlier
    // version of this comment justified LOAD's inclusion by a "one-tick notch" timing
    // argument -- that specific claim was independently checked and found technically
    // incorrect during the audit, though the conclusion to include LOAD was right anyway,
    // for the REQ-CORE-3 reason above.) EXPIRED is included for uniformity only -- COUNT
    // is 0 there by construction, so the comparison is never true regardless.
    wire ch_active  = (state != S_IDLE);
    // trailing-edge PWM: high while COUNT > COMPARE (REQ-CORE-3). Compares against the
    // *shadowed* compare_shadow, not the live `compare` input: Design 7.4 requires a
    // mid-RUNNING write to COMPARE (like PERIOD, already shadowed via `count <= period`
    // happening only at LOAD entry) to take effect only on the next LOAD, not immediately.
    wire pwm_level  = pwm_en & ch_active & (count > compare_shadow);

    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            state          <= S_IDLE;
            count          <= '0;
            compare_shadow <= '0;
            pwm_q          <= 1'b0;
            ch_en_q        <= 1'b0;
            expiry         <= 1'b0;
            ch_en_clr      <= 1'b0;
            ch_start_pending <= 1'b0;
        end else begin
            // F4 fix (2026-09-19 audit): hold ch_en_q across a freeze instead of tracking
            // ch_en unconditionally. Previously a CH_EN 0->1 write arriving while
            // module_en==0 was already "seen" by ch_en_q by the time the freeze lifted, so
            // the rising edge (and with it, the start) was silently lost -- the natural
            // bring-up order (disable, configure, enable CH_EN, then enable module) left
            // every channel stuck in IDLE forever. Holding ch_en_q while frozen means a
            // real transition during the freeze is still detected as a rising edge on the
            // first un-frozen cycle. Not gated on soft_reset: CH_EN is config and survives
            // soft_reset (REQ-RST-2), so soft_reset alone should not affect this tracking.
            if (module_en) ch_en_q <= ch_en;
            expiry    <= 1'b0;     // default: pulses low
            ch_en_clr <= 1'b0;
            // latch, frozen or not; cleared at consumption below
            if (ch_start) ch_start_pending <= 1'b1;

            if (soft_reset) begin
                state            <= S_IDLE;
                count            <= '0;
                compare_shadow   <= '0;
                pwm_q            <= 1'b0;
                ch_start_pending <= 1'b0;   // channel core clears with the rest of soft-reset state
            end else if (!module_en) begin
                // errata 12.3: freeze — hold state, count, and pwm level exactly.
            end else begin
                // immediate soft-disable overrides everything except reset/freeze (REQ-CORE-5)
                if (!ch_en && state != S_IDLE) begin
                    state <= S_IDLE;   // COUNT retained (not cleared)
                    // F1/F14 fix (2026-09-19 audit): force pwm low on the SAME edge the
                    // soft-disable takes state to IDLE. Previously `pwm_q <= pwm_level;`
                    // below executed unconditionally even on this path, using pwm_level
                    // computed from the PRE-disable state -- so pwm_out stayed high for
                    // one extra cycle after the channel had already returned to IDLE,
                    // violating "forced low when ... channel IDLE" (design_spec.md SPEC-PWM-1)
                    // and REQ-OUT-1. Independently confirmed by two different audit methods:
                    // design-reviewer traced the cycle timing statically; verification-reviewer
                    // found cg_pwm.cp_pwm_by_state.idle_high (documented "structurally
                    // unreachable") actually firing, by mutation, for this exact mechanism.
                    pwm_q <= 1'b0;
                end else begin
                    unique case (state)
                        S_IDLE: begin
                            if (start_trig) begin
                                count            <= period;   // load at LOAD entry
                                compare_shadow   <= compare;  // shadow COMPARE too (Design 7.4)
                                state            <= S_LOAD;
                                ch_start_pending <= 1'b0;     // consumed
                            end
                        end
                        S_LOAD: begin
                            if (tick_en) begin
                                // errata 12.1: if paused as LOAD completes -> straight to PAUSED
                                state <= ch_pause ? S_PAUSED : S_RUNNING;
                            end
                        end
                        S_RUNNING: begin
                            if (ch_pause) begin
                                state <= S_PAUSED;
                            end else if (tick_en) begin
                                if (count == '0) begin
                                    state  <= S_EXPIRED;
                                    expiry <= 1'b1;      // raise expiry event
                                end else begin
                                    count <= count - 1'b1;
                                end
                            end
                        end
                        S_PAUSED: begin
                            if (!ch_pause) state <= S_RUNNING;
                        end
                        S_EXPIRED: begin
                            if (tick_en) begin
                                if (ch_mode) begin       // errata 12.2: live CH_MODE at expiry
                                    // Periodic auto-reload goes back through LOAD, per the
                                    // Design 7.3 transition table (EXPIRED + Periodic -> LOAD).
                                    // Going straight to RUNNING would skip the LOAD tick and
                                    // make the first period one tick longer than every
                                    // subsequent one. LOAD then applies CH_PAUSE as usual.
                                    count          <= period;   // COUNT loaded from PERIOD at LOAD
                                    compare_shadow <= compare;  // shadow COMPARE too (Design 7.4)
                                    state          <= S_LOAD;
                                end else begin
                                    state     <= S_IDLE; // one-shot: self-disable
                                    ch_en_clr <= 1'b1;   // clear CH_EN in the regblock
                                end
                            end
                        end
                        default: state <= S_IDLE;
                    endcase
                end
                pwm_q <= pwm_level;
            end
        end
    end

    assign busy    = (state == S_LOAD) | (state == S_RUNNING) | (state == S_PAUSED);
    assign state_o = state;
    assign pwm     = pwm_q;
endmodule
