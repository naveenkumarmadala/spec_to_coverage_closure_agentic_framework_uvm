# Commands — Setup to Coverage Closure

Step-by-step commands for this repo, from a fresh clone to coverage closure. Three parts:

- **Part A** — one-time environment setup.
- **Part B** — the generic per-IP flow (any new IP, via slash commands).
- **Part C** — running the `pmtpc4` reference IP on Vivado xsim (compile → elaborate → run → regress).

Slash commands (`/vlsi-*`) run inside Claude Code. Everything else runs in a WSL2 Ubuntu shell with
Vivado xsim on PATH.

---

## Part A — One-time environment setup

*First time on this machine? [`GETTING_STARTED.md`](GETTING_STARTED.md) walks through all of this from
a blank machine, including WSL2 and the Vivado install.*

```bash
# From WSL2 Ubuntu, at the repo root — run this yourself (needs your sudo password interactively)
bash env/bootstrap-wsl2.sh            # Verible, Yosys, sv2v, Verilator/Icarus (helpers), PeakRDL venv
source env/.venv/bin/activate         # activate the Python venv (needed in every new shell)
```

Install Vivado xsim separately (free ML Standard, into WSL2) — see [`env/README.md`](env/README.md).
Then make it available in each shell (add to `~/.bashrc`):

```bash
source /tools/Xilinx/2025.1/Vivado/settings64.sh
```

Verify:
```bash
xvlog --version && xsim --version                     # the UVM simulator
bash env/bootstrap-wsl2.sh --check                    # helper tools + whether xsim is reachable
```

---

## Part B — Generic flow for a NEW IP (any protocol/subsystem)

Run these as Claude Code slash commands, in order. Each stage is a hard gate — fix failures first.

```
/vlsi-ingest path/to/requirement_spec.(md|pdf|docx) <ip_name>
```
Extracts a draft `ip_config.yaml` + requirements. **Stops at a confirmation gate** — review/correct
`ips/<ip_name>/ip_config.yaml` before continuing.

```
/vlsi-spec <ip_name>            # requirements database + design specification
/vlsi-registers <ip_name>       # SystemRDL + PeakRDL → regblock RTL, UVM RAL, C header, HTML
/vlsi-rtl <ip_name>             # synthesizable RTL + static gate (Verible + Verilator lint + Yosys)
/vlsi-build-env <ip_name>       # vPlan + SystemVerilog UVM env + smoke test on xsim
/vlsi-verify <ip_name>          # directed + native constrained-random tests, run on xsim
/vlsi-close-coverage <ip_name>  # regress across seeds, merge coverage, triage to the goal
/vlsi-status <ip_name>          # lifecycle status at any point
```

Or run the whole thing unattended after the confirmation gate:
```
/vlsi-flow <ip_name>
```

---

## Part C — Running `pmtpc4` on xsim

`pmtpc4` (4-channel timer/PWM, APB) is the reference IP. Its complete SystemVerilog UVM environment
compiles, elaborates, and runs on xsim.

### C1. Static gate — lint + synthesizability elaboration
```bash
source env/.venv/bin/activate

# Verible lint over hand-authored RTL
verible-verilog-lint ips/pmtpc4/rtl/*.sv

# Verilator lint-only (fast helper) — shared waiver covers peakrdl-regblock false-positives
verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
  flow/tools/verilator_waivers.vlt \
  -f ips/pmtpc4/dv/filelist.f --top-module pmtpc4

# Yosys elaboration — sv2v-flatten first (Yosys rejects peakrdl's unpacked hwif structs)
mkdir -p ips/pmtpc4/dv/generated
sv2v -w ips/pmtpc4/dv/generated/pmtpc4_yosys_flat.v \
  $(grep -v '^[[:space:]]*//' ips/pmtpc4/dv/filelist.f)
yosys -p "read_verilog -sv ips/pmtpc4/dv/generated/pmtpc4_yosys_flat.v; hierarchy -top pmtpc4 -check"
```

### C2. UVM smoke test on xsim (compile → elaborate → run)
```bash
source /tools/Xilinx/2025.1/Vivado/settings64.sh
bash flow/scripts/xsim_flow.sh smoke ips/pmtpc4 pmtpc4_sanity_test
```
Expect the UVM report summary with `UVM_ERROR : 0`, `UVM_FATAL : 0`, and `checks=… errors=0`. Under
the hood this runs:
```bash
xvlog -sv -L uvm -f ips/pmtpc4/dv/sv/filelist.f
xelab -L uvm -timescale 1ns/1ps -relax pmtpc4_tb_top -s pmtpc4_sim
xsim pmtpc4_sim -R -testplusarg "UVM_TESTNAME=pmtpc4_sanity_test" -sv_seed 1
```

### C3. Seeded regression + coverage
```bash
python3 flow/scripts/run_regression.py ips/pmtpc4            # all tests × N seeds (from ip_config), + coverage
python3 flow/scripts/run_regression.py ips/pmtpc4 --seeds 25 # override seed count
python3 flow/scripts/run_regression.py ips/pmtpc4 --no-cov   # faster, skip coverage
```
Per-run logs land in `ips/pmtpc4/reports/_runs/seed_<N>/`, a summary in `reports/regression.txt`, and
merged functional + code coverage under `reports/_cov/_merged/` (see the **regression-runner** skill).

### C4. Test plan (Excel) + coverage closure
```bash
# render the traditional test plan (test cases / checkers / coverage points / REQ traceability)
python3 flow/scripts/gen_testplan.py ips/pmtpc4    # -> ips/pmtpc4/vplan/pmtpc4_testplan.xlsx
```
Coverage is scored on the DUT via the waiver file `ips/pmtpc4/dv/pmtpc4_cov_exclusions.txt`
(xsim `-ccExclusionFile`), applied automatically by `run_regression.py` (writes
`reports/_cov/{functional_report,code_report}/`).
```
/vlsi-close-coverage pmtpc4
```
Drives the closure loop (regress → merge → triage → add stimulus/waive) to the `coverage_goal_pct` in
`ip_config.yaml`, producing `ips/pmtpc4/reports/coverage_summary.md` with per-vPlan and per-REQ
roll-ups. Report the real number; a green run needs pass/fail *and* coverage both met.

### C5. Formal (optional)
```bash
cd ips/pmtpc4/formal && sby -f pmtpc4_channel.sby   # needs sby + an SMT solver (z3/boolector/yices)
```

---

## Notes

- Re-`source /tools/Xilinx/.../settings64.sh` and `source env/.venv/bin/activate` in every new shell
  (or add both to `~/.bashrc`). The flow scripts also source `$VIVADO_SETTINGS` if xsim isn't on PATH.
- Regenerate registers after any `.rdl` edit:
  ```bash
  cd ips/pmtpc4/rdl
  peakrdl regblock pmtpc4.rdl -o generated/rtl --cpuif passthrough \
    --module-name pmtpc4_regblock --package-name pmtpc4_regblock_pkg --hwif-report
  peakrdl uvm   pmtpc4.rdl -o generated/pmtpc4_ral_pkg.sv
  peakrdl html  pmtpc4.rdl -o generated/html
  ```
- A failing gate blocks the next stage — report the actual tool output, never paper over it
  (per [`CLAUDE.md`](CLAUDE.md)).
- **Known xsim specifics** (see the project memory / `env/README.md`): filelists use `-i` not
  `+incdir+`; the RAL block class name collides with the DUT module (alias it, construct with `new`);
  white-box SVA must bind to the registered signal, not a combinational output alias.
