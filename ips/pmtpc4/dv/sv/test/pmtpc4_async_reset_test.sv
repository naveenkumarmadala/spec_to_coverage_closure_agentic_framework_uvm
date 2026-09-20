// VP-RST-ASYNC: async PRESETn from RUNNING/PAUSED/EXPIRED/mid-APB-ACCESS.
class pmtpc4_async_reset_test extends pmtpc4_base_test;
    `uvm_component_utils(pmtpc4_async_reset_test)
    function new(string n, uvm_component p); super.new(n, p); endfunction
    task run_phase(uvm_phase phase);
        pmtpc4_async_reset_vseq v = pmtpc4_async_reset_vseq::type_id::create("v");
        phase.raise_objection(this);
        run_vseq(v);
        #100ns;
        phase.drop_objection(this);
    endtask
endclass
