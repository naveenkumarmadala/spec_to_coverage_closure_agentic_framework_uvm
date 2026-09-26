// =============================================================================
// reg_bit_toggle_cov — reusable, RAL-derived REGISTER-BIT TOGGLE coverage.
//
// Why this exists: Vivado xsim's code-toggle instrumentation cannot measure a PeakRDL
// register block. The field flops live in nested structs (field_storage / hwif_out),
// which xsim does not instrument for toggle, and the per-field `automatic` next-value
// temporaries it DOES list are never updated and cannot be excluded. So the code-toggle
// report can say nothing true about register storage. This collector measures the same
// property from the outside, as functional coverage xsim reports reliably: for every
// bit of every RAL field it records a RISE (0->1) and a FALL (1->0) whenever the DUT's
// own bus read-back shows that bit changed since the previous observation.
//
// Evidence rules (what counts as a toggle -- DUT-observed, never predicted):
//   * READ  : the value the DUT returned on the bus (uvm_reg_predictor -> post_predict
//             UVM_PREDICT_READ). A bit differing from the last observed value is a toggle
//             in the direction of the new value.
//   * WRITE : NOT credited, EXCEPT for SystemRDL `singlepulse` fields (list generated from
//             the RDL by flow/scripts/gen_reg_toggle_cfg.py). Those hold a written 1 for one
//             clock, so no read can ever return 1; the accepted write of 1 credits the rise
//             and the next read returning 0 credits the fall.
//   * Baseline = each field's reset value, re-armed by handle_reset() after any reset.
//     Transitions caused by a reset itself are not credited (not observed on the bus).
//
// Generic: attach(<any uvm_reg_block>) instruments every field it contains. One named
// covergroup instance per field (bit x direction cross) shows up in the xcrg functional
// report; report_phase prints a totals line + every uncovered bit/direction.
// =============================================================================
`ifndef REG_BIT_TOGGLE_COV_SVH
`define REG_BIT_TOGGLE_COV_SVH

// One covergroup per field: every bit x {fall, rise}.
class reg_bit_toggle_field_cg;
    covergroup cg(int unsigned w, string nm) with function sample(int unsigned b, bit rose);
        option.per_instance = 1;
        option.name         = nm;
        cp_bit: coverpoint b    { bins bit_[] = {[0:w-1]}; }
        cp_dir: coverpoint rose { bins fall = {0}; bins rise = {1}; }
        x_bit_dir: cross cp_bit, cp_dir;
    endgroup
    function new(int unsigned w, string nm); cg = new(w, nm); endfunction
endclass

typedef class reg_bit_toggle_cov;

