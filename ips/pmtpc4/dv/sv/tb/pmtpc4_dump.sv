// Waveform dump, kept in its OWN top-level module (elaborated as an extra top of the normal
// snapshot only) and only active with +DUMP.
//
// Why a separate top and not an `if ($test$plusargs("DUMP"))` inside pmtpc4_tb_top: on
// Vivado xsim 2025.1 the mere PRESENCE of $dumpvars in the elaborated design stops code-toggle
// recording on some DUT nets, even when the call never executes (measured 2026-09-26: the
// prescaler counter, start_trig and pwm_level read 0% toggle with a gated-but-unexecuted
// $dumpvars present, and toggle normally when it is absent). xsim_flow.sh leaves this top
// out of the code-toggle snapshot (<ip>_tcov), so that build contains no $dumpvars at all.
// Use:  xsim_flow.sh run ips/pmtpc4 <test> <seed> --plusargs +DUMP   (normal snapshot)
module pmtpc4_dump;
    initial begin
        if ($test$plusargs("DUMP")) begin
            $dumpfile("pmtpc4.vcd");
            $dumpvars(0, pmtpc4_tb_top);
        end
    end
endmodule
