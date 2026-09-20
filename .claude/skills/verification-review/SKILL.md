---
name: verification-review
description: Method for auditing verification collateral (the SystemVerilog UVM environment, scoreboards, assertions, tests, coverage model, waivers) for whether it is actually trustworthy, not just green. Use once coverage closure is claimed, or whenever the DV environment changes, before treating verification as signed off.
---

# Verification review (is the checking real?)

`coverage-closure` proves a coverage *number*. This skill audits whether that number means anything —
whether the environment that produced it can actually detect a bug, not just accumulate green
checkmarks. This is grounded in real signoff practice: OpenTitan's V3 stage requires a green
multi-seed regression with a week of soak time, 100% coverage, and a clean testbench lint — but real
DV teams additionally qualify the *testbench itself* via mutation/bug-seeding analysis, because
100% coverage with a broken checker is worse than no coverage at all (it hides the fact that nothing
was verified).

## Why this exists (evidence, not theory)

On a real IP carried through this flow, the *first-generation* coverage environment reached "100%"
while checking almost nothing: tests called the coverage API directly to mark a bin covered,
disconnected from any signal the environment had actually checked. Every number was real in the sense
that the code ran; none of them were evidence the DUT behaved correctly. The failure was invisible
from the coverage report alone — it only showed up when someone read what the sampling call sites
were actually attached to. That is exactly the class of problem this skill exists to catch before it
reaches signoff, on any IP, before it happens again.

## Method

### 0. Spec-independence — the precondition everything below assumes

Before checking whether a checker fires, check what it's actually checking *against*. A checker,
assertion, covergroup bin, or waiver justification is only evidence of correctness if its expected
value/condition was derived from the **design spec and register spec**, independently of the RTL that
implements it. If it was derived by reading the RTL and transcribing what the RTL does, it will agree
with the RTL by construction, forever, including when the RTL is wrong — and no amount of mutation
testing will ever reveal that, because mutation testing only proves a checker reacts to a *deliberate*
change; it cannot prove the checker's original formula was correct in the first place. A checker and
the RTL it checks can be in perfect, permanent agreement while both are wrong about the requirement.

**This happened on a real IP in this project**, not hypothetically: an assertion's own header comment
said "we rebuild that exact register here" and then copied the RTL's `(state != S_IDLE)` gating
condition verbatim, where the design spec's literal text was `(state==RUNNING||PAUSED)` — a strictly
narrower condition. The assertion and the RTL agreed on every mutation ever tried, because they were
the same formula. The bug (PWM glitching high during the LOAD state) survived multiple dedicated
mutation-testing review passes and was only found by accident, much later, from reading raw simulator
console output during an unrelated waveform inspection. A companion `illegal_bins` coverage classification
had *already* independently claimed the same wrong behavior was "structurally unreachable" — reasoned
from RTL timing ("LOAD lasts exactly one tick") rather than cross-checked against the spec's PWM
formula — so the coverage model was complicit, not just the assertion.

**The line that matters, and how to apply it to every item in §2/§3/§5/§6 below:**
- RTL may tell you **how to observe** something: signal names, port widths, clock domain, timing
  relative to an edge (preponed-region issues, registered-vs-combinational, latency). That's
  structural knowledge with no other source, and reading the RTL for it is correct and necessary.
- RTL must never tell you **what the correct value or condition is**. That answer comes from the
  design spec / register spec text, quoted, not paraphrased from memory of what the RTL does.
- For every checker/assertion reference-model expression, find the exact spec paragraph it implements,
  quote it, and diff it word-for-word (not "sounds like the same idea") against the code. A comment
  that *cites* a spec section number is not evidence the code *matches* that section's text — verify
  the citation, don't trust it.
- Apply the identical discipline to `illegal_bins`/`ignore_bins` coverage classifications and to
  "unreachable by construction" waiver justifications (§5, §6) — these are claims of correct behavior
  exactly as much as an assertion is, and a proof reasoned purely from RTL timing/structure (without an
  independent spec cross-check) is not sufficient, no matter how rigorous the RTL-side reasoning looks.
- If a claim is only reasoned from the RTL — even correctly, even with real empirical testing behind
  it — that is itself a finding: not necessarily "this is wrong," but "this has not been shown to be
  right by the standard this project requires." Say so explicitly rather than letting a well-argued
  RTL-only justification read as equivalent to a spec-grounded one.

### 1. Environment architecture — is anything actually wired up and firing?
- Confirm the driver/sequencer/monitor/scoreboard/coverage-collector chain described in
  `uvm-env-scaffold` is fully connected: sequencer → driver (via `seq_item_port`/`get_next_item`),
  monitor → scoreboard and monitor → coverage collector (via analysis ports/exports), env → agent(s)
  via `config_db`. An unconnected analysis port silently means "never called," not an error.
