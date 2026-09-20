// Top-level assertions — bound into pmtpc4: IRQ aggregation, freeze, reset.
module pmtpc4_top_sva (
    input logic       pclk, presetn, module_en,
    input logic [3:0] int_status_val, int_en_val,
    input logic       global_ie, global_int_status, irq,
    input logic [3:0] pwm_out,
    // VP-RST-ASYNC: per-channel FSM state + APB phase pins, sampled only at the
    // instant reset asserts, to record WHAT was interrupted (Design 6 / REQ-RST-1
    // "from any state"). ch_state uses the pmtpc4_channel state_e encoding
    // (S_IDLE=0, S_LOAD=1, S_RUNNING=2, S_PAUSED=3, S_EXPIRED=4).
    input logic [2:0] ch_state0, ch_state1, ch_state2, ch_state3,
    input logic       psel, penable,
    // VP-INT-SETPRI / VP-INT-W1C / VP-INT-SIMUL: per-channel expiry pulse + the
    // regblock's INT_STATUS sw-write strobe (address/data), needed to distinguish a
    // hw-set from a sw-clear and to detect the same-cycle collision (errata/Design 7.2).
    input logic [3:0] ch_expiry,
    input logic       cpuif_req, cpuif_req_is_wr,
    input logic [6:0] cpuif_addr,
    input logic [31:0] cpuif_wr_data,
    input logic        soft_reset,
    // F7-verif (2026-09-19 audit -- see reports/coverage_waivers.md "Tier 2"): no
    // checker anywhere in the regression had ever proven STATUS.BUSY/READY correct for
    // channels 1-3 specifically -- every existing chk() against ral.STATUS reads
    // channel 0's contribution only (pmtpc4_soft_reset_vseq.sv, pmtpc4_channel_vseq.sv,
    // pmtpc4_async_reset_vseq.sv). Bound here as a CONTINUOUS property instead of a new
    // directed test: this retroactively validates every existing test that already
    // exercises channels 1-3 (pmtpc4_pwm_all_channels_test, pmtpc4_freeze_states_test,
    // etc.), not just a fresh one written to target this gap.
    input logic [3:0]  ch_busy,
    input logic        status_busy_val, status_ready_val
);
    wire exp_int = global_ie & (|(int_status_val & int_en_val));

    a_irq_aggregation: assert property (@(posedge pclk) disable iff (!presetn)
        irq == exp_int);
    a_gisr_readback:   assert property (@(posedge pclk) disable iff (!presetn)
        global_int_status == exp_int);
    a_freeze_pwm_low:  assert property (@(posedge pclk) disable iff (!presetn)
        (!module_en) |-> (pwm_out == 4'b0000));
    a_reset_outputs_low: assert property (@(posedge pclk)
        (!presetn) |-> (pwm_out == 4'b0000 && irq == 1'b0));

    // SPEC-INT-1 (design_spec.md section 7): "STATUS.BUSY = |(channel busy) ... and 0
    // while MODULE_EN=0. STATUS.READY = module_en & ~soft_reset_active." Independently
    // re-derived from ch_busy/module_en/soft_reset ports (never read from pmtpc4.sv's
    // own hwif_in.STATUS assignment -- these two ports ARE that assignment's RHS, bound
    // in specifically so this checker tests it, not restates it).
    a_status_busy:  assert property (@(posedge pclk) disable iff (!presetn)
        status_busy_val  == (module_en & (|ch_busy)));
    a_status_ready: assert property (@(posedge pclk) disable iff (!presetn)
        status_ready_val == (module_en & ~soft_reset));

    // Positive evidence, not just absence of failure: prove each channel was actually
    // observed as the SOLE contributor to BUSY at some point (closes the "channels 1-3
    // never independently proven" half of F7-verif with real coverage, not just a
    // property that never fired).
    covergroup cg_status_busy @(posedge pclk);
        option.per_instance = 1;
        cp_sole_busy: coverpoint ch_busy iff (presetn && module_en) {
            bins ch0_only = {4'b0001};
            bins ch1_only = {4'b0010};
            bins ch2_only = {4'b0100};
            bins ch3_only = {4'b1000};
            bins none      = {4'b0000};
            bins multiple  = default;
        }
    endgroup
    cg_status_busy status_busy_cov = new();

    // -------------------------------------------------------------------------------
    // VP-RST-ASYNC coverage: what state was interrupted, and what APB bus phase was
    // in flight, at the instant reset asserted. Sampled on the falling edge of
    // presetn itself (not @(posedge pclk)) -- that is the one instant that matters,
    // and it is exactly asynchronous, so a pclk-edge-sampled covergroup would miss an
    // async_delay!=0 assertion that lands off the clock edge.
    // -------------------------------------------------------------------------------
    typedef enum logic [2:0] { S_IDLE, S_LOAD, S_RUNNING, S_PAUSED, S_EXPIRED } ch_state_e;

    function automatic ch_state_e any_active_state();
        if (ch_state0 != S_IDLE) return ch_state_e'(ch_state0);
        if (ch_state1 != S_IDLE) return ch_state_e'(ch_state1);
        if (ch_state2 != S_IDLE) return ch_state_e'(ch_state2);
        if (ch_state3 != S_IDLE) return ch_state_e'(ch_state3);
        return S_IDLE;
    endfunction

    typedef enum { APB_BUS_IDLE, APB_MID_SETUP, APB_MID_ACCESS } apb_phase_e;
    function automatic apb_phase_e apb_phase_at_reset();
        if (!psel)    return APB_BUS_IDLE;
        if (!penable) return APB_MID_SETUP;
        return APB_MID_ACCESS;
    endfunction

    covergroup cg_reset @(negedge presetn);
        option.per_instance = 1;
        cp_state_at_reset: coverpoint any_active_state() {
            bins idle    = {S_IDLE};
            bins load    = {S_LOAD};
            bins running = {S_RUNNING};
            bins paused  = {S_PAUSED};
            bins expired = {S_EXPIRED};
        }
        cp_apb_at_reset: coverpoint apb_phase_at_reset() {
            bins bus_idle  = {APB_BUS_IDLE};
            bins mid_setup = {APB_MID_SETUP};
            bins mid_access = {APB_MID_ACCESS};
        }
        x_reset: cross cp_state_at_reset, cp_apb_at_reset;
    endgroup
    cg_reset reset_cov = new();

    // =================================================================================
    // VP-INT-SETPRI / VP-INT-W1C / VP-INT-MASK-CROSS / VP-INT-SIMUL
    // =================================================================================

    // A software W1C write hits INT_STATUS on the cycle cpuif_req/cpuif_req_is_wr/
    // cpuif_addr resolve (pmtpc4_apb_slave: cpuif_req is a single-cycle pulse in the
    // completing, non-erroring ACCESS cycle -- see that module's header comment).
    wire [3:0] w1c_write_hit = (cpuif_req && cpuif_req_is_wr && (cpuif_addr == 7'h60))
                               ? cpuif_wr_data[3:0] : 4'h0;

    // VP-INT-SETPRI (Design 7.2 / REQ-INT-1): if channel n re-expires the same cycle
    // its INT_STATUS bit is being W1C-cleared, the bit stays SET (precedence=hw in the
    // RDL). `cover property` is the natural way to confirm the race was actually
    // exercised (not vacuous) -- xsim 2025.1 does NOT support it in simulation
    // ("SystemVerilog Cover" is silently ignored at elaboration, confirmed empirically
    // this session), so a plain hit counter + a $display at end-of-sim stands in for
    // it: grep the transcript for "VP-INT-SETPRI collisions" to confirm >0.
    genvar gp;
    generate
        for (gp = 0; gp < 4; gp = gp + 1) begin : g_setpri
            a_int_set_priority: assert property (@(posedge pclk) disable iff (!presetn)
                (ch_expiry[gp] && w1c_write_hit[gp]) |=> int_status_val[gp]);

            int unsigned setpri_collision_count;
            always_ff @(posedge pclk or negedge presetn) begin
                if (!presetn) setpri_collision_count <= '0;
                else if (ch_expiry[gp] && w1c_write_hit[gp])
                    setpri_collision_count <= setpri_collision_count + 1;
            end
        end
    endgenerate
    final $display("VP-INT-SETPRI collisions: ch0=%0d ch1=%0d ch2=%0d ch3=%0d",
        g_setpri[0].setpri_collision_count, g_setpri[1].setpri_collision_count,
        g_setpri[2].setpri_collision_count, g_setpri[3].setpri_collision_count);

    // VP-INT-W1C: per-bit operation classification (hw-set / sw-clear / write-0-holds /
    // hw-set-while-already-set), one independent covergroup instance per channel bit
    // (option.per_instance stands in for the vplan's cp_bit x cp_op cross -- ch0-3
    // report separately instead of merging, exactly like cg_fsm/cg_pwm elsewhere in
    // this environment).
    typedef enum { OP_NONE, OP_SET_HW, OP_CLR_W1, OP_HOLD_W0, OP_ALREADY_SET } int_op_e;
    genvar gb;
    generate
        for (gb = 0; gb < 4; gb = gb + 1) begin : g_int_bit
            logic prev_val;
            always_ff @(posedge pclk or negedge presetn) begin
                if (!presetn) prev_val <= 1'b0;
                else          prev_val <= int_status_val[gb];
            end
            wire w0_hit = cpuif_req && cpuif_req_is_wr && (cpuif_addr == 7'h60) &&
                          !cpuif_wr_data[gb];

            function automatic int_op_e classify_op();
                if (int_status_val[gb] && !prev_val)                          return OP_SET_HW;
                if (!int_status_val[gb] && prev_val && !ch_expiry[gb] && !soft_reset)
                                                                                return OP_CLR_W1;
                if (w0_hit && prev_val && int_status_val[gb])                  return OP_HOLD_W0;
                if (ch_expiry[gb] && prev_val)                                 return OP_ALREADY_SET;
                return OP_NONE;
            endfunction

            covergroup cg_int_bit @(posedge pclk);
                option.per_instance = 1;
                cp_op: coverpoint classify_op() iff (presetn) {
                    bins set_by_hw             = {OP_SET_HW};
                    bins clr_by_w1             = {OP_CLR_W1};
                    bins hold_on_w0            = {OP_HOLD_W0};
                    bins already_set_set_again = {OP_ALREADY_SET};
                    ignore_bins none_op        = {OP_NONE};
                }
            endgroup
            cg_int_bit int_bit_cov = new();
        end
    endgenerate

    // VP-INT-MASK-CROSS / VP-INT-SIMUL: mask-state-space + simultaneous-expiry coverage.
    covergroup cg_int @(posedge pclk);
        option.per_instance = 1;
        cp_global_ie: coverpoint global_ie iff (presetn) {
            bins dis = {1'b0}; bins en = {1'b1};
        }
        cp_any_enabled_status: coverpoint (|(int_status_val & int_en_val)) iff (presetn) {
            bins none = {1'b0}; bins some = {1'b1};
        }
        cp_masked_but_latched: coverpoint ((|int_status_val) && !irq) iff (presetn) {
            bins latched_while_masked = {1'b1};
            bins not_masked           = {1'b0};
        }
        cp_irq: coverpoint irq iff (presetn) { bins lo = {1'b0}; bins hi = {1'b1}; }
        // F15 fix (2026-09-20 audit -- see reports/coverage_waivers.md "Tier 3"): same
        // missing-iff bug found and fixed across the other crosses in this codebase (a cross
        // with no iff of its own samples at the covergroup's sample event, every posedge pclk
        // here, not gated by its coverpoints' own `iff (presetn)`). Lower-severity than the
        // other instances (presetn is only false for a brief window at the very start of
        // simulation), but the same correctness principle applies.
        x_mask: cross cp_global_ie, cp_any_enabled_status iff (presetn);
        cp_n_simultaneous: coverpoint $countones(ch_expiry) iff (presetn && |ch_expiry) {
            bins one = {1}; bins two = {2}; bins three = {3}; bins four = {4};
        }
    endgroup
    cg_int int_cov = new();
endmodule
