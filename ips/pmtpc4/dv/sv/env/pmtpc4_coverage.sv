// PMTPC-4 configuration/functional coverage (transaction-based).
// Covers the programmed values that shape behavior; white-box FSM/PWM coverage is
// collected by the bound sva/ modules, and APB protocol coverage by the VIP.
class pmtpc4_coverage extends uvm_subscriber #(apb_item);
    `uvm_component_utils(pmtpc4_coverage)
    apb_item tr;

    function bit is_ch(bit [7:0] a, bit [7:0] off);
        return (a==(8'h20+off))||(a==(8'h30+off))||(a==(8'h40+off))||(a==(8'h50+off));
    endfunction

    covergroup cg_cfg;
        option.per_instance = 1;
        cp_prescaler: coverpoint tr.data[15:0] iff (tr.write && tr.addr[7:0]==8'h10)
            { bins zero={0}; bins one={1}; bins mid={[2:16'hFFFE]}; bins max={16'hFFFF}; }
        cp_period: coverpoint tr.data[15:0] iff (tr.write && is_ch(tr.addr[7:0],8'h04))
            { bins zero={0}; bins one={1}; bins mid={[2:16'hFFFE]}; bins max={16'hFFFF}; }
        cp_compare: coverpoint tr.data[15:0] iff (tr.write && is_ch(tr.addr[7:0],8'h08))
            { bins zero={0}; bins mid={[1:16'hFFFE]}; bins max={16'hFFFF}; }
        cp_mode: coverpoint tr.data[1] iff (tr.write && is_ch(tr.addr[7:0],8'h00))
            { bins oneshot={0}; bins periodic={1}; }
        cp_pwm_en: coverpoint tr.data[2] iff (tr.write && is_ch(tr.addr[7:0],8'h00))
            { bins off={0}; bins on={1}; }
        cp_pause: coverpoint tr.data[4] iff (tr.write && is_ch(tr.addr[7:0],8'h00))
            { bins run={0}; bins pause={1}; }
        cp_gie: coverpoint tr.data[0] iff (tr.write && tr.addr[7:0]==8'h08)
            { bins dis={0}; bins en={1}; }
        cp_inten: coverpoint tr.data[3:0] iff (tr.write && tr.addr[7:0]==8'h64)
            { bins none={0}; bins some={[1:14]}; bins all={15}; }
        cp_moduleen: coverpoint tr.data[0] iff (tr.write && tr.addr[7:0]==8'h00)
            { bins dis={0}; bins en={1}; }
    endgroup

    // =================================================================================
    // VP-SELFCLR (errata 12.5): transaction-level, purely from the write/read STREAM
    // the scoreboard already sees -- no new SVA ports needed (per the vplan's own
    // implementation note: "record a write that set the bit, then classify the next
    // read of the same address by how many cycles later it landed").
    //
    // VP-RST-SOFT cp_soft_cleared: classified from READ-SHADOWS of CH0_COUNT/
    // INT_STATUS/STATUS.BUSY updated as this subscriber observes those addresses
    // being read -- legitimate because pmtpc4_soft_reset_vseq deliberately reads all
    // three immediately before pulsing SOFT_RESET (its own preconditions). NOT
    // modelled here (left as directed-test-only checks, honestly not claimed as
    // covergroup bins): cp_soft_preserved and cp_soft_during -- both would need
    // either duplicate PRESCALER/CLK_SEL shadow bookkeeping that only restates what
    // the directed test already asserts, or true bus-phase-overlap detection this
    // transaction-level (one-item-at-a-time) subscriber structurally cannot see.
    // =================================================================================
    typedef enum { SC_NONE, SC_SOFT_RESET, SC_CH_START0, SC_CH_START1, SC_CH_START2, SC_CH_START3 } selfclr_e;
    selfclr_e  pending_kind = SC_NONE;
    bit [7:0]  pending_addr;
    realtime   pending_time;

    selfclr_e  samp_selfclr_bit;
    int        samp_latency_ns;
    bit        selfclr_sample_valid;

    bit [15:0] count0_shadow, int_status_shadow;
    bit        busy_shadow;
    bit        soft_reset_sample_valid;

    function selfclr_e classify_write_selfclr(apb_item t);
        bit [7:0] a = t.addr[7:0];
        if (!t.write) return SC_NONE;
        if (a == 8'h00 && t.data[1]) return SC_SOFT_RESET;
        if (t.data[3]) begin
            case (a)
                8'h20: return SC_CH_START0;
                8'h30: return SC_CH_START1;
                8'h40: return SC_CH_START2;
                8'h50: return SC_CH_START3;
                default: return SC_NONE;
            endcase
        end
        return SC_NONE;
    endfunction

    covergroup cg_selfclr;
        option.per_instance = 1;
        cp_selfclr_bit: coverpoint samp_selfclr_bit iff (selfclr_sample_valid) {
            bins soft_reset  = {SC_SOFT_RESET};
            bins ch_start_ch0 = {SC_CH_START0};
            bins ch_start_ch1 = {SC_CH_START1};
            bins ch_start_ch2 = {SC_CH_START2};
            bins ch_start_ch3 = {SC_CH_START3};
        }
        // "immediate_next_transfer" = the read is the VERY NEXT bus transfer after the
        // self-clearing write, with no idle cycle between them (an APB back-to-back
        // pair: ACCESS -> SETUP with PSEL held, driven by apb_agent_cfg.b2b_enable +
        // apb_item.back_to_back / pmtpc4_base_vseq::raw_b2b()).
        //
        // BOUNDARY CORRECTED 2026-09-18 (was {[0:19]} / {[20:$]}, which made
        // immediate_next_transfer UNREACHABLE and is why it sat at 0 hits). These
        // latencies are measured between the two transfers' COMPLETION instants (the
        // monitor publishes an item on the clock edge that ends its ACCESS phase), and
        // an APB3 transfer occupies a minimum of TWO clocks (SETUP + ACCESS). So the
        // smallest possible write->next-read gap is exactly 2 clock periods = 20ns at
        // 100MHz, and "< 20ns" can never happen for ANY stimulus. The intent was always
        // "within two clock periods"; the bin now says that. A non-chained pair costs a
        // third clock (the driver's idle cycle before SETUP) and lands at >= 30ns.
        // TIGHTENED 2026-09-19 (verification-reviewer): {[0:20]} still silently admitted
        // the impossible 0-19ns range, so any future bug producing a <20ns gap would be
        // MISREAD as extra "immediate_next_transfer" coverage rather than flagged. The
        // value is exactly one number by construction; pin the bin to it and make the
        // impossible range `illegal_bins` so it is a violation, not a coverage credit.
        cp_read_latency: coverpoint samp_latency_ns iff (selfclr_sample_valid) {
            bins immediate_next_transfer = {20};
            bins delayed                 = {[21:$]};
            illegal_bins impossible_fast = {[0:19]};   // < 2 clocks: cannot happen if the bus model is correct
        }
        // F15 audit (2026-09-20 -- see reports/coverage_waivers.md "Tier 3"): checked for the
        // same missing-iff cross bug found elsewhere in this codebase, and this one is NOT an
        // instance of it -- this covergroup has no clocking event, so it only samples via an
        // explicit .sample() call from write(), and that call site itself is already gated
        // (`if (selfclr_sample_valid) cg_selfclr.sample();`, below). The cross and its
        // coverpoints' iff are therefore redundant with each other, not mismatched; left as
        // coverpoint-level iff without adding one to the cross, to avoid implying a fix where
        // none was needed.
        x_selfclr: cross cp_selfclr_bit, cp_read_latency;
    endgroup

    // Three independent boolean coverpoints (rather than one packed value) so each
    // vplan-named bin (count_nonzero/int_status_nonzero/fsm_non_idle) is a direct,
    // unambiguous bin instead of a range-with-expression trick.
    covergroup cg_reset_soft;
        option.per_instance = 1;
        cp_soft_cleared_count: coverpoint (count0_shadow != 0) iff (soft_reset_sample_valid) {
            bins count_nonzero = {1'b1}; bins count_zero = {1'b0};
        }
        cp_soft_cleared_intstat: coverpoint (int_status_shadow != 0) iff (soft_reset_sample_valid) {
            bins int_status_nonzero = {1'b1}; bins int_status_zero = {1'b0};
        }
        cp_soft_cleared_fsm: coverpoint busy_shadow iff (soft_reset_sample_valid) {
            bins fsm_non_idle = {1'b1}; bins fsm_idle = {1'b0};
        }
    endgroup

    function new(string n, uvm_component p);
        super.new(n, p); cg_cfg = new(); cg_selfclr = new(); cg_reset_soft = new();
    endfunction

    function void write(apb_item t);
        tr = t;
        cg_cfg.sample();

        // ---- read-shadows for cp_soft_cleared's preconditions ----
        if (!t.write) begin
            if (t.addr[7:0] == 8'h2C) count0_shadow     = t.rdata[15:0]; // CH0_COUNT
            if (t.addr[7:0] == 8'h60) int_status_shadow = t.rdata[15:0]; // INT_STATUS
            if (t.addr[7:0] == 8'h04) busy_shadow       = t.rdata[0];    // STATUS.BUSY
        end
        soft_reset_sample_valid = (t.write && t.addr[7:0]==8'h00 && t.data[1]);
        if (soft_reset_sample_valid) cg_reset_soft.sample();

        // ---- self-clear write/next-read latency ----
        selfclr_sample_valid = 1'b0;
        begin
            selfclr_e k = classify_write_selfclr(t);
            if (k != SC_NONE) begin
                pending_kind = k;
                pending_addr = t.addr[7:0];
                pending_time = $realtime;
            end else if (!t.write && t.addr[7:0] == pending_addr && pending_kind != SC_NONE) begin
                samp_selfclr_bit     = pending_kind;
                samp_latency_ns      = int'(($realtime - pending_time) / 1ns);
                selfclr_sample_valid = 1'b1;
                pending_kind         = SC_NONE;   // only the FIRST following read is classified
            end
        end
        if (selfclr_sample_valid) cg_selfclr.sample();
    endfunction
endclass
