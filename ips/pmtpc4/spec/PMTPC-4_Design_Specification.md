Programmable Multi-Channel Timer/PWM Controller
(PMTPC-4)
Design Specification
Document Rev: 1.1
Status: Frozen for Verification
Classification: Verification Reference Golden Spec

# Revision History

| Rev | Date | Author | Description |
| --- | --- | --- | --- |
| 0.1 | 2026-06-01 | Arch Team | Initial draft |
| 1.0 | 2026-06-15 | Arch Team / Verification Lead | Frozen for RTL and verification kickoff |
| 1.1 | 2026-06-22 | Verification Lead | Errata: resolved 4 ambiguities raised during test-plan review — MODULE_EN freeze semantics, CH_PAUSE level-sensitivity, CH_MODE live-sampling, PSLVERR zero-wait-state, plus a self-clear timing clarification. See Section 12. |

# 1. Introduction

## 1.1 Purpose
This document defines the functional and micro-architectural specification of the Programmable Multi-Channel Timer/PWM Controller, referred to throughout as PMTPC-4. It is the golden reference for RTL implementation, verification test planning, UVM environment development, and coverage closure. All functional claims in the verification test plan and testbench must trace back to a statement in this document or its companion Register Specification.

## 1.2 Scope
PMTPC-4 is a synthesizable digital IP block providing four independently programmable timer/PWM channels, configured and monitored via a single APB (Advanced Peripheral Bus) slave interface. The IP targets integration into an SoC peripheral subsystem behind an APB bridge/interconnect.

## 1.3 Acronyms and Definitions

| Term | Definition |
| --- | --- |
| APB | Advanced Peripheral Bus (AMBA APB protocol, low-power/low-complexity register access bus) |
| PMTPC-4 | Programmable Multi-Channel Timer/PWM Controller, 4 channels |
| PWM | Pulse Width Modulation |
| PSLVERR | APB slave error response signal |
| W1C | Write-1-to-Clear register bit behavior |
| RO / RW / WO | Read-Only / Read-Write / Write-Only register access type |
| FSM | Finite State Machine |
| ISR | Interrupt Status Register |

## 1.4 References
- ARM AMBA3 APB Protocol Specification (IHI 0024) — protocol timing and signal behavior baseline
- PMTPC-4 Register Specification, Rev 1.1 (companion document)
- PMTPC-4 Verification Test Plan (downstream document, not covered here)

# 2. Feature Overview
- Single APB3-compliant slave interface for all configuration, control, and status access.
- 4 independent timer/PWM channels (CH0–CH3), each individually configurable.
- Per-channel selectable mode: One-Shot or Periodic (auto-reload) counting.
- Per-channel optional PWM output generation with independently programmable period and duty/compare value.
- Global clock prescaler (16-bit) shared by all channels, plus a reserved clock-source-select field for future use.
- Per-channel maskable interrupt on expiry/overflow event, plus an aggregated global interrupt output.
- Software-triggered global soft reset independent of the system reset.
- Per-channel pause/resume control without loss of current count value.
- APB address decode with explicit reserved regions that generate PSLVERR on access, and PSLVERR on illegal writes to read-only registers.
- Register address space: 0x00–0xFF (256 bytes), byte-addressed, 32-bit aligned register accesses only.

# 3. Architecture Overview
PMTPC-4 is partitioned into four functional sub-blocks: the APB Slave Interface (containing the APB protocol FSM and address decoder), the Register File, four instances of the Timer/PWM Channel Core, and the Interrupt Aggregator. The block-level structure is shown conceptually below.

### 3.1 Top-Level Block Diagram (structural description)

