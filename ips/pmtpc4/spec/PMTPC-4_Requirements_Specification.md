Programmable Multi-Channel Timer/PWM Controller
(PMTPC-4)
Requirements Specification
Document Rev: 1.0 (Retroactive Reconstruction)
Authored: 2026-07-18 (after Design Spec Rev 1.1 frozen)
Status: Frozen — Companion to Design Spec Rev 1.1 & Register Spec Rev 1.1

# Revision History

| Rev | Date | Author | Description |
| --- | --- | --- | --- |
| 1.0 | 2026-07-18 | Verification Lead | Retroactive reconstruction: authored after Design Spec Rev 1.1 frozen, to establish documented requirements justifying architecture decisions. |

# 1. Document Purpose & Provenance
This Requirements Specification is an explicit RETROACTIVE RECONSTRUCTION, authored after the Design Specification (Rev 1.1) was already frozen. It is NOT the original source document from which the design was derived. Rather, it documents the system-level requirements that the Design Specification architecture satisfies, backfilled to formalize the traceability chain.

# 2. System Requirements Overview

## 2.1 System-Level Goal
Design and verify a synthesizable, peripheral-IP-level timer/PWM controller suitable for integration into a SoC subsystem via an AMBA APB slave interface, providing independent, software-configured timing and waveform-generation capabilities on four channels, with sufficient architectural simplicity that 100% functional and code coverage can be achieved and documented within a bounded test-plan scope.

## 2.2 Target Integration Context
- Integration point: APB slave peripheral, behind an APB3 bridge/interconnect in a typical ARM-based SoC.
- Subsystem/context: Peripheral subsystem, not a core/fabric component.
- Clock domain: Single clock domain (PCLK shared between APB and channel counters); no CDC required.
- User: Software-driven peripheral control via memory-mapped registers.

# 3. Functional Requirements

## 3.1 Timer/PWM Channel Core
REQ-CORE-1 [Independent Counting]: Each of four channels shall maintain an independent down-counter, decremented once per prescaled tick. The counter shall reload from a software-programmed PERIOD value and be capable of reaching zero and signaling expiry without data loss or lock-up, including edge cases such as PERIOD=0.
REQ-CORE-2 [Dual Timer Modes]: Each channel shall support two independently selectable modes: (a) One-Shot — on expiry, the channel disables itself and self-clears its enable bit; (b) Periodic — on expiry, the channel automatically reloads from PERIOD and continues. Mode selection shall be live-sampled at the instant of expiry, not latched.
REQ-CORE-3 [PWM Output Generation]: Each channel shall independently generate a PWM output, enabled by a software flag, producing a high-true, trailing-edge-modulated waveform: output high while COUNT > COMPARE, low otherwise.
REQ-CORE-4 [Pause/Resume without State Loss]: Each channel shall support pause/resume control via a software-writable flag: pause freezes the counter and PWM output, resume continues from the frozen value. Pause shall be level-sensitive and continuously sampled, allowing it to trap the channel in a paused state immediately after LOAD.
REQ-CORE-5 [Soft Disable without Reset]: Software shall be able to disable (CH_EN=0) a running channel immediately, returning it to idle without clearing state.
REQ-CORE-6 [Global Prescaler Sharing]: A single, global 16-bit prescaler value shall divide PCLK for all four channels identically, supporting divide-by-1 (PRESCALER=0) through divide-by-65536 (PRESCALER=0xFFFF), changeable mid-run.
REQ-CORE-7 [Expiry Event Signaling]: Each channel shall signal an expiry event on EXPIRED state entry, independent of masking.
REQ-CORE-8 [Global Module Enable with Freeze Semantics]: A global module-enable flag shall freeze all channel state to their current values when deasserted, without resetting them. Channels resume from the exact frozen state when re-enabled. Externally, PWM outputs forced low and STATUS.BUSY reads 0.

