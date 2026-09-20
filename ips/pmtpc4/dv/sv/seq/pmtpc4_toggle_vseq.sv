// Toggle-closure sequence: drives the DUT datapath so every *reachable* register/
// datapath bit flips 0<->1 for code toggle coverage. Complements cov_close (FSM/config)
// and rand (random traffic). Targets the bits that only move under specific stimulus:
//   - full-range register storage: walking-1 / walking-0 / AA / 55 on PERIOD & COMPARE
//     (all 4 channels) so every storage bit toggles both directions;
//   - channel datapath: compare_shadow (loaded from COMPARE at LOAD), pwm_level (PWM
//     output high/low), start_trig (pulses on CH_EN rising) -- exercised by PWM-active
//     runs with the compare swept below, above, and mid the period;
//   - a free-running prescaler so its counter low bits toggle.
// Structurally-static bits (unused upper bus bits, wrapper-bypassed regblock error nets,
// parked reserved/RO storage) cannot be toggled by any stimulus -> those are waived, not
// chased here (see the coverage waiver list).
class pmtpc4_toggle_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_toggle_vseq)
    function new(string name="pmtpc4_toggle_vseq"); super.new(name); endfunction

    localparam bit [31:0] EN=1, MODE=2, PWM=4;

    // write a pattern set that flips every bit of a 16-bit field both ways
    task walk16(uvm_reg r);
        reg_wr(r, 16'h0000);
        reg_wr(r, 16'hFFFF);   // every bit 0->1
        reg_wr(r, 16'h0000);   // every bit 1->0
        reg_wr(r, 16'hAAAA);
        reg_wr(r, 16'h5555);   // every bit toggles vs AAAA
    endtask

    task body();
        reg_wr(p_sequencer.ral.PRESCALER, 0);
        reg_wr(p_sequencer.ral.CTRL, EN);                 // MODULE_EN=1

        // --- full-range storage toggle on every channel's PERIOD & COMPARE ---
        for (int ch = 0; ch < 4; ch++) begin
            walk16(chan(ch).CH_PERIOD);
            walk16(chan(ch).CH_COMPARE);
        end
        // --- config-register storage toggle ---
        walk16(p_sequencer.ral.PRESCALER);
        reg_wr(p_sequencer.ral.PRESCALER, 0);
        reg_wr(p_sequencer.ral.INT_ENABLE, 4'hF);
        reg_wr(p_sequencer.ral.INT_ENABLE, 4'h0);
        reg_wr(p_sequencer.ral.GLOBAL_IE, 1);
        reg_wr(p_sequencer.ral.GLOBAL_IE, 0);

        // --- channel datapath: PWM active, compare swept below/at/above period so
        //     pwm_level and compare_shadow both toggle; CH_EN cycled so start_trig pulses ---
        for (int ch = 0; ch < 4; ch++) begin
            begin
                bit [15:0] cmps [4] = '{16'h0001, 16'h0008, 16'h000F, 16'h0000};
                reg_wr(chan(ch).CH_PERIOD, 16'h000F);
                foreach (cmps[k]) begin
                    reg_wr(chan(ch).CH_CTRL, 0);              // ensure CH_EN low
                    reg_wr(chan(ch).CH_COMPARE, cmps[k]);
                    reg_wr(chan(ch).CH_CTRL, EN|MODE|PWM);   // CH_EN rising -> start_trig; periodic+PWM
                    cyc(24);                                 // run through several periods
                end
            end
            reg_wr(chan(ch).CH_CTRL, 0);                      // stop
        end

        // --- free-running prescaler so its counter low bits toggle ---
        reg_wr(p_sequencer.ral.PRESCALER, 16'h000F);
        reg_wr(chan(0).CH_PERIOD, 16'h0004);
        reg_wr(chan(0).CH_CTRL, EN|MODE|PWM);                // periodic keeps prescaler ticking
        cyc(200);
        reg_wr(chan(0).CH_CTRL, 0);
        reg_wr(p_sequencer.ral.PRESCALER, 0);
    endtask
endclass
