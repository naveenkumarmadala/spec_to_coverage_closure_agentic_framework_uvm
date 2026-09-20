# PMTPC-4 — Requirements Database

Formalized by the `requirements-analyst` from the three PMTPC-4 specs (Requirements + Design Rev 1.1
+ Register Rev 1.1). IDs reuse the source spec's `REQ-*` labels (stable, testable). This is the root
of the traceability spine: `REQ → SPEC → REG → RTL → VP → COV`.

Source docs: [Requirements](PMTPC-4_Requirements_Specification.md) ·
[Design Rev 1.1](PMTPC-4_Design_Specification.md) · [Register Rev 1.1](PMTPC-4_Register_Specification.md)

## Functional — Timer/PWM channel core

| ID | Requirement (atomic, testable) | Cat | Pri | Source | Verifiable-by |
|---|---|---|---|---|---|
| REQ-CORE-1 | Each of 4 channels has an independent down-counter, decremented once per prescaled tick, reloading from PERIOD; must reach 0 and signal expiry without lock-up, including PERIOD=0 (expire next tick). | functional | must | Req §3.1, Des §7 | directed + covergroup |
| REQ-CORE-2 | Each channel supports One-Shot (on expiry: disable + self-clear CH_EN) and Periodic (on expiry: reload + continue); mode is **live-sampled at expiry**, not latched (errata 12.2). | functional | must | Req §3.1, Des §7.3/12.2 | directed + covergroup |
| REQ-CORE-3 | Each channel generates high-true trailing-edge PWM: output high while COUNT > COMPARE, low otherwise, gated by PWM_EN. | functional | must | Req §3.1, Des §7.4 | directed + assertion + covergroup |
| REQ-CORE-4 | Pause/resume via CH_PAUSE freezes COUNT and pwm_out and resumes from frozen value; **level-sensitive**, continuously sampled (errata 12.1). | functional | must | Req §3.1, Des §7.4/12.1 | directed + covergroup |
| REQ-CORE-5 | Soft-disable (CH_EN=0) returns a running channel to IDLE immediately without clearing COUNT state. | functional | must | Req §3.1, Des §7.3 | directed |
| REQ-CORE-6 | One shared 16-bit prescaler divides PCLK identically for all 4 channels, divide-by-1 (0) … divide-by-65536 (0xFFFF), changeable mid-run (takes effect next tick boundary, no corruption). | functional | must | Req §3.1, Reg §4 PRESCALER | directed + covergroup |
| REQ-CORE-7 | Each channel signals an expiry event on EXPIRED entry, independent of masking. | functional | must | Req §3.1, Des §7.2/8 | assertion + covergroup |
| REQ-CORE-8 | Global MODULE_EN=0 **freezes** (not resets) all channel state; pwm_out forced low, STATUS.BUSY=0; on MODULE_EN=1 each channel resumes from exact frozen state (errata 12.3). | functional | must | Req §3.1, Des §12.3 | directed + covergroup |

## Functional — Interrupts

| ID | Requirement | Cat | Pri | Source | Verifiable-by |
|---|---|---|---|---|---|
| REQ-INT-1 | INT_STATUS[n] latches on channel n expiry independent of masking; W1C; if a channel re-expires on the same cycle its bit is being cleared, **set wins** (no dropped event). | interrupt | must | Req §3.2, Reg §6 | directed + assertion |
| REQ-INT-2 | Per-channel INT_ENABLE masks a channel's contribution to IRQ/GLOBAL_ISR without blocking the raw latch; GLOBAL_IE globally gates. IRQ = GLOBAL_IE AND OR(INT_STATUS[n] AND INT_ENABLE[n]). | interrupt | must | Req §3.2, Des §8 | directed + covergroup + assertion |
| REQ-INT-3 | Simultaneous expiry of ≥2 channels on the identical prescaled tick sets all their status bits independently, no loss, no arbitration. | interrupt | must | Req §3.2, Des §7.4/8 | directed + covergroup |

## Interface — APB slave + outputs

