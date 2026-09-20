// VP-REG-ACCESS: a raw write with garbage in the bus's unused upper bits on a
// register narrower than the bus must not corrupt the field's readback value.
class pmtpc4_wdata_upper_bits_test extends pmtpc4_base_test;
    `uvm_component_utils(pmtpc4_wdata_upper_bits_test)
    function new(string n, uvm_component p); super.new(n, p); endfunction
    task run_phase(uvm_phase phase);
        pmtpc4_wdata_upper_bits_vseq v = pmtpc4_wdata_upper_bits_vseq::type_id::create("v");
        phase.raise_objection(this);
        run_vseq(v);
        #100ns;
        phase.drop_objection(this);
    endtask
endclass
