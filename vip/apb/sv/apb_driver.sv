// APB driver: one transfer per item (SETUP then ACCESS-until-PREADY), captures results.
//
// Two OPT-IN behaviours layered on top of that default:
//   * back-to-back (cfg.b2b_enable + item.back_to_back): PSEL is held asserted across
//     the ACCESS -> SETUP boundary so the next transfer starts with no idle cycle.
//   * reset abort: if PRESETn asserts mid-transfer the driver stops driving, marks the
//     item aborted, and re-arms after reset release (an APB master must not drive
//     during reset). Costs nothing when reset never toggles mid-simulation.
class apb_driver extends uvm_driver #(apb_item);
    `uvm_component_utils(apb_driver)
    apb_agent_cfg cfg;

    // PSEL is currently held asserted from a preceding back-to-back transfer, i.e.
    // this transfer's SETUP phase must be presented WITHOUT a leading idle cycle.
    protected bit m_psel_held;
    // drive() already called item_done() for the current item (back-to-back early ack).
    protected bit m_acked;
    // One clocking-edge of grace before the b2b guard decides nobody is coming (the
    // guard and drive() both wake on the edge that starts the hold, in either order).
    protected bit m_hold_grace;

    function new(string n, uvm_component p); super.new(n, p); endfunction

    function void build_phase(uvm_phase phase);
        if (!uvm_config_db#(apb_agent_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal("NOCFG", "apb_agent_cfg not set")
    endfunction

    task run_phase(uvm_phase phase);
        park();
        // An APB master must not drive during reset. Wait for presetn deassertion before
        // the first transfer, else a transaction issued right at time 0 races reset release
        // and is lost (e.g. bit-bash's first CTRL write reading back 0). Generic across IPs.
        wait (cfg.vif.presetn === 1'b1);
        @(cfg.vif.drv_cb);
        fork
            b2b_guard();
            forever begin
                apb_item it;
                seq_item_port.get_next_item(it);
                m_acked = 0;
                drive(it);
                if (!m_acked) seq_item_port.item_done();
            end
        join
    endtask

    // Safety net for a broken back_to_back contract. An item flagged back_to_back
    // PROMISES an immediate follower; if none arrives, PSEL would stay asserted with
    // PENABLE low, i.e. an illegally extended SETUP phase, for the rest of the run.
    // Close the transfer and say so loudly instead. A no-op whenever the back-to-back
    // mode is off (m_psel_held can only be set by a chained transfer).
    protected task b2b_guard();
        forever begin
            @(cfg.vif.drv_cb);
            if (!m_psel_held) begin
                m_hold_grace = 1'b0;
            end else if (m_hold_grace) begin
                m_hold_grace = 1'b0;          // this is the edge the hold started on
            end else begin
                `uvm_warning("APB_B2B", "item marked back_to_back had no immediate follower; deasserting PSEL to keep the SETUP phase legal")
                cfg.vif.drv_cb.psel    <= 1'b0;
                cfg.vif.drv_cb.penable <= 1'b0;
                m_psel_held = 1'b0;
            end
        end
    endtask

    // A task, not a function: IEEE 1800 forbids a clocking drive inside a function.
    protected task park();
        cfg.vif.drv_cb.psel    <= 1'b0;
        cfg.vif.drv_cb.penable <= 1'b0;
        m_psel_held  = 1'b0;
        m_hold_grace = 1'b0;
    endtask

    protected function bit in_reset(); return (cfg.vif.presetn !== 1'b1); endfunction

    task drive(apb_item it);
        int w = 0;
        // Chaining is a two-key opt-in: the agent must allow it AND the item must ask.
        bit chain = cfg.b2b_enable && it.back_to_back;

        it.aborted = 1'b0;

        // ---- SETUP phase ----------------------------------------------------
        // When PSEL is already held from the previous transfer we are sitting at the
        // clocking-block edge that ended its ACCESS phase; driving the new address here
        // makes the very next cycle this transfer's SETUP (ACCESS -> SETUP back-to-back,
        // PSEL never low). Otherwise take the normal idle -> SETUP edge.
        if (!m_psel_held) @(cfg.vif.drv_cb);
        m_psel_held  = 1'b0;
        m_hold_grace = 1'b0;
        if (in_reset()) begin abort(it, w); return; end
        cfg.vif.drv_cb.psel    <= 1'b1;
        cfg.vif.drv_cb.penable <= 1'b0;
        cfg.vif.drv_cb.pwrite  <= it.write;
        cfg.vif.drv_cb.paddr   <= it.addr;
        cfg.vif.drv_cb.pwdata  <= it.data;

        // ---- ACCESS phase ---------------------------------------------------
        @(cfg.vif.drv_cb);
        if (in_reset()) begin abort(it, w); return; end
        cfg.vif.drv_cb.penable <= 1'b1;

        if (chain) begin
            // Release the sequence NOW — a full clock before this transfer completes —
            // so the follower item is queued by the time the ACCESS phase ends and its
            // SETUP phase can begin on the very next cycle. Without this lookahead the
            // SETUP phase would stretch while we waited for the sequence, which is a
            // protocol violation, not a back-to-back transfer.
            m_acked = 1'b1;
            seq_item_port.item_done();
        end

        forever begin
            @(cfg.vif.drv_cb);
            if (in_reset()) begin abort(it, w); return; end
            if (cfg.vif.drv_cb.pready) begin
                it.rdata  = cfg.vif.drv_cb.prdata;
                it.slverr = cfg.vif.drv_cb.pslverr;
                it.waits  = w;
                break;
            end
            w++;
        end

        // ---- end of ACCESS --------------------------------------------------
        if (chain) begin
            cfg.vif.drv_cb.penable <= 1'b0;   // PSEL stays asserted -> next SETUP
            m_psel_held  = 1'b1;
            m_hold_grace = 1'b1;
        end else begin
            cfg.vif.drv_cb.psel    <= 1'b0;
            cfg.vif.drv_cb.penable <= 1'b0;
        end
    endtask

    // Reset hit mid-transfer: stop driving immediately, flag the item, and wait for
    // reset release before the next transfer.
    protected task abort(apb_item it, int w);
        park();
        it.aborted = 1'b1;
        it.rdata   = '0;
        it.slverr  = 1'b0;
        it.waits   = w;
        `uvm_info("APB_RST", $sformatf("transfer to 0x%0h aborted by reset", it.addr), UVM_MEDIUM)
        wait (cfg.vif.presetn === 1'b1);
        @(cfg.vif.drv_cb);
    endtask
endclass
