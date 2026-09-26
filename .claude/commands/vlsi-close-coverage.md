---
description: Run the coverage-closure loop for an IP — regress across seeds, merge functional + code coverage, triage holes, and drive new stimulus until the coverage goal is met and every requirement is covered.
argument-hint: <ip_name>
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

Close coverage for IP `$1`.

Delegate to the **coverage-closure** agent (using the **coverage-triage** and **regression-runner**
skills) to run the loop:

1. Regress the full test list across the configured seeds on **xsim**
   (`python3 flow/scripts/run_regression.py ips/$1`); collect functional + code coverage. The runner
   also rebuilds the union test on the code-toggle snapshot (tb top without the bind/dump tops) and
   must report `identical_to_normal_run=True`. Read the numbers from `reports/_cov/`:
   `functional_report/`, `code_report/` (stmt/branch/cond), `toggle_summary.txt` (DUT code toggle,
   bit-weighted) and `reg_bit_toggle.txt` (generated register block). Never quote the xcrg dashboard's
   toggle figure — it averages over files and counts the UVM library file at 0%.
   `run_regression.py ips/$1 --reports-only` regenerates the reports without simulating.
2. Merge coverage and produce `ips/$1/reports/coverage_summary.md` with per-vPlan and **per-REQ**
   roll-ups.
3. Triage each hole (reachable→add stimulus via test-writer; unreachable→justified waiver; bug→file
   back to the owning stage). Loop until `coverage_goal_pct` is met **and** every requirement traces
   to a covered item.
4. Report the **real** coverage number, the closure status per requirement, remaining holes with
   dispositions, and any waivers with justification. Do not claim closure that isn't proven.
