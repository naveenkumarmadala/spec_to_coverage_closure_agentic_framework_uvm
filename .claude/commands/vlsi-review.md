---
description: Independently review an IP's RTL against its spec/requirements, and its verification collateral for trustworthiness (not just a green coverage number) — before treating either as signed off.
argument-hint: <ip_name> [design|verification]
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

Review IP `$1`. If `$2` is `design` or `verification`, run only that half; otherwise run both.

1. Delegate to the **design-reviewer** agent (using the **design-review** skill) to independently
   re-derive expected RTL behavior from `ips/$1/spec/requirements.md`, `spec/design_spec.md`, and the
   register spec/RDL, then compare against `ips/$1/rtl/*.sv` — reporting CONFIRMED/PLAUSIBLE findings
   and a traceability-completeness tally. If reviewing after a coverage-closure run, scope it to
   `git diff` on `ips/$1/rtl/` and `ips/$1/rdl/`.
2. Delegate to the **verification-reviewer** agent (using the **verification-review** skill) to audit
   `ips/$1/dv/` — environment wiring, scoreboard/assertion vacuity (including a deliberate, temporary
   mutation/bug-seeding spot-check that is always reverted), test quality, coverage-model integrity,
   and whether `ips/$1/reports/coverage_summary.md`'s waivers are rule-matched and structurally
   justified rather than a convenient allow-list.
3. Report both sets of findings together, most-severe first. State plainly whether the IP's current
   coverage number is *trustworthy evidence* of correctness or just a number — these are different
   claims. Do not fix anything found here; hand findings back to `rtl-designer`, `test-writer`, or the
   user to act on.
