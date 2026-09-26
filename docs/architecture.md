# Architecture — VLSI Front-End Agentic Framework

## 1. Goal & scope

A multi-agent framework that carries **any IP or subsystem** through the **front-end** VLSI
lifecycle using **free/free-to-use tools**, from a single input — a requirement spec document:

```
Requirement Spec ─▶ (extract + confirm) ─▶ Design Spec ─┬─▶ Design Thread:   Register Spec ─▶ RTL ─▶ static gate ─▶ design review
                                                          └─▶ Verification Thread: vPlan ─▶ UVM env authoring
                                                                     (both run independently, converge at the simulation gate)
                                     ─▶ Register Verification (RAL) ─▶ Functional Verification ─▶ 100% Coverage Closure
```

The design thread and verification thread run independently once the design spec exists — vPlan
authoring only needs the register map, and env authoring doesn't need working RTL, only its
interface. They share nothing else until the simulation gate, where verification's stimulus first
runs against design's RTL. See §4 below for the agents on each thread and their independent
reviewers.

Out of scope: physical design, synthesis-for-production, timing signoff, and all commercial EDA
(Cadence/Synopsys/Siemens). Synthesizability is checked (Yosys) only as a *front-end* quality gate.

## 2. Design principles

0. **Spec-driven front door.** One input: a requirement specification document. The `spec-ingestor`
   extracts a draft `ip_config.yaml` + requirements and **stops at a confirmation gate**; nothing
   downstream runs until the user approves. Extracted assumptions are tracked in `provenance`.
1. **Config-driven genericity, protocol-agnostic.** All IP specifics live in one `ip_config.yaml`.
   Protocols/interfaces are **not** a fixed list — they resolve through a pluggable
   [`vip_registry.yaml`](../flow/config/vip_registry.yaml), so any protocol is added by registering a
   VIP, never by editing code. The schema is **subsystem-ready** (optional `subsystem` block) so
   multi-block integration verification slots in later without reworking single-IP configs.
2. **Single-track SystemVerilog UVM.** One verification environment — standard SV/UVM (`uvm_pkg`,
   RAL, covergroups, SVA, native `rand`/`constraint`) — generated from the config + vPlan and run on
   AMD Vivado xsim. (Forked from a former dual-track SV/UVM + pyuvm design; the Python track is retired.)
3. **Traceability spine.** Stable IDs thread `REQ → SPEC → REG → RTL → VP → COV`; closure is proven at
   the requirement level.
4. **Hard quality gates.** RTL is agent-authored but accepted only after lint → elaboration →
   simulation → coverage. Failures are reported with real tool output, never hidden.
5. **Free toolchain, honestly.** Everything runs on WSL2 with PeakRDL/Verible/Yosys and the UVM
   simulator **Vivado xsim** (free ML Standard). Verilator/Icarus are optional lint/elab helpers only.
   Where xsim can't run a construct, it's fixed or the gap recorded — never a fallback to a Python
   track or a paid simulator.

## 3. Toolchain

| Concern | Tool |
|---|---|
| Register source-of-truth → RTL/RAL/headers/docs | PeakRDL (SystemRDL 2.0) |
| Lint / format / parse | Verible |
| **SV/UVM simulation + coverage** | **AMD Vivado xsim** (`xvlog`/`xelab`/`xsim`/`xcrg`; free ML Standard) |
| Fast lint/elaboration helper (not UVM sign-off) | Verilator, Icarus Verilog |
| Synthesizability elaboration | Yosys (+ sv2v) |

Pinned in [`env/tool-versions.yaml`](../env/tool-versions.yaml).

### Coverage measurement (every IP)

| Metric | Measured on | Report |
|---|---|---|
| Functional, assertions, statement/branch/condition | normal snapshot `<ip>_sim` = `<ip>_tb_top` + `<ip>_binds` + `<ip>_dump` | `reports/_cov/functional_report/`, `code_report/` |
| Code toggle (hand-written RTL) | toggle snapshot `<ip>_tcov` = `<ip>_tb_top` alone (`xsim_flow.sh --toggle`) | `reports/_cov/toggle_summary.txt` (bit-weighted) |
| Generated register block toggle | `reg_bit_toggle_cov` (every RAL field bit rise+fall, as read back from the DUT) + `<ip>_reg_toggle_test` | `reports/_cov/reg_bit_toggle.txt` |

