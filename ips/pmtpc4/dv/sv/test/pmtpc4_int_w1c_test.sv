// VP-INT-W1C: per-bit INT_STATUS hw-set / write-0-holds / write-1-clears.
class pmtpc4_int_w1c_test extends pmtpc4_base_test;
    `uvm_component_utils(pmtpc4_int_w1c_test)
    function new(string n, uvm_component p); super.new(n, p); endfunction
    task run_phase(uvm_phase phase);
        pmtpc4_int_w1c_vseq v = pmtpc4_int_w1c_vseq::type_id::create("v");
        phase.raise_objection(this);
        run_vseq(v);
        #100ns;
        phase.drop_objection(this);
    endtask
endclass
