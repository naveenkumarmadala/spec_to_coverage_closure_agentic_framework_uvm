// VP-RST-SOFT: SOFT_RESET clears channel/interrupt state, preserves PRESCALER/CLK_SEL.
class pmtpc4_soft_reset_test extends pmtpc4_base_test;
    `uvm_component_utils(pmtpc4_soft_reset_test)
    function new(string n, uvm_component p); super.new(n, p); endfunction
    task run_phase(uvm_phase phase);
        pmtpc4_soft_reset_vseq v = pmtpc4_soft_reset_vseq::type_id::create("v");
        phase.raise_objection(this);
        run_vseq(v);
        #100ns;
        phase.drop_objection(this);
    endtask
endclass
