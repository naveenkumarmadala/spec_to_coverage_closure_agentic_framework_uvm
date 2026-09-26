---
name: vplan-schema
description: The schema and conventions for the verification plan (vplan.yaml) that maps requirements to coverage items and tests for the SystemVerilog UVM environment. Use when creating or updating a vPlan, or generating covergroups/tests from it.
---

# vPlan schema (`ips/<ip>/vplan/vplan.yaml`)

The vPlan is the machine-readable contract for "verified." The UVM environment generates coverage and
tests from it, and coverage closure rolls results back up to requirements through it.

## Structure

```yaml
ip: apb_gpio
coverage_goal_pct: 100
items:
  - id: VP-001
    feature: "All register fields readable/writable per access policy"
    traces_to: [REQ-010, REQ-011, REQ-012]      # MANDATORY — no orphan items
    method: register                             # directed | constrained-random | assertion | register | formal
    coverage:
      kind: ral                                  # ral | covergroup | code | assertion
      ral_sequences: [reset, bit_bash, access]   # standard RAL sequences
    tests: [reg_reset_test, reg_access_test]
    status: planned                              # planned | covered | closed | waived

  - id: VP-010
    feature: "GPIO interrupt-on-change for every pin, both edges"
    traces_to: [REQ-020, REQ-021]
    method: constrained-random
    coverage:
      kind: covergroup
      name: cg_gpio_intr
      coverpoints:
        pin:  { bins: "each of [0..31]" }
        edge: { bins: [rise, fall] }
      cross: [pin, edge]                         # 32 x 2 = 64 crosses to close
    tests: [gpio_intr_random_test, gpio_intr_directed_test]
    status: planned

  - id: VP-020
    feature: "APB error response on reserved address"
    traces_to: [REQ-030]
    method: directed
    coverage: { kind: assertion, name: a_pslverr_on_reserved }
    tests: [apb_error_test]
    status: planned

  - id: VP-030
    feature: "RTL code coverage of timer datapath"
    traces_to: [REQ-025]
    method: constrained-random
    coverage: { kind: code, targets: [statement, branch, toggle], scope: timer }
    tests: [timer_random_test]
    status: planned

  - id: VP-REG-TOGGLE          # standard for EVERY IP with a generated register block
    feature: "Every bit of every RAL field seen rising and falling in the DUT's bus read-back"
    traces_to: [REQ-012, REQ-025]
    method: directed
    coverage: { kind: reg_bit_toggle }     # measured by vip/common/sv/reg_bit_toggle_cov.svh
    tests: [<ip>_reg_toggle_test]
    status: planned
```

Coverage `kind`s: `covergroup` (bins/crosses), `ral` (built-in register sequences), `assertion`,
`code` (statement/branch/condition/toggle — toggle is read from the toggle build's
`reports/_cov/toggle_summary.txt`, over the hand-written RTL), and **`reg_bit_toggle`** (the
generated register block's per-field-bit rise/fall, from `reports/_cov/reg_bit_toggle.txt`; xsim
cannot measure that block's code toggle, so this item stands in for it).

## Rules

- **Every requirement appears in ≥1 `traces_to`.** A closure report flags any REQ with no vPlan item.
- **No orphan items:** every item's `traces_to` must reference real REQ/SPEC IDs.
- Bins must be **reachable and named** — avoid giant auto-bins that hide holes; avoid unreachable
  bins that inflate the denominator.
- `method` drives which stimulus the test-writer creates; `coverage.kind` drives what the tb-architect
  generates (RAL seq, covergroup, code-coverage target, or assertion).
- `status` is updated by coverage-closure: `covered` (bins hit) → `closed` (hit AND checks pass) or
  `waived` (with recorded justification).
- Realize each item as a concrete SystemVerilog covergroup/bin/cross or code-coverage target the
  UVM env and xsim can measure directly.
