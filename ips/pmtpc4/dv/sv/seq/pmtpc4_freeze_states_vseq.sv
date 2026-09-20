// VP-FREEZE-STATES: freeze (MODULE_EN=0) from LOAD, PAUSED and EXPIRED -- not just
// RUNNING, which is all pmtpc4_freeze_vseq ever exercised -- and confirm the channel
// resumes and completes the pending transition, including the deferred re-expiry
// out of a frozen periodic EXPIRED. Also exercises the CH_PAUSE-during-EXPIRED
// corner a prior mutation pass flagged as unexercised: RTL's S_EXPIRED case ignores
// ch_pause entirely (only S_RUNNING checks it), so a pause asserted while EXPIRED
// must NOT block the EXPIRED->LOAD reload; it only takes effect once LOAD is
// reached (errata 12.1: LOAD->PAUSED).
//
// cg_fsm.cp_frozen_state (bound SVA, not this vseq) is what actually credits the
// load/paused/expired bins; a_freeze_hold (already existing, continuous,
// state-agnostic) is what would catch a violation from any of these states. Every
// task therefore runs on ALL FOUR channels: cp_frozen_state is per-instance, so a
// bin closed on ch0 says nothing about ch1-3 (the 2026-09-18 report had `load`
// missing on ch2/ch3, `paused` on ch0/ch1/ch3 and `expired` on all four).
//
// ---------------------------------------------------------------------------
// 2026-09-18 TIMING ROOT-CAUSE FIX -- why cp_frozen_state.expired read 0 on every
// channel even though freeze_from_expired() ran twice and its functional checks
// passed:
//
// Both the LOAD and the EXPIRED windows are exactly ONE tick_en wide, and the
// shared prescaler free-runs at an arbitrary phase relative to any APB write. The
// old code reached for those windows with a fixed `cyc(N)` guess and then spent a
// whole extra APB READ (the INT_STATUS check) before issuing the freeze write --
// so MODULE_EN actually dropped ~15 cycles later than the `cyc(N)` comment assumed,
// by which time the EXPIRED -> IDLE (one-shot) / EXPIRED -> LOAD (periodic) tick had
// already fired. The freeze was real and a_freeze_hold/COUNT-stability still passed
// -- they just described a freeze taken from IDLE/LOAD, not from EXPIRED.
//
// Two fixes, one per window:
//   EXPIRED: stop guessing. wait_expiry() POLLS INT_STATUS and returns within one
//     APB read of the expiry event itself, and the freeze write is then the very
//     next bus transaction (~10 cycles). A deliberately slow EXP_PRESC stretches
//     the EXPIRED window to 64 cycles, i.e. ~6x that latency.
//   LOAD: pin the shared prescaler's own counter at a known 0 by holding PRESCALER=0
//     (with the module enabled) for a couple of cycles immediately before switching
//     to the wide LOAD_PRESC value and starting the channel, so the next tick_en is a
//     KNOWN LOAD_PRESC+1 cycles away instead of an arbitrary phase, and the freeze
//     lands ~10 cycles into a ~33-cycle window. (2026-09-19 F5 fix: this used to use a
//     SOFT_RESET pulse for the same purpose, but SOFT_RESET no longer touches the
//     prescaler at all -- REQ-RST-2 -- so the phase is now pinned via PRESCALER=0
//     instead; see freeze_from_load() below and pmtpc4_prescaler.sv.)
//
// Both tasks now also make a DISCRIMINATING check that the freeze really did land
// in EXPIRED rather than trusting the coverage report to say so:
//   one-shot: CH_EN must still read 1 DURING the freeze. CH_EN self-clears on the
//     EXPIRED -> IDLE tick, so a reading of 1 proves that tick has not happened yet.
//   periodic: COUNT must read 0 DURING the freeze. The EXPIRED -> LOAD tick reloads
//     COUNT with PERIOD, so a reading of 0 proves the reload has not happened yet.
// ---------------------------------------------------------------------------
class pmtpc4_freeze_states_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_freeze_states_vseq)
    function new(string name="pmtpc4_freeze_states_vseq"); super.new(name); endfunction

    localparam bit [31:0] EN=1, MODE=2, PAUSE=16;
    // tick every (N+1) PCLK cycles -- the width of the one-tick LOAD / EXPIRED window
    localparam bit [15:0] LOAD_PRESC = 16'd31;    //  32-cycle LOAD window
    localparam bit [15:0] EXP_PRESC  = 16'd63;    //  64-cycle EXPIRED window

    // Poll INT_STATUS until channel `ch` has latched its expiry. Returns within one
    // APB read of the expiry event, which (unlike a fixed cyc() wait) pins the
    // caller to a known, small offset into the EXPIRED window.
    task wait_expiry(int ch, int unsigned max_polls = 400);
        uvm_reg_data_t v;
        for (int unsigned i = 0; i < max_polls; i++) begin
            reg_rd(p_sequencer.ral.INT_STATUS, v);
            if (v[ch]) return;
        end
        chk(1'b0, $sformatf("CH%0d never latched its expiry within the poll budget", ch));
    endtask

    task freeze_from_load(int ch);
        uvm_reg_data_t s1, s2, v;
        // F5 fix (2026-09-19 audit -- see reports/coverage_waivers.md "Tier 2"): SOFT_RESET
        // no longer zeroes the prescaler's cnt (pmtpc4_prescaler.sv F5 fix -- REQ-RST-2 means
        // soft_reset must not touch the prescaler at all), so this task can no longer use a
        // SOFT_RESET pulse to pin the divider's phase before starting the channel. Instead:
        // hold PRESCALER at 0 with the module enabled first -- with prescaler_val==0 the
        // divider's `cnt>=prescaler_val` comparison is true every cycle, so cnt is pinned at 0
        // continuously (never advances) regardless of its value beforehand -- then switch to
        // the wide LOAD_PRESC value. cnt resumes counting from that known 0 starting point,
        // giving the same known LOAD_PRESC+1-cycle window the old SOFT_RESET trick did.
        reg_wr(p_sequencer.ral.CTRL, EN);           // module_en=1 so cnt actively pins at 0
        reg_wr(p_sequencer.ral.PRESCALER, 0);
        cyc(3);
        reg_wr(chan(ch).CH_PERIOD, 16'd5);
        reg_wr(p_sequencer.ral.PRESCALER, LOAD_PRESC);  // cnt resumes from the known 0
        reg_wr(chan(ch).CH_CTRL, EN);               // IDLE->LOAD (start_trig)
        reg_wr(p_sequencer.ral.CTRL, 0);            // freeze from LOAD
        reg_rd(chan(ch).CH_COUNT, s1);
        chk(s1 == 16'd5,
            $sformatf("CH%0d frozen from LOAD: COUNT must already hold PERIOD=5 (got 0x%0h)", ch, s1));
        cyc(30);
        reg_rd(chan(ch).CH_COUNT, s2);
        chk(s1 == s2, $sformatf("CH%0d frozen from LOAD: COUNT must hold", ch));
        reg_wr(p_sequencer.ral.CTRL, EN);           // resume
        cyc(400);                                    // >= 7 ticks * (LOAD_PRESC+1)
        reg_rd(p_sequencer.ral.INT_STATUS, v);
        chk(v[ch] == 1'b1, $sformatf("CH%0d must complete LOAD->RUN->EXPIRED after resuming from a frozen LOAD", ch));
        reg_wr(p_sequencer.ral.INT_STATUS, (32'h1 << ch));
        reg_wr(chan(ch).CH_CTRL, 0);
        reg_wr(p_sequencer.ral.PRESCALER, 0);
    endtask

    task freeze_from_paused(int ch);
        uvm_reg_data_t s1, s2, v;
        reg_wr(p_sequencer.ral.PRESCALER, 0);
        reg_wr(p_sequencer.ral.CTRL, EN);
        reg_wr(chan(ch).CH_PERIOD, 16'h00FF);
        reg_wr(chan(ch).CH_CTRL, EN|PAUSE);         // IDLE->LOAD->PAUSED (errata 12.1)
        cyc(10);
        reg_wr(p_sequencer.ral.CTRL, 0);             // freeze from PAUSED
        reg_rd(chan(ch).CH_COUNT, s1);
        cyc(30);
        reg_rd(chan(ch).CH_COUNT, s2);
        chk(s1 == s2, $sformatf("CH%0d frozen from PAUSED: COUNT must hold", ch));
        reg_wr(p_sequencer.ral.CTRL, EN);            // resume (still paused)
        cyc(20);
        reg_rd(chan(ch).CH_COUNT, s2);
        chk(s1 == s2, $sformatf("CH%0d: resuming from a frozen PAUSED must stay paused (COUNT still held)", ch));
        reg_wr(chan(ch).CH_CTRL, EN);                 // release pause
        cyc(300);
        reg_rd(p_sequencer.ral.INT_STATUS, v);
        chk(v[ch] == 1'b1, $sformatf("CH%0d must run to expiry after the pause is released", ch));
        reg_wr(p_sequencer.ral.INT_STATUS, (32'h1 << ch));
        reg_wr(chan(ch).CH_CTRL, 0);
    endtask

    task freeze_from_expired(int ch, bit periodic);
        uvm_reg_data_t s1, s2, v, ctrl_frozen, ctrl_after;
        bit [31:0] ctrl_bits = periodic ? (EN|MODE) : EN;
        reg_wr(p_sequencer.ral.INT_STATUS, (32'h1 << ch));
        reg_wr(p_sequencer.ral.PRESCALER, EXP_PRESC);
        reg_wr(p_sequencer.ral.CTRL, EN);
        reg_wr(chan(ch).CH_PERIOD, 16'd2);
        reg_wr(chan(ch).CH_CTRL, ctrl_bits);
        wait_expiry(ch);                              // returns inside the EXPIRED window
        reg_wr(p_sequencer.ral.CTRL, 0);              // freeze from EXPIRED (next bus transfer)

        // ---- discriminating evidence that the freeze really landed in EXPIRED ----
        // COUNT==0 uniquely identifies EXPIRED regardless of mode: S_LOAD loads
        // count<=period (2, nonzero); S_RUNNING transitions OUT to S_EXPIRED on the
        // exact same tick_en that would first observe count=='0 (rtl/pmtpc4_channel.sv
        // S_RUNNING case), so RUNNING itself is never observed holding count==0; only
        // EXPIRED holds it there, unchanged, while frozen. This replaces an earlier
        // one-shot-only check on CH_EN==1 that a 2026-09-19 verification-reviewer
        // mutation audit proved NON-discriminating (CH_EN also reads 1 throughout
        // LOAD/RUNNING/PAUSED -- reverting wait_expiry() to the old fixed cyc(95) wait
        // caused this check to keep passing silently even though the freeze had
        // landed in RUNNING, not EXPIRED, on the one-shot channels; only the
        // periodic branch's COUNT==0 check caught the injected race). CH_EN==1 is
        // kept as a secondary, non-discriminating sanity check for one-shot (it does
        // still correctly rule out "already self-cleared to IDLE").
        reg_rd(chan(ch).CH_COUNT, s1);
        reg_rd(chan(ch).CH_CTRL,  ctrl_frozen);
        chk(s1 == 16'd0,
            $sformatf("CH%0d %s: frozen in EXPIRED means COUNT is still 0; got 0x%0h",
                      ch, periodic ? "periodic" : "one-shot", s1));
        if (!periodic)
            chk(ctrl_frozen[0] == 1'b1,
                $sformatf("CH%0d one-shot: CH_EN must not have self-cleared yet; got CH_CTRL=0x%0h", ch, ctrl_frozen));

        cyc(60);
        reg_rd(chan(ch).CH_COUNT, s2);
        chk(s1 == s2, $sformatf("CH%0d frozen from EXPIRED: COUNT must hold", ch));
        reg_wr(p_sequencer.ral.INT_STATUS, (32'h1 << ch));   // clear, so a re-expiry below is unambiguous
        reg_wr(p_sequencer.ral.CTRL, EN);             // resume
        cyc(500);                                      // >= 5 ticks * (EXP_PRESC+1)
        reg_rd(chan(ch).CH_CTRL, ctrl_after);
        reg_rd(p_sequencer.ral.INT_STATUS, v);
        if (periodic) begin
            chk(ctrl_after[0] == 1'b1,
                $sformatf("CH%0d periodic: CH_EN must still be 1 after resuming from a frozen EXPIRED", ch));
            chk(v[ch] == 1'b1,
                $sformatf("CH%0d periodic: must reload, run and raise a SECOND (deferred) interrupt after resume", ch));
        end else begin
            chk(ctrl_after[0] == 1'b0,
                $sformatf("CH%0d one-shot: CH_EN must self-clear after resuming from a frozen EXPIRED", ch));
        end
        reg_wr(p_sequencer.ral.INT_STATUS, (32'h1 << ch));
        reg_wr(chan(ch).CH_CTRL, 0);
        reg_wr(p_sequencer.ral.PRESCALER, 0);
    endtask

    // CH_PAUSE asserted while sitting in EXPIRED: the reload decision itself must
    // NOT be blocked (RTL's S_EXPIRED case does not check ch_pause), but the
    // resulting LOAD must then land in PAUSED (errata 12.1) and hold there.
    task pause_during_expired(int ch);
        uvm_reg_data_t v, c1, c2;
        reg_wr(p_sequencer.ral.INT_STATUS, (32'h1 << ch));
        reg_wr(p_sequencer.ral.PRESCALER, EXP_PRESC);
        reg_wr(p_sequencer.ral.CTRL, EN);
        reg_wr(chan(ch).CH_PERIOD, 16'd2);
        reg_wr(chan(ch).CH_CTRL, EN|MODE);            // periodic
        wait_expiry(ch);                               // now sitting in EXPIRED
        reg_wr(chan(ch).CH_CTRL, EN|MODE|PAUSE);       // assert CH_PAUSE while sitting in EXPIRED
        cyc(200);                                       // the EXPIRED->LOAD tick must still fire
        reg_rd(chan(ch).CH_COUNT, c1);
        chk(c1 == 16'd2,
            $sformatf("CH%0d: EXPIRED->LOAD reload must proceed despite CH_PAUSE (got COUNT=0x%0h)", ch, c1));
        cyc(200);
        reg_rd(chan(ch).CH_COUNT, c2);
        chk(c1 == c2, $sformatf("CH%0d: must now be held PAUSED (LOAD->PAUSED, errata 12.1)", ch));
        reg_wr(p_sequencer.ral.INT_STATUS, (32'h1 << ch));
        reg_wr(chan(ch).CH_CTRL, EN|MODE);             // release pause
        cyc(400);
        reg_rd(p_sequencer.ral.INT_STATUS, v);
        chk(v[ch] == 1'b1, $sformatf("CH%0d must resume and re-expire once the pause is released", ch));
        reg_wr(p_sequencer.ral.INT_STATUS, (32'h1 << ch));
        reg_wr(chan(ch).CH_CTRL, 0);
        reg_wr(p_sequencer.ral.PRESCALER, 0);
    endtask

    task body();
        enable_module(0);
        for (int ch = 0; ch < 4; ch++) freeze_from_load(ch);
        for (int ch = 0; ch < 4; ch++) freeze_from_paused(ch);
        // alternate one-shot / periodic so both EXPIRED exit paths are frozen, and
        // both discriminating checks above are exercised, across the four channels
        for (int ch = 0; ch < 4; ch++) freeze_from_expired(ch, ch[0]);
        pause_during_expired(1);
    endtask
endclass
