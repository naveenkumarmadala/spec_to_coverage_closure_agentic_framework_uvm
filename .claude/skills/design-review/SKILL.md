---
name: design-review
description: Method and checklist for reviewing RTL against the design specification, register specification, and requirements — independent semantic conformance, not lint/elaboration (that's the static gate). Use when RTL is claimed complete or has just been changed (including by coverage-closure), before or alongside verification effort.
---

# Design review (RTL vs. spec vs. requirements)

The static gate (`lint-static-checker`) proves RTL is clean, elaborable, and synthesizable. It does
**not** prove RTL does what the spec says. This skill is that second, independent check: read the
spec cold, re-derive what the RTL *should* do, then read the RTL and compare — don't start from the
RTL's own comments and confirm they sound reasonable. A `// impl SPEC-012` tag is a claim, not proof.

This is grounded in real signoff practice (e.g. OpenTitan's D2/D3 design-stage checklist): an
independent reviewer, port/architecture frozen, deleted/changed logic specifically re-examined, no
open TODOs, waivers signed off — not just "the tool didn't complain."

## Why this exists (evidence, not theory)

On a real IP carried through this flow, four bugs shipped past lint, elaboration, and initial
smoke-testing before being caught — all four were **RTL that plausibly looked right** but
implemented something other than what the spec said:
- A protocol phase decoded from a *registered* state instead of combinationally — one cycle of
  timing wrong on every transaction, invisible unless you check the spec's cycle-by-cycle rule, not
  just "does it eventually respond."
- An FSM transition that skipped a state the spec's own transition table required.
- A register bit whose clear condition the spec required but the RDL simply didn't declare.
- A live register read where the spec explicitly required a shadowed (latched-at-an-event) value.

None of these were syntax errors, latches, or elaboration failures. All four were caught only by
a human-grade, spec-literal reading — which is exactly what this skill is for.

## Method

1. **Rebuild the contract before reading the RTL.** For the module/feature under review, extract
   the exact prose from `design_spec.md`, the register bit-field semantics from `<ip>.rdl` /
   `spec/*Register*`, and the REQ-ID wording from `requirements.md`. Write down what you expect to
   see in the RTL *before* opening the RTL file — this prevents anchoring on whatever the RTL already
   does.
2. **Walk every REQ/SPEC ID that traces to this module** (via the RTL's own `// impl SPEC-x / REQ-y`
   tags, and via `vplan.yaml`'s `traces_to`) and confirm, line by line, that the implementation
   matches the contract from step 1 — not that it's plausible, that it's what was actually specified.
   Flag any REQ/SPEC with no implementing construct at all.
3. **Specifically hunt for these bug classes** (each one bit a real IP in production use of this
   framework):
   - **Combinational-vs-registered timing on a bus/protocol phase.** If the spec describes a
     same-cycle response (e.g. a ready/ack signal), check whether the RTL decodes the triggering
     condition combinationally or from a registered state one cycle behind. Trace the exact cycle
     the spec says a signal should assert against the exact cycle the RTL asserts it.
   - **FSM transition-table fidelity.** Build the transition table the RTL actually implements
     (state × condition → next state) and diff it against the spec's own table. A state skipped, an
     edge merged, or a condition inverted will not show up as a lint/elaboration failure.
   - **"Takes effect at next X, not immediately" semantics.** Any spec language like "a write while
     running takes effect at the next reload/boundary" implies a shadow register latched at that
     boundary. Grep for every register field mentioned that way and confirm the RTL reads a latched
     copy, not the live register, in the datapath that uses it.
   - **Hardware set/clear precedence on W1C / status fields.** Multiple hardware and software write
     sources (hwset, hwclr, sw write, reset) on the same bit almost always have an unstated precedence
     the spec assumes — verify the generated precedence actually matches spec intent for every
     same-cycle collision case (e.g., "does a clear win over a simultaneous set, or vice versa,
     and is that what the spec wants").
   - **Freeze/pause/disable interactions.** Any global enable/freeze/pause signal that's supposed to
     hold state exactly (not reset it, not let it drift) — confirm every piece of state actually
     stops (counters, output levels, pending pulses), not just the obvious ones.
   - **A shared/derived condition reused more broadly than one specific formula needs.** RTL often
     factors out a convenience signal like `active = (state != IDLE)` and reuses it everywhere "active"
     seems relevant — but the spec frequently states a *narrower* condition for one specific output
     (e.g. "PWM level is only meaningful in RUNNING or PAUSED," which is not the same as "not IDLE";
     LOAD and EXPIRED are also "not IDLE" but not RUNNING/PAUSED). Confirm every downstream use of a
     broad, reused condition against that specific use's own spec formula, not just against the
     convenience signal's name sounding right. This bit a real IP in this project: a `ch_active`
     signal correctly meaning "not idle" for STATUS.BUSY was reused, unmodified, to gate PWM output —
     where the spec's actual formula was strictly narrower — producing a real output glitch during the
     LOAD state that survived because the RTL was internally self-consistent and a testbench checker
     had copied the same (too-broad) condition rather than the spec's own.
4. **Independent-reviewer discipline.** Do not accept an inline comment's justification for *why*
   something is correct — re-derive it yourself from the spec. If the comment and your own
   independent read disagree, that's a finding, not a tie-breaker in the comment's favor.
5. **Check what changed, not just what exists**, when reviewing RTL that another agent (especially
   `coverage-closure`, which is allowed to edit RTL to close holes) modified after the fact: `git diff`
   every touched file and re-run steps 1-3 scoped to the diff. A fix for one requirement can silently
   violate another (e.g. widening a comparison to fix a boundary case, but breaking a different
   corner the spec also requires).
6. **Confirm traceability completeness**, not just correctness: every requirement in
   `requirements.md` should map to at least one RTL construct (directly, or via the register block it
   configures). A requirement with no home in the RTL at all is a finding regardless of whether
   anything is "wrong" per se.

## Output

A findings report, most-severe first:
- **CONFIRMED**: re-derived independently from the spec and the RTL both read, mismatch is certain.
- **PLAUSIBLE**: looks wrong but couldn't be fully confirmed without simulating (say so — this is a
  static, spec-literal review, not a substitute for dynamic verification; hand ambiguous cases to
  `verification-reviewer` or flag for a directed test).
- For each finding: the spec/REQ text, the RTL location, and the concrete scenario where they diverge
  (not just "this seems off").
- A traceability-completeness tally: N/M requirements with a confirmed implementing construct.

Do not fix anything found here yourself unless asked — this is a review, and the same discipline that
makes an independent design reviewer valuable (OpenTitan requires review "by a separate engineer")
applies here: reviewing and fixing in the same pass re-introduces the confirmation bias this skill
exists to avoid. Report; let `rtl-designer` (or the user) decide the fix.
