# PMTPC-4 — Design Specification (micro-architecture)

Produced by the `design-architect` from [requirements.md](requirements.md) + the golden
[Design Rev 1.1](PMTPC-4_Design_Specification.md) / [Register Rev 1.1](PMTPC-4_Register_Specification.md).
Each `SPEC-*` item lists the `REQ-*` it satisfies. This is the implementation contract for the RTL.

## 1. Block structure (SPEC-ARCH-1 — Satisfies REQ-CORE-1, REQ-APB-1)

```mermaid
flowchart LR
  APB[APB Slave IF\nprotocol FSM + decode + PSLVERR] --> RF[Register File\n(PeakRDL regblock)]
  RF -->|hwif_out cfg| CH0[Channel Core 0]
  RF -->|hwif_out cfg| CH1[Channel Core 1]
  RF -->|hwif_out cfg| CH2[Channel Core 2]
  RF -->|hwif_out cfg| CH3[Channel Core 3]
  CH0 -->|count/expiry| RF
  CH0 & CH1 & CH2 & CH3 --> IRQ[Interrupt Aggregator]
  IRQ -->|irq| out1((irq))
  CH0 & CH1 & CH2 & CH3 -->|pwm_out n| out2((pwm_out 3:0))
  PRE[Prescaler\n16-bit shared] -->|tick_en| CH0 & CH1 & CH2 & CH3
```

Sub-blocks: `pmtpc4_apb_slave`, the generated `pmtpc4_regblock` (register file), `pmtpc4_prescaler`,
four `pmtpc4_channel`, `pmtpc4_irq_aggregator`, wired in top `pmtpc4`.

