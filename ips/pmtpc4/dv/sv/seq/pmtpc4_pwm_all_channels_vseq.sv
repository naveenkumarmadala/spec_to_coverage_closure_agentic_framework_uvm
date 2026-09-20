// VP-PWM-BLACKBOX: four channels with distinct PERIOD/COMPARE running concurrently
// (checking "no cross-talk" -- a leak from one channel into another's pin would be
// caught by pmtpc4_pwm_blackbox_checker regardless of what the other channels are
// doing, since each pin's force-low expectation is derived purely from that
// channel's OWN RAL mirror), plus explicit force-low scenarios (MODULE_EN freeze,
// PWM_EN off, COMPARE>=PERIOD) held long enough (>=2 activity windows) to actually
// exercise the checker's hard-fail path. This vseq only creates the scenarios; all
// checking is pmtpc4_pwm_blackbox_checker's (subscribed to env.pwm_agt.mon.ap), not
// this vseq's.
class pmtpc4_pwm_all_channels_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_pwm_all_channels_vseq)
    function new(string name="pmtpc4_pwm_all_channels_vseq"); super.new(name); endfunction

    localparam bit [31:0] EN=1, MODE=2, PWM=4;

    task body();
        bit [15:0] periods[4]  = '{16'd20, 16'd35, 16'd50, 16'd65};
        bit [15:0] compares[4] = '{16'd5,  16'd17, 16'd49, 16'd64};   // ch2/ch3: lt/eq-ish spread

        enable_module(0);
        for (int ch = 0; ch < 4; ch++) begin
            reg_wr(chan(ch).CH_PERIOD, periods[ch]);
            reg_wr(chan(ch).CH_COMPARE, compares[ch]);
            reg_wr(chan(ch).CH_CTRL, EN|MODE|PWM);   // periodic, PWM on, all four concurrently
        end
        cyc(400);   // several periods each, all four running independently

        // ---- force-low: PWM_EN off on one channel while the others keep running ----
        reg_wr(chan(0).CH_CTRL, EN|MODE);            // PWM_EN off; ch0 must go/stay dark
        cyc(200);

        // ---- force-low: COMPARE>=PERIOD on another channel ----
        reg_wr(chan(1).CH_COMPARE, periods[1]);       // compare_eq_period -> always low
        cyc(200);

        // ---- force-low: whole-module freeze (all four pins forced low at once) ----
        reg_wr(p_sequencer.ral.CTRL, 0);              // MODULE_EN=0
        cyc(200);
        reg_wr(p_sequencer.ral.CTRL, EN);

        cyc(100);
        for (int ch = 0; ch < 4; ch++) reg_wr(chan(ch).CH_CTRL, 0);
    endtask
endclass
