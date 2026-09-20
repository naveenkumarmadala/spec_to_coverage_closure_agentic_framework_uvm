# flow/templates/ — env generation templates (hybrid model)

The UVM env is generated **hybrid**: templates own the *mechanical* layer (deterministic, identical
shape per IP, and the place the xsim/UVM gotchas are baked in once); the **agent** authors the
*semantic* layer (reference-model scoreboard, covergroup bins, SVA properties, sequences) into the
`AGENT:`-marked regions the templates leave. The reusable bus UVC lives in `vip/<bus>/sv/`, not here.
See the `uvm-env-scaffold` skill for the full split and contract.

Rendered against `ip_config.yaml` + `vplan.yaml` + the generated RAL.

## Templates (mechanical layer — gotcha-safe skeletons)

- `tb_top.sv.j2` — clock/reset, DUT instance, `config_db` vif, `run_test`, and the **SVA bind
  pattern** (bind checkers to the *registered* signal, never a combinational alias — the xsim
  preponed-X gotcha).
- `full_test.sv.j2` — the standard `<ip>_full_test` that runs every vseq in one sim for union coverage.
- *(to add, same pattern)* `filelist.f.j2` (xsim `-i` form), `pkg.sv.j2`, `base_test.sv.j2`,
  `env.sv.j2` (RAL typedef-alias + `new()` + predictor + scoreboard/coverage wiring), `agent_cfg.sv.j2`,
  `scoreboard.sv.j2` skeleton (analysis imp + shadow + per-register predict/check hooks).

## What is deliberately NOT templated (agent-authored)

The reference-model scoreboard body, coverage bins (from the vPlan), SVA properties, and the
directed/constrained-random sequences — these need design insight and are written by `tb-architect`
/ `test-writer` into the skeleton's `AGENT:` regions.

> A `gen_env.py` renderer that instantiates this template set for an IP is the remaining wiring; today
> `tb-architect` follows these templates + the `uvm-env-scaffold` contract when authoring the env.
