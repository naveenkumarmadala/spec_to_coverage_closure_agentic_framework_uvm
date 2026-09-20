// Smoke: reset value, one RW round-trip, and a legal CHx_COUNT read (1 wait state).
class pmtpc4_smoke_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_smoke_vseq)
    function new(string name = "pmtpc4_smoke_vseq"); super.new(name); endfunction
    task body();
        uvm_reg_data_t v; apb_item it;
        reg_rd(p_sequencer.ral.PRESCALER, v);
        if (v != 0) `uvm_error("SMOKE", "PRESCALER reset value not 0")
        reg_wr(p_sequencer.ral.PRESCALER, 32'h1234);
        reg_rd(p_sequencer.ral.PRESCALER, v);
        if (v != 16'h1234) `uvm_error("SMOKE", "PRESCALER round-trip failed")
        raw(0, 8'h2C, 0, it);   // CH0_COUNT read
        if (it.waits != 1) `uvm_error("SMOKE", $sformatf("CH0_COUNT read waits=%0d (exp 1)", it.waits))
    endtask
endclass
