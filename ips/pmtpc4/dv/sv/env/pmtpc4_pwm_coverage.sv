// =============================================================================
// pmtpc4_pwm_coverage — VP-PWM-BLACKBOX functional coverage (cg_pwm_out).
//
// Black-box PWM observation: subscribes to the reusable vip/pwm UVC's analysis
// port (pmtpc4_env.pwm_agt.mon.ap), which samples the DUT's pwm_out pins at the
// TB boundary. Everything the DUT's internal state could tell us is deliberately
// NOT used here — the whole point of VP-PWM-BLACKBOX is the outside-the-DUT view.
//
// Bins are exactly the vplan's VP-PWM-BLACKBOX specification:
//   cp_pin      [0..3]                          (one bin per channel output)
//   cp_level    low / high
//   cp_activity toggling / held_low / held_high (from the monitor's activity window)
//   x_pin_level cross cp_pin x cp_level
//
// SCOPE: coverage only. The VP-PWM-BLACKBOX CHECKER — a per-pin reference model
// predicting pwm_out from the RAL mirror of CHx_PERIOD/CHx_COMPARE/CHx_CTRL — is
// a separate component fed from the same analysis port; this class does not
// attempt it and must not be mistaken for it.
// =============================================================================
class pmtpc4_pwm_coverage extends uvm_subscriber #(pwm_item);
    `uvm_component_utils(pmtpc4_pwm_coverage)

    // activity classes — an enum so the bin expressions are elaboration-time constants
    typedef enum int { ACT_TOGGLING = 0, ACT_HELD_LOW = 1, ACT_HELD_HIGH = 2 } pwm_act_e;

    pwm_item  tr;
    pwm_act_e act = ACT_HELD_LOW;  // last computed activity class (valid on PWM_WINDOW)

    covergroup cg_pwm_out;
        option.per_instance = 1;
        // pmtpc4 has one independently-driven pwm_out per channel (REQ-OUT-1).
        cp_pin: coverpoint tr.pin {
            bins pin[] = {0, 1, 2, 3};
        }
        cp_level: coverpoint tr.level {
            bins low  = {0};
            bins high = {1};
        }
        // Only an activity WINDOW item carries a meaningful activity class; edge and
        // reset items are excluded so a held-level bin cannot be claimed vacuously.
        cp_activity: coverpoint act iff (tr.kind == PWM_WINDOW) {
            bins toggling  = {ACT_TOGGLING};
            bins held_low  = {ACT_HELD_LOW};
            bins held_high = {ACT_HELD_HIGH};
        }
        x_pin_level: cross cp_pin, cp_level;
    endgroup

    function new(string n, uvm_component p);
        super.new(n, p);
        cg_pwm_out = new();
    endfunction

    function void write(pwm_item t);
        tr = t;
        if (t.kind == PWM_WINDOW)
            act = (t.edges_in_window != 0) ? ACT_TOGGLING
                                           : (t.level ? ACT_HELD_HIGH : ACT_HELD_LOW);
        cg_pwm_out.sample();
    endfunction
endclass