- For each agent/interface, confirm the monitor is sampling on the interface's actual clocking event
  (not a stray `#0` or a never-asserted trigger) and confirm at least one test actually exercises it
  (a monitor that never sees a transaction is as dead as one that isn't wired at all).
- Check every `uvm_config_db`/`ConfigDB` `set`/`get` pair by name and type — a mismatched string key
  or type parameter fails silently (build succeeds, the wrong/default object is used).

### 2. Scoreboard/checker vacuity — does it ever actually fail?
- **First, §0**: confirm the comparison's expected-value side was derived from spec, not from reading
  the RTL it's checking. Vacuity (below) and spec-independence (§0) are different failure modes — a
  checker can be fully non-vacuous (fires reliably on real mutations) and still be checking the wrong
  thing, if what it fires on is "disagrees with the RTL" rather than "disagrees with the spec."
- For every comparison the scoreboard makes, confirm there is a code path where it **can** report a
  mismatch — not just a path where it reports a match. A checker that only ever calls "pass" is not
  a checker.
- Grep for the anti-pattern directly: any test or sequence file calling the coverage-sampling API
  (`sample`, `sample_event`, a covergroup `.sample()`, etc.) that is *not* inside the
  monitor/scoreboard's own check path is a finding — coverage must be a side effect of a check that
  just ran, never an assertion of intent by the stimulus code that created the scenario.
- Spot-check by **deliberate, temporary mutation** (the standard "bug seeding" / mutation-testing
  technique): pick a handful of RTL lines central to the requirement under review — especially any
  the design-reviewer or coverage-closure recently touched — and introduce a small, obviously-wrong
  change (flip a comparison operator, invert a condition, change a shadow-latch back to a live read).
  Re-run the affected tests. **If nothing fails, the checker for that behavior does not exist**,
  regardless of what the coverage report claims. Revert the mutation immediately after — this is a
  diagnostic, never a committed change.

### 3. Assertions — triggered, or vacuously true?
- **§0 applies here most directly**: an assertion's reference-model expression (any local register it
  builds to predict expected behavior, e.g. a mirrored/rebuilt version of a DUT signal) must be quoted
  from the spec formula, not copied from the RTL expression it's meant to be checking independently of.
  "We rebuild that exact register here" is the anti-pattern, not a plan — rebuild the *spec's* register,
  not the RTL's.
- For every `assert property`, confirm a companion `cover property` exists on the antecedent (the
  triggering condition) and that it has actually hit at least once in the regression. An assertion
  whose antecedent never fires is *vacuously* true — it "passes" by never being tested, which looks
  identical to a real pass in a bare pass/fail count.
- Cross-check the assertion's cover-hit count against the regression logs, not just its pass/fail
  status.

### 4. Tests — well-formed, or padding?
- Every test maps to ≥1 `vplan.yaml` ID (checked by `test-writer`'s own rule) — re-verify it's true,
  don't just trust the header comment.
- Every test is genuinely self-checking (scoreboard/RAL/reference-model predicts, the test does not
  eyeball a waveform or only check its own local state).
- `method: constrained-random` items actually randomize something meaningful (not a randomized value
  immediately overwritten or constrained to a single legal value).
- No test exists solely to "unconditionally hit a bin" (see §2) as opposed to creating a real
  scenario and letting an observer credit it.

### 5. Coverage model integrity
- **`illegal_bins`/`ignore_bins` unreachability claims are checker claims (§0 applies).** A proof
  reasoned purely from RTL timing/structure — even a real, empirically-tested one — is not sufficient
  on its own; cross-check it against the spec's independent statement of the same behavior before
  accepting it. An "unreachable" claim that turns out to only be unreachable under a narrower condition
  than the code covers (e.g. proven at one config value, applied as a blanket illegal_bin) is exactly
  the failure mode to hunt for here.
- Every bin traces to `vplan.yaml` (no orphan bins hiding outside the plan, no vPlan items with no
  bins).
- Bins are reachable and specific — no giant auto-bins or wildcard bins that can be satisfied by
  nearly anything, which inflate the percentage without proving anything precise.
- Sampling point is causally *after* the checked behavior occurred, from a signal the check just
  read (see §2) — not sampled speculatively before the outcome is known.

### 6. Waivers — legitimate, or convenient?
- Every waiver has a recorded justification tying it to a structural reason the point/bin is
  unreachable (a disabled feature, a tied-off port, an out-of-scope width) — not just "didn't get to
  it."
- Waivers should be matched **by rule/pattern** (a file/module/signal-name pattern, a structural
  predicate) rather than as a hand-maintained allow-list of specific point names. A pattern-matched
  waiver keeps catching *new* holes that happen to fall in the same reachable/unreachable class; a
  name allow-list silently stops working the moment the RTL changes shape.
- Spot-check a sample of "unreachable by construction" claims against the actual RTL/connectivity —
  confirm the claimed reason is structurally true, don't take the comment's word for it (same
  independent-reviewer discipline as `design-review`). **Structurally true against the RTL is not the
  same as correct** (§0) — also confirm the claim matches what the spec says should happen, not just
  what the RTL currently does; a waiver can be perfectly accurate about the RTL's behavior while that
  behavior itself is the bug.
- **Confirm the exclusion file actually applied — a broken exclusion silently *inflates* the DUT
  number, which is the opposite failure but just as invisible.** xsim's `-ccExclusionFile` fails
  silently and completely: a single `\r` (Windows CRLF) or a `#` comment line corrupts xcrg's in-place
  rewrite and it drops *every* exclusion, un-scoping the report so the UVM library/VIP re-enter the
  denominator. Checks: (a) `grep -c "not found\|No module name" <cov>/xcrg.log` must be **0**; (b) the
  code-report dashboard's in-scope module list must contain **only DUT modules** (no `uvm_pkg`,
  `apb_pkg`, `*_tb_top`, `*_sva`, `*_pkg`) — if the module count is suspiciously large the exclusions
  didn't take; (c) confirm the file fed to xcrg is pure LF directives with no comments; (d) for each
  `signal -<name>` toggle waiver, confirm it was actually honored (the signal's bits left the toggle
  denominator) — some are silently ignored, leaving the number unchanged and the waiver misleading.
  A DUT coverage number reported off an un-applied exclusion file is not trustworthy regardless of how
  well-justified the waiver list reads.
