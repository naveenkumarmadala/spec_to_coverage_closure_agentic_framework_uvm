// APB protocol functional coverage (address x rw x error x wait).
class apb_coverage extends uvm_subscriber #(apb_item);
    `uvm_component_utils(apb_coverage)
    apb_item tr;

    // VP-APB-ERR-CAUSE: a dedicated, narrow classification of the error CAUSE (as
    // opposed to cp_addr's per-register granularity) so the x_cause cross below stays
    // small — exactly the reserved/unaligned/RO-write cells the item asks for, not a
    // full cp_addr x cp_rw x cp_err explosion. RO-write is only the cause when the
    // access is actually a write to a fully-RO offset; a READ of an RO register is a
    // perfectly legal access (cause_legal), matching the DUT's real PSLVERR decode.
    typedef enum { CAUSE_RESERVED, CAUSE_UNALIGNED, CAUSE_RO_WRITE, CAUSE_LEGAL } cause_e;
    function cause_e classify_cause(apb_item t);
        bit [7:0] a = t.addr[7:0];
        if (a[1:0] != 0) return CAUSE_UNALIGNED;
        if (a inside {8'h18, 8'h1C, 8'h68, 8'h6C, 8'h70, 8'hFC}) return CAUSE_RESERVED;
        if (t.write && (a==8'h04 || a==8'h0C || a==8'h2C || a==8'h3C || a==8'h4C || a==8'h5C))
            return CAUSE_RO_WRITE;
        return CAUSE_LEGAL;
    endfunction

    covergroup cg_apb;
        option.per_instance = 1;
        cp_rw:  coverpoint tr.write   { bins rd = {0}; bins wr = {1}; }
        cp_err: coverpoint tr.slverr  { bins ok = {0}; bins err = {1}; }
        cp_wait:coverpoint tr.waits   { bins zero = {0}; bins one = {1}; bins many = {[2:$]}; }
        cp_addr:coverpoint tr.addr[7:0] {
            bins ctrl = {8'h00}; bins status = {8'h04}; bins gie = {8'h08}; bins gisr = {8'h0C};
            bins presc = {8'h10}; bins clksel = {8'h14};
            bins ch_ctrl[]   = {8'h20, 8'h30, 8'h40, 8'h50};
            bins ch_period[] = {8'h24, 8'h34, 8'h44, 8'h54};
            bins ch_cmp[]    = {8'h28, 8'h38, 8'h48, 8'h58};
            bins ch_count[]  = {8'h2C, 8'h3C, 8'h4C, 8'h5C};
            bins intstat = {8'h60}; bins inten = {8'h64};
            bins reserved[]  = {8'h18, 8'h1C, 8'h68, 8'h6C, 8'h70, 8'hFC};
            bins unaligned   = {[8'h01:8'hFF]} with (item[1:0] != 0);
        }
        cp_cause: coverpoint classify_cause(tr) {
            bins reserved = {CAUSE_RESERVED};
            bins unaligned = {CAUSE_UNALIGNED};
            bins ro_write  = {CAUSE_RO_WRITE};
            bins legal     = {CAUSE_LEGAL};
        }
        x_rw_err: cross cp_rw, cp_err;
        // VP-APB-ERR-CAUSE: each error CAUSE class proven in BOTH directions (read AND
        // write), not just in aggregate. Every "legal" cell is ignored (cp_addr x cp_rw
        // already covers "which register, ok" — that is not this item's job), and every
        // structurally-impossible cell (a RO-write cause can only coincide with a WRITE
        // and with err=1) is ignored too. What survives is exactly the 5 real cells:
        // reserved x {rd,wr}, unaligned x {rd,wr}, ro_write x wr — all err=1 by
        // construction, so cp_err doesn't even need to appear as an ignore dimension.
        x_cause: cross cp_cause, cp_rw, cp_err {
            ignore_bins legal_all       = binsof(cp_cause.legal);
            ignore_bins ro_rd_impossible = binsof(cp_cause.ro_write) && binsof(cp_rw.rd);
            ignore_bins nonlegal_ok_impossible = !binsof(cp_cause.legal) && binsof(cp_err.ok);
        }
        // VP-APB-WAIT-ERR / errata 12.4: an errored access never inserts a wait state.
        // The ignore_bin IS the errata statement — the remaining cells are exactly
        // normal_0ws (ok,zero), count_rd_1ws (ok,one) and err_0ws (err,zero).
        x_wait_err: cross cp_wait, cp_err {
            ignore_bins err_waited = binsof(cp_err.err) && binsof(cp_wait.one);
            // cp_wait.many (>=2 waits) is itself unreachable by design (this
            // completer inserts at most 1 wait state -- see VP-APB-WAIT's own
            // signed-off waiver) and stays waived; excluded here too so it does
            // not ALSO show up as an uncovered cross cell.
            ignore_bins many_unreachable = binsof(cp_wait.many);
        }
    endgroup

    function new(string n, uvm_component p); super.new(n, p); cg_apb = new(); endfunction
    function void write(apb_item t); tr = t; cg_apb.sample(); endfunction
endclass
