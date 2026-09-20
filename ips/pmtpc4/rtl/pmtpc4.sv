// pmtpc4 — top level (SPEC-ARCH-1). APB3 4-channel timer/PWM controller.
// Integrates: APB slave wrapper, PeakRDL passthrough regblock (register file + RAL source),
// shared prescaler, four channel cores, and the interrupt aggregator.
module pmtpc4 (
    input  logic        pclk,
    input  logic        presetn,     // async active-low system reset (REQ-RST-1)
    // APB3 slave port
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [7:0]  paddr,
    input  logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic        pready,
    output logic        pslverr,
    // IP outputs
    output logic [3:0]  pwm_out,
    output logic        irq
);
    import pmtpc4_regblock_pkg::*;

    // ---- regblock passthrough CPU interface ----
    logic        cpuif_req, cpuif_req_is_wr;
    logic [6:0]  cpuif_addr;
    logic [31:0] cpuif_wr_data, cpuif_wr_biten;
    // cpuif_wr_data (2026-09-20, item 3 of the toggle-coverage residual audit -- see
    // reports/coverage_waivers.md "Tier 3"/item 3): TRIED eliminating this wire via a
    // hierarchical port reference (u_rb's input connected directly to u_apb.cpuif_wr_data,
    // no top-level net) to match the technique that fixed cpuif_rd_data_pad. REVERTED after
    // the full static gate caught a real problem the syntax checker alone did not: Verible
    // and Verilator both accepted it cleanly, but `yosys` (via the project's mandatory sv2v
    // pre-flatten step) reported "Resizing cell port pmtpc4.u_rb.s_cpuif_wr_data from 1 bits
    // to 32 bits" -- sv2v does not correctly preserve a hierarchical port reference's width
    // when flattening SystemVerilog to Verilog, silently defaulting to 1 bit. That would have
    // been a severe, synthesis-breaking correctness bug (write data truncated to 1 bit) had
    // it gone in without running the full lint -> elaboration gate, not just a syntax check.
    // Left as the documented, accepted tool artifact it already was; not fixed.
    // cpuif_rd_data is split into active/pad halves -- no combined 32-bit
    // signal is declared at all, so there is nothing redundant left for a
    // coverage exclusion to either miss or over-waive. Every register/field
    // in this IP's map is <=16 bits wide (see pmtpc4_regblock.sv's readback
    // mux: no readback_data_var write ever touches a bit above 15), so bits
    // [31:16] of the 32-bit APB readback word are permanently zero by
    // construction, not by stimulus limitation.
    logic [15:0] cpuif_rd_data_active;  // real field-readback bits (toggles)
    logic [15:0] cpuif_rd_data_pad;     // always zero -- see comment above

    // ---- regblock hardware interface ----
    pmtpc4__in_t  hwif_in;
    pmtpc4__out_t hwif_out;

    // ---- global control / shared signals ----
    wire         module_en      = hwif_out.CTRL.MODULE_EN.value;
    wire         soft_rst_pulse = hwif_out.CTRL.SOFT_RESET.value;   // 1-cycle (singlepulse)
    logic        tick_en;
    logic        global_int_status;

    // ---- per-channel nets ----
    logic [15:0] ch_count  [4];
    logic        ch_busy   [4];
    logic        ch_expiry [4];
    logic        ch_en_clr [4];
    logic [2:0]  ch_state  [4];
    logic        ch_pwm    [4];

    // ------------------------------------------------------------------
    // APB slave wrapper + register block
    // ------------------------------------------------------------------
    pmtpc4_apb_slave u_apb (
        .pclk, .presetn,
        .psel, .penable, .pwrite, .paddr, .pwdata, .prdata, .pready, .pslverr,
        .cpuif_req, .cpuif_req_is_wr, .cpuif_addr,
        .cpuif_wr_data, .cpuif_wr_biten,
        .cpuif_rd_data ({cpuif_rd_data_pad, cpuif_rd_data_active})
    );

    // The regblock is generated with the "passthrough" cpuif variant (no
    // wait-states, single-cycle ack): its req_stall_wr/rd, rd_ack/err, and
    // wr_ack/err ports always resolve combinationally to constants and carry
    // no information the APB wrapper needs, so they are intentionally left
    // unconnected. Scoped waiver -- not a blanket suppression.
    /* verilator lint_off PINCONNECTEMPTY */
    pmtpc4_regblock u_rb (
        .clk               (pclk),
        .arst_n            (presetn),
        .s_cpuif_req       (cpuif_req),
        .s_cpuif_req_is_wr (cpuif_req_is_wr),
        .s_cpuif_addr      (cpuif_addr),
        .s_cpuif_wr_data   (cpuif_wr_data),
        .s_cpuif_wr_biten  (cpuif_wr_biten),
        .s_cpuif_req_stall_wr (),
        .s_cpuif_req_stall_rd (),
        .s_cpuif_rd_ack    (),
        .s_cpuif_rd_err    (),
        .s_cpuif_rd_data   ({cpuif_rd_data_pad, cpuif_rd_data_active}),
        .s_cpuif_wr_ack    (),
        .s_cpuif_wr_err    (),
        .hwif_in           (hwif_in),
        .hwif_out          (hwif_out)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    // ------------------------------------------------------------------
    // Shared prescaler
    // ------------------------------------------------------------------
    pmtpc4_prescaler #(.PW(16)) u_pre (
        .pclk, .presetn,
        .soft_reset   (soft_rst_pulse),
        .module_en    (module_en),
        .prescaler_val(hwif_out.PRESCALER.PRESCALER_VAL.value),
        .tick_en      (tick_en)
    );

    // ------------------------------------------------------------------
    // Four channel cores
    // ------------------------------------------------------------------
    pmtpc4_channel #(.CW(16)) u_ch0 (
        .pclk, .presetn, .soft_reset(soft_rst_pulse), .module_en, .tick_en,
        .ch_en   (hwif_out.CH0.CH_CTRL.CH_EN.value),
        .ch_mode (hwif_out.CH0.CH_CTRL.CH_MODE.value),
        .pwm_en  (hwif_out.CH0.CH_CTRL.PWM_EN.value),
        .ch_start(hwif_out.CH0.CH_CTRL.CH_START.value),
        .ch_pause(hwif_out.CH0.CH_CTRL.CH_PAUSE.value),
        .period  (hwif_out.CH0.CH_PERIOD.PERIOD_VAL.value),
        .compare (hwif_out.CH0.CH_COMPARE.COMPARE_VAL.value),
        .count   (ch_count[0]), .busy(ch_busy[0]), .expiry(ch_expiry[0]),
        .ch_en_clr(ch_en_clr[0]), .state_o(ch_state[0]), .pwm(ch_pwm[0])
    );
    pmtpc4_channel #(.CW(16)) u_ch1 (
        .pclk, .presetn, .soft_reset(soft_rst_pulse), .module_en, .tick_en,
        .ch_en   (hwif_out.CH1.CH_CTRL.CH_EN.value),
        .ch_mode (hwif_out.CH1.CH_CTRL.CH_MODE.value),
        .pwm_en  (hwif_out.CH1.CH_CTRL.PWM_EN.value),
        .ch_start(hwif_out.CH1.CH_CTRL.CH_START.value),
        .ch_pause(hwif_out.CH1.CH_CTRL.CH_PAUSE.value),
        .period  (hwif_out.CH1.CH_PERIOD.PERIOD_VAL.value),
        .compare (hwif_out.CH1.CH_COMPARE.COMPARE_VAL.value),
        .count   (ch_count[1]), .busy(ch_busy[1]), .expiry(ch_expiry[1]),
        .ch_en_clr(ch_en_clr[1]), .state_o(ch_state[1]), .pwm(ch_pwm[1])
    );
    pmtpc4_channel #(.CW(16)) u_ch2 (
        .pclk, .presetn, .soft_reset(soft_rst_pulse), .module_en, .tick_en,
        .ch_en   (hwif_out.CH2.CH_CTRL.CH_EN.value),
        .ch_mode (hwif_out.CH2.CH_CTRL.CH_MODE.value),
        .pwm_en  (hwif_out.CH2.CH_CTRL.PWM_EN.value),
        .ch_start(hwif_out.CH2.CH_CTRL.CH_START.value),
        .ch_pause(hwif_out.CH2.CH_CTRL.CH_PAUSE.value),
        .period  (hwif_out.CH2.CH_PERIOD.PERIOD_VAL.value),
        .compare (hwif_out.CH2.CH_COMPARE.COMPARE_VAL.value),
        .count   (ch_count[2]), .busy(ch_busy[2]), .expiry(ch_expiry[2]),
        .ch_en_clr(ch_en_clr[2]), .state_o(ch_state[2]), .pwm(ch_pwm[2])
    );
    pmtpc4_channel #(.CW(16)) u_ch3 (
        .pclk, .presetn, .soft_reset(soft_rst_pulse), .module_en, .tick_en,
        .ch_en   (hwif_out.CH3.CH_CTRL.CH_EN.value),
        .ch_mode (hwif_out.CH3.CH_CTRL.CH_MODE.value),
        .pwm_en  (hwif_out.CH3.CH_CTRL.PWM_EN.value),
        .ch_start(hwif_out.CH3.CH_CTRL.CH_START.value),
        .ch_pause(hwif_out.CH3.CH_CTRL.CH_PAUSE.value),
        .period  (hwif_out.CH3.CH_PERIOD.PERIOD_VAL.value),
        .compare (hwif_out.CH3.CH_COMPARE.COMPARE_VAL.value),
        .count   (ch_count[3]), .busy(ch_busy[3]), .expiry(ch_expiry[3]),
        .ch_en_clr(ch_en_clr[3]), .state_o(ch_state[3]), .pwm(ch_pwm[3])
    );

    // ------------------------------------------------------------------
    // Interrupt aggregation (SPEC-INT-1 / REQ-INT-2, REQ-OUT-2)
    // ------------------------------------------------------------------
    // int_status_val/int_en_val/masked (2026-09-20, item 3 of the toggle-coverage residual
    // audit -- see reports/coverage_waivers.md "Tier 3"/item 3): TRIED inlining these into
    // global_int_status's assignment and deleting all three wires, matching the technique
    // that fixed cpuif_rd_data_pad. REVERTED after measuring the actual effect (same
    // regression that caught start_trig/pwm_level's identical problem in pmtpc4_channel.sv):
    // xcrg tracks sub-expression toggle points for inline boolean expressions separately,
    // and unlike a named signal, an anonymous expression cannot be waived by name -- the
    // existing `signal -int_status_val` / `signal -int_en_val` waivers matched nothing once
    // the wires were gone. Restored as named wires.
    wire [3:0] int_status_val = { hwif_out.INT_STATUS.CH_INT_STATUS3.value,
                                  hwif_out.INT_STATUS.CH_INT_STATUS2.value,
                                  hwif_out.INT_STATUS.CH_INT_STATUS1.value,
                                  hwif_out.INT_STATUS.CH_INT_STATUS0.value };
    wire [3:0] int_en_val = hwif_out.INT_ENABLE.CH_INT_EN.value;
    wire       global_ie  = hwif_out.GLOBAL_IE.GLOBAL_INT_EN.value;
    wire [3:0] masked     = int_status_val & int_en_val;

    assign global_int_status = global_ie & (|masked);
    assign irq               = global_int_status;

    // ------------------------------------------------------------------
    // Drive regblock hardware inputs
    // ------------------------------------------------------------------
    always_comb begin
        // NOTE: a bare `'0` scalar assign to an unpacked-struct signal fails to
        // codegen on Verilator (through at least 5.038; C++ operator= mismatch),
        // so use an explicit assignment pattern instead -- semantically
        // identical, and still synthesizable (Yosys/sv2v handle both forms fine).
        hwif_in = '{default: '0};
        hwif_in.STATUS.BUSY.next  = module_en & (ch_busy[0] | ch_busy[1] | ch_busy[2] | ch_busy[3]);
        hwif_in.STATUS.READY.next = module_en & ~soft_rst_pulse;
        hwif_in.GLOBAL_ISR.GLOBAL_INT_STATUS.next = global_int_status;

        hwif_in.CH0.CH_CTRL.CH_EN.hwclr = ch_en_clr[0];
        hwif_in.CH1.CH_CTRL.CH_EN.hwclr = ch_en_clr[1];
        hwif_in.CH2.CH_CTRL.CH_EN.hwclr = ch_en_clr[2];
        hwif_in.CH3.CH_CTRL.CH_EN.hwclr = ch_en_clr[3];

        hwif_in.CH0.CH_COUNT.COUNT_VAL.next = ch_count[0];
        hwif_in.CH1.CH_COUNT.COUNT_VAL.next = ch_count[1];
        hwif_in.CH2.CH_COUNT.COUNT_VAL.next = ch_count[2];
        hwif_in.CH3.CH_COUNT.COUNT_VAL.next = ch_count[3];

        // Interrupt latch. SOFT_RESET clears the interrupt state (Design 9 / REQ-RST-2).
        // F6 correction (2026-09-19 audit, see reports/coverage_waivers.md "Tier 2"): an
        // earlier version of this comment cited "Design 7.4" for "an expiry pending in that
        // same cycle must NOT be latched" -- checked directly, Section 7.4 is the
        // PERIOD/COMPARE/CH_START edge-case list and states no such requirement; there is no
        // spec text mandating this specific outcome. It is nonetheless the only reasonable
        // reading of "soft reset clears the interrupt state" (Section 9) with no stated
        // exception for a same-cycle expiry, so the gate below is kept as a deliberate design
        // choice, not a spec-cited one. The generated field logic evaluates hwset before
        // hwclr (verified directly in rdl/generated/rtl/pmtpc4_regblock.sv), so without this
        // gate a same-cycle collision would let the expiry win instead; the expiry pulse is
        // gated here (`& ~soft_rst_pulse`) to make the soft-reset clear win instead, and this
        // AND-gate is also what makes hwset and this hwclr structurally mutually exclusive at
        // the regblock, independent of the regblock's own (opposite) internal precedence.
        hwif_in.INT_STATUS.CH_INT_STATUS0.hwset = ch_expiry[0] & ~soft_rst_pulse;
        hwif_in.INT_STATUS.CH_INT_STATUS1.hwset = ch_expiry[1] & ~soft_rst_pulse;
        hwif_in.INT_STATUS.CH_INT_STATUS2.hwset = ch_expiry[2] & ~soft_rst_pulse;
        hwif_in.INT_STATUS.CH_INT_STATUS3.hwset = ch_expiry[3] & ~soft_rst_pulse;

        hwif_in.INT_STATUS.CH_INT_STATUS0.hwclr = soft_rst_pulse;
        hwif_in.INT_STATUS.CH_INT_STATUS1.hwclr = soft_rst_pulse;
        hwif_in.INT_STATUS.CH_INT_STATUS2.hwclr = soft_rst_pulse;
        hwif_in.INT_STATUS.CH_INT_STATUS3.hwclr = soft_rst_pulse;
    end

    // ------------------------------------------------------------------
    // PWM outputs — forced low while MODULE_EN=0 (errata 12.3)
    // ------------------------------------------------------------------
    assign pwm_out[0] = module_en & ch_pwm[0];
    assign pwm_out[1] = module_en & ch_pwm[1];
    assign pwm_out[2] = module_en & ch_pwm[2];
    assign pwm_out[3] = module_en & ch_pwm[3];

endmodule
