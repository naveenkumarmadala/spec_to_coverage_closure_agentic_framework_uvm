// VP-SELFCLR: SOFT_RESET / CH_START never observable as 1 on the next read.
class pmtpc4_selfclear_test extends pmtpc4_base_test;
    `uvm_component_utils(pmtpc4_selfclear_test)
    function new(string n, uvm_component p); super.new(n, p); endfunction
    task run_phase(uvm_phase phase);
        pmtpc4_selfclear_vseq v = pmtpc4_selfclear_vseq::type_id::create("v");
        phase.raise_objection(this);
        run_vseq(v);
        #100ns;
        phase.drop_objection(this);
    endtask
endclass