| Block | Responsibility |
| --- | --- |
| APB Slave Interface | Implements the APB protocol FSM (Section 5). Decodes PADDR into a register-file access (read or write), inserts wait states via PREADY when needed, and asserts PSLVERR for reserved-address or illegal-write accesses. |
| Register File | Holds all architectural registers (Section 6 summarizes; full bit-level detail is in the companion Register Specification). Presents configuration fields to the four Channel Cores and captures live status/count values for read-back. |
| Timer/PWM Channel Core x4 | One instance per channel (CH0–CH3). Implements the per-channel counting FSM (Section 7), generates the PWM output waveform when enabled, and raises a channel-local expiry event. |
| Interrupt Aggregator | Latches each channel's expiry event into INT_STATUS (per-channel, W1C), applies per-channel enable masking from INT_ENABLE, and ORs the result into GLOBAL_ISR / the single external interrupt line, subject to GLOBAL_IE. |

### 3.2 Clocking and Reset
PMTPC-4 operates from a single clock domain, PCLK, which also clocks the APB interface (no clock-domain crossing is present in this version). All channel counters are derived from PCLK divided by (PRESCALER_VAL + 1).
The IP has two independent reset mechanisms:
- PRESETn — asynchronous, active-low system reset. Resets the entire IP, including the APB FSM, to its default state.
- SOFT_RESET — a synchronous, software-triggered reset via CTRL.SOFT_RESET (Register Specification, 0x00). Resets all four channel cores and the interrupt state, but does not reset the APB FSM or in-flight APB transfer. SOFT_RESET is self-clearing: it reads back as 0 one PCLK cycle after being written to 1.

# 4. Interface Description

## 4.1 APB Slave Interface Signals

| Signal | Dir | Width | Description |
| --- | --- | --- | --- |
| PCLK | in | 1 | APB clock |
| PRESETn | in | 1 | Active-low asynchronous reset |
| PSEL | in | 1 | Slave select |
| PENABLE | in | 1 | Enable, asserted in the ACCESS phase |
| PWRITE | in | 1 | 1 = write, 0 = read |
| PADDR | in | 8 | Byte address, 0x00–0xFF |
| PWDATA | in | 32 | Write data |
| PRDATA | out | 32 | Read data |
| PREADY | out | 1 | 1 = transfer completes this cycle; 0 = insert wait state |
| PSLVERR | out | 1 | 1 = transfer completed with an error |

## 4.2 Other IP-Level Signals

| Signal | Dir | Width | Description |
| --- | --- | --- | --- |
| pwm_out | out | 4 | One PWM/timer output per channel (pwm_out[3:0]), driven only while the owning channel is enabled with PWM_EN=1 |
| irq | out | 1 | Single aggregated interrupt request line, active-high level, cleared by writing INT_STATUS bits and/or masking via INT_ENABLE / GLOBAL_IE |

