// Constrained-random register-traffic test: the dedicated home of the randomized
// stimulus (pmtpc4_rand_vseq). This is the test that receives the multi-seed sweep in
// regression (seeds sized to its random-variable space); the directed/register/full
// tests run at seed 1. See ip_config.yaml verification.regression.seeds_per_test.
class pmtpc4_rand_test extends pmtpc4_base_test;
    `uvm_component_utils(pmtpc4_rand_test)
    function new(string n, uvm_component p); super.new(n, p); endfunction
    task run_phase(uvm_phase phase);
        pmtpc4_rand_vseq v = pmtpc4_rand_vseq::type_id::create("v");
        phase.raise_objection(this);
        run_vseq(v);
        #100ns;
        phase.drop_objection(this);
    endtask
endclass
