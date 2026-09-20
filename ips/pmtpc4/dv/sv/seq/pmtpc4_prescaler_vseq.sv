// VP-PRESC-RATIO: for N in {0,1,3,0x3F}, time a known-PERIOD expiry and (where the
// margin is comfortable relative to APB write jitter) bound the elapsed cycle count
// both ways; then change PRESCALER mid-RUNNING and check COUNT is not corrupted.
//
// The precise, cycle-exact ratio check is sva/pmtpc4_presc_sva.sv's a_presc_ratio
// (mutation-tested separately) -- this vseq's job is to CREATE the varied-N, varied-
// timing scenarios that exercise it (and cg_presc, which samples from the same
// bound module, not from this vseq).
class pmtpc4_prescaler_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_prescaler_vseq)
    function new(string name="pmtpc4_prescaler_vseq"); super.new(name); endfunction

    localparam bit [31:0] EN=1, MODE=2;
    localparam bit [15:0] P = 16'd3;

    task time_expiry(bit [15:0] n);
        uvm_reg_data_t v;
        // RTL trace: LOAD consumes 1 tick (IDLE->LOAD->RUNNING without touching
        // COUNT), then RUNNING takes (PERIOD+1) more ticks to walk COUNT down from
        // PERIOD to 0 and raise EXPIRED on the tick COUNT==0 is observed -- so a
        // full one-shot expiry takes (PERIOD+2) ticks, not (PERIOD+1); each tick is
        // (N+1) PCLK cycles (this is what a_presc_ratio checks directly and
        // precisely -- this vseq-level bound is deliberately looser).
        int unsigned total_expected = (int'(P) + 2) * (int'(n) + 1);
        reg_wr(p_sequencer.ral.INT_STATUS, 4'hF);
        reg_wr(p_sequencer.ral.PRESCALER, n);
        reg_wr(p_sequencer.ral.CTRL, EN);
        reg_wr(chan(0).CH_PERIOD, P);
        reg_wr(chan(0).CH_CTRL, EN);           // one-shot start

        if (total_expected > 40) begin
            cyc(total_expected - 20);
            reg_rd(p_sequencer.ral.INT_STATUS, v);
            chk(v[0] == 1'b0,
                $sformatf("PRESCALER=%0d PERIOD=%0d: expired too fast (before ~%0d cycles)",
                          n, P, total_expected - 20));
            cyc(40);
        end else begin
            cyc(total_expected + 40);
        end
        reg_rd(p_sequencer.ral.INT_STATUS, v);
        chk(v[0] == 1'b1,
            $sformatf("PRESCALER=%0d PERIOD=%0d: did not expire within margin of ~%0d cycles",
                      n, P, total_expected));
        reg_wr(chan(0).CH_CTRL, 0);
    endtask

    task midrun_change_uncorrupted();
        uvm_reg_data_t c1, c2, c3;
        reg_wr(p_sequencer.ral.PRESCALER, 16'd7);
        reg_wr(p_sequencer.ral.CTRL, EN);
        reg_wr(chan(0).CH_PERIOD, 16'h00FF);
        reg_wr(chan(0).CH_CTRL, EN|MODE);      // periodic, long period so it stays running
        cyc(60);
        reg_rd(chan(0).CH_COUNT, c1);
        reg_wr(p_sequencer.ral.PRESCALER, 16'd1);   // faster mid-run change
        cyc(4);
        reg_rd(chan(0).CH_COUNT, c2);
        chk(c2 <= c1, "COUNT must never jump upward when PRESCALER changes mid-run");
        cyc(60);
        reg_rd(chan(0).CH_COUNT, c3);
        chk(c3 < c2, "COUNT must keep advancing normally after a mid-run PRESCALER change");
        reg_wr(chan(0).CH_CTRL, 0);
        reg_wr(p_sequencer.ral.PRESCALER, 0);
    endtask

    // ---------------------------------------------------------------------------
    // cg_presc.x_presc (div1, changed_midrun).
    //
    // NOT reachable by simply writing PRESCALER while running at div1: with
    // PRESCALER_VAL=0 the prescaler's `cnt >= prescaler_val` is true every cycle, so
    // tick_en is asserted EVERY cycle, so pmtpc4_presc_sva's interval bookkeeping
    // re-latches presc_at_interval_start (and clears presc_changed_midrun) on the very
    // same cycle the new PRESCALER value appears. An interval that STARTED at div1 can
    // therefore never observe a change -- unless the interval is SUSPENDED first.
    //
    // MODULE_EN=0 does exactly that (errata 12.3): the prescaler freezes with its cnt
    // held and tick_en low, and the SVA's freeze branch leaves presc_at_interval_start
    // (=0, div1) and presc_changed_midrun (=0) untouched. A PRESCALER write taken
    // during that freeze is then a genuine mid-interval change of a div1 interval,
    // observed as soon as the module resumes. a_presc_ratio correctly stands down for
    // this interval (both its presc_changed_midrun and presc_interrupted guards fire) --
    // the exact-ratio claim does not apply across a freeze, and that is checked
    // elsewhere, not here.
    task div1_changed_midrun();
        reg_wr(p_sequencer.ral.PRESCALER, 0);
        reg_wr(p_sequencer.ral.CTRL, EN);            // free-run at div1
        cyc(10);
        reg_wr(p_sequencer.ral.CTRL, 0);             // freeze: the div1 interval stays open
        reg_wr(p_sequencer.ral.PRESCALER, 16'd40);   // mid-interval change of a div1 interval
        reg_wr(p_sequencer.ral.CTRL, EN);            // resume
        cyc(150);                                     // >= one full 41-cycle interval
        reg_wr(p_sequencer.ral.PRESCALER, 0);
    endtask

    // ---------------------------------------------------------------------------
    // cg_presc.x_presc (max, unchanged).
    //
    // cp_presc_at_run samples the value latched at the START of the interval that the
    // current tick_en ENDS. `max` was only ever hit as the value being changed INTO
    // (0xFFFF written, then immediately lowered so a tick came quickly) -- i.e. only
    // ever crossed with changed_midrun, never sustained. For (max, unchanged) the
    // divide-by-65536 interval has to actually elapse, untouched, end to end.
    //
    // That costs 65536 PCLK cycles (655.4 us) and is deliberate: this is the ONE
    // sample in the whole regression where a_presc_ratio evaluates the divide ratio at
    // the top of PRESCALER's range (gap == 0xFFFF + 1), so the wait buys a real check
    // of REQ-CORE-6's full range, not just a coverage bin. It is also exactly the
    // trade the vplan's VP-PRESC-RATIO anticipated when it chose to measure tick
    // SPACING rather than a whole channel expiry ("one interval of 65536 cycles is
    // fine; a whole channel period of that many prescaled ticks would not be").
    //
    // Starting from div1 (tick_en every cycle, cnt parked at 0) makes the latch
    // instant deterministic: the tick on the very cycle 0xFFFF appears latches
    // presc_at_interval_start=0xFFFF with presc_changed_midrun=0, and the next tick is
    // a full 65536 cycles later.
    task max_unchanged();
        reg_wr(p_sequencer.ral.PRESCALER, 0);
        reg_wr(p_sequencer.ral.CTRL, EN);
        cyc(10);
        reg_wr(p_sequencer.ral.PRESCALER, 16'hFFFF);
        cyc(65600);                                   // one complete 65536-cycle interval
        reg_wr(p_sequencer.ral.PRESCALER, 0);
    endtask

    task body();
        time_expiry(16'd0);
        time_expiry(16'd1);
        time_expiry(16'd3);
        time_expiry(16'h003F);
        midrun_change_uncorrupted();
        div1_changed_midrun();
        max_unchanged();
    endtask
endclass
