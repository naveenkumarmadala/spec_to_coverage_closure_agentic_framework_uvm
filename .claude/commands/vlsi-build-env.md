---
description: Build the verification plan and the SystemVerilog UVM testbench for an IP, then bring up a smoke test on Vivado xsim.
argument-hint: <ip_name>
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

Stand up verification for IP `$1`.

1. Delegate to the **verification-planner** agent (using the **vplan-schema** skill) to write
   `ips/$1/vplan/vplan.yaml`, ensuring every requirement is traced by ≥1 vPlan item.
2. Delegate to the **tb-architect** agent (using the **uvm-env-scaffold** skill) to generate the
   SystemVerilog UVM env (`ips/$1/dv/sv/`) from the config + vPlan, reusing bus VIP from `vip/`
   (build it there once if missing).
3. Bring up a **smoke test** (reset + one RAL register access, self-checked) and confirm it compiles,
   elaborates, and runs clean on **xsim**:
   `bash flow/scripts/xsim_flow.sh smoke ips/$1 $1_sanity_test` (see **regression-runner**). Report
   the result; if a construct fails on xsim, fix it and note the change — do not add a second track.
