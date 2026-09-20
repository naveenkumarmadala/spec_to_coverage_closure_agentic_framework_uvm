// APB protocol assertions — bound into the pmtpc4 top (white-box on the APB port).
module pmtpc4_apb_sva (
    input logic       pclk, presetn,
    input logic       psel, penable, pready, pslverr, pwrite,
    input logic [7:0] paddr
);
    wire access = psel & penable;

    function automatic bit valid(bit [7:0] a);
        case (a)
            8'h00,8'h04,8'h08,8'h0C,8'h10,8'h14,
            8'h20,8'h24,8'h28,8'h2C,8'h30,8'h34,8'h38,8'h3C,
            8'h40,8'h44,8'h48,8'h4C,8'h50,8'h54,8'h58,8'h5C,
            8'h60,8'h64: return 1; default: return 0;
        endcase
    endfunction
    function automatic bit ro(bit [7:0] a);
        return (a==8'h04)||(a==8'h0C)||(a==8'h2C)||(a==8'h3C)||(a==8'h4C)||(a==8'h5C);
    endfunction
    function automatic bit exp_err(bit [7:0] a, bit wr);
        return (a[1:0]!=0) || !valid(a) || (wr && ro(a));
    endfunction

    a_slverr_with_ready: assert property (@(posedge pclk) disable iff (!presetn)
        pslverr |-> pready);
    a_err_matches_decode: assert property (@(posedge pclk) disable iff (!presetn)
        (access && pready) |-> (pslverr == exp_err(paddr, pwrite)));
    a_stable_during_wait: assert property (@(posedge pclk) disable iff (!presetn)
        (access && !pready) |=> ($stable(paddr) && $stable(pwrite)));
    // errored access completes in zero wait states (errata 12.4)
    a_err_zero_wait: assert property (@(posedge pclk) disable iff (!presetn)
        (psel && !penable && exp_err(paddr, pwrite)) |=> (access && pready));
endmodule
