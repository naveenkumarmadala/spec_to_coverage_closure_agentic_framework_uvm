# CLAUDE.md — Project guidance for the VLSI Front-End Agentic Framework

This file orients any Claude Code session working in this repo. Read it before acting.

## Mission

Drive the **front-end VLSI lifecycle** for any IP/subsystem using **free/free-to-use tools**,
from a **single input — a requirement specification document**:
Requirement spec → (extract) → Design Spec → Register Spec + Register Verification → RTL →
**SystemVerilog UVM verification** → **100% coverage closure**. No physical design. No paid
Cadence/Synopsys/Siemens licenses.

## What changed from the reference framework (read this)

This framework was forked from a **dual-track** design (SystemVerilog UVM *plus* a
pyuvm/cocotb Python twin) that leaned on Verilator and, when Verilator's UVM support fell short,
fell back to the Python track to carry coverage closure. **That dual-track is gone.** This is a
**single-track, standard SystemVerilog UVM** framework:

- **One verification methodology: standard SystemVerilog UVM** — `uvm_pkg`, factory, `config_db`,
  sequencer/driver/monitor, RAL, virtual sequences, covergroups, and SVA. Native
  `rand`/`constraint`/`dist`/`solve...before`/`randomize()` — a real constraint solver, not a
  Python re-implementation.
- **One simulator: AMD Vivado `xsim`** — the only free, local, headless simulator that runs
  *complete* UVM with native constrained randomization, functional + code coverage, and SVA.
  The static RTL gate is Vivado-only too (Verible lint + xsim elaboration + Vivado synthesis).
  cocotb, pyuvm, the `crv.py` helper, Verilator, Icarus, Yosys and sv2v are not used.

If you find any pyuvm/cocotb/`dv/py`/`crv.py` reference still in the repo, it is a leftover to
delete, not a track to maintain.

## Non-negotiable principles

0. **Spec-driven front door.** The flow starts from a requirement *document*, not a hand-filled
   config. The `spec-ingestor` extracts a draft `ip_config.yaml` + requirements, then **STOPS at a
   confirmation gate**. Never run design/RTL/verification on an auto-extracted config until the user
   has approved it (`provenance.needs_confirmation` lists what to confirm).
1. **Generic-first, protocol-agnostic.** Never hardcode an IP's or a protocol's details into agents,
   skills, templates, or VIP. Everything reads from the IP's
   [`ip_config.yaml`](flow/config/ip_config.example.yaml); protocols/interfaces resolve through the
   pluggable [`vip_registry.yaml`](flow/config/vip_registry.yaml). A new protocol = a registry entry +
   a VIP under `vip/`, never an agent/schema edit. If you're special-casing an IP or protocol, lift
   it into config, the registry, or a template parameter instead.
2. **One source of truth, one environment.** The SV/UVM env is generated from the
   `ip_config.yaml` + vPlan. There is no second track to keep in sync — build the UVM env once, and
   build it at full, closure-grade capability.
3. **Traceability is mandatory.** Every artifact carries a stable ID. Preserve the chain
   `REQ → SPEC → REG → RTL → VPLAN → COV`. IDs never get reused or silently renumbered.
4. **Quality gates are hard gates.** RTL and DV are agent-authored but only "accepted" after they
   pass, in order: **static gate (`flow/scripts/static_gate.py`: Verible lint + xsim elaboration +
   Vivado synthesis) → simulation (xsim) → coverage (xsim `-cov` + `xcrg`)**. A failing gate blocks the next stage;
   report the failure with the actual tool output, never paper over it.
   **Coverage is measured from two xsim snapshots of the same test and seed** (verified identical by
   `run_regression.py`): the normal one (tb top + `tb/<ip>_binds.sv`) for
   assertions, functional and statement/branch/condition; and the code-toggle one (tb top alone),
   because on xsim a bound checker or a `$dumpvars` in the design silently corrupts toggle recording
   (so there is no `$dumpvars` at all — waveforms come from `xsim_flow.sh wave`, a Vivado `.wdb`).
   The generated register block's toggle, which xsim cannot measure, is measured by the reusable
   `reg_bit_toggle_cov` + `<ip>_reg_toggle_test`. Every result is on one page,
   `reports/coverage_dashboard.html` (written by `run_regression.py`). Quote toggle from it or from
   `reports/_cov/toggle_summary.txt`
   and `reg_bit_toggle.txt`, never from the xcrg dashboard (it counts the UVM library file at 0%).
