// PMTPC-4 environment configuration.
class pmtpc4_env_cfg extends uvm_object;
    `uvm_object_utils(pmtpc4_env_cfg)
    apb_agent_cfg          apb_cfg;
    pmtpc4_pwm_agent_cfg_t pwm_cfg;      // vip/pwm UVC (passive pwm_out observation)
    bit                    en_scoreboard = 1;
    bit                    en_coverage   = 1;
    bit                    en_pwm_agent  = 1;

    // Reset control, published by the testbench top. Non-null means a sequence can
    // assert PRESETn at an arbitrary point in a running simulation (VP-RST-ASYNC).
    virtual reset_if       reset_vif;

    function new(string name = "pmtpc4_env_cfg"); super.new(name); endfunction
endclass
