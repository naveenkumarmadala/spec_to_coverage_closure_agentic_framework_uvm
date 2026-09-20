// APB transaction item.
class apb_item extends uvm_sequence_item;
    rand bit        write;
    rand bit [31:0] addr;      // low ADDR_WIDTH bits used
    rand bit [31:0] data;      // write data
    // ---- back-to-back (ACCESS -> SETUP with PSEL held) request -------------
    // OPT-IN, DEFAULT OFF. When set (and apb_agent_cfg.b2b_enable is also set) the
    // driver does NOT deassert PSEL at the end of this transfer's ACCESS phase; it
    // moves straight into the SETUP phase of the FOLLOWING item. This is the legal
    // APB back-to-back optimisation.
    //
    // CONTRACT: back_to_back==1 is a PROMISE by the sequence that another item
    // follows IMMEDIATELY (no intervening delay). The driver releases the sequence
    // early (at the start of this ACCESS phase) so the follower is queued in time to
    // keep the SETUP phase exactly one cycle long — an extended SETUP would be a
    // protocol violation. Set it on every item of a burst EXCEPT the last.
    //
    // CONSEQUENCE of the early release: rdata/slverr/waits for a back_to_back item
    // are written ~1 clock AFTER finish_item() returns, so do not read them until
    // the burst has finished (they are all valid once the closing, non-b2b item
    // completes). Leave back_to_back=0 (the default) and the classic
    // one-item-per-transfer semantics are byte-identical to before this knob existed.
    rand bit        back_to_back;

    // captured on completion:
    bit [31:0]      rdata;
    bit             slverr;
    int             waits;
    bit             aborted;   // transfer torn down by a reset assertion mid-transfer

    `uvm_object_utils_begin(apb_item)
        `uvm_field_int(write,        UVM_ALL_ON)
        `uvm_field_int(addr,         UVM_ALL_ON)
        `uvm_field_int(data,         UVM_ALL_ON)
        `uvm_field_int(back_to_back, UVM_ALL_ON)
        `uvm_field_int(rdata,        UVM_ALL_ON)
        `uvm_field_int(slverr,       UVM_ALL_ON)
        `uvm_field_int(waits,        UVM_ALL_ON)
        `uvm_field_int(aborted,      UVM_ALL_ON)
    `uvm_object_utils_end

    // Aligned by default; tests deliberately relax this to exercise PSLVERR.
    constraint c_align { soft addr[1:0] == 2'b00; }
    // Back-to-back is never produced by accident: a randomized item is a single
    // transfer unless the test explicitly asks for chaining.
    constraint c_b2b   { soft back_to_back == 1'b0; }

    function new(string name = "apb_item"); super.new(name); endfunction
endclass
