// Interrupt aggregation, masking, and simultaneous multi-channel expiry.
class pmtpc4_irq_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_irq_vseq)
    function new(string name="pmtpc4_irq_vseq"); super.new(name); endfunction
    task body();
        uvm_reg_data_t v, g;
        // masking: raw status latches, but GLOBAL_ISR/irq gated by GLOBAL_IE
        enable_module(0);
        reg_wr(p_sequencer.ral.GLOBAL_IE, 0);
        reg_wr(chan(0).CH_PERIOD, 3);
        reg_wr(chan(0).CH_CTRL, 1);                 // one-shot
        cyc(20);
        reg_rd(p_sequencer.ral.INT_STATUS, v);
        if (!(v & 1)) `uvm_error("IRQ", "raw INT_STATUS must latch while masked")
        reg_rd(p_sequencer.ral.GLOBAL_ISR, g);
        if (g & 1) `uvm_error("IRQ", "GLOBAL_ISR must be 0 while GLOBAL_IE=0")
        reg_wr(p_sequencer.ral.INT_ENABLE, 1);
        reg_wr(p_sequencer.ral.GLOBAL_IE, 1);
        reg_rd(p_sequencer.ral.GLOBAL_ISR, g);
        if (!(g & 1)) `uvm_error("IRQ", "GLOBAL_ISR must assert once enabled")
        reg_wr(p_sequencer.ral.INT_STATUS, 32'hF);  // clear all
        // simultaneous expiry of all 4 channels on the same tick
        reg_wr(p_sequencer.ral.CTRL, 1);
        for (int n = 0; n < 4; n++) begin
            reg_wr(chan(n).CH_PERIOD, 5);
            reg_wr(chan(n).CH_CTRL, 1);
        end
        cyc(30);
        reg_rd(p_sequencer.ral.INT_STATUS, v);
        if ((v & 4'hF) != 4'hF) `uvm_error("IRQ", $sformatf("all 4 expiries must latch, got 0x%0h", v))

        // F4-verif (2026-09-19 audit -- see reports/coverage_waivers.md "Tier 2"):
        // a_irq_aggregation/a_gisr_readback (sva/pmtpc4_top_sva.sv) are continuous,
        // independently-derived checkers of the full 4-bit masking formula -- but nothing
        // in the regression had ever driven a genuinely MIXED per-channel INT_ENABLE
        // pattern (some channels masked, others not) WHILE a channel was actually expired,
        // so a per-bit masking bug (e.g. only channel 0's INT_ENABLE bit ever actually
        // wired/checked) could have slipped through despite the strong checker.
        // pmtpc4_cov_close_vseq.sv writes INT_ENABLE=4'h7 for register-coverage purposes,
        // but before any channel has expired, so it proves nothing about masking's effect.
        // This directly and deterministically exercises the per-channel distinction:
        // mask channels 1 and 3, leave 0 and 2 unmasked, and confirm irq responds to EACH
        // channel individually, not just to "any channel."
        reg_wr(p_sequencer.ral.INT_STATUS, 32'hF);      // clear all
        reg_wr(p_sequencer.ral.GLOBAL_IE, 1);
        reg_wr(p_sequencer.ral.INT_ENABLE, 4'b0101);    // ch0,ch2 unmasked; ch1,ch3 masked
        for (int n = 0; n < 4; n++) reg_wr(chan(n).CH_PERIOD, 5);

        // masked channel 1 expires alone: raw latch sets, irq/GLOBAL_ISR must stay 0
        reg_wr(chan(1).CH_CTRL, 1);
        cyc(20);
        reg_rd(p_sequencer.ral.INT_STATUS, v);
        if (!(v[1])) `uvm_error("IRQ", "F4-verif: masked CH1 must still raw-latch INT_STATUS[1]")
        reg_rd(p_sequencer.ral.GLOBAL_ISR, g);
        if (g & 1) `uvm_error("IRQ", "F4-verif: GLOBAL_ISR must stay 0 -- only a MASKED channel (CH1) has expired")

        // masked channel 3 expires too: still 0 -- proves it's not "one masked channel is
        // special", every masked bit is excluded
        reg_wr(chan(3).CH_CTRL, 1);
        cyc(20);
        reg_rd(p_sequencer.ral.INT_STATUS, v);
        if (!(v[3])) `uvm_error("IRQ", "F4-verif: masked CH3 must still raw-latch INT_STATUS[3]")
        reg_rd(p_sequencer.ral.GLOBAL_ISR, g);
        if (g & 1) `uvm_error("IRQ", "F4-verif: GLOBAL_ISR must still be 0 -- both expired channels (CH1,CH3) are masked")

        // unmasked channel 0 expires: irq must now assert, proving CH0's mask bit (not
        // some other channel's) is what gates it
        reg_wr(chan(0).CH_CTRL, 1);
        cyc(20);
        reg_rd(p_sequencer.ral.INT_STATUS, v);
        if (!(v[0])) `uvm_error("IRQ", "F4-verif: CH0 must have expired")
        reg_rd(p_sequencer.ral.GLOBAL_ISR, g);
        if (!(g & 1)) `uvm_error("IRQ", "F4-verif: GLOBAL_ISR must assert once the UNMASKED CH0 expires")

        // unmasked channel 2 expires too: irq must stay asserted
        reg_wr(chan(2).CH_CTRL, 1);
        cyc(20);
        reg_rd(p_sequencer.ral.INT_STATUS, v);
        if (v[3:0] != 4'hF) `uvm_error("IRQ", $sformatf("F4-verif: all 4 channels must have expired by now, got 0x%0h", v))
        reg_rd(p_sequencer.ral.GLOBAL_ISR, g);
        if (!(g & 1)) `uvm_error("IRQ", "F4-verif: GLOBAL_ISR must still assert (CH0 and CH2 both unmasked and set)")

        // clear ONLY the unmasked channels' bits: irq must drop, even though the masked
        // channels' bits (CH1, CH3) remain SET -- proves masked-but-set bits never drive
        // irq by themselves, not merely that "some channel is enabled"
        reg_wr(p_sequencer.ral.INT_STATUS, 4'b0101);    // W1C ch0, ch2 only
        cyc(5);
        reg_rd(p_sequencer.ral.INT_STATUS, v);
        if (v[3:0] != 4'b1010) `uvm_error("IRQ", $sformatf("F4-verif: CH1/CH3 must remain latched (masked, never cleared), got 0x%0h", v))
        reg_rd(p_sequencer.ral.GLOBAL_ISR, g);
        if (g & 1) `uvm_error("IRQ", "F4-verif: GLOBAL_ISR must drop to 0 -- the only SET bits left (CH1,CH3) are masked")

        reg_wr(p_sequencer.ral.INT_STATUS, 32'hF);
        reg_wr(p_sequencer.ral.INT_ENABLE, 4'hF);
        for (int n = 0; n < 4; n++) reg_wr(chan(n).CH_CTRL, 0);
    endtask
endclass
