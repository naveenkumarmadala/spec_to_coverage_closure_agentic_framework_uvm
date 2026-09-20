// VP-INT-W1C: per-bit INT_STATUS W1C semantics -- hw sets independent of masking,
// write-1 clears, write-0 has NO effect (never exercised by any existing test),
// reset value 0. Self-checking directly against literal expected values (same style
// as pmtpc4_oneshot_vseq/pmtpc4_softdisable_vseq): the scoreboard cannot predict this
// register (hw can set it at any time, independent of any write -- see
// pmtpc4_scoreboard.sv's readmask() comment), so the check lives here instead.
// Coverage (cg_int_bit.cp_op, cg_int.cp_n_simultaneous) is sampled by the bound SVA
// from the same signals this vseq's stimulus toggles -- this vseq never samples it.
class pmtpc4_int_w1c_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_int_w1c_vseq)
    function new(string name="pmtpc4_int_w1c_vseq"); super.new(name); endfunction

    localparam bit [31:0] EN=1;

    task expire_channel(int ch);
        reg_wr(chan(ch).CH_PERIOD, 3);
        reg_wr(chan(ch).CH_CTRL, EN);     // one-shot
        cyc(20);
    endtask

    task body();
        uvm_reg_data_t v;
        enable_module(0);
        reg_wr(p_sequencer.ral.INT_STATUS, 4'hF);   // start clean

        // ---- per-bit: hw-set, write-0-holds, write-1-clears ----
        for (int n = 0; n < 4; n++) begin
            expire_channel(n);
            reg_rd(p_sequencer.ral.INT_STATUS, v);
            chk(v[n] == 1'b1, $sformatf("bit %0d must be hw-set by channel %0d's expiry", n, n));

            reg_wr(p_sequencer.ral.INT_STATUS, (32'h1 << n) ^ (32'hF));  // write 0 to bit n, 1 to the others (already 0)
            reg_rd(p_sequencer.ral.INT_STATUS, v);
            chk(v[n] == 1'b1, $sformatf("write-0 to bit %0d must NOT clear it", n));

            reg_wr(p_sequencer.ral.INT_STATUS, (32'h1 << n));           // write 1 to bit n only
            reg_rd(p_sequencer.ral.INT_STATUS, v);
            chk(v[n] == 1'b0, $sformatf("write-1 to bit %0d must clear it", n));
        end

        // ---- multi-bit write: expire all 4, clear 2, leave 2 ----
        for (int n = 0; n < 4; n++) expire_channel(n);
        reg_rd(p_sequencer.ral.INT_STATUS, v);
        chk(v[3:0] == 4'hF, "all four bits must be hw-set after expiring every channel");
        reg_wr(p_sequencer.ral.INT_STATUS, 4'h5);   // clear bits 0,2; leave 1,3
        reg_rd(p_sequencer.ral.INT_STATUS, v);
        chk(v[3:0] == 4'hA, $sformatf("multi-bit W1C: expected 0xA after clearing 0,2, got 0x%0h", v[3:0]));
        reg_wr(p_sequencer.ral.INT_STATUS, 4'hA);   // clear the rest
        reg_rd(p_sequencer.ral.INT_STATUS, v);
        chk(v[3:0] == 4'h0, "all bits must read 0 after clearing the remainder");
    endtask
endclass
