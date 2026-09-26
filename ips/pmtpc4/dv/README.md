# PMTPC-4 verification

One environment: standard **SystemVerilog UVM** (`sv/`), derived from the
[ip_config](../ip_config.yaml) + [vPlan](../vplan/vplan.yaml), run on **AMD Vivado xsim**.

> ## Status
>
> | Item | State |
> |---|---|
> | Static gate (Verible + xsim elaboration + Vivado synthesis — `reports/static_gate.txt`) | ✅ PASS |
> | SV/UVM compile + elaborate on xsim (`-L uvm`) | ✅ clean |
> | All 5 tests (sanity/reg/channel/irq/error) | ✅ green — UVM_ERROR 0, UVM_FATAL 0, 0 SVA fails, scoreboard errors 0 |
> | Seeded regression | ✅ **125/125 runs** (5 tests × 25 seeds), 0 failures |
> | Functional + code coverage | ✅ collected per run; per-test functional reports under `reports/_cov/<test>_report/`. 100% closure = ongoing loop (see below) |

## Architecture (`sv/`)
```
vip/apb/sv/    reusable APB UVC (if, agent, driver/monitor/seqr, coverage, reg adapter, seq lib,
               apb_fsm_cov = clock-sampled IDLE/SETUP/ACCESS phase coverage)
vip/pwm/sv/    reusable PASSIVE PWM-output UVC (pwm_if, pwm_item, monitor, agent)
vip/common/sv/ reset_if — reset generation/observation interface (mid-simulation reset control)
sv/env/        env_cfg, scoreboard (reference model), coverage, pwm coverage, vseqr, env,
               RAL predictor wiring
sv/seq/        base_vseq + smoke/reg/channel/irq/error virtual sequences
sv/test/       base_test + reg/sanity/channel/irq/error tests (one per file)
sv/sva/        bound assertions + white-box FSM coverage (apb / top / channel)
sv/tb/         tb_top (DUT + IFs + SVA binds + run_test)
sv/filelist.f  xsim compile list (`-i` include dirs, `#` comments; UVM via -L uvm)
```
Checking is split by strength: **scoreboard** = register/protocol transactions; **SVA** = cycle rules
(APB handshake, PWM waveform, IRQ aggregation, MODULE_EN freeze, reset).

## Test-writer hooks (infrastructure + the tests that now use it)

These three hooks were added 2026-09-18 for `VP-RST-ASYNC`, `VP-APB-FSM-B2B` and `VP-PWM-BLACKBOX`,
and (same day) actually exercised by dedicated tests — see the table for which.

| Hook | Call it as | For | Used by |
|---|---|---|---|---|
| Mid-simulation async reset | `async_reset(cycles, async_delay)` in any vseq (also `reset_assert()` / `reset_release()`) | `VP-RST-ASYNC` | `pmtpc4_async_reset_test` |
| APB back-to-back (PSEL held across ACCESS→SETUP) | `set_b2b(1)` then `raw_b2b(wr, addr, data, items)`, or drive `apb_b2b_seq` directly | `VP-APB-FSM-B2B` | `pmtpc4_apb_b2b_test` |
| Black-box `pwm_out` observation | subscribe to `env.pwm_agt.mon.ap` (`pwm_item` stream) | `VP-PWM-BLACKBOX` | `pmtpc4_pwm_blackbox_checker` (env, always active) / `pmtpc4_pwm_all_channels_test` |

- `async_reset()` pulses PRESETn low for `cycles` clocks at any point in a running simulation and then
  **re-syncs the environment**: `ral.reset()` (RAL mirror → reset values) and
  `pmtpc4_scoreboard::handle_reset()` (readback shadow dropped; every register resets to 0 per
  `pmtpc4.rdl`). Pass a non-zero `async_delay` to assert reset **off** the clock edge — that is what
  makes the assertion genuinely asynchronous and lets it land inside an APB SETUP/ACCESS phase. The
  APB driver and monitor abort an in-flight transfer on reset rather than hanging on a PREADY that
  will never arrive (the driver flags the item `aborted`; the monitor drops the torn transfer so it
  never reaches the scoreboard or the RAL predictor). `pmtpc4_async_reset_vseq` pulses from RUNNING,
  PAUSED, EXPIRED and mid-APB-ACCESS.
- Back-to-back is **opt-in twice over**: `apb_agent_cfg.b2b_enable` (default 0) and
  `apb_item.back_to_back` (default 0, soft-constrained to 0). With the defaults the driver's bus
  behaviour is byte-identical to before the knob existed. `back_to_back = 1` is a *promise* that
  another item follows immediately — `apb_b2b_seq` sets it on every item except the last. Consequence:
  a chained item's `rdata`/`slverr`/`waits` land ~1 clock after `finish_item()` returns, so read them
  only once the burst has finished. `pmtpc4_apb_b2b_vseq` drives a 5-item mixed read/write burst.
- The PWM UVC is passive by construction (`pwm` is an interface *input* port). `pmtpc4_pwm_coverage`
  subscribes to the analysis port and implements `cg_pwm_out` (observation only). The **checker**
  named by VP-PWM-BLACKBOX, `pmtpc4_pwm_blackbox_checker`, attaches to the same port plus the RAL
  mirror (never a DUT-internal signal) and checks the GATING invariant only (MODULE_EN/PWM_EN/CH_EN
  force-low) — honestly NOT the exact duty value or the COMPARE≥PERIOD case, both of which need
  internal/deferred-timing knowledge this checker deliberately doesn't have; see VP-PWM-BLACKBOX's
  gap note in `vplan.yaml` for the full boundary.

## 1. Toolchain (once)
```bash
bash env/bootstrap-wsl2.sh                             # helper tools + PeakRDL venv
# then install Vivado xsim (free ML Standard) — see ../../../env/README.md
source /tools/Xilinx/2025.1/Vivado/settings64.sh
```

## 2. Static gate (Vivado-only: lint + elaboration + synthesizability)

Run from the repo root. The DUT files are the RTL entries of [`sv/filelist.f`](sv/filelist.f) (the
same list simulation compiles), so there is no second list to keep in sync.

```bash
python3 flow/scripts/static_gate.py ips/pmtpc4    # -> reports/static_gate.txt
```
Verible lint (hand-written RTL) → xsim `xvlog`/`xelab` of the DUT alone → Vivado `synth_design`
(out-of-context): latches, multi-driven/undriven nets, port-width mismatches, loops. Deny-by-default.
The only informational note on pmtpc4 worth knowing: `pmtpc4_prescaler.soft_reset` has no load —
intentional since the F5 fix (soft reset must not disturb the prescaler; see the module header).

## 3. UVM simulation on xsim

```bash
source /tools/Xilinx/2025.1/Vivado/settings64.sh

