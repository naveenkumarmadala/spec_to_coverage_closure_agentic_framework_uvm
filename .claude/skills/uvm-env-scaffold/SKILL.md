---
name: uvm-env-scaffold
description: The standard, industry-grade SystemVerilog UVM architecture to generate for any IP — a reusable protocol UVC, a layered env (RAL + reference-model scoreboard + functional coverage + virtual sequencer), a virtual-sequence library, a test library, and an SVA assertion layer — built to compile, elaborate, and run on Vivado xsim. Use when building or extending an IP's dv/ environment.
---

# Standard UVM environment architecture (generate this for every IP)

One environment: standard SystemVerilog UVM, run on xsim, built at full, closure-grade capability.
It derives from the IP's `ip_config` + vPlan and uses native `rand`/`constraint`/`dist`, covergroups,
and SVA. There is no second (Python) track.

## Hybrid generation: template the mechanical layer, author the semantic layer

Split the env by *kind of code*, because the two need opposite treatments:

| Layer | Owner | Files |
|---|---|---|
| **Mechanical / boilerplate** — *template it* (deterministic, gotcha-safe, identical shape per IP) | `flow/templates/*.j2` | `tb_top` (clock/reset/DUT/config_db/run_test + SVA-bind pattern), `filelist.f` (xsim `-i` form), `<ip>_pkg`, `base_test`, `env` wiring (agent + RAL alias + `new()` + predictor + scoreboard/coverage instantiation), `agent_cfg`, and the standard **`<ip>_full_test`** |
| **Reusable bus UVC** — *neither; build once* | `vip/<bus>/sv/` | driver/monitor/sequencer/seq_item/coverage/reg_adapter (selected via `vip_registry`) |
| **Semantic / design-specific** — *agent authors* into templated skeletons | agent (`tb-architect`/`test-writer`) | reference-model `scoreboard` body, `coverage` covergroup bins (from vPlan), `sva/` properties, `seq/` directed + constrained-random vseqs |

Why: the mechanical layer carries no design insight but *does* carry the xsim gotchas below — bake
them into templates once so IP #2..N never re-hit them. The semantic layer needs judgment (a
reference model / assertion can't be templated). The template emits compile-clean skeletons with
clearly-marked `AGENT:` regions and the exact port/analysis contract; the agent fills the bodies.

**Standard tests every IP gets** (templated): a smoke test, and **`<ip>_full_test`** that runs *every*
vseq in one simulation to produce the union coverage database (the reliable path on xsim — see
`regression-runner`). A **reference-model scoreboard skeleton** (analysis imp + shadow map + a
`predict()`/`check()` hook per register from the RAL) is scaffolded from the register map; the agent
fills the IP-specific prediction logic.

## Directory layout (one class per file)

```
vip/<bus>/sv/            REUSABLE UVC (build once, use for any IP on that bus)
   <bus>_if.sv  <bus>_seq_item.sv  <bus>_agent_cfg.sv  <bus>_driver.sv
   <bus>_monitor.sv  <bus>_coverage.sv  <bus>_reg_adapter.sv  <bus>_seq_lib.sv
   <bus>_agent.sv  <bus>_pkg.sv  <bus>.f
ips/<ip>/dv/sv/
   env/   <ip>_env_cfg.sv  <ip>_scoreboard.sv (reference model)  <ip>_coverage.sv
          <ip>_vseqr.sv (virtual sequencer)  <ip>_env.sv
   seq/   <ip>_base_vseq.sv + smoke/reg/<feature> virtual sequences
   test/  <ip>_base_test.sv + one file per test
   sva/   <ip>_<blk>_sva.sv  (bound assertion + white-box coverage modules)
   tb/    <ip>_tb_top.sv  (DUT + IF + run_test — NO binds, NO $dumpvars)
          <ip>_binds.sv   (module <ip>_binds: every white-box SVA/coverage bind — a separate top)
          <ip>_dump.sv    (module <ip>_dump: +DUMP waveform dump — a separate top)
   <ip>_test_pkg.sv   filelist.f
ips/<ip>/formal/         (optional) SymbiYosys harness(es) + .sby for control-logic proofs
```

## Component responsibilities (the "exact architecture")

