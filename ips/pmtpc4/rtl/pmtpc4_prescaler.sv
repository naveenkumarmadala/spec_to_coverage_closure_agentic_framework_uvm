// pmtpc4_prescaler — shared 16-bit clock prescaler (SPEC-PRE-1 / REQ-CORE-6).
// Emits a 1-cycle tick_en every (prescaler_val+1) pclk cycles. Frozen when
// module_en=0 (errata 12.3). Uses >= compare so a mid-run decrease of
// prescaler_val takes effect on the next tick boundary.
// F5 fix (2026-09-19 audit -- see reports/coverage_waivers.md "Tier 2"): soft_reset
// previously zeroed `cnt` here too. REQ-RST-2 states soft_reset clears channel cores +
// interrupt state (COUNT, FSM, INT_STATUS) "but NOT PRESCALER/CLK_SEL/APB FSM" -- grouping
// PRESCALER with APB FSM's own explicit in-flight-state preservation reads as the whole
// prescaler block's state (this divider's phase included), not just the PRESCALER_VAL
// config register. The `soft_reset` port is left connected at the top level (see pmtpc4.sv)
// for interface symmetry with every other channel-adjacent block, but is deliberately
// unused below: this module's counter and tick_en must be completely undisturbed by a
// soft reset. (This changed the timing trick pmtpc4_freeze_states_test used to reach a
// known LOAD-state window; see that test's history for how it was reworked to poll instead
// of assuming a soft-reset-zeroed phase.)
module pmtpc4_prescaler #(
    parameter int PW = 16
)(
    input  logic          pclk,
    input  logic          presetn,      // async active-low
    input  logic          soft_reset,   // unused: see F5 fix comment above
    input  logic          module_en,
    input  logic [PW-1:0] prescaler_val,
    output logic          tick_en
);
    logic [PW-1:0] cnt;

    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            cnt     <= '0;
            tick_en <= 1'b0;
        end else if (!module_en) begin
            tick_en <= 1'b0;            // freeze: hold cnt, no ticks
        end else begin
            if (cnt >= prescaler_val) begin
                cnt     <= '0;
                tick_en <= 1'b1;
            end else begin
                cnt     <= cnt + 1'b1;
                tick_en <= 1'b0;
            end
        end
    end
endmodule
