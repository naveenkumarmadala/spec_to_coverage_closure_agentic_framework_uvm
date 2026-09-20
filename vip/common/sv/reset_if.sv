// =============================================================================
// reset_if — reusable reset-generation/observation interface (VIP, protocol-agnostic).
//
// Gives a testbench ONE place that owns the DUT reset pin, and gives the UVM
// environment a virtual-interface handle it can call to assert reset at an
// ARBITRARY point in a running simulation (not just power-on). Without this a
// tb_top that drives reset from a single `initial` block makes "async reset from
// a running state" structurally untestable.
//
// Usage (tb_top):
//     reset_if #(.ACTIVE_LOW(1), .POR_CYCLES(5)) rst_if (.clk(pclk));
//     wire presetn = rst_if.rst;          // feed the DUT / bus interfaces
//     initial rst_if.power_on_reset();
//     initial uvm_config_db#(virtual reset_if)::set(null, "*", "reset_vif", rst_if);
//
// Usage (sequence):
//     p_sequencer.reset_vif.apply(4);            // 4 clocks, edge-aligned
//     p_sequencer.reset_vif.apply(3, 3ns);       // asserted off-edge => truly async
//
// NOTE the parameter defaults are the values a plain `virtual reset_if` handle
// refers to; instantiate with those defaults (as apb_if does) so the config_db
// type matches, or use an explicit `virtual reset_if#(...)` handle type.
// =============================================================================
interface reset_if #(parameter bit ACTIVE_LOW = 1'b1,
                     parameter int unsigned POR_CYCLES = 5)
                    (input logic clk);

    localparam logic ASSERTED   = ACTIVE_LOW ? 1'b0 : 1'b1;
    localparam logic DEASSERTED = ACTIVE_LOW ? 1'b1 : 1'b0;

    // The reset signal driven to the DUT. Starts ASSERTED so nothing sees X before
    // power_on_reset() runs.
    logic rst = ASSERTED;

    // ---- observation state (for monitors / reset coverage / debug) ----
    int unsigned assert_count  = 0;   // number of reset assertions so far
    int unsigned release_count = 0;   // number of completed reset releases
    event        reset_asserted_e;
    event        reset_released_e;

    function automatic bit is_asserted();  return (rst === ASSERTED);   endfunction
    function automatic bit is_released();  return (rst === DEASSERTED); endfunction

    // ---- drive API ----------------------------------------------------------
    // Assert reset (optionally after an off-edge delay, which is what makes it
    // genuinely ASYNCHRONOUS w.r.t. clk), hold it for `cycles` clock edges, then
    // release it synchronously to the clock.
    task automatic apply(int unsigned cycles = POR_CYCLES, time async_delay = 0ns);
        if (async_delay > 0) #(async_delay);
        assert_reset();
        repeat (cycles) @(posedge clk);
        release_reset();
    endtask

    // Level control, for tests that want to hold reset across their own stimulus.
    task automatic assert_reset();
        rst = ASSERTED;
        assert_count++;
        -> reset_asserted_e;
    endtask

    task automatic release_reset();
        rst = DEASSERTED;
        release_count++;
        -> reset_released_e;
    endtask

    // Power-on reset: identical to apply(), named for intent at tb_top.
    task automatic power_on_reset(int unsigned cycles = POR_CYCLES);
        apply(cycles);
    endtask

    task automatic wait_release();
        wait (rst === DEASSERTED);
    endtask

    task automatic wait_assert();
        wait (rst === ASSERTED);
    endtask
endinterface
