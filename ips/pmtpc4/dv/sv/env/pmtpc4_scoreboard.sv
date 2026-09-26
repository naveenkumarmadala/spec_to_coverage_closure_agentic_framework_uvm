// PMTPC-4 transaction scoreboard = the register/protocol reference model.
// Checks, for every APB access: PSLVERR legality, wait-state count, PRDATA=0 on
// error, and read-back of the deterministic (static) RW/RO registers against a
// shadow. Cycle-level behavior (PWM waveform, IRQ aggregation, W1C set-priority,
// MODULE_EN freeze, reset) is proven by the SVA layer (sva/),
// which is where those cycle-accurate golden checks belong.
`uvm_analysis_imp_decl(_apb)
class pmtpc4_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(pmtpc4_scoreboard)
    uvm_analysis_imp_apb #(apb_item, pmtpc4_scoreboard) sb_imp;
    int unsigned shadow [bit [7:0]];
    int          errors, checks;

    function new(string n, uvm_component p);
        super.new(n, p); sb_imp = new("sb_imp", this);
    endfunction

    // ---- address classification (Register Spec Rev 1.1) ----
    function bit is_valid(bit [7:0] a);
        case (a)
            8'h00,8'h04,8'h08,8'h0C,8'h10,8'h14,
            8'h20,8'h24,8'h28,8'h2C,8'h30,8'h34,8'h38,8'h3C,
            8'h40,8'h44,8'h48,8'h4C,8'h50,8'h54,8'h58,8'h5C,
            8'h60,8'h64: return 1;
            default:     return 0;
        endcase
    endfunction
    function bit is_ro(bit [7:0] a);
        return (a==8'h04)||(a==8'h0C)||(a==8'h2C)||(a==8'h3C)||(a==8'h4C)||(a==8'h5C);
    endfunction
    function bit is_count(bit [7:0] a);
        return (a==8'h2C)||(a==8'h3C)||(a==8'h4C)||(a==8'h5C);
    endfunction
    function bit exp_err(bit [7:0] a, bit wr);
        return (a[1:0]!=0) || !is_valid(a) || (wr && is_ro(a));
    endfunction
    function int exp_waits(bit [7:0] a, bit wr);
        return (!exp_err(a,wr) && !wr && is_count(a)) ? 1 : 0;
    endfunction
    // -1 => dynamic register (no static readback prediction)
    // VP-SELFCLR (errata 12.5): CTRL.SOFT_RESET and CHx_CTRL.CH_START are singlepulse
    // fields that must NEVER be observable as 1 on any subsequent read, including a
    // back-to-back minimum-latency read. selfclear_mask() below is FOLDED INTO the
    // comparison mask (not excluded from it, as the earlier revision did) so the
    // shadow's stored value for those bits is unconditionally forced to 0 regardless
    // of what was written — the model itself asserts the self-clear property on every
    // single subsequent read, not just in a dedicated test.
    function int readmask(bit [7:0] a);
        if (a==8'h00) return 32'h3;          // CTRL: MODULE_EN persists; SOFT_RESET forced 0 (self-clears)
        if (a==8'h08) return 32'h1;          // GLOBAL_IE
        if (a==8'h10) return 32'hFFFF;       // PRESCALER
        if (a==8'h14) return 32'h1;          // CLK_SEL
        if (a==8'h64) return 32'hF;          // INT_ENABLE
        if (a inside {8'h20,8'h30,8'h40,8'h50}) return 32'h1E; // CH_CTRL sw-persist bits: CH_MODE|PWM_EN|CH_PAUSE
                                                                // (0x16) PLUS CH_START(bit3=0x8, forced 0 below) =
                                                                // 0x1E. CH_EN(0) is hw-cleared on one-shot expiry
                                                                // (hwclr) so it's not statically predictable —
                                                                // its dynamics are checked by the directed channel
                                                                // vseqs + RAL, not this shadow.
        if (a inside {8'h24,8'h34,8'h44,8'h54}) return 32'hFFFF; // CH_PERIOD
        if (a inside {8'h28,8'h38,8'h48,8'h58}) return 32'hFFFF; // CH_COMPARE
        return -1;                           // STATUS/GLOBAL_ISR/INT_STATUS: dynamic (see VP-INT-W1C —
                                              // checked by a directed per-bit test instead, not this shadow;
                                              // hw can set these independent of any write, which a pure
                                              // write-history shadow cannot predict). CH_COUNT: see
                                              // last_period[]/CH_COUNT bound-check below (VP-CH-COUNT-READBACK).
    endfunction
    // Bits that must read back as 0 unconditionally, regardless of what was written
    // (errata 12.5 self-clearing fields).
    function int selfclear_mask(bit [7:0] a);
        if (a==8'h00) return 32'h2;                              // CTRL.SOFT_RESET
        if (a inside {8'h20,8'h30,8'h40,8'h50}) return 32'h8;    // CHx_CTRL.CH_START
        return 0;
    endfunction

    // ---- VP-CH-COUNT-READBACK: bound-check, not a full value predictor -------------
    // The scoreboard only sees COMPLETED APB transactions, not pclk/tick_en, so it
    // cannot cycle-accurately predict a live-decrementing counter (that cycle-accurate
    // job belongs to the SVA layer — see VP-CH-COUNT-VALUE). What IS checkable at the
    // bus level without cycle modeling: CHx_COUNT can never read back higher than the
    // last value written to CHx_PERIOD (COUNT only ever loads FROM period and decrements
    // — REQ-CORE-1), so a wrong-register read, a stuck-high counter, or a corrupted
    // reload would be caught even though the exact mid-count value is not predicted.
    int unsigned last_period[4];
    function int ch_of(bit [7:0] a);
        case (a & 8'hF0)
            8'h20: return 0; 8'h30: return 1; 8'h40: return 2; 8'h50: return 3;
            default: return -1;
        endcase
    endfunction

    function void write_apb(apb_item t);
        bit [7:0] a = t.addr[7:0];
        bit ee = exp_err(a, t.write);
        int wm;
        checks++;
        if (t.slverr != ee) begin fail($sformatf("PSLVERR mismatch @0x%02h exp %0b got %0b", a, ee, t.slverr)); return; end
        if (ee) begin
            if (!t.write && t.rdata != 0) fail($sformatf("errored read PRDATA!=0 @0x%02h", a));
            return;
        end
        if (t.waits != exp_waits(a, t.write))
            fail($sformatf("wait-state mismatch @0x%02h exp %0d got %0d", a, exp_waits(a,t.write), t.waits));
        wm = readmask(a);
        if (t.write) begin
            if (wm != -1) shadow[a] = (t.data & wm) & ~selfclear_mask(a);
            // Track the MAX PERIOD value ever written per channel, not just the most
            // recent write: a PERIOD write mid-RUNNING is deferred to the next LOAD
            // (Design 7.4 / VP-PWM-SHADOW-DEFER), so COUNT can legitimately still be
            // bounded by an OLDER, larger PERIOD value for a while after a smaller
            // one is written. The max is monotonically safe either way (COUNT can
            // never exceed ANY period value it was ever validly loaded from).
            // Empirically found this session: a plain "most recent write" bound
            // false-failed under exactly this deferred-write scenario.
            if ((a[3:0] == 4'h4) && ch_of(a) != -1) begin
                int ch = ch_of(a);
                if (t.data[15:0] > last_period[ch]) last_period[ch] = t.data[15:0];
            end
        end else if (wm != -1) begin
            int unsigned exp = (shadow.exists(a) ? shadow[a] : 0) & wm;
            if ((t.rdata & wm) != exp)
                fail($sformatf("readback @0x%02h exp 0x%0h got 0x%0h", a, exp, t.rdata & wm));
        end
        if (!t.write && is_count(a)) begin
            int ch = ch_of(a);
            if (ch != -1 && t.rdata[15:0] > last_period[ch])
                fail($sformatf("CH%0d_COUNT readback 0x%0h exceeds last-written PERIOD 0x%0h",
                               ch, t.rdata[15:0], last_period[ch]));
        end
    endfunction

    // Reset-aware hook. PRESETn returns every modelled register to its reset value
    // (all reset=0 in pmtpc4.rdl), so the readback shadow must be dropped — the
    // read path treats an absent entry as 0, which is exactly the post-reset state.
    // Called from pmtpc4_base_vseq::async_reset() / pmtpc4_env::handle_reset();
    // without it every post-reset read of a previously-written register mismatches.
    virtual function void handle_reset();
        shadow.delete();
        foreach (last_period[i]) last_period[i] = 0;
        `uvm_info("SCB", "readback shadow cleared on reset", UVM_MEDIUM)
    endfunction

    function void fail(string m); errors++; `uvm_error("SCB", m) endfunction
    function void report_phase(uvm_phase phase);
        `uvm_info("SCB", $sformatf("checks=%0d errors=%0d", checks, errors), UVM_LOW)
        if (errors != 0) `uvm_error("SCB", $sformatf("%0d scoreboard error(s)", errors))
    endfunction
endclass
