// PWM agent — passive by construction (the UVC observes output pins; there is
// nothing to drive, so there is no driver/sequencer).
class pwm_agent #(parameter int unsigned NUM_PINS = 1) extends uvm_agent;
    `uvm_component_param_utils(pwm_agent#(NUM_PINS))

    pwm_agent_cfg #(NUM_PINS) cfg;
    pwm_monitor   #(NUM_PINS) mon;

    function new(string n, uvm_component p);
        super.new(n, p);
        is_active = UVM_PASSIVE;
    endfunction

    function void build_phase(uvm_phase phase);
        if (!uvm_config_db#(pwm_agent_cfg#(NUM_PINS))::get(this, "", "cfg", cfg))
            `uvm_fatal("NOCFG", "pwm_agent_cfg not set")
        is_active = UVM_PASSIVE;
        uvm_config_db#(pwm_agent_cfg#(NUM_PINS))::set(this, "mon", "cfg", cfg);
        mon = pwm_monitor#(NUM_PINS)::type_id::create("mon", this);
    endfunction
endclass
