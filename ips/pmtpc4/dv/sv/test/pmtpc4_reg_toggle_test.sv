// Register-block toggle closure test: every register field bit shown rising and falling
// in the DUT's bus read-back (reg_bit_toggle_cov). See pmtpc4_reg_toggle_vseq.
class pmtpc4_reg_toggle_test extends pmtpc4_base_test;
    `uvm_component_utils(pmtpc4_reg_toggle_test)
    function new(string n, uvm_component p); super.new(n, p); endfunction
    task run_phase(uvm_phase phase);
        pmtpc4_reg_toggle_vseq v = pmtpc4_reg_toggle_vseq::type_id::create("v");
        phase.raise_objection(this);
        run_vseq(v);
        #100ns;
        phase.drop_objection(this);
    endtask
endclass
