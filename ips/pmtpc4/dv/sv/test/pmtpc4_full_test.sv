// Unified all-scenarios test: runs every vseq in ONE simulation so a single
// coverage database captures the union of functional coverage across all
// scenarios (xsim overwrites the db per run and xcrg cross-db merge is unreliable
// on 2025.1, so a single-sim union is the reliable way to a merged number).
class pmtpc4_full_test extends pmtpc4_base_test;
    `uvm_component_utils(pmtpc4_full_test)
    function new(string n, uvm_component p); super.new(n, p); endfunction
    task run_phase(uvm_phase phase);
        // register scenarios (split per scenario, all RAL-derived)
        pmtpc4_reg_reset_vseq     rr = pmtpc4_reg_reset_vseq::type_id::create("rr");
        pmtpc4_reg_rw_vseq        rw = pmtpc4_reg_rw_vseq::type_id::create("rw");
        pmtpc4_reg_ro_vseq        ro = pmtpc4_reg_ro_vseq::type_id::create("ro");
        pmtpc4_reg_wo_vseq        wo = pmtpc4_reg_wo_vseq::type_id::create("wo");
        pmtpc4_reg_reserved_vseq  rsv= pmtpc4_reg_reserved_vseq::type_id::create("rsv");
        pmtpc4_reg_unaligned_vseq un = pmtpc4_reg_unaligned_vseq::type_id::create("un");
        pmtpc4_wdata_upper_bits_vseq wdu = pmtpc4_wdata_upper_bits_vseq::type_id::create("wdu");
        // functional scenarios
        pmtpc4_oneshot_vseq     s0 = pmtpc4_oneshot_vseq::type_id::create("s0");
        pmtpc4_periodic_vseq    s1 = pmtpc4_periodic_vseq::type_id::create("s1");
        pmtpc4_pause_vseq       s2 = pmtpc4_pause_vseq::type_id::create("s2");
        pmtpc4_freeze_vseq      s3 = pmtpc4_freeze_vseq::type_id::create("s3");
        pmtpc4_softdisable_vseq s4 = pmtpc4_softdisable_vseq::type_id::create("s4");
        pmtpc4_irq_vseq         iq = pmtpc4_irq_vseq::type_id::create("iq");
        pmtpc4_cov_close_vseq   cc = pmtpc4_cov_close_vseq::type_id::create("cc");
        pmtpc4_toggle_vseq      tg = pmtpc4_toggle_vseq::type_id::create("tg");
        pmtpc4_rand_vseq        rv = pmtpc4_rand_vseq::type_id::create("rv");
        pmtpc4_pwm_duty_vseq    pd = pmtpc4_pwm_duty_vseq::type_id::create("pd");
        // 2026-09-18 backlog closure
        pmtpc4_apb_b2b_vseq          b2b  = pmtpc4_apb_b2b_vseq::type_id::create("b2b");
        pmtpc4_async_reset_vseq      arst = pmtpc4_async_reset_vseq::type_id::create("arst");
        pmtpc4_soft_reset_vseq       srst = pmtpc4_soft_reset_vseq::type_id::create("srst");
        pmtpc4_selfclear_vseq        sc   = pmtpc4_selfclear_vseq::type_id::create("sc");
        pmtpc4_prescaler_vseq        presc= pmtpc4_prescaler_vseq::type_id::create("presc");
        pmtpc4_count_value_vseq      cv   = pmtpc4_count_value_vseq::type_id::create("cv");
        pmtpc4_pwm_shadow_vseq       psh  = pmtpc4_pwm_shadow_vseq::type_id::create("psh");
        pmtpc4_mode_live_vseq        ml   = pmtpc4_mode_live_vseq::type_id::create("ml");
        pmtpc4_freeze_states_vseq    fs   = pmtpc4_freeze_states_vseq::type_id::create("fs");
        pmtpc4_int_w1c_vseq          iw1c = pmtpc4_int_w1c_vseq::type_id::create("iw1c");
        pmtpc4_int_simultaneous_vseq isim = pmtpc4_int_simultaneous_vseq::type_id::create("isim");
        pmtpc4_int_setpriority_vseq  isp  = pmtpc4_int_setpriority_vseq::type_id::create("isp");
        pmtpc4_pwm_all_channels_vseq pac  = pmtpc4_pwm_all_channels_vseq::type_id::create("pac");
        pmtpc4_freeze_start_vseq     fst  = pmtpc4_freeze_start_vseq::type_id::create("fst");
        pmtpc4_selfclear_race_vseq   scr  = pmtpc4_selfclear_race_vseq::type_id::create("scr");
        phase.raise_objection(this);
        run_vseq(rr); run_vseq(rw); run_vseq(ro); run_vseq(wo); run_vseq(rsv); run_vseq(un);
        run_vseq(wdu);           // VP-REG-ACCESS: garbage-upper-bits write robustness
        run_vseq(s0); run_vseq(s1); run_vseq(s2); run_vseq(s3); run_vseq(s4);
        run_vseq(iq);
        run_vseq(cc);            // exercises all 4 channels + config sweep for coverage closure
        run_vseq(tg);            // full-range datapath stimulus for code toggle coverage
        run_vseq(rv);            // constrained-random register traffic for code (toggle) coverage
        run_vseq(pd);            // VP-PWM-DUTY: COMPARE sweep closing cg_pwm on all 4 channels
        run_vseq(b2b);           // VP-APB-FSM-B2B
        run_vseq(arst);          // VP-RST-ASYNC
        run_vseq(srst);          // VP-RST-SOFT
        run_vseq(sc);            // VP-SELFCLR
        run_vseq(presc);         // VP-PRESC-RATIO
        run_vseq(cv);            // VP-CH-COUNT-READBACK
        run_vseq(psh);           // VP-PWM-SHADOW-DEFER
        run_vseq(ml);            // VP-CH-MODE-LIVE (ch0-3)
        run_vseq(fs);            // VP-FREEZE-STATES (LOAD/PAUSED/EXPIRED + pause-during-EXPIRED)
        run_vseq(iw1c);          // VP-INT-W1C
        run_vseq(isim);          // VP-INT-SIMUL
        run_vseq(isp);           // VP-INT-SETPRI
        run_vseq(pac);           // VP-PWM-BLACKBOX
        run_vseq(fst);           // F4: CH_EN/CH_START during freeze must not be swallowed
        run_vseq(scr);           // F3: coincident CHx_CTRL write must not defeat one-shot self-clear
        #100ns;
        phase.drop_objection(this);
    endtask
endclass
