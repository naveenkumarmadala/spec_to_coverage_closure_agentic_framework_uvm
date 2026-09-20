---
description: Run the end-to-end front-end lifecycle for an IP — from a requirement spec document (or a confirmed config) through registers, RTL, env, register + functional verification, to coverage closure — enforcing the quality gates between stages.
argument-hint: <spec-file | ip_name> [from=<stage>] [to=<stage>]
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, WebSearch, WebFetch
---

Run the full front-end flow via the **vlsi-orchestrator** agent.

If "$ARGUMENTS" names a **requirement document** (a file path), start at stage 0. If it names an IP
that already has a **confirmed** `ips/<ip>/ip_config.yaml`, start at stage 1.

Sequence, stopping at any red gate and reporting it:
0. `/vlsi-ingest <spec-file>` → auto-extract config + draft requirements, **STOP at the confirmation
   gate** until the user approves. (Skipped if a confirmed config is given.)
1. `/vlsi-spec $1`      → formalized requirements + design spec
2. `/vlsi-registers $1` → SystemRDL + PeakRDL (RTL/RAL/docs)
3. `/vlsi-rtl $1`       → RTL + static gate (must PASS)
4. `/vlsi-build-env $1` → vPlan + SystemVerilog UVM env + smoke test (xsim)
5. `/vlsi-verify $1`    → register verification (RAL) then functional tests on xsim
6. `/vlsi-close-coverage $1` → closure loop to the coverage goal

Honor optional `from=`/`to=` bounds in "$ARGUMENTS" to run a sub-span. Maintain the traceability
spine (REQ→SPEC→REG→RTL→VP→COV) across stages. End with a lifecycle summary table
(stage, status, key artifact, coverage where relevant). If an input is missing or a gate is red,
stop and tell the user exactly what's needed — don't fabricate progress.
