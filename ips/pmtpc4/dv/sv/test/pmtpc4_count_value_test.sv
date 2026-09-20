// VP-CH-COUNT-READBACK: CHx_COUNT read over APB/RAL against the programmed PERIOD.
class pmtpc4_count_value_test extends pmtpc4_base_test;
    `uvm_component_utils(pmtpc4_count_value_test)
    function new(string n, uvm_component p); super.new(n, p); endfunction
    task run_phase(uvm_phase phase);
        pmtpc4_count_value_vseq v = pmtpc4_count_value_vseq::type_id::create("v");
        phase.raise_objection(this);
        run_vseq(v);
        #100ns;
        phase.drop_objection(this);
    endtask
endclass
