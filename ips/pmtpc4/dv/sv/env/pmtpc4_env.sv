// PMTPC-4 environment: APB agent + reg predictor/RAL + scoreboard + coverage + vseqr,
// plus the passive vip/pwm UVC observing pwm_out at the TB boundary (VP-PWM-BLACKBOX).
// RAL top block class is named 'pmtpc4' (from the RDL addrmap) — same as the DUT module;
// pmtpc4_reg_block_t aliases it (::type_id::create can't resolve back to the module this
// way). Now defined package-wide in pmtpc4_test_pkg.sv (needed by files included earlier
// than this one, e.g. pmtpc4_pwm_blackbox_checker.sv).
class pmtpc4_env extends uvm_env;
    `uvm_component_utils(pmtpc4_env)
    pmtpc4_env_cfg                cfg;
    apb_agent                     agent;
    pmtpc4_pwm_agent_t            pwm_agt;   // passive: observes pwm_out[3:0]
    pmtpc4_scoreboard             scb;
    pmtpc4_coverage               cov;
    pmtpc4_pwm_coverage           pwm_cov;
    pmtpc4_pwm_blackbox_checker   pwm_bb;    // VP-PWM-BLACKBOX checker
    pmtpc4_reg_block_t            ral;   // aliased RAL block (name collides with DUT module 'pmtpc4')
    apb_reg_adapter               adapter;
    uvm_reg_predictor #(apb_item) predictor;
    pmtpc4_vseqr                  vseqr;

    function new(string n, uvm_component p); super.new(n, p); endfunction

    function void build_phase(uvm_phase phase);
        if (!uvm_config_db#(pmtpc4_env_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal("NOCFG", "pmtpc4_env_cfg not set")
        uvm_config_db#(apb_agent_cfg)::set(this, "agent", "cfg", cfg.apb_cfg);
        agent = apb_agent::type_id::create("agent", this);
        if (cfg.en_pwm_agent && cfg.pwm_cfg != null) begin
            uvm_config_db#(pmtpc4_pwm_agent_cfg_t)::set(this, "pwm_agt", "cfg", cfg.pwm_cfg);
            pwm_agt = pmtpc4_pwm_agent_t::type_id::create("pwm_agt", this);
            if (cfg.en_coverage) pwm_cov = pmtpc4_pwm_coverage::type_id::create("pwm_cov", this);
            pwm_bb = pmtpc4_pwm_blackbox_checker::type_id::create("pwm_bb", this);
        end
        if (cfg.en_scoreboard) scb = pmtpc4_scoreboard::type_id::create("scb", this);
        if (cfg.en_coverage)   cov = pmtpc4_coverage::type_id::create("cov", this);
        if (ral == null) begin
            ral = new("ral");   // PeakRDL RAL block is not factory-registered; construct with new()
            ral.build();
            ral.lock_model();
        end
        adapter   = apb_reg_adapter::type_id::create("adapter");
        predictor = uvm_reg_predictor#(apb_item)::type_id::create("predictor", this);
        vseqr     = pmtpc4_vseqr::type_id::create("vseqr", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        if (cfg.en_scoreboard) agent.mon.ap.connect(scb.sb_imp);
        if (cfg.en_coverage)   agent.mon.ap.connect(cov.analysis_export);
        agent.mon.ap.connect(predictor.bus_in);
        predictor.map     = ral.default_map;
        predictor.adapter = adapter;
        ral.default_map.set_sequencer(agent.seqr, adapter);
        ral.default_map.set_auto_predict(0);
        // Black-box pwm_out observation. The analysis port is the single hand-off
        // point: the coverage subscriber attaches here, and so will the VP-PWM-BLACKBOX
        // per-pin reference-model checker when it is added.
        if (pwm_agt != null && pwm_cov != null)
            pwm_agt.mon.ap.connect(pwm_cov.analysis_export);
        if (pwm_agt != null && pwm_bb != null) begin
            pwm_bb.ral = ral;   // RAL mirror handle only -- no bus/internal-signal access
            pwm_agt.mon.ap.connect(pwm_bb.analysis_export);
            agent.mon.ap.connect(pwm_bb.apb_imp);   // to timestamp CTRL/CHx_CTRL writes
        end
        vseqr.apb_seqr  = agent.seqr;
        vseqr.ral       = ral;
        vseqr.scb       = scb;
        vseqr.apb_cfg   = cfg.apb_cfg;
        vseqr.reset_vif = cfg.reset_vif;
    endfunction

    // Re-sync every predictive model in the environment to the device's post-reset
    // state. Called by pmtpc4_base_vseq::async_reset() after PRESETn is released;
    // without it the RAL mirror and the scoreboard's readback shadow keep predicting
    // pre-reset values and every subsequent read mismatches.
    virtual function void handle_reset();
        if (ral != null) ral.reset();        // RAL mirror/desired -> reset values
        if (scb != null) scb.handle_reset(); // scoreboard readback shadow
    endfunction
endclass
