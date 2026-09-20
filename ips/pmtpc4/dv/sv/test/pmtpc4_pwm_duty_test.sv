// VP-PWM-DUTY: directed PWM duty-cycle test — sweeps COMPARE across
// {0, <PERIOD, ==PERIOD, >PERIOD} against a fixed PERIOD on every channel with PWM_EN on
// (plus a PWM_EN=off leg), closing cg_pwm's cp_duty_class x cp_pwm_en cross and every
// cp_measured_duty bin (dv/sv/sva/pmtpc4_pwm_cov.sv). Self-checking is via that module's
// bound assertions (a_duty_compare_zero / a_duty_full_low / a_duty_matches_cmp / a_pwm_off).
class pmtpc4_pwm_duty_test extends pmtpc4_base_test;
    `uvm_component_utils(pmtpc4_pwm_duty_test)
    function new(string n, uvm_component p); super.new(n, p); endfunction
    task run_phase(uvm_phase phase);
        pmtpc4_pwm_duty_vseq s0 = pmtpc4_pwm_duty_vseq::type_id::create("s0");
        phase.raise_objection(this);
        run_vseq(s0);
        #100ns;
        phase.drop_objection(this);
    endtask
endclass
