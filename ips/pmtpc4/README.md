# PMTPC-4 — Programmable Multi-Channel Timer/PWM Controller

Built end-to-end by the front-end flow from the three PMTPC-4 specification documents
(Requirements + Design Rev 1.1 + Register Rev 1.1), all converted to Markdown under [`spec/`](spec/).

APB slave, 4 independent timer/PWM channels (down-counter, one-shot/periodic, PWM, pause/resume,
soft-disable), shared 16-bit prescaler, per-channel raw+masked interrupts with global gating and an
aggregated IRQ, async + synchronous soft reset. Full behavior incl. the **five errata (§12.1–12.5)**.

This is the **reference IP** for the single-track SystemVerilog UVM + Vivado xsim framework: its full
UVM environment compiles, elaborates, and runs on xsim.

## Lifecycle status

| Stage | Artifact | State |
|---|---|---|
| Ingest | [`ip_config.yaml`](ip_config.yaml) (+provenance) | ✅ validates |
| Requirements | [`spec/requirements.md`](spec/requirements.md) | ✅ full REQ traceability |
| Design spec | [`spec/design_spec.md`](spec/design_spec.md) | ✅ microarchitecture + SPEC↔REQ |
| Registers | [`rdl/pmtpc4.rdl`](rdl/pmtpc4.rdl) → [`rdl/generated/`](rdl/generated/) | ✅ PeakRDL: regblock RTL, UVM RAL, HTML, C header |
| RTL | [`rtl/`](rtl/) (apb_slave, prescaler, channel, top) | ✅ authored, synthesizable; **4 design bugs fixed** (see below) |
| vPlan | [`vplan/vplan.yaml`](vplan/vplan.yaml) | ✅ every REQ traced |
| Env (SV/UVM) | [`dv/sv/`](dv/sv/) | ✅ **runs on xsim** — all 5 tests green (UVM_ERROR 0, 0 SVA fails, scoreboard errors 0) |
| Static gate | Verible lint + sv2v + Yosys elaboration | ✅ clean |
| Seeded regression | [`reports/regression.txt`](reports/) | ✅ **125/125 runs** (5 tests × 25 seeds), 0 failures |
| Coverage | [`reports/coverage_summary.md`](reports/coverage_summary.md) | ✅ **functional 100% net of 1 waiver**; code statement 99% (branch/cond/toggle partial — structural, see report) |

### Running it (xsim)

```bash
source /tools/Xilinx/2025.1/Vivado/settings64.sh
bash flow/scripts/xsim_flow.sh smoke ips/pmtpc4 pmtpc4_sanity_test   # compile+elab+run one test
python3 flow/scripts/run_regression.py ips/pmtpc4                    # all tests × N seeds + coverage
```
See [`dv/README.md`](dv/README.md) for the environment structure and [`../../commands.md`](../../commands.md)
Part C for the full command sequence.

### Regression status

All 5 tests pass; the full seeded regression is **125/125 (5 tests × 25 seeds), 0 failures**. The
findings surfaced during bring-up were all testbench/methodology issues (SVA preponed-X sampling, the
built-in bit-bash vs RO-write PSLVERR, a scoreboard mask, a racy freeze check) — the RTL is
spec-correct. Details in [`dv/README.md`](dv/README.md). Functional + code coverage is collected;
reaching 100% coverage *closure* is the ongoing coverage-closure loop.

## Design bugs fixed (retained in the RTL)

Found and fixed while bringing this IP through verification; the fixes are present in `rtl/`/`rdl/` and
should be re-confirmed by `design-reviewer` before sign-off:

1. **`pmtpc4_apb_slave.sv` — PREADY was one cycle late.** ACCESS phase decoded from a *registered* FSM
   state inserted a wait state on every transfer (two on a CHx_COUNT read). Violated REQ-APB-2/3 and
   errata 12.4. Phase decode is now combinational on PSEL/PENABLE.
2. **`pmtpc4_channel.sv` — periodic reload skipped the LOAD state.** EXPIRED went straight to RUNNING,
   contradicting Design §7.3 and making the first period one tick longer. Now EXPIRED → LOAD
   (`pwm_level` extended to cover LOAD so the COMPARE=0 rule in §7.4 still holds).
3. **`pmtpc4.rdl` / `pmtpc4.sv` — SOFT_RESET did not clear INT_STATUS** (REQ-RST-2, Design §9).
   INT_STATUS now has `hwclr` from the soft-reset pulse, gated so a same-cycle expiry can't re-set it.
4. **`pmtpc4_channel.sv` — mid-RUNNING COMPARE writes applied immediately instead of at next LOAD**
   (Design §7.4). Added a `compare_shadow` register latched at the same points `count` loads from
   `period`.

## xsim bring-up fixes (SV/UVM env)

Surfaced when the SV/UVM env was first actually simulated on xsim (see the project's `xsim-uvm-gotchas`
memory): a reserved-keyword task named `expect` (renamed); the RAL top block class name colliding with
the DUT module `pmtpc4` (aliased via typedef; constructed with `new`, not `type_id::create`, since the
PeakRDL block isn't factory-registered); the filelist converted from `+incdir+` to xsim's `-i` form;
and a white-box channel SVA bound to the combinational `state_o` alias (which xsim samples as X in the
preponed region) retargeted to the registered `state`.

## Constrained-random

`method: constrained-random` vPlan items are realized with native SystemVerilog `rand`/`constraint`/
`dist` in the seq_item and sequences, seeded via `xsim -sv_seed` (see the `constrained-random` skill).

## Faithfulness note
The register map, FSMs, and all five errata are taken verbatim from the Design/Register Spec Rev 1.1.
The reference implementation in the source repo was **not** consulted — the RTL and testbenches here
are generated fresh by the flow.
