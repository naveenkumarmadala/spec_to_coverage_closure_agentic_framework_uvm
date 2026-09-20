// VP-PWM-BLACKBOX: 4 concurrent channels + explicit force-low scenarios, checked by
// pmtpc4_pwm_blackbox_checker (RAL-mirror-driven, black-box only).
class pmtpc4_pwm_all_channels_test extends pmtpc4_base_test;
    `uvm_component_utils(pmtpc4_pwm_all_channels_test)
    function new(string n, uvm_component p); super.new(n, p); endfunction
    task run_phase(uvm_phase phase);
        pmtpc4_pwm_all_channels_vseq v = pmtpc4_pwm_all_channels_vseq::type_id::create("v");
        phase.raise_objection(this);
        run_vseq(v);
        #100ns;
        phase.drop_objection(this);
    endtask
endclass
