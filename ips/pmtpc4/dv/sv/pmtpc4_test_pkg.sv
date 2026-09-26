// PMTPC-4 UVM environment + sequences + tests package.
package pmtpc4_test_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import apb_pkg::*;
    import pwm_pkg::*;
    import pmtpc4_ral_pkg::*;

    // ---- structural parameters, from ip_config.yaml ------------------------
    // interfaces[] -> name: pwm_out, kind: pwm, width: 4
    localparam int unsigned PMTPC4_NUM_PWM = 4;
    // One typedef per parameterized VIP type so the testbench top and the env agree
    // on the exact specialization used as the uvm_config_db key.
    typedef virtual pwm_if #(PMTPC4_NUM_PWM)   pmtpc4_pwm_vif_t;
    typedef pwm_agent_cfg  #(PMTPC4_NUM_PWM)   pmtpc4_pwm_agent_cfg_t;
    typedef pwm_agent      #(PMTPC4_NUM_PWM)   pmtpc4_pwm_agent_t;
    // RAL top block class is named 'pmtpc4' (from the RDL addrmap) — same as the DUT
    // module. Aliased here, package-wide and early, so every env/checker file that
    // needs a RAL handle (incl. pmtpc4_pwm_blackbox_checker.sv, included before
    // pmtpc4_env.sv) can reference it without re-deriving the alias.
    typedef pmtpc4_ral_pkg::pmtpc4 pmtpc4_reg_block_t;

    // reusable register-bit toggle coverage (vip/common) + its RDL-derived config
    `include "reg_bit_toggle_cov.svh"
    `include "pmtpc4_reg_toggle_cfg.svh"
    // env
    `include "pmtpc4_env_cfg.sv"
    `include "pmtpc4_scoreboard.sv"
    `include "pmtpc4_coverage.sv"
    `include "pmtpc4_pwm_coverage.sv"
    `include "pmtpc4_pwm_blackbox_checker.sv"
    `include "pmtpc4_vseqr.sv"
    `include "pmtpc4_env.sv"
    // sequences
    `include "pmtpc4_base_vseq.sv"
    `include "pmtpc4_reg_vseq.sv"
    `include "pmtpc4_smoke_vseq.sv"
    `include "pmtpc4_channel_vseq.sv"
    `include "pmtpc4_irq_vseq.sv"
    `include "pmtpc4_error_vseq.sv"
    `include "pmtpc4_cov_close_vseq.sv"
    `include "pmtpc4_toggle_vseq.sv"
    `include "pmtpc4_rand_vseq.sv"
    `include "pmtpc4_pwm_duty_vseq.sv"
    `include "pmtpc4_apb_b2b_vseq.sv"
    `include "pmtpc4_async_reset_vseq.sv"
    `include "pmtpc4_soft_reset_vseq.sv"
    `include "pmtpc4_selfclear_vseq.sv"
    `include "pmtpc4_prescaler_vseq.sv"
    `include "pmtpc4_count_value_vseq.sv"
    `include "pmtpc4_pwm_shadow_vseq.sv"
    `include "pmtpc4_mode_live_vseq.sv"
    `include "pmtpc4_freeze_states_vseq.sv"
    `include "pmtpc4_int_w1c_vseq.sv"
    `include "pmtpc4_int_simultaneous_vseq.sv"
    `include "pmtpc4_int_setpriority_vseq.sv"
    `include "pmtpc4_pwm_all_channels_vseq.sv"
    `include "pmtpc4_freeze_start_vseq.sv"
    `include "pmtpc4_selfclear_race_vseq.sv"
    `include "pmtpc4_reg_toggle_vseq.sv"
    // tests
    `include "pmtpc4_base_test.sv"
    `include "pmtpc4_sanity_test.sv"
    `include "pmtpc4_channel_test.sv"
    `include "pmtpc4_irq_test.sv"
    // register scenarios — one dedicated, scenario-named test each
    `include "pmtpc4_reg_reset_test.sv"
    `include "pmtpc4_reg_rw_test.sv"
    `include "pmtpc4_reg_ro_test.sv"
    `include "pmtpc4_reg_wo_test.sv"
    `include "pmtpc4_reg_reserved_test.sv"
    `include "pmtpc4_reg_unaligned_test.sv"
    `include "pmtpc4_wdata_upper_bits_test.sv"
    // toggle-closure + constrained-random (multi-seed) + union-coverage
    `include "pmtpc4_toggle_test.sv"
    `include "pmtpc4_rand_test.sv"
    `include "pmtpc4_pwm_duty_test.sv"
    // 2026-09-18 backlog closure: stimulus-only, new checkers, register/reset, coverage-resolution
    `include "pmtpc4_apb_b2b_test.sv"
    `include "pmtpc4_async_reset_test.sv"
    `include "pmtpc4_soft_reset_test.sv"
    `include "pmtpc4_selfclear_test.sv"
    `include "pmtpc4_prescaler_test.sv"
    `include "pmtpc4_count_value_test.sv"
    `include "pmtpc4_pwm_shadow_test.sv"
    `include "pmtpc4_mode_live_test.sv"
    `include "pmtpc4_freeze_states_test.sv"
    `include "pmtpc4_int_w1c_test.sv"
    `include "pmtpc4_int_simultaneous_test.sv"
    `include "pmtpc4_int_setpriority_test.sv"
    `include "pmtpc4_pwm_all_channels_test.sv"
    `include "pmtpc4_freeze_start_test.sv"
    `include "pmtpc4_selfclear_race_test.sv"
    `include "pmtpc4_reg_toggle_test.sv"
    `include "pmtpc4_full_test.sv"
endpackage
