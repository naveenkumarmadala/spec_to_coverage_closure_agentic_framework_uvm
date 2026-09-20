// APB monitor: publishes every completed transfer (with wait count) on ap.
class apb_monitor extends uvm_monitor;
    `uvm_component_utils(apb_monitor)
    apb_agent_cfg cfg;
    uvm_analysis_port #(apb_item) ap;
    function new(string n, uvm_component p); super.new(n, p); ap = new("ap", this); endfunction

    function void build_phase(uvm_phase phase);
        if (!uvm_config_db#(apb_agent_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal("NOCFG", "apb_agent_cfg not set")
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            // detect an ACCESS phase, then count waits until PREADY
            @(cfg.vif.mon_cb);
            if (cfg.vif.presetn !== 1'b1) continue;     // nothing on the bus is meaningful
            if (cfg.vif.mon_cb.psel && cfg.vif.mon_cb.penable) begin
                int w = 0;
                bit torn = 0;
                while (!cfg.vif.mon_cb.pready) begin
                    w++;
                    @(cfg.vif.mon_cb);
                    // A reset in the middle of an ACCESS phase tears the transfer down.
                    // Publishing a torn transfer would feed the scoreboard/RAL predictor
                    // a transaction that never completed, so drop it instead.
                    if (cfg.vif.presetn !== 1'b1) begin torn = 1; break; end
                end
                if (torn) continue;
                begin
                    apb_item it = apb_item::type_id::create("it");
                    it.write  = cfg.vif.mon_cb.pwrite;
                    it.addr   = cfg.vif.mon_cb.paddr;
                    it.data   = cfg.vif.mon_cb.pwdata;
                    it.rdata  = cfg.vif.mon_cb.prdata;
                    it.slverr = cfg.vif.mon_cb.pslverr;
                    it.waits  = w;
                    ap.write(it);
                end
            end
        end
    endtask
endclass
