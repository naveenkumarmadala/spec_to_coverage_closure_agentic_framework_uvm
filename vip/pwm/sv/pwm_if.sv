// =============================================================================
// pwm_if — reusable, PASSIVE observation interface for PWM-style outputs (VIP).
//
// Protocol-agnostic: it is just "N output pins plus the clock/reset used to
// sample them". Any IP that drives one or more PWM / timer-output pins can use
// it; the UVC never drives the pins (they are interface INPUT ports, so passivity
// is enforced structurally, not by convention).
//
// Usage (tb_top):
//     pwm_if #(.NUM_PINS(4)) pwm_ivf (.clk(pclk), .rst_n(presetn), .pwm(pwm_out));
//     uvm_config_db#(virtual pwm_if#(4))::set(null, "*", "pwm_vif", pwm_ivf);
// =============================================================================
interface pwm_if #(parameter int unsigned NUM_PINS = 1)
                  (input logic                 clk,
                   input logic                 rst_n,
                   input logic [NUM_PINS-1:0]  pwm);

    clocking mon_cb @(posedge clk);
        default input #1step;
        input pwm;
    endclocking

    modport mon (clocking mon_cb, input rst_n, input pwm, input clk);
endinterface