// RAL field callback: forwards every prediction to the collector.
class reg_bit_toggle_cb extends uvm_reg_cbs;
    `uvm_object_utils(reg_bit_toggle_cb)
    reg_bit_toggle_cov owner;
    function new(string name = "reg_bit_toggle_cb"); super.new(name); endfunction
    virtual function void post_predict(input uvm_reg_field  fld,
                                       input uvm_reg_data_t previous,
                                       inout uvm_reg_data_t value,
                                       input uvm_predict_e  kind,
                                       input uvm_path_e     path,
                                       input uvm_reg_map    map);
        if (owner != null) owner.observe(fld, value, kind);
    endfunction
endclass

class reg_bit_toggle_cov extends uvm_component;
    `uvm_component_utils(reg_bit_toggle_cov)

    // "<reg>.<field>" suffixes of singlepulse fields (from the generated <ip>_reg_toggle_cfg.svh)
    string                  pulse_suffixes[$];

    protected uvm_reg_field           flds[string];     // full name -> field
    protected reg_bit_toggle_field_cg cgs[string];
    protected uvm_reg_data_t          last[string];     // last DUT-observed value
    protected bit                     is_pulse[string];
    protected bit                     hit[string];      // "<field>[<bit>].rise|fall" -> seen
    protected reg_bit_toggle_cb       cb;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    // Instrument every field of `blk` (call once, after the RAL model is built/locked).
    function void attach(uvm_reg_block blk);
        uvm_reg_field fs[$];
        cb = reg_bit_toggle_cb::type_id::create("cb");
        cb.owner = this;
        blk.get_fields(fs);
        foreach (fs[i]) begin
            string nm = fs[i].get_full_name();
            flds[nm]     = fs[i];
            cgs[nm]      = new(fs[i].get_n_bits(), nm);
            is_pulse[nm] = 0;
            foreach (pulse_suffixes[j])
                if (has_suffix(nm, pulse_suffixes[j])) is_pulse[nm] = 1;
            uvm_reg_field_cb::add(fs[i], cb);
        end
        handle_reset();
        `uvm_info("REGTOG", $sformatf("instrumented %0d register fields (%0d singlepulse)",
                  flds.num(), count_pulse()), UVM_LOW)
    endfunction

    // After any reset the device is back at reset values: re-arm the baseline.
    function void handle_reset();
        foreach (flds[nm]) last[nm] = flds[nm].get_reset();
    endfunction

    function void observe(uvm_reg_field f, uvm_reg_data_t v, uvm_predict_e kind);
        string nm = f.get_full_name();
        int unsigned w;
        if (!cgs.exists(nm)) return;
        w = f.get_n_bits();
        if (kind == UVM_PREDICT_WRITE) begin
            if (!is_pulse[nm]) return;                     // only singlepulse writes count
            for (int unsigned b = 0; b < w; b++)
                if (v[b] && !last[nm][b]) begin mark(nm, b, 1'b1); last[nm][b] = 1'b1; end
            return;
        end
        if (kind != UVM_PREDICT_READ) return;
        for (int unsigned b = 0; b < w; b++)
            if (v[b] !== last[nm][b]) mark(nm, b, v[b]);
        last[nm] = v;
    endfunction

    protected function void mark(string nm, int unsigned b, bit rose);
        cgs[nm].cg.sample(b, rose);
        hit[$sformatf("%s[%0d].%s", nm, b, rose ? "rise" : "fall")] = 1;
    endfunction

    // Totals: bit-directions covered / total, over every instrumented field.
    function void totals(output int unsigned covered, output int unsigned total);
        covered = 0; total = 0;
        foreach (flds[nm])
            for (int unsigned b = 0; b < flds[nm].get_n_bits(); b++) begin
                total += 2;
                if (hit.exists($sformatf("%s[%0d].rise", nm, b))) covered++;
                if (hit.exists($sformatf("%s[%0d].fall", nm, b))) covered++;
            end
    endfunction

    function void report_phase(uvm_phase phase);
        int unsigned c, t;
        string holes = "", byfield = "";
        int unsigned nholes = 0;
        totals(c, t);
        foreach (flds[nm]) begin
            int unsigned fh = 0;
            for (int unsigned b = 0; b < flds[nm].get_n_bits(); b++)
                for (int k = 0; k < 2; k++) begin
                    string d = (k == 0) ? "rise" : "fall";
                    if (!hit.exists($sformatf("%s[%0d].%s", nm, b, d))) begin
                        nholes++; fh++;
                        if (nholes <= 64) holes = {holes, $sformatf("\n    %s[%0d] %s", nm, b, d)};
                    end
                end
            // per-field summary: never truncated, tells the test-writer WHICH fields still need stimulus
            if (fh != 0)
                byfield = {byfield, $sformatf("\n    %s: %0d of %0d bit-directions uncovered%s", nm, fh,
                           2 * flds[nm].get_n_bits(), is_pulse[nm] ? " (singlepulse)" : "")};
        end
        // Machine-readable totals line (parsed by flow/scripts/run_regression.py).
        `uvm_info("REGTOG", $sformatf("REG_BIT_TOGGLE covered=%0d total=%0d pct=%0.2f fields=%0d",
                  c, t, (t == 0) ? 0.0 : 100.0 * c / t, flds.num()), UVM_NONE)
        if (nholes != 0) begin
            `uvm_info("REGTOG", $sformatf("uncovered by field:%s", byfield), UVM_NONE)
            `uvm_info("REGTOG", $sformatf("%0d uncovered bit-direction(s)%s%s", nholes, holes,
                      (nholes > 64) ? "\n    ..." : ""), UVM_NONE)
        end
    endfunction

    // true iff `s` ends with ".<suf>" (a whole-name boundary, so CTRL.X never matches XCTRL.X)
    protected function bit has_suffix(string s, string suf);
        if (suf.len() + 1 > s.len()) return 0;
        return s.substr(s.len() - suf.len() - 1, s.len() - 1) == {".", suf};
    endfunction

    protected function int unsigned count_pulse();
        count_pulse = 0;
        foreach (is_pulse[nm]) if (is_pulse[nm]) count_pulse++;
    endfunction
endclass

`endif
