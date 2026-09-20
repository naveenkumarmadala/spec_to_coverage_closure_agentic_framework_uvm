// VP-CH-MODE-LIVE: CH_MODE flipped mid-RUNNING on every channel, both directions.
class pmtpc4_mode_live_test extends pmtpc4_base_test;
    `uvm_component_utils(pmtpc4_mode_live_test)
    function new(string n, uvm_component p); super.new(n, p); endfunction
    task run_phase(uvm_phase phase);
        pmtpc4_mode_live_vseq v = pmtpc4_mode_live_vseq::type_id::create("v");
        phase.raise_objection(this);
        run_vseq(v);
        #100ns;
        phase.drop_objection(this);
    endtask
endclass
