// VP-SELFCLR (errata 12.5): CTRL.SOFT_RESET and CHx_CTRL.CH_START self-clear within
// one cycle and are never observable as 1 by any subsequent read, including a
// back-to-back minimum-latency read. Checked TWO ways:
//   1. explicitly here, immediately after each write;
//   2. by pmtpc4_scoreboard.sv on every single subsequent read of these registers,
//      for the rest of the regression (readmask()/selfclear_mask() now fold the
//      self-clear bits into the comparison mask, forcing the shadow to 0 regardless
//      of what was written) -- so this property is continuously enforced, not just
//      by this one test.
class pmtpc4_selfclear_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_selfclear_vseq)
    function new(string name="pmtpc4_selfclear_vseq"); super.new(name); endfunction

    localparam bit [31:0] EN=1, START=8;

    // The self-clearing write and its read-back issued as a single APB back-to-back
    // pair: PSEL is held across the ACCESS -> SETUP boundary, so the read's ACCESS
    // phase ends exactly 2 clock periods (20ns) after the write's. That is the
    // MINIMUM-latency observation the errata-12.5 claim is really about, and it is
    // what closes cg_selfclr.cp_read_latency.immediate_next_transfer (a plain
    // sequential pair costs a third clock for the driver's idle cycle -> 30ns ->
    // "delayed"). See pmtpc4_coverage.sv's cp_read_latency comment for the bin
    // arithmetic.
    task b2b_write_then_read(bit [31:0] addr, bit [31:0] wdata, output bit [31:0] rdata);
        bit        wr[$];
        bit [31:0] ad[$], da[$];
        apb_item   items[$];
        wr = '{1, 0};
        ad = '{addr, addr};
        da = '{wdata, 32'h0};
        set_b2b(1);
        raw_b2b(wr, ad, da, items);
        set_b2b(0);
        chk(items.size() == 2, "b2b self-clear pair must produce 2 items");
        chk(!items[0].aborted && !items[1].aborted, "b2b self-clear pair must not abort");
        rdata = items[1].rdata;
    endtask

    task body();
        apb_item it;
        bit [31:0] rd;
        enable_module(0);

        // CTRL.SOFT_RESET (bit 1): write 1, then read on the very next transfer.
        raw(1, 32'h00, EN | 32'h2, it);
        raw(0, 32'h00, 0, it);
        chk(it.rdata[1] == 1'b0, "CTRL.SOFT_RESET must read 0 on the immediately following transfer");

        // Same property, but with a DELAYED read (cp_read_latency.delayed) -- a
        // 2026-09-18 functional-coverage-report audit found the immediate-only form
        // above left this bin permanently unhit.
        raw(1, 32'h00, EN | 32'h2, it);
        cyc(20);
        raw(0, 32'h00, 0, it);
        chk(it.rdata[1] == 1'b0, "CTRL.SOFT_RESET must still read 0 after a delay");

        // CHx_CTRL.CH_START (bit 3) on all four channels.
        for (int ch = 0; ch < 4; ch++) begin
            bit [31:0] base = 32'h20 + ch*32'h10;
            raw(1, base, EN | START, it);
            raw(0, base, 0, it);
            chk(it.rdata[3] == 1'b0,
                $sformatf("CH%0d_CTRL.CH_START must read 0 on the immediately following transfer", ch));
            raw(1, base, 0, it);   // stop the channel again before the next iteration
        end

        // ---- same property at the true MINIMUM latency: write and read-back issued
        // as one APB back-to-back pair (20ns apart, no idle cycle). This is the
        // strongest form of the errata-12.5 claim -- the bit is not observable as 1
        // even by a reader that cannot physically get to the bus any sooner.
        b2b_write_then_read(32'h00, EN | 32'h2, rd);
        chk(rd[1] == 1'b0,
            "CTRL.SOFT_RESET must read 0 on a back-to-back (minimum-latency) read");
        for (int ch = 0; ch < 4; ch++) begin
            bit [31:0] base = 32'h20 + ch*32'h10;
            b2b_write_then_read(base, EN | START, rd);
            chk(rd[3] == 1'b0,
                $sformatf("CH%0d_CTRL.CH_START must read 0 on a back-to-back (minimum-latency) read", ch));
            raw(1, base, 0, it);   // stop the channel again
        end
    endtask
endclass
