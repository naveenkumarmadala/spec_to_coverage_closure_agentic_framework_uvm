// VP-INT-SETPRI: free-run a short-PERIOD periodic channel and issue W1C writes at
// swept phase offsets so a write lands on the same cycle as the channel's expiry
// pulse (Design 7.2 / REQ-INT-1: hw-set wins the collision, precedence=hw in the
// RDL). This vseq only creates the scenario -- whether the exact collision cycle
// was actually hit is confirmed by sva/pmtpc4_top_sva.sv's cov_int_set_priority
// `cover property` (sampled by the SVA, never by this vseq), and any violation of
// the set-priority rule itself is caught continuously by a_int_set_priority. The
// directed self-check here is weaker by necessity (the race is racy w.r.t. bus
// timing) -- it confirms the channel keeps expiring normally afterward, i.e. the
// race never corrupts or drops a subsequent event.
class pmtpc4_int_setpriority_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_int_setpriority_vseq)
    function new(string name="pmtpc4_int_setpriority_vseq"); super.new(name); endfunction

    localparam bit [31:0] EN=1, MODE=2;
    localparam bit [15:0] PER = 16'd6;

    task body();
        uvm_reg_data_t v;
        apb_item it;
        enable_module(0);
        reg_wr(p_sequencer.ral.INT_STATUS, 4'hF);
        reg_wr(chan(0).CH_PERIOD, PER);
        reg_wr(chan(0).CH_CTRL, EN|MODE);        // periodic, free-running

        // Sweep the write's phase across more than one full period so some iteration's
        // completing cycle lands on an expiry cycle.
        for (int k = 0; k < 2*PER; k++) begin
            cyc(1);
            raw(1, 32'h60, 32'h1, it);           // W1C write of bit0 (INT_STATUS)
        end

        // No lockup / dropped-event check: the channel must still be visibly
        // re-expiring after the sweep, W1C-clearable as normal.
        reg_wr(p_sequencer.ral.INT_STATUS, 4'h1);
        cyc(3*PER);
        reg_rd(p_sequencer.ral.INT_STATUS, v);
        chk(v[0] == 1'b1, "periodic channel 0 must still be re-expiring after the set-priority sweep");
        reg_wr(chan(0).CH_CTRL, 0);
        reg_wr(p_sequencer.ral.INT_STATUS, 4'hF);
    endtask
endclass