## 2. Clocking & reset (SPEC-CLK-1 — Satisfies REQ-SYNTH-2, REQ-RST-1, REQ-RST-2)
- Single domain `pclk`. No CDC.
- `presetn`: async assert, active-low → all flops to reset values, FSMs to IDLE, `pwm_out=0`, `irq=0`.
- `soft_reset` (from CTRL.SOFT_RESET, synchronous): clears channel cores + INT_STATUS; **preserves**
  PRESCALER, CLK_SEL, CTRL config, and the APB FSM/in-flight transfer. Self-clears after 1 cycle.
  **(2026-09-19 clarification, F5 audit — see reports/coverage_waivers.md "Tier 2"):** "preserves
  PRESCALER" means the prescaler block's entire state, including its free-running divider's phase
  (`pmtpc4_prescaler.sv`'s internal `cnt`) — not just the PRESCALER_VAL config register. An earlier
  RTL implementation zeroed `cnt` on `soft_reset`, which read REQ-RST-2's parenthetical scope
  ("clears ... (COUNT, FSM, INT_STATUS)") too narrowly and its exclusion clause ("NOT
  PRESCALER/CLK_SEL/APB FSM") too loosely — that exclusion is grouped with the APB FSM's own
  explicit in-flight-*state* preservation, which is the stronger reading. Fixed: `soft_reset` is now
  entirely unconnected from the prescaler's internal logic (RTL still wires the port through, for
  interface symmetry with every other channel-adjacent block, but the counter and `tick_en` are
  unaffected by it).
  **(2026-09-19 clarification, F6 audit — see reports/coverage_waivers.md "Tier 2"):** neither the
  golden design spec nor any REQ states what happens if a channel expiry lands on the exact same
  cycle as `soft_reset`. The implementation's choice — soft_reset wins, the expiry is not latched —
  is a deliberate design decision (`pmtpc4.sv` gates each channel's `hwset` input with
  `& ~soft_rst_pulse`), not one derived from stated spec text. Documented here because an earlier
  RTL/RDL comment incorrectly cited "Section 7.4" as mandating this outcome; Section 7.4 says
  nothing about it.

## 3. Prescaler (SPEC-PRE-1 — Satisfies REQ-CORE-6)
- 16-bit free-running divider `presc_cnt`. Generates a 1-`pclk`-wide `tick_en` pulse every
  `(PRESCALER_VAL+1)` cycles (PRESCALER_VAL=0 ⇒ every cycle). Shared by all channels so their ticks
  are aligned (enables true simultaneous expiry, REQ-INT-3).
- Mid-run PRESCALER_VAL change takes effect at the next tick boundary; the in-flight divide count is
  not corrupted (reload compare against the live value).
- Gated by `module_en` (frozen when MODULE_EN=0, SPEC-FREEZE-1).

## 4. Channel core FSM (SPEC-CH-1 — Satisfies REQ-CORE-1..5, REQ-CORE-7)
States: `IDLE, LOAD, RUNNING, PAUSED, EXPIRED` (3-bit enum). Advance only on `tick_en` except the
combinational control writes (CH_EN/CH_PAUSE) which are sampled continuously.

| Current | Condition | Next | Action |
|---|---|---|---|
| IDLE | CH_EN 0→1, or CH_START pulse while CH_EN=1 | LOAD | — |
| LOAD | (on tick) CH_PAUSE=1 | PAUSED | COUNT←PERIOD, then freeze (errata 12.1) |
| LOAD | (on tick) CH_PAUSE=0 | RUNNING | COUNT←PERIOD |
| RUNNING | CH_EN=0 | IDLE | immediate soft-disable (REQ-CORE-5) |
| RUNNING | CH_PAUSE=1 | PAUSED | freeze COUNT & pwm level (REQ-CORE-4) |
| RUNNING | (on tick) COUNT==0 | EXPIRED | raise `expiry` pulse |
| RUNNING | (on tick) COUNT>0 | RUNNING | COUNT←COUNT-1 |
| PAUSED | CH_EN=0 | IDLE | disable overrides pause |
| PAUSED | CH_PAUSE=0 | RUNNING | resume from frozen COUNT |
| EXPIRED | CH_MODE==0 (One-Shot) | IDLE | self-clear CH_EN (hw clears bit) |
| EXPIRED | CH_MODE==1 (Periodic) | LOAD | auto-reload (COUNT←PERIOD) |

Key design decisions (errata, normative):
- **SPEC-CH-PAUSE-1 (REQ-CORE-4 / errata 12.1):** CH_PAUSE is a level, sampled in LOAD/RUNNING/PAUSED.
  If set as LOAD completes → straight to PAUSED with COUNT=PERIOD.
- **SPEC-CH-MODE-1 (REQ-CORE-2 / errata 12.2):** CH_MODE read **live at the EXPIRED evaluation**, no
  shadow latch.
- **SPEC-CH-EN-1 (REQ-CORE-5):** CH_EN=0 forces IDLE from any state combinationally on the write.
- PERIOD/COMPARE writes while running take effect at next LOAD (registered snapshot at LOAD entry).
- PERIOD=0 ⇒ COUNT loads 0, expires the next tick (guard COUNT==0 in RUNNING right after LOAD).

## 5. PWM generation (SPEC-PWM-1 — Satisfies REQ-CORE-3, REQ-OUT-1)
- Combinational: `pwm_level = PWM_EN && (state != IDLE) && (COUNT > COMPARE_shadow)`.
  **(2026-09-19 correction — see reports/coverage_waivers.md "Tier 2" for the full audit trail.)**
  Originally written as `state==RUNNING||PAUSED`; corrected after an independent design/verification
  audit found that formula violates REQ-CORE-3 itself, which states the rule with **no state
  qualifier at all**: "output high while COUNT > COMPARE, low otherwise, gated by PWM_EN." During
  LOAD, `COUNT` already holds the just-reloaded PERIOD (the same cycle software can read it back via
  `CHx_COUNT`), so `COUNT > COMPARE` is a real, meaningful comparison there, not a don't-care — and
  excluding LOAD would make `pwm_out` disagree with a concurrent `CHx_COUNT` read, plus introduce a
  full extra prescaled tick of missing high time on every periodic reload (a measurable duty-cycle
  error, not a cosmetic one). This bullet's own second clause ("or channel IDLE", below) already
  implied the `!= IDLE` form — the two bullets were self-contradictory before this fix. EXPIRED is
  included by the `!= IDLE` form for uniformity only: `COUNT==0` throughout EXPIRED by construction
  (it is entered only when COUNT hits 0, and nothing touches COUNT again until the next LOAD), so
  `COUNT > COMPARE_shadow` is never true there regardless of the state condition — EXPIRED never
  actually produces a high level either way.
  Uses the *shadowed* COMPARE (COMPARE_shadow, latched at LOAD entry per §4), not the live COMPARE
  register — a mid-RUNNING/PAUSED write to COMPARE takes effect only at the next LOAD, matching the
  PERIOD shadow rule.
- Registered output `pwm_out[n]`. In PAUSED, `pwm_out[n]` holds its frozen level (COUNT frozen ⇒
  level stable). Forced low when `module_en==0` (SPEC-FREEZE-1) or channel IDLE (including the cycle
  immediately after a soft-disable takes the channel to IDLE — the registered output must not lag the
  state transition by even one cycle).
- COMPARE=0 ⇒ high whenever COUNT>0; COMPARE≥PERIOD ⇒ always low. Both legal.

## 6. Module-enable freeze (SPEC-FREEZE-1 — Satisfies REQ-CORE-8, errata 12.3)
- `module_en = CTRL.MODULE_EN`. When 0: `tick_en` is suppressed globally, so every channel's COUNT,
  FSM state, and any in-progress LOAD/EXPIRED evaluation hold. Externally `pwm_out=4'b0000` and
  `STATUS.BUSY=0`. When 1: channels resume exactly (a mid-EXPIRED channel completes its EXPIRED, incl.
  raising its interrupt, on the next tick). Distinct from soft-reset (which clears).

## 7. Interrupt aggregator (SPEC-INT-1 — Satisfies REQ-INT-1..3, REQ-CORE-7, REQ-OUT-2)
- `INT_STATUS[n]` set by `expiry[n]` (RUNNING→EXPIRED), independent of masking. W1C from APB, with
  **set-priority**: if `expiry[n]` and a W1C to bit n coincide, the bit stays/gets set (no drop).
  Implemented in the regblock via a hw-set + sw-woclr field with set precedence.
- `irq = GLOBAL_IE.GLOBAL_INT_EN & |(INT_STATUS[3:0] & INT_ENABLE[3:0])`.
- `GLOBAL_ISR.GLOBAL_INT_STATUS` = same expression (RO read-back).
- STATUS.BUSY = `|(channel busy)` where busy = state∈{RUNNING,LOAD,PAUSED}, and 0 while MODULE_EN=0.
  STATUS.READY = `module_en & ~soft_reset_active`.

## 8. APB slave FSM (SPEC-APB-1 — Satisfies REQ-APB-1..3, errata 12.4)
States `IDLE/SETUP/ACCESS`. In SETUP: latch PADDR/PWRITE/PWDATA, do address decode + legality:
- reserved region (0x18–0x1C, 0x68–0x6C, 0x70–0xFF) ⇒ `err`.
- write to fully-RO offset (0x04, 0x0C, any CHx_COUNT) ⇒ `err`.
- `PADDR[1:0]!=0` ⇒ `err`.
In ACCESS: on `err` → `PSLVERR=1, PREADY=1, PRDATA=0`, no register access (zero wait, errata 12.4).
On legal access → drive regblock; `PREADY=1` immediately except a CHx_COUNT **read**, which asserts
`PREADY=0` for exactly one cycle then completes (SPEC-APB-WAIT-1, REQ-APB-3). Back-to-back honored
(ACCESS→SETUP when PSEL stays high). The regblock's own CPU interface is driven behind this FSM (the
regblock uses PeakRDL apb3; the wait-state + PSLVERR shaping for reserved/RO/unaligned and the COUNT
read latch are added in `pmtpc4_apb_slave` around it).

