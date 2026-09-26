---
description: Author the SystemRDL register map for an IP and run PeakRDL to generate register-block RTL, the UVM RAL model, C headers, and HTML docs.
argument-hint: <ip_name>
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

Build the register layer for IP `$1`.

1. Delegate to the **register-designer** agent (using the **systemrdl-authoring** skill) to author
   `ips/$1/rdl/$1.rdl` from the design spec's register-to-function map. Keep REQ/SPEC IDs in each
   field `desc`.
2. From WSL2 with the venv active, run PeakRDL to generate (into `ips/$1/rdl/generated/`): regblock
   RTL (`--cpuif` matching `bus.protocol`), the UVM RAL package, HTML docs, and the C header.
3. Confirm the RDL compiles cleanly; report any PeakRDL errors verbatim and fix the RDL.
4. Generate the register-bit toggle config (the RDL's `singlepulse` fields, read by the reusable
   `reg_bit_toggle_cov`): `env/.venv/bin/python3 flow/scripts/gen_reg_toggle_cfg.py ips/$1`.
   Re-run it whenever the RDL changes (the regression runner also refreshes it automatically).
5. Summarize the register map (registers, offsets, key fields) and the generated artifacts.