- **tb_top** — clock/reset, DUT, interface(s), set vif in config_db, `run_test`. **The SVA binds and
  the waveform dump are NOT in tb_top** — each is its own top module (`tb/<ip>_binds.sv`,
  `tb/<ip>_dump.sv`) so the code-toggle snapshot can elaborate `tb_top` alone: on xsim a bound checker
  erases the toggles of the DUT nets it observes, and `$dumpvars` merely present in the design (even
  gated, never executed) stops toggle recording on others. `xsim_flow.sh` handles both snapshots.
- **Interface** — pin bundle + clocking blocks + modports (in the reusable UVC).
- **Reusable UVC** (`vip/<bus>/sv/`) — `seq_item` (with `rand` fields + `constraint`s), `driver`,
  `monitor`, `sequencer`, config-driven `agent` (active/passive, coverage on/off), `coverage`, and the
  **reg adapter**. Never re-implement a bus driver inside an IP.
- **RAL** — the PeakRDL-generated `uvm_reg_block`, wired via the adapter + an explicit
  `uvm_reg_predictor` (auto-predict off).
- **Reference-model scoreboard** — predicts and checks register readback + protocol (PSLVERR, wait
  states); cycle-accurate golden checks live in the SVA layer, not here.
- **Functional coverage** — register/config covergroups (transaction-based) + white-box FSM/waveform
  covergroups bound into the RTL (`sva/`). Plus the UVC's protocol coverage. Sampled by the
  monitor/scoreboard, never by tests.
- **Virtual sequencer + virtual sequences** — `base_vseq` with RAL + raw-bus helpers; concrete vseqs
  per feature (register built-ins, directed scenarios, error/corner, constrained-random).
- **Test library** — `base_test` builds env + configs; one test per file, each running vseq(s).
- **SVA layer** — bound modules asserting protocol timing, datapath/waveform rules, aggregation, and
  reset; carry white-box covergroups too.
- **Formal (optional)** — a SymbiYosys harness proving control-FSM safety. Free (Yosys); keep
  properties simple (open-source SVA support is partial).

## Standard register-verification suite (generate for EVERY IP — RAL/RDL-derived, not hand-coded)

Register checking is the first verification milestone and must be a standard, generic set — never
hand-listed addresses. **Each scenario is its own dedicated vseq AND its own dedicated, scenario-named
test — never bundled into one "reg_test"/"error_test".** The name states the scenario, so a regression
line or a coverage hole points straight at the failing policy:

| Scenario | Dedicated vseq | Dedicated test (name = scenario) | Mechanism |
|---|---|---|---|
| Reset / default values | `<ip>_reg_reset_vseq` | `<ip>_reg_reset_test` | `uvm_reg_hw_reset_seq` (RAL-driven; every field's reset value) |
| Read/write access policy | `<ip>_reg_rw_vseq` | `<ip>_reg_rw_test` | `uvm_reg_bit_bash_seq` (RAL-driven) |
| RO-write → PSLVERR | `<ip>_reg_ro_vseq` | `<ip>_reg_ro_test` | registers whose every field `get_access()=="RO"` |
| WO-read → PSLVERR | `<ip>_reg_wo_vseq` | `<ip>_reg_wo_test` | registers whose every field `get_access()=="WO"` |
| Reserved-offset → PSLVERR, PRDATA=0 | `<ip>_reg_reserved_vseq` | `<ip>_reg_reserved_test` | every aligned word in `[0, 2^addr_width)` no register occupies |
| Unaligned → PSLVERR | `<ip>_reg_unaligned_vseq` | `<ip>_reg_unaligned_test` | a valid base + {1,2,3} |
| W1C / special fields | `<ip>_reg_<field>_vseq` | per RDL `onwrite`/`hwset` | directed |
| **Register-bit toggle** (every field bit rise + fall) | `<ip>_reg_toggle_vseq` | `<ip>_reg_toggle_test` | bit-bash writable bits; pulse `singlepulse` fields; drive every hw-set RO bit both ways while reading it; measured by `reg_bit_toggle_cov` |

**Register-bit toggle coverage is part of every env.** xsim cannot measure a PeakRDL register block's
code toggle (nested-struct flops, unexcludable `automatic` temporaries), so the env instantiates the
reusable `reg_bit_toggle_cov` (`vip/common/sv/reg_bit_toggle_cov.svh`, `include`d in the test package)
when coverage is on, fills `pulse_suffixes` from the generated `<ip>_reg_toggle_cfg.svh`
(`env/.venv/bin/python3 flow/scripts/gen_reg_toggle_cfg.py ips/<ip>` — the RDL's `singlepulse`
fields), calls `attach(ral)` in `connect_phase` and `handle_reset()` from the env's reset hook. It hooks
every field's `post_predict`, so it credits only what the DUT returned on the bus (plus the accepted
write of 1 for a singlepulse field). The test's vseq also runs inside `<ip>_full_test`.

