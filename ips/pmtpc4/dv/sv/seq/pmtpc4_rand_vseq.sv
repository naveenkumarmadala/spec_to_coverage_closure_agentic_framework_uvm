// Constrained-random register traffic for code-coverage closure (toggle/branch/
// condition). Uses native SystemVerilog randomization (rand/constraint/dist),
// seeded by `xsim -sv_seed`, to drive full-range values into the writable
// registers of all four channels so their datapath bits toggle 0<->1.
class pmtpc4_rand_item extends uvm_sequence_item;
    `uvm_object_utils(pmtpc4_rand_item)
    rand bit [1:0]  ch;               // target channel 0..3
    rand bit [2:0]  which;            // 0=period 1=compare 2=ctrl 3=prescaler 4=inten 5=gie
    rand bit [15:0] val16;
    rand bit [4:0]  ctrl;             // EN|MODE|PWM|START|PAUSE
    // bias val16 toward toggling extremes AND the full range (so every bit flips)
    constraint c_val { val16 dist { 16'h0000:=1, 16'hFFFF:=1, 16'h5555:=1, 16'hAAAA:=1,
                                    [1:16'hFFFE]:/6 }; }
    function new(string n="pmtpc4_rand_item"); super.new(n); endfunction
endclass

class pmtpc4_rand_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_rand_vseq)
    int unsigned n_iters = 80;   // enough to hit the dist extremes; keeps full_test fast in regression
    function new(string name="pmtpc4_rand_vseq"); super.new(name); endfunction

    task body();
        pmtpc4_rand_item it = pmtpc4_rand_item::type_id::create("it");
        reg_wr(p_sequencer.ral.CTRL, 1);                 // MODULE_EN=1
        for (int i = 0; i < n_iters; i++) begin
            if (!it.randomize()) `uvm_fatal("RAND", "randomize failed")
            case (it.which)
                0: reg_wr(chan(it.ch).CH_PERIOD,  it.val16);
                1: reg_wr(chan(it.ch).CH_COMPARE, it.val16);
                2: reg_wr(chan(it.ch).CH_CTRL,    it.ctrl);
                3: reg_wr(p_sequencer.ral.PRESCALER, it.val16);
                4: reg_wr(p_sequencer.ral.INT_ENABLE, it.val16[3:0]);
                default: reg_wr(p_sequencer.ral.GLOBAL_IE, it.val16[0]);
            endcase
            if ((i % 7) == 0) cyc(2);                    // let some ticks advance the datapaths
        end
        // exercise INT_STATUS W1C bits (toggle) + read back COUNT on all channels
        begin uvm_reg_data_t v;
            reg_wr(p_sequencer.ral.INT_STATUS, 4'hF);
            for (int c = 0; c < 4; c++) reg_rd(chan(c).CH_COUNT, v);
        end
        // full-width raw APB traffic: 32-bit random data into valid PERIOD/COMPARE
        // addresses so the pwdata/prdata/paddr buses toggle across all bits (the
        // regblock ignores the unused upper bits; the bus nets still toggle).
        begin
            apb_item it;
            bit [7:0] per[4] = '{8'h24,8'h34,8'h44,8'h54};   // CHx_PERIOD
            bit [7:0] cmp[4] = '{8'h28,8'h38,8'h48,8'h58};   // CHx_COMPARE
            for (int i = 0; i < 40; i++) begin
                bit [31:0] d = {$urandom(), $urandom()};      // 32-bit random
                raw(1, per[i%4], d, it);
                raw(1, cmp[i%4], ~d, it);
                raw(0, per[i%4], 0, it);                      // read back (toggles prdata)
            end
        end
    endtask
endclass
