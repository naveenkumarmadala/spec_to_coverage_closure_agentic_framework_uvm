// Configurable APB agent (active/passive, optional coverage).
class apb_agent extends uvm_agent;
    `uvm_component_utils(apb_agent)
    apb_agent_cfg              cfg;
    apb_driver                drv;
    apb_monitor               mon;
    uvm_sequencer #(apb_item) seqr;
    apb_coverage              cov;

    function new(string n, uvm_component p); super.new(n, p); endfunction

    function void build_phase(uvm_phase phase);
        if (!uvm_config_db#(apb_agent_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal("NOCFG", "apb_agent_cfg not set")
        mon = apb_monitor::type_id::create("mon", this);
        if (cfg.en_cov) cov = apb_coverage::type_id::create("cov", this);
        if (cfg.is_active == UVM_ACTIVE) begin
            drv  = apb_driver::type_id::create("drv", this);
            seqr = uvm_sequencer#(apb_item)::type_id::create("seqr", this);
        end
        uvm_config_db#(apb_agent_cfg)::set(this, "mon", "cfg", cfg);
        uvm_config_db#(apb_agent_cfg)::set(this, "drv", "cfg", cfg);
    endfunction

    function void connect_phase(uvm_phase phase);
        if (cfg.en_cov) mon.ap.connect(cov.analysis_export);
        if (cfg.is_active == UVM_ACTIVE)
            drv.seq_item_port.connect(seqr.seq_item_export);
    endfunction
endclass
