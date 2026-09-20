// VP-RST-ASYNC: pulse PRESETn mid-simulation from RUNNING, PAUSED, EXPIRED and in
// the middle of an APB ACCESS phase, and confirm the environment recovers cleanly:
// every register reads its reset value afterwards (checked here directly, and by
// re-running the RAL hw-reset sequence, which is itself self-checking against the
// RAL's mirror) and the scoreboard/RAL are resynced (pmtpc4_base_vseq::async_reset()
// already calls handle_reset() on both — see dv/README.md's "Test-writer hooks").
class pmtpc4_async_reset_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_async_reset_vseq)
    function new(string name="pmtpc4_async_reset_vseq"); super.new(name); endfunction

    localparam bit [31:0] EN=1, MODE=2, PWM=4, START=8, PAUSE=16, SOFTRST=2;
    // tick every (N+1) PCLK cycles: widens the one-tick LOAD / EXPIRED windows into
    // something a reset can be landed inside (same technique, and the same reasoning,
    // as pmtpc4_freeze_states_vseq -- see its header for why a fixed cyc() guess is
    // not good enough for either window).
    localparam bit [15:0] LOAD_PRESC = 16'd31;
    localparam bit [15:0] EXP_PRESC  = 16'd63;

    task check_all_idle_and_reset();
        uvm_reg_data_t v;
        uvm_reg_hw_reset_seq rst = uvm_reg_hw_reset_seq::type_id::create("rst_after_async");
        // Direct, immediate check (before the (slower) full hw_reset_seq sweep) that
        // every channel is back in IDLE and CH_EN reads 0 -- the exact claim
        // REQ-RST-1 makes about "from any state".
        for (int ch = 0; ch < 4; ch++) begin
            reg_rd(chan(ch).CH_CTRL, v);
            chk(v == 0, $sformatf("CH%0d_CTRL must read all-0 after async reset (got 0x%0h)", ch, v));
        end
        reg_rd(p_sequencer.ral.STATUS, v);
        chk(v == 0, $sformatf("STATUS must read 0 (all IDLE, not READY) after async reset (got 0x%0h)", v));
        // Full RAL-derived sweep of every field's reset value (self-checking: the
        // built-in sequence errors on any mismatch against the RAL's own spec).
        rst.model = p_sequencer.ral;
        rst.start(null);
    endtask

    task body();
        // ---- from IDLE ----
        // cg_reset.cp_state_at_reset.idle: the power-on reset never produces a
        // negedge presetn event (2026-09-18 finding: reset_if's `rst` starts
        // asserted from time 0, so the very first power-on release is a POSEDGE,
        // and cg_reset triggers on negedge -- power-on alone can never sample this
        // bin). A genuinely idle, deliberate mid-sim reset closes it instead.
        enable_module(0);
        async_reset(4);
        check_all_idle_and_reset();

        // ---- from LOAD ----
        // A slow PRESCALER stretches the one-tick LOAD state into a window this
        // vseq can reliably land a reset inside (same trick as
        // pmtpc4_freeze_states_vseq::freeze_from_load).
        reg_wr(p_sequencer.ral.PRESCALER, 16'd20);
        reg_wr(p_sequencer.ral.CTRL, EN);
        reg_wr(chan(0).CH_PERIOD, 16'd5);
        reg_wr(chan(0).CH_CTRL, EN);           // IDLE->LOAD
        cyc(4);                                 // still in LOAD (tick_en hasn't fired yet)
        async_reset(4);
        reg_wr(p_sequencer.ral.PRESCALER, 0);
        check_all_idle_and_reset();

        // ---- from RUNNING ----
        enable_module(0);
        reg_wr(chan(0).CH_PERIOD, 16'h0FFF);
        reg_wr(chan(0).CH_CTRL, EN|MODE|PWM);
        cyc(10);                              // now RUNNING
        async_reset(4);
        check_all_idle_and_reset();

        // ---- from PAUSED ----
        enable_module(0);
        reg_wr(chan(1).CH_PERIOD, 16'h0FFF);
        reg_wr(chan(1).CH_CTRL, EN|MODE|PAUSE);
        cyc(10);                              // LOAD->PAUSED (errata 12.1) and holding
        async_reset(4);
        check_all_idle_and_reset();

        // ---- from EXPIRED ----
        enable_module(0);
        reg_wr(chan(2).CH_PERIOD, 3);
        reg_wr(chan(2).CH_CTRL, EN);           // one-shot, short period
        cyc(20);                              // expires and self-disables well within 20 cyc
        async_reset(4);
        check_all_idle_and_reset();

        // ---- mid APB ACCESS phase ----
        // async_delay lands the assertion off the clock edge, inside whatever phase
        // the bus happens to be in when the fork below fires -- including ACCESS.
        // The APB driver/monitor abort any in-flight transfer rather than hang.
        enable_module(0);
        reg_wr(chan(3).CH_PERIOD, 16'h0FFF);
        reg_wr(chan(3).CH_CTRL, EN|MODE|PWM);
        cyc(5);
        fork
            begin
                apb_item it;
                raw(0, 32'h10, 0, it);          // a read of PRESCALER, long enough to overlap the reset
            end
            async_reset(4, 3ns);
        join
        check_all_idle_and_reset();

        // ---- cg_reset.x_reset: the FSM-state x APB-phase coincidence, swept ----
        sweep_all_states_vs_apb_phase();
    endtask

    // =====================================================================
    // VP-RST-ASYNC coverage closure: cg_reset's x_reset cross is a TWO-AXIS
    // coincidence -- which channel FSM state was interrupted (cp_state_at_reset) AND
    // which APB bus phase the reset landed in (cp_apb_at_reset) -- and the scenarios
    // above only ever produce one axis deliberately at a time. 10 of its 15 cells
    // were open (every `expired` cell, every `mid_setup` cell, and
    // {load,running,paused} x mid_access).
    //
    // Closed by sweeping, not by a single lucky offset:
    //   * A background stream of ordinary (non-chained) APB reads makes the bus cycle
    //     through IDLE -> SETUP -> ACCESS with a period of 3 PCLK cycles (the driver
    //     takes one idle clock before each SETUP, then one SETUP and one zero-wait
    //     ACCESS clock).
    //   * The reset is fired at PCLK-offset 0..5 into that stream, so every residue
    //     of that 3-cycle pattern is covered several times over. `3ns` puts the
    //     assertion genuinely OFF the clock edge, which is what makes this an
    //     asynchronous reset rather than a synchronous one in disguise.
    //   * arm_state() re-establishes the target channel state before EVERY attempt,
    //     because the previous attempt's reset destroyed it.
    //
    // The CHECK on every one of these resets is REQ-RST-1's own claim -- all four
    // channels back in IDLE and every CH_CTRL / STATUS bit at its reset value. The
    // heavier full-RAL sweep (check_all_idle_and_reset) stays on the scenarios above;
    // repeating its ~112 register reads 30 more times would buy nothing new.
    // =====================================================================
    task light_reset_check(string nm, int unsigned off);
        uvm_reg_data_t v;
        for (int ch = 0; ch < 4; ch++) begin
            reg_rd(chan(ch).CH_CTRL, v);
            chk(v == 0, $sformatf("reset from %s (offset %0d): CH%0d_CTRL must read 0 (got 0x%0h)",
                                  nm, off, ch, v));
        end
        reg_rd(p_sequencer.ral.STATUS, v);
        chk(v == 0, $sformatf("reset from %s (offset %0d): STATUS must read 0 (got 0x%0h)", nm, off, v));
    endtask

    // Put channel 0 -- and only channel 0, so cg_reset's priority-ordered
    // any_active_state() reports exactly what this task armed -- into `st`.
    // 0=IDLE 1=LOAD 2=RUNNING 3=PAUSED 4=EXPIRED
    task arm_state(int unsigned st);
        uvm_reg_data_t v;
        case (st)
            0: enable_module(0);                             // nothing running at all
            1: begin
                // SOFT_RESET zeroes the shared prescaler's counter, so the single
                // tick_en that ends S_LOAD is a known LOAD_PRESC+1 cycles away
                // instead of at an arbitrary phase.
                reg_wr(p_sequencer.ral.PRESCALER, LOAD_PRESC);
                reg_wr(chan(0).CH_PERIOD, 16'd5);
                reg_wr(p_sequencer.ral.CTRL, EN|SOFTRST);
                reg_wr(chan(0).CH_CTRL, EN);                 // IDLE->LOAD, and it stays there
            end
            2: begin
                enable_module(0);
                reg_wr(chan(0).CH_PERIOD, 16'h0FFF);
                reg_wr(chan(0).CH_CTRL, EN|MODE|PWM);
                cyc(10);                                     // RUNNING, long period
            end
            3: begin
                enable_module(0);
                reg_wr(chan(0).CH_PERIOD, 16'h0FFF);
                reg_wr(chan(0).CH_CTRL, EN|MODE|PAUSE);      // LOAD->PAUSED (errata 12.1)
                cyc(10);                                     // holds indefinitely
            end
            4: begin
                reg_wr(p_sequencer.ral.INT_STATUS, 4'hF);
                reg_wr(p_sequencer.ral.PRESCALER, EXP_PRESC);
                reg_wr(p_sequencer.ral.CTRL, EN);
                reg_wr(chan(0).CH_PERIOD, 16'd2);
                reg_wr(chan(0).CH_CTRL, EN|MODE);            // periodic: EXPIRED is EXP_PRESC+1 cycles wide
                // Poll for the expiry rather than guessing a cyc() -- this returns
                // within one APB read of EXPIRED being ENTERED, so the reset below
                // lands ~15 cycles into a 64-cycle window.
                for (int unsigned i = 0; i < 400; i++) begin
                    reg_rd(p_sequencer.ral.INT_STATUS, v);
                    if (v[0]) break;
                end
                chk(v[0] == 1'b1, "arm_state(EXPIRED): CH0 never latched its expiry");
            end
            default: enable_module(0);
        endcase
    endtask

    task reset_during_bus_traffic(int unsigned offset);
        fork
            begin : traffic
                apb_item it;
                // PRESCALER reads: legal, zero-wait, side-effect-free, and enough of
                // them that the bus is still cycling when the reset lands.
                repeat (12) raw(0, 32'h10, 0, it);
            end
            begin : rst
                cyc(4 + offset);
                async_reset(4, 3ns);
            end
        join
    endtask

    task sweep_all_states_vs_apb_phase();
        string names[5] = '{"IDLE", "LOAD", "RUNNING", "PAUSED", "EXPIRED"};
        for (int unsigned st = 0; st < 5; st++) begin
            for (int unsigned off = 0; off <= 5; off++) begin
                arm_state(st);
                reset_during_bus_traffic(off);
                light_reset_check(names[st], off);
            end
        end
        reg_wr(p_sequencer.ral.PRESCALER, 0);
    endtask
endclass