5. **Everything runs on the free toolchain in WSL2.** The UVM simulator is **Vivado xsim** (free
   ML Standard Edition, installed for Linux inside WSL2). If a construct isn't supported by xsim,
   fix the construct or record a justified, visible gap — never silently drop a check and never
   require a paid simulator. Do not reintroduce a Python verification track to work around a tool gap.

## Toolchain (invoked from WSL2 Ubuntu)

`peakrdl` (registers/RAL/docs), **Vivado `xvlog`/`xelab`/`xsim`/`xcrg`** (compile/elaborate/run/
coverage — the UVM sign-off simulator), **Vivado `synth_design`** (synthesizability, in the static
gate), `verible-verilog-{lint,format,syntax}` (lint).
Pinned in [`env/tool-versions.yaml`](env/tool-versions.yaml); installed by
[`env/bootstrap-wsl2.sh`](env/bootstrap-wsl2.sh). **Vivado is a manual install** (see
[`env/README.md`](env/README.md)); the bootstrap installs everything else.

## How the pieces fit

- **Agents** ([`.claude/agents/`](.claude/agents/)) — one specialist per lifecycle stage, plus an
  `orchestrator` that sequences them. Each agent's frontmatter says when to use it and which tools
  it may touch.
- **Skills** ([`.claude/skills/`](.claude/skills/)) — reusable, IP-agnostic know-how (spec
  extraction, VIP registry, SystemRDL authoring, UVM scaffolding, vPlan schema, constrained-random
  methodology, coverage triage, regression running). Agents invoke skills; skills contain the
  durable methodology.
- **Commands** ([`.claude/commands/`](.claude/commands/)) — user-facing `/vlsi-*` entry points.
  `/vlsi-ingest <spec>` is the front door; `/vlsi-flow` runs the whole lifecycle.
- **VIP registry** ([`flow/config/vip_registry.yaml`](flow/config/vip_registry.yaml)) — the authority
  for which bus/interface protocols exist and where their (SystemVerilog UVC) VIP lives. Add a
  protocol here, never in an agent.
- **Engine** ([`flow/`](flow/)) — schema, validator, jinja templates, and the xsim flow-runner
  scripts that turn config into concrete files and drive the tools.

## Working conventions

- **Your IPs** live under `ips/<ip_name>/`; the config template is
  `flow/config/ip_config.example.yaml`. Each IP dir has `spec/ rdl/ rtl/ dv/ vplan/ reports/`.
- The UVM environment lives in `ips/<ip>/dv/sv/`; the reusable protocol UVCs live in `vip/<bus>/sv/`.
  There is no `dv/py`.
- Generated files go in a `generated/` subdir and are git-ignored until explicitly promoted.
- Prefer editing templates in `flow/templates/` over editing generated output by hand.
- When authoring RTL, match the surrounding style and keep it synthesizable (the static gate's Vivado synthesis must pass).
- Report tool results faithfully. If coverage is 87%, say 87% and show the holes — do not claim closure.
- Files run in WSL2/Docker (Linux). `.gitattributes` forces LF on tool-consumed files — keep it that way.

## Current status

**Migration in progress:** forked from the dual-track reference and being converted to single-track
SystemVerilog UVM on Vivado xsim. The agentic layer (agents/skills/commands/config) is being purged
of the pyuvm/cocotb track; the xsim flow-runner scripts and the `pmtpc4` proof-of-life run are the
active work. Check [docs/architecture.md](docs/architecture.md) and the git log for the phase you're
picking up. Vivado xsim must be installed in WSL2 before simulation/coverage can actually run.
