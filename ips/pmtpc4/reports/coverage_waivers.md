# PMTPC-4 coverage waiver list (with justification)

Signed-off record of every coverage item that is **not** hit and **why it is acceptable**. All
numbers are from the union `pmtpc4_full_test` run (seed 1). Statement/branch/condition come from
the normal build, DUT-scoped via `dv/pmtpc4_cov_exclusions.txt`. Code toggle comes from the
toggle-measurement build via `dv/pmtpc4_toggle_exclusions.txt`. Regenerate both with
`python3 flow/scripts/gen_exclusions.py ips/pmtpc4`; the toggle waivers and their justifications
live in `dv/pmtpc4_toggle_waivers.txt`.

## Final coverage — 2026-09-26 (41/41 seeded runs pass; UVM_ERROR=0, SVA=0, scoreboard errors=0; toggle build verified identical to the normal run)

| Metric | Score | Closure statement |
|---|---|---|
| Functional (type / instance) | 99.72% / 99.90% | **Closed.** The only residual is the signed-off `cg_apb.cp_wait.many` waiver below. |
| Code — statement (DUT) | 99.87% | 100% net of 1 unreachable FSM default (prescaler back in scope) |
| Code — branch (DUT) | 98.09% | 100% net of the documented unreachable branches |
| Code — condition (DUT) | 100% | **closed** |
| Code — toggle (DUT, hand-written RTL) | **93.47%** (458/490 bits) | **100% net of 1 documented constant net.** `pmtpc4_apb_slave`, `pmtpc4_channel` and `pmtpc4_prescaler` are all at 100%. The top level's only uncovered item is `cpuif_rd_data_pad`, which is always zero by construction; xsim lists it twice and no exclusion form removes the second copy. |
| Register-block toggle (`pmtpc4_regblock`) | **100%** (486/486) | Every bit of all 45 RAL fields was seen rising and falling in the DUT's own bus read-back (`reg_bit_toggle_cov`). This is the "option C" substitute for code toggle, which xsim cannot measure on a PeakRDL block. |

Sources: `reports/_cov/{functional,code}_report/`, `reports/_cov/toggle_summary.txt` (bit-weighted,
per file, with every uncovered row), `reports/_cov/reg_bit_toggle.txt`.

## 2026-09-26 toggle measurement correction (read this first — supersedes the toggle analysis below)

The earlier toggle analysis below concluded that the DUT's toggle was "permanently capped" by xsim
blind spots, and it waived about a dozen signals as tool artifacts. **That diagnosis was wrong.** A
controlled bisection isolated the real DUT from the testbench one ingredient at a time. It showed
that the testbench itself was corrupting xsim's toggle recording:

- **`$dumpvars` present anywhere in the design** stops toggle recording on some DUT nets. This held
  even inside an `if ($test$plusargs("DUMP"))` that never executes. It produced the prescaler's
  "No Toggles in Module" and the 0% on `start_trig` and `pwm_level`.
- **`bind`-ed white-box checkers** erase the toggles of every DUT net they observe. This is what
  zeroed `int_status_val`, `int_en_val`, `cpuif_addr`, the top-level `cpuif_wr_data` and
  `compare_shadow`.

**Fix (testbench only, no RTL change):**
- The binds and the dump each became their own top module: `tb/pmtpc4_binds.sv` and
  `tb/pmtpc4_dump.sv`.
- Code toggle is measured on a second snapshot, `pmtpc4_tcov`, built from `pmtpc4_tb_top` alone.
  It runs the same test and seed.
- `run_regression.py` verifies the two runs executed identically: same scoreboard check count
  (9041 = 9041) and same register-bit toggle totals (486 = 486).
- Every "tool artifact" waiver and the prescaler module exclusion were **removed**. All of those
  signals now measure, and toggle in both directions.

**What is genuinely beyond xsim**, all in the PeakRDL-generated register block:
- `automatic` next-value temporaries (153 entries) are listed as toggle points but never updated,
  and no exclusion form removes them.
- The nested-struct field flops (`field_storage` / `hwif_out`) are not instrumented for toggle at all.
- There is no bit-range exclusion.

Vivado 2026.1 documents no change to any of these. The register block is therefore excluded from the
*toggle* report only (it stays in statement/branch/condition), and it is measured instead by
`reg_bit_toggle_cov` plus `pmtpc4_reg_toggle_test`:
- the writable bits are bit-bashed;
- the `singlepulse` fields (`SOFT_RESET`, `CH_START`) are credited on the accepted write of 1 and
  the following read of 0;
- every hardware-set read-only bit is driven both ways while being read back: `COUNT` over two full
  0xFFFF periods, `BUSY`, `READY`, `GLOBAL_ISR` and `INT_STATUS`.

**Reporting fix:** the xcrg dashboard's toggle figure is an unweighted average over report *files*.
It always includes the UVM library's file (`xlnx_uvm_package.sv`) at 0%, which no `file -` or
`dir -` directive removes, so it is not a DUT metric. It read 65.31% for this very run. Toggle is
therefore reported bit-weighted from xcrg's own per-file tables (`toggle_summary.txt`).

## (Superseded 2026-09-26) Executive summary: why DUT toggle coverage cannot reach 100%

Functional coverage, statement coverage, branch coverage, and condition coverage are all closed
(100%, or accepted with a single named, signed-off waiver). **Toggle coverage (46.0%) is the one
metric that is permanently capped**, for four separate, unrelated, individually-confirmed reasons —
not one blocker, four small ones, each already tested against every fix technique available this
session (splitting a signal, inlining an expression, waiving by name):

| # | Cause | Example | Why it cannot be closed |
|---|---|---|---|
| 1 | **PeakRDL's `automatic` local variables** in the generated register file (~149 instances) | `next_c`, `load_next_c` | Re-computed fresh every time their `always_comb` block runs — not persistent storage (no flip-flop behind them). xsim's toggle instrumentation only tracks persistent signals; these are permanently invisible to the tool regardless of stimulus. Not a testing gap — a tool-scope limitation. |
| 2 | **Structurally-constant bits** in the generated register file | `is_valid_addr`, `is_valid_rw` | Hard-wired to `'1` because the APB wrapper already validates every access upstream. A signal tied to a constant cannot be asked to "toggle" — there is nothing to stimulate. |
| 3 | **Dead upper bits from a bus-width mismatch**, *inside* the PeakRDL-generated register file | `cpuif_rd_data`/`readback_data` bits `[31:16]` | Every register field in this chip is ≤16 bits, so the top half of the 32-bit data bus is always zero. Already fixed once at the top level (split into an active 16-bit half and an always-zero pad half, each separately waivable). Cannot apply the same fix *inside* the register file, because that file is PeakRDL-generated and this project never hand-edits generated files — a future regeneration would silently discard the edit. |
| 4 | **Tool blind spot on plain alias wires** (`wire X = expr;`, no flip-flop of their own) | `cpuif_wr_data`, `cpuif_addr`, `ch_expiry[3]` | Independently proven (via cross-checking other, unrelated coverage evidence from the same simulation run) that these genuinely change value — xsim's toggle instrumentation just doesn't see it. Normally fixed by waiving the name in the exclusion file, but `xcrg`'s waiver matching is by bare name across the *entire* design, not scoped to one instance — several of these names are reused on a different, correctly-tracked signal elsewhere, so waiving would silently delete that other signal's real coverage too (measured directly for `cpuif_wr_data`: waiving it moved the score *down*, not up). Left deliberately unwaived rather than "fixed" wrong. |

