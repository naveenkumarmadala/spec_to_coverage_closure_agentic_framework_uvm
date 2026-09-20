// =============================================================================
// pmtpc4_pwm_blackbox_checker — VP-PWM-BLACKBOX's checker.
//
// A per-pin reference model fed ONLY from:
//   (a) the RAL MIRROR of CTRL.MODULE_EN / CHx_CTRL.PWM_EN / CHx_CTRL.CH_EN (i.e.
//       what SOFTWARE WROTE, read back via get_mirrored_value() -- no bus access,
//       no DUT-internal signal), timestamped from the same apb_item stream the
//       scoreboard/RAL predictor already observe, and
//   (b) env.pwm_agt.mon.ap's pwm_item RISE-edge stream (the black-box pwm_out
//       observation).
// It never reads count/state_o/compare_shadow/pwm_q or any other internal net --
// that is precisely the perspective the existing WHITE-BOX SVA (a_pwm_rule,
// a_duty_matches_cmp, ...) cannot provide, and the whole point of this class.
//
// SCOPE (honest boundary -- see dv/README.md / vplan gap note):
//   Checked:     "whenever software's own configuration says this pin must be
//                 forced low -- MODULE_EN off, this channel's PWM_EN off, or this
//                 channel's CH_EN off (IDLE) -- the black-box pin never goes HIGH
//                 again once that configuration has had time to propagate."
//   NOT checked: the COMPARE>=PERIOD "always low" configuration. That case is
//                subject to compare_shadow's DEFERRED-EFFECT timing (Design 7.4 /
//                VP-PWM-SHADOW-DEFER): a COMPARE/PERIOD write takes effect only at
//                the next LOAD, not immediately, so "software's live register value
//                says compare>=period" does NOT mean the CURRENTLY-RUNNING period's
//                shadowed comparison already reflects it. Resolving that black-box
//                would require knowing the LOAD boundary, which is exactly the
//                internal knowledge this checker is not supposed to use. Left to
//                VP-PWM-DUTY's white-box a_duty_full_low instead.
//   NOT checked (either direction): the exact duty-cycle VALUE -- that needs a
//                live cycle-accurate COUNT, unobservable black-box; VP-PWM-DUTY
//                covers it white-box.
// This narrower gating check is still real, independent bug-catching value: a
// completely different signal path (RAL mirror + the passive TB-boundary monitor)
// than a_freeze_pwm_low/a_pwm_off (which read hwif_out/compare_shadow directly), and
// it directly serves the item's own "forced low during MODULE_EN=0 freeze" +
// "no cross-talk between independently-driven outputs" language (a leaking channel
// would show up here as an unexpected RISE on a pin whose OWN config says
// forced-low, regardless of what any other channel is doing).
//
// GRACE: checked on every PWM_RISE edge, not on a fixed sampling window (a window-
// boundary sample can straddle a configuration change and misclassify legitimate,
// already-in-flight toggling as a violation -- empirically hit during this
// session's regression before the design was switched to edge-based checking).
// A RISE is only flagged if it happens more than GRACE_NS after the LAST relevant
// register write (module CTRL or this channel's CH_CTRL/CH_PERIOD/CH_COMPARE) --
// comfortably more than the ~2-3 pclk cycles MODULE_EN/PWM_EN/CH_EN take to
// combinationally/registered-ly propagate to pwm_out.
// =============================================================================
`uvm_analysis_imp_decl(_pwmbbcfg)
class pmtpc4_pwm_blackbox_checker extends uvm_subscriber #(pwm_item);
    `uvm_component_utils(pmtpc4_pwm_blackbox_checker)

    uvm_analysis_imp_pwmbbcfg #(apb_item, pmtpc4_pwm_blackbox_checker) apb_imp;

    pmtpc4_reg_block_t ral;   // set by the env after RAL construction; see connect_phase
    int unsigned checks, errors;
    // "opportunities" is evidence this checker's antecedent was genuinely exercised
    // (a force-low condition was actually created), independent of `checks` -- which,
    // for a CORRECT design, legitimately stays 0 forever (no RISE ever happens while
    // force-low, so there is nothing to flag) and would otherwise look vacuous.
    int unsigned opportunities;
    realtime last_module_change_time = 0ns;
    realtime last_ch_change_time[4]  = '{0ns, 0ns, 0ns, 0ns};
    localparam realtime GRACE_NS = 30ns;   // >> the ~2-3 pclk cycles of real propagation

    function new(string n, uvm_component p);
        super.new(n, p);
        apb_imp = new("apb_imp", this);
    endfunction

    function pmtpc4__channel_rf chan(int n);
        case (n)
            0: return ral.CH0; 1: return ral.CH1; 2: return ral.CH2;
            default: return ral.CH3;
        endcase
    endfunction

    // Timestamp every write that can affect a pin's force-low condition (MODULE_EN,
    // or this channel's own CH_CTRL) -- fed from the SAME apb_item stream the
    // scoreboard/RAL predictor already observe (agent.mon.ap), not a new bus tap.
    function void write_pwmbbcfg(apb_item t);
        bit [7:0] a = t.addr[7:0];
        if (!t.write) return;
        if (a == 8'h00) last_module_change_time = $realtime;
        else begin
            int ch = -1;
            case (a & 8'hF0)
                8'h20: ch = 0; 8'h30: ch = 1; 8'h40: ch = 2; 8'h50: ch = 3;
                default: ch = -1;
            endcase
            if (ch != -1 && (a & 8'h0F) == 8'h00)   // CH_CTRL only (PWM_EN/CH_EN live here)
                last_ch_change_time[ch] = $realtime;
        end
        if (ral != null) begin
            bit module_en = ral.CTRL.MODULE_EN.get_mirrored_value();
            if (!module_en) opportunities++;
            else for (int c = 0; c < 4; c++)
                if (!chan(c).CH_CTRL.PWM_EN.get_mirrored_value() ||
                    !chan(c).CH_CTRL.CH_EN.get_mirrored_value()) opportunities++;
        end
    endfunction

    function void write(pwm_item t);
        int ch;
        bit module_en, pwm_en, ch_en, force_low;
        realtime last_change;

        if (t.kind != PWM_RISE) return;   // only a rising edge can violate a force-low expectation
        if (ral == null) return;          // defensive; env always sets this before run_phase

        ch = t.pin;
        module_en = ral.CTRL.MODULE_EN.get_mirrored_value();
        pwm_en    = chan(ch).CH_CTRL.PWM_EN.get_mirrored_value();
        ch_en     = chan(ch).CH_CTRL.CH_EN.get_mirrored_value();
        force_low = !module_en || !pwm_en || !ch_en;

        if (force_low) begin
            checks++;
            last_change = (last_module_change_time > last_ch_change_time[ch])
                          ? last_module_change_time : last_ch_change_time[ch];
            if (($realtime - last_change) > GRACE_NS) begin
                errors++;
                `uvm_error("PWM_BB", $sformatf(
                    "pin %0d went HIGH at %0t while the RAL mirror says it must be forced LOW (module_en=%0b pwm_en=%0b ch_en=%0b), %0t after the last relevant config write",
                    ch, $realtime, module_en, pwm_en, ch_en, $realtime - last_change))
            end
        end
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("PWM_BB", $sformatf("opportunities=%0d checks=%0d errors=%0d",
            opportunities, checks, errors), UVM_LOW)
        if (errors != 0) `uvm_error("PWM_BB", $sformatf("%0d pwm black-box checker error(s)", errors))
    endfunction
endclass
