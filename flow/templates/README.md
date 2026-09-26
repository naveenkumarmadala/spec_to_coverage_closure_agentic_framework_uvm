# flow/templates/ — env generation templates (hybrid model)

The UVM env is generated **hybrid**: templates own the *mechanical* layer (deterministic, identical
shape per IP, and the place the xsim/UVM gotchas are baked in once); the **agent** authors the
*semantic* layer (reference-model scoreboard, covergroup bins, SVA properties, sequences) into the
`AGENT:`-marked regions the templates leave. The reusable bus UVC lives in `vip/<bus>/sv/`, not here.
See the `uvm-env-scaffold` skill for the full split and contract.

Rendered against `ip_config.yaml` + `vplan.yaml` + the generated RAL.

## Templates (mechanical layer — gotcha-safe skeletons)

- `tb_top.sv.j2` — clock/reset, DUT instance, `config_db` vif, `run_test`. **No binds and no
  `$dumpvars` in it** (both corrupt xsim code-toggle recording); those are the two companion tops below.
- `binds.sv.j2` → `tb/<ip>_binds.sv` — module `<ip>_binds`, every white-box SVA/coverage `bind`
  (bind checkers to the *registered* signal, never a combinational alias — the xsim preponed-X gotcha).
- `dump.sv.j2` → `tb/<ip>_dump.sv` — module `<ip>_dump`, the `+DUMP` waveform dump.
  `xsim_flow.sh` elaborates both companion tops in the normal snapshot and leaves them out of the
  code-toggle snapshot (`--toggle`); `run_regression.py` refuses a toggle build whose tb top still
  contains a bind or a dump.
- `full_test.sv.j2` — the standard `<ip>_full_test` that runs every vseq in one sim for union
  coverage, ending with the register-toggle vseq.
- `reg_toggle_vseq.sv.j2` / `reg_toggle_test.sv.j2` — the standard register-block toggle closure
  (measured by the reusable `vip/common/sv/reg_bit_toggle_cov.svh`). Generic sections: bit-bash,
  singlepulse fields (from `<ip>_reg_toggle_cfg.svh`, generated from the RDL by
  `flow/scripts/gen_reg_toggle_cfg.py`), read-all; one `AGENT:` section for hardware-set fields.
- *(to add, same pattern)* `filelist.f.j2` (xsim `-i` form), `pkg.sv.j2`, `base_test.sv.j2`,
  `env.sv.j2` (RAL typedef-alias + `new()` + predictor + scoreboard/coverage wiring), `agent_cfg.sv.j2`,
  `scoreboard.sv.j2` skeleton (analysis imp + shadow + per-register predict/check hooks).

## What is deliberately NOT templated (agent-authored)

The reference-model scoreboard body, coverage bins (from the vPlan), SVA properties, and the
directed/constrained-random sequences — these need design insight and are written by `tb-architect`
/ `test-writer` into the skeleton's `AGENT:` regions.

> A `gen_env.py` renderer that instantiates this template set for an IP is the remaining wiring; today
> `tb-architect` follows these templates + the `uvm-env-scaffold` contract when authoring the env.
