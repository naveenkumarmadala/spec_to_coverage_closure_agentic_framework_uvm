// Directed channel scenarios (one-shot, periodic, pause, freeze, soft-disable).
// CH_CTRL bits: CH_EN=1 CH_MODE=2 PWM_EN=4 CH_START=8 CH_PAUSE=16.
class pmtpc4_oneshot_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_oneshot_vseq)
    function new(string name="pmtpc4_oneshot_vseq"); super.new(name); endfunction
    task body();
        uvm_reg_data_t v;
        enable_module(0);
        reg_wr(chan(0).CH_PERIOD, 4);
        reg_wr(chan(0).CH_CTRL, 1);            // CH_EN, one-shot
        cyc(40);
        reg_rd(p_sequencer.ral.INT_STATUS, v);
        if ((v & 1) == 0) `uvm_error("ONESHOT", "ch0 did not expire")
        reg_rd(chan(0).CH_CTRL, v);
        if ((v & 1) != 0) `uvm_error("ONESHOT", "one-shot must self-clear CH_EN")
    endtask
endclass

class pmtpc4_periodic_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_periodic_vseq)
    function new(string name="pmtpc4_periodic_vseq"); super.new(name); endfunction
    task body();
        uvm_reg_data_t v;
        enable_module(0);
        reg_wr(chan(0).CH_PERIOD, 3);
        reg_wr(chan(0).CH_CTRL, 1|2);          // periodic
        cyc(20); reg_rd(p_sequencer.ral.INT_STATUS, v);
        if (!(v & 1)) `uvm_error("PERIODIC", "did not expire")
        reg_wr(p_sequencer.ral.INT_STATUS, 1); // W1C clear
        cyc(20); reg_rd(p_sequencer.ral.INT_STATUS, v);
        if (!(v & 1)) `uvm_error("PERIODIC", "did not re-expire after clear")
    endtask
endclass

class pmtpc4_pause_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_pause_vseq)
    function new(string name="pmtpc4_pause_vseq"); super.new(name); endfunction
    task body();
        uvm_reg_data_t c1, c2, c3;
        enable_module(3);
        reg_wr(chan(0).CH_PERIOD, 16'h00FF);
        reg_wr(chan(0).CH_CTRL, 1|2); cyc(20);
        reg_wr(chan(0).CH_CTRL, 1|2|16);       // pause
        reg_rd(chan(0).CH_COUNT, c1); cyc(20); reg_rd(chan(0).CH_COUNT, c2);
        if (c1 != c2) `uvm_error("PAUSE", "COUNT must freeze while paused")
        reg_wr(chan(0).CH_CTRL, 1|2); cyc(20); reg_rd(chan(0).CH_COUNT, c3);  // resume
        if (c3 == c2) `uvm_error("PAUSE", "COUNT must advance after resume")
    endtask
endclass

class pmtpc4_freeze_vseq extends pmtpc4_base_vseq;   // MODULE_EN freeze (errata 12.3)
    `uvm_object_utils(pmtpc4_freeze_vseq)
    function new(string name="pmtpc4_freeze_vseq"); super.new(name); endfunction
    task body();
        uvm_reg_data_t c1, c2, c3, c3a, s;
        enable_module(0);
        reg_wr(chan(0).CH_COMPARE, 1);
        reg_wr(chan(0).CH_PERIOD, 16'h00FF);
        reg_wr(chan(0).CH_CTRL, 1|2|4); cyc(30);
        reg_rd(chan(0).CH_COUNT, c1);
        reg_wr(p_sequencer.ral.CTRL, 0);       // MODULE_EN=0
        reg_rd(p_sequencer.ral.STATUS, s);
        if (s & 1) `uvm_error("FREEZE", "BUSY must be 0 while frozen")
        // COUNT is frozen once MODULE_EN=0 has taken effect. Read it post-freeze (c2),
        // wait, read again (c3a): a frozen COUNT must be *stable* and non-zero (held, not
        // reset). Comparing to the pre-freeze c1 would be racy — COUNT legitimately keeps
        // decrementing in the APB cycles between the c1 read and the CTRL write landing.
        reg_rd(chan(0).CH_COUNT, c2);
        cyc(20); reg_rd(chan(0).CH_COUNT, c3a);
        if (c2 != c3a) `uvm_error("FREEZE", $sformatf("COUNT must be frozen (c2=0x%0h c3a=0x%0h)", c2, c3a))
        if (c2 == 0)   `uvm_error("FREEZE", "COUNT must hold its value, not reset to 0, while frozen")
        reg_wr(p_sequencer.ral.CTRL, 1); cyc(10); reg_rd(chan(0).CH_COUNT, c3);
        if (c3 == c3a) `uvm_error("FREEZE", "COUNT must resume advancing from the frozen value")
    endtask
endclass

class pmtpc4_softdisable_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_softdisable_vseq)
    function new(string name="pmtpc4_softdisable_vseq"); super.new(name); endfunction
    task body();
        uvm_reg_data_t v;
        enable_module(3);
        reg_wr(chan(0).CH_PERIOD, 16'h00FF);
        reg_wr(chan(0).CH_CTRL, 1|2); cyc(30);
        reg_wr(chan(0).CH_CTRL, 0);            // CH_EN=0 -> immediate IDLE
        cyc(5);
        reg_rd(chan(0).CH_CTRL, v);
        if (v & 1) `uvm_error("SOFTDIS", "CH_EN should read 0")
    endtask
endclass
