// VP-PRESC-RATIO: divide-by-(N+1) timing + mid-run change without corruption.
class pmtpc4_prescaler_test extends pmtpc4_base_test;
    `uvm_component_utils(pmtpc4_prescaler_test)
    function new(string n, uvm_component p); super.new(n, p); endfunction
    task run_phase(uvm_phase phase);
        pmtpc4_prescaler_vseq v = pmtpc4_prescaler_vseq::type_id::create("v");
        phase.raise_objection(this);
        run_vseq(v);
        #100ns;
        phase.drop_objection(this);
    endtask
endclass
