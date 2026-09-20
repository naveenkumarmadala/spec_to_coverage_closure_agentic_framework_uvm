// Reusable APB3 interface (VIP). Defaults 8-bit addr / 32-bit data.
interface apb_if #(parameter int ADDR_WIDTH = 8, parameter int DATA_WIDTH = 32)
                  (input logic pclk, input logic presetn);
    logic                   psel, penable, pwrite;
    logic [ADDR_WIDTH-1:0]  paddr;
    logic [DATA_WIDTH-1:0]  pwdata, prdata;
    logic                   pready, pslverr;

    clocking drv_cb @(posedge pclk);
        default input #1step output #1;
        output psel, penable, pwrite, paddr, pwdata;
        input  prdata, pready, pslverr;
    endclocking

    clocking mon_cb @(posedge pclk);
        default input #1step;
        input psel, penable, pwrite, paddr, pwdata, prdata, pready, pslverr;
    endclocking

    modport drv (clocking drv_cb, input presetn);
    modport mon (clocking mon_cb, input presetn);
endinterface
