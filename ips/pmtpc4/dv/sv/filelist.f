# PMTPC-4 SystemVerilog UVM compile list for AMD Vivado xsim (paths relative to dv/sv).
# xsim -f files use `-i <dir>` for include dirs (NOT +incdir+) and `#` for comments.
# Built-in UVM 1.2 is pulled in with `-L uvm` at the xvlog/xelab step (see flow/scripts).
# Typical use (from dv/sv):
#   xvlog -sv -L uvm -f filelist.f
#   xelab -L uvm -timescale 1ns/1ps -cov all pmtpc4_tb_top -s pmtpc4_sim
#   xsim pmtpc4_sim -R -testplusarg UVM_TESTNAME=pmtpc4_reg_reset_test -sv_seed 1

# ---- include dirs (UVC + env/seq/test class includes) ----
-i ../../../../vip/apb/sv
-i ../../../../vip/pwm/sv
-i ../../../../vip/common/sv
-i env
-i seq
-i test

# ---- DUT RTL ----
../../rdl/generated/rtl/pmtpc4_regblock_pkg.sv
../../rdl/generated/rtl/pmtpc4_regblock.sv
../../rtl/pmtpc4_prescaler.sv
../../rtl/pmtpc4_channel.sv
../../rtl/pmtpc4_apb_slave.sv
../../rtl/pmtpc4.sv

# ---- generated UVM RAL ----
../../rdl/generated/pmtpc4_ral_pkg.sv

# ---- reusable common VIP (reset control/observation interface) ----
../../../../vip/common/sv/reset_if.sv

# ---- reusable APB UVC ----
../../../../vip/apb/sv/apb_if.sv
../../../../vip/apb/sv/apb_pkg.sv
../../../../vip/apb/sv/apb_fsm_cov.sv

# ---- reusable PWM UVC (passive output observation) ----
../../../../vip/pwm/sv/pwm_if.sv
../../../../vip/pwm/sv/pwm_pkg.sv

# ---- env + sequences + tests (package) ----
pmtpc4_test_pkg.sv

# ---- SVA (bound) ----
sva/pmtpc4_apb_sva.sv
sva/pmtpc4_top_sva.sv
sva/pmtpc4_channel_sva.sv
sva/pmtpc4_pwm_cov.sv
sva/pmtpc4_presc_sva.sv

# ---- TB top + the bind top (the code-toggle snapshot omits the bind top) ----
tb/pmtpc4_tb_top.sv
tb/pmtpc4_binds.sv
