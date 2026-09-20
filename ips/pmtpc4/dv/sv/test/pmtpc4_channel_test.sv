// Directed channel behavior test: runs all channel scenarios sequentially.
class pmtpc4_channel_test extends pmtpc4_base_test;
    `uvm_component_utils(pmtpc4_channel_test)
    function new(string n, uvm_component p); super.new(n, p); endfunction
    task run_phase(uvm_phase phase);
        pmtpc4_oneshot_vseq      s0 = pmtpc4_oneshot_vseq::type_id::create("s0");
        pmtpc4_periodic_vseq     s1 = pmtpc4_periodic_vseq::type_id::create("s1");
        pmtpc4_pause_vseq        s2 = pmtpc4_pause_vseq::type_id::create("s2");
        pmtpc4_freeze_vseq       s3 = pmtpc4_freeze_vseq::type_id::create("s3");
        pmtpc4_softdisable_vseq  s4 = pmtpc4_softdisable_vseq::type_id::create("s4");
        phase.raise_objection(this);
        run_vseq(s0); run_vseq(s1); run_vseq(s2); run_vseq(s3); run_vseq(s4);
        #100ns;
        phase.drop_objection(this);
    endtask
endclass