## 3.2 Interrupt Architecture
REQ-INT-1 [Raw Per-Channel Interrupt Status]: A per-channel interrupt status register shall latch on channel expiry, independent of any masking, with write-1-to-clear guarantee that if a channel re-expires on the same cycle its bit is being cleared, the set takes priority.
REQ-INT-2 [Per-Channel Masking and Global Aggregation]: A per-channel interrupt enable mask shall allow suppressing each channel's contribution to the external IRQ line without preventing the raw status latch. A global interrupt-enable flag further gates all interrupts. IRQ = GLOBAL_IE AND OR(per-channel status AND per-channel enable).
REQ-INT-3 [Simultaneous Multi-Channel Expiry]: No shared state or arbitration shall exist; if two or more channels expire on the identical prescaled-tick pulse, all shall independently signal expiry with all status bits set without loss.

# 4. Interface Requirements

## 4.1 APB Slave Port
REQ-APB-1 [AMBA3 APB3 Compliance]: The IP shall present a compliant APB3 slave interface supporting PSEL, PENABLE, PWRITE, PADDR (8-bit), PWDATA (32-bit), PRDATA (32-bit), PREADY, and PSLVERR. Only 32-bit, word-aligned transfers are legal.
REQ-APB-2 [Address Decode and Error Response]: The slave shall decode 0x00–0xFF, implementing valid registers and reserved regions. Accesses to reserved regions, writes to read-only registers, or unaligned transfers (PADDR[1:0] ≠ 0) return PSLVERR=1 and PRDATA=0x00000000, completing in zero wait states.
REQ-APB-3 [Selective Wait-State Support]: All registers complete with zero wait states, except per-channel COUNT reads, which insert exactly one wait state to model a hardware read-latch synchronization delay.

## 4.2 Per-Channel Outputs
REQ-OUT-1 [PWM Output Pin Per Channel]: The IP shall provide one PWM output per channel (4 total), independently driven per the PWM waveform rule. During module-enable=0 freeze, outputs forced low externally.
REQ-OUT-2 [Aggregated Interrupt Request]: The IP shall provide a single active-high, level-driven interrupt request line aggregating all masked, enabled per-channel interrupts.

# 5. Reset & Control Requirements
REQ-RST-1 [Asynchronous System Reset]: An active-low asynchronous reset (PRESETn) shall initialize all registers to reset values, return all channel FSMs to IDLE, drive PWM outputs low, and drive IRQ low, regardless of operating state.
REQ-RST-2 [Synchronous Soft Reset]: A synchronous software-writable bit in CTRL shall trigger a soft reset scoped to all channel cores and interrupt state (COUNT, FSM state, INT_STATUS) but NOT to PRESCALER, CLK_SEL, or the APB FSM. The reset bit shall self-clear one cycle after being written and not disturb an in-flight APB transfer.

# 6. Traceability Matrix — Requirements to Design Specification
The following table shows which Design Specification (Rev 1.1) and Register Specification (Rev 1.1) sections satisfy each requirement:

