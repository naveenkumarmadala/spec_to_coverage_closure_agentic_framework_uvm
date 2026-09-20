---
name: constrained-random
description: How to implement every vplan.yaml item tagged method:constrained-random with native SystemVerilog constrained randomization (rand/constraint/dist/solve-before) in the UVM sequence_item and sequence classes, seeded and reproducible on Vivado xsim. Use whenever test-writer authors a constrained-random test, or when setting up an IP's multi-seed regression.
---

# Constrained-random verification with native SystemVerilog

xsim has a **real constraint solver**, so constrained-random is done the standard UVM way — no
software re-implementation, no helper library that hand-picks value lists. This skill is the
methodology; the mechanism is `rand` + `constraint` + `dist` + `randomize()` in the transaction
and sequence classes.

## The mechanism

- **`rand` fields** on the `seq_item` (address, data, delays, control) and on sequences (counts,
  modes). Use `randc` for cycle-through where it matters (note: xsim treats `randc` wider than 8
  bits as `rand` — keep `randc` fields narrow).
- **`constraint` blocks** encode the legal/interesting space: valid address ranges, alignment,
  weighted corners via `dist` (`addr dist {0:=1, [1:MAX-1]:/8, MAX:=1}`), and relationships
  (`solve a before b` when one field biases another).
- **`randomize()` with inline `with {}`** in the sequence body to bias a specific scenario without
  editing the item's base constraints. Always check the return: `if(!item.randomize() with {...})
  \`uvm_fatal(...)`.
- **Reproducibility** rides on the UVM seed: `xsim -sv_seed <N>` (set once per iteration by
  `flow/scripts/run_regression.py`). The same seed reproduces the same stimulus. Do not invent a
  separate seeding mechanism.

## Method

1. **Derive the legal space from the IP, not from memory.** Valid addresses/offsets come from the
   generated RAL / the RDL register map (see `systemrdl-authoring`), referenced in constraints —
   never a hand-typed address list copied into a test. If the register map changes, the constraint
   space changes with it.
2. **One seeded test per `method: constrained-random` vPlan item, not one for the whole IP.** A
   shared grab-bag test measures "did anything happen"; a per-item test with `randomize() with {}`
   biased to that item's corners measures whether *that* requirement's random space was exercised —
   traceable, and far more likely to hit the scenario the vPlan item names.
3. **Bias toward the requirement's actual edge cases.** Read the vPlan item's `feature` text and the
   requirement it traces to before writing the `dist`/`with` weights — a prescaler item weights
   0/1/mid/max divide ratios; an FSM item weights the transitions the transition table calls out.
   Generic 0/1/max/uniform coverage is the floor, not the whole job.
4. **Every transaction still goes through the normal driver and reference-model check.** CRV changes
   what stimulus is created; it must never bypass or weaken the per-cycle checking every other test
   gets (see `verification-review`'s vacuity checks).
5. **Functional coverage measures what random hit** — never sample coverage from the sequence/test;
   the monitor/scoreboard samples from a signal it just checked (see `test-writer`).

## Example shape

```systemverilog
class apb_item extends uvm_sequence_item;
  rand bit [ADDR_W-1:0] addr;
  rand bit [DATA_W-1:0] data;
  rand int unsigned     idle_delay;
  constraint c_align   { addr[1:0] == 2'b00; }
  constraint c_delay   { idle_delay dist {0:=5, [1:3]:/3, [4:15]:=1}; }
  `uvm_object_utils(apb_item)
endclass

// per-item bias in the sequence, not in the item's base constraints:
if (!req.randomize() with { addr inside {[PRESCALER_LO:PRESCALER_HI]};
                            data dist {0:=1, 16'hFFFF:=1, [1:16'hFFFE]:/6}; })
  `uvm_fatal("RAND", "prescaler CRV randomize failed")
```

## Rules

- Encode value distributions as `constraint`/`dist`, not as procedural `$urandom` value-picking in
  the test — the solver, seed, and coverage then all line up, and a constraint fixed once applies
  everywhere the item is used.
- A `method: constrained-random` vPlan item with no seeded test behind it (only directed tests, or
  riding on an unrelated grab-bag test) is a finding for `verification-reviewer` to raise.
- Measure whether multiple seeds actually earn their keep (compare one seed's coverage to the full
  merge) rather than assuming more seeds always help — report what the data says, even if it's "no
  incremental gain," per this project's standing rule against overclaiming.
