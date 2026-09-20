// =============================================================================
// Reusable PWM / timer-output UVC (passive observation only).
//
// Scope: an IP drives N output pins whose LEVEL and EDGES must be observable from
// OUTSIDE the DUT (black-box), so that a checker can predict them from what
// software programmed rather than from the DUT's own internal state.
//
// Contents: pwm_item (level/edge/activity transaction), pwm_agent_cfg, pwm_monitor
// (publishes on an analysis port), pwm_agent (passive). Coverage and checking are
// deliberately NOT here: bin names and reference models are IP-specific and belong
// in the consuming environment's dv/sv/env.
//
// Compile pwm_if.sv separately (interfaces cannot live in a package).
// =============================================================================
package pwm_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "pwm_item.sv"
    `include "pwm_agent_cfg.sv"
    `include "pwm_monitor.sv"
    `include "pwm_agent.sv"
endpackage
