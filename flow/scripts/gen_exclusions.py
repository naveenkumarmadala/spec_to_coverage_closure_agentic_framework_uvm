#!/usr/bin/env python3
"""
gen_exclusions.py — generate an IP-agnostic xsim code-coverage exclusion file that
scopes code coverage to the DUT RTL, by classifying every source in the IP's
filelist as DUT vs verification and waiving the verification modules/packages.

DUT        = files under  ips/<ip>/rtl/  or  ips/<ip>/rdl/generated/rtl/
Verification (waived) = everything else in the filelist (the reusable bus VIP,
             the RAL package, the env/test package, the TB top, the interface,
             bound SVA checkers) plus the UVM library.

The DUT-scoping part is auto-generated and re-runnable; it never hand-lists IP-specific
names. Per-signal code-coverage waivers (e.g. structurally-dead toggle nets that no
stimulus can flip) are IP-specific and live in a MAINTAINED sidecar,
  ips/<ip>/dv/<ip>_toggle_waivers.txt ,
which this script appends verbatim so regenerating the DUT scope never loses them. Each
sidecar line is a clean xcrg directive (e.g. `signal -<name>`) with '#' justification
lines; keep only whole-signal waivers that cannot toggle by construction (see the
coverage-triage skill -- never a blanket wildcard to manufacture 100%).

Usage:  python3 flow/scripts/gen_exclusions.py ips/<ip>
Output: ips/<ip>/dv/<ip>_cov_exclusions.txt   (xsim/xcrg -ccExclusionFile format)
"""
import re, sys
from pathlib import Path

# Declarations that xsim elaborates as a named "module" in the coverage database.
# NOTE `clocking`: xsim elaborates every clocking block of an interface as its OWN
# module (e.g. apb_if's `drv_cb` shows up as instance <tb>.apb.drv_cb), so waiving
# the parent interface does NOT take its clocking blocks out of scope. Left
# unwaived, a VIP interface's clocking block silently adds its sampled nets to the
# DUT toggle denominator.
DECL = re.compile(r"^\s*(?:default\s+)?(module|package|interface|clocking)\s+(\w+)", re.M)


def sources_from_filelist(sv_dir: Path):
    """Resolve the source files referenced by dv/sv/filelist.f (relative to it)."""
    fl = sv_dir / "filelist.f"
    srcs = []
    if not fl.exists():
        return srcs
    for line in fl.read_text(errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("-"):
            continue
        p = (sv_dir / line).resolve()
        if p.exists():
            srcs.append(p)
    return srcs


def decls_in(path: Path):
    try:
        return DECL.findall(path.read_text(errors="replace"))
    except Exception:
        return []


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: gen_exclusions.py ips/<ip>")
    ip_dir = Path(sys.argv[1]).resolve()
    ip = ip_dir.name
    sv_dir = ip_dir / "dv" / "sv"
    rtl_dirs = [(ip_dir / "rtl").resolve(), (ip_dir / "rdl" / "generated" / "rtl").resolve()]

    waive = set()
    for src in sources_from_filelist(sv_dir):
        is_dut = any(str(src).startswith(str(d)) for d in rtl_dirs)
        if is_dut:
            continue                                  # keep DUT RTL in coverage scope
        for kind, name in decls_in(src):
            # xsim elaborates SOME modules/interfaces under a variant name rather than
            # their literal declared name -- confirmed empirically for THREE distinct
            # cases so far: an interface's default modport ("<name>_default"), a
            # generate-block-containing module bound into per-instance hierarchy
            # (pmtpc4_top_sva -> "pmtpc4_top_sva_default", found 2026-09-19 via a
            # verification-reviewer audit: it left toggle/branch/condition scored on
            # testbench SVA code, not just DUT), and an interface's own clocking block
            # elaborating as its own separate module (handled by the `clocking` DECL
            # keyword above). There is no reliable static rule for WHICH modules xsim
            # will rename, so every non-DUT name is wildcarded unconditionally rather
            # than special-cased per `kind` -- a name-exact directive that silently
            # stops matching post-elaboration is a worse failure mode (inflates the
            # DUT coverage denominator without any warning) than a wildcard being
            # slightly broader than strictly needed on verification-only names.
            waive.add(name + "*")
    waive.add("uvm_pkg")                              # simulator-provided UVM library

    out = ip_dir / "dv" / f"{ip}_cov_exclusions.txt"
    # PURE DIRECTIVES ONLY -- no comments. xcrg rewrites this file in place and splits
    # keyword words out of comment text; with several comment lines that corruption makes
    # xcrg drop *all* exclusions ("module ... not found"), silently un-scoping the report.
    # A comment-free file is reliable; the documentation lives in the companion README.
    lines = [f"module -{name}" for name in sorted(waive)]

    # Append the maintained per-signal waiver sidecar (its clean directive lines only), so
    # regenerating the DUT scope never drops the hand-justified code-coverage waivers.
    sidecar = ip_dir / "dv" / f"{ip}_toggle_waivers.txt"
    n_sig = 0
    if sidecar.exists():
        directives = [l.rstrip() for l in sidecar.read_text(errors="replace").splitlines()
                      if l.strip() and not l.lstrip().startswith("#")]
        n_sig = len(directives)
        lines += directives

    # LF line endings are mandatory: xcrg matches the whole line, so a trailing '\r' (what
    # Path.write_text emits on Windows) turns "module -foo" into "module -foo\r" -> "not
    # found" and ALL exclusions are silently dropped. .gitattributes also forces LF here.
    out.write_text("\n".join(lines) + "\n", newline="\n")

    # Companion README carries the human documentation (kept out of the xcrg-fed file).
    readme = ip_dir / "dv" / f"{ip}_cov_exclusions.README.md"
    readme.write_text(
        f"# {ip} code-coverage exclusions ({out.name})\n\n"
        "AUTO-GENERATED by `flow/scripts/gen_exclusions.py` -- do not hand-edit the .txt; "
        "re-run the script instead. The .txt is **pure directives, no comments** on purpose "
        "(xcrg corrupts comment lines via its in-place rewrite and then drops all "
        "exclusions).\n\n"
        "- **`module -<name>`**: DUT-scoping. Waives verification code (VIP / tests / RAL / "
        "TB / bound SVA checkers) and the UVM library so code coverage scores the DUT only.\n"
        f"- **`signal -<name>`**: per-signal code-coverage waivers, sourced from the "
        f"maintained sidecar `{ip}_toggle_waivers.txt` (which carries the justifications). "
        "Each is a whole DUT signal that cannot toggle by construction, or a proven tool "
        "artifact -- never a reachable-but-hard bit.\n\n"
        "Satisfies REQ-VERIF-2 (machine-enforced waiver list). Full rationale per waiver is "
        "in `reports/coverage_waivers.md`.\n", newline="\n")

    print(f"wrote {out}  ({len(waive)} verification modules/packages waived; DUT RTL kept in "
          f"scope; {n_sig} per-signal waivers from sidecar) + {readme.name}")


if __name__ == "__main__":
    main()
