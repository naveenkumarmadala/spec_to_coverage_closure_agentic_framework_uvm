// Virtual sequencer: holds handles that virtual sequences need (APB sequencer + RAL
// + the environment models a sequence has to re-sync after an async reset).
class pmtpc4_vseqr extends uvm_sequencer;
    `uvm_component_utils(pmtpc4_vseqr)
    apb_sequencer     apb_seqr;   // from the APB agent
    pmtpc4            ral;        // generated RAL block
    pmtpc4_scoreboard scb;        // null if the scoreboard is disabled
    apb_agent_cfg     apb_cfg;    // lets a vseq flip VIP knobs (e.g. b2b_enable)

    // Reset control hook, published by the testbench top (vip/common/sv/reset_if.sv).
    // Non-null means a sequence can pulse PRESETn mid-simulation; see
    // pmtpc4_base_vseq::async_reset(), which also re-syncs the RAL/scoreboard.
    virtual reset_if  reset_vif;

    function new(string n, uvm_component p); super.new(n, p); endfunction
endclass