| REQ ID | Title | Design Spec § | Register Spec § |
| --- | --- | --- | --- |
| REQ-CORE-1 | Independent Counting | 7 (Channel FSM) | 5 (CHx registers) |
| REQ-CORE-2 | Dual Timer Modes | 7.2/7.3, 12.2 (errata) | 5.1 (CH_MODE) |
| REQ-CORE-3 | PWM Output Generation | 7.4 (PWM rule) | 5.3 (CHx_COMPARE) |
| REQ-CORE-4 | Pause/Resume | 7.2/7.3, 12.1 (errata) | 5.1 (CH_PAUSE) |
| REQ-CORE-5 | Soft Disable | 7.3 (CH_EN=0 overrides) | 5.1 (CH_EN) |
| REQ-CORE-6 | Global Prescaler | 3.2, 7 | 4 (PRESCALER) |
| REQ-CORE-7 | Expiry Event | 7.2, 8 | 6 (INT_STATUS) |
| REQ-CORE-8 | Module Enable Freeze | 9, 12.3 (errata) | 4.1 (MODULE_EN), 4.2 (STATUS) |
| REQ-INT-1 | Raw Status Latch | 8 | 6 (INT_STATUS) |
| REQ-INT-2 | Masking & Aggregation | 8 | 6 (INT_ENABLE), 4 (GLOBAL_IE) |
| REQ-INT-3 | Simultaneous Expiry | 7.4, 8 | 6 (INT_STATUS bits) |
| REQ-APB-1 | APB3 Compliance | 5 (APB FSM) | 3 (address map) |
| REQ-APB-2 | Address Decode & Error | 5.4 (PSLVERR) | 2 (reserved regions) |
| REQ-APB-3 | Wait-State Support | 5.3 | 5 (CHx_COUNT) |
| REQ-OUT-1 | PWM Outputs | 7 (pwm_out) | 5 (CHx_CTRL.PWM_EN) |
| REQ-OUT-2 | Interrupt Request | 8 (irq aggregation) | 4 (GLOBAL_ISR) |
| REQ-RST-1 | System Reset | 9 (PRESETn) | 4 (reset values) |
| REQ-RST-2 | Soft Reset | 9, 12.5 (errata) | 4.1 (CTRL.SOFT_RESET) |

# 7. Non-Functional Requirements
REQ-VERIF-1 [Full Functional Coverage]: The design shall be verified to 100% functional coverage across all architectural FSMs, register fields, and protocol edge cases, including the five errata-level design decisions, with formal traceability to spec requirements.
REQ-VERIF-2 [Code Coverage Closure]: The design RTL shall achieve 100% line, toggle, FSM state/transition, and branch coverage, with a justified waiver list for unreachable code.
REQ-SYNTH-1 [Synthesizable RTL]: The design shall be synthesizable to a standard-cell library without special assertions or simulator-specific directives.
REQ-SYNTH-2 [Single Clock Domain]: The design shall operate from a single clock input (PCLK); no clock-domain crossing required.
REQ-SCOPE-1 [Verification-Bounded Complexity]: The design shall be intentionally simple to allow realistic 100% coverage closure within a bounded, single-engineer verification exercise. Trade-offs favoring simplicity and testability are preferred over feature completeness.

# 8. Design Constraints & Assumptions

## 8.1 Assumptions
- APB master is protocol-compliant (never drops PSEL mid-transfer, always asserts PENABLE the cycle after PSEL in SETUP).
- Clock is well-behaved (no glitches, meets all setup/hold requirements).
- All inputs externally synchronized to PCLK; no metastability analysis required.

## 8.2 Out of Scope (Explicit Non-Requirements)
- Sub-word (8-bit/16-bit) APB access support.
- Multi-master arbitration or cross-bar interconnect support.
- Clock gating or dynamic power management.
- Asynchronous PWM output (PCLK-derived only).
- CDC or multi-clock-domain logic.
- Security/TrustZone attributes on APB accesses.
- External trigger or hardware-initiated counting (software-only control).

# 9. Backward Traceability Notes
This Requirements Specification was authored retroactively, after the Design Specification (Rev 1.1) was already frozen. This document's primary purpose is to establish documented justification and traceability rather than to have driven the original design decisions.
The design was born from an architectural sketch specifying only three constraints: (1) APB interface, (2) 0x00–0xFF register space, and (3) an APB FSM. From those seeds, the timer/PWM peripheral concept, 4-channel architecture, dual timer modes, global prescaler, and interrupt scheme emerged as a coherent microarchitecture suitable for a verification exercise.
This Requirements Specification reconstructs the system-level needs that such an architecture satisfies. For any future audit trail or external review, this document must be accompanied by the note that it is a reconstruction, with the true source-of-truth for design decisions being the Design Specification Rev 1.1 itself.

# 10. Open Items
None at the time of this reconstruction. All requirements are addressed by the frozen Design Specification and Register Specification (both Rev 1.1).
