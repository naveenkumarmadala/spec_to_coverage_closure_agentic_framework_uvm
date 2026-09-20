// VP-APB-FSM-B2B: drive a real back-to-back APB burst (PSEL held across the
// ACCESS->SETUP boundary) so cg_apb_fsm.cp_trans.access_setup_b2b — structurally
// unreachable before the VIP's b2b driver mode existed — is actually hit.
//
// This vseq only CREATES the scenario (turns on the opt-in b2b knobs and issues a
// multi-item raw burst); the self-checking is the existing scoreboard, which sees
// every completed item exactly as it would a normal transfer (VP-APB-XFER's
// PSLVERR/wait/readback checks apply unchanged), and cg_apb_fsm (bound once at
// tb_top, sampled every pclk from psel/penable) is what actually credits the bin —
// this sequence never samples coverage itself.
class pmtpc4_apb_b2b_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_apb_b2b_vseq)
    function new(string name="pmtpc4_apb_b2b_vseq"); super.new(name); endfunction

    task body();
        bit        wr[$];
        bit [31:0] addr[$];
        bit [31:0] data[$];
        apb_item   items[$];

        // A mixed read/write burst over legal, zero-wait registers so every chained
        // boundary is a genuine ACCESS->SETUP with PSEL never dropping low.
        wr   = '{1, 0, 1, 0, 1};
        addr = '{32'h08, 32'h08, 32'h14, 32'h14, 32'h10};   // GLOBAL_IE, GLOBAL_IE, CLK_SEL, CLK_SEL, PRESCALER
        data = '{32'h1, 32'h0, 32'h1, 32'h0, 32'hBEEF};

        set_b2b(1);
        raw_b2b(wr, addr, data, items);
        set_b2b(0);   // opt back out; nothing after this vseq is affected

        foreach (items[i])
            chk(!items[i].aborted, $sformatf("b2b item %0d unexpectedly aborted", i));
    endtask
endclass
