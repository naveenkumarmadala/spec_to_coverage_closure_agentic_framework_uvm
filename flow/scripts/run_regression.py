#!/usr/bin/env python3
"""
run_regression.py — single-track SV/UVM regression runner on Vivado xsim.

Compiles + elaborates an IP's UVM env once (with coverage), then runs every test
across N seeds, parses pass/fail, merges coverage across runs, and writes a
regression summary. IP-agnostic: tests are discovered from dv/sv/test/*.sv and
seed count from ip_config.yaml (verification.regression.seeds).

Usage:
    run_regression.py <ip_dir> [--seeds N] [--tests t1,t2,...] [--no-cov]

Run inside WSL2 with Vivado xsim reachable (see env/README.md). Emits:
    <ip_dir>/reports/_runs/seed_<N>/<test>.log     per-run log
    <ip_dir>/reports/regression.txt                one line per test/seed
    <ip_dir>/reports/_cov/_merged/                 merged coverage db + html (best effort)
"""
import argparse, glob, os, re, subprocess, sys, shutil
from pathlib import Path

HERE = Path(__file__).resolve().parent
XFLOW = HERE / "xsim_flow.sh"


def read_seed_policy(ip_dir: Path, base_default=1, rand_default=5):
    """Return (base_seeds, random_seeds, seeds_per_test) from ip_config.yaml.

    base_seeds     -> directed / seed-invariant tests (default 1; more is pure waste)
    random_seeds   -> fallback for a randomized test with no explicit per-test count
    seeds_per_test -> {test_name: N} explicit counts, sized to each test's random space
    """
    base, rand, per_test = base_default, rand_default, {}
    cfg = ip_dir / "ip_config.yaml"
    if cfg.exists():
        txt = cfg.read_text()
        m = re.search(r"^\s*seeds:\s*(\d+)", txt, re.M)
        if m:
            base = int(m.group(1))
        m = re.search(r"^\s*random_seeds:\s*(\d+)", txt, re.M)
        if m:
            rand = int(m.group(1))
        mb = re.search(r"^(\s*)seeds_per_test:\s*$", txt, re.M)
        if mb:
            indent = len(mb.group(1))
            for line in txt[mb.end():].splitlines():
                if line.strip() == "" or line.lstrip().startswith("#"):
                    continue                       # blank / comment inside the block
                if (len(line) - len(line.lstrip())) <= indent:
                    break                          # dedent -> end of the block
                mm = re.match(r"\s*([A-Za-z_]\w*):\s*(\d+)", line)
                if mm:
                    per_test[mm.group(1)] = int(mm.group(2))
    return base, rand, per_test


RANDOM_RE = re.compile(r"randomize\s*\(|\$urandom")
# tokens that name a sequence/item/test class we should follow to find randomization
_REF_RE = re.compile(r"\b(\w+(?:_vseq|_seq|_sequence|_item|_test))\b")


def build_class_index(ip_dir: Path):
    """Map every class name defined under dv/sv -> the full text of its file (over-
    approximate: all classes in a file share that file's text). Used to follow a test's
    sequence references and decide whether its stimulus is randomized."""
    idx = {}
    for f in glob.glob(str(ip_dir / "dv/sv/**/*.sv"), recursive=True):
        text = Path(f).read_text()
        for m in re.finditer(r"\bclass\s+(\w+)\b", text):   # \b so 'endclass' doesn't match
            idx.setdefault(m.group(1), text)
    return idx


def test_is_random(test: str, idx: dict) -> bool:
    """True if the test class, or any sequence/item it transitively references, contains
    native randomization. Fully generic — reads the source, needs no per-IP list."""
    seen, stack = set(), [test]
    while stack:
        name = stack.pop()
        if name in seen:
            continue
        seen.add(name)
        text = idx.get(name)
        if not text:
            continue                          # UVM built-in / external class: no source here
        if RANDOM_RE.search(text):
            return True
        for m in _REF_RE.finditer(text):
            if m.group(1) not in seen:
                stack.append(m.group(1))
    return False


def discover_tests(ip_dir: Path):
    tests = []
    for f in sorted(glob.glob(str(ip_dir / "dv/sv/test/*.sv"))):
        for m in re.finditer(r"\bclass\s+(\w+_test)\s+extends", Path(f).read_text()):
            tests.append(m.group(1))
    # base_test is abstract scaffolding; skip if a sanity/smoke test exists
    tests = [t for t in tests if not t.endswith("base_test")]
    return sorted(set(tests))


def sh(args, **kw):
    # errors='replace': xsim logs occasionally contain non-UTF-8 bytes (e.g. 0xFF); a
    # strict decode would crash the whole regression on one stray byte.
    return subprocess.run(args, text=True, capture_output=True, errors="replace", **kw)


