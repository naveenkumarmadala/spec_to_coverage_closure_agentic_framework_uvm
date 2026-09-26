---
name: regression-runner
description: How to compile, elaborate, run, and regress the SystemVerilog UVM environment on AMD Vivado xsim across seeds, collecting functional + code coverage. Use when running tests, launching a regression, or wiring CI.
---

# Running & regressing on Vivado xsim (single-track SV/UVM)

All commands run from **WSL2** with Vivado on PATH (`settings64.sh` is auto-sourced in
interactive shells; scripts source `$VIVADO_SETTINGS` if it isn't). There is one verification
environment — standard SystemVerilog UVM in `ips/<ip>/dv/sv/` — and one simulator, xsim.

## The generic runner (use this, don't hand-roll)

`flow/scripts/xsim_flow.sh` is the low-level driver; `flow/scripts/run_regression.py` is the
seed-sweep orchestrator. Both are IP-agnostic (top module, tests, and seed count are derived
from the IP layout + `ip_config.yaml`).

```bash
# one test, end-to-end (compile + elaborate + run, seed 1)
bash flow/scripts/xsim_flow.sh smoke ips/<ip> <ip>_sanity_test

# full regression: every dv/sv/test/*_test, seeds PER TEST (see seed policy below),
# with functional + code coverage
python3 flow/scripts/run_regression.py ips/<ip>
python3 flow/scripts/run_regression.py ips/<ip> --seeds 3 --random-seeds 10  # override counts
python3 flow/scripts/run_regression.py ips/<ip> --tests t1,t2                # subset
python3 flow/scripts/run_regression.py ips/<ip> --no-cov                     # faster, no coverage
```

## Seed policy — seeds follow randomization intent, per test (not one global number)

A seed only changes anything for a test whose stimulus is **randomized**. So the runner sets the
seed count **per test**, and this is the rule to keep:

- **Directed test** (targets one specific scenario, deterministic stimulus) → **1 seed**. Extra seeds
  produce byte-identical runs — pure waste. The runner auto-detects this by scanning the test and the
  sequences it transitively references for native randomization (`randomize()` / `$urandom`); if none,
  it's directed.
- **Randomized test** (deliberately randomizes to hit the DUT broadly) → **multiple seeds**, and the
  **count is sized to that test's random-variable space** (how many random variables, their widths and
  constraint spread) — declared in `ip_config.yaml verification.regression.seeds_per_test`. A thin
  randomization space needs few seeds; a wide one earns more. It is **not** a flat number applied to
  every randomized test.

```yaml
verification:
  regression:
    seeds: 1                 # directed / seed-invariant tests
    random_seeds: 5          # fallback for a randomized test not listed
    seeds_per_test:
      <ip>_rand_test: 8      # sized to its random vars — justify the number in a comment
```

Put the constrained-random stimulus in its **own dedicated `<ip>_rand_test`** (the test that carries
the seed sweep). Keep `<ip>_full_test` — the union-coverage vehicle — at seed 1; it still *includes*
the random vseq for coverage, but its job is one all-scenarios sim, not a seed sweep. Before raising a
seed count, confirm the coverage actually moves across seeds — if a single seed already saturates the
bins, more seeds buy regression-stability / bug-hunt diversity, not coverage; say which.

## What the driver runs (the proven xsim invocation)

```bash
# compile — xsim -f files use `-i <dir>` for includes (NOT +incdir+) and `#` comments
xvlog -sv -L uvm -f ips/<ip>/dv/sv/filelist.f

# elaborate — built-in UVM 1.2 via -L uvm; add code coverage with -cc_type
xelab -L uvm -timescale 1ns/1ps -relax <ip>_tb_top -s <ip>_sim \
      -cc_type sbct --cov_db_dir <sv>/xsim.cov --cov_db_name <ip>_sim

