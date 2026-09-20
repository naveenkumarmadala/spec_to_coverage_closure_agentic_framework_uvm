// Reusable APB3 UVM VIP (UVC). Move-once, use for any APB IP.
// Compile apb_if.sv separately (interfaces cannot live in a package).
package apb_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "apb_seq_item.sv"
    typedef uvm_sequencer #(apb_item) apb_sequencer;
    `include "apb_agent_cfg.sv"
    `include "apb_driver.sv"
    `include "apb_monitor.sv"
    `include "apb_coverage.sv"
    `include "apb_reg_adapter.sv"
    `include "apb_seq_lib.sv"
    `include "apb_agent.sv"
endpackage
