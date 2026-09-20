# PMTPC4 — Coverage Summary (generated)

- **Seeded regression:** pmtpc4 regression — 40/40 runs passed
- **Functional coverage (union):** 99.7%  (goal 100%)
- **DUT code coverage:** stmt 99.9% / branch 98.1% / cond 100.0% / toggle 46.0%

## Per-vPlan item

| VP-ID | Method | Requirement(s) | Status |
|---|---|---|---|
| VP-REG-RESET | register | REQ-RST-1 | covered |
| VP-REG-ACCESS | register | REQ-APB-1, REQ-APB-2 | covered |
| VP-APB-XFER | constrained-random | REQ-APB-1 | covered |
| VP-APB-FSM-B2B | constrained-random | REQ-APB-1 | covered |
| VP-APB-ERR | directed | REQ-APB-2 | covered |
| VP-APB-ERR-CAUSE | directed | REQ-APB-2 | covered |
| VP-APB-WAIT | directed | REQ-APB-3 | covered |
| VP-APB-WAIT-ERR | directed | REQ-APB-3 | covered |
| VP-CH-FSM | constrained-random | REQ-CORE-1, REQ-CORE-2, REQ-CORE-5 | covered |
| VP-CH-PERIOD | constrained-random | REQ-CORE-1 | covered |
| VP-CH-PERIOD0 | directed | REQ-CORE-1 | covered |
| VP-CH-COUNT-VALUE | assertion | REQ-CORE-1, REQ-CORE-5 | covered |
| VP-CH-COUNT-READBACK | test | REQ-CORE-1 | covered |
| VP-CH-MODE | directed | REQ-CORE-2 | covered |
| VP-CH-MODE-LIVE | directed | REQ-CORE-2 | covered |
| VP-CH-PAUSE | directed | REQ-CORE-4 | covered |
| VP-CH-PAUSE-PWM | assertion | REQ-CORE-4 | covered |
| VP-CH-DISABLE | directed | REQ-CORE-5 | covered |
| VP-PRESC-CFG | constrained-random | REQ-CORE-6 | covered |
| VP-PRESC-RATIO | directed | REQ-CORE-6 | covered |
| VP-PWM-DUTY | directed | REQ-CORE-3, REQ-OUT-1 | covered |
| VP-PWM-SHADOW-VALUE | assertion | REQ-CORE-3, REQ-CORE-1 | covered |
| VP-PWM-SHADOW-DEFER | assertion | REQ-CORE-3, REQ-CORE-1 | covered |
| VP-PWM-BLACKBOX | assertion | REQ-OUT-1 | covered |
| VP-PWM-ASSERT | assertion | REQ-CORE-3, REQ-CORE-8, REQ-OUT-1 | covered |
| VP-INT-AGG | assertion | REQ-INT-2, REQ-OUT-2 | covered |
| VP-INT-MASK-CROSS | constrained-random | REQ-INT-2, REQ-CORE-7 | covered |
| VP-INT-W1C | directed | REQ-INT-1, REQ-CORE-7 | covered |
| VP-INT-SIMUL | directed | REQ-INT-3 | covered |
| VP-INT-SETPRI | assertion | REQ-INT-1 | covered |
| VP-CORE7-EXPIRY | assertion | REQ-CORE-7 | covered |
| VP-RST-POR | directed | REQ-RST-1 | covered |
| VP-RST-ASYNC | directed | REQ-RST-1 | covered |
| VP-RST-SOFT | directed | REQ-RST-2 | covered |
| VP-SELFCLR | directed | REQ-RST-2 | covered |
| VP-MODULE-FREEZE | directed | REQ-CORE-8 | covered |
| VP-STATUS-AGG | assertion | REQ-CORE-8 | covered |
| VP-FREEZE-STATES | directed | REQ-CORE-8 | covered |
| VP-ERRATA | directed | REQ-VERIF-1 | covered |
| VP-VERIF-FCOV | constrained-random | REQ-VERIF-1 | covered |
| VP-CODECOV-SBC | constrained-random | REQ-VERIF-2 | covered |
| VP-CODECOV-TOGGLE | constrained-random | REQ-VERIF-2 | waived |
| VP-SYNTH-ELAB | static | REQ-SYNTH-1 | covered |
| VP-SYNTH-CDC | static | REQ-SYNTH-2 | covered |

## Per-requirement closure

| REQ | vPlan item(s) | Status |
|---|---|---|
| REQ-CORE-1 | VP-CH-FSM, VP-CH-PERIOD, VP-CH-PERIOD0, VP-CH-COUNT-VALUE, VP-CH-COUNT-READBACK, VP-PWM-SHADOW-VALUE, VP-PWM-SHADOW-DEFER | covered |
| REQ-CORE-2 | VP-CH-FSM, VP-CH-MODE, VP-CH-MODE-LIVE | covered |
| REQ-CORE-3 | VP-PWM-DUTY, VP-PWM-SHADOW-VALUE, VP-PWM-SHADOW-DEFER, VP-PWM-ASSERT | covered |
| REQ-CORE-4 | VP-CH-PAUSE, VP-CH-PAUSE-PWM | covered |
| REQ-CORE-5 | VP-CH-FSM, VP-CH-COUNT-VALUE, VP-CH-DISABLE | covered |
| REQ-CORE-6 | VP-PRESC-CFG, VP-PRESC-RATIO | covered |
| REQ-CORE-7 | VP-INT-MASK-CROSS, VP-INT-W1C, VP-CORE7-EXPIRY | covered |
| REQ-CORE-8 | VP-PWM-ASSERT, VP-MODULE-FREEZE, VP-STATUS-AGG, VP-FREEZE-STATES | covered |
| REQ-INT-1 | VP-INT-W1C, VP-INT-SETPRI | covered |
| REQ-INT-2 | VP-INT-AGG, VP-INT-MASK-CROSS | covered |
| REQ-INT-3 | VP-INT-SIMUL | covered |
| REQ-APB-1 | VP-REG-ACCESS, VP-APB-XFER, VP-APB-FSM-B2B | covered |
| REQ-APB-2 | VP-REG-ACCESS, VP-APB-ERR, VP-APB-ERR-CAUSE | covered |
| REQ-APB-3 | VP-APB-WAIT, VP-APB-WAIT-ERR | covered |
| REQ-OUT-1 | VP-PWM-DUTY, VP-PWM-BLACKBOX, VP-PWM-ASSERT | covered |
| REQ-OUT-2 | VP-INT-AGG | covered |
| REQ-RST-1 | VP-REG-RESET, VP-RST-POR, VP-RST-ASYNC | covered |
| REQ-RST-2 | VP-RST-SOFT, VP-SELFCLR | covered |
| REQ-VERIF-1 | VP-ERRATA, VP-VERIF-FCOV | covered |
| REQ-VERIF-2 | VP-CODECOV-SBC, VP-CODECOV-TOGGLE | covered |
| REQ-SYNTH-1 | VP-SYNTH-ELAB | covered |
| REQ-SYNTH-2 | VP-SYNTH-CDC | covered |

> Numbers are read from reports/_cov and reports/regression.txt; waiver justifications are maintained by coverage-closure. Regenerate with `flow/scripts/coverage_report.py`.
