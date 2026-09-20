// VP-INT-SIMUL: align 2, then 3, then 4 channels so they expire on the identical
// prescaled tick. Uses a PRESCALER large relative to the few cycles of APB write
// latency needed to start N channels, so every channel is well into LOAD before the
// next shared tick_en fires -- they all transition LOAD->RUNNING on that SAME tick
// and (same PERIOD) decrement and expire in lockstep thereafter. This vseq only
// creates the alignment and checks the resulting register state; whether the
// channels' expiry pulses actually coincided on one cycle is what
// pmtpc4_top_sva.sv's cg_int.cp_n_simultaneous (sampled from ch_expiry, not by this
// vseq) measures.
class pmtpc4_int_simultaneous_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_int_simultaneous_vseq)
    function new(string name="pmtpc4_int_simultaneous_vseq"); super.new(name); endfunction

    localparam bit [31:0] EN=1;
    localparam bit [15:0] PRESC = 16'd50;   // >> the ~cycles needed to start up to 4 channels
    localparam bit [15:0] PER   = 16'd4;

    task align(int n);
        bit [31:0] mask = (32'h1 << n) - 1;
        uvm_reg_data_t v;
        reg_wr(p_sequencer.ral.INT_STATUS, 4'hF);           // start clean
        reg_wr(p_sequencer.ral.PRESCALER, PRESC);
        reg_wr(p_sequencer.ral.CTRL, EN);
        for (int ch = 0; ch < n; ch++) begin
            reg_wr(chan(ch).CH_PERIOD, PER);
            reg_wr(chan(ch).CH_CTRL, EN);                   // one-shot start
        end
        cyc((PER + 3) * (PRESC + 1) + 100);
        reg_rd(p_sequencer.ral.INT_STATUS, v);
        chk((v[3:0] & mask[3:0]) == mask[3:0],
            $sformatf("aligning %0d channels: expected bits 0x%0h set, got 0x%0h", n, mask[3:0], v[3:0]));
        reg_wr(p_sequencer.ral.INT_STATUS, 4'hF);
        reg_wr(p_sequencer.ral.PRESCALER, 0);
    endtask

    task body();
        enable_module(0);
        align(2);
        align(3);
        align(4);
    endtask
endclass