Access sizing note: PMTPC-4 supports only full 32-bit, word-aligned APB accesses (PADDR[1:0] must be 2'b00). This is an architectural simplification adopted to bound the verification scope for this exercise; sub-word access support is explicitly out of scope (Section 11).

# 5. APB Slave Protocol FSM
The APB Slave Interface implements the standard 3-state APB slave FSM, augmented with an explicit wait-state count and a PSLVERR generation path. This is the FSM referenced throughout the verification test plan as the primary protocol-compliance coverage target.

## 5.1 States

| State | Description |
| --- | --- |
| IDLE | Default/reset state. No transfer in progress. PSEL is expected to be low. PREADY and PSLVERR are driven low. |
| SETUP | Entered when PSEL is sampled high with PENABLE low. Address (PADDR), PWRITE, and (for writes) PWDATA are latched. Address decode and access-legality checking occurs combinationally in this state. |
| ACCESS | Entered when PENABLE is sampled high while in SETUP. The actual register read or write occurs here. PREADY may be deasserted by the Register File to insert one or more wait cycles for registers that require it (Section 5.3). PSLVERR is asserted in this state if the access was determined illegal in SETUP. |

## 5.2 State Transition Table

| Current State | Condition | Next State | Notes |
| --- | --- | --- | --- |
| IDLE | PSEL=0 | IDLE | No transfer requested |
| IDLE | PSEL=1, PENABLE=0 | SETUP | New transfer requested; address decode begins |
| SETUP | PENABLE=1 | ACCESS | Per APB protocol, PENABLE must go high exactly one cycle after PSEL in SETUP |
| ACCESS | PREADY=0 (wait inserted) | ACCESS | Slave not yet ready; PSEL and PENABLE held by master |
| ACCESS | PREADY=1, PSEL=0 | IDLE | Transfer complete, no back-to-back transfer |
| ACCESS | PREADY=1, PSEL=1, PENABLE=0 | SETUP | Transfer complete, back-to-back transfer begins immediately |

## 5.3 Wait-State Behavior
All Global and Interrupt registers (0x00–0x1F, 0x60–0x6F) and per-channel CTRL/PERIOD/COMPARE registers respond with zero wait states (PREADY=1 in the first ACCESS cycle). The per-channel COUNT register (read-only, live counter value) inserts exactly one wait state to model a synchronizing read latch, giving the verification environment a concrete, deterministic non-zero wait-state case rather than an arbitrary one. This is intentional: it guarantees the APB FSM's PREADY-low path is exercised by legitimate, spec-mandated traffic rather than only by artificially injected stalls.

## 5.4 PSLVERR Generation Rules
PSLVERR is asserted (for exactly one ACCESS cycle, together with PREADY=1) when, during the SETUP phase preceding that ACCESS, any of the following is detected:
- The decoded address falls within a reserved region: 0x18–0x1C, 0x68–0x6C, or 0x70–0xFF.
- PWRITE=1 (a write) targets a register or field that is read-only in its entirety (STATUS 0x04, GLOBAL_ISR 0x0C, any CHx_COUNT). The write does not modify the register; data is discarded.
- PADDR[1:0] != 2'b00 (unaligned access).

On PSLVERR, PRDATA is driven to 32'h00000000 for reads; no register state changes as a result of an errored access.
Rev 1.1 clarification: illegal/reserved-address accesses always complete with zero wait states — PREADY=1 in the very first ACCESS cycle, together with PSLVERR=1. The single-wait-state behavior described in Section 5.3 applies only to legal, non-erroring accesses (specifically, CHx_COUNT reads); an errored access never inserts a wait state, since no register-file access actually occurs.

# 6. Register Space Summary
Full bit-field detail, reset values, and per-bit access types for every register below are defined in the companion document, PMTPC-4 Register Specification, Rev 1.1. This section provides only the address map overview for architectural context.

| Offset | Name | Access | Description |
| --- | --- | --- | --- |
| 0x00 | CTRL | RW | Global control: module enable, soft reset |
| 0x04 | STATUS | RO | Global status: busy/ready |
| 0x08 | GLOBAL_IE | RW | Global interrupt enable |
| 0x0C | GLOBAL_ISR | RO | Aggregated global interrupt status |
| 0x10 | PRESCALER | RW | 16-bit clock prescaler value |
| 0x14 | CLK_SEL | RW | Clock source select (reserved bit today) |
| 0x18–0x1C | Reserved | — | Reserved; access generates PSLVERR |
| 0x20–0x2C | CH0_CTRL/PERIOD/COMPARE/COUNT | RW/RW/RW/RO | Channel 0 configuration and status |
| 0x30–0x3C | CH1_CTRL/PERIOD/COMPARE/COUNT | RW/RW/RW/RO | Channel 1 configuration and status |
| 0x40–0x4C | CH2_CTRL/PERIOD/COMPARE/COUNT | RW/RW/RW/RO | Channel 2 configuration and status |
| 0x50–0x5C | CH3_CTRL/PERIOD/COMPARE/COUNT | RW/RW/RW/RO | Channel 3 configuration and status |
| 0x60 | INT_STATUS | RW1C | Per-channel interrupt status, write-1-to-clear |
| 0x64 | INT_ENABLE | RW | Per-channel interrupt enable mask |
| 0x68–0x6C | Reserved | — | Reserved; access generates PSLVERR |
| 0x70–0xFF | Reserved | — | Reserved; access generates PSLVERR |

# 7. Timer/PWM Channel Core

## 7.1 Overview
Each of the four Channel Cores is functionally identical and independent, differing only in the register offsets that feed it. Each channel maintains a free-running-within-period down-counter (COUNT), reloaded from PERIOD, decrementing once per prescaled clock tick while the channel is enabled and not paused.

## 7.2 Channel FSM States

| State | Description |
| --- | --- |
| IDLE | Channel disabled (CH_EN=0) or held here after reset/soft-reset. COUNT holds its last value; no decrementing occurs. |
| LOAD | Entered for exactly one prescaled tick when the channel transitions from disabled to enabled (CH_EN 0→1) or when CH_START is pulsed. COUNT is loaded from PERIOD. |
| RUNNING | COUNT decrements once per prescaled tick. If PWM_EN=1, pwm_out for this channel is driven high while COUNT > COMPARE and low otherwise (standard trailing-edge PWM). |
| PAUSED | Entered from RUNNING when CH_PAUSE=1 is written. COUNT is frozen at its current value; pwm_out is frozen at its current level. Returns to RUNNING when CH_PAUSE=0 is written. |
| EXPIRED | Entered for exactly one prescaled tick when COUNT reaches 0 in RUNNING. The channel's expiry event is raised to the Interrupt Aggregator on this transition. |

## 7.3 Channel FSM Transition Table

| Current State | Condition | Next State | Notes |
| --- | --- | --- | --- |
| IDLE | CH_EN=0 | IDLE | Disabled, no activity |
| IDLE | CH_EN=1 (rising) or CH_START pulsed while CH_EN=1 | LOAD | Begin a new counting cycle |
| LOAD | next prescaled tick | RUNNING | COUNT now holds PERIOD value |
| RUNNING | CH_PAUSE=1 | PAUSED | Freeze count and PWM level |
| RUNNING | COUNT reaches 0 | EXPIRED | Raise channel interrupt event |
| RUNNING | CH_EN=0 | IDLE | Software disable takes effect immediately |
| PAUSED | CH_PAUSE=0 | RUNNING | Resume counting from frozen value |
| PAUSED | CH_EN=0 | IDLE | Software disable overrides pause |
| EXPIRED | CH_MODE=One-Shot | IDLE | Channel self-disables; CH_EN reads back 0 |
| EXPIRED | CH_MODE=Periodic | LOAD | Auto-reload; counting continues without software intervention |

## 7.4 Edge Cases Called Out for Verification
- PERIOD_VAL = 0: COUNT loads 0 and expires on the very next tick after LOAD — a legal but boundary configuration that must produce a correct, immediate EXPIRED transition, not a lock-up.
- COMPARE_VAL >= PERIOD_VAL: pwm_out for that channel must remain continuously low for the entire period (never exceeds compare), which is a legal configuration, not an error.
- COMPARE_VAL = 0: pwm_out must remain continuously high for the entire period except at COUNT=0.
- Writing PERIOD or COMPARE while the channel is RUNNING: the new value takes effect only on the next LOAD (i.e., the next reload/expiry), not immediately — the in-flight count is not corrupted.
- CH_START pulsed while already RUNNING: has no effect (ignored) — only a rising edge on CH_EN, or CH_START while transitioning out of IDLE, initiates LOAD.
- Simultaneous expiry of multiple channels on the same prescaled tick: each channel's interrupt bit in INT_STATUS must be set independently and correctly; no event may be dropped due to another channel expiring in the same cycle.
- SOFT_RESET asserted while one or more channels are RUNNING/PAUSED: all channels must return to IDLE, COUNT and pwm_out must be forced to their reset values, and any pending (unset) expiry in the same cycle must not be latched into INT_STATUS.
- Rev 1.1 clarification: CH_PAUSE is level-sensitive, not edge-triggered, and is continuously sampled whenever the channel is in LOAD, RUNNING, or PAUSED. If CH_PAUSE=1 is already set at the moment LOAD would complete, the channel transitions directly from LOAD to PAUSED (skipping a visible RUNNING cycle), with COUNT holding the freshly loaded PERIOD value. This resolves the previously open question of CH_EN and CH_PAUSE being written together in the same APB write from IDLE.
- Rev 1.1 clarification: CH_MODE is sampled live at the instant of each EXPIRED transition, not latched at LOAD entry. A write to CH_MODE at any time — including while the channel is RUNNING or PAUSED — takes effect for whichever EXPIRED evaluation occurs next; no separate latch or shadow register is needed, and the transition table in Section 7.3 is evaluated using the live register value.
- Rev 1.1 clarification: self-clearing bits (SOFT_RESET at 0x00, CH_START in CHx_CTRL) are guaranteed by APB minimum transaction timing to never be observable as still-1 by a subsequent software read. A new APB transaction requires at least two PCLK cycles (SETUP then ACCESS) after the triggering write's ACCESS phase completes, while self-clear completes one PCLK cycle after that same ACCESS phase. This is a timing guarantee, not a race condition; verification should confirm it with a directed back-to-back minimum-latency read rather than treat it as an open corner case.

# 8. Interrupt Architecture
Each channel's transition into EXPIRED sets its corresponding bit in INT_STATUS[3:0] (0x60), regardless of the state of INT_ENABLE — INT_STATUS reflects raw channel events. A bit in INT_STATUS remains set until software writes a 1 to that bit position (write-1-to-clear); writing 0 has no effect on that bit.
The external irq output is the logical AND of GLOBAL_IE.GLOBAL_INT_EN with the logical OR, across all four channels, of (INT_STATUS[n] AND INT_ENABLE[n]). Consequently, software can leave INT_STATUS bits set (for polling) while suppressing the irq line entirely via INT_ENABLE or GLOBAL_IE, and GLOBAL_ISR (0x0C) reports that same masked-and-aggregated value for read-back convenience, distinct from the raw per-channel bits in INT_STATUS.

# 9. Reset Behavior Summary

| Reset Source | Scope | Behavior |
| --- | --- | --- |
| PRESETn (async, active-low) | Entire IP | All registers to their reset values (Register Specification), APB FSM to IDLE, all channels to IDLE, pwm_out driven low, irq driven low. |
| CTRL.SOFT_RESET (sync, self-clearing) | Register File (except CTRL/STATUS/APB FSM state) and all 4 channels | All channel COUNT values, states, and pwm_out outputs return to reset defaults. INT_STATUS is cleared. The APB transfer in progress, if any, completes normally; PRESCALER and CLK_SEL retain their programmed values (soft reset is a channel/interrupt reset, not a full reconfiguration reset). |

# 10. Representative Timing Behavior (textual waveform description)
A single-wait-state APB read of a CHx_COUNT register proceeds as: Cycle 1 (IDLE→SETUP): master drives PSEL=1, PENABLE=0, PADDR=target, PWRITE=0. Cycle 2 (SETUP→ACCESS): PENABLE=1; slave decodes address, begins synchronizing read, drives PREADY=0. Cycle 3 (ACCESS, wait): PSEL/PENABLE held; slave drives PREADY=1 and valid PRDATA in this same cycle, completing the transfer. Cycle 4: FSM returns to IDLE (or SETUP if back-to-back).

# 11. Assumptions and Out-of-Scope Items

## 11.1 Assumptions
- Single clock domain; PCLK drives both the APB interface and, after prescaling, all channel counters.
- APB master is protocol-compliant (e.g., never drops PSEL mid-transfer, always asserts PENABLE the cycle after PSEL in SETUP).
- System integrator ties off unused pwm_out bits externally if fewer than 4 channels are used on the board — not applicable here since all 4 are always present.

## 11.2 Out of Scope
- Sub-word (8-bit/16-bit) APB access support — only full 32-bit word accesses are supported; PADDR[1:0] != 0 is treated as an error (Section 5.4).
- Multiple outstanding/pipelined APB transfers (not supported by APB protocol itself).
- Clock-domain crossing / asynchronous PWM output clock — single clock domain only in this version.
- Low-power / clock-gating control interface.
- Security/TrustZone attribute checking on APB accesses (PPROT is not used by this design).

# 12. Errata and Design Clarifications (Rev 1.1)
During verification test-plan review, four ambiguities and one false-positive corner case were identified in Rev 1.0 of this document. Each was resolved as a binding design decision below, made by the verification lead in the role of architecture owner, and is now normative for RTL implementation, the Register Specification, and the verification test plan. This is the standard spec-errata process: ambiguities found during test planning are resolved here rather than left to individual interpretation by RTL and verification engineers separately, which is exactly the failure mode this section exists to prevent.

## 12.1 CH_PAUSE / CH_EN Written Together From IDLE
Issue: Section 7 did not define behavior when software writes CH_EN=1 and CH_PAUSE=1 in the same APB write while the channel is IDLE.
Decision: CH_PAUSE is level-sensitive (Section 7.4). The channel proceeds IDLE→LOAD normally, and if CH_PAUSE is still 1 when LOAD completes, it transitions directly to PAUSED instead of RUNNING, with COUNT already holding the loaded PERIOD value. This keeps CH_PAUSE's semantics uniform in every state instead of requiring separate rules for a same-cycle write.

## 12.2 CH_MODE Changed While a Channel Is RUNNING
Issue: Section 7 did not state whether a mid-cycle write to CH_MODE takes effect immediately, at the next LOAD, or at the next EXPIRED.
Decision: CH_MODE is sampled live at the moment of each EXPIRED transition (Section 7.4). No latching or shadow copy is implemented; whichever value is programmed at the instant COUNT reaches 0 determines whether the channel goes to IDLE (One-Shot) or LOAD (Periodic).

## 12.3 MODULE_EN=0 Behavior — Freeze, Not Reset
Issue: Section 2 and the original CTRL.MODULE_EN description stated only that channels are “forced IDLE” while MODULE_EN=0, without specifying whether COUNT is retained or cleared, and without defining resume behavior when MODULE_EN returns to 1.
Decision: MODULE_EN=0 freezes all four channels — FSM state, COUNT value, and any single-cycle LOAD/EXPIRED evaluation in progress are held exactly as they were at the moment MODULE_EN transitioned to 0, identically in effect to CH_PAUSE=1 applied globally to every channel simultaneously. Externally, pwm_out is forced low for all channels and STATUS.BUSY reads as 0 while MODULE_EN=0, even though internal state is preserved rather than cleared. When MODULE_EN returns to 1, each channel resumes exactly from its frozen state: a RUNNING channel continues decrementing from the retained COUNT, a channel frozen mid-LOAD completes the LOAD on the next tick, and a channel frozen mid-EXPIRED completes its EXPIRED transition (including raising the interrupt) on the next tick. This makes MODULE_EN a safe global pause that never loses channel timing state, and keeps it architecturally distinct from SOFT_RESET, which clears state rather than freezing it. This supersedes the MODULE_EN wording in Section 2, and the companion Register Specification's CTRL register description has been updated to Rev 1.1 to match.

## 12.4 PSLVERR and Wait-State Interaction
Issue: Section 5 did not explicitly state whether an illegal/reserved-address access could ever incur a wait state the way a legal CHx_COUNT read does.
Decision: illegal accesses always complete with zero wait states (Section 5.4, updated). No register-file access actually occurs on an errored transfer, so there is nothing to synchronize against.

## 12.5 Self-Clearing Bit Read-Back — Timing Guarantee, Not a Race
Issue: it was initially flagged as an open race condition whether software could observe SOFT_RESET or CH_START as still 1 if it issued a read in the same cycle the self-clear occurs.
Decision: this is not actually a race. The minimum possible latency for a new APB transaction to reach its ACCESS phase (SETUP + ACCESS, 2 PCLK cycles) is strictly greater than the 1 PCLK cycle the self-clear takes to complete after the triggering write's own ACCESS phase. No physically valid APB read sequence can observe the bit as 1. Verification should still add a directed back-to-back minimum-latency test to confirm this timing guarantee holds in RTL, rather than exclude it as untestable (Section 7.4).

# 13. Open Issues
None outstanding as of Rev 1.1. The four ambiguities and one false-positive race raised during verification test-plan review (Section 12) have been resolved and are binding. Any further deviation discovered during RTL implementation or verification must be raised against this document and the companion Register Specification before test plan sign-off is impacted.