**2026-09-20 finding, added to this list because it generalizes**: the standard-looking fix for
case 4 — delete the named alias wire, write its expression directly at the one place it's used —
was tried on five signals (`int_status_val`, `int_en_val`, `masked`, `start_trig`, `pwm_level`)
and made the score *worse*, not better (one module's toggle score dropped from 100% to 40%).
Root cause: `xcrg` tracks toggle points for inline expression sub-terms separately from named
signals, and an anonymous expression has no name to put in a waiver directive. The one place this
technique *does* work (case 3's `cpuif_rd_data` split) replaces one wire with two other **named,
still-waivable** wires — a fundamentally different move from inlining into a bare expression. All
five signals were reverted back to named-wire form once this was measured (see "item 3" below for
the full sequence, including a *second*, independent bug this same investigation caught and
reverted before it reached simulation — a Yosys/`sv2v` toolchain bug that would have silently
truncated a 32-bit write-data path to 1 bit).

**Bottom line**: closing the remaining ~54% would require one of: (a) a newer xsim/xcrg build with
better toggle instrumentation for `automatic` locals and alias wires, (b) hand-editing a
PeakRDL-generated file against this project's own explicit policy (and losing the edit on the next
regeneration), or (c) broad wildcard waivers that would hide real coverage rather than exclude
known-dead bits — none of which this project is willing to do. 46.0% with every uncovered bit
individually classified and justified is treated as the honest, correct number, not a shortfall to
paper over.

**2026-09-19 correction (found by an independent verification-reviewer audit, not self-reported):**
`dv/pmtpc4_cov_exclusions.txt` was excluding `pmtpc4_top_sva` by its literal declared name, but that
module contains `generate` blocks and xsim elaborates its bound instance as `pmtpc4_top_sva_default` —
a third instance of the exact bug class already seen twice (an interface's default-modport suffix; an
interface's clocking block eliding as its own module). The exact-name directive silently stopped
matching post-elaboration, so testbench SVA code (all of `pmtpc4_top_sva`'s reset/interrupt coverage
and assertions) sat inside the DUT code-coverage denominator, understating branch/condition/toggle and
slightly overstating statement. Fixed generically in `flow/scripts/gen_exclusions.py` — every non-DUT
name is now wildcarded unconditionally rather than special-cased per construct a fourth time. Numbers
above are the regenerated, correct ones (statement barely moved; branch 97.46%->98.07%; **condition
97.65%->100%, i.e. it was already fully closed and the stale number was hiding that**; toggle
34.96%->39.85%). No DUT RTL or stimulus changed — this was purely a measurement-scope fix.

**History — why functional coverage went DOWN, then back up**: the 2026-09-16/17 P0 closure added
`option.per_instance=1` to `cg_fsm` (previously merged ch0-3's score, hiding real gaps) and a brand-new
`cg_pwm` covergroup, dropping the reported number from 97.78% to 91.82% — this made real, previously-hidden
gaps (`cg_fsm.cp_frozen_state`/mode-liveness on channels 1-3, and later 5 more new covergroups added
2026-09-18 for reset/prescaler/interrupt/APB-FSM) visible in the number for the first time, rather than
the model staying blind to them (bottoming out at 92.1% once all the new covergroups landed but before
their own bins were closed). Each of the 7 concrete gaps that number represented was then diagnosed
bin-by-bin against the live xcrg report and closed 2026-09-18/19 — 5 with real new stimulus, 2 cells
found structurally unreachable and moved to `ignore_bins` (below) — landing at 99.72%/99.80%, i.e. 100%
net of the one pre-existing `cg_apb.cp_wait.many` waiver. See `vplan.yaml`'s `VP-VERIF-FCOV` for the
full, current closure statement, and "Coverage-model bugs found and fixed" below for the two real bugs
(one stimulus-timing, one covergroup-bin-boundary) this closure pass found along the way.

**No RTL bugs.** Every waived item is unreachable by construction, a wrapper-bypassed net, or a
proven tool artifact. The APB/register-facing checkers are real and demonstrably catch injected bugs.
The channel-datapath checkers (COUNT value, `compare_shadow` value, PWM duty) are now ALSO real and
demonstrably catch injected bugs — see the 2026-09-16/17 P0 closure below, which specifically closed
the gap the original "Verification-quality findings" section (further down) identified.

**2026-09-15 closure iteration**: a full hole-by-hole audit (`reports/pmtpc4_coverage_holes_audit.xlsx`)
classified every uncovered item as Coverable, Waiver, or Needs-Investigation, with primary
justification against spec and secondary against RTL. Actioned: 12 new signals waived (below);
`compare_shadow` empirically proven a tool artifact via a temporary RTL trace (not assumed); one real
stimulus gap fixed (`ch_count` upper bits on channels 1–3, now 100%); one mixed active/dead signal
(`cpuif_rd_data`) resolved by an RTL split rather than left unwaivable.

**2026-09-16/17 P0 verification-quality closure**: implemented per `vplan.yaml`'s P0 backlog (itself
derived from this document's "Verification-quality findings" below) — new assertions
(`a_shadow_latches_input`, `a_count_loads_period`, `a_count_decrements`, `a_count_retained`,
`a_mode_live`) predicting from input ports rather than DUT-internal registers, plus a new `cg_pwm`
covergroup + checkers + `pmtpc4_pwm_duty_test`. Independently re-audited by a second, skeptical
verification-reviewer pass (2026-09-17) that re-seeded both original mutations from scratch
(reproduced exact failure counts) and ran 6 additional mutations to prove every new assertion
non-vacuous — see "Verification-quality findings" for the full independent audit. Two coverage-model
bugs found and fixed during closure: (1) the new `pmtpc4_pwm_cov.sv` testbench module was leaking
into the DUT-scoped code-coverage denominator because `gen_exclusions.py` wasn't re-run after adding
it to the filelist — fixed, DUT code numbers unaffected once corrected; (2) `cp_pwm_by_state.load_high`
was an unreachable bin masquerading as a real gap — proven structurally impossible (pwm is registered
one cycle behind its input, and S_LOAD lasts exactly one cycle) and moved to `illegal_bins`, matching
`idle_high`/`exp_high`'s existing pattern. Full 24/24 regression re-verified green after every change
in both rounds.

## Functional waivers

| Coverpoint / bin | Justification | Evidence |
|---|---|---|
| `cg_apb.cp_wait.many` (waits ≥ 2) | The APB completer inserts **at most one** wait state (one, only on a CHx_COUNT read; zero otherwise) by spec/errata 12.4. Two-or-more waits can never occur. | `pmtpc4_apb_slave.sv` PREADY logic; REQ-APB-3 |

**This one waiver sets the reported-number ceiling.** `xcrg`'s aggregate functional score is the
unweighted mean of the per-covergroup scores, and `cg_apb` cannot exceed 23/24 = 95.83% while
`cp_wait.many` is carried as a *waiver* rather than removed from the model. With every other
covergroup at 100%, the highest number the tool can print is therefore **(14×100 + 95.83)/15 =
99.72%**, i.e. *100% net of this one signed-off waiver*. It is deliberately **not** converted to an
`ignore_bins`: `cp_wait` lives in the reusable `vip/apb` VIP, where a completer inserting two or
more wait states is entirely legal — making it structurally impossible there would be wrong for
every other IP that uses the VIP. Read 99.72% as closure; read the bin list, not the mean.

## Functional `ignore_bins` — structurally unreachable functional-coverage cells

Functional-coverage impossibilities are removed **in the covergroup**, with the reasoning at the
declaration. They are deliberately *not* put in `dv/pmtpc4_cov_exclusions.txt` — that file is
`xcrg`'s **code**-coverage exclusion list and has no notion of a covergroup bin.

| Cross / cell | File | Justification |
|---|---|---|
| `cg_pwm.x_period0` — `(cp_period_at_load.zero, cp_expired_after.many)` | `dv/sv/sva/pmtpc4_pwm_cov.sv` | `a_period0_expires` (same file) asserts `per_at_load==0 \|-> ticks_since_load <= 2`, and `cp_expired_after.one_tick` is already `illegal_bins` (EXPIRED is reachable only from S_RUNNING, which costs the S_LOAD tick first). PERIOD=0 therefore reaches EXPIRED in **exactly** 2 ticks; a "many" sample would be an *assertion failure*, not a coverage hole. The assertion is the check; the `ignore_bins` is only the matching coverage statement. |
| `cg_pwm.x_period0` — `({one,smallp,largep}, cp_expired_after.two_ticks)` | `dv/sv/sva/pmtpc4_pwm_cov.sv` | A full expiry costs exactly **(PERIOD+2)** ticks by RTL construction (`rtl/pmtpc4_channel.sv`): S_LOAD consumes one `tick_en` to reach S_RUNNING *without touching COUNT*, then S_RUNNING needs (PERIOD+1) more ticks to walk COUNT from PERIOD down to 0 and observe `count=='0`. So `ticks_since_load == PERIOD+2 ≥ 3` for every nonzero PERIOD — only PERIOD==0 can ever land in `two_ticks`. Same accounting `pmtpc4_prescaler_vseq::time_expiry`'s bound already uses. **No stimulus was fabricated for these cells**; 4 of the cross's 8 cells were open and all 4 are in these two classes. |

## Coverage-model bugs found and fixed (NOT waivers — these were wrong bins, not hard gaps)

- **`cg_fsm.cp_frozen_state.expired` read 0 hits on all four channels despite two dedicated,
  passing-their-own-checks attempts — a genuine STIMULUS-TIMING RACE, not a tool artifact or an
  unreachable bin.** EXPIRED is exactly one `tick_en` wide before the FSM auto-advances (to LOAD if
  periodic, IDLE if one-shot). The original `pmtpc4_freeze_states_vseq::freeze_from_expired()` reached
  for that window with a fixed `cyc(95)` guess and then spent a whole extra APB READ (an INT_STATUS
  check) *before* issuing the freeze write — two sequential APB/RAL transactions' worth of UVM
  sequencer/driver/monitor latency is not reliably faster than one ~21-cycle tick period, so the
  freeze (`CTRL=0`) could land *after* the next `tick_en` had already moved the FSM out of EXPIRED.
  The bug was invisible to the test itself because `INT_STATUS` is a **sticky, latched** bit — "must
  have already latched its expiry" kept passing even though the FSM had already moved on, and the
  subsequent COUNT-stability check still passed too (it was just proving a freeze from IDLE/LOAD, not
  from EXPIRED). Fixed by polling `INT_STATUS` directly (`wait_expiry()`, returns within one APB read
  of the actual expiry edge) and issuing the freeze write as the very next bus transaction with no
  read in between, plus a deliberately slow dedicated prescaler (`EXP_PRESC=63`, a 64-cycle window)
  for margin; each call now also asserts a DISCRIMINATING check that the freeze genuinely landed in
  EXPIRED — `COUNT` still reads 0 (true for either mode: S_LOAD loads `count<=period`, nonzero, and
  S_RUNNING transitions OUT to EXPIRED on the exact tick that would first observe `count=='0`, so
  RUNNING is never itself observed holding 0) — rather than trusting the coverage report to say so.
  `freeze_from_load`/`freeze_from_paused` got the analogous LOAD-window fix (a `SOFT_RESET` pulse
  zeroes the shared prescaler's own counter immediately before starting the channel, so the next tick
  is a *known* offset away instead of an arbitrary phase) and are now run on all four channels, closing
  `cp_frozen_state.{load,paused,expired}` everywhere.
  **2026-09-19 correction (verification-reviewer):** the first version of this fix used `CH_EN==1` as
  the *sole* one-shot discriminator, which a mutation audit proved non-discriminating — `CH_EN` also
  reads 1 throughout LOAD/RUNNING/PAUSED, so it cannot tell an EXPIRED freeze from an early one; only
  the periodic branch's `COUNT==0` check was actually catching a reverted-fix mutation (2 errors on
  CH1/CH3; CH0/CH2's one-shot check passed silently despite the freeze landing in RUNNING). Fixed by
  using `COUNT==0` for both modes (`CH_EN==1` kept as a secondary, non-discriminating sanity check for
  one-shot only). Re-verified: 37/37 green, and `cp_frozen_state.expired` is still hit on all 4 channels.
- **`cg_selfclr.cp_read_latency.immediate_next_transfer` was an unreachable bin, mis-read as a
  stimulus gap.** The bins were `{[0:19]}` / `{[20:$]}` ns, but the latency is measured between two
  transfers' *completion* instants (the APB monitor publishes an item on the clock edge that ends
  its ACCESS phase) and an APB3 transfer occupies a minimum of **two** clocks (SETUP + ACCESS) — so
  the smallest gap any stimulus can produce is exactly 20ns at 100MHz, and `< 20ns` was impossible.
  The intent was always "within two clock periods"; boundary corrected to `{[0:20]}` / `{[21:$]}`
  (`dv/sv/env/pmtpc4_coverage.sv`), and `pmtpc4_selfclear_vseq` now also issues each
  self-clearing write and its read-back as one **back-to-back** APB pair
  (`apb_agent_cfg.b2b_enable` + `raw_b2b()`), which is the genuine minimum-latency observation
  errata 12.5 is about. That closes the bin *and* the 5 `x_selfclr` cells it was blocking, and it
  strengthens the errata-12.5 claim rather than merely relabelling it.
- **`cg_presc.x_presc.(div1, changed_midrun)` needed a specific legal scenario, not more of the
  same.** With PRESCALER_VAL=0 the prescaler's `cnt >= prescaler_val` is true every cycle, so
  `tick_en` is asserted *every* cycle and `pmtpc4_presc_sva` re-latches
  `presc_at_interval_start` (clearing `presc_changed_midrun`) on the very cycle a new PRESCALER
  value appears — a free-running div1 interval can never observe a change. The one legal way is to
  **suspend** the interval: MODULE_EN=0 freezes the prescaler (errata 12.3) while leaving
  `presc_at_interval_start`=0 intact, so a PRESCALER write taken during the freeze is a genuine
  mid-interval change of a div1 interval once the module resumes. Added as
  `pmtpc4_prescaler_vseq::div1_changed_midrun()`. Not a waiver: the cell is real and now hit.

## Checker robustness corrections (found by new stimulus, not by inspection)

- **`a_pwm_stable_in_paused` (`dv/sv/sva/pmtpc4_pwm_cov.sv`) antecedent narrowed to require TWO
  consecutive PAUSED cycles.** The new `pmtpc4_pwm_shadow_vseq::compare_write_while_paused()`
  parks a channel in PAUSED by entering it straight from LOAD (errata 12.1 — CH_EN|CH_PAUSE written
  together), which is an entry path no earlier test used; every earlier test entered PAUSED from
  RUNNING. `pwm` is `pwm_q`, registered one cycle behind `pwm_level`, and S_LOAD lasts exactly one
  cycle — so on the **first** PAUSED cycle `pwm_q` still carries the value computed while the FSM
  was in S_IDLE (`ch_active=0` ⇒ low) and settles to the level implied by the frozen COUNT on the
  second. That produced exactly one failure per channel (4 total) on otherwise-correct RTL. This is
  the *same* one-cycle registration artifact already documented for
  `cg_pwm.cp_pwm_by_state.load_high` (moved to `illegal_bins` on the same reasoning in the
  2026-09-17 pass), not a violation of Design 7.3: the invariant is about the level being *held*,
  and the level is not established until `pwm_q` has had its one cycle. Requiring two consecutive
  PAUSED cycles states that precisely and costs no sensitivity — any `pwm` change during a
  sustained PAUSED still fires, which is the mutation class the assertion was written for.

## Statement / branch waivers (documented — xsim `-ccExclusionFile` has no line/block granularity)

These are unreachable-by-construction; xsim's exclusion file supports only module/signal scope, so
they cannot be tool-excluded and are accounted for here instead. They are the entire residual of the
99.88% statement / 98.07% branch DUT scores.

| # | Location | Item | Justification |
|---|---|---|---|
| 1 | `pmtpc4_channel.sv:129` | `default: state <= S_IDLE;` (statement + its branch) | Defensive default of a `case` over a fully-enumerated 3-bit FSM; all legal states are covered. Reachable only on an illegal state encoding that cannot occur. |
| 2 | `pmtpc4_regblock.sv` Br 9/10 | `CTRL.SOFT_RESET.load_next` MISSING ELSE | SOFT_RESET is a self-clearing (singlepulse) field: PeakRDL asserts `load_next` every cycle to auto-clear it, so the "don't load" else-leg is unreachable (TRUE 9514 / FALSE 0). |
| 3–6 | `pmtpc4_regblock.sv` Br 45/46, 81/82, 117/118, 153/154 | `CHx.CH_CTRL.CH_START.load_next` MISSING ELSE (ch0–ch3) | Same self-clearing-field pattern for CH_START on all four channels. |

## Toggle waivers — whole-signal, tool-excluded via `signal -<name>`

Each is an entire DUT net that cannot toggle by construction. Excluding them lifted DUT toggle
24.63% → 26.13% → 38.6% across two rounds (2026-09-07 baseline, then 2026-09-15).

| Signal(s) | Module | Justification |
|---|---|---|
| `cpuif_wr_biten` | regblock / top / apb_slave | Wrapper drives it constant `32'hFFFF_FFFF` (word writes only); never toggles. |
| `cpuif_req_stall_wr`, `cpuif_req_stall_rd` | regblock | Regblock is single-cycle; the wrapper never stalls it. |
| `cpuif_rd_err`, `cpuif_wr_err`, `decoded_err` | regblock | `pmtpc4_apb_slave` resolves all PSLVERR/decode itself (`cpuif_req = complete & ~err`) and forwards only legal accesses, so the regblock never sees an error. |
| `is_valid_addr`, `is_valid_rw` | regblock | Wrapper forwards only already-validated accesses. |
| `readback_err` | regblock | No errored readback ever reaches the regblock readback mux. |
| `cnt` | prescaler | **Tool artifact, not a real hole.** `pmtpc4_prescaler.sv:31 cnt<=cnt+1` executes 973× (proven in the statement report), so `cnt` provably increments, yet xsim reports its toggle as 0% while every other internal reg toggles. The `signal -cnt` waiver is present but xsim did not honor it, so prescaler toggle still reads 0% in the report — a documented tool sampling artifact, not an RTL or stimulus gap. |
| `tick_en` | prescaler | Same tool artifact as `cnt` — xcrg's raw report for this module literally reads "No Toggles in Module" (zero toggle-trackable variables found at all), a stronger statement of the same instrumentation gap. Added for documentation parity with `cnt`. |
| `next_c`, `load_next_c` | regblock (76 fields × 2) | PeakRDL-generated `automatic logic` locals inside `always_comb`, one pair per register field — procedural temporaries, not persistent nets, structurally outside what toggle coverage can instrument. **Justification holds; mechanical effect does not** — isolated testing shows removing this exclusion changes the aggregate score by only 0.01pp (38.60%→38.59%), i.e. xcrg is not actually honoring it despite correct formatting. This is why `pmtpc4_regblock` reports such a low toggle score: ~150 of its ~155 "uncovered" entries are these two names. |
| `cpuif_addr`, `decoded_wr_biten` | regblock | Pass-through aliases of the address/biten ports (`assign cpuif_addr = s_cpuif_addr;` etc.). cg_apb independently proves 31/31 address bins and 1579 write hits — the alias's 0/0 toggle report contradicts that evidence from the same database; a pass-through-alias tool limitation. |
| `readback_data_var` | regblock | Same PeakRDL `automatic` pattern as `next_c` (whole-signal 0/0, no mixed active bits — safe to exclude wholesale, unlike its sibling `readback_data` below). |
| `start_trig`, `pwm_level` | channel (×4 instances) | Continuous-assign `wire` booleans. `start_trig` gates channel.sv:85, whose branch table shows 8–16 TRUE hits per instance — contradicts the 0/0 toggle report. Same alias-tracking limitation. |
| `int_status_val`, `int_en_val` | top | Continuous-assign `wire` aliases of `hwif_out.INT_STATUS`/`INT_ENABLE`. cg_apb proves GISR/GIE/INTSTAT/INTEN all accessed; irq_test exercises interrupts explicitly. Same alias-tracking limitation. |
| `compare_shadow` | channel (×4 instances) | **Empirically proven tool artifact, not assumed.** A targeted vseq drove COMPARE=0xBEEF→0→0xBEEF→0 through repeated LOAD triggers on every channel; still 0/0. A temporary RTL `$display` at channel.sv:87 (since reverted) confirmed `compare` genuinely carries 1/8/f/beef/0 repeatedly at the exact latch point (49 executions, including the added stimulus's explicit beef→0 cycles) — the register demonstrably changes value in hardware. xsim simply doesn't observe it. **The stimulus task itself was subsequently deleted** (see Verification-quality findings below) — it was redundant with `pmtpc4_toggle_vseq` and structurally unobservable (PWM was never enabled during it), so it added no checking value; this toggle waiver stands independent of that task's existence. |
| `cpuif_rd_data_pad` | top | See "Mixed active/dead signals" below — the dead half of an RTL split. **Not confirmed effective** (see below) — kept for audit-trail completeness. |

## Mixed active/dead signals — resolved by RTL split, not left unwaivable

Some signals mix genuinely-active bits with structurally-dead ones (e.g. a 16-bit register field
read back through a 32-bit APB word). xsim's exclusion file has **no bit-range syntax** — confirmed
by direct empirical test (`signal -ch_count[31:16]` in the exclusion file produces `WARNING: Signal
Name 'ch_count[31:16]' ... is not declared in the given design. Hence, it is ignored.`) and by AMD's
own docs (UG937 "Code Coverage Exclusion Support", UG900 "Code Coverage Support" — both document only
module/instance/signal/dir/file granularity, no bit-select). A blanket whole-signal exclusion would
discard the real, active-bit coverage right along with the dead padding.

**`cpuif_rd_data` (top, `pmtpc4.sv`) — fixed 2026-09-15.** Split into two independently-declared
16-bit signals: `cpuif_rd_data_active` (real field-readback bits) and `cpuif_rd_data_pad` (always
zero — no register/field in this map exceeds bit 15, verified against every `readback_data_var`
write in the generated regblock). The original 32-bit wire was eliminated entirely — both the
regblock output port and the APB-slave input port now connect directly via
`{cpuif_rd_data_pad, cpuif_rd_data_active}` — so there is no redundant signal left to either miss or
over-waive. Re-verified: `cpuif_rd_data_active` now reports 100% covered independently — **this half
of the fix works and is confirmed.** `cpuif_rd_data_pad`'s `signal -` exclusion, however, is **not
honored by xcrg** — confirmed by direct testing (reproduced in complete isolation with a single-line
exclusion file containing only that one directive; the signal still appears as uncovered in the
report). This joins the same unresolved class of tool behavior already documented for
`cnt`/`is_valid_addr`/`is_valid_rw` above. The measured toggle improvement this session (26.13% →
38.6%) comes entirely from `cpuif_rd_data_active` now being correctly, independently tracked — not
from `cpuif_rd_data_pad` leaving the denominator, which it hasn't.

**`pmtpc4_regblock.sv`'s own internal `readback_data`/`cpuif_rd_data` — NOT split, left as documented
residual.** `pmtpc4_regblock.sv` is **PeakRDL-generated** (`rdl/generated/rtl/`); hand-editing
generated output is against this project's convention (a future `peakrdl regblock` regen would
silently discard the edit and reintroduce the identical gap invisibly). The same-named signal inside
regblock is therefore left alone, matching the "do not over-waive" precedent already established for
this exact pattern before this session.

## Why the aggregate toggle score is 38.6%, not higher (2026-09-16 breakdown)

Per-module toggle after this session's fixes: `pmtpc4_apb_slave` 100%, `pmtpc4_channel` 100%,
`pmtpc4` (top) 90.4%, `pmtpc4_regblock` ~18%, `pmtpc4_prescaler` 0%. The aggregate is pulled down
hard by `pmtpc4_regblock`, because it's by far the largest file (642 statements vs. channel's 44,
top's 22, prescaler's 13) — it dominates the weighted average.

**`pmtpc4_regblock`'s ~18% is not ~18% of real unexercised behavior.** Isolated testing (see the
`next_c`/`load_next_c` waiver above) shows ~150 of its ~155 "uncovered" toggle entries are the
`automatic`-local `next_c`/`load_next_c` pair per field — structurally incapable of ever toggling,
correctly identified and waived in principle, but the waiver's mechanical effect on the score is
**not honored by xcrg** (removing the two exclusion lines changes the score by only 0.01
percentage point). The score looks catastrophic; the actual unaddressed residual is not. Once you
subtract the mismeasured `next_c`/`load_next_c` noise, regblock's real, genuine, not-yet-closed
residual is just two items — its own internal `readback_data`/`cpuif_rd_data` mixed active/dead
bits (the same pattern fixed at the top level via an RTL split, blocked here because the file is
PeakRDL-generated) — plus whatever field-storage bits are parked at their reset value because no
stimulus in the suite ever drives that particular field's hardware-write path to a second value
(e.g. RO status bits mirroring a hardware condition the testbench never forces).

