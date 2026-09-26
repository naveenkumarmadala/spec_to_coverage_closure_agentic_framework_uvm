---
description: Write the directed and constrained-random SystemVerilog UVM tests/sequences for an IP's vPlan, run them on xsim, and report pass/fail plus initial coverage.
argument-hint: <ip_name>
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

Write and run tests for IP `$1`.

1. Delegate to the **test-writer** agent to implement the tests named in `ips/$1/vplan/vplan.yaml` —
   directed tests for specific requirements/corners, native constrained-random (`rand`/`constraint`/
   `dist`, per the **constrained-random** skill) for breadth, all self-checking against the
   scoreboard/RAL. Each test's header cites its `VP-` id.
2. Run the tests on **xsim** using the **regression-runner** skill
   (`python3 flow/scripts/run_regression.py ips/$1`).
   This includes the standard `$1_reg_toggle_test`: fill its hardware-set-field section so every
   register field bit is seen rising and falling.
3. Report per-test pass/fail and the initial functional + code coverage (code toggle from
   `reports/_cov/toggle_summary.txt`, register-bit toggle from `reports/_cov/reg_bit_toggle.txt` —
   never the xcrg dashboard toggle figure). List which vPlan items are now covered vs still open.
   Then suggest `/vlsi-close-coverage $1`.
