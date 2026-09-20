// F3 regression test (2026-09-19 audit): a software write to CHx_CTRL landing on the
// exact same cycle as the one-shot CH_EN self-clear (hwclr) must not defeat the clear --
// hwclr must win (precedence=hw, now declared on CH_EN in pmtpc4.rdl). Before the fix,
// SystemRDL's default precedence=sw meant a coincident software write silently dropped
// the hwclr pulse forever, permanently wedging the channel (CH_EN stuck at 1, channel
// stuck IDLE, no rising edge available to restart it).
//
// Exact cycle alignment between an APB write and an internal one-shot expiry is not
// practical to control precisely from a vseq without internal timing knowledge that would
// make this test as fragile as the bug it's checking for. Instead: run a short one-shot
// channel to expiry repeatedly, each time spraying back-to-back PWM_EN-toggling writes to
// the SAME CHx_CTRL register across the whole run (via the APB back-to-back driver mode,
// so writes land on consecutive bus cycles with no gap) -- across enough repeats, at least
// one write is virtually certain to land on the exact hwclr cycle. If the fix works, CH_EN
// always ends up 0 regardless of which cycle a write happened to land on; if it doesn't,
// CH_EN sticks at 1 on the sprayed run and the channel never re-arms.
class pmtpc4_selfclear_race_vseq extends pmtpc4_base_vseq;
    `uvm_object_utils(pmtpc4_selfclear_race_vseq)
    function new(string name="pmtpc4_selfclear_race_vseq"); super.new(name); endfunction

    localparam bit [31:0] EN=1, PWM=4;

    task run_with_spray(int ch, int unsigned n_writes);
        uvm_reg_data_t v;
        bit [31:0] addr = chan(ch).CH_CTRL.get_address();
        bit        wr[$];
        bit [31:0] data[$];
        apb_item items[$];

        reg_wr(p_sequencer.ral.PRESCALER, 0);
        reg_wr(p_sequencer.ral.CTRL, EN);
        reg_wr(chan(ch).CH_PERIOD, 16'd2);             // short one-shot: expires in a handful of ticks
        reg_wr(chan(ch).CH_CTRL, EN);

        // spray n_writes back-to-back writes toggling PWM_EN (harmless, doesn't affect
        // CH_EN itself) at CHx_CTRL, chained with no gap via the b2b driver mode --
        // covers a wide window of cycles around the expected expiry.
        set_b2b(1);
        wr.delete(); data.delete();
        for (int unsigned i = 0; i < n_writes; i++) begin
            wr.push_back(1'b1);
            data.push_back(i[0] ? (EN|PWM) : EN);      // alternate PWM_EN 0/1, CH_EN always requested 1
        end
        begin
            bit [31:0] addrs[$];
            for (int unsigned i = 0; i < n_writes; i++) addrs.push_back(addr);
            raw_b2b(wr, addrs, data, items);
        end
        set_b2b(0);

        cyc(50);                                        // let any pending expiry complete
        reg_rd(chan(ch).CH_CTRL, v);
        chk(v[0] == 1'b0,
            $sformatf("CH%0d: CH_EN must have self-cleared to 0 after one-shot expiry even with %0d coincident CHx_CTRL writes sprayed across the expiry window (got CH_CTRL=0x%0h -- the hwclr precedence race was lost)",
                      ch, n_writes, v));
        reg_rd(p_sequencer.ral.INT_STATUS, v);
        chk(v[ch] == 1'b1, $sformatf("CH%0d: must still have expired and latched its interrupt", ch));
        reg_wr(p_sequencer.ral.INT_STATUS, (32'h1 << ch));
        reg_wr(chan(ch).CH_CTRL, 0);
    endtask

    task body();
        // repeat several times with a fresh spray each time to widen the chance of
        // landing on the exact hwclr cycle across the run
        for (int rep = 0; rep < 5; rep++) run_with_spray(2, 40);
        reg_wr(p_sequencer.ral.PRESCALER, 0);
    endtask
endclass
