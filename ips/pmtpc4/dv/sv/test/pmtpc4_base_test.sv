// Base test: build env + configs, fetch vif, provide a run_vseq helper.
class pmtpc4_base_test extends uvm_test;
    `uvm_component_utils(pmtpc4_base_test)
    pmtpc4_env      env;
    pmtpc4_env_cfg  cfg;
    apb_agent_cfg   apb_cfg;

    function new(string n, uvm_component p); super.new(n, p); endfunction

    pmtpc4_pwm_agent_cfg_t pwm_cfg;

    function void build_phase(uvm_phase phase);
        apb_cfg = apb_agent_cfg::type_id::create("apb_cfg");
        apb_cfg.is_active = UVM_ACTIVE;
        apb_cfg.en_cov    = 1;
        // Back-to-back (ACCESS->SETUP with PSEL held) is opt-in per test; default off
        // keeps every existing test's bus behaviour byte-identical.
        apb_cfg.b2b_enable = 0;
        if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", apb_cfg.vif))
            `uvm_fatal("NOVIF", "virtual apb_if not set by testbench")

        cfg = pmtpc4_env_cfg::type_id::create("cfg");
        cfg.apb_cfg = apb_cfg;

        // vip/pwm UVC: passive observation of pwm_out[3:0] at the TB boundary.
        pwm_cfg = pmtpc4_pwm_agent_cfg_t::type_id::create("pwm_cfg");
        pwm_cfg.num_pins        = PMTPC4_NUM_PWM;
        pwm_cfg.activity_window = 64;      // clocks per cp_activity sample
        if (!uvm_config_db#(pmtpc4_pwm_vif_t)::get(this, "", "pwm_vif", pwm_cfg.vif))
            `uvm_fatal("NOVIF", "virtual pwm_if not set by testbench")
        cfg.pwm_cfg = pwm_cfg;

        // Reset control hook (VP-RST-ASYNC). Optional: absence only means no test in
        // this run can pulse PRESETn mid-simulation, so warn rather than fatal.
        if (!uvm_config_db#(virtual reset_if)::get(this, "", "reset_vif", cfg.reset_vif))
            `uvm_warning("NORSTVIF", "virtual reset_if not set by testbench: mid-simulation reset unavailable")

        uvm_config_db#(pmtpc4_env_cfg)::set(this, "env", "cfg", cfg);
        env = pmtpc4_env::type_id::create("env", this);
    endfunction

    task run_vseq(pmtpc4_base_vseq seq);
        seq.start(env.vseqr);
    endtask

    function void end_of_elaboration_phase(uvm_phase phase);
        uvm_top.print_topology();
    endfunction
endclass
