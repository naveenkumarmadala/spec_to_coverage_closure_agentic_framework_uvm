// Base virtual sequence: RAL + raw-APB helpers used by all PMTPC-4 scenarios.
class pmtpc4_base_vseq extends uvm_sequence;
    `uvm_object_utils(pmtpc4_base_vseq)
    `uvm_declare_p_sequencer(pmtpc4_vseqr)
    function new(string name = "pmtpc4_base_vseq"); super.new(name); endfunction

    // channel register-block handle by index
    function pmtpc4__channel_rf chan(int n);
        case (n)
            0: return p_sequencer.ral.CH0;
            1: return p_sequencer.ral.CH1;
            2: return p_sequencer.ral.CH2;
            default: return p_sequencer.ral.CH3;
        endcase
    endfunction

    // RAL access
    task reg_wr(uvm_reg r, uvm_reg_data_t v);
        uvm_status_e s; r.write(s, v);
        if (s != UVM_IS_OK) `uvm_error("REGWR", $sformatf("%s write not OK", r.get_name()))
    endtask
    task reg_rd(uvm_reg r, output uvm_reg_data_t v);
        uvm_status_e s; r.read(s, v);
    endtask

    // raw APB (for illegal/unaligned/wait-state stimulus the RAL cannot express)
    task raw(bit wr, bit [31:0] addr, bit [31:0] data, output apb_item it);
        apb_rw_seq seq = apb_rw_seq::type_id::create("seq");
        seq.write = wr; seq.addr = addr; seq.data = data;
        seq.start(p_sequencer.apb_seqr);
        it = seq.rsp_item;
    endtask

    task cyc(int n); repeat (n) #10ns; endtask

    // generic pass/fail check ('expect' is a reserved SV keyword, so 'chk')
    task chk(bit cond, string msg);
        if (!cond) `uvm_error("CHK", msg)
    endtask

    // RAL introspection: true iff the register has >=1 field and EVERY field's access
    // equals `acc` (e.g. "RO"/"WO"). Generic — used to derive access-policy targets.
    function bit all_fields_access(uvm_reg r, string acc);
        uvm_reg_field fs[$];
        r.get_fields(fs);                    // fresh local queue each call
        if (fs.size() == 0) return 0;
        foreach (fs[j]) if (fs[j].get_access() != acc) return 0;
        return 1;
    endfunction

    // common: enable module + set prescaler
    task enable_module(bit [15:0] presc = 0);
        reg_wr(p_sequencer.ral.PRESCALER, presc);
        reg_wr(p_sequencer.ral.CTRL, 32'h1);   // MODULE_EN=1
    endtask

    // ---- async reset (VP-RST-ASYNC) ----------------------------------------
    // Pulse PRESETn low for `cycles` clocks at an ARBITRARY point in a running
    // simulation, then release it and re-sync every predictive model in the
    // environment to the device's post-reset state.
    //
    //   async_delay > 0 asserts reset OFF the clock edge, which is what makes the
    //   assertion genuinely asynchronous (use it to land a reset inside an APB
    //   SETUP/ACCESS phase). The APB driver/monitor abort any in-flight transfer
    //   rather than hanging on a PREADY that will never come.
    //
    // Re-sync performed here, in this order:
    //   RAL mirror   -> reset values (ral.reset())
    //   scoreboard   -> readback shadow dropped (scb.handle_reset())
    // The uvm_reg_predictor itself carries no cross-transaction state to clear; it
    // predicts from the map+adapter, both of which are reset by ral.reset().
    task async_reset(int unsigned cycles = 4, time async_delay = 0ns);
        if (p_sequencer.reset_vif == null)
            `uvm_fatal("NORSTVIF", "reset_vif not set on the virtual sequencer: tb_top must publish a 'reset_vif' handle (see vip/common/sv/reset_if.sv)")
        `uvm_info("RST", $sformatf("asserting async reset for %0d cycles (delay %0t)",
                                   cycles, async_delay), UVM_LOW)
        p_sequencer.reset_vif.apply(cycles, async_delay);
        sync_models_after_reset();
    endtask

    // Hold reset asserted / release it explicitly, for scenarios that need to do
    // something while the device is held in reset.
    task reset_assert();
        if (p_sequencer.reset_vif == null) `uvm_fatal("NORSTVIF", "reset_vif not set")
        p_sequencer.reset_vif.assert_reset();
    endtask
    task reset_release();
        if (p_sequencer.reset_vif == null) `uvm_fatal("NORSTVIF", "reset_vif not set")
        p_sequencer.reset_vif.release_reset();
        sync_models_after_reset();
    endtask

    task sync_models_after_reset();
        // let the release settle on the bus before anything else drives it
        @(posedge p_sequencer.reset_vif.clk);
        p_sequencer.ral.reset();
        if (p_sequencer.scb != null) p_sequencer.scb.handle_reset();
    endtask

    // ---- APB back-to-back mode (VP-APB-FSM-B2B) -----------------------------
    // Opt in / out of the VIP driver's ACCESS->SETUP chaining for this environment.
    // Default is OFF; nothing chains unless a sequence turns it on AND marks items.
    function void set_b2b(bit on);
        if (p_sequencer.apb_cfg == null) `uvm_fatal("NOAPBCFG", "apb_cfg not set on vseqr")
        p_sequencer.apb_cfg.b2b_enable = on;
    endfunction

    // Issue a back-to-back burst over the raw APB path (PSEL held across every
    // ACCESS->SETUP boundary). Returns the completed items.
    task raw_b2b(bit wr[$], bit [31:0] addr[$], bit [31:0] data[$], ref apb_item items[$]);
        apb_b2b_seq seq = apb_b2b_seq::type_id::create("b2b_seq");
        foreach (addr[i]) begin
            seq.writes.push_back(i < wr.size()   ? wr[i]   : 1'b0);
            seq.addrs.push_back(addr[i]);
            seq.datas.push_back(i < data.size() ? data[i] : 32'h0);
        end
        seq.start(p_sequencer.apb_seqr);
        items = seq.items;
    endtask
endclass