**`pmtpc4_prescaler`'s 0% is entirely the same tool artifact already documented for `cnt`** — the
module's raw toggle report literally says "No Toggles in Module," meaning xcrg found zero
toggle-trackable variables in it at all, not that stimulus is missing (a 973×-executed
`cnt<=cnt+1` proves otherwise).

**`pmtpc4` (top)'s remaining ~10% is `cpuif_rd_data_pad`** — confirmed structurally dead (every
register field in the map is ≤16 bits), correctly split out via RTL, but its exclusion is (like
`next_c`) not honored by the tool.

**Bottom line: there is no large pool of genuinely-unexercised toggle behavior hiding in this
38.6% number.** The overwhelming majority of the gap between 38.6% and 100% is `xcrg` not honoring
`signal -` exclusions for specific signal classes (confirmed for `next_c`/`load_next_c`,
`cpuif_rd_data_pad`, `cnt`, `tick_en`, `is_valid_addr`, `is_valid_rw` — a broader and more
consequential instance of a pre-existing, previously-underestimated tool limitation), not missing
stimulus. The channel and apb_slave modules — where exclusions were confirmed to actually work —
reached 100%.

## Toggle residual (NOT waived — kept honestly in the denominator)

- **`pmtpc4_regblock.sv`'s internal `readback_data`/`cpuif_rd_data`** — mixed active/dead bits, tool
  offers no bit-range exclusion, generated file so not RTL-splittable. See above.
- **Parked storage / reserved bits** — field storage bits that only ever hold their reset value
  (RO/reserved fields), which no stimulus can flip.

A full-range toggle stimulus (`pmtpc4_toggle_vseq`: walking-1/0, AA/55 on every PERIOD/COMPARE, PWM
active on all channels, free-running prescaler) is in the suite; measured effect on DUT toggle beyond
the fixes above was negligible because `pmtpc4_cov_close_vseq` already exercises the reachable
datapath — confirming the remaining residual is structural, not a missing test.

## Verification-quality findings (2026-09-15, `verification-reviewer`) — NOT resolved this session

A coverage number moving is not the same as the underlying behavior being verified. A full
mutation-testing pass on this session's changes found real gaps, holding sign-off on the DV
environment even though the coverage numbers above are accurate and the regression is green:

- **COUNT's loaded value is completely unchecked.** The scoreboard's `readmask()` returns `-1` for
  `CH_COUNT` (reads are skipped from prediction entirely), and the existing pause/freeze vseqs that
  read `CH_COUNT` only compare it to itself (stability/change), never to the programmed PERIOD. A
  deliberately seeded off-by-one on the PERIOD→COUNT load (`count <= period + 1`) survived a full
  green regression. This session's `ch_count` toggle fix (channels 1–3's upper bits, now 100%) is
  real, additional stimulus — the first anywhere in the suite to drive a large PERIOD into COUNT on
  those channels — but it closes the toggle *number* without the scoreboard having anything to say
  about whether the loaded value is *correct*. Recommend: either extend the scoreboard to predict
  `CH_COUNT` reads, or add an SVA property asserting `count == period` immediately following a
  LOAD-triggering edge.
- **`compare_shadow`'s latched *value* is unverifiable, only its *timing*.** The channel-level SVA
  (`pmtpc4_channel_sva.sv`'s `a_pwm_rule`) rebuilds its expected PWM by reading the DUT's own
  `compare_shadow` — a white-box mirror that is structurally blind to the shadow register holding the
  wrong *value* (a deliberately seeded `compare_shadow <= '0` at both latch points survived a fully
  green regression), even though it correctly catches a shadow-vs-live-input *timing* mistake (a
  deliberate swap to comparing against live `compare` instead of the shadow was caught immediately,
  112 SVA failures). Compounding this: nothing in the environment observes `pwm_out` from a black-box
  perspective at all.
- **`pmtpc4_channel`'s reported toggle "100%" is a claim about 8 bits, not the channel datapath.**
  Waiving `compare_shadow`/`pwm_level`/`start_trig` (all confirmed tool artifacts, not stimulus gaps —
  see above) left only 4 one-bit signals in the module's toggle model (`ch_en_rise`, `ch_active`,
  `ch_en_q`, `pwm_q`); `count`, `state`, `expiry`, and others aren't independently toggle-instrumented
  at this scope. Accurate, but don't read "channel toggle 100%" as "channel datapath toggle closed."
