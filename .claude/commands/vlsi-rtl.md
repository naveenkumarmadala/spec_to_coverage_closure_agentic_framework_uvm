---
description: Author synthesizable SystemVerilog RTL for an IP from its design spec, integrate the generated register block, and pass the static gate (Verible lint + Verilator/Yosys elaboration).
argument-hint: <ip_name>
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

Design the RTL for IP `$1`.

1. Delegate to the **rtl-designer** agent to write `ips/$1/rtl/*.sv` implementing the design spec and
   instantiating the PeakRDL regblock (connect `hwif_in`/`hwif_out`). Tag blocks with `// impl SPEC-…`.
2. Delegate to the **lint-static-checker** agent to run the static gate: `verible-verilog-lint`,
   `verilator --lint-only -Wall`, and Yosys elaboration. Build `ips/$1/dv/filelist.f`.
3. Iterate until the gate is **PASS**. Report the gate result with real tool output for any failures.
   Do not declare the RTL done while the gate is red.
