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
    # register-bit toggle totals printed by reg_bit_toggle_cov (DUT-observed via the bus)
    rt = re.findall(r"REG_BIT_TOGGLE covered=(\d+) total=(\d+) pct=([\d.]+)", text)
    regtog = (int(rt[-1][0]), int(rt[-1][1])) if rt else None
    return dict(uvm_error=err, uvm_fatal=fat, sva_fails=sva,
                scb_checks=scb_checks, scb_errors=scb_err, ran=ran, raw_errors=raw_err,
                regtog=regtog)


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
    ap.add_argument("--reports-only", action="store_true",
                    help="regenerate coverage reports from the existing databases (no simulation)")
    a = ap.parse_args()

    ip_dir = Path(a.ip_dir).resolve()
    ip = ip_dir.name
    if a.reports_only:
        tests = discover_tests(ip_dir)
        reg = (ip_dir / "reports" / "regression.txt")
        m = re.search(r"# toggle-build seed=1 test=(\S+) ok=(\S+) identical_to_normal_run=(\S+) (.*)",
                      reg.read_text() if reg.exists() else "")
        tog = (dict(test=m.group(1), ok=m.group(2) == "True", same=m.group(3) == "True",
                    tag=f"{m.group(1)}_seed1_tcov", detail=m.group(4)) if m else None)
        coverage_reports(ip_dir, tests, tog)
        return
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

    # generated inputs that must track the RDL / filelist (so no manual step is ever needed)
    refresh_regs(ip_dir)
    refresh_reg_toggle_cfg(ip_dir)

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

    # code-toggle measurement build: same union test + seed on the snapshot WITHOUT the bind
    # top, verified to have executed identically to the normal run (see toggle_run)
    tog = toggle_run(ip_dir, tests, rows, reports) if cov else None

    # summary file
    npass = sum(1 for x in rows if x["ok"])
    with open(reports / "regression.txt", "w") as f:
        f.write(f"# {ip} regression — {npass}/{len(rows)} runs passed\n")
        for x in rows:
            f.write(f"seed={x['seed']} test={x['test']} ok={x['ok']} "
                    f"uvm_error={x['uvm_error']} uvm_fatal={x['uvm_fatal']} "
                    f"sva_fails={x['sva_fails']} scb_errors={x['scb_errors']} "
                    f"raw_errors={x['raw_errors']}\n")
        if tog is not None:
            f.write(f"# toggle-build seed=1 test={tog['test']} ok={tog['ok']} "
                    f"identical_to_normal_run={tog['same']} {tog['detail']}\n")

    # per-test functional coverage reports (xcrg cross-db merge is unreliable on
    # xsim 2025.1 — see coverage_reports docstring)
    if cov:
        coverage_reports(ip_dir, tests, tog)

    tog_ok = tog is None or tog["ok"]
    print(f"== regression done: {npass}/{len(rows)} runs passed"
          + ("" if tog is None else f"; toggle build {'OK' if tog['ok'] else 'FAILED'}")
          + " — see reports/regression.txt ==")
    sys.exit(0 if (npass == len(rows) and tog_ok) else 1)


def toggle_run(ip_dir: Path, tests, rows, reports: Path):
    """Run the union test once more on the CODE-TOGGLE snapshot (<ip>_tcov: testbench top
    without the bind top, no waveform dump) and prove it executed exactly like the normal
    run it stands in for.

    Why a second build (Vivado xsim 2025.1, measured 2026-09-26): a DUT net that a bound
    white-box checker observes loses its code-toggle coverage, and $dumpvars stops toggle
    recording on some nets. The binds are read-only, so the DUT behaves identically without
    them; the identical-execution check below makes that a verified fact, not an assumption:
    same pass status, same scoreboard check count, same register-bit toggle totals observed
    on the bus. Toggle is reported from this build; everything else from the normal one.
    """
    ip = ip_dir.name
    union = f"{ip}_full_test" if f"{ip}_full_test" in tests else tests[0]
    ref = next((x for x in rows if x["test"] == union and x["seed"] == 1), None)
    # The toggle snapshot is the testbench top ALONE. If that top still contains a bind or a
    # $dumpvars, the toggle numbers would be silently corrupted while the identical-execution
    # check still passes -- so refuse, and say how to fix it.
    bad = tb_top_toggle_hazards(ip_dir)
    if bad:
        print(f"   [FAIL] toggle build: tb top contains {', '.join(bad)} -- move binds to "
              f"tb/{ip}_binds.sv (module {ip}_binds) and delete the $dumpvars (waveforms: "
              f"xsim_flow.sh wave); see the uvm-env-scaffold skill")
        return dict(test=union, ok=False, same=False, tag=None,
                    detail=f"tb top contains {', '.join(bad)}")
    r = sh(["bash", str(XFLOW), "elab", str(ip_dir), "--cov", "--toggle"])
    if r.returncode != 0:
        sys.stderr.write(r.stdout + r.stderr)
        print("   [FAIL] toggle build: ELABORATION FAILED")
        return dict(test=union, ok=False, same=False, tag=None, detail="elaboration failed")
    tag = f"{union}_seed1_tcov"
    r = sh(["bash", str(XFLOW), "run", str(ip_dir), union, "1", "--cov", "--toggle", "--covtag", tag])
    log = r.stdout + r.stderr
    (reports / "_runs" / "seed_1").mkdir(parents=True, exist_ok=True)
    (reports / "_runs" / "seed_1" / f"{union}__tcov.log").write_text(log)
    res = parse_log(log)
    # SVA failures can't occur here (no checkers bound); everything else must be clean
    clean = (res["ran"] and res["uvm_error"] == 0 and res["uvm_fatal"] == 0
             and res["scb_errors"] in (0, None) and res["raw_errors"] == 0)
    same = (ref is not None and res["scb_checks"] == ref["scb_checks"]
            and res["regtog"] == ref["regtog"])
    detail = (f"scb_checks={res['scb_checks']}/{ref['scb_checks'] if ref else None} "
              f"reg_bit_toggle={res['regtog']}/{ref['regtog'] if ref else None}")
    ok = clean and same
    print(f"   [{'PASS' if ok else 'FAIL'}] toggle build   {union} seed=1  "
          f"identical execution: {same}  ({detail})")
    return dict(test=union, ok=ok, same=same, tag=tag, detail=detail)