- **The RTL split's own correctness *is* verified** — a deliberately seeded bit-order swap in the new
  `{cpuif_rd_data_pad, cpuif_rd_data_active}` concatenation was caught immediately by the scoreboard
  (three distinct error classes within 625 ns of simulation time). This one is trustworthy.
- **The vPlan's functional coverage model is largely unimplemented, independent of this session.**
  `vplan.yaml` declares 17 covergroups; only 3 exist in the environment (`cg_cfg`, `cg_fsm`, `cg_apb`),
  none sharing a name with anything in the plan. Every one of the vPlan's 25 items is hand-marked
  `status: covered` regardless. Most notably, `cg_pwm` (duty cycle vs. COMPARE/PERIOD, exactly the
  behavior discussed above) does not exist. This predates this session's changes and is out of this
  iteration's scope (toggle-coverage housekeeping), but is a materially larger, separate body of work:
  implementing the missing covergroups and correcting the vPlan's self-reported status against what's
  actually implemented.

**Bottom line from the review: the APB/register half of this environment is real and demonstrably
catches bugs (multiple mutations caught within microseconds); the channel-datapath half (COUNT value,
compare_shadow value, PWM output) currently is not, and the coverage model doesn't yet reflect the
vPlan closely enough to catch that gap on its own.** 23/23 green remains an accurate statement about
the checks that exist — it is not yet a complete statement about the IP's behavior.

> **RESOLVED 2026-09-16/17.** The COUNT-value and `compare_shadow`-value gaps identified above were
> closed by the P0 backlog this finding fed into (`vplan.yaml` VP-CH-COUNT-VALUE, VP-PWM-SHADOW-VALUE,
> VP-PWM-DUTY) — see the "2026-09-16/17 P0 verification-quality closure" note near the top of this
> document, and the independent re-audit below this box, which specifically re-tested the claims in
> this section and confirmed the fix. PWM output remains genuinely open at the black-box level
> (`VP-PWM-BLACKBOX` — nothing subscribes to `pwm_out` from outside the DUT); that part of this
> finding still stands.
>
> ---
>
> ## Independent re-audit of the P0 closure (2026-09-17, second verification-reviewer pass)
>
> Verdict: **the checkers are real. The coverage number briefly wasn't, but is now.**
>
> - Re-seeded both original mutations (`compare_shadow <= '0` at both latch points;
>   `count <= period + 1`) from scratch, independently. Reproduced the test-writer's exact failure
>   counts: 244 (`a_shadow_latches_input`) + 2728 (`a_pwm_matches_independent`) for the first; 94
>   (`a_count_loads_period`) + 58 (`a_duty_full_low`/`a_duty_matches_cmp`) for the second.
> - Ran 6 further mutations the closure work never tried, to prove non-vacuity rather than trust
>   compilation: `count <= count-2` (caught, 13344 failures), COUNT-not-cleared-on-soft-disable
>   (caught, 73 failures — the specific REQ-CORE-5 clause `VP-CH-DISABLE` used to flag as unchecked),
>   two live-CH_MODE variants (one caught at 309+346 failures, one a genuine, separately-tracked
>   stimulus hole — CH_PAUSE during EXPIRED at a tick_en edge is never exercised by any test), a
>   dropped PWM_EN gate (caught, 458 failures across three assertions), and a dropped freeze-hold
>   (caught, 7113 failures, confirming the *pre-existing* `a_freeze_hold` is still live). Every new
>   assertion fired on a targeted mutation; none false-fired across 24/24 clean runs.
> - Confirmed all 3 claimed xsim/timing bug fixes from the closure work are real, not sensitivity
>   quietly traded away: reverted each to its naive form on known-good RTL and counted false
>   failures (6497 / 19 / 127 respectively) — every one was a genuine bug, not a convenience choice.
> - Found `a_pwm_matches_independent` is independent of `compare_shadow` (provably — that's the whole
>   point, and it works) but **not** independent of `count` or the FSM `state` register — the checker
>   *ensemble* is independent of any single DUT register, but no single assertion is a true black-box
>   check. `VP-PWM-BLACKBOX` remains genuinely open on this basis, not closed by the new work.
> - Found the new `cg_pwm` module (testbench code) was leaking into the DUT-scoped code-coverage
>   denominator — `gen_exclusions.py` had not been re-run after adding it to the filelist. Fixed;
>   confirmed the true DUT code-coverage numbers are unaffected once corrected (same as pre-P0).
> - Certified specific `vplan.yaml` promotions from `planned` to `covered` (with residuals split out
>   into new, honestly-`planned` items rather than folded back in) — see `vplan.yaml` directly for
>   the item-by-item ruling; this document's summary table above reflects the outcome.
> - One process hazard surfaced during this audit, unrelated to the IP itself: a concurrent session
>   running `xelab`/`xsim` against the same shared `ips/pmtpc4/dv/sv/xsim.dir` mid-audit silently
>   corrupted 22 of 24 runs in this reviewer's first attempt. **Do not run two agents against this
>   IP's regression concurrently** — the audit was redone in an isolated copy to get a trustworthy
>   result, but the shared-directory hazard itself is not fixed and will recur.

## 2026-09-19 independent re-audit of the 92.1%->99.72% closure pass

A second, focused verification-reviewer pass (scoped to only the files this closure pass touched, not
a full environment re-audit) found 2 blocking and 6 minor issues. The 2 blocking ones are fixed and
re-verified (37/37 green) — see their notes inline above (`cg_fsm.cp_frozen_state.expired`'s
discriminating-check fix, and this section's code-coverage correction). Of the 6 minor findings:

**Fixed:**
- `cg_pwm.x_period0`'s two structurally-unreachable cells changed from `ignore_bins` to `illegal_bins`
  (both are backed by a live checker — `a_period0_expires` and `a_count_loads_period`/
  `a_count_decrements` respectively — so a real violation now surfaces as a bin-hit error instead of
  silently vanishing; matches the sibling `cp_expired_after.one_tick` pattern already in the same file).
- `cg_selfclr.cp_read_latency.immediate_next_transfer` tightened from `{[0:20]}` to exactly `{20}`,
  with `{[0:19]}` now `illegal_bins` — the old range still silently admitted the impossible <20ns
  gap, so a future timing regression would have been misread as extra coverage rather than flagged.
- `vplan.yaml`'s `covergroup_inventory.cg_pwm` entry was missing `cp_period_at_load`,
  `cp_expired_after`, `cp_cmp_write_timing`, `cp_per_write_timing`, `x_period0`, `x_cmp_write_duty` —
  added 2026-09-18/19 to the same file but never listed in the "authoritative name<->file map".

**Acknowledged, not fixed (honest residuals, not hidden):**
- `pmtpc4_async_reset_vseq::light_reset_check()` reads all 4 channels' `CH_CTRL` on every one of the
  30 state x phase sweep iterations, but `arm_state()` only ever arms channel 0 — so 3 of those 4 reads
  (all 4 for the IDLE case) are trivially true rather than discriminating. `x_reset`'s closure itself is
  unaffected (`cg_reset` samples independently via SVA on `negedge presetn`), and CH0's own check plus
  STATUS remains real discrimination; this is a weaker in-test guard than the header comment claims,
  not a false coverage credit.
- `a_pwm_stable_in_paused`'s two-consecutive-PAUSED-cycle gating (narrowed to work around a genuine
  one-cycle `pwm_q` settle artifact on LOAD->PAUSED entry) also exempts the first PAUSED cycle on
  RUNNING->PAUSED entry, where the artifact does not apply — a real but narrow sensitivity gap on that
  specific one-cycle window, not on sustained PAUSED. Tightening it to gate only the LOAD-entry path
  is the correct fix but was not attempted this pass to avoid rushing a change to an assertion's timing
  without the same re-verification rigor the rest of this pass got.
- `reports/_cov/code_report/functionalCoverageReport/` (as opposed to the `functional_report/` dir the
  vPlan actually cites) contains a stale, truncated report from an earlier `xcrg` run that died mid-write
  — anyone opening that specific directory by hand would read pre-fix numbers. The evidence chain used
  by this document and `vplan.yaml` is unaffected (both cite `functional_report/`), but the stray
  directory is a housekeeping trap for the next person who doesn't know which path is authoritative.
- This repo is not under version control, so file mtimes (not diffs) were the only way to confirm which
  files a given pass touched — sufficient for this audit, but a process gap worth closing before the
  next one (e.g. `git init` so future closure/review passes get real diffs).

## 2026-09-19 toggle-coverage deep-dive (why 39.9%, hole-by-hole)

Per-module breakdown (DUT-scoped, from the corrected exclusion file, `reports/_cov/code_report`):

| Module | Toggle score | Total bits | Covered | Status |
|---|---|---|---|---|
| `pmtpc4_apb_slave` | 100% | 16 | 16 | closed |
| `pmtpc4_channel` (x4 instances) | 100% | 8 | 8 | closed |
| `pmtpc4` (top) | 60.61% | 452 | 274 | residual, all classified (below) |
| `pmtpc4_regblock` (PeakRDL-generated) | 18.4% | 1282 | 236 | residual, all classified (below) |
| `pmtpc4_prescaler` | N/A — **"No Toggles in Module"** | — | — | whole-module tool blind spot |
| `pmtpc4_regblock_pkg` | N/A (0 statements too) | 0 | 0 | empty package (typedefs only), not a gap |

`pmtpc4_apb_slave` and `pmtpc4_channel` are genuinely, fully closed this session (were not before). The
39.85% aggregate is dragged down almost entirely by `pmtpc4_regblock` and `pmtpc4_prescaler`, which is
exactly what `vplan.yaml`'s `VP-CODECOV-TOGGLE` gap text already said (`"regblock ~18%, prescaler 0%"`)
— today's audit is a fresh, line-by-line re-verification of that claim, not a new discovery of decline.

**`pmtpc4_regblock`'s 1046 uncovered bits, classified:**

| Category | Count | Bits (approx.) | Classification |
|---|---|---|---|
| `next_c` / `load_next_c` (PeakRDL `automatic` procedural temporaries, one pair per field) | 76 declarations (38 fields) | 214 (RTL-verified via `grep` on `pmtpc4_regblock.sv`) | **Tool artifact** — `automatic` block-locals are not persistent storage; no toggle tool tracks them. Already `signal -next_c` / `signal -load_next_c` in the sidecar. |
| `readback_data_var` | 1 | 32 | **Tool artifact** — same `automatic`-scratch-variable pattern. Already waived. |
| `is_valid_addr`, `is_valid_rw` | 2 | 2 | **Structurally dead by design** — RTL-verified: `is_valid_addr = '1;` / `is_valid_rw = '1;`, unconditional constants (`pmtpc4_regblock.sv:113-114`), because `pmtpc4_apb_slave` pre-validates every access before it reaches the regblock. Not a tool artifact — genuinely, permanently constant. Already waived. |
| `cpuif_rd_data` / `readback_data` upper bits `[31:16]` | 2 | 32 | **Genuine, permanently-open residual** — every field in this register map is <=16 bits wide, so the upper half of the CPU-interface data word is dead by construction, exactly like the already-solved top-level `cpuif_rd_data_pad`. Cannot be fixed the same way (RTL split) because this file is **PeakRDL-generated** — hand-editing it is explicitly forbidden project-wide (a regen silently discards the edit) — and xcrg has no bit-range exclusion syntax. **Deliberately left unwaived** (see the sidecar's own note: a same-name `signal -` directive would also strip the regblock's real low-16-bit coverage). This is the ONE item in this whole analysis that is a true, currently-unresolvable residual, not a tool-reporting problem. |
| *(unaccounted)* | — | ~766 | Not individually re-derived this pass — see caveat below. **RESOLVED 2026-09-20, see "pmtpc4_regblock's ~766 unaccounted toggle bits, fully reconciled" below — no new category found.** |

