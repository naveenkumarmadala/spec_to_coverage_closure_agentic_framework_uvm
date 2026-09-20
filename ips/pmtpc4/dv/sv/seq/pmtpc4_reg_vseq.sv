// Register access-policy vseqs via UVM built-in RAL sequences, split ONE PER SCENARIO
// so each maps to a dedicated, scenario-named test. RAL-driven and IP-agnostic.

// --- Reset / default values: checks every field's reset value (RAL-driven). ---
class pmtpc4_reg_reset_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_reg_reset_vseq)
    function new(string name = "pmtpc4_reg_reset_vseq"); super.new(name); endfunction
    task body();
        uvm_reg_hw_reset_seq rst = uvm_reg_hw_reset_seq::type_id::create("rst");
        rst.model = p_sequencer.ral;
        rst.start(null);
    endtask
endclass

// --- Read/write access policy: walking-bit write/read of every writable field. ---
class pmtpc4_reg_rw_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_reg_rw_vseq)
    function new(string name = "pmtpc4_reg_rw_vseq"); super.new(name); endfunction

    // This IP returns PSLVERR on writes to read-only registers (per spec). The built-in
    // uvm_reg_bit_bash_seq writes RO fields expecting OKAY (unchanged), so it flags every
    // RO-register write as UVM_NOT_OK. Exclude fully-RO registers from bit-bash; their RO
    // policy is covered by the reset vseq (reset values) and the RO-write vseq (PSLVERR).
    // Generic: any register whose every field is "RO".
    function void exclude_ro_from_bitbash();
        uvm_reg regs[$];
        p_sequencer.ral.get_registers(regs);
        foreach (regs[i])
            if (all_fields_access(regs[i], "RO"))
                uvm_resource_db#(bit)::set(
                    {"REG::", regs[i].get_full_name()}, "NO_REG_BIT_BASH_TEST", 1);
    endfunction

    task body();
        uvm_reg_bit_bash_seq bb = uvm_reg_bit_bash_seq::type_id::create("bb");
        exclude_ro_from_bitbash();
        bb.model = p_sequencer.ral;
        bb.start(null);
    endtask
endclass

// --- Write-data upper-bit robustness (VP-REG-ACCESS): a raw (non-RAL) write with
// garbage in the bus's unused upper bits on a register whose field is narrower than
// the bus, confirming the RTL actually ignores them rather than the environment just
// assuming it. This is deliberately a raw() write, not reg_wr() -- the RAL model
// always zero-extends a 16-bit field to the full 32-bit bus word, so a RAL-driven
// write could never exercise this even by accident.
//
// This is also the correct closure for cpuif_wr_data[31:16]'s toggle-coverage gap
// (see reports/coverage_waivers.md / coverage-triage skill): those bits are driven
// by PWDATA and are only ever zero because of the RAL's own write habit, not because
// the RTL structurally prevents them from varying -- unlike the read side
// (cpuif_rd_data_pad, genuinely, permanently zero by construction, correctly handled
// with an RTL split + waiver instead), so real stimulus is the right fix here, not a
// split. pmtpc4_scoreboard's readmask (0xFFFF for a 16-bit field) already anticipates
// exactly this masking, so no scoreboard changes are needed for this to pass on
// correct RTL.
class pmtpc4_wdata_upper_bits_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_wdata_upper_bits_vseq)
    function new(string name = "pmtpc4_wdata_upper_bits_vseq"); super.new(name); endfunction
    task body();
        apb_item it;
        uvm_reg_data_t rd;
        bit [31:0] addr = chan(0).CH_PERIOD.get_address();
        // garbage in [31:16], a real legal 16-bit field value in [15:0]
        raw(1, addr, 32'hBEEF_002A, it);
        reg_rd(chan(0).CH_PERIOD, rd);
        chk(rd == 'h002A, $sformatf(
            "CH0_PERIOD must read back only the lower 16 bits written (0x002A); upper garbage (0xBEEF) must be ignored -- got 0x%0h", rd));
        // a second, different pattern so the upper bits also toggle 1->0 (not just 0->1)
        raw(1, addr, 32'h1357_1000, it);
        reg_rd(chan(0).CH_PERIOD, rd);
        chk(rd == 'h1000, $sformatf(
            "CH0_PERIOD must still read back only the lower 16 bits after a second garbage-upper write -- got 0x%0h", rd));
    endtask
endclass