| ID | Requirement | Cat | Pri | Source | Verifiable-by |
|---|---|---|---|---|---|
| REQ-APB-1 | Compliant APB3 slave: PSEL/PENABLE/PWRITE/PADDR[7:0]/PWDATA[31:0]/PRDATA[31:0]/PREADY/PSLVERR; only 32-bit word-aligned transfers legal; standard IDLE/SETUP/ACCESS FSM. | interface | must | Req §4.1, Des §5 | protocol assertions + covergroup |
| REQ-APB-2 | Decode 0x00–0xFF; reserved region / RO-register write / unaligned (PADDR[1:0]≠0) → PSLVERR=1, PRDATA=0, zero wait states, no state change. | error | must | Req §4.1, Des §5.4 | directed + covergroup |
| REQ-APB-3 | All registers zero-wait **except** CHx_COUNT reads, which insert exactly one wait state; errored accesses never insert a wait state (errata 12.4). | interface | must | Req §4.1, Des §5.3/12.4 | directed + covergroup |
| REQ-OUT-1 | One PWM output per channel (4 total), independently driven per the waveform rule; forced low during MODULE_EN=0 freeze. | interface | must | Req §4.2, Des §4.2 | assertion + covergroup |
| REQ-OUT-2 | Single active-high level IRQ line aggregating masked/enabled per-channel interrupts. | interface | must | Req §4.2, Des §8 | assertion |

## Reset & control

| ID | Requirement | Cat | Pri | Source | Verifiable-by |
|---|---|---|---|---|---|
| REQ-RST-1 | Async active-low PRESETn initializes all registers to reset values, all FSMs to IDLE, pwm_out low, irq low, from any state. | functional | must | Req §5, Des §9 | directed + reset assertion |
| REQ-RST-2 | Synchronous CTRL.SOFT_RESET clears channel cores + interrupt state (COUNT, FSM, INT_STATUS) but NOT PRESCALER/CLK_SEL/APB FSM; self-clears 1 cycle after write; does not disturb in-flight APB (errata 12.5). | functional | must | Req §5, Des §9/12.5 | directed |

## Non-functional

| ID | Requirement | Cat | Pri | Source | Verifiable-by |
|---|---|---|---|---|---|
| REQ-VERIF-1 | Verify to 100% functional coverage across all FSMs, register fields, and protocol edge cases, including the five errata, with traceability. | performance | must | Req §7 | coverage closure report |
| REQ-VERIF-2 | RTL achieves 100% line, toggle, FSM state/transition, and branch coverage, with a justified waiver list for unreachable code. | performance | must | Req §7 | code-coverage report |
| REQ-SYNTH-1 | RTL is synthesizable to a standard-cell library with no simulator-specific directives. | functional | must | Req §7 | Yosys elaboration gate |
| REQ-SYNTH-2 | Single clock domain (PCLK); no CDC. | functional | must | Req §7, Des §3.2 | design review + lint |

## Derived register requirements (from Register Spec Rev 1.1)

Each register/field yields access-policy + reset-value + reserved-bit requirements, verified by the
RAL sequences and register covergroups. Captured as vPlan `register`-method items rather than
individual REQ rows; the register map is the [SystemRDL source](../rdl/pmtpc4.rdl).

- CTRL(0x00): MODULE_EN[0] RW, SOFT_RESET[1] RW/self-clear, [31:2] reserved.
- STATUS(0x04, RO): BUSY[0], READY[1]. GLOBAL_IE(0x08): GLOBAL_INT_EN[0]. GLOBAL_ISR(0x0C, RO): [0].
- PRESCALER(0x10): PRESCALER_VAL[15:0]. CLK_SEL(0x14): CLK_SRC_SEL[0] (writable, no effect).
- CHx_CTRL(0x20/30/40/50): CH_EN[0], CH_MODE[1], PWM_EN[2], CH_START[3] self-clear, CH_PAUSE[4].
- CHx_PERIOD(+0x04): PERIOD_VAL[15:0]. CHx_COMPARE(+0x08): COMPARE_VAL[15:0]. CHx_COUNT(+0x0C, RO, 1 wait): COUNT_VAL[15:0].
- INT_STATUS(0x60, RW1C): CH_INT_STATUS[3:0]. INT_ENABLE(0x64): CH_INT_EN[3:0].
- Reserved offsets: 0x18–0x1C, 0x68–0x6C, 0x70–0xFF → PSLVERR.

## Open questions

None. All ambiguities were resolved as binding errata in Design Spec §12 (12.1–12.5) and are treated
as first-class requirements above. Coverage note: every register/field/interface/interrupt in
`ip_config.yaml` and every errata maps to ≥1 requirement or derived-register item.
