// Register scenario: read of a write-only register -> PSLVERR (RAL-derived).
// pmtpc4 has no fully-WO register, so this scenario is vacuously covered here; the
// generic vseq exercises it for any IP that does have WO registers.
class pmtpc4_reg_wo_test extends pmtpc4_base_test;
    `uvm_component_utils(pmtpc4_reg_wo_test)
    function new(string n, uvm_component p); super.new(n, p); endfunction
    task run_phase(uvm_phase phase);
        pmtpc4_reg_wo_vseq v = pmtpc4_reg_wo_vseq::type_id::create("v");
        phase.raise_objection(this);
        run_vseq(v);
        #100ns;
        phase.drop_objection(this);
    endtask
endclass
