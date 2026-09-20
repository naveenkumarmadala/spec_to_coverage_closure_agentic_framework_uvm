Programmable Multi-Channel Timer/PWM Controller
(PMTPC-4)
Register Specification
Document Rev: 1.1
Address Range: 0x00 – 0xFF (256 bytes)
Status: Frozen for Verification

# Revision History

| Rev | Date | Author | Description |
| --- | --- | --- | --- |
| 0.1 | 2026-06-01 | Arch Team | Initial draft |
| 1.0 | 2026-06-15 | Arch Team / Verification Lead | Frozen for RTL and verification kickoff, companion to Design Specification Rev 1.0 |
| 1.1 | 2026-06-22 | Verification Lead | Amended CTRL.MODULE_EN (freeze semantics), CTRL.SOFT_RESET / CHx_CTRL.CH_START (self-clear timing note), CHx_CTRL.CH_PAUSE (level-sensitivity), CHx_CTRL.CH_MODE (live-sampling) to match Design Specification Rev 1.1, Section 12. |

# 1. Introduction
This document is the companion Register Specification to the PMTPC-4 Design Specification, Rev 1.0. It defines the complete, bit-accurate register map for the PMTPC-4 IP across its full APB address range, 0x00–0xFF. Every register, every field, every reset value, and every reserved region defined here is binding for RTL implementation and is the direct source for the verification register model (RAL) and functional coverage on register fields.

## 1.1 Access Type Legend

| Type | Meaning |
| --- | --- |
| RW | Read-Write. Software may read back the last written value. |
| RO | Read-Only. Writes are ignored for reserved bits within an otherwise-writable register; a write to an offset that is entirely RO asserts PSLVERR. |
| RW1C | Read-Write-1-to-Clear. Reading returns current status; writing 1 to a bit clears it; writing 0 has no effect. |
| Self-Clear | Hardware automatically returns the bit to 0 a fixed number of cycles after software writes it to 1; software does not need to (and cannot meaningfully) write it back to 0. |