def tb_top_toggle_hazards(ip_dir: Path):
    """Constructs in the testbench top that corrupt xsim code-toggle recording (measured on
    Vivado 2025.1): a `bind` (the observed DUT nets lose their toggles) and any $dumpvars /
    $dumpfile (even never executed). Comments are ignored. Returns what was found."""
    tops = sorted((ip_dir / "dv" / "sv" / "tb").glob("*_tb_top.sv"))
    if not tops:
        return []
    src = tops[0].read_text(errors="replace")
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    src = re.sub(r"//[^\n]*", "", src)
    found = []
    if re.search(r"^\s*bind\s+\w+", src, re.M):
        found.append("`bind` statement(s)")
    if re.search(r"\$dump(vars|file|on|all)\b", src):
        found.append("$dumpvars/$dumpfile")
    return found


def refresh_regs(ip_dir: Path):
    """Run gen_regs.py (PeakRDL regblock/RAL/docs/header, options from ip_config.yaml) when the
    generated register outputs are missing or older than the RDL or ip_config.yaml. They are
    git-ignored, so this is what makes a fresh clone build without a remembered command."""
    cfg = ip_dir / "ip_config.yaml"
    m = re.search(r"^registers:\s*\n(?:\s+.*\n)*?\s+source:\s*(\S+)", cfg.read_text(), re.M) if cfg.exists() else None
    if not m or not (ip_dir / m.group(1)).exists():
        return
    rdl = ip_dir / m.group(1)
    ral = rdl.parent / "generated" / f"{ip_dir.name}_ral_pkg.sv"
    rtl = rdl.parent / "generated" / "rtl"
    newest_src = max(rdl.stat().st_mtime, cfg.stat().st_mtime)
    if ral.exists() and rtl.is_dir() and any(rtl.glob("*.sv")) and ral.stat().st_mtime >= newest_src:
        return
    venv_py = HERE.parent.parent / "env" / ".venv" / "bin" / "python3"
    py = str(venv_py) if venv_py.exists() else sys.executable
    r = sh([py, str(HERE / "gen_regs.py"), str(ip_dir)])
    print("   " + (r.stdout.strip() or r.stderr.strip()).replace("\n", "\n   "))
    if r.returncode != 0:
        sys.exit("register generation failed -- fix the RDL / ip_config registers: section first")


def refresh_reg_toggle_cfg(ip_dir: Path):
    """Regenerate <ip>_reg_toggle_cfg.svh (the RDL's singlepulse fields, read by
    reg_bit_toggle_cov) when the test package uses it and it is missing or older than the
    RDL -- so an RDL change can never leave the collector with a stale list."""
    ip = ip_dir.name
    pkg = ip_dir / "dv" / "sv" / f"{ip}_test_pkg.sv"
    svh = ip_dir / "dv" / "sv" / "env" / f"{ip}_reg_toggle_cfg.svh"
    if not pkg.exists() or f"{ip}_reg_toggle_cfg.svh" not in pkg.read_text(errors="replace"):
        return
    cfg = ip_dir / "ip_config.yaml"
    m = re.search(r"^registers:\s*\n(?:\s+.*\n)*?\s+source:\s*(\S+)", cfg.read_text(), re.M) if cfg.exists() else None
    rdl = ip_dir / m.group(1) if m else None
    if svh.exists() and (rdl is None or not rdl.exists() or svh.stat().st_mtime >= rdl.stat().st_mtime):
        return
    venv_py = HERE.parent.parent / "env" / ".venv" / "bin" / "python3"
    py = str(venv_py) if venv_py.exists() else sys.executable
    r = sh([py, str(HERE / "gen_reg_toggle_cfg.py"), str(ip_dir)])
    print("   " + (r.stdout.strip() or r.stderr.strip()))