def parse_log(text: str):
    def num(pat):
        m = re.search(pat, text)
        return int(m.group(1)) if m else None
    err = num(r"UVM_ERROR\s*:\s*(\d+)")
    fat = num(r"UVM_FATAL\s*:\s*(\d+)")
    sva = len(re.findall(r"Assertion failed", text))
    scb = re.findall(r"checks=(\d+)\s+errors=(\d+)", text)
    scb_checks, scb_err = (int(scb[-1][0]), int(scb[-1][1])) if scb else (None, None)
    ran = "UVM Report Summary" in text
    # Bare simulator ERROR: lines (e.g. an `illegal_bins` coverage violation) are NOT
    # routed through the UVM reporting mechanism at all, so UVM_ERROR stays 0 even
    # though the console printed a real error — a test can be recorded "ok=True" while
    # having printed exactly this. Confirmed missed in practice (2026-09-19): a
    # `cp_pwm_by_state.load_high` illegal-bin violation fired 24 times in a run that
    # UVM_ERROR/UVM_FATAL/SVA/scoreboard counts all reported clean. Anchored at line
    # start so it doesn't false-positive on `UVM_ERROR @ ...` lines (different prefix).
    raw_err = len(re.findall(r"^ERROR:", text, re.M))
    return dict(uvm_error=err, uvm_fatal=fat, sva_fails=sva,
                scb_checks=scb_checks, scb_errors=scb_err, ran=ran, raw_errors=raw_err)