# one test end-to-end (compile + elaborate + run)
bash flow/scripts/xsim_flow.sh smoke ips/pmtpc4 pmtpc4_sanity_test

# one test with a waveform (Vivado .wdb), then open it in the Vivado wave viewer
bash flow/scripts/xsim_flow.sh wave ips/pmtpc4 pmtpc4_pwm_duty_test 1
xsim --gui ips/pmtpc4/reports/waves/pmtpc4_pwm_duty_test_seed1.wdb

# full seeded regression (all tests × N seeds from ip_config) + functional/code coverage
python3 flow/scripts/run_regression.py ips/pmtpc4
```
Under the hood: `xvlog -sv -L uvm -f sv/filelist.f` → `xelab -L uvm -timescale 1ns/1ps -cov ...` →
`xsim <snap> -R -testplusarg UVM_TESTNAME=<test> -sv_seed <N>`. See the `regression-runner` skill.

## xsim-specific gotchas (baked into this env)

- **filelist** uses `-i <dir>` for includes (not `+incdir+`) and `#` comments.
- **RAL block name collides with the DUT module** `pmtpc4`: the env aliases it
  (`typedef pmtpc4_ral_pkg::pmtpc4 pmtpc4_reg_block_t;`) and constructs it with `new("ral")` — the
  PeakRDL block is not factory-registered, so `type_id::create` doesn't apply.
- **White-box SVA binds to the registered FSM reg, not the combinational output alias** (`.state_o(state)`
  in `tb/pmtpc4_tb_top.sv`): xsim samples a continuous-assign net as X in the preponed region, which
  otherwise fires the valid-state assertion every clock even though the settled value is correct.
- `expect` is a reserved SV keyword — the error vseq's helper is named `chk`.

## Findings resolved during bring-up (all testbench/methodology — RTL is spec-correct)

- **`a_pwm_rule` fired every cycle** — xsim samples bound-module *output ports/nets* as X in the
  preponed region. Fixed by rebuilding the expected PWM as an active-region register (`pwm_exp`)
  mirroring the RTL (`pwm_q <= pwm_level`, shadowed COMPARE, non-IDLE state) and binding `pwm` to the
  internal `pwm_q`; `state_o` is likewise bound to the internal `state` reg.
- **`reg_test` 250 errors** — `uvm_reg_bit_bash_seq` writes RO registers expecting OKAY, but this
  design PSLVERRs on RO writes (per spec). `reg_vseq` now excludes fully-RO registers via
  `NO_REG_BIT_BASH_TEST` (their RO policy is covered by the reset + error sequences). *(A real bug in
  that exclusion loop was also fixed: `get_fields()` appends, so the queue must be `.delete()`d each
  iteration.)*
- **Scoreboard `@0x20` mismatch** — CH_CTRL readback mask treated `CH_EN` as static, but it's
  hardware-cleared on one-shot expiry. Dropped `CH_EN` from the static mask (0x17→0x16).
- **`freeze_vseq` COUNT check** — was racy (compared count read *before* MODULE_EN=0 to *after*);
  replaced with a post-freeze stability + non-zero check.

## Coverage — open [`../reports/coverage_dashboard.html`](../reports/coverage_dashboard.html)

Every current number is on that one page (written by `run_regression.py`): regression, static gate,
functional per covergroup, statement/branch/condition per file, bit-weighted code toggle, register-bit
toggle, each linked to its xcrg detail report. Per-requirement roll-up:
[`../reports/coverage_summary.md`](../reports/coverage_summary.md); every waiver and known hole with its
justification: [`../reports/coverage_waivers.md`](../reports/coverage_waivers.md). This file does not
repeat the numbers, so it cannot go stale.

Coverage is measured from `pmtpc4_full_test` (all vseqs in one simulation — reliable, since xcrg
cross-db merge is broken on xsim 2025.1 and xsim overwrites the shared db per run); code toggle comes
from a separate toggle-only snapshot of the same test and seed.

**xcrg notes (xsim 2025.1):** point `-cov_db_dir` at the *parent* dir, **pre-create the `-report_dir`**
(xcrg won't create the code-cov report dir itself), run from a writable cwd.

## Coverage closure
Regression logs land in [`../reports/_runs/`](../reports/) and merged coverage under
`../reports/_cov/_merged/`; the closure summary (per-vPlan / per-REQ roll-ups, waivers, per-seed log)
is written to `../reports/coverage_summary.md` by the coverage-closure loop.