- **A waiver can be honored and still be wrong — check for over-broad matching, not just "did it
  apply."** xsim's `-ccExclusionFile` matches `signal -<name>` by bare name across the *entire* design,
  not by hierarchical path. If two different modules each declare a signal with the same name (a
  top-level pass-through wire and the submodule port it feeds is the common case), one directive
  excludes both — including a genuinely-covered signal in a module the waiver never meant to touch, net
  *decreasing* the trustworthy score while looking like a normal, honored waiver. Spot-check by
  re-running `xcrg` on the existing database with and without a sampled waiver line and comparing the
  score; a directive whose removal makes the score *go up* is a finding.
- **A whole-module `module -<name>`/`instance -<path>` DUT exclusion is a different, more consequential
  category than a `signal -` waiver and deserves more scrutiny, not less.** It should only apply to a
  module xcrg reports literally zero data for (its own report says something like "No Toggles in
  Module"), independently corroborated by a different coverage metric on the same database — not to a
  module that IS instrumented but merely scores low (that's a real gap, belongs in the closure loop).
  Confirm the before/after was actually measured for all affected metrics (excluding a module changes
  statement/branch/condition too, not just the metric it was aimed at), and confirm the waiver doc
  labels it distinctly from ordinary signal-level waivers rather than folding it into the same table.

### 7. Regression hygiene
- Confirm the environment actually runs on xsim (compile + elaborate + simulate), not just that files
  exist; a generated-but-unrun env is the exact failure mode this single-track framework was built to
  eliminate. If any construct can't run on xsim, confirm the gap is stated plainly, not silently absent.
- Full regression green across the configured seed count, no simulator compile/runtime warnings, the
  testbench code itself passes lint, no open TODOs in verification code — the same bar OpenTitan's V3
  stage applies to the DUT.
- **"Green" is only as trustworthy as what the pass/fail check actually parses.** `run_regression.py`
  determines pass/fail from `UVM_ERROR`/`UVM_FATAL`/SVA-failure/scoreboard-error counts — it does not
  scan for bare simulator `ERROR:` lines (e.g. an `illegal_bins` violation, which xsim prints as a raw
  `ERROR:` outside the UVM report mechanism entirely). A test can print real errors to the console and
  still be recorded as `ok=True`. Grep the **raw per-run log** (`reports/_runs/seed_<N>/<test>.log`) for
  `ERROR:` independently of the summary counts — do not trust "N/N passed" as evidence nothing printed
  an error.

## Output

A findings report, most-severe first, using the same CONFIRMED/PLAUSIBLE distinction as
`design-review`:
- **Vacuity findings** (§2, §3): name the specific checker/assertion, why it can't fail as written,
  and — where a mutation spot-check was run — what mutation was tried and what the (non-)result was.
- **Waiver findings** (§6): which waiver, why the justification doesn't hold up, and whether it's
  name-matched vs. rule-matched.
- **Coverage-model findings** (§5): which bins/items are non-specific or improperly sampled.
- A one-line verdict: is the coverage number *trustworthy* evidence of correctness, or a number that
  happens to be 100% for reasons unrelated to correctness? These are different claims, and this
  report's whole purpose is telling them apart.

Report; do not silently fix. If a mutation spot-check reveals a genuinely dead checker, that is
exactly the kind of finding that needs a human or `coverage-closure` to decide how to rebuild it —
not a quiet patch buried in a review pass.
