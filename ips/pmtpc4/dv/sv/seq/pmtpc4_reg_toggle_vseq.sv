// Register-block toggle closure (coverage-waivers "option C"): drive EVERY bit of EVERY
// register field through a 0->1 and a 1->0 transition that the DUT's own bus read-back
// shows, so reg_bit_toggle_cov (RAL-derived, functional coverage) records both
// directions. This is the measurable substitute for the register block's code-toggle
// coverage, which xsim cannot instrument (PeakRDL field storage is nested structs; its
// `automatic` next-value temporaries are listed but never updated).
//
// Three stimulus classes, matching how each field's bits can change:
//   1. software-writable bits      -> RAL bit-bash (each writable bit written 1 then 0,
//                                     read back each time)
//   2. singlepulse bits            -> write 1 (stored for one clock), read back 0
//   3. hardware-driven read-only   -> make the hardware drive them both ways, read often:
//      CHx_COUNT[15:0] (down-counter, period 0xFFFF), STATUS.BUSY/READY,
//      GLOBAL_ISR, INT_STATUS[3:0] (hw-set, W1C-cleared)
class pmtpc4_reg_toggle_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_reg_toggle_vseq)
    function new(string name = "pmtpc4_reg_toggle_vseq"); super.new(name); endfunction

    localparam bit [31:0] EN = 1, MODE = 2, PWM = 4, START = 8, PAUSE = 16, SRST = 2;
    // COUNT polling: a full down-count from 0xFFFF takes 65536 ticks at prescaler div1.
    // Poll every channel's COUNT every POLL_GAP cycles (prime, so the sample phase walks
    // across the counter) for two full periods: every COUNT bit is then seen falling and
    // rising (bit 15 falls at 0x7FFF and rises at the reload back to 0xFFFF).
    int unsigned POLL_GAP    = 1021;
    int unsigned POLL_ROUNDS = 140;     // 140 x ~1037 cycles > 2 x 65536

    task body();
        uvm_reg_data_t v;

        // ---- 1. software-writable bits: RAL bit-bash (restores each register after) ----
        begin
            pmtpc4_reg_rw_vseq bb = pmtpc4_reg_rw_vseq::type_id::create("bb");
            bb.start(p_sequencer, this);
        end

        // ---- 2. singlepulse fields: accepted write of 1, then a read of 0 ----
        reg_wr(p_sequencer.ral.CTRL, EN);              // MODULE_EN=1 (READY rises)
        reg_rd(p_sequencer.ral.STATUS, v);
        reg_wr(p_sequencer.ral.CTRL, EN | SRST);       // CTRL.SOFT_RESET one-cycle pulse
        reg_rd(p_sequencer.ral.CTRL, v);
        chk(v[1] == 1'b0, "CTRL.SOFT_RESET must read back 0 after its one-cycle pulse");
        for (int ch = 0; ch < 4; ch++) begin           // CHx_CTRL.CH_START one-cycle pulse
            reg_wr(chan(ch).CH_CTRL, EN | START);
            reg_rd(chan(ch).CH_CTRL, v);               // CH_EN seen 1 (rise)
            chk(v[3] == 1'b0, $sformatf("CH%0d_CTRL.CH_START must read back 0", ch));
            reg_wr(chan(ch).CH_CTRL, 0);               // stop the channel again
            reg_rd(chan(ch).CH_CTRL, v);               // CH_EN seen 0 (fall)
        end

        // ---- 3. hardware-driven read-only bits ----
        // all four channels free-running, periodic, full 16-bit period, prescaler div1,
        // interrupts enabled so INT_STATUS / GLOBAL_ISR get set by the hardware
        reg_wr(p_sequencer.ral.PRESCALER, 0);
        reg_wr(p_sequencer.ral.INT_ENABLE, 4'hF);
        reg_wr(p_sequencer.ral.GLOBAL_IE, 1);
        reg_wr(p_sequencer.ral.INT_STATUS, 4'hF);      // start from a clean W1C state
        for (int ch = 0; ch < 4; ch++) begin
            reg_wr(chan(ch).CH_PERIOD,  16'hFFFF);
            reg_wr(chan(ch).CH_COMPARE, 16'h8000);
            reg_wr(chan(ch).CH_CTRL,    EN | MODE | PWM);
        end
        reg_rd(p_sequencer.ral.STATUS, v);             // BUSY rises (channels running)
        for (int unsigned r = 0; r < POLL_ROUNDS; r++) begin
            for (int ch = 0; ch < 4; ch++) reg_rd(chan(ch).CH_COUNT, v);
            // after the first expiry of every channel (> 65536 ticks in), show the
            // interrupt bits set, then W1C-clear them and show them clear again
            if (r == 80) begin
                reg_rd(p_sequencer.ral.INT_STATUS, v);     // CH_INT_STATUS[3:0] rise
                reg_rd(p_sequencer.ral.GLOBAL_ISR, v);     // GLOBAL_INT_STATUS rise
                reg_wr(p_sequencer.ral.INT_STATUS, 4'hF);  // W1C
                reg_rd(p_sequencer.ral.INT_STATUS, v);     // fall
                reg_rd(p_sequencer.ral.GLOBAL_ISR, v);     // fall
            end
            cyc(POLL_GAP);
        end
        // stop everything: BUSY falls; then MODULE_EN=0: READY falls
        for (int ch = 0; ch < 4; ch++) reg_wr(chan(ch).CH_CTRL, 0);
        cyc(4);
        reg_rd(p_sequencer.ral.STATUS, v);             // BUSY fall
        reg_wr(p_sequencer.ral.CTRL, 0);
        reg_rd(p_sequencer.ral.STATUS, v);             // READY fall
        reg_wr(p_sequencer.ral.INT_STATUS, 4'hF);      // leave the block quiet
        reg_wr(p_sequencer.ral.GLOBAL_IE, 0);
        reg_wr(p_sequencer.ral.INT_ENABLE, 0);
        reg_wr(p_sequencer.ral.CTRL, EN);
    endtask
endclass
