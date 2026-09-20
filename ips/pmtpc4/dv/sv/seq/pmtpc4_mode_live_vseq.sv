// VP-CH-MODE-LIVE (errata 12.2): flip CH_MODE mid-RUNNING and check the outcome at
// the very next EXPIRED evaluation follows the LIVE value, on every channel (not
// just channel 0 -- the existing directed vseqs only ever touch channel 0). This is
// what closes cg_fsm.cp_mode_changed_run.changed_midrun and exercises
// sva/pmtpc4_channel_sva.sv::a_mode_live on the "changed" path, which no existing
// test did.
class pmtpc4_mode_live_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_mode_live_vseq)
    function new(string name="pmtpc4_mode_live_vseq"); super.new(name); endfunction

    localparam bit [31:0] EN=1, MODE=2;

    task flip_oneshot_to_periodic(int ch);
        uvm_reg_data_t v;
        reg_wr(chan(ch).CH_PERIOD, 16'd16);
        reg_wr(chan(ch).CH_CTRL, EN);            // one-shot start
        cyc(4);                                   // now RUNNING, well before expiry
        reg_wr(chan(ch).CH_CTRL, EN|MODE);        // live flip to periodic while RUNNING
        cyc(40);                                   // past the first expiry
        reg_rd(chan(ch).CH_CTRL, v);
        chk(v[0] == 1'b1,
            $sformatf("CH%0d: live flip one-shot->periodic must reload (CH_EN stays 1), not self-clear", ch));
        reg_rd(p_sequencer.ral.INT_STATUS, v);
        chk(v[ch] == 1'b1, $sformatf("CH%0d must have expired at least once", ch));
        reg_wr(p_sequencer.ral.INT_STATUS, (32'h1 << ch));
        reg_wr(chan(ch).CH_CTRL, 0);
    endtask

    task flip_periodic_to_oneshot(int ch);
        uvm_reg_data_t v;
        reg_wr(chan(ch).CH_PERIOD, 16'd16);
        reg_wr(chan(ch).CH_CTRL, EN|MODE);        // periodic start
        cyc(4);
        reg_wr(chan(ch).CH_CTRL, EN);             // live flip to one-shot while RUNNING
        cyc(40);
        reg_rd(chan(ch).CH_CTRL, v);
        chk(v[0] == 1'b0,
            $sformatf("CH%0d: live flip periodic->one-shot must self-clear CH_EN at expiry", ch));
        reg_rd(p_sequencer.ral.INT_STATUS, v);
        chk(v[ch] == 1'b1, $sformatf("CH%0d must have expired", ch));
        reg_wr(p_sequencer.ral.INT_STATUS, (32'h1 << ch));
    endtask

    task body();
        enable_module(0);
        for (int ch = 0; ch < 4; ch++) begin
            flip_oneshot_to_periodic(ch);
            flip_periodic_to_oneshot(ch);
        end
    endtask
endclass