## 9. Register→function map (SPEC-MAP-1 — Satisfies REQ-CORE-*, REQ-INT-*)
Config fields (regblock `hwif_out`) feed channels; status/count (regblock `hwif_in`) captured back.
Full bit-accuracy is the [SystemRDL](../rdl/pmtpc4.rdl); mapping summary:

| Field | Drives |
|---|---|
| CTRL.MODULE_EN / SOFT_RESET | global freeze / synchronous soft-reset pulse |
| PRESCALER_VAL | prescaler divide |
| CHx_CTRL.{CH_EN,CH_MODE,PWM_EN,CH_START,CH_PAUSE} | channel FSM control |
| CHx_PERIOD/COMPARE | reload + PWM compare |
| CHx_COUNT (hwif_in) | live COUNT read-back (1 wait state) |
| INT_STATUS (hw set/ sw w1c) | expiry latch |
| INT_ENABLE, GLOBAL_IE | irq masking/gating |
| STATUS (hwif_in), GLOBAL_ISR (hwif_in) | busy/ready, aggregated irq read-back |

## 10. Assumptions
APB master protocol-compliant; inputs synchronous to pclk (no metastability handling); all 4 channels
always present. Out of scope: sub-word access, multi-master, CDC, clock-gating, TrustZone (per Des §11).
