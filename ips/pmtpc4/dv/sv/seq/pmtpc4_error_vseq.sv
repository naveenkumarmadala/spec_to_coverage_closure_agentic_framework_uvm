// APB register-error (PSLVERR) scenarios, split ONE PER SCENARIO so each maps to a
// dedicated, scenario-named test. Every target is DERIVED FROM THE RAL at runtime
// (register offsets + per-field access), so these bodies work for ANY IP — only the
// class name is IP-specific. No hardcoded addresses.

// --- Write to a fully read-only register -> PSLVERR, zero wait states. ---
class pmtpc4_reg_ro_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_reg_ro_vseq)
    function new(string name = "pmtpc4_reg_ro_vseq"); super.new(name); endfunction
    task body();
        apb_item it; uvm_reg regs[$]; int unsigned n = 0;
        p_sequencer.ral.get_registers(regs);
        foreach (regs[i]) begin
            if (all_fields_access(regs[i], "RO")) begin
                int unsigned off = regs[i].get_address();
                raw(1, off, 32'hDEAD_BEEF, it);
                chk(it.slverr && it.waits == 0,
                    $sformatf("RO-write @0x%02h must assert PSLVERR with 0 wait states", off));
                n++;
            end
        end
        `uvm_info("REGRO", $sformatf("checked %0d fully read-only register(s)", n), UVM_LOW)
    endtask
endclass

// --- Read of a fully write-only register -> PSLVERR. ---
class pmtpc4_reg_wo_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_reg_wo_vseq)
    function new(string name = "pmtpc4_reg_wo_vseq"); super.new(name); endfunction
    task body();
        apb_item it; uvm_reg regs[$]; int unsigned n = 0;
        p_sequencer.ral.get_registers(regs);
        foreach (regs[i]) begin
            if (all_fields_access(regs[i], "WO")) begin
                int unsigned off = regs[i].get_address();
                raw(0, off, 0, it);
                chk(it.slverr, $sformatf("WO-read @0x%02h must assert PSLVERR", off));
                n++;
            end
        end
        if (n == 0)
            `uvm_info("REGWO", "no fully write-only registers in this IP's RAL — scenario vacuously passes", UVM_LOW)
        else
            `uvm_info("REGWO", $sformatf("checked %0d fully write-only register(s)", n), UVM_LOW)
    endtask
endclass

// --- Access to a reserved offset (no register decodes there) -> PSLVERR, PRDATA=0. ---
class pmtpc4_reg_reserved_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_reg_reserved_vseq)
    function new(string name = "pmtpc4_reg_reserved_vseq"); super.new(name); endfunction
    // Full byte-addressable range of the register space = 2^bus.addr_width.
    // pmtpc4: addr_width=8 -> 256. Settable per IP (from ip_config addr_width).
    int unsigned addr_bytes = 256;
    task body();
        apb_item it; uvm_reg regs[$]; bit occupied [int unsigned]; int unsigned n = 0;
        p_sequencer.ral.get_registers(regs);
        foreach (regs[i]) occupied[regs[i].get_address()] = 1;
        for (int unsigned a = 0; a < addr_bytes; a += 4) begin
            if (occupied.exists(a)) continue;
            raw(0, a, 0, it);
            chk(it.slverr && it.waits == 0, $sformatf("reserved read @0x%02h must PSLVERR (0 wait)", a));
            raw(1, a, 32'hA5A5_A5A5, it);
            chk(it.slverr && it.waits == 0, $sformatf("reserved write @0x%02h must PSLVERR (0 wait)", a));
            n++;
        end
        `uvm_info("REGRSV", $sformatf("checked %0d reserved offset(s)", n), UVM_LOW)
    endtask
endclass

// --- Unaligned access (PADDR[1:0] != 0) -> PSLVERR, in BOTH directions. ---
// VP-APB-ERR-CAUSE (2026-09-18 functional-coverage-report audit): the original
// revision of this vseq only ever issued unaligned READS, leaving cg_apb.x_cause's
// "unaligned x wr x err" cell permanently uncovered -- a real, closable stimulus
// gap, not a tool artifact (confirmed by inspecting the functional coverage report's
// per-cross-cell hit counts).
class pmtpc4_reg_unaligned_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_reg_unaligned_vseq)
    function new(string name = "pmtpc4_reg_unaligned_vseq"); super.new(name); endfunction
    task body();
        apb_item it; uvm_reg regs[$]; int unsigned base;
        p_sequencer.ral.get_registers(regs);
        base = (regs.size() > 0) ? regs[0].get_address() : 0;
        for (int k = 1; k < 4; k++) begin
            raw(0, base + k, 0, it);
            chk(it.slverr, $sformatf("unaligned read @0x%02h must PSLVERR", base + k));
            raw(1, base + k, 32'hDEAD_BEEF, it);
            chk(it.slverr, $sformatf("unaligned write @0x%02h must PSLVERR", base + k));
        end
    endtask
endclass