Rules that keep this generic:
- **Targets are DERIVED FROM THE RAL at runtime** — query `get_registers`, `get_address`,
  `get_fields`, `get_access`; build the reserved-offset set from `reg.get_address()`. Never hardcode
  RO/WO/reserved/unaligned address lists. Only the class name is IP-specific; the body is generic.
- For the RW (bit-bash) scenario, exclude fully-RO registers where the bus PSLVERRs on RO writes
  (set `NO_REG_BIT_BASH_TEST`). Remember `get_fields()` *appends* — use a fresh/`.delete()`d queue
  each register (a shared `all_fields_access(reg, "RO"/"WO")` helper in the base vseq does this).
- A scenario with **no targets in this IP** (e.g. an IP with no WO register) must **log a UVM_INFO
  that it is vacuously covered**, not silently pass with zero checks — the same generic test then does
  real work on the next IP that does have such registers.
- *(Back-door `uvm_reg_access_seq` requires an `hdl_path` back-door; enable it only when the regblock
  exposes one — otherwise front-door bit_bash + the per-scenario error tests fully cover access policy.)*
- The all-scenarios `<ip>_full_test` runs every register-scenario vseq too, so union coverage is
  unaffected by the split.

## Division of checking (play to each tool's strength)
- **Scoreboard** → register + protocol transaction correctness.
- **SVA** → cycle-accurate relationships (waveform rule, aggregation, handshake, set-priority).
- **Formal (optional)** → exhaustive corners on control logic.
- **Coverage** → reg fields + FSM states/transitions + scenario crosses, rolled up to the vPlan/REQ.

## Reusable-UVC correctness (bake into every bus driver)
- **A bus driver must NOT drive during reset — wait for reset deassertion before the first transfer.**
  `run_phase` should drive the idle/deasserted bus, then `wait (vif.<resetn> === 1'b1); @(vif.drv_cb);`
  before the get/drive loop. Skipping this races the first transaction against reset release: it is
  silently lost (e.g. a first register write reads back its reset value). It hides for a long time
  because it only bites when the *first* transaction targets a real writable register — a standalone
  `uvm_reg_bit_bash_seq` does exactly that, while functional vseqs whose first write is a 0→0 field mask
  it. (Found on APB during the register-test split; generic to every protocol UVC.)

## xsim compatibility (bake these in — confirmed on real bring-up)
- **filelist.f** uses `-i <dir>` for include dirs (NOT `+incdir+`) and `#` comments; UVM comes from
  `-L uvm` (built-in UVM 1.2), so `uvm_macros.svh` resolves with no extra incdir.
- **RAL block name** collides with the DUT top module when the RDL addrmap shares the IP name. Alias
  it (`typedef <ral_pkg>::<block> <ip>_reg_block_t;`) before `::type_id`, and construct the PeakRDL
  block with `new("ral")` — it is **not** factory-registered.
- **White-box SVA must bind to the registered signal, not a combinational output alias** (e.g. bind
  `.state_o(state)`, the FSM reg, not the `assign state_o = state` net): on xsim the preponed sample
  of a continuous-assign net reads X every clock and spuriously fires clocked assertions.
- Don't name a task/function `expect` (reserved SV keyword); `$past` in an assertion action needs an
  explicit clock argument.

## Rules
- Config objects everywhere (agent + env); factory + config_db, no hard-coded structure.
- Keep the reusable UVC generic in `vip/<bus>/sv/`; only IP glue (ref model, coverage, vseqs) in `dv/sv/`.
- Bring up the **smoke** vseq (reset + one register access) and confirm it compiles, elaborates, and
  runs clean on xsim before elaborating the full suite.
- Where xsim can't run a construct, rewrite it in a supported form and record the gap plainly — never
  reintroduce a Python track and never require a paid simulator.
