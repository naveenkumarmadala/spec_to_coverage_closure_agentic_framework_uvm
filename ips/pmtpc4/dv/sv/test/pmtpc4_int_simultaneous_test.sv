// VP-INT-SIMUL: 2/3/4-channel aligned simultaneous expiry.
class pmtpc4_int_simultaneous_test extends pmtpc4_base_test;
    `uvm_component_utils(pmtpc4_int_simultaneous_test)
    function new(string n, uvm_component p); super.new(n, p); endfunction
    task run_phase(uvm_phase phase);
        pmtpc4_int_simultaneous_vseq v = pmtpc4_int_simultaneous_vseq::type_id::create("v");
        phase.raise_objection(this);
        run_vseq(v);
        #100ns;
        phase.drop_objection(this);
    endtask
endclass