**Caveat on the unaccounted ~766 bits (as it stood on 2026-09-19; fully resolved 2026-09-20, see
below):** xcrg's per-signal table reports "All bits of X: covered" as a single yes/no per variable (did
*any* bit toggle both ways), not a per-bit breakdown — so a wide signal shown as "covered" in that table
can still contain individually-uncovered bits that only appear in a deeper per-signal drill-down the
module-level report doesn't expose in scrapeable form. Given every *named, uncovered* variable in the
regblock's table (all 81 of them, both the 79 tool-artifact ones and the 2 genuine dead-bit ones) was
already accounted for and classified above, the unaccounted bits were reasoned to very likely be the
SAME categories at finer granularity rather than a new class of hole — but that was a reasoned inference,
not independently re-verified bit-by-bit, at the time this was written.

**`pmtpc4` (top level)'s 178 uncovered bits, classified:**

| Signal | Bits | Classification |
|---|---|---|
| `cpuif_wr_data`, `cpuif_wr_biten` | 32+32=64 | **Tool artifact** (pass-through-alias blind spot) for `cpuif_wr_data` — proven via regblock's own copy being genuinely 1/1 covered AND `cg_apb.cp_rw.wr`=2261 hits from the same db. `cpuif_wr_biten` is separately, correctly waived (driven constant `32'hFFFF_FFFF` by the wrapper — genuinely dead, not an artifact). **`cpuif_wr_data` is deliberately NOT added to the exclusion list** — measured empirically (see below) that doing so makes the aggregate score WORSE, not better. |
| `cpuif_rd_data_pad` | 16 | Already waived; exclusion directive present but proven (2026-09-15) not honored by xcrg. Genuinely, permanently dead by design (RTL split already done — this is the intentionally-dead half). |
| `ch_expiry[3]` | 1 | **Tool artifact, proven via independent cross-validation** — `g_int_bit[3].cg_int_bit.cp_op.set_by_hw`=15 hits and `cg_fsm` (channel 3 instance) `cp_trans.run_exp`=83 hits, both from the SAME database, both structurally impossible unless `ch_expiry[3]` pulsed. Ruled out as an RTL/wiring bug by direct inspection of `pmtpc4.sv:105-150` — all four channel instantiations wire `.expiry(ch_expiry[N])` identically, no `generate` loop, no shared logic. **Deliberately not waived** — waiving `ch_expiry` would also strip bits [0]/[1]/[2]'s real, already-covered contribution (no bit-range exclusion syntax exists). |
| (remainder) | ~65 | Smaller-width signals following the same already-documented alias/artifact patterns (`int_status_val`/`int_en_val`, etc.) — not re-itemized here, see the sidecar for each. |

**The `cpuif_wr_data` experiment (why "add it to the exclusions" doesn't always help):** tried it, measured
it, reverted it. Adding `signal -cpuif_wr_data` moved the aggregate DUT toggle score from **39.85% to
39.22%** — DOWN. Root cause: xcrg's `signal -X` directive matches by bare name across the *entire* design,
not by hierarchical path. `pmtpc4_regblock` independently declares its own `cpuif_wr_data` (its own input
port), which genuinely toggles and is correctly counted as covered; the SAME directive that removes the
top-level wire's artifact also removes the regblock's real, working coverage, and the net effect is
negative. This is the concrete, reproducible answer to "why isn't it in the exclusions": for `next_c` /
`load_next_c` / `is_valid_addr` / etc., it already IS in the exclusions and xcrg silently ignores the
directive anyway (a separate, previously-proven tool limitation); for `cpuif_wr_data`, adding it is
actively counterproductive due to a name collision with a real, different signal in a different module.
Every existing alias waiver in this file (`cpuif_addr`, `decoded_wr_biten`, `start_trig`, `pwm_level`,
`int_status_val`, `int_en_val`) was accepted on its own stated evidence but has **not** been individually
re-measured before/after the way `cpuif_wr_data` was here — flagged as a follow-up audit item, since any
of them could be silently making the score worse rather than better.

**Bottom line:** zero RTL bugs found in this pass (the one signal that looked most like a candidate,
`ch_expiry[3]`, was specifically investigated and disproven as a bug via independent cross-validation).
Of `pmtpc4_regblock`'s 1046 uncovered bits, ~248 are classified with certainty (214 tool-artifact +
2 structurally-constant + 32 genuine permanent residual), and the remaining ~766 were, at the time this
was written, reasoned to be more of the same but not individually re-verified — **fully confirmed
2026-09-20 by an exhaustive per-signal walk, see below: zero unclassified, no new category found.**
Of `pmtpc4`'s 178, essentially all are classified,
split between already-proven tool artifacts and two freshly-found ones this pass (`cpuif_wr_data`,
`ch_expiry[3]`) that are documented but deliberately not added as exclusion directives because doing so
would be net-negative or would discard other bits' real coverage. `pmtpc4_prescaler`'s "No Toggles in
Module" was a total, whole-module tool blind spot -- resolved below via module-level exclusion, not a
per-signal waiver.

## 2026-09-19 prescaler module-exclusion (not a signal waiver -- a different category of decision)

xcrg's `-ccExclusionFile` mechanism supports `module -<name>` and `instance -<path>` directives, not just
`signal -<name>` -- this project had only ever used `module -X` to scope out VERIFICATION code (the
DUT-scoping mechanism every IP's exclusion file is built on). This is the first time it has been applied
to a **DUT** module, and that is a materially different kind of decision, spelled out here rather than
folded into the signal-waiver table above:

- **What it is not:** a claim that `pmtpc4_prescaler` is proven covered. It is not -- `xcrg`'s own module
  report for it literally reads `"No Toggles in Module"`: zero toggle-trackable variables found, before
  any exclusion is even applied. There is no score to selectively hide; there is no data.
- **What it is:** a decision to stop letting a module the tool cannot instrument at all drag down the
  aggregate DUT toggle score, on the documented basis that (a) the module's actual activity is
  independently corroborated by a DIFFERENT coverage metric from the SAME database
  (`pmtpc4_prescaler.sv:31`'s `cnt <= cnt + 1` executes 973 times per the statement report), and (b) this
  specific "No Toggles in Module" failure mode was investigated in an earlier session pass and found to be
  a genuine simulator limitation, not a stimulus gap.
- **Measured, not assumed, cost:** excluding the whole module moves DUT toggle 39.85% -> 46.5% (+6.65pp),
  but also DUT statement 99.8658% -> 99.8634% and branch 98.0707% -> 98.0392% (both tiny *decreases* --
  prescaler was a free 100% contributor to those two metrics, and removing it costs that). Condition is
  unaffected (100% either way). Tested directly against the live database before being applied for real.
- **Scope of the precedent:** this is currently the ONLY whole-module DUT exclusion in this project. It
  should not be reused as a general pattern for "a module with a low score" -- the precondition is
  specifically zero-instrumentation ("No Toggles in Module" or equivalent), independently corroborated,
  and measured before/after. A module that IS instrumented but merely scores low is a real coverage gap
  and belongs in the closure loop, not this exclusion file.

## 2026-09-19 investigated and rejected: narrowing the regblock CPU-interface data width

Considered (to eliminate the ~32-bit `cpuif_rd_data`/`readback_data` dead-upper-bits residual inside
`pmtpc4_regblock` at the source, the same way the top-level `cpuif_rd_data_pad` split already worked) and
**not pursued**, on the following reasoning: PeakRDL's `regwidth`/`accesswidth` properties, which set the
passthrough cpuif's data-port width, are also what determine register address stride in the generated
address map. Narrowing the CPU-interface width from 32 to 16 bits would very likely halve every register's
byte offset, not just narrow a data path -- rippling into the register spec, the RAL model, every
generated C header, and every hardcoded address literal already in this testbench (the reserved-offset
list in `pmtpc4_reg_reserved_vseq`, `cg_apb`'s `is_ch()` decode function, etc.), plus creating an unusual
16-bit-strided register map on a 32-bit APB bus that would need its own justification independent of
coverage. That is disproportionate for closing 32 dead bits out of several thousand, and those bits are
dead for a completely ordinary reason (narrower fields inside a standard-width bus is normal register-map
design, not a smell). Not implemented. If revisited, the first step is confirming with PeakRDL-regblock's
own documentation/source whether `accesswidth` can be decoupled from register stride for a passthrough
cpuif -- not yet verified either way.

## Open avenue for the remaining top-level alias signals (attempted 2026-09-20, see "item 3" below for the outcome)

Every top-level toggle-artifact signal found across this whole audit -- `cpuif_addr`/`decoded_wr_biten`
(regblock-internal), `cpuif_wr_data`, `start_trig`/`pwm_level`, `int_status_val`/`int_en_val`,
`ch_expiry[3]` -- shares one structural trait: each is a `wire`/continuous-assign net (no procedural
`always_ff` driver of its own), never a genuinely registered signal. `compare_shadow` is the one
confirmed exception, and it was independently, specifically investigated (temporary RTL trace) rather
than assumed to be "the same kind of thing." This is a strong, consistent pattern across every case found
so far, not a single anecdote, and points at a real, reproducible characteristic of xcrg's toggle
instrumentation: it reliably tracks clocked storage but has a genuine blind spot for pure pass-through /
alias wires.

The technique that already fixed `cpuif_rd_data_pad` — eliminate the redundant named intermediate signal
entirely and connect the driving expression directly at each use site (no combined wire left for the tool
to either track or miss) — applies cleanly to the ones that are TRUE cross-module identity pass-throughs
in hand-written, editable RTL: `cpuif_wr_data` (pmtpc4.sv, `u_apb` output straight into `u_rb` input, no
other consumer) is the cleanest candidate. `int_status_val`/`int_en_val` (pmtpc4.sv) and `start_trig`/
`pwm_level` (pmtpc4_channel.sv) are also hand-written and editable, but are consumed by an EXPRESSION
rather than passed straight to another port (e.g. `ch_expiry[N] & ~soft_rst_pulse`), so the fix there is
"inline the aliased expression at every use site and delete the wire declaration," not "connect two ports
directly" -- same principle, different mechanics, and needs checking that nothing else in the file
references the wire by name before deleting it. `cpuif_addr`/`decoded_wr_biten` are the one pair that
CANNOT be fixed this way -- they live inside `pmtpc4_regblock.sv`, a PeakRDL-generated file this project
never hand-edits.

**Not attempted in this section's original pass** — deliberately left for a follow-up with its own
review/mutation-testing cycle. **That follow-up happened 2026-09-20 — see "item 3: RTL-split
(inline-alias) fix attempted, partially landed, partially reverted" below for the full outcome**:
`int_status_val`/`int_en_val` landed clean; `cpuif_wr_data` was attempted and reverted after the
static gate caught a real `sv2v`/Yosys width-truncation bug; `ch_expiry[3]` was never attempted for
lack of a credible mechanism (the other 3 array elements use the identical pattern and already
toggle fine).

## 2026-09-20 — `pmtpc4_regblock`'s ~766 unaccounted toggle bits, fully reconciled (no longer open)

The earlier deep-dive's own action item was to walk `xcrg`'s per-signal detail pages instead of
scraping the HTML module summary, to settle whether the unaccounted bits are more of the same
already-classified categories or a new, undiscovered class of hole. Done this pass, exhaustively,
not by sampling:

- `-report_format text` does **not** change anything for code coverage on this xcrg build (2025.1) --
  it silently still emits the same HTML output as `-report_format html`. A real limitation, worth
  knowing for future toggle-coverage work, not a workaround-able flag.
- The per-**file** HTML page (`code_report/codeCoverageReport/file4.html`, `pmtpc4_regblock.sv`) DOES
  carry the fine-grained detail the module-summary page doesn't: a full "Toggle Coverage of File"
  table, one row per declared variable (splitting a signal into named sub-ranges when only part of it
  toggles, e.g. `cpuif_rd_data [0:15]` vs `All Other bits of cpuif_rd_data`), with `0->1`/`1->0` counts.
  This is the "proper per-signal walk" the earlier action item asked for.
- Parsed that table completely: **167 total toggle variables, 155 uncovered** (matching the module
  summary's own stated split exactly). Classified **all 155** against the 4 categories the earlier
  session had already justified — zero left unclassified:

  | Category | Uncovered variables | Already justified as |
  |---|---|---|
  | `next_c` / `load_next_c` (PeakRDL `automatic` temporaries) | 149 | Tool artifact — not persistent storage, no toggle tool tracks it |
  | `readback_data_var` | 2 | Same `automatic`-scratch-variable pattern |
  | `is_valid_addr` / `is_valid_rw` | 2 | Structurally dead by design — unconditional constants |
  | `cpuif_rd_data` / `readback_data` upper bits | 2 | Genuine, permanently-open residual (dead by field-width construction) |
  | **Total** | **155 / 155** | **zero unclassified** |

- **Answer to the original question**: no. There is no hidden new category of hole among the
  previously-"unaccounted" bits. Every uncovered variable in `pmtpc4_regblock`'s entire toggle report
  falls into a category already found, justified, and (where tool-honorable) waived by the 2026-09-19
  deep-dive — just at finer per-declaration granularity than that session's grep-based declaration
  count captured (that session counted 76 `next_c`/`load_next_c` *declarations* by grepping the source
  for the pattern once per field; the actual per-generate-block-instance elaborated count the toggle
  tool reports is 149, since many fields' combinational blocks are themselves elaborated per-instance —
  same root cause as `pmtpc4_top_sva`'s `_default` renaming in the W4 finding above: generate-block
  elaboration multiplying instance counts beyond a simple source-level grep).
- **What did NOT fully reconcile, and why that's not a concern**: converting each classified variable
  to an exact bit count (by regex-matching a `[hi:lo]` range at its reported declaration line against
  the RTL source) totaled 555 bits, not the report's stated 1046 uncovered bits. This gap is
  attributable to the width-inference method being crude (it can't resolve multi-line declarations,
  typedef-based widths, or xcrg's own internal line-number-to-elaborated-instance mapping), not to any
  undiscovered variable -- the variable-level count (155) is exact and exhaustive because it came
  directly from walking the complete table, while the bit-level number is an approximation that was
  never the load-bearing part of the question. Left as an approximation rather than chased further,
  since the decisive finding (no new category) does not depend on it.

**This closes the `pmtpc4_regblock` ~766-bit item.** No code, waiver, or exclusion-file change
resulted -- this was a pure reconciliation/audit task, so no regression re-run is needed.

## 2026-09-20 — the 6 remaining alias waivers, individually measured (no longer open)

The 6 alias waivers flagged above as never individually before/after-measured --
`cpuif_addr`, `decoded_wr_biten`, `start_trig`, `pwm_level`, `int_status_val`, `int_en_val` --
were each tested directly against the live coverage database (via `xcrg` re-runs on the existing
`pmtpc4_full_test_seed1` database, no new simulation), the same methodology already used for
`cpuif_wr_data` and `pmtpc4_prescaler`. Removed one waiver at a time from a copy of
`dv/pmtpc4_cov_exclusions.txt` and re-measured DUT toggle against the 46.0% all-6-waived baseline:

| Waiver removed | Resulting toggle | Delta | Verdict |
|---|---|---|---|
| `cpuif_addr` | 45.91% | −0.09pp | legitimate (score drops when un-waived) |
| `decoded_wr_biten` | 45.89% | −0.11pp | legitimate |
| `start_trig` | 43.26% | −2.74pp | legitimate |
| `pwm_level` | 43.26% | −2.74pp | legitimate |
| `int_status_val` | 45.88% | −0.12pp | legitimate |
| `int_en_val` | 45.88% | −0.12pp | legitimate |

Every single one moves the score DOWN when un-waived, the opposite of the `cpuif_wr_data` pattern
(which moved the score down when the waiver was *added*, proving it was net-negative). None of these
6 is net-negative; all 6 are confirmed doing their intended job -- removing genuinely
untracked/dead-by-tool-limitation bits from the denominator, not colliding with an unrelated,
actually-covered same-named signal elsewhere. No waiver-file change needed.

`start_trig` and `pwm_level` landing on the identical 43.26% (verified the two exclusion-file variants
actually differ -- not a script bug) is explained by both being single-bit continuous-assign wires in
`pmtpc4_channel.sv`, each instantiated once per channel (4 bit-instances), with the same "always
0-toggle when untracked" profile -- an identical width/coverage shape producing an identical delta, not
a coincidence to be suspicious of. The size of that delta (2.74pp from what a naive count would call
"4 bits") is consistent with this project's established finding (see F15/W4 above) that xcrg's toggle
percentage is not simply proportional to raw bit count -- it was not re-derived further here since the
verdict (legitimate, keep) does not depend on explaining the exact magnitude.

**This closes the "6 other alias waivers" item from the "Still open" list above** -- it is no longer
open. (The `pmtpc4_regblock` ~766-bit item was closed separately, above.)

## 2026-09-20 — item 3: RTL-split (inline-alias) fix attempted in full, reverted in full

The "Open avenue for the remaining top-level alias signals" plan above proposed inlining
`cpuif_wr_data`, `int_status_val`/`int_en_val`, `start_trig`/`pwm_level`, and `ch_expiry[3]` at
their use sites and deleting the redundant wires, mirroring the technique that already fixed
`cpuif_rd_data_pad`. Taken up this pass, item by item, each run through the full static gate
(Verible -> Verilator -> Yosys/sv2v) *and* the full simulation regression before being trusted
-- and every part of the plan that reached simulation was reverted. Full sequence, in the order
it actually happened, not a cleaned-up retelling:

1. **`int_status_val` / `int_en_val` / `masked` (`pmtpc4.sv`) and `start_trig` / `pwm_level`
   (`pmtpc4_channel.sv`) — inlined.** Each had exactly one downstream use site, confirmed by grep
   before deleting the wire; none were bound by any checker (`pmtpc4_channel_sva.sv` and
   `pmtpc4_pwm_cov.sv` deliberately keep their own independent re-derivations, never reading the
   DUT's own wires, per this session's spec-independence discipline). The SVA bind in
   `pmtpc4_tb_top.sv` was updated to connect `int_status_val`/`int_en_val`'s ports straight to the
   same `hwif_out` expressions instead of the since-deleted wires. Clean through Verible, Verilator
   (project's actual `flow/tools/verilator_waivers.vlt`-based invocation), and Yosys/sv2v (zero
   warnings) -- the static gate found nothing wrong with either of these.
2. **`cpuif_wr_data` (`pmtpc4.sv`) — attempted differently, caught and reverted by the static
   gate itself.** Unlike the other four, this is a pure identity pass-through between two module
   instances with no transforming expression to inline -- the one use site IS the direct
   instance-to-instance connection. Tried a hierarchical port reference (`u_rb`'s
   `.s_cpuif_wr_data(u_apb.cpuif_wr_data)`, no top-level net at all). Verible and Verilator both
   accepted it cleanly, but Yosys (via the project's mandatory `sv2v` pre-flatten step) reported
   **"Resizing cell port pmtpc4.u_rb.s_cpuif_wr_data from 1 bits to 32 bits"** -- `sv2v` does not
   correctly preserve a hierarchical port reference's width when flattening SystemVerilog to
   Verilog, silently defaulting to 1 bit. Had this shipped without the full lint -> elaboration
   gate, it would have been a severe, synthesis-breaking correctness bug (write data truncated to
   1 bit). **Reverted immediately**, before ever reaching simulation.
3. **`ch_expiry[3]` — never attempted.** Elements `[0]`, `[1]`, `[2]` of the same array use the
   textually identical port-connection pattern and already toggle correctly (confirmed 2026-09-19,
   no `generate` loop, no shared logic between channels), so there is no expression to inline and
   no identified mechanism an inlining-style fix would change. Left as-is: a proven, understood,
   single-bit tool artifact.
4. **The two changes that passed the static gate (item 1) were then run through the full
   simulation regression -- and made the actual metric they were meant to improve WORSE, not
   better.** `pmtpc4_channel`'s DUT toggle score dropped from **100% to 40%**; the aggregate DUT
   toggle score dropped from 46.0% to 35.92%. Root cause, confirmed by the module-level
   breakdown: `xcrg` tracks toggle points for INLINE boolean sub-expressions separately from
   named signals, and unlike a named wire, an anonymous expression **cannot be excluded by a
   `signal -X` directive** -- there is no name to write in the exclusion file. The two existing
   waivers (`signal -start_trig`, `signal -pwm_level`, still in `dv/pmtpc4_toggle_waivers.txt`)
   went from correctly matching a real (if artifact-affected) named signal to matching nothing at
   all, while the inlined expressions' own untracked sub-terms became new, unwaivable uncovered
   toggle points. This is the OPPOSITE of what happened with `cpuif_rd_data_pad`, and the
   difference matters: that fix split one wire into two still-NAMED, still-waivable/trackable
   signals (`cpuif_rd_data_active`/`_pad`); this attempt replaced named wires with bare anonymous
   expressions, which is a fundamentally different move that this session's plan (written
   2026-09-19, before this was tested) did not distinguish. **All five wires -- `int_status_val`,
   `int_en_val`, `masked`, `start_trig`, `pwm_level` -- were restored to their original named-wire
   form**, and the SVA bind reverted to referencing them by name again.

**Net result: item 3 is fully reverted. Nothing from this plan landed.** Every one of the four
signals/groups considered is exactly what it already was before this session started: a
documented, understood, deliberately-not-waived (for `cpuif_wr_data`/`ch_expiry[3]`) or
tool-artifact-waived (for the other four) toggle-coverage residual. This was not wasted effort --
it is now KNOWN, with direct measurement rather than assumption, that "inline the expression and
delete the wire" is not a safe general technique for this xcrg blind spot, only the specific
"split into two still-named signals" form already used for `cpuif_rd_data_pad` is. That
distinction is now recorded here for anyone who revisits this residual later, and is exactly why
the project's quality-gate order (lint -> elaboration -> **simulation** -> coverage) is run in
full and not stopped at the static gate: `int_status_val`/`int_en_val`/`start_trig`/`pwm_level`
passed lint and elaboration cleanly and only failed at the coverage-measurement step, the very
last gate, after `cpuif_wr_data` had already failed one step earlier at elaboration. Both were
caught before being reported as done.

**Verification status — CONFIRMED 2026-09-20**: full regression re-run after the complete revert:
`40/40 runs passed`, zero `raw_ERROR`/`SVA` failures, DUT toggle back to **46.04%** (matching the
pre-item-3 baseline exactly), confirming the revert is complete and correct.

## 2026-09-19 Tier 1 closure — the three unambiguous design-audit findings (F1/F3/F4)

Following the independent design-review/verification-review audit (this document's earlier sections),
three findings were confirmed real and unambiguous (fixable regardless of the still-open `ch_active`/
PWM-gating spec question below) and are now fixed, with dedicated regression tests, in
`pmtpc4_full_test`.

- **F1/F14 — PWM stayed high one extra cycle after soft-disable.** Fixed in
  `rtl/pmtpc4_channel.sv`: the soft-disable branch (`!ch_en && state != S_IDLE`) now forces
  `pwm_q <= 1'b0` on the same edge it forces `state <= S_IDLE`, instead of letting the unconditional
  `pwm_q <= pwm_level;` below it fire with the pre-disable `pwm_level`. New dedicated regression guard:
  `a_pwm_low_in_idle` in `pmtpc4_channel_sva.sv` (a property, not a covergroup bin — see below for why).
  Verified via a temporary Active-region RTL diagnostic (reverted): zero `state==IDLE && pwm_q==1`
  occurrences across the full regression, confirming the RTL fix directly, independent of any coverage
  tooling.
  - **Coverage-model side-finding**: `cg_pwm.cp_pwm_by_state.idle_high` still credited a hit in 4 runs
    even after the RTL fix, and even after routing the coverpoint through this file's existing
    one-cycle-delayed mirrors (`state_prev`/`pwm_mirror`) instead of the bare bound ports. A second,
    doubly-registered mirror stage *also* didn't stop it. This points at a genuine SystemVerilog
    scheduling-region effect (a covergroup with an explicit clocking event samples in the Observed
    region, which runs after the same edge's NBA updates commit — differently from any Active-region
    procedural reader of the identical signals, confirmed by a temporary diagnostic that never saw the
    condition in the Active region on the same run the covergroup credited it) rather than a coding
    mistake, but the exact xsim mechanics were not fully pinned down. Given the independent RTL proof
    above, `idle_high` is downgraded from `illegal_bins` to `ignore_bins` (no longer treated as a
    coverage-model correctness claim), and the real regression guard is now `a_pwm_low_in_idle`, which
    reads the bare `pwm` port directly (matching the already-reliable `a_pwm_rule` pattern — properties,
    unlike this file's covergroups, sample bound ports reliably against a local register). `exp_high`
    and `load_high` were independently investigated, not assumed to share the same issue: `exp_high` has
    never been observed to fire and stays `illegal_bins`; `load_high` is the separate, real,
    still-open `ch_active` question and stays `illegal_bins` on purpose (see below).
- **F3 — one-shot `CH_EN` self-clear could be permanently defeated by a coincident software write.**
  Fixed in `rdl/pmtpc4.rdl`: added `precedence=hw;` to `CH_EN`, then regenerated the regblock
  (`peakrdl regblock ... --module-name pmtpc4_regblock --package-name pmtpc4_regblock_pkg
  --default-reset arst_n` — the installed peakrdl-regblock version's *defaults* for output file naming
  and reset style both changed from what originally generated this project's files; explicit flags are
  now required to match the existing integration). Diff-verified minimal: only the 4 channels' `CH_EN`
  field logic changed, swapping `hwclr` to be checked before the SW-write branch instead of after.
  New dedicated regression test: `pmtpc4_selfclear_race_test` (`pmtpc4_selfclear_race_vseq.sv`) — since
  exact cycle-alignment between an APB write and an internal expiry isn't practical to control
  precisely from a vseq, it sprays 40 back-to-back `CHx_CTRL` writes (via the APB b2b driver mode)
  across a one-shot channel's expiry window, 5 times, and confirms `CH_EN` always ends up 0 regardless
  of which cycle a write landed on. Passes clean.
- **F4 — `CH_EN`/`CH_START` writes issued while `MODULE_EN==0` were silently swallowed.** Fixed in
  `rtl/pmtpc4_channel.sv`: `ch_en_q` now only updates `if (module_en)` (held across a freeze instead of
  tracking `ch_en` unconditionally), and a new sticky `ch_start_pending` register latches a `CH_START`
  pulse regardless of freeze state, consumed exactly at the `S_IDLE` `start_trig` branch. New dedicated
  regression test: `pmtpc4_freeze_start_test` (`pmtpc4_freeze_start_vseq.sv`) — the natural bring-up
  order (disable, configure, write `CH_EN`/`CH_START` while frozen, un-freeze) now correctly starts the
  channel. Passes clean.
  - **Checker-desync finding (found by this fix, not by the original audit)**: both
    `pmtpc4_channel_sva.sv` and `pmtpc4_pwm_cov.sv` have their own *independent* re-derivations of
    `start_trig` (`ch_en_q_mirror`/`start_trig_mirror`), used respectively by `a_count_loads_period`/
    `a_count_retained`/etc. and by `load_decision` (which feeds `ticks_since_load`, `per_at_load`,
    `a_period0_expires`, and the `x_period0` cross). Neither mirror was updated to match the corrected
    freeze semantics, so once the RTL fix landed, these checkers' *own* models still predicted the
    pre-fix (buggy) behavior and flagged the corrected RTL as a violation — `a_count_retained` and
    `a_period0_expires` failed, and `x_period0.nonzero_is_never_two_ticks` fired 148+ times, in
    `pmtpc4_freeze_start_test` alone. This is exactly the class of thing `verification-review`'s new §0
    exists to catch, caught here by the dedicated regression test actually exercising the freeze/start
    interaction rather than by inspection. Fixed by updating both mirrors independently (re-derived from
    the `ch_en`/`ch_start`/`module_en` PORTS, never by reading the DUT's own `ch_en_q`/`ch_start_pending`
    registers) to implement the same corrected semantics. Re-verified: full regression green on this
    front, zero SVA failures, `x_period0` illegal-cross-bin count back to only what `load_high`'s
    still-open question accounts for.

**Net effect on the regression**: every remaining failing run's `raw_ERROR` count is now attributable
entirely to `cp_pwm_by_state.load_high` (the open `ch_active` question, Tier 2) — confirmed by
re-running the full regression after these fixes and finding zero SVA failures and zero non-`load_high`
raw `ERROR:` lines anywhere. `pmtpc4_freeze_start_test` and `pmtpc4_selfclear_race_test` both added to
`pmtpc4_full_test` as well as standing alone.

**2026-09-19 fast-follow, done**: `vplan.yaml` updated with `gap:` findings for F1 (under
`VP-CH-DISABLE`), F3 (under `VP-CH-MODE`), and F4 (under `VP-MODULE-FREEZE`), each documenting the
RTL bug, why the item's pre-existing checker/coverage pair couldn't have caught it, the fix, and the
new dedicated test; `tests:` lists updated to include `pmtpc4_freeze_start_test` and
`pmtpc4_selfclear_race_test`.

**Still not yet done**: a fresh `coverage_summary.md`/testplan xlsx regeneration reflecting these
fixes plus the Tier 2 resolution below.

## 2026-09-19 Tier 2 resolution — `ch_active`/PWM-gating spec-vs-RTL discrepancy

**The question**: `design_spec.md` SPEC-PWM-1 originally gated `pwm_level` on
`state==RUNNING||PAUSED`, while `pmtpc4_channel.sv`'s `ch_active` used the broader `state != S_IDLE`
(i.e., also true during LOAD). RTL and spec disagreed; both the RTL comment and the checkers that
mirrored `ch_active` (`a_pwm_rule` in `pmtpc4_channel_sva.sv`, `a_pwm_matches_independent`/
`pwm_exp_local` in `pmtpc4_pwm_cov.sv`) had, at various points, framed the broader condition as
"copied from RTL" rather than independently spec-derived — precisely the anti-pattern
`verification-review`'s new §0 exists to flag. `cg_pwm.cp_pwm_by_state.load_high` was `illegal_bins`
on the premise that LOAD could never produce a high `pwm_q`, which is only true under the *narrow*
formula.

**Adjudication (user-approved, "yes, I will go with your recommendation. Continue.")**: widen the
spec to match the RTL's `state != IDLE`, not narrow the RTL to match the original spec text. Reasons,
independent of which one happened to be already-implemented:
- REQ-CORE-3 itself (the requirement SPEC-PWM-1 is supposed to satisfy) states the PWM rule with
  **no state qualifier at all**: "output high while COUNT > COMPARE, low otherwise, gated by
  PWM_EN." The narrow `RUNNING||PAUSED` form was SPEC-PWM-1's own invention, not something
  REQ-CORE-3 asked for.
- During LOAD, `COUNT` already holds the just-reloaded `PERIOD` (the same cycle software can read
  it back via `CHx_COUNT`), so `COUNT > COMPARE_shadow` is a real, meaningful comparison during
  LOAD, not a don't-care that happens to need suppressing.
- SPEC-PWM-1's *own second bullet* ("forced low when module_en==0 or channel IDLE") already implied
  the `!= IDLE` form — the two bullets were self-contradictory before this fix, independent of the
  RTL entirely.
- Narrowing the RTL instead would have introduced a real, measurable behavioral regression: an
  extra full prescaled tick of missing PWM high time on every periodic reload, and a `pwm_out` that
  disagrees with a concurrently-read `CHx_COUNT` during LOAD — i.e., narrowing would have *created*
  a bug to satisfy a spec sentence that was itself found to be wrong.

**Changes made**:
1. `design_spec.md` SPEC-PWM-1 (§5) rewritten to `state != IDLE`, with the full reasoning above and
   an explicit history note pointing back here.
2. `pmtpc4_channel.sv`'s `ch_active`/`pwm_level` comment rewritten to cite the corrected spec and
   REQ-CORE-3 directly, and to explicitly flag that the RTL's original "one-tick notch" justification
   for including LOAD was independently checked and found technically incorrect even though its
   conclusion (include LOAD) was right — for the REQ-CORE-3 reason above, not that reason.
3. `pmtpc4_channel_sva.sv`'s `a_pwm_rule`/`pwm_exp` comment and `pmtpc4_pwm_cov.sv`'s
   `a_pwm_matches_independent`/`pwm_exp_local` comment both rewritten to frame the formula as
   spec-derived, removing the "we rebuild that exact register"/RTL-copying framing. Both files now
   note their real independence from each other comes from the compare source substitution
   (`cmp_at_load` vs. `compare_shadow`), not from the state condition — the state condition is
   expected to agree everywhere, by design, because both are correctly implementing the same spec
   formula.
4. `pmtpc4_pwm_cov.sv`'s `cp_pwm_by_state.load_high` changed from `illegal_bins` to a real,
   positively-covered `bins load_high = {{S_LOAD, 1'b1}};`; the now-conflicting duplicate
   `illegal_bins load_high` line further down was removed. Surrounding comment block marked
   "RESOLVED 2026-09-19" with the spec-citation reasoning in place of the old unreachability claim.
   `idle_high` (`ignore_bins`, F1/xsim-Observed-region issue) and `exp_high` (`illegal_bins`, never
   observed to fire) are unrelated and untouched.
5. `vplan.yaml`'s `VP-PWM-DUTY` item updated with a correction note explaining why the earlier
   "structurally unreachable" reasoning for `load_high` was wrong in its premise (it implicitly
   assumed the narrow gating condition).

**Verification status — CONFIRMED 2026-09-19**: full regression re-run after these five changes:
`40/40 runs passed`, every run `UVM_ERROR=0 FATAL=0 SVA=0 scb_err=0 raw_ERROR=0` (including
`pmtpc4_full_test` across seeds 1-5, `pmtpc4_pwm_duty_test`, and every other test in the suite).
`reports/_cov/functional_report`'s `cg_pwm.cp_pwm_by_state` shows **8/8 bins covered, 0 uncovered,
100%** — confirming `load_high` is not merely error-free but genuinely, positively hit as a real
bin. This was the last known source of `illegal_bins` violations in the design (Tier 1's F1/F3/F4
already eliminated every other source per the section above): the regression has now reached a
fully clean state — zero `raw_ERROR` lines anywhere — for the first time this session.

## 2026-09-19 Tier 2 remainder — F6, F5, F7-verif

- **F6 — an RDL/RTL comment claimed the OPPOSITE of what the generated field logic does, citing a
  spec section that says nothing on the topic.** `rdl/pmtpc4.rdl`'s `INT_STATUS` block said "hwclr
  must take precedence over hwset (verified in the generated field logic)" for the
  hwset(expiry)-vs-hwclr(soft_reset) collision, citing "Design Spec Section 7.4." Checked both
  claims directly, not from memory: (1) Section 7.4 is the PERIOD/COMPARE/CH_START edge-case list —
  it says nothing about interrupts or soft reset; no such requirement exists to cite. (2) The
  generated field logic (`rdl/generated/rtl/pmtpc4_regblock.sv`, the `CH_INT_STATUSn` combinational
  block) reads `if(hwset) ... else if(hwclr) ...` — HWSET is checked first and wins a same-cycle
  collision, the *opposite* of the comment's claim; this is peakrdl-regblock's fixed internal
  precedence, not something any RDL-level `precedence` property controls for hwset-vs-hwclr
  specifically. In practice the collision cannot occur anyway — `pmtpc4.sv` gates each channel's
  `hwset` input with `& ~soft_rst_pulse`, making hwset and this hwclr structurally mutually
  exclusive — so no behavior was ever wrong, only the documentation. Fixed: corrected comments in
  `pmtpc4.rdl` and `pmtpc4.sv` with the evidence inline, plus a `design_spec.md` clarification
  (§2) noting this is a deliberate design choice with no spec-mandated origin, not a cited
  requirement. Regenerated the regblock from the corrected RDL and diffed it byte-identical against
  the checked-in copy, confirming the edit was comment-only.
- **F5 — `soft_reset` zeroed the shared prescaler's own divider phase, not just leaving its config
  register alone.** REQ-RST-2 excludes PRESCALER from what `soft_reset` clears ("clears ... (COUNT,
  FSM, INT_STATUS) but NOT PRESCALER/CLK_SEL/APB FSM"), grouping it with the APB FSM's own explicit
  in-flight-*state* preservation — read most naturally as the whole prescaler block's state, phase
  included, not just its `PRESCALER_VAL` register. The RTL only ever preserved the register; every
  existing test (`pmtpc4_soft_reset_vseq.sv`) only ever checked the register too. **User-adjudicated
  2026-09-19**: fix the RTL to the literal reading, not reinterpret the requirement. Fixed:
  `pmtpc4_prescaler.sv`'s `soft_reset` branch removed entirely — the divider counter and `tick_en`
  are now completely unaffected by `soft_reset` (the port stays wired at the top level for interface
  symmetry with every other channel-adjacent block, but is deliberately unused inside the module).
  This broke `pmtpc4_freeze_states_vseq.sv`'s `freeze_from_load()` task, which had used a
  `SOFT_RESET` pulse specifically to pin the divider's phase to a known 0 before reaching a
  deterministic LOAD-state freeze window — reworked to pin the phase via `PRESCALER=0` (with the
  module enabled, so the divider's `cnt>=0` comparison holds every cycle and pins `cnt` at 0
  continuously) instead, achieving the same determinism without depending on `soft_reset`. Also
  added a genuinely new, previously-missing check to `pmtpc4_soft_reset_vseq.sv` that directly
  exercises phase preservation (not just register-value preservation): parks the divider at a known
  mid-phase (~700 of 999), pulses `soft_reset`, starts a fresh channel with `PERIOD=0`, and confirms
  time-to-expiry is consistent with the phase having survived (~1300 cycles) rather than reset to 0
  (~2000 cycles) — a ~700-cycle gap, robust against ordinary APB-latency slop without needing
  cycle-exact prediction.
- **F7-verif — no checker anywhere in the regression had ever proven `STATUS.BUSY`/`STATUS.READY`
  correct for channels 1, 2, or 3.** Every existing `chk()` against `ral.STATUS`
  (`pmtpc4_soft_reset_vseq.sv`, `pmtpc4_channel_vseq.sv`, `pmtpc4_async_reset_vseq.sv`) reads
  channel 0's contribution exclusively. A mutation dropping channels 1-3 from the OR reduction in
  `pmtpc4.sv`'s `hwif_in.STATUS.BUSY.next` assignment would have survived the entire regression
  undetected. Fixed with a continuous property rather than a new directed test: `a_status_busy` /
  `a_status_ready` added to `sva/pmtpc4_top_sva.sv` (bound once at the top level), re-deriving the
  expected value from `ch_busy[3:0]`/`module_en`/`soft_reset` ports independently of the RTL line
  being checked, straight from SPEC-INT-1's formula. Being continuous and bound at the top, this
  retroactively validates every test in the regression that already exercises channels 1-3
  (`pmtpc4_pwm_all_channels_test`, `pmtpc4_freeze_states_test`, etc.) without needing bespoke new
  stimulus. Added `cg_status_busy.cp_sole_busy` (bins `ch0_only`..`ch3_only`) alongside it for
  positive evidence — proof each channel was actually observed as BUSY's sole contributor at some
  point, not just "no assertion ever failed."

**Verification status — CONFIRMED 2026-09-19**: two separate full regressions, both `40/40 runs
passed`, zero `raw_ERROR`/`SVA` failures anywhere. First run (F5 RTL fix, F6 comment corrections,
`pmtpc4_freeze_states_vseq.sv` rework, new `pmtpc4_soft_reset_vseq.sv` phase-preservation check) —
`pmtpc4_freeze_states_test` and `pmtpc4_soft_reset_test` both clean, confirming the LOAD-window
rework still lands correctly and the new phase check passes on the fixed RTL's ~1300-cycle branch
(not the ~2000-cycle buggy branch). Second run (F7-verif's `a_status_busy`/`a_status_ready` +
`cg_status_busy` in `pmtpc4_top_sva.sv`, wired via the `pmtpc4_tb_top.sv` bind update) — also clean;
`cg_status_busy.cp_sole_busy` shows all 4 `chN_only` bins genuinely hit (ch0=6937, ch1=5837,
ch2=4225, ch3=4440 occurrences), confirming every channel was independently observed as
`STATUS.BUSY`'s sole contributor, not just "no assertion ever failed."

- **F4-verif — no test had ever driven a genuinely mixed per-channel `INT_ENABLE` pattern while a
  channel was actually expired.** `a_irq_aggregation`/`a_gisr_readback` (continuous, independently
  re-derived from raw `int_status_val`/`int_en_val`/`global_ie` ports, confirmed by tracing
  `pmtpc4.sv`'s exact wire connections) are strong, correct checkers — but `pmtpc4_cov_close_vseq.sv`'s
  `INT_ENABLE=4'h7` write happens before any channel has expired, exercising only the register's
  write path, not masking's functional effect. A per-bit masking bug could have slipped through
  despite the strong checker simply because no test ever put the RTL in a state where such a bug
  would produce a different answer than the correct one. Fixed: `pmtpc4_irq_vseq.sv` extended with a
  fully deterministic, per-channel-discriminating scenario — `INT_ENABLE=4'b0101` (ch0,ch2 unmasked;
  ch1,ch3 masked), each channel expired one at a time with an `irq`/`GLOBAL_ISR` check after each:
  masked channels raw-latch but never move `irq`; the first *unmasked* expiry (ch0) is what actually
  flips it; clearing only the unmasked channels' bits (leaving the still-set masked bits alone) drops
  `irq` back to 0 — proving a masked-but-set bit never drives `irq` by itself.

**Verification status — CONFIRMED 2026-09-20**: full regression re-run after this addition (batched
with no other pending file changes, one run): `40/40 runs passed`, zero `raw_ERROR`/`SVA` failures
anywhere, including `pmtpc4_irq_test` with the new per-channel masking scenario. This closes every
Tier 2 remainder item (F5, F6, F7-verif, F4-verif) in this pass.

## 2026-09-20 Tier 3 — F15 (cross-sampling `iff`-guard bug) and W4 (toggle-weighting "mystery")

- **F15 — a `cross` with no `iff` of its own samples at the covergroup's own clocking event, not
  gated by its constituent coverpoints' individual `iff` guards.** Confirmed empirically, not from
  documentation alone: `cg_pwm.x_duty_class_pwm_en` (`pmtpc4_pwm_cov.sv`) had no `iff`, while both its
  coverpoints (`cp_duty_class`, `cp_pwm_en`) carry `iff (presetn && run_to_exp_edge)` — a rare,
  once-per-expiry event. The covergroup itself is `@(posedge pclk)`. Reading the last regression's
  functional coverage report: `cp_duty_class`'s own (correctly gated) total hit count across all bins
  was 183, but `x_duty_class_pwm_en`'s cross-cell total was **102,510** — a ~560x discrepancy. The
  cross was combining whatever `duty_class`/`pwm_en` held on *every* `pclk` edge, not just at the
  intended expiry instant; its "100% covered" never proved every (duty_class × pwm_en) combination was
  seen AT an actual expiry, only that clock-rate noise eventually filled every cell. This is a real
  SystemVerilog semantics gap between coverpoint-level and cross-level `iff` (the LRM's coverpoint
  `iff` only gates that coverpoint's own bins, not a cross built from it), not a copy-paste mistake
  isolated to one cross — found in **5 separate crosses** across the environment: `x_duty_class_pwm_en`,
  `x_period0`, `x_cmp_write_duty` (`pmtpc4_pwm_cov.sv`), `x_mode_live` (`pmtpc4_channel_sva.sv`), and
  `x_presc` (`pmtpc4_presc_sva.sv`). Fixed by adding the matching `iff` directly to each cross. Also
  checked (not assumed) every other `cross` in the environment for the same pattern: `x_reset` and
  `x_pin_level` were confirmed NOT instances of this bug (their constituent coverpoints carry no `iff`
  either, so cross and coverpoints are already consistent); `x_mask` (`pmtpc4_top_sva.sv`, `cg_int
  @(posedge pclk)`) IS the same bug (coverpoints gated `iff (presetn)`) and was fixed too, though its
  severity is much lower than the other 5 since `presetn` is false only for a brief window at the very
  start of simulation; `x_selfclr` (`pmtpc4_coverage.sv`) was investigated and found NOT an instance —
  that covergroup has no clocking event and is only ever sampled via an explicit `.sample()` call that
  is *itself* already conditioned on the same guard (`if (selfclr_sample_valid) cg_selfclr.sample();`),
  so no fix was applied there (a fix was drafted, then reverted on realizing the premise was wrong —
  see the git-free audit trail in this session's own transcript for the self-correction).
  - **Related, separately-caused bug found while investigating this**: `pmtpc4_presc_sva.sv`'s local
    `gap`-tracking mirror still treated `soft_reset` as interrupting the prescaler's tick spacing
    (`gap <= '0; presc_interrupted <= 1'b1;` on `soft_reset || !module_en`), matching the *pre-F5* RTL.
    After F5's fix (soft_reset no longer touches the prescaler at all), this checker mirror had gone
    stale — the same class of checker-desync problem F4's fix caused elsewhere, here from F5 instead.
    Effect was a false negative, not a false positive (the ratio check was needlessly *skipped* across
    every soft_reset, not wrongly failed), which is why the regression stayed green despite the desync
    — but it silently weakened `a_presc_ratio`'s real coverage. Fixed by removing `soft_reset` from the
    interruption condition (freeze/`module_en` is unchanged and still legitimately interrupts).
- **W4 — a large (double-digit percentage point), non-bit-proportional DUT toggle-coverage swing that
  earlier looked unexplainable.** Root-caused by re-reading `flow/scripts/gen_exclusions.py`'s own
  header comment (a fix already landed earlier this session, before this Tier 3 pass, but never
  written up here): xsim elaborates **some** bound/generate-block-containing modules under a
  **renamed instance**, not their literal declared name — confirmed for `pmtpc4_top_sva` specifically,
  which elaborates as `pmtpc4_top_sva_default` because it contains `generate` blocks
  (`g_setpri`/`g_int_bit`). A `module -pmtpc4_top_sva` exclusion directive (exact name) silently fails
  to match that renamed instance, so the module's own internal signals (covergroup/generate-block
  registers, e.g. `setpri_collision_count`, `prev_val` in `g_int_bit[gb]`) leak into the "DUT" toggle
  denominator uncounted as excluded — inflating the module count and dragging the score down by
  whatever fraction of *that whole module's* declared bits happened to be un-toggled, which has no
  relationship to any single signal's bit width. This is why a swing from fixing it looks "impossible
  under simple bit-weighting": it isn't a bit-weighting effect at all, it's a **scoping** bug — an
  entire miscategorized module either counted or not counted, not a handful of individual bits.
  `gen_exclusions.py` was already fixed (unconditional wildcarding of every non-DUT declared name,
  `name + "*"`, regardless of module/package/interface/clocking kind, specifically because "there is
  no reliable static rule for WHICH modules xsim will rename"). **Verified this pass** (not assumed):
  regenerated `dv/pmtpc4_cov_exclusions.txt` fresh from `gen_exclusions.py` and diffed it against the
  checked-in copy — byte-identical, confirming the fix is already in effect and current. Cross-checked
  the live `code_report`'s module listing: exactly 5 DUT modules (`pmtpc4`, `pmtpc4_apb_slave`,
  `pmtpc4_regblock`, `pmtpc4_channel`, `pmtpc4_regblock_pkg`), no `pmtpc4_top_sva`/`_default` or any
  other TB/SVA name present. **Conclusion**: W4 is resolved, not an open mystery — the fix predates
  this write-up and is confirmed still active; this session's contribution was tracing the root cause
  to its actual mechanism and giving it the documentation it never received, plus confirming (via a
  direct `xcrg`-only re-run against the existing coverage database, no new simulation) that removing
  the exclusion file entirely reports 9.8% toggle across 55 TB+DUT instances — a completely different,
  uninformative population, not a valid "unwaived DUT" baseline — which is itself a useful negative
  result: there is no clean way to measure "DUT toggle % with zero scoping" from this tool's report
  structure, so the DUT-scoped report (currently 46.0%) is the only meaningful number to track.

**Verification status — CONFIRMED 2026-09-20**: full regression re-run after the batched F15 fixes:
`40/40 runs passed`, zero `raw_ERROR`/`SVA` failures anywhere. Directly confirmed the fix is real, not
cosmetic: `x_duty_class_pwm_en`'s cross-cell hit counts now sum to exactly **183** (8+25+41+6+28+59+
3+5+1+7), precisely matching `cp_duty_class`'s own gated total — down from the pre-fix 102,510, a
~560x reduction, and all 10 cells remain genuinely covered (nonzero) on the corrected, properly-gated
sampling. W4 required no code change (the real fix already existed and was independently re-verified
byte-identical); nothing further to run for it.
