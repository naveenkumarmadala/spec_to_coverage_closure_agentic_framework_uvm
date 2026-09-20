// VP-PRESC-RATIO: the shared prescaler actually divides by (PRESCALER_VAL+1)
// (REQ-CORE-6 / SPEC-PRE-1). Bound ONCE at pmtpc4 top scope (not per-channel --
// this is a property of the single shared prescaler, not of any one channel).
//
// Measures the PCLK-cycle gap between consecutive tick_en pulses directly (not via
// a full channel expiry -- a channel's expiry timing is a SEPARATE, already-checked
// consequence; measuring the prescaler's own tick spacing is both simpler and is what
// makes the vplan's "not simulation-practical end-to-end" 0xFFFF corner practical:
// waiting for one interval of 65536 cycles is fine; waiting for a whole channel
// period of that many prescaled ticks would not be).
module pmtpc4_presc_sva (
    input logic        pclk, presetn, soft_reset, module_en,
    input logic [15:0] prescaler_val,
    input logic        tick_en
);
    // gap counts PCLK cycles since the last tick_en (inclusive: the cycle tick_en
    // itself fired counts as cycle 1 of the interval that just ENDED, matching the
    // prescaler's own cnt>=prescaler_val comparison: cnt runs 0..prescaler_val, i.e.
    // prescaler_val+1 cycles, before the NEXT tick_en).
    logic [31:0] gap;
    logic [15:0] presc_at_interval_start;
    logic        presc_changed_midrun;
    // An interval interrupted by freeze (module_en=0, errata 12.3) holds the
    // prescaler's OWN `cnt`, so `gap` is no longer comparable to
    // presc_at_interval_start+1 even though PRESCALER_VAL itself never changed --
    // this is a SEPARATE reason to skip the exact-ratio check from a PRESCALER_VAL
    // change, and needs its own sticky flag (empirically found this session:
    // a mid-run freeze produced a false failure before this flag was added).
    // F15/F5-desync fix (2026-09-20 audit -- see reports/coverage_waivers.md "Tier 3"):
    // soft_reset used to also zero this mirror's gap (matching the pre-F5 RTL, which
    // zeroed the prescaler's own cnt on soft_reset). After F5's fix, soft_reset no
    // longer touches the prescaler's cnt/tick_en at all -- this mirror was not updated
    // when that RTL fix landed, so it was needlessly, incorrectly SKIPPING the ratio
    // check across every soft_reset (a false negative, not a false positive, which is
    // why the regression stayed green despite the desync -- but it silently weakened
    // a_presc_ratio's effective coverage). Removed soft_reset from this condition to
    // match the corrected RTL; freeze (module_en) is unchanged and still interrupts.
    logic        presc_interrupted;

    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            gap                     <= '0;
            presc_at_interval_start <= prescaler_val;
            presc_changed_midrun    <= 1'b0;
            presc_interrupted       <= 1'b0;
        end else if (!module_en) begin
            gap               <= '0;   // prescaler itself holds cnt/tick_en while frozen
            presc_interrupted <= 1'b1;
        end else if (tick_en) begin
            gap                     <= 32'd1;
            presc_at_interval_start <= prescaler_val;
            presc_changed_midrun    <= 1'b0;
            presc_interrupted       <= 1'b0;
        end else begin
            gap <= gap + 32'd1;
            if (prescaler_val != presc_at_interval_start) presc_changed_midrun <= 1'b1;
        end
    end

    // Mirror everything one more register stage (same bare-port-safety idiom used
    // throughout dv/sv/sva/ -- see pmtpc4_channel_sva.sv's header comment) before use
    // inside a property: tick_en is a port; gap/presc_at_interval_start/
    // presc_changed_midrun are local but derived same-edge from that port, so they
    // get the same extra-stage treatment for consistency and safety.
    logic        tick_en_r;
    logic [31:0] gap_r;
    logic [15:0] presc_at_interval_start_r;
    logic        presc_changed_midrun_r;
    logic        presc_interrupted_r;

    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            tick_en_r                 <= 1'b0;
            gap_r                     <= '0;
            presc_at_interval_start_r <= '0;
            presc_changed_midrun_r    <= 1'b0;
            presc_interrupted_r       <= 1'b0;
        end else begin
            tick_en_r                 <= tick_en;
            gap_r                     <= gap;
            presc_at_interval_start_r <= presc_at_interval_start;
            presc_changed_midrun_r    <= presc_changed_midrun;
            presc_interrupted_r       <= presc_interrupted;
        end
    end

    // Only checked when nothing wrote PRESCALER_VAL mid-interval (the "unchanged"
    // bin) AND no freeze interrupted this interval -- both are SEPARATE legal cases
    // (mid-run PRESCALER_VAL change is checked only for "does not corrupt the
    // in-flight count", by the directed test; a freeze legally holds the prescaler's
    // own counter, per errata 12.3) -- asserting an exact ratio through either would
    // over-constrain legal behavior. soft_reset is NOT one of these cases (F5, 2026-
    // 09-19): it does not touch the prescaler at all, so a ratio interval spanning a
    // soft_reset pulse is fully checkable and intentionally NOT exempted here.
    a_presc_ratio: assert property (@(posedge pclk) disable iff (!presetn)
        (tick_en_r && !presc_changed_midrun_r && !presc_interrupted_r) |->
        (gap_r == presc_at_interval_start_r + 32'd1));

    covergroup cg_presc @(posedge pclk);
        option.per_instance = 1;
        cp_presc_at_run: coverpoint presc_at_interval_start iff (presetn && tick_en) {
            bins div1 = {16'h0000};
            bins div2 = {16'h0001};
            bins mid  = {[16'h0002:16'hFFFE]};
            bins max  = {16'hFFFF};
        }
        cp_presc_change_run: coverpoint presc_changed_midrun iff (presetn && tick_en) {
            bins changed_midrun = {1'b1};
            bins unchanged      = {1'b0};
        }
        // F15 fix (2026-09-20 audit -- see reports/coverage_waivers.md "Tier 3"): a `cross`
        // with no `iff` of its own samples at the covergroup's own sample event (every
        // posedge pclk), not gated by its constituent coverpoints' individual iff guards --
        // same bug class found and fixed across pmtpc4_pwm_cov.sv/pmtpc4_channel_sva.sv's
        // crosses. Fixed by giving the cross the same iff its coverpoints already have.
        x_presc: cross cp_presc_at_run, cp_presc_change_run iff (presetn && tick_en);
    endgroup
    cg_presc presc_cov = new();
endmodule
