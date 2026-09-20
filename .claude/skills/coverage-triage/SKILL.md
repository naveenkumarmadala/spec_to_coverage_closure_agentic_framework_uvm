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

### Toggle "0%" isn't always a real hole — cross-check before you believe it, verify before you waive it

xsim's toggle instrumentation has real, reproducible blind spots that report 0% on signals that are
*provably* active. Don't take a 0/0 toggle report at face value — cross-check it against a **different**
coverage type from the **same** database before concluding anything:

- **`automatic` procedural locals never toggle-track**, regardless of stimulus. Every PeakRDL
  passthrough-cpuif regblock declares `automatic logic next_c` / `automatic logic load_next_c` per
  field inside an `always_comb` — these are recomputed fresh each evaluation, not persistent storage.
  100% generic and predictable from the `--cpuif` template: pre-seed `signal -next_c` /
  `signal -load_next_c` for every IP (see `register-designer`'s rules) rather than rediscovering this.
  The same applies to any other hand-authored `automatic` scratch variable in a mux/decoder.
- **Continuous-assign (`wire = expr`) alias signals sometimes don't get an independent toggle
  identity**, even when the expression is proven to vary. Signature: the alias reads 0/0 while a
  *different* coverage type on the exact same signal/database proves activity — e.g. a `wire start_trig`
  gating `if (start_trig)` shows the `if`'s branch-coverage TRUE count is nonzero, or a `wire cpuif_addr`
  aliasing an address port shows the functional address-coverpoint hit every bin. That contradiction
  *is* the confirmation it's a tool artifact, not something to take on faith — find the corroborating
  evidence before waiving.
- **A whole module can report "No Toggles in Module"** in xcrg's raw per-module toggle section — a
  stronger, cleaner signal of the same instrumentation gap than a per-signal 0%, seen on a small
  counter module whose `always_ff` increment is independently proven to execute hundreds of times via
  statement coverage. Don't mistake "no toggles found" for "nothing happened here."
  **Resolution, once independently corroborated (not before):** `module -<name>` (or the coarser
  `instance -<path>`) in the exclusion sidecar removes the whole module from the toggle denominator.
  This is a *categorically different* decision from a `signal -` waiver and should be labeled as such
  in the waiver doc, not folded into the same table: a signal waiver says "proven covered/dead, here's
  why"; a module exclusion for a zero-instrumentation module says "the tool produced no data at all, so
  we are declining to have this module's toggle metric count against the aggregate." **Measure the
  real cost before applying it** — excluding a module removes it from ALL FOUR metrics, not just
  toggle, and if that module happened to score 100% on statement/branch/condition (small modules often
  do), the aggregate for those metrics will move down slightly, not up. Report the actual before/after
  numbers for all four, not just the toggle win.
- **When a signal is a real register (not automatic, not an alias) and no other coverage type
  corroborates activity, don't assume — verify.** Write the targeted stimulus, run it, and if the
  toggle number still doesn't move, add a **temporary** `$display` at the RTL assignment site (revert
  it immediately after) to directly observe whether the value the register is being loaded with
  actually varies. If it does vary and toggle still reads 0/0, that's now an *empirically proven* tool
  artifact — safe to waive with the trace excerpt as evidence. If the value never actually varies, it's
  a genuine stimulus gap — fix the vseq, not the exclusion file. Don't skip straight to "probably a
  tool artifact" for a real register just because other signals nearby turned out to be one.

## Exclusion-file mechanics (xsim `-ccExclusionFile` — hard-won, bake in)

- **Granularity is module / instance / signal / dir ONLY — there is NO line/block/statement/branch
  exclusion.** So unreachable *statements/branches* (the FSM default, the self-clear else-legs) cannot
  be tool-excluded; they stay in the score and are accounted for in the **waiver document**
  (`reports/coverage_waivers.md`), which is the entire residual of the stmt/branch numbers.
- **`signal -<name>` matches by bare name across the ENTIRE design, not by hierarchical path — it does
  NOT "preserve module scoping."** If two different modules each declare a signal with the same name
  (a top-level pass-through wire and the submodule's own same-named port it feeds, for instance), one
  `signal -<name>` directive silently excludes BOTH — including a genuinely-covered signal in a module
  you never intended to touch. This is a *different* failure mode from "the waiver wasn't honored"
  (below): here the waiver IS honored, just too broadly, and can make the aggregate score **worse**
  than not waiving at all if the collateral signal was a real, positive contributor. Confirmed
  empirically: adding one such directive dropped a DUT toggle score by 0.6pp. **Before trusting any
  new `signal -` waiver, measure the aggregate score with and without it** (re-run `xcrg` on the
  existing database with the candidate line added, compare, then decide) — don't assume a
  correctly-named, correctly-justified directive is net-positive just because the specific bits you
  intended to hide are gone.
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
  `ips/<ip>/dv/<ip>_toggle_waivers.txt` (clean `signal -<name>` lines + `#` justifications);
  `gen_exclusions.py` appends the directive lines (stripping comments) after the auto DUT-scoping, so
  regenerating never loses them. Human rationale for every waiver (functional + stmt/branch + toggle)
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
