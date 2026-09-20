// pmtpc4_apb_slave — APB3 slave FSM + address-legality decode + wait-state shaping
// (SPEC-APB-1 / REQ-APB-1..3, errata 12.4). Wraps the PeakRDL passthrough regblock:
// only legal, aligned, in-range accesses are forwarded; reserved/RO-write/unaligned
// return PSLVERR in zero wait states; a legal CHx_COUNT read inserts exactly one wait.
module pmtpc4_apb_slave (
    input  logic        pclk,
    input  logic        presetn,       // async active-low
    // APB slave port
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [7:0]  paddr,
    input  logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic        pready,
    output logic        pslverr,
    // passthrough CPU interface to the regblock
    output logic        cpuif_req,
    output logic        cpuif_req_is_wr,
    output logic [6:0]  cpuif_addr,
    output logic [31:0] cpuif_wr_data,
    output logic [31:0] cpuif_wr_biten,
    input  logic [31:0] cpuif_rd_data
);
    typedef enum logic [1:0] {ST_IDLE, ST_SETUP, ST_ACCESS} apb_e;
    apb_e state;    // APB phase of the CURRENT cycle (decoded from the bus pins)
    logic waited;   // 1 after the single wait cycle of a CHx_COUNT read

    // The APB phase of the current cycle is fully determined by PSEL/PENABLE:
    //   PSEL=0            -> IDLE
    //   PSEL=1, PENABLE=0 -> SETUP
    //   PSEL=1, PENABLE=1 -> ACCESS
    // This MUST be combinational: PREADY is sampled by the master at the end of
    // the very cycle in which it drives PENABLE=1, so a registered phase decode
    // would make PREADY a cycle late and force a wait state onto *every* access
    // (violating REQ-APB-2/REQ-APB-3 and errata 12.4).
    always_comb begin
        if      (!psel)    state = ST_IDLE;
        else if (!penable) state = ST_SETUP;
        else               state = ST_ACCESS;
    end

    // ---- address legality decode (PADDR is stable through SETUP+ACCESS per APB) ----
    logic aligned, valid_off, ro_off, is_count_rd, err;
    always_comb begin
        aligned = (paddr[1:0] == 2'b00);
        unique case (paddr)
            8'h00, 8'h04, 8'h08, 8'h0C, 8'h10, 8'h14,
            8'h20, 8'h24, 8'h28, 8'h2C,
            8'h30, 8'h34, 8'h38, 8'h3C,
            8'h40, 8'h44, 8'h48, 8'h4C,
            8'h50, 8'h54, 8'h58, 8'h5C,
            8'h60, 8'h64:  valid_off = 1'b1;
            default:       valid_off = 1'b0;
        endcase
        ro_off      = (paddr == 8'h04) || (paddr == 8'h0C) ||
                      (paddr == 8'h2C) || (paddr == 8'h3C) ||
                      (paddr == 8'h4C) || (paddr == 8'h5C);
        is_count_rd = ~pwrite & ((paddr == 8'h2C) || (paddr == 8'h3C) ||
                                 (paddr == 8'h4C) || (paddr == 8'h5C));
        // Illegal: unaligned, reserved/undefined offset, or write to a fully-RO offset.
        err = (~aligned) | (~valid_off) | (pwrite & ro_off);
    end

    // ---- handshake outputs (meaningful only in ACCESS) ----
    wire in_access = (state == ST_ACCESS);
    always_comb begin
        pready  = 1'b0;
        if (in_access) begin
            if (err)              pready = 1'b1;   // errored access: zero wait (errata 12.4)
            else if (is_count_rd) pready = waited; // one wait state, then complete
            else                  pready = 1'b1;   // all other legal accesses: zero wait
        end
    end
    wire complete = in_access & pready;

    assign cpuif_req      = complete & ~err;        // pulse only in the completing legal cycle
    assign cpuif_req_is_wr = pwrite;
    assign cpuif_addr     = paddr[6:0];
    assign cpuif_wr_data  = pwdata;
    assign cpuif_wr_biten = {32{1'b1}};             // 32-bit word writes only
    assign prdata         = (complete & ~err & ~pwrite) ? cpuif_rd_data : 32'h0000_0000;
    assign pslverr        = complete & err;

    // ---- wait tracker ----
    // Set at the end of the first ACCESS cycle of a CHx_COUNT read (the inserted
    // wait cycle), so the second ACCESS cycle completes. Cleared everywhere else,
    // which also re-arms it correctly for back-to-back transfers.
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn)
            waited <= 1'b0;
        else if (in_access)
            waited <= ~pready;                 // mark the inserted wait cycle
        else
            waited <= 1'b0;
    end
endmodule