def passed(r):
    return (r["ran"] and r["uvm_error"] == 0 and r["uvm_fatal"] == 0
            and r["sva_fails"] == 0 and (r["scb_errors"] in (0, None))
            and r["raw_errors"] == 0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ip_dir")
    ap.add_argument("--seeds", type=int, default=None, help="override seeds for directed tests")
    ap.add_argument("--random-seeds", type=int, default=None, help="override seeds for randomized tests")
    ap.add_argument("--tests", default=None, help="comma-separated; default=auto-discover")
    ap.add_argument("--no-cov", action="store_true")
    a = ap.parse_args()

    ip_dir = Path(a.ip_dir).resolve()
    ip = ip_dir.name
    base_seeds, rand_seeds, per_test = read_seed_policy(ip_dir)
    if a.seeds is not None:
        base_seeds = a.seeds
    if a.random_seeds is not None:
        rand_seeds = a.random_seeds
    tests = a.tests.split(",") if a.tests else discover_tests(ip_dir)
    cov = not a.no_cov
    if not tests:
        sys.exit(f"no *_test classes found under {ip_dir}/dv/sv/test/")

    # Seeds follow randomization intent, per test. A directed test targets one specific
    # scenario deterministically -> 1 seed is a complete run; sweeping it is byte-identical
    # waste. A randomized test gets an explicit seeds_per_test count (sized to its random-
    # variable space) or the random_seeds fallback. Directed vs randomized is detected from
    # the source, so this stays IP-agnostic.
    idx = build_class_index(ip_dir)
    def seed_count(t):
        if t in per_test:
            return per_test[t]
        return rand_seeds if test_is_random(t, idx) else base_seeds
    seeds_for = {t: seed_count(t) for t in tests}
    total_runs = sum(seeds_for.values())

    reports = ip_dir / "reports"
    reports.mkdir(exist_ok=True)
    print(f"== regression: {ip} | {len(tests)} tests | {total_runs} runs | coverage={'on' if cov else 'off'} ==")
    for t in tests:
        why = "explicit" if t in per_test else ("randomized" if test_is_random(t, idx) else "directed")
        print(f"     {t:30s} -> {seeds_for[t]:3d} seed(s)  [{why}]")

    # compile + elaborate once
    covflag = ["--cov"] if cov else []
    r = sh(["bash", str(XFLOW), "compile", str(ip_dir)])
    if r.returncode != 0:
        sys.stderr.write(r.stdout + r.stderr)
        sys.exit(f"COMPILE FAILED for {ip}")
    r = sh(["bash", str(XFLOW), "elab", str(ip_dir), *covflag])
    if r.returncode != 0:
        sys.stderr.write(r.stdout + r.stderr)
        sys.exit(f"ELABORATION FAILED for {ip}")
    print("   compile + elaborate: OK")

    rows = []
    for t in tests:
        for seed in range(1, seeds_for[t] + 1):
            seed_dir = reports / "_runs" / f"seed_{seed}"
            seed_dir.mkdir(parents=True, exist_ok=True)
            tag = f"{t}_seed{seed}"
            r = sh(["bash", str(XFLOW), "run", str(ip_dir), t, str(seed),
                    *covflag, *(["--covtag", tag] if cov else [])])
            log = r.stdout + r.stderr
            (seed_dir / f"{t}.log").write_text(log)
            res = parse_log(log)
            res.update(test=t, seed=seed, ok=passed(res))
            rows.append(res)
            flag = "PASS" if res["ok"] else "FAIL"
            print(f"   [{flag}] {t:28s} seed={seed:<3d} "
                  f"UVM_ERROR={res['uvm_error']} FATAL={res['uvm_fatal']} "
                  f"SVA={res['sva_fails']} scb_err={res['scb_errors']} "
                  f"raw_ERROR={res['raw_errors']}")

    # summary file
    npass = sum(1 for x in rows if x["ok"])
    with open(reports / "regression.txt", "w") as f:
        f.write(f"# {ip} regression — {npass}/{len(rows)} runs passed\n")
        for x in rows:
            f.write(f"seed={x['seed']} test={x['test']} ok={x['ok']} "
                    f"uvm_error={x['uvm_error']} uvm_fatal={x['uvm_fatal']} "
                    f"sva_fails={x['sva_fails']} scb_errors={x['scb_errors']} "
                    f"raw_errors={x['raw_errors']}\n")

    # per-test functional coverage reports (xcrg cross-db merge is unreliable on
    # xsim 2025.1 — see coverage_reports docstring)
    if cov:
        coverage_reports(ip_dir, tests)

    print(f"== regression done: {npass}/{len(rows)} runs passed — see reports/regression.txt ==")
    sys.exit(0 if npass == len(rows) else 1)


def coverage_reports(ip_dir: Path, tests):
    """Generate the union functional report + the DUT-scoped code report.

    Coverage tooling notes for Vivado xsim 2025.1 (all learned the hard way):
      * The union number comes from the all-scenarios `<ip>_full_test` (one sim) —
        xsim overwrites the shared db per run and xcrg cross-db *merge* segfaults,
        so a multi-db merge is unreliable; a single-sim union is the robust path.
      * xcrg wants the PARENT seed dir as -cov_db_dir (it finds xsim.covdb /
        xsim.codeCov under it), a writable cwd, and a pre-created -report_dir.
      * Code coverage is scored on the DUT only, via the IP's exclusion file
        (dv/<ip>_cov_exclusions.txt). xcrg REWRITES its exclusion file in place, so
        we pass it a throwaway copy to keep the source intact.
    """
    import shutil
    cov_root = ip_dir / "reports" / "_cov"
    ip = ip_dir.name
    db = f"{ip}_sim"
    # Ensure xcrg is on PATH without a login-shell reset (bash -c inherits our env);
    # only source Vivado settings if xcrg isn't already reachable.
    settings = ("command -v xcrg >/dev/null 2>&1 || "
                "source ${VIVADO_SETTINGS:-/tools/Xilinx/2025.1/Vivado/settings64.sh} 2>/dev/null; ")

    def _xcrg(cmd):
        # xcrg is finicky: run from cov_root with RELATIVE paths (absolute -report_dir /
        # -ccExclusionFile fail on this build), and clear its per-run log/state first so
        # back-to-back calls don't collide.
        return sh(["bash", "-c", settings + f"cd '{cov_root}' && rm -f xcrg.log && {cmd}"])

    # pick the union db (full_test) if present, else the first test with a db
    candidates = [f"{ip}_full_test_seed1"] + [f"{t}_seed1" for t in tests]
    covdir = next((cov_root / c for c in candidates if (cov_root / c / "xsim.covdb").exists()), None)
    if covdir is None:
        print("   coverage: no coverage database found (skipped)")
        return
    src = "full_test (union)" if covdir.name.endswith("full_test_seed1") else covdir.name

    dbrel = covdir.name                                # relative to cov_root
    # functional coverage report (no exclusion needed)
    frep = cov_root / "functional_report"
    frep.mkdir(parents=True, exist_ok=True)
    _xcrg(f"xcrg -cov_db_dir '{dbrel}' -cov_db_name {db} -report_dir functional_report -report_format html")

    # DUT-scoped code coverage report (apply the exclusion file via a throwaway copy)
    crep = cov_root / "code_report"
    crep.mkdir(parents=True, exist_ok=True)
    excl_src = ip_dir / "dv" / f"{ip}_cov_exclusions.txt"
    excl_arg = ""
    if excl_src.exists():
        shutil.copy(excl_src, cov_root / "_excl_copy.txt")   # xcrg mutates it; protect the source
        excl_arg = "-ccExclusionFile _excl_copy.txt"
    _xcrg(f"xcrg -cov_db_dir '{dbrel}' -cov_db_name {db} -report_dir code_report -report_format html {excl_arg}")

    fok = (frep / "functionalCoverageReport" / "dashboard.html").exists()
    cok = (crep / "codeCoverageReport" / "dashboard.html").exists()
    print(f"   coverage: from {src} -> functional_report/ ({'ok' if fok else 'FAILED'}), "
          f"code_report/ DUT-scoped ({'ok' if cok else 'FAILED'})"
          + ("" if excl_arg else "  [no exclusion file -> code cov NOT DUT-scoped]"))


if __name__ == "__main__":
    main()
