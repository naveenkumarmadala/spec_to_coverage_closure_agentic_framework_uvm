---
name: coverage-triage
description: Method for analyzing coverage holes and driving them closed — classifying each uncovered bin/item, choosing directed vs constrained-random remedies, handling unreachable bins with justified waivers, and rolling coverage up to requirement-level closure. Use during the coverage-closure loop.
---

# Coverage triage & closure

Goal: reach `coverage_goal_pct` **and** prove every requirement is covered — not just move a number.

## What "closed" means

An item is `closed` only when: its coverage bins are **hit**, the associated **checks pass**
(scoreboard/RAL/assertions actually verifying, not just running), and it **traces to a requirement**.
100% bins with a silent scoreboard is *not* closure.

## Triage each hole

For every uncovered bin / unmet target, classify:

1. **Reachable, not yet hit** — the common case.
   - Random didn't reach it → tighten/steer constraints, add a seed, or bias the distribution.
   - Needs a specific sequence → add a **directed** test.
   - Hand the concrete gap to `test-writer` with the exact bin and how to hit it.
2. **Unreachable by construction** — the bin can't occur given the design (e.g. a reserved encoding
   the RTL prevents).
   - Write a **justified waiver**: the bin, why it's unreachable, evidence (spec/RTL reference).
   - Record it in the report and (ideally) get sign-off. Never silently delete the bin.
3. **Blocked by a bug** — the bin *should* be hittable but a defect prevents it.
   - This is a finding, not a coverage task. File it back to `rtl-designer` (RTL bug),
     `register-designer` (RDL/reset mismatch), or `design-architect` (spec gap) with evidence.
4. **Over-specified coverage** — the bin doesn't correspond to real intent (bad vPlan).
   - Send back to `verification-planner` to fix the model — with justification, not to game the %.

## Closure-stimulus patterns (reusable across IPs)

