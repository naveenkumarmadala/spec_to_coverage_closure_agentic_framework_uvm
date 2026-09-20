// VP-CH-COUNT-READBACK: CHx_COUNT read over APB/RAL returns the register's live
// value, not just that the internal net loads/decrements correctly (VP-CH-COUNT-
// VALUE's SVA layer already proves that). Checked directly here (COUNT<=PERIOD just
// after LOAD, and strictly decreasing across a wait) AND by
// pmtpc4_scoreboard.sv's bound-check (every CHx_COUNT read, for the rest of the
// regression, is compared against the last-written PERIOD -- see readmask()'s
// comment) -- this test is what actually exercises that bound-check path, which
// previously was skipped entirely (readmask() returned -1 for CH_COUNT).
class pmtpc4_count_value_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_count_value_vseq)
    function new(string name="pmtpc4_count_value_vseq"); super.new(name); endfunction

    localparam bit [31:0] EN=1, MODE=2;

    task check_channel(int ch, bit [15:0] per_v);
        uvm_reg_data_t c1, c2, c3;
        reg_wr(p_sequencer.ral.PRESCALER, 16'd3);   // slow enough that reads land mid-count
        reg_wr(p_sequencer.ral.CTRL, EN);
        reg_wr(chan(ch).CH_PERIOD, per_v);
        reg_wr(chan(ch).CH_CTRL, EN|MODE);          // periodic, keeps running
        reg_rd(chan(ch).CH_COUNT, c1);
        chk(c1 <= per_v, $sformatf("CH%0d_COUNT readback 0x%0h must never exceed PERIOD 0x%0h", ch, c1, per_v));
        cyc(20);
        reg_rd(chan(ch).CH_COUNT, c2);
        chk(c2 <= per_v, $sformatf("CH%0d_COUNT readback 0x%0h must never exceed PERIOD 0x%0h", ch, c2, per_v));
        chk(c2 != c1, $sformatf("CH%0d_COUNT must have advanced between two reads 20 cycles apart", ch));
        cyc(20);
        reg_rd(chan(ch).CH_COUNT, c3);
        chk(c3 <= per_v, $sformatf("CH%0d_COUNT readback 0x%0h must never exceed PERIOD 0x%0h", ch, c3, per_v));
        reg_wr(chan(ch).CH_CTRL, 0);
        reg_wr(p_sequencer.ral.PRESCALER, 0);
    endtask

    task body();
        check_channel(0, 16'h00FF);
        check_channel(1, 16'h0FFF);
        check_channel(2, 16'h0010);
        check_channel(3, 16'hFFFF);
    endtask
endclass