Why: on Vivado xsim a `bind`-ed checker erases the toggles of the DUT nets it observes and a
`$dumpvars` merely present in the design stops toggle recording on others, so binds and the dump live
in their own tops and toggle is measured without them. `run_regression.py` reruns the union test on the
toggle snapshot and requires identical execution (same scoreboard checks and register-bit totals); it
also regenerates the exclusion lists (`gen_exclusions.py`, which scopes the generated register block
out of the toggle report automatically) and the RDL-derived `singlepulse` list
(`gen_reg_toggle_cfg.py`), and refuses a toggle build whose tb top still contains a bind or a dump.

## 4. The multi-agent framework

### Agents (`.claude/agents/`)
`vlsi-orchestrator` sequences the specialists and enforces gates. Stage 0 (front door) and stages
1-2 (requirements/design spec) are shared; after that, the pipeline splits into two threads that run
independently and converge only at the simulation gate (see §1's diagram):

**Shared front door**

| Agent | Stage | Key output |
|---|---|---|
| `spec-ingestor` | **Ingest + confirm (front door)** | `ip_config.yaml` (+`provenance`), `spec/requirements.draft.md` |
| `requirements-analyst` | Requirements | `spec/requirements.md` (ID'd, testable) |
| `design-architect` | Design spec | `spec/design_spec.md` |

**Design thread** — RTL side; its reviewer never reads `dv/`

| Agent | Stage | Key output |
|---|---|---|
| `register-designer` | Registers | `rdl/*.rdl` → PeakRDL RTL/RAL/docs |
| `rtl-designer` | RTL | `rtl/*.sv` |
| `lint-static-checker` | Static gate | pass/fail + findings |
| `design-reviewer` | Independent design review | Spec-conformance findings + traceability tally |

**Verification thread** — DV side; its reviewer independently re-derives expected checker behavior
from spec before ever comparing it to the DV collateral or to `design-reviewer`'s findings

| Agent | Stage | Key output |
|---|---|---|
| `verification-planner` | vPlan | `vplan/vplan.yaml` |
| `tb-architect` | Env | SystemVerilog UVM env `dv/sv/` |
| `test-writer` | Register + functional tests | RAL seqs + directed/constrained-random sequences/tests |
| `coverage-closure` | Closure (needs the simulation gate: accepted RTL + built env) | `reports/coverage_summary.md` |
| `verification-reviewer` | Independent verification review | Vacuity/waiver findings + trustworthiness verdict |

`design-reviewer` and `verification-reviewer` are independent audits, not authors: they report
findings for a human (or the authoring agent) to act on, never silently fix what they review, and
never read the other thread's collateral or the other reviewer's conclusions before finishing their
own — the same discipline real signoff processes apply by requiring a *separate*, unbriefed reviewer.
`coverage-closure` is the one verification-thread stage allowed to edit RTL (a design-thread
artifact) when triage finds a bug — when it does, `design-reviewer` re-runs scoped to that diff
before the fix is trusted.

### Skills (`.claude/skills/`)
Durable, IP-agnostic methodology invoked by the agents: `spec-extraction`, `vip-registry`,
`ip-config`, `spec-to-requirements`, `systemrdl-authoring`, `vplan-schema`, `uvm-env-scaffold`,
`regression-runner`, `constrained-random`, `coverage-triage`, `design-review`, `verification-review`.

### Commands (`.claude/commands/`)
Front door + entry points: `/vlsi-ingest` (ingest a requirement doc), `/vlsi-new-ip` (manual config),
`/vlsi-spec`, `/vlsi-registers`, `/vlsi-rtl`, `/vlsi-build-env`, `/vlsi-verify`,
`/vlsi-close-coverage`, `/vlsi-review`, `/vlsi-flow`, `/vlsi-status`.

### Engine (`flow/`)
`config/` (schema + validator + **vip_registry**), `templates/` (jinja env generation — P3),
`scripts/` (runners), `tools/` (uniform CLI wrappers — P2).

## 5. Data flow & artifacts

```
requirement_spec.(md|pdf|docx)
        │  spec-ingestor (extract)
        ▼
ip_config.yaml + requirements.draft.md ──▶ [CONFIRMATION GATE: user approves] 
        │  (protocol/interface resolved via vip_registry.yaml)
        ▼
ip_config.yaml ─┬─▶ requirements.md ─▶ design_spec.md ─┬─▶ <ip>.rdl ─(PeakRDL)─┬─▶ regblock RTL ─┐
                │                                       │                      ├─▶ UVM RAL  ─────┤
                │                                       │                      └─▶ docs/headers  │
                │                                       └─────────────────────────────▶ rtl/*.sv ┤
                └─▶ vplan.yaml ◀── requirements + spec + rdl                                     │
                          │                                                                       ▼
                          └─▶ dv/sv (SystemVerilog UVM) ─▶ RAL verif ─▶ xsim regression ─▶ coverage_summary.md
```

## 6. Traceability model

Each stage emits IDs and references upstream IDs:
`REQ-NNN` (requirement) → `SPEC-NNN` (design item, `Satisfies: REQ-…`) → RDL field `desc` (cites
REQ/SPEC) → RTL `// impl SPEC-…` tags → `VP-NNN` (`traces_to: [REQ/SPEC…]`) → coverage bins carry
their `VP-` id. The closure report inverts this chain to prove every requirement is covered.

## 7. Phased roadmap & status

| Phase | Scope | Status |
|---|---|---|
| **P0** | Repo skeleton, WSL2 bootstrap, `ip_config` schema, agents/skills/commands | **Done** |
| **P0.1** | Alignment: spec-ingestion front door, pluggable VIP registry, subsystem-ready schema, `examples/` reframe | **Done** |
| P1 | Spec-doc ingestion (real parsing) → confirmed config; requirements DB + design spec | Next |
| P2 | SystemRDL + PeakRDL integration; RTL generation; static gate; `flow/tools` wrappers | |
| P3 | `flow/templates` env generation; first bus VIP (APB) in registry; SV/UVM smoke on xsim; RAL verif | |
| P4 | vPlan realization; directed + constrained-random tests | |
| P5 | Regression runner; coverage merge/report; closure loop to goal | |
| P6 | Prove protocol-agnosticism (AXI-Lite via registry) + subsystem hierarchy/integration verif | |

## 8. Example (not the product)

`examples/apb_gpio/` — an APB4 32-bit GPIO + timer peripheral used to prove the flow end-to-end.
Register-heavy on purpose: it exercises the full SystemRDL → PeakRDL → RAL → register-coverage path,
the highest-value part of the flow. It is a demo; the framework itself is IP/protocol-agnostic. Real
IPs live under `ips/` and are onboarded from a requirement document via `/vlsi-ingest`.

## 9. Subsystem support (design-now, build-later)

The schema carries an **optional `subsystem` block** (child blocks + interconnect + address map) so a
subsystem is expressed as a composition of IP configs. Single-IP configs omit it and are unaffected.
Integration-level verification (fabric checks, cross-block scenarios, system RAL) is a **P6** build;
the hooks exist now so nothing needs reworking when it lands.

## 10. Known risks & mitigations

- **Open-source UVM simulator gap** → resolved by adopting Vivado xsim (free ML Standard), the only
  free/local/headless simulator that runs complete UVM; Verilator's incomplete UVM support is why it's
  a lint/elab helper here, not the sign-off sim. Its one gap (no assertion-coverage report) is handled
  by routing assertion evidence through the scoreboard + SVA `cover`.
- **LLM-authored RTL quality** → hard gates (lint/elaborate/sim/coverage) + human PR review; RTL is
  never "done" on assertion, only on green gates.
- **Extraction errors** → the ingestion confirmation gate + `provenance.needs_confirmation` force
  human review of every assumption before effort is spent downstream.
- **Windows tooling** → all sims run in WSL2/Docker; the repo is edited on Windows, executed in Linux.
- **Coverage gaming** → closure requires bins hit *and* checks passing *and* requirement roll-up;
  waivers require recorded justification. **Confirmed in practice, not just a theoretical risk**: a
  real IP's first-generation environment reached 100% via bins sampled directly by test code, checking
  nothing. `verification-reviewer` exists specifically to catch this class of gap, including via
  deliberate mutation/bug-seeding spot-checks that prove a checker can actually fail.
- **LLM-authored RTL that looks right but implements the wrong thing** → lint/elaboration/simulation
  passing is not proof of spec conformance; a protocol-timing bug, a skipped FSM state, and a missing
  hardware-clear condition all shipped past those gates on a real IP before `design-reviewer`'s
  independent, spec-literal re-derivation existed. Static analysis alone (lint/elaborate) cannot catch
  every such bug — dynamic verification (simulation, the mutation spot-check above) is still required.
