// PWM UVC configuration. Parameterized on pin count so the UVC works for any
// IP's output width; everything else is a runtime knob.
class pwm_agent_cfg #(parameter int unsigned NUM_PINS = 1) extends uvm_object;
    `uvm_object_param_utils(pwm_agent_cfg#(NUM_PINS))

    virtual pwm_if #(NUM_PINS) vif;

    // Number of pins actually connected/observed (<= NUM_PINS). Lets an IP with a
    // narrower bus reuse a wider-parameterized instance without spurious coverage.
    int unsigned num_pins = NUM_PINS;

    // Periodic activity sampling: emit one PWM_WINDOW item per pin every N sampling
    // clocks. 0 disables activity sampling (edge items only).
    int unsigned activity_window = 64;

    // Emit an item for every observed edge. Leave on; the analysis port is the only
    // way anything outside the DUT can see the waveform.
    bit en_edge_items = 1;

    function new(string name = "pwm_agent_cfg"); super.new(name); endfunction
endclass