# run one seed — reproducible stimulus via -sv_seed
xsim <ip>_sim -R -testplusarg "UVM_TESTNAME=<test>" -sv_seed <seed>
```

`-sv_seed <N>` is the single reproducibility knob: the same seed reproduces the same
constrained-random stimulus, exactly like a logged UVM seed. Pin the seed set so regressions
reproduce; the runner records seeds in the summary.

## Coverage merge & report — single-sim union, NOT a true multi-db merge (confirmed, not aspirational)

Each run's coverage database is snapshotted to `reports/_cov/<test>_seed<N>/` (functional under
`xsim.covdb/`, code under `xsim.codeCov/`). **`xcrg`'s documented multi-db merge
(`-cov_db_dir run1 -cov_db_dir run2 ... -merge_dir ...`) is unreliable on xsim 2025.1 — it has been
observed to segfault / produce untrustworthy results, not a hypothetical concern.** `run_regression.py`
does not use it. Instead, the "merged" number is a **single-simulation union**: `<ip>_full_test` runs
every scenario vseq back-to-back inside ONE simulation (one coverage database, seed 1), and that
database's own report IS the reported functional+code coverage — never combined with any other test's
database after the fact. This is why `<ip>_full_test` exists as its own test (see the seed-policy
section) and why it must actually include every vseq you want credited in the headline number — a vseq
that only runs in some OTHER standalone test is invisible to `coverage_summary.md`'s percentage even
though it ran and passed in the regression. If you add a new vseq/scenario and expect it to move the
reported coverage, confirm it is called from `<ip>_full_test`'s body, not just from its own test.

## Coverage reports, exclusions & the test plan

- **Two snapshots.** `<ip>_sim` = `tb_top` + the bind top (`tb/<ip>_binds.sv`): assertions,
  functional coverage, statement/branch/condition. `<ip>_tcov`
  (`xsim_flow.sh ... --toggle`) = `tb_top` only: **code toggle**. On xsim a bound checker erases the
  toggles of the DUT nets it observes, and `$dumpvars` merely present in the design stops toggle
  recording on others — so toggle is never read from `<ip>_sim`, and no `$dumpvars` is used at all.
- **Waveforms:** `bash flow/scripts/xsim_flow.sh wave ips/<ip> <test> [<seed>]` builds a third
  snapshot `<ip>_wave` (tb top + bind top, `-debug typical`, no coverage), logs every signal under the
  tb top and writes `ips/<ip>/reports/waves/<test>_seed<seed>.wdb`; open it with
  `xsim --gui <file>.wdb`. It never touches the coverage snapshots.
- After the regression, `run_regression.py` reruns the union test (`<ip>_full_test`, seed 1) on
  `<ip>_tcov` and **verifies identical execution** against the normal run (both clean, same scoreboard
  check count, same register-bit toggle totals). The result is the `# toggle-build ...
  identical_to_normal_run=` line in `reports/regression.txt`; a mismatch fails the regression.
- Reports, all from the union test: `reports/_cov/functional_report/`, `reports/_cov/code_report/`
  (DUT-scoped stmt/branch/cond), `reports/_cov/toggle_report/` (xcrg HTML from `<ip>_tcov`),
  **`reports/_cov/toggle_summary.txt`** (the DUT code-toggle number: bit-weighted over the IP's RTL
  files from xcrg's own per-file tables, plus every uncovered row), and
  `reports/_cov/reg_bit_toggle.txt` (register-bit toggle from `reg_bit_toggle_cov`: totals + every
  uncovered bit/direction). `run_regression.py ips/<ip> --reports-only` regenerates all of them from
  the existing databases without simulating.
- **Never quote the xcrg dashboard's toggle aggregate.** On xsim 2025.1 it is an unweighted average
  over report *files* and always includes the UVM library file (`xlnx_uvm_package.sv`) at 0% — no
  `file -`/`dir -` directive removes it (measured: dashboard 65.31% vs. 93.47% real bit-weighted).
- **Exclusion files** (generated by `gen_exclusions.py`, pure LF directives): `<ip>_cov_exclusions.txt`
  (DUT scoping only, for code_report) and `<ip>_toggle_exclusions.txt` (scoping + the maintained
  `<ip>_toggle_waivers.txt` sidecar, for toggle_report) — the machine-enforced waiver lists
  (REQ-VERIF-2). xcrg rewrites its exclusion file in place, so the flow passes a throwaway copy with
  any CR stripped (a single CR silently disables every directive); xcrg also needs a writable cwd and
  **relative** paths.
- **Traditional test plan**: `python3 flow/scripts/gen_testplan.py ips/<ip>` renders
  `vplan.yaml` + `requirements.md` into `ips/<ip>/vplan/<ip>_testplan.xlsx` (Test Plan / Requirements
  Traceability / Coverage Summary) — the human-facing, sign-off form of the YAML vPlan.

## Run artifacts (conventions)

```
reports/_runs/seed_<N>/<test>.log     # full per-run log
reports/regression.txt                # one `seed=.. test=.. ok=.. uvm_error=..` line per run
reports/_cov/<test>_seed<N>/          # per-run coverage db snapshot
reports/_cov/<union>_seed1_tcov/      # the toggle build's db (code toggle)
reports/_cov/{functional,code,toggle}_report/   # xcrg HTML reports
reports/_cov/reg_bit_toggle.txt       # register-bit toggle totals + uncovered list
reports/_runs/seed_1/<union>__tcov.log  # the toggle build's run log
```

## Rules

- A regression is green only when **all runs pass AND** the coverage goal is met — track both. A
  run passes only if it ran to the UVM report summary with `UVM_ERROR=0`, `UVM_FATAL=0`, zero SVA
  failures, and the scoreboard reporting `errors=0`.
- **Seeds follow randomization intent (see the seed-policy section):** directed tests run at 1 seed;
  randomized tests get a per-test count sized to their random-variable space. Don't sweep a directed
  test — its runs are byte-identical. Before raising a randomized test's count, confirm coverage
  actually moves across seeds; otherwise the extra seeds buy regression-stability, not coverage.
- xsim does **not** report assertion coverage; roll an assertion's evidence up as its pass/fail
  plus any SVA `cover property`, not as an assertion-coverage number.
- Keep run artifacts under `reports/` (git-ignored) but present for triage.
- Prefer running from the Linux filesystem where possible; on `/mnt/*` (Windows drives) xsim I/O
  is slower but works.
- **Never run two regressions against the same IP concurrently.** `xelab`/`xsim` share
  `ips/<ip>/dv/sv/xsim.dir` (and the coverage db under it); a second run starting while one is still in
  flight has been observed to silently corrupt the first's results (22 of 24 runs in one incident) with
  no error indicating anything went wrong — the regression just reports the wrong thing. Check
  `ps aux | grep -E "xelab|xsim|xvlog"` is empty before starting one, every time, including when
  launching a background/subagent task that will run one — this is exactly the kind of thing that's
  invisible until you compare against a rerun.
