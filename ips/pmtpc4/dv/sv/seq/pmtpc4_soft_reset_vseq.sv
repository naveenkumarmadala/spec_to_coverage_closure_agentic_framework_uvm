// VP-RST-SOFT: CTRL.SOFT_RESET clears channel cores + interrupt state (COUNT, FSM,
// INT_STATUS) but PRESERVES PRESCALER/CLK_SEL/the APB FSM, and does not disturb an
// in-flight APB transfer (REQ-RST-2 / Design 9). Directed, self-checking against
// literal expected values -- the scoreboard's write-history shadow cannot predict a
// soft reset's effect on COUNT/INT_STATUS (dynamic, hw-driven registers; see
// pmtpc4_scoreboard.sv's readmask() comment), so the checks live here.
// The body's final block (F5, 2026-09-19) additionally proves PRESCALER preservation
// goes beyond the register value -- pmtpc4_prescaler.sv's own internal divider PHASE
// must also survive soft_reset, which no earlier check here (or anywhere else in the
// regression) had ever actually exercised.
class pmtpc4_soft_reset_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_soft_reset_vseq)
    function new(string name="pmtpc4_soft_reset_vseq"); super.new(name); endfunction

    localparam bit [31:0] EN=1, MODE=2, SOFTRST=2;

    // A soft reset forces the channel FSM (state/count/compare_shadow) back to IDLE
    // but does NOT touch the CH_CTRL register storage (CH_EN's hwclr line is only
    // pulsed by one-shot self-clear, never by soft_reset) -- so if CH_EN is already
    // 1, re-writing the SAME value produces no rising edge and the channel never
    // restarts. Toggle through 0 first to get a genuine restart, exactly as real
    // software driving this register would after a soft reset.
    task restart_ch0_periodic();
        reg_wr(chan(0).CH_CTRL, 0);
        reg_wr(chan(0).CH_CTRL, EN|MODE);
    endtask

    task body();
        uvm_reg_data_t v, presc_before, clksel_before, count_before;
        apb_item it;

        // cg_reset_soft.cp_soft_cleared_fsm.fsm_idle (the vacuous precondition case:
        // a soft reset applied while already idle) -- a 2026-09-18 functional-
        // coverage-report audit found every OTHER soft-reset pulse in the
        // regression happens while a channel is running, leaving this bin unhit.
        // Deliberately exercised here too, once, before any channel starts.
        reg_wr(p_sequencer.ral.CTRL, 32'h1);
        reg_rd(p_sequencer.ral.STATUS, v);
        chk(v[0] == 1'b0, "precondition: STATUS.BUSY must be 0 while genuinely idle");
        reg_wr(p_sequencer.ral.CTRL, 32'h1 | 32'h2);   // SOFT_RESET while idle -- vacuous, but tracked

        // ---- get INT_STATUS[1] nonzero FIRST, with a fast prescaler, before the
        // slow PRESCALER value (needed for the "preserved" checks below) is programmed ----
        reg_wr(p_sequencer.ral.PRESCALER, 0);
        reg_wr(p_sequencer.ral.CTRL, EN);
        reg_wr(chan(1).CH_PERIOD, 2);
        reg_wr(chan(1).CH_CTRL, EN);
        cyc(15);
        reg_rd(p_sequencer.ral.INT_STATUS, v);
        chk(v[1] == 1'b1, "precondition: INT_STATUS[1] must be set before the soft reset");

        // ---- program non-default PRESCALER/CLK_SEL and get COUNT/FSM non-zero ----
        reg_wr(p_sequencer.ral.PRESCALER, 16'h1234);
        reg_wr(p_sequencer.ral.CLK_SEL, 1);
        reg_wr(chan(0).CH_PERIOD, 16'h00FF);
        reg_wr(chan(0).CH_CTRL, EN|MODE);          // periodic; COUNT<=PERIOD immediately at LOAD entry
        cyc(20);

        reg_rd(chan(0).CH_COUNT, count_before);
        chk(count_before != 0, "precondition: COUNT must be nonzero before the soft reset (else the observation proves nothing)");
        reg_rd(p_sequencer.ral.PRESCALER, presc_before);
        reg_rd(p_sequencer.ral.CLK_SEL, clksel_before);
        chk(presc_before == 16'h1234 && clksel_before == 1,
            "precondition: PRESCALER/CLK_SEL must hold their programmed values before the soft reset");

        // ---- pulse SOFT_RESET from a genuinely NON-IDLE channel FSM ----
        // REQ-RST-2 is a claim about clearing the channel cores "from any state", so
        // the interesting pulse is the one issued while a channel is actually
        // LOAD/RUNNING/PAUSED/EXPIRED -- not one issued into an already-idle device.
        // STATUS.BUSY is the observable, black-box statement of that precondition, so
        // read it and require it here rather than assuming it from COUNT!=0 alone
        // (COUNT is retained across a soft-disable, so a nonzero COUNT does NOT by
        // itself prove the FSM is non-idle). This read is also what supplies
        // cg_reset_soft.cp_soft_cleared_fsm's busy_shadow: the bin fsm_non_idle was at
        // 0 hits purely because every SOFT_RESET write in the regression was preceded
        // by a STATUS read taken while idle (or by no STATUS read at all).
        reg_rd(p_sequencer.ral.STATUS, v);
        chk(v[0] == 1'b1,
            "precondition: STATUS.BUSY must be 1 (channel FSM non-IDLE) before this soft reset");
        reg_wr(p_sequencer.ral.CTRL, EN | SOFTRST);
        cyc(4);

        reg_rd(chan(0).CH_COUNT, v);
        chk(v == 0, $sformatf("COUNT must be 0 after soft reset (got 0x%0h)", v));
        reg_rd(p_sequencer.ral.STATUS, v);
        chk(v[0] == 1'b0, "STATUS.BUSY must be 0 (all FSMs IDLE) after soft reset");
        reg_rd(p_sequencer.ral.INT_STATUS, v);
        chk(v[3:0] == 4'h0, $sformatf("INT_STATUS must be cleared by soft reset (got 0x%0h)", v[3:0]));
        reg_rd(p_sequencer.ral.PRESCALER, v);
        chk(v == presc_before, $sformatf("PRESCALER must survive a soft reset (exp 0x%0h got 0x%0h)", presc_before, v));
        reg_rd(p_sequencer.ral.CLK_SEL, v);
        chk(v == clksel_before, "CLK_SEL must survive a soft reset");

        // ---- repeat, landing the pulse during an in-flight APB ACCESS phase ----
        restart_ch0_periodic();
        cyc(20);
        reg_rd(chan(0).CH_COUNT, count_before);
        chk(count_before != 0, "precondition (2nd pass): COUNT must be nonzero again");
        fork
            raw(0, 32'h10, 0, it);                  // a PRESCALER read overlapping the pulse below
            begin
                cyc(1);
                reg_wr(p_sequencer.ral.CTRL, EN | SOFTRST);
            end
        join
        chk(!it.aborted && !it.slverr,
            "an APB transfer in flight when SOFT_RESET pulses must complete normally (REQ-RST-2)");
        cyc(4);
        reg_rd(chan(0).CH_COUNT, v);
        chk(v == 0, "COUNT must be 0 after the mid-transfer soft reset too");
        reg_rd(p_sequencer.ral.PRESCALER, v);
        chk(v == presc_before, "PRESCALER must still survive a soft reset issued mid-transfer");

        reg_wr(chan(0).CH_CTRL, 0);
        reg_wr(chan(1).CH_CTRL, 0);
        reg_wr(p_sequencer.ral.PRESCALER, 0);
        reg_wr(p_sequencer.ral.CLK_SEL, 0);

        // ---- F5 (2026-09-19 audit): PRESCALER's *phase* must also survive a soft reset,
        // not just its config register value. Every check above only reads the PRESCALER
        // register (its programmed VALUE) -- none of them touch pmtpc4_prescaler.sv's own
        // free-running divider counter, so this requirement clause had never actually been
        // exercised. Prove it by DISTINGUISHING "phase preserved" from "phase reset to 0"
        // via the timing of a channel expiry started well after the soft_reset pulse: the
        // shared divider is put at a known, deliberately mid-count phase (~700 of 999) right
        // before the pulse, then a channel is started ~10 cycles after the pulse and PERIOD=0
        // (needs exactly 2 tick_en pulses -- LOAD->RUN, then RUN(count==0)->EXPIRED). If the
        // phase survived, the first tick is only ~(999-700)=~300 cycles away, so expiry
        // arrives at roughly cnt_at_pulse-away + 1000 =~ 1300 cycles after the channel start
        // -- if soft_reset had wrongly zeroed the phase (the pre-fix bug), expiry would
        // instead take close to a full 1000+1000=2000 cycles. The two outcomes differ by
        // ~700 cycles, far more than any APB write-latency slop, so a loose threshold
        // robustly discriminates them without needing cycle-exact prediction.
        begin
            uvm_reg_data_t iv;
            time t_start, t_done;
            int unsigned elapsed_cycles;
            reg_wr(p_sequencer.ral.CTRL, EN);              // module_en=1 so cnt actively pins/counts
            reg_wr(p_sequencer.ral.PRESCALER, 0);          // pin cnt at a known 0
            cyc(3);
            reg_wr(p_sequencer.ral.PRESCALER, 16'd999);    // cnt resumes counting from 0
            cyc(700);                                       // cnt now ~700 of 999 -- deliberately mid-phase
            reg_wr(p_sequencer.ral.CTRL, EN | SOFTRST);    // the pulse under test
            cyc(4);
            reg_wr(chan(0).CH_PERIOD, 16'd0);
            t_start = $time;
            reg_wr(chan(0).CH_CTRL, EN);                    // IDLE->LOAD now, ~10 cycles post-pulse
            for (int unsigned i = 0; i < 3000; i++) begin
                reg_rd(p_sequencer.ral.INT_STATUS, iv);
                if (iv[0]) break;
                cyc(1);
            end
            t_done = $time;
            chk(iv[0] == 1'b1, "CH0 never expired within the poll budget after the post-soft-reset phase check");
            elapsed_cycles = (t_done - t_start) / 10;
            chk(elapsed_cycles < 1700,
                $sformatf("PRESCALER phase must survive soft_reset: expiry took %0d cycles from channel start, expected ~1300 (phase preserved); ~2000 would mean soft_reset wrongly reset the divider's phase to 0 (F5 regression)",
                           elapsed_cycles));
            reg_wr(p_sequencer.ral.INT_STATUS, 32'h1);
            reg_wr(chan(0).CH_CTRL, 0);
            reg_wr(p_sequencer.ral.PRESCALER, 0);
        end
    endtask
endclass
