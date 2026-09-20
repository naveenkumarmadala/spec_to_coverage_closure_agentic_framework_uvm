// Reusable APB sequences.
class apb_base_seq extends uvm_sequence #(apb_item);
    `uvm_object_utils(apb_base_seq)
    function new(string name = "apb_base_seq"); super.new(name); endfunction
endclass

// Single read or write; captured results left on the item for the caller.
class apb_rw_seq extends apb_base_seq;
    `uvm_object_utils(apb_rw_seq)
    rand bit        write;
    rand bit [31:0] addr;
    rand bit [31:0] data;
    apb_item        rsp_item;
    function new(string name = "apb_rw_seq"); super.new(name); endfunction
    task body();
        apb_item it = apb_item::type_id::create("it");
        start_item(it);
        it.write = write; it.addr = addr; it.data = data;
        it.c_align.constraint_mode(0);   // caller controls alignment explicitly
        finish_item(it);
        rsp_item = it;
    endtask
endclass

// -----------------------------------------------------------------------------
// Back-to-back burst: N transfers with PSEL held asserted across every
// ACCESS -> SETUP boundary (the legal APB back-to-back optimisation).
//
// REQUIRES apb_agent_cfg.b2b_enable = 1 on the agent driving this sequencer;
// with the default (0) the driver silently runs the burst as ordinary, separated
// transfers, so an existing environment cannot be changed by accident.
//
// Fill `addrs`/`datas`/`writes` (same length) before start(), or leave `n` set and
// let the constraints randomize them. `items[]` holds the completed transactions;
// all of their rdata/slverr/waits are valid once body() returns.
// -----------------------------------------------------------------------------
class apb_b2b_seq extends apb_base_seq;
    `uvm_object_utils(apb_b2b_seq)

    rand int unsigned n;                 // burst length (>= 2 to produce a b2b edge)
    bit        writes [$];
    bit [31:0] addrs  [$];
    bit [31:0] datas  [$];
    apb_item   items  [$];

    constraint c_n { soft n inside {[2:8]}; }

    function new(string name = "apb_b2b_seq"); super.new(name); endfunction

    task body();
        int unsigned len = (addrs.size() != 0) ? addrs.size() : n;
        if (len < 2)
            `uvm_warning("APB_B2B", "burst length < 2 produces no ACCESS->SETUP edge")
        items.delete();
        for (int unsigned i = 0; i < len; i++) begin
            apb_item it = apb_item::type_id::create($sformatf("b2b_%0d", i));
            start_item(it);
            it.c_align.constraint_mode(0);
            it.c_b2b.constraint_mode(0);
            if (addrs.size() != 0) begin
                it.write = (writes.size() > i) ? writes[i] : 1'b0;
                it.addr  = addrs[i];
                it.data  = (datas.size() > i) ? datas[i] : 32'h0;
            end else if (!it.randomize() with { addr[1:0] == 2'b00; }) begin
                `uvm_error("APB_B2B", "randomize failed")
            end
            // Every item except the last promises an immediate follower; the last one
            // closes the burst so PSEL deasserts and the bus returns to IDLE.
            it.back_to_back = (i != len - 1);
            finish_item(it);
            items.push_back(it);
        end
    endtask
endclass
