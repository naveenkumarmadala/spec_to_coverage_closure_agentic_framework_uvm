// APB agent configuration object (active/passive, coverage, vif handle).
class apb_agent_cfg extends uvm_object;
    `uvm_object_utils(apb_agent_cfg)
    uvm_active_passive_enum is_active = UVM_ACTIVE;
    bit                     en_cov    = 1;
    virtual apb_if          vif;

    // Master enable for the driver's back-to-back mode (ACCESS -> SETUP with PSEL
    // held). DEFAULT OFF: with b2b_enable=0 the driver behaves exactly as it always
    // has (one transfer per item, PSEL deasserted between transfers) for every
    // existing IP and test. A test that wants chaining sets this AND
    // apb_item.back_to_back on the items it wants chained.
    bit                     b2b_enable = 0;
    function new(string name = "apb_agent_cfg"); super.new(name); endfunction
endclass
