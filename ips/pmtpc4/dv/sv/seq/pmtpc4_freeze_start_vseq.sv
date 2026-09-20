// F4 regression test (2026-09-19 audit): CH_EN/CH_START writes issued WHILE MODULE_EN==0
// must not be silently swallowed. Before the fix, ch_en_q tracked ch_en unconditionally
// even while frozen, so a CH_EN 0->1 rising edge (or a CH_START pulse) taken during a
// freeze was already "seen" by the time the freeze lifted -- the channel never started.
// This is exactly the natural bring-up order: disable, configure, enable channels, then
// enable the module.
class pmtpc4_freeze_start_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_freeze_start_vseq)
    function new(string name="pmtpc4_freeze_start_vseq"); super.new(name); endfunction

    localparam bit [31:0] EN=1, START=8;

    // Natural bring-up order: MODULE_EN=0 throughout configuration, CH_EN written while
    // frozen, MODULE_EN=1 only at the end.
    task ch_en_during_freeze(int ch);
        uvm_reg_data_t v;
        reg_wr(p_sequencer.ral.CTRL, 0);              // MODULE_EN=0 (frozen)
        reg_wr(chan(ch).CH_PERIOD, 16'd5);
        reg_wr(chan(ch).CH_CTRL, EN);                 // CH_EN 0->1 while frozen
        cyc(10);                                       // stay frozen for a while
        reg_rd(chan(ch).CH_CTRL, v);
        chk(v[0] == 1'b1, $sformatf("CH%0d: CH_EN must still read 1 while frozen", ch));
        reg_wr(p_sequencer.ral.CTRL, EN);              // MODULE_EN=1 (un-freeze)
        cyc(100);
        reg_rd(p_sequencer.ral.INT_STATUS, v);
        chk(v[ch] == 1'b1,
            $sformatf("CH%0d: a CH_EN write during freeze must still start the channel once un-frozen (got no expiry -- channel silently swallowed the start)", ch));
        reg_wr(p_sequencer.ral.INT_STATUS, (32'h1 << ch));
        reg_wr(chan(ch).CH_CTRL, 0);
    endtask

    // Same scenario via CH_START instead of the CH_EN rising edge (channel already
    // enabled from a prior run, soft-disabled, then re-started via CH_START while frozen).
    task ch_start_during_freeze(int ch);
        uvm_reg_data_t v;
        reg_wr(p_sequencer.ral.CTRL, EN);
        reg_wr(chan(ch).CH_PERIOD, 16'd5);
        reg_wr(chan(ch).CH_CTRL, EN);
        cyc(3);
        reg_wr(chan(ch).CH_CTRL, 0);                   // soft-disable back to IDLE
        cyc(3);
        reg_wr(p_sequencer.ral.CTRL, 0);               // freeze
        reg_wr(chan(ch).CH_CTRL, EN|START);             // CH_EN=1 + CH_START pulse while frozen
        cyc(10);
        reg_wr(p_sequencer.ral.CTRL, EN);              // un-freeze
        cyc(100);
        reg_rd(p_sequencer.ral.INT_STATUS, v);
        chk(v[ch] == 1'b1,
            $sformatf("CH%0d: a CH_START pulse during freeze must still start the channel once un-frozen", ch));
        reg_wr(p_sequencer.ral.INT_STATUS, (32'h1 << ch));
        reg_wr(chan(ch).CH_CTRL, 0);
    endtask

    task body();
        ch_en_during_freeze(0);
        ch_start_during_freeze(1);
        reg_wr(p_sequencer.ral.PRESCALER, 0);
    endtask
endclass