## 1.2 General Access Rules
- All registers are 32 bits wide and must be accessed as full, aligned 32-bit words (PADDR[1:0] = 2'b00). Unaligned accesses assert PSLVERR (see Design Specification, Section 5.4).
- Bits marked Reserved always read as 0 and ignore writes, within an otherwise valid, non-reserved register offset.
- Accessing a Reserved offset (Section 3) is distinct from a Reserved bit within a valid register: an access to a fully Reserved offset asserts PSLVERR; writing a Reserved bit within a valid register does not.
- A write to an offset that is architecturally entirely read-only (STATUS 0x04, GLOBAL_ISR 0x0C, any CHx_COUNT) asserts PSLVERR and the write has no effect on any state.

## 1.3 Rev 1.1 Amendments
Four field descriptions in this document were amended in Rev 1.1 to resolve ambiguities raised during verification test-plan review; each amendment is marked inline with a [Rev 1.1: ...] or [Amended Rev 1.1 ...] note at the affected field and cross-references the corresponding decision in the companion Design Specification, Rev 1.1, Section 12: CTRL.MODULE_EN (Section 4), CTRL.SOFT_RESET and every CHx_CTRL.CH_START (Section 4 and Section 5), and every CHx_CTRL.CH_PAUSE and CHx_CTRL.CH_MODE (Section 5).

# 2. Address Map Summary

| Offset | Name | Access | Reset | Summary |
| --- | --- | --- | --- | --- |
| 0x00 | CTRL | RW | 0x00000000 | Global module control: enable and software reset. |
| 0x04 | STATUS | RO | 0x00000000 | Global status: aggregated busy/ready indication across all channels. |
| 0x08 | GLOBAL_IE | RW | 0x00000000 | Global interrupt enable master switch. |
| 0x0C | GLOBAL_ISR | RO | 0x00000000 | Aggregated, masked global interrupt status (read-back convenience register; distinct from raw per-channel INT_STATUS at 0x60). |
| 0x10 | PRESCALER | RW | 0x00000000 | 16-bit clock prescaler shared by all 4 channels. |
| 0x14 | CLK_SEL | RW | 0x00000000 | Clock source selection (reserved for future multi-clock-source support). |
| 0x18 – 0x1C | Reserved | — | — | Reserved; PSLVERR on access |
| 0x20 | CH0_CTRL | RW | 0x00000000 | Channel 0 control register. |
| 0x24 | CH0_PERIOD | RW | 0x00000000 | Channel 0 period (reload) value. |
| 0x28 | CH0_COMPARE | RW | 0x00000000 | Channel 0 PWM compare/duty value. |
| 0x2C | CH0_COUNT | RO | 0x00000000 | Channel 0 live counter value (read-only; inserts 1 APB wait state, Design Specification Section 5.3). |
| 0x30 | CH1_CTRL | RW | 0x00000000 | Channel 1 control register. |
| 0x34 | CH1_PERIOD | RW | 0x00000000 | Channel 1 period (reload) value. |
| 0x38 | CH1_COMPARE | RW | 0x00000000 | Channel 1 PWM compare/duty value. |
| 0x3C | CH1_COUNT | RO | 0x00000000 | Channel 1 live counter value (read-only; inserts 1 APB wait state, Design Specification Section 5.3). |
| 0x40 | CH2_CTRL | RW | 0x00000000 | Channel 2 control register. |
| 0x44 | CH2_PERIOD | RW | 0x00000000 | Channel 2 period (reload) value. |
| 0x48 | CH2_COMPARE | RW | 0x00000000 | Channel 2 PWM compare/duty value. |
| 0x4C | CH2_COUNT | RO | 0x00000000 | Channel 2 live counter value (read-only; inserts 1 APB wait state, Design Specification Section 5.3). |
| 0x50 | CH3_CTRL | RW | 0x00000000 | Channel 3 control register. |
| 0x54 | CH3_PERIOD | RW | 0x00000000 | Channel 3 period (reload) value. |
| 0x58 | CH3_COMPARE | RW | 0x00000000 | Channel 3 PWM compare/duty value. |
| 0x5C | CH3_COUNT | RO | 0x00000000 | Channel 3 live counter value (read-only; inserts 1 APB wait state, Design Specification Section 5.3). |
| 0x60 | INT_STATUS | RW1C | 0x00000000 | Raw, per-channel interrupt status, write-1-to-clear. |
| 0x64 | INT_ENABLE | RW | 0x00000000 | Per-channel interrupt enable mask. |
| 0x68 – 0x6C | Reserved | — | — | Reserved; PSLVERR on access |
| 0x70 – 0xFF | Reserved | — | — | Reserved; PSLVERR on access |

# 3. Reserved Address Regions
The following address ranges are unimplemented and must never be targeted by legal software accesses. They are intentionally included in the verification scope as the primary stimulus target for APB error-response (PSLVERR) functional coverage.

| Range | Behavior |
| --- | --- |
| 0x18 – 0x1C | Reserved (2 words). Any access (read or write) decodes as illegal and returns PSLVERR=1, PRDATA=0x00000000 for reads. |
| 0x68 – 0x6C | Reserved (2 words). Any access (read or write) decodes as illegal and returns PSLVERR=1, PRDATA=0x00000000 for reads. |
| 0x70 – 0xFF | Reserved (36 words). Any access (read or write) decodes as illegal and returns PSLVERR=1, PRDATA=0x00000000 for reads. This is the largest contiguous reserved region in the map and is the primary target for APB-error-path functional coverage. |

# 4. Global / System Registers (0x00 – 0x1F)

### CTRL  —  Offset 0x00
Access: RW    Reset Value: 0x00000000
Global module control: enable and software reset.

| Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| 31:2 | Reserved | RO | 0 | Reserved. Reads as 0. Writes ignored. |
| 1 | SOFT_RESET | RW / Self-Clear | 0 | Write 1 to trigger a synchronous soft reset of all 4 channel cores and the interrupt state (see Design Specification, Section 9). Self-clears to 0 one PCLK cycle after being written to 1. Reading this bit while a soft reset is in progress returns 1; software may poll it to confirm completion. [Rev 1.1: this self-clear is guaranteed, by minimum APB transaction timing, to complete before any subsequent software read can occur — see Design Specification Section 12.5. Not a race condition.] |
| 0 | MODULE_EN | RW | 0 | 1 = module enabled; the APB interface remains live regardless of this bit. 0 = default at reset; all four channels are frozen — FSM state, COUNT, and any in-progress LOAD/EXPIRED evaluation are held exactly as they were at the moment MODULE_EN transitioned to 0 (equivalent to CH_PAUSE=1 applied globally), not reset or cleared. Externally, pwm_out is forced low and STATUS.BUSY reads 0 while MODULE_EN=0. When MODULE_EN returns to 1, each channel resumes exactly from its frozen state. [Amended Rev 1.1 — see Design Specification Section 12.3; supersedes the Rev 1.0 “forced IDLE” wording, which did not specify COUNT retention or resume behavior.] |

### STATUS  —  Offset 0x04
Access: RO    Reset Value: 0x00000000
Global status: aggregated busy/ready indication across all channels.

| Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| 31:2 | Reserved | RO | 0 | Reserved. Reads as 0. Writes ignored. |
| 1 | READY | RO | 0 | 1 = MODULE_EN=1 and no soft reset is currently in progress. 0 otherwise. |
| 0 | BUSY | RO | 0 | 1 = at least one channel is currently in RUNNING, LOAD, or PAUSED state. 0 = all four channels are IDLE. |

### GLOBAL_IE  —  Offset 0x08
Access: RW    Reset Value: 0x00000000
Global interrupt enable master switch.

| Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| 31:1 | Reserved | RO | 0 | Reserved. Reads as 0. Writes ignored. |
| 0 | GLOBAL_INT_EN | RW | 0 | 1 = the irq output may be asserted (subject to per-channel INT_ENABLE and INT_STATUS, Design Specification Section 8). 0 = irq is forced low regardless of any channel's interrupt status; INT_STATUS bits still latch normally. |

### GLOBAL_ISR  —  Offset 0x0C
Access: RO    Reset Value: 0x00000000
Aggregated, masked global interrupt status (read-back convenience register; distinct from raw per-channel INT_STATUS at 0x60).

| Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| 31:1 | Reserved | RO | 0 | Reserved. Reads as 0. Writes ignored. |
| 0 | GLOBAL_INT_STATUS | RO | 0 | Combinational OR, across all 4 channels, of (INT_STATUS[n] AND INT_ENABLE[n]), further ANDed with GLOBAL_IE.GLOBAL_INT_EN. This bit is a live read-back of the same condition that drives the irq output; it is not itself writable or clearable — clear the underlying INT_STATUS bits at 0x60 instead. A write to this offset is a write to a fully read-only register and asserts PSLVERR (Design Specification, Section 5.4). |

### PRESCALER  —  Offset 0x10
Access: RW    Reset Value: 0x00000000
16-bit clock prescaler shared by all 4 channels.

| Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| 31:16 | Reserved | RO | 0 | Reserved. Reads as 0. Writes ignored. |
| 15:0 | PRESCALER_VAL | RW | 0x0000 | Each channel's counter decrements once every (PRESCALER_VAL + 1) PCLK cycles. PRESCALER_VAL = 0 yields a divide-by-1 (every PCLK cycle) — a legal boundary value, not an error. Changing PRESCALER_VAL while channels are RUNNING takes effect on the next prescaled tick boundary; it does not corrupt the in-flight tick count. |

### CLK_SEL  —  Offset 0x14
Access: RW    Reset Value: 0x00000000
Clock source selection (reserved for future multi-clock-source support).

| Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| 31:1 | Reserved | RO | 0 | Reserved. Reads as 0. Writes ignored. |
| 0 | CLK_SRC_SEL | RW | 0 | Reserved for future use. In the current implementation only PCLK is available as a clock source; this bit is writable and readable but has no functional effect on channel counting behavior. Included in the address map now to avoid a future backward-incompatible address shift. |

# 5. Per-Channel Registers (0x20 – 0x5F)
Channels 0–3 are architecturally and functionally identical; each block below is independently instantiated hardware, not a shared/aliased register.

## 5.1 Channel 0  (Base Offset 0x20)

### CH0_CTRL  —  Offset 0x20
Access: RW    Reset Value: 0x00000000
Channel 0 control register.

| Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| 31:5 | Reserved | RO | 0 | Reserved. Reads as 0. Writes ignored. |
| 4 | CH_PAUSE | RW | 0 | 1 = freeze COUNT and pwm_out at current values (RUNNING→PAUSED). 0 = resume counting (PAUSED→RUNNING). No effect if the channel is IDLE. [Rev 1.1: level-sensitive, continuously sampled in LOAD/RUNNING/PAUSED — if set at the moment LOAD completes, the channel goes directly to PAUSED instead of RUNNING. See Design Specification Section 12.1.] |
| 3 | CH_START | RW / Self-Clear | 0 | Write 1 to pulse a (re)start of this channel's counting cycle if the channel is IDLE and CH_EN=1. Self-clears to 0 the following PCLK cycle. Writing 1 while the channel is already RUNNING or PAUSED has no effect (ignored, not an error). [Rev 1.1: self-clear timing is guaranteed to complete before any subsequent software read — see Design Specification Section 12.5.] |
| 2 | PWM_EN | RW | 0 | 1 = pwm_out[n] is driven per the PWM waveform rule (Design Specification Section 7.4). 0 = pwm_out[n] is held low regardless of COUNT/COMPARE; the channel still counts and can still generate interrupts. |
| 1 | CH_MODE | RW | 0 | 0 = One-Shot: on EXPIRED, channel returns to IDLE and CH_EN self-clears to 0. 1 = Periodic: on EXPIRED, channel auto-reloads from PERIOD and continues running without software intervention. [Rev 1.1: sampled live at the instant of each EXPIRED transition, not latched at LOAD — a write while RUNNING/PAUSED takes effect at the next EXPIRED evaluation. See Design Specification Section 12.2.] |
| 0 | CH_EN | RW | 0 | 1 = channel enabled; a 0→1 transition on this bit (with the channel currently IDLE) triggers LOAD, identically to a CH_START pulse. 0 = channel forced to IDLE immediately, regardless of current state; also self-clears to 0 automatically at the end of a One-Shot cycle. |

### CH0_PERIOD  —  Offset 0x24
Access: RW    Reset Value: 0x00000000
Channel 0 period (reload) value.

| Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| 31:16 | Reserved | RO | 0 | Reserved. Reads as 0. Writes ignored. |
| 15:0 | PERIOD_VAL | RW | 0x0000 | Value loaded into COUNT on every LOAD state entry. PERIOD_VAL = 0 is a legal boundary value: COUNT loads 0 and the channel expires on the very next prescaled tick. A write while the channel is RUNNING/PAUSED does not affect the current in-flight COUNT — it takes effect at the next LOAD. |

### CH0_COMPARE  —  Offset 0x28
Access: RW    Reset Value: 0x00000000
Channel 0 PWM compare/duty value.

| Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| 31:16 | Reserved | RO | 0 | Reserved. Reads as 0. Writes ignored. |
| 15:0 | COMPARE_VAL | RW | 0x0000 | While PWM_EN=1: pwm_out[n] is high while COUNT > COMPARE_VAL and low otherwise. COMPARE_VAL = 0 yields pwm_out[n] high for the entire period except at COUNT=0. COMPARE_VAL >= PERIOD_VAL yields pwm_out[n] continuously low for the entire period — both are legal configurations, not errors. A write while RUNNING/PAUSED takes effect at the next LOAD, matching PERIOD_VAL behavior. |

### CH0_COUNT  —  Offset 0x2C
Access: RO    Reset Value: 0x00000000
Channel 0 live counter value (read-only; inserts 1 APB wait state, Design Specification Section 5.3).

| Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| 31:16 | Reserved | RO | 0 | Reserved. Reads as 0. |
| 15:0 | COUNT_VAL | RO | 0x0000 | Current live count value of this channel's down-counter. Synchronized into the APB read path, which is why this register alone inserts one APB wait state. A write to this offset is a write to a fully read-only register and asserts PSLVERR. |

## 5.2 Channel 1  (Base Offset 0x30)

### CH1_CTRL  —  Offset 0x30
Access: RW    Reset Value: 0x00000000
Channel 1 control register.

| Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| 31:5 | Reserved | RO | 0 | Reserved. Reads as 0. Writes ignored. |
| 4 | CH_PAUSE | RW | 0 | 1 = freeze COUNT and pwm_out at current values (RUNNING→PAUSED). 0 = resume counting (PAUSED→RUNNING). No effect if the channel is IDLE. [Rev 1.1: level-sensitive, continuously sampled in LOAD/RUNNING/PAUSED — if set at the moment LOAD completes, the channel goes directly to PAUSED instead of RUNNING. See Design Specification Section 12.1.] |
| 3 | CH_START | RW / Self-Clear | 0 | Write 1 to pulse a (re)start of this channel's counting cycle if the channel is IDLE and CH_EN=1. Self-clears to 0 the following PCLK cycle. Writing 1 while the channel is already RUNNING or PAUSED has no effect (ignored, not an error). [Rev 1.1: self-clear timing is guaranteed to complete before any subsequent software read — see Design Specification Section 12.5.] |
| 2 | PWM_EN | RW | 0 | 1 = pwm_out[n] is driven per the PWM waveform rule (Design Specification Section 7.4). 0 = pwm_out[n] is held low regardless of COUNT/COMPARE; the channel still counts and can still generate interrupts. |
| 1 | CH_MODE | RW | 0 | 0 = One-Shot: on EXPIRED, channel returns to IDLE and CH_EN self-clears to 0. 1 = Periodic: on EXPIRED, channel auto-reloads from PERIOD and continues running without software intervention. [Rev 1.1: sampled live at the instant of each EXPIRED transition, not latched at LOAD — a write while RUNNING/PAUSED takes effect at the next EXPIRED evaluation. See Design Specification Section 12.2.] |
| 0 | CH_EN | RW | 0 | 1 = channel enabled; a 0→1 transition on this bit (with the channel currently IDLE) triggers LOAD, identically to a CH_START pulse. 0 = channel forced to IDLE immediately, regardless of current state; also self-clears to 0 automatically at the end of a One-Shot cycle. |

### CH1_PERIOD  —  Offset 0x34
Access: RW    Reset Value: 0x00000000
Channel 1 period (reload) value.

| Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| 31:16 | Reserved | RO | 0 | Reserved. Reads as 0. Writes ignored. |
| 15:0 | PERIOD_VAL | RW | 0x0000 | Value loaded into COUNT on every LOAD state entry. PERIOD_VAL = 0 is a legal boundary value: COUNT loads 0 and the channel expires on the very next prescaled tick. A write while the channel is RUNNING/PAUSED does not affect the current in-flight COUNT — it takes effect at the next LOAD. |

### CH1_COMPARE  —  Offset 0x38
Access: RW    Reset Value: 0x00000000
Channel 1 PWM compare/duty value.

| Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| 31:16 | Reserved | RO | 0 | Reserved. Reads as 0. Writes ignored. |
| 15:0 | COMPARE_VAL | RW | 0x0000 | While PWM_EN=1: pwm_out[n] is high while COUNT > COMPARE_VAL and low otherwise. COMPARE_VAL = 0 yields pwm_out[n] high for the entire period except at COUNT=0. COMPARE_VAL >= PERIOD_VAL yields pwm_out[n] continuously low for the entire period — both are legal configurations, not errors. A write while RUNNING/PAUSED takes effect at the next LOAD, matching PERIOD_VAL behavior. |

### CH1_COUNT  —  Offset 0x3C
Access: RO    Reset Value: 0x00000000
Channel 1 live counter value (read-only; inserts 1 APB wait state, Design Specification Section 5.3).

| Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| 31:16 | Reserved | RO | 0 | Reserved. Reads as 0. |
| 15:0 | COUNT_VAL | RO | 0x0000 | Current live count value of this channel's down-counter. Synchronized into the APB read path, which is why this register alone inserts one APB wait state. A write to this offset is a write to a fully read-only register and asserts PSLVERR. |

## 5.3 Channel 2  (Base Offset 0x40)

### CH2_CTRL  —  Offset 0x40
Access: RW    Reset Value: 0x00000000
Channel 2 control register.

| Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| 31:5 | Reserved | RO | 0 | Reserved. Reads as 0. Writes ignored. |
| 4 | CH_PAUSE | RW | 0 | 1 = freeze COUNT and pwm_out at current values (RUNNING→PAUSED). 0 = resume counting (PAUSED→RUNNING). No effect if the channel is IDLE. [Rev 1.1: level-sensitive, continuously sampled in LOAD/RUNNING/PAUSED — if set at the moment LOAD completes, the channel goes directly to PAUSED instead of RUNNING. See Design Specification Section 12.1.] |
| 3 | CH_START | RW / Self-Clear | 0 | Write 1 to pulse a (re)start of this channel's counting cycle if the channel is IDLE and CH_EN=1. Self-clears to 0 the following PCLK cycle. Writing 1 while the channel is already RUNNING or PAUSED has no effect (ignored, not an error). [Rev 1.1: self-clear timing is guaranteed to complete before any subsequent software read — see Design Specification Section 12.5.] |
| 2 | PWM_EN | RW | 0 | 1 = pwm_out[n] is driven per the PWM waveform rule (Design Specification Section 7.4). 0 = pwm_out[n] is held low regardless of COUNT/COMPARE; the channel still counts and can still generate interrupts. |
| 1 | CH_MODE | RW | 0 | 0 = One-Shot: on EXPIRED, channel returns to IDLE and CH_EN self-clears to 0. 1 = Periodic: on EXPIRED, channel auto-reloads from PERIOD and continues running without software intervention. [Rev 1.1: sampled live at the instant of each EXPIRED transition, not latched at LOAD — a write while RUNNING/PAUSED takes effect at the next EXPIRED evaluation. See Design Specification Section 12.2.] |
| 0 | CH_EN | RW | 0 | 1 = channel enabled; a 0→1 transition on this bit (with the channel currently IDLE) triggers LOAD, identically to a CH_START pulse. 0 = channel forced to IDLE immediately, regardless of current state; also self-clears to 0 automatically at the end of a One-Shot cycle. |

### CH2_PERIOD  —  Offset 0x44
Access: RW    Reset Value: 0x00000000
Channel 2 period (reload) value.

| Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| 31:16 | Reserved | RO | 0 | Reserved. Reads as 0. Writes ignored. |
| 15:0 | PERIOD_VAL | RW | 0x0000 | Value loaded into COUNT on every LOAD state entry. PERIOD_VAL = 0 is a legal boundary value: COUNT loads 0 and the channel expires on the very next prescaled tick. A write while the channel is RUNNING/PAUSED does not affect the current in-flight COUNT — it takes effect at the next LOAD. |

### CH2_COMPARE  —  Offset 0x48
Access: RW    Reset Value: 0x00000000
Channel 2 PWM compare/duty value.

| Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| 31:16 | Reserved | RO | 0 | Reserved. Reads as 0. Writes ignored. |
| 15:0 | COMPARE_VAL | RW | 0x0000 | While PWM_EN=1: pwm_out[n] is high while COUNT > COMPARE_VAL and low otherwise. COMPARE_VAL = 0 yields pwm_out[n] high for the entire period except at COUNT=0. COMPARE_VAL >= PERIOD_VAL yields pwm_out[n] continuously low for the entire period — both are legal configurations, not errors. A write while RUNNING/PAUSED takes effect at the next LOAD, matching PERIOD_VAL behavior. |

### CH2_COUNT  —  Offset 0x4C
Access: RO    Reset Value: 0x00000000
Channel 2 live counter value (read-only; inserts 1 APB wait state, Design Specification Section 5.3).

| Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| 31:16 | Reserved | RO | 0 | Reserved. Reads as 0. |
| 15:0 | COUNT_VAL | RO | 0x0000 | Current live count value of this channel's down-counter. Synchronized into the APB read path, which is why this register alone inserts one APB wait state. A write to this offset is a write to a fully read-only register and asserts PSLVERR. |

## 5.4 Channel 3  (Base Offset 0x50)

### CH3_CTRL  —  Offset 0x50
Access: RW    Reset Value: 0x00000000
Channel 3 control register.

| Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| 31:5 | Reserved | RO | 0 | Reserved. Reads as 0. Writes ignored. |
| 4 | CH_PAUSE | RW | 0 | 1 = freeze COUNT and pwm_out at current values (RUNNING→PAUSED). 0 = resume counting (PAUSED→RUNNING). No effect if the channel is IDLE. [Rev 1.1: level-sensitive, continuously sampled in LOAD/RUNNING/PAUSED — if set at the moment LOAD completes, the channel goes directly to PAUSED instead of RUNNING. See Design Specification Section 12.1.] |
| 3 | CH_START | RW / Self-Clear | 0 | Write 1 to pulse a (re)start of this channel's counting cycle if the channel is IDLE and CH_EN=1. Self-clears to 0 the following PCLK cycle. Writing 1 while the channel is already RUNNING or PAUSED has no effect (ignored, not an error). [Rev 1.1: self-clear timing is guaranteed to complete before any subsequent software read — see Design Specification Section 12.5.] |
| 2 | PWM_EN | RW | 0 | 1 = pwm_out[n] is driven per the PWM waveform rule (Design Specification Section 7.4). 0 = pwm_out[n] is held low regardless of COUNT/COMPARE; the channel still counts and can still generate interrupts. |
| 1 | CH_MODE | RW | 0 | 0 = One-Shot: on EXPIRED, channel returns to IDLE and CH_EN self-clears to 0. 1 = Periodic: on EXPIRED, channel auto-reloads from PERIOD and continues running without software intervention. [Rev 1.1: sampled live at the instant of each EXPIRED transition, not latched at LOAD — a write while RUNNING/PAUSED takes effect at the next EXPIRED evaluation. See Design Specification Section 12.2.] |
| 0 | CH_EN | RW | 0 | 1 = channel enabled; a 0→1 transition on this bit (with the channel currently IDLE) triggers LOAD, identically to a CH_START pulse. 0 = channel forced to IDLE immediately, regardless of current state; also self-clears to 0 automatically at the end of a One-Shot cycle. |

### CH3_PERIOD  —  Offset 0x54
Access: RW    Reset Value: 0x00000000
Channel 3 period (reload) value.

| Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| 31:16 | Reserved | RO | 0 | Reserved. Reads as 0. Writes ignored. |
| 15:0 | PERIOD_VAL | RW | 0x0000 | Value loaded into COUNT on every LOAD state entry. PERIOD_VAL = 0 is a legal boundary value: COUNT loads 0 and the channel expires on the very next prescaled tick. A write while the channel is RUNNING/PAUSED does not affect the current in-flight COUNT — it takes effect at the next LOAD. |

### CH3_COMPARE  —  Offset 0x58
Access: RW    Reset Value: 0x00000000
Channel 3 PWM compare/duty value.

| Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| 31:16 | Reserved | RO | 0 | Reserved. Reads as 0. Writes ignored. |
| 15:0 | COMPARE_VAL | RW | 0x0000 | While PWM_EN=1: pwm_out[n] is high while COUNT > COMPARE_VAL and low otherwise. COMPARE_VAL = 0 yields pwm_out[n] high for the entire period except at COUNT=0. COMPARE_VAL >= PERIOD_VAL yields pwm_out[n] continuously low for the entire period — both are legal configurations, not errors. A write while RUNNING/PAUSED takes effect at the next LOAD, matching PERIOD_VAL behavior. |

### CH3_COUNT  —  Offset 0x5C
Access: RO    Reset Value: 0x00000000
Channel 3 live counter value (read-only; inserts 1 APB wait state, Design Specification Section 5.3).

| Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| 31:16 | Reserved | RO | 0 | Reserved. Reads as 0. |
| 15:0 | COUNT_VAL | RO | 0x0000 | Current live count value of this channel's down-counter. Synchronized into the APB read path, which is why this register alone inserts one APB wait state. A write to this offset is a write to a fully read-only register and asserts PSLVERR. |

# 6. Interrupt Registers (0x60 – 0x6F)

### INT_STATUS  —  Offset 0x60
Access: RW1C    Reset Value: 0x00000000
Raw, per-channel interrupt status, write-1-to-clear.

| Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| 31:4 | Reserved | RO | 0 | Reserved. Reads as 0. Writes ignored. |
| 3:0 | CH_INT_STATUS[3:0] | RW1C | 0x0 | Bit n corresponds to channel n. Set by hardware on that channel's RUNNING→EXPIRED transition, independent of INT_ENABLE or GLOBAL_IE (masking only affects the irq output and GLOBAL_ISR, not this register). Cleared by software writing a 1 to the corresponding bit position; writing 0 to a bit has no effect on it. If a channel expires again on the same cycle its bit is being cleared, the set takes priority (the bit remains/becomes 1) — no expiry event may be silently dropped. |

### INT_ENABLE  —  Offset 0x64
Access: RW    Reset Value: 0x00000000
Per-channel interrupt enable mask.

| Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| 31:4 | Reserved | RO | 0 | Reserved. Reads as 0. Writes ignored. |
| 3:0 | CH_INT_EN[3:0] | RW | 0x0 | Bit n = 1 allows channel n's INT_STATUS bit to contribute to GLOBAL_ISR and the irq output. Bit n = 0 masks channel n's contribution; INT_STATUS[n] still latches normally and must still be cleared by software (masking is not the same as disabling event capture). |

# 7. Cross-Reference to Design Specification
FSM behavior driven by these registers (APB protocol FSM and per-channel counting FSM), interrupt aggregation logic, and reset semantics are defined in the companion PMTPC-4 Design Specification, Rev 1.0, Sections 5, 7, 8, and 9 respectively. This document defines field-level bit accuracy only; behavioral semantics should always be cross-checked against the Design Specification during test plan construction.