When functional holes are "reachable, not yet hit," these patterns close them generically (content is
IP-specific, the pattern isn't):
- **Exercise every instance, not just instance 0.** The first IP's directed vseqs only touched
  channel 0, leaving ch1–3 FSM coverage at 0%. A closure vseq should loop over *all* instances and
  drive each through **every FSM state and transition** in its table.
- **Config-bin sweep:** write each config field's boundary + mid values (0/1/mid/max, all modes) so
  `cg_cfg`-style bins fill.
- **Native constrained-random traffic** (`rand`/`constraint`/`dist`, per `constrained-random`) for
  breadth + code-coverage toggle on datapaths; full-width raw bus writes to toggle bus bits.
- Add these as their own vseqs and include them in `<ip>_full_test` (union coverage).

## Code coverage: DUT scoping and the toggle reality

- **Score code coverage on the DUT only.** xsim instruments the UVM library, VIP, tests, and RAL too,
  which crushes the flat branch/toggle numbers. Generate the DUT-scoping exclusion file with
  `python3 flow/scripts/gen_exclusions.py ips/<ip>` (waives non-DUT modules; `run_regression.py`
  applies it). Read the *DUT* numbers, not the flat total.
  **xsim elaborates some modules/interfaces under a variant name, not their literal declared name** —
  confirmed for three distinct cases so far (an interface's default-modport `_default` suffix, an
  interface's own clocking block elaborating as a separate module, and a plain `module` containing
  `generate` blocks also getting a `_default` suffix). An exact-name exclusion silently stops matching
  post-elaboration with no error — it just quietly leaves testbench code in the DUT denominator. The
  script is hardened against this generically (every non-DUT name is wildcarded unconditionally, not
  matched exactly), but if you ever hand-write an exclusion line, wildcard it too rather than trusting
  the literal declared name. **Sanity check after every `gen_exclusions.py` run**: the code-report
  module list should contain only real DUT modules — if a `_sva`/`_pkg`/testbench name is still there,
  the exclusion for it isn't matching.
- **Statement/branch/condition** are the meaningful, closable code metrics. Recurring
  unreachable-by-construction classes to expect (justified waivers, not missing tests):
  - **FSM `default` arm** of a `case` over a fully-enumerated state reg — reachable only on an illegal
    encoding that can't occur.
  - **Self-clearing (singlepulse) register field `load_next` else-legs** in a PeakRDL regblock — the
    field loads every cycle to auto-clear, so the "don't load" branch is dead (e.g. SOFT_RESET,
    CH_START). Shows as "MISSING ELSE, ... 0F".
  - **Wrapper-bypassed submodule nets** — when a wrapper resolves errors/decoding itself and forwards
    only legal accesses, the inner block's error/stall/partial-write logic never activates.
- **Toggle has a structural ceiling** (register-storage/hwif bits parked at reset, unused upper bus
  bits on narrow registers, reserved fields). Improve it with full-range/full-width stimulus, then
  **waive genuinely-unreachable toggle nets per-signal with a written reason** — never a blanket
  wildcard to manufacture 100% (that's coverage-gaming, exactly what `verification-review` hunts).
  Expect diminishing returns: once the closure vseqs saturate the *reachable* datapath, more stimulus
  moves toggle negligibly — the residual is per-bit structural. Prove it (add the stimulus, measure),
  then waive/document.

### Toggle measurement integrity on xsim — fix the MEASUREMENT before you triage a single hole

Measured 2026-09-26 (Vivado 2025.1) by isolating the real DUT from the testbench one ingredient at a
time. Two testbench constructs silently corrupt xsim's code-toggle recording, and they — not "xsim
alias-wire blind spots" — produced most of the 0% toggle signals an earlier pass waived as tool
artifacts (every one of those waivers was wrong and has been removed):

- **`$dumpvars` merely being present in the elaborated design** stops toggle recording on some DUT nets
  (a counter flop, single-use `wire x = expr` nets) — even `$dumpvars(1, top)`, and even inside an
  `if ($test$plusargs(...))` that never executes (gating it is NOT enough; measured). It is what
  produced a module's "No Toggles in Module". **Rule: the dump is its own top module
  (`tb/<ip>_dump.sv`, active with `+DUMP`) that the code-toggle snapshot does not elaborate.**
- **A `bind`-ed white-box checker makes every DUT net it observes lose its toggle data** (the toggles
  are not re-attributed to the checker; they are just gone). Wrapping the port connection as `{x}` does
  not help. **Rule: binds live in their own top module (`tb/<ip>_binds.sv`); measure toggle on a second
  snapshot elaborated without that top or the dump top** (`xsim_flow.sh --toggle`, `<ip>_tcov`),
  running the same test and seed. The binds are read-only, and `run_regression.py` *verifies* identical execution (same
  pass status, scoreboard check count and register-bit toggle totals) before reporting that toggle.
  Assertions, functional coverage and statement/branch/condition keep coming from the normal build.
- Ruled out as causes (don't re-investigate): `wire x = expr` style, port-driven nets, unpacked arrays,
  parameter overrides, `-relax`, `-L uvm`/importing `uvm_pkg`, reusing one `xsim.cov` across tests,
  `-debug typical|all`, `-O0`.

**Genuine xsim toggle limitations that remain** (all found in the PeakRDL register block, and nothing
documented for 2026.1 changes them):
- **`automatic` block locals** (`next_c`, `load_next_c`, `is_valid_*`, `readback_data_var`) are listed as
  toggle points but never updated, and **no** exclusion form (bare, wildcard, hierarchical) removes all
  of their copies.
- **Nested-struct signals** (PeakRDL `field_storage`, `hwif_out`) are not instrumented for toggle at
  all, despite the docs' "non-dynamic struct members" claim — the register flops are invisible.
- **No bit-range exclusion** (`sig[31:16]` → "not declared").
- **Duplicate listings**: a net connected into two instance ports (e.g. via `{a, b}` concatenations)
  can be listed twice, and every exclusion form removes only one copy. Report the remaining copy as a
  documented constant (the DUT toggle summary does this for any sidecar-listed signal).
- **The xcrg dashboard's toggle aggregate is not a DUT metric** — it averages over report files and
  always counts the UVM library's file at 0%. Use `reports/_cov/toggle_summary.txt` (bit-weighted).

**So a generated register block's toggle cannot be measured by xsim code coverage.** Exclude that module
from the *toggle* report only (a `module -` line in the toggle sidecar; `gen_exclusions.py` keeps it out of
the stmt/branch/cond report) and measure its register storage with **`reg_bit_toggle_cov`**
(`vip/common/sv/reg_bit_toggle_cov.svh`): every bit of every RAL field, rise and fall, as read back from
the DUT on the bus (functional coverage, reported reliably), with a closure test that bit-bashes the
writable bits, pulses the `singlepulse` ones and drives every hardware-set read-only bit both ways.

- **Before waiving a real register as "tool artifact", verify**: targeted stimulus first; if it still
  reads 0/0 in the toggle build (no dump, no binds), add a **temporary** `$display` at its assignment
  (revert after) to see whether the value actually varies. Varies → proven tool gap, waive with the
  trace as evidence. Doesn't vary → stimulus gap, fix the vseq.

## Exclusion-file mechanics (xsim `-ccExclusionFile` — hard-won, bake in)

- **Granularity is module / instance / signal / dir ONLY — there is NO line/block/statement/branch
  exclusion.** So unreachable *statements/branches* (the FSM default, the self-clear else-legs) cannot
  be tool-excluded; they stay in the score and are accounted for in the **waiver document**
  (`reports/coverage_waivers.md`), which is the entire residual of the stmt/branch numbers.
- **Name `signal -` waivers by hierarchical DOT path**: `signal -<tb_top>.dut.<inst>.<sig>` excludes
  exactly that one signal (tested on 2025.1; the slash form `/tb/dut/sig` is NOT accepted). A **bare**
  `signal -<name>` matches that name across the entire design — if another module has a same-named
  signal (a top-level pass-through and the submodule port it feeds), both are excluded, which can drop
  real coverage and move the score *down* (measured −0.6pp once). Wildcards with an instance
  (`signal -*u_inst*name`) also work. **Measure every new waiver**: re-run `xcrg` on the existing
  database with and without the line and compare.
- **Confirm every waiver actually helped, in the other direction too — don't assume a
  correctly-formatted, correctly-justified `signal -` waiver moved the score, even for a pattern
  that recurs dozens of times.** This is not a rare edge case: a session that added 12 `signal -`
  waivers found only ~5 had any measurable effect; the rest (including a PeakRDL `automatic`-local
  pattern repeated ~150 times across every field of a regblock) were silently not honored despite
  being syntactically identical to the ones that worked. The symptom is easy to miss because the
  *aggregate* score still moves (from the waivers that did work), giving false confidence that
  "waivers are working" as a category. **The reliable check**: take the real, full exclusion file,
  remove just the one line/pattern you're verifying, regenerate the report, and diff the score
  against the full-file version. If the delta is near zero, the exclusion isn't taking effect no
  matter how correct it looks — say so in the waiver doc rather than reporting the aggregate
  improvement as if it came from where you expected. When it's not honored, a low module-level
  score can look catastrophic while the *actual* unaddressed residual (once you mentally subtract
  the mismeasured pattern) is much smaller — reconstruct and report the real residual, not the raw
  number, when this happens.
- **The file MUST be pure LF directives, no comments.** Two silent failure modes, both of which make
  xcrg emit "module ... not found" and drop *every* exclusion (report un-scopes, branch/cond collapse
  as UVM re-enters scope): (1) a trailing `\r` (Windows CRLF) — write with `newline="\n"`;
  (2) `#` comment lines — xcrg's in-place rewrite splits keyword words out of them. Keep justifications
  in the sidecar / README, never in the file fed to xcrg. Symptom to check: dashboard module count
  jumps (e.g. 8→22) and `grep "not found" xcrg.log` is non-zero.
- **Per-signal waivers are IP-specific → maintained sidecar.** Put them in
  `ips/<ip>/dv/<ip>_toggle_waivers.txt` (clean directive lines + `#` justifications). `gen_exclusions.py`
  writes two files: `<ip>_cov_exclusions.txt` (DUT scoping only — stmt/branch/cond report) and
  `<ip>_toggle_exclusions.txt` (scoping + the sidecar — code-toggle report), so a whole-module toggle
  exclusion never costs that module its statement/branch/condition data. Regenerating never loses them. Human rationale for every waiver (functional + stmt/branch + toggle)
  goes in **`reports/coverage_waivers.md`** — produce this per IP; it is the signed-off artifact.
  **Edit the sidecar, never the generated `<ip>_cov_exclusions.txt` directly** — it's regenerated by
  `gen_exclusions.py` and a hand-edit there is silently lost the next time anyone re-runs it. After
  editing the sidecar, re-run `gen_exclusions.py` and diff the output against what you expected as a
  sanity check that the sidecar change actually took effect.
- **There is no bit-range/bit-select exclusion syntax — confirmed, not assumed.** `signal -foo[31:16]`
  is silently accepted by the parser but never matches anything; xcrg logs
  `WARNING : Signal Name 'foo[31:16]' mentioned in exclusion file is not declared in the given design.
  Hence, it is ignored.` and the exclusion has zero effect. This is the documented AMD behavior too
  (UG937 "Code Coverage Exclusion Support", UG900 "Code Coverage Support": both specify only
  module/instance/signal/dir/file granularity). So a signal that mixes genuinely-active bits with
  structurally-dead ones (the common case: an N-bit register field read back through a wider bus,
  e.g. a 16-bit COMPARE value on a 32-bit APB read-data bus) **cannot be partially waived** —
  whole-signal-excluding it would discard the real coverage on the active bits along with the dead
  padding.
  **The fix is an RTL split, not a cleverer exclusion file.** In the hand-authored RTL (never in a
  PeakRDL-generated file — see below), decompose the mixed signal into two independently-declared
  signals, e.g. `foo_active` (the real bits) and `foo_pad` (the always-zero bits), and eliminate the
  original combined signal entirely rather than keeping it as a redundant alias (a port can be
  connected directly to a concatenation expression, `{foo_pad, foo_active}`, on both the driving and
  receiving side — legal per IEEE 1800 §23.3.3.7 — so no intermediate wire is needed). This gives each
  half its own toggle-tracked identity: `foo_active` shows real coverage, `foo_pad` is safe to
  whole-signal-exclude with zero risk of hiding anything. Re-verify after the split that the *original*
  signal name has actually disappeared from the report (not just gained a sibling) — if a redundant
  alias of the old combined signal still exists anywhere (e.g. the same value also flows, unsplit,
  through another module's port on its way further downstream), that copy still needs its own
  disposition; don't assume splitting once has propagated the fix everywhere the value travels.
  **Never hand-edit this technique into a PeakRDL-generated file** (anything under
  `rdl/generated/rtl/`) — a future regeneration silently discards the change and reintroduces the
  identical gap invisibly. If the mixed-bits signal lives inside generated code, leave it as
  documented residual (matching the existing project precedent of not over-waiving there) rather than
  hand-editing generated output.
  **Do this proactively, not reactively — but only for the READ side.** A PeakRDL passthrough
  regblock's `cpuif_rd_data` mismatch (bus width wider than every implemented field) is entirely
  predictable before a single test runs — `register-designer` reports the widest field's top bit after
  generating, and `rtl-designer` applies this exact split at the top-level integration point as a
  standard step whenever that's narrower than `bus.data_width`. Waiting for `coverage-closure` to
  discover this after the fact costs real investigation time re-deriving something that was knowable at
  RTL-authoring time. This only ever closes the *top-level* (hand-written RTL) copy — the regblock's own
  internal copy of the same mismatch, inside generated code, stays a smaller, permanent,
  honestly-documented residual regardless of how early the top-level split happens.
  **`cpuif_wr_data`'s unused upper bits are a different kind of gap and must not be waived the same
  way.** The readback pad is structurally constant (the RTL itself builds it as zero-extension); the
  write-data upper bits come from the external bus and are only zero because RAL-driven writes happen
  to zero-extend a narrow field — nothing in the RTL prevents a real value from appearing there. Treat
  it as *reachable, not yet hit* (category 1, above): the fix is a raw/non-RAL directed write with
  garbage in the unused bits, confirming readback is unaffected — real stimulus with real verification
  value (proves the RTL ignores those bits rather than assuming it), not a split-and-waive.
  **Do NOT generalize this split technique to "delete a named continuous-assign alias and write its
  expression inline at its one use site" for a plain boolean/control alias (e.g. `wire start_trig =
  a | (b & c);` used once in `if (start_trig)`) — that is a different move with the opposite effect,
  confirmed by direct measurement, not theory.** The `cpuif_rd_data` split works because it replaces
  one wire with **two other named, independently declared, still-waivable signals** — there is always
  something with a name left for the exclusion file to reference. Deleting a wire and inlining its
  expression leaves **no replacement name at all**: `xcrg` was observed to still track toggle points
  for the inlined expression's sub-terms, but as anonymous entries a `signal -<name>` directive has
  nothing to match, while the *old* waiver for the now-deleted wire (if one existed) starts matching
  nothing too. Net effect measured on a real IP: one module's DUT toggle score dropped from 100% to
  40% after inlining five such aliases, and the aggregate score dropped by ~10 percentage points —
  the opposite of the intended fix. If a plain alias wire is a proven tool artifact (per the
  corroborating-evidence check above) and already carries a `signal -` waiver that's confirmed to
  take effect, **leave it as a named wire** — there is no known safe way to eliminate it that
  actually improves the score; inlining is not that way, and neither is a hierarchical port
  reference across two module instances (see `lint-static-checker`'s note on that — it also fails,
  differently, by silently truncating width under `sv2v`). Only touch this class of signal again if a
  new technique is found and it is verified with a real before/after regression, never on the
  strength of the `cpuif_rd_data_pad` precedent alone.

## Parsing xcrg's raw HTML reports directly (if you ever need per-line/per-signal detail)

`xcrg`'s functional/code coverage reports are HTML (no usable text format for code coverage — asking
for `-report_format text` prints `WARNING : Text based reporting is not supported for Code Coverage
yet.` and falls back to HTML anyway). If you need finer-grained detail than the dashboard/module
summary tables give you (e.g. exactly which branch or toggle entry is 0), two rendering quirks will
silently corrupt a naive parse:
- **A fully-zero outcome renders as a blank cell, not the literal text "0".** A parser that treats an
  empty cell as "no data, skip this row" will silently drop every genuinely-uncovered item and only
  see the covered ones — the opposite of what you want. Only filter on the presence of a `Branch N`/
  `Toggle N` label in the row, never on whether the count cell has content.
- **The second outcome of a branch (typically the FALSE leg) can render as a separate `<tr>` with a
  blank LineNumber cell**, immediately following the row that has the real line number — a naive
  parser keyed on "does this row have a digit in column 1" drops these continuation rows entirely,
  under-reporting how many outcomes a branch actually has. Carry the last-seen real line number forward
  onto blank-line-number rows instead of discarding them.

## Roll-up to requirements

Map every bin/assertion/RAL result → its `VP-` item → its `traces_to` REQ IDs. Report:
- overall coverage %, split functional / code / assertion;
- a per-REQ table: covered? by which VP items? closed/open;
- the open-holes list with each hole's disposition (which class above), owner, and action;
- all waivers with justification.

## Anti-patterns (never do these)

- Deleting or coarsening a bin to hit 100%.
- Reporting bins-hit as closure while checks are disabled/absent.
- Waiving a reachable bin because it's hard — that's a missing test, not a waiver.
- Claiming a number you didn't get from merged tool output.