def coverage_reports(ip_dir: Path, tests, tog=None):
    """Generate the union functional report, the DUT-scoped code report
    (statement/branch/condition), and -- from the toggle build -- the code-toggle report.

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
    # Always regenerate the exclusion files from the CURRENT filelist first: a newly added
    # testbench file (checker, bind/dump top, VIP) must never leak into the DUT scope just
    # because nobody re-ran gen_exclusions.py (it happened once: a new coverage module sat in
    # the DUT denominator until noticed).
    r = sh([sys.executable, str(HERE / "gen_exclusions.py"), str(ip_dir)])
    if r.returncode != 0:
        sys.stderr.write(r.stdout + r.stderr)
    else:
        print("   " + r.stdout.strip())
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

    def _excl_copy(name, dst):
        """Throwaway copy of an exclusion file for xcrg (which rewrites it in place), with
        any CR stripped: git's core.autocrlf can check the source out as CRLF, and a single
        trailing CR makes xcrg ignore EVERY directive (silently un-scoping the report)."""
        src_f = ip_dir / "dv" / name
        if not src_f.exists():
            return ""
        (cov_root / dst).write_bytes(src_f.read_bytes().replace(b"\r", b""))
        return f"-ccExclusionFile {dst}"

    # DUT-scoped code coverage report: statement / branch / condition (normal build)
    crep = cov_root / "code_report"
    crep.mkdir(parents=True, exist_ok=True)
    excl_arg = _excl_copy(f"{ip}_cov_exclusions.txt", "_excl_copy.txt")
    _xcrg(f"xcrg -cov_db_dir '{dbrel}' -cov_db_name {db} -report_dir code_report -report_format html {excl_arg}")

    fok = (frep / "functionalCoverageReport" / "dashboard.html").exists()
    cok = (crep / "codeCoverageReport" / "dashboard.html").exists()
    print(f"   coverage: from {src} -> functional_report/ ({'ok' if fok else 'FAILED'}), "
          f"code_report/ DUT-scoped stmt/branch/cond ({'ok' if cok else 'FAILED'})"
          + ("" if excl_arg else "  [no exclusion file -> code cov NOT DUT-scoped]"))

    # code-TOGGLE report: from the toggle build's database (no bind top, no dump)
    if tog is not None and tog.get("tag") and (cov_root / tog["tag"]).exists():
        trep = cov_root / "toggle_report"
        if trep.exists():
            shutil.rmtree(trep)
        trep.mkdir(parents=True, exist_ok=True)
        texcl = _excl_copy(f"{ip}_toggle_exclusions.txt", "_texcl_copy.txt")
        _xcrg(f"xcrg -cov_db_dir '{tog['tag']}' -cov_db_name {ip}_tcov -report_dir toggle_report "
              f"-report_format html {texcl}")
        tok = (trep / "codeCoverageReport" / "dashboard.html").exists()
        print(f"   coverage: toggle build -> toggle_report/ DUT code-toggle "
              f"({'ok' if tok else 'FAILED'}){'' if tog['ok'] else '  [toggle build NOT verified identical]'}")
        if tok:
            s = dut_toggle_summary(ip_dir, trep / "codeCoverageReport", cov_root / "toggle_summary.txt")
            if s:
                print(f"   coverage: DUT code toggle (bit-weighted) {s['covered']}/{s['total']} bits = "
                      f"{s['pct']:.2f}%  | net of documented constant nets {s['net']:.2f}%  "
                      f"-> _cov/toggle_summary.txt")

    # register-bit toggle (functional, RAL-derived): totals + uncovered list from the
    # union run's log, for the report generators
    ulog = ip_dir / "reports" / "_runs" / "seed_1" / f"{ip}_full_test.log"
    if ulog.exists():
        text = ulog.read_text(errors="replace")
        tot = re.findall(r"REG_BIT_TOGGLE covered=(\d+) total=(\d+) pct=([\d.]+) fields=(\d+)", text)
        m = re.search(r"uncovered bit-direction\(s\)((?:\n {4}\S.*)+)", text)
        bf = re.search(r"uncovered by field:((?:\n {4}\S.*)+)", text)
        out = cov_root / "reg_bit_toggle.txt"
        if tot:
            c, t, p, nf = tot[-1]
            out.write_text(f"REG_BIT_TOGGLE covered={c} total={t} pct={p} fields={nf}\n"
                           + ("uncovered by field:" + bf.group(1) + "\n" if bf else "")
                           + ("uncovered:" + m.group(1) + "\n" if m else "uncovered: none\n"))
            print(f"   coverage: register-bit toggle (RAL-derived) {c}/{t} bit-directions = {p}%"
                  f"  -> _cov/reg_bit_toggle.txt")

    # one page with every result, the correct (bit-weighted) toggle, and links into xcrg
    r = sh([sys.executable, str(HERE / "gen_dashboard.py"), str(ip_dir)])
    print("   dashboard: " + ("reports/coverage_dashboard.html" if r.returncode == 0
                              else "FAILED -- " + (r.stderr.strip().splitlines() or ["?"])[-1]))


def dut_toggle_summary(ip_dir: Path, rep: Path, out: Path):
    """Bit-weighted DUT code toggle, computed from xcrg's own per-file toggle tables.

    Why not the xcrg dashboard figure: on xsim 2025.1 the dashboard's toggle aggregate is an
    unweighted average over report FILES, and it always includes the UVM library's own file
    (xlnx_uvm_package.sv) at 0% -- `module -uvm_pkg` removes its module, and no `file -` /
    `dir -` directive removes the file row (measured 2026-09-26). So that number is not a DUT
    metric. Here: sum(covered bits) / sum(total bits) over the files under the IP's RTL dirs
    (rtl/, rdl/generated/rtl/) that the report still contains, plus every uncovered row.
    A row whose signal is listed in the toggle-waiver sidecar is one the exclusion did not
    fully remove (xsim can list a net twice and exclude only one copy); it is reported as
    "documented constant", and `net` recomputes the ratio without those bits.
    """
    rtl = {p.name for d in ("rtl", "rdl/generated/rtl") for p in (ip_dir / d).glob("*.sv")}
    documented = set()
    side = ip_dir / "dv" / f"{ip_dir.name}_toggle_waivers.txt"
    if side.exists():
        for l in side.read_text(errors="replace").splitlines():
            mm = re.match(r"\s*signal\s+-(\S+)", l)
            if mm:
                documented.add(mm.group(1).split(".")[-1].strip("*"))
    covered = total = doc_bits = 0
    files, holes = [], []
    for f in sorted(rep.glob("file*.html")):
        h = f.read_text(encoding="latin-1", errors="replace")
        k = h.find("Toggle Coverage of File")
        mm = re.search(r"(/[^\s<|>]+?\.sv)", h[k:k + 600]) if k >= 0 else None
        if not mm or Path(mm.group(1)).name not in rtl:
            continue
        src = Path(mm.group(1))
        s = re.sub(r"<[^>]+>", "|", h[k:]); s = re.sub(r"&nbsp;", " ", s); s = re.sub(r"&#\d+;", "", s)
        s = re.sub(r"[ \t\r\n]+", " ", s); s = re.sub(r"(\| ?)+", "|", s)
        tb = re.search(r"Total Bits \|(\d+)\|(\d+)\|", s)
        if not tb:
            continue
        ftot, fcov = int(tb.group(1)), int(tb.group(2))
        total += ftot; covered += fcov
        files.append(f"file {src.name} {fcov}/{ftot} {100.0 * fcov / ftot if ftot else 100.0:.2f}")
        src_lines = src.read_text(errors="replace").splitlines() if src.exists() else []
        for ln, ty, var, a01, a10 in re.findall(r"\|(\d+)\|(\w+)\|([^|]+?)\|(\d) \|(\d) ", s):
            if a01 == "1" and a10 == "1":
                continue
            name = re.sub(r"^(All Other bits of |All bits of )", "", var).split(" ")[0].split("[")[0]
            why = ""
            if name in documented and var.startswith("All bits of"):
                decl = src_lines[int(ln) - 1] if 0 < int(ln) <= len(src_lines) else ""
                w = re.search(r"\[\s*(\d+)\s*:\s*(\d+)\s*\]", decl)
                width = abs(int(w.group(1)) - int(w.group(2))) + 1 if w else 1
                missing = (a01 == "0") + (a10 == "0")
                doc_bits += width * missing
                why = "documented constant (sidecar waiver; xsim listed a copy it could not exclude)"
            holes.append(f"uncovered {src.name}:L{ln} {var} [{a01}{a10}] {why}".rstrip())
    if total == 0:
        return None
    pct = 100.0 * covered / total
    net = 100.0 * covered / (total - doc_bits) if total > doc_bits else 100.0
    out.write_text(f"DUT_TOGGLE bits_covered={covered} bits_total={total} pct={pct:.2f} "
                   f"net_of_documented={net:.2f}\n" + "\n".join(files + holes) + "\n")
    return dict(covered=covered, total=total, pct=pct, net=net)


if __name__ == "__main__":
    main()
