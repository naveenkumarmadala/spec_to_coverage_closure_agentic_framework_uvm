#!/usr/bin/env python3
"""
static_gate.py — the static-quality gate for an IP's RTL, on the Vivado-only toolchain.

Runs, over the DUT RTL (the files of dv/sv/filelist.f that live under rtl/ or
rdl/generated/rtl/, in filelist order):

  1. verible   verible-verilog-lint on the hand-written RTL (rtl/*.sv): style + lint rules
     rtl-scan  simulation-only constructs in the hand-written RTL (delays, initial, $display...),
               which synthesis silently ignores
  2. xsim      xvlog -sv + xelab of the DUT top alone: language/elaboration errors
  3. vivado    synth_design (out-of-context, fixed part): synthesizability, inferred latches,
               multi-driven / undriven nets, port-width mismatches; report_drc LUTLP-1:
               combinational loops

Known limit (no Vivado check exists for it): a width mismatch between operands INSIDE an
expression (e.g. an 8-bit counter compared with a 16-bit limit) is silently zero-extended and
not reported. Port-connection width mismatches ARE reported.

Policy is DENY BY DEFAULT: every warning a tool prints fails the gate unless its message id is
in INFO below (each entry says why it cannot indicate an RTL defect on its own) or it is waived
for this IP in dv/<ip>_static_waivers.txt with a written justification. Informational messages
are still listed in the report so a reviewer sees them.

Usage:
    python3 flow/scripts/static_gate.py ips/<ip> [--part <part>]
Writes <ip>/reports/static_gate.txt (summary) and <ip>/dv/static_gate/ (tool logs, git-ignored).
Exit 0 = PASS, 1 = FAIL.

Waiver file (optional), one per line, `#` comments allowed:
    <tool> <message-id> <python-regex matched against the message text>  -- <justification>
    e.g.  vivado Synth-8-3848 "Net foo_q in module bar"  -- driven by a bind-only test hook
"""
import argparse, os, re, shutil, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_PART = "xc7a100tcsg324-1"   # any installed 7-series part: only synthesizability is judged
VIVADO_SETTINGS = os.environ.get("VIVADO_SETTINGS", "/tools/Xilinx/2025.1/Vivado/settings64.sh")

# Message ids that are reported but never fail the gate on their own.
INFO = {
    "XSIM-43-3431": "xelab notice about C-compiler environment variables (host setup, not RTL)",
    "Synth-8-7080": "parallel-synthesis criteria not met (tool performance note)",
    "Synth-8-7129": "port unconnected / no load: expected for generic blocks with unused bits "
                    "(e.g. upper bus bits); listed so an unexpected one is visible",
    "Synth-8-3331": "unconnected port on a sub-module (same class as 8-7129)",
    "Synth-8-3332": "unused sequential element removed by optimization (reviewed in the list)",
    "Synth-8-6014": "unused sequential element removed by optimization (reviewed in the list)",
    "Synth-8-3917": "port driven by a constant (tie-off)",
    "DRC-23-814": "out-of-context DRC notice: connectivity DRCs needing a full chip are skipped",
}

# Simulation-only constructs in hand-written RTL. Synthesis silently ignores (or drops) these, so
# the synthesized hardware would differ from what simulation checked -- a text scan is the only
# Vivado-flow check that sees them. Comments and strings are stripped first.
SIM_ONLY = [
    (r"#\s*\d+(\.\d+)?\s*(fs|ps|ns|us|ms|s)?\b", "delay control (#N): ignored by synthesis"),
    (r"\binitial\b", "initial block: not hardware (use reset)"),
    (r"\$(display|write|monitor|strobe|finish|stop|random|urandom|urandom_range|time|realtime)\b",
     "simulation system task/function"),
    (r"\b(force|release|fork|join|wait)\b", "simulation-only statement"),
]


def dut_files(ip_dir: Path):
    """DUT sources in dv/sv/filelist.f order: entries under rtl/ or rdl/generated/rtl/."""
    sv_dir = ip_dir / "dv" / "sv"
    roots = [(ip_dir / "rtl").resolve(), (ip_dir / "rdl" / "generated" / "rtl").resolve()]
    out = []
    for line in (sv_dir / "filelist.f").read_text(errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith(("#", "-")):
            continue
        p = (sv_dir / line).resolve()
        if any(str(p).startswith(str(r) + os.sep) for r in roots):
            if not p.exists():
                sys.exit(f"static_gate: DUT file in filelist not found: {line}")
            out.append(p)
    if not out:
        sys.exit("static_gate: no DUT files found in dv/sv/filelist.f (rtl/ or rdl/generated/rtl/)")
    return out


def sim_only_constructs(files, ip_dir):
    """[(where, what)] for simulation-only constructs in the given RTL files."""
    hits = []
    for f in files:
        text = f.read_text(errors="replace")
        text = re.sub(r"/\*.*?\*/", lambda m: re.sub(r"[^\n]", " ", m.group(0)), text, flags=re.S)
        for n, line in enumerate(text.splitlines(), 1):
            line = re.sub(r'"([^"\\]|\\.)*"', '""', line.split("//", 1)[0])
            for pat, what in SIM_ONLY:
                if re.search(pat, line):
                    hits.append((f"{f.relative_to(ip_dir)}:{n}", f"{what}: {line.strip()}"))
    return hits


def run(cmd, cwd, log):
    """Run a shell command (Vivado settings sourced if the tools are not on PATH)."""
    prefix = "" if shutil.which("vivado") else f"source {VIVADO_SETTINGS} >/dev/null 2>&1; "
    r = subprocess.run(["bash", "-c", prefix + cmd], cwd=cwd, capture_output=True, text=True)
    Path(log).write_text(r.stdout + r.stderr)
    return r.returncode, r.stdout + r.stderr


def messages(text, kinds=("WARNING", "CRITICAL WARNING", "ERROR")):
    """[(severity, id, text)] for Vivado/xsim style lines: SEV: [Tool nn-nnn] text"""
    out = []
    for m in re.finditer(r"^(CRITICAL WARNING|WARNING|ERROR): \[(\w+) ([\d-]+)\] (.*)$", text, re.M):
        msg = (m.group(1), f"{m.group(2)}-{m.group(3)}", m.group(4).strip())
        if m.group(1) in kinds and msg not in out:     # Vivado repeats messages in its summary
            out.append(msg)
    return out


def load_waivers(path: Path):
    ws = []
    if path.exists():
        for n, line in enumerate(path.read_text().splitlines(), 1):
            s = line.split("#", 1)[0].strip()
            if not s:
                continue
            m = re.match(r'(\w+)\s+(\S+)\s+"(.*)"\s+--\s+(\S.*)$', s)
            if not m:
                sys.exit(f"static_gate: bad waiver line {path.name}:{n} (need: tool id \"regex\" -- why)")
            ws.append((m.group(1), m.group(2), re.compile(m.group(3)), m.group(4)))
    return ws


def classify(tool, msgs, waivers):
    fail, info, waived = [], [], []
    for sev, mid, txt in msgs:
        w = next((w for w in waivers if w[0] == tool and w[1] == mid and w[2].search(txt)), None)
        if sev == "ERROR":
            fail.append((mid, txt))
        elif w:
            waived.append((mid, txt, w[3]))
        elif sev == "WARNING" and mid in INFO:
            info.append((mid, txt))
        else:
            fail.append((mid, txt))        # CRITICAL WARNING, or a warning nobody has classified
    return fail, info, waived


def main():
    ap = argparse.ArgumentParser(description="Vivado-only static gate for an IP's RTL")
    ap.add_argument("ip_dir")
    ap.add_argument("--part", default=os.environ.get("STATIC_GATE_PART", DEFAULT_PART))
    args = ap.parse_args()
    ip_dir = Path(args.ip_dir).resolve()
    ip = ip_dir.name
    top = ip
    m = re.search(r"^ip:\s*\n(?:\s+.*\n)*?\s+name:\s*(\w+)", (ip_dir / "ip_config.yaml").read_text(), re.M)
    if m:
        top = m.group(1)
    files = dut_files(ip_dir)
    hand = [f for f in files if (ip_dir / "rtl").resolve() in f.parents]
    work = ip_dir / "dv" / "static_gate"
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    waivers = load_waivers(ip_dir / "dv" / f"{ip}_static_waivers.txt")
    flist = " ".join(f'"{f}"' for f in files)
    results = {}

    # 1. Verible (hand-written RTL only; the generated register block is PeakRDL's output)
    rc, out = run("verible-verilog-lint " + " ".join(f'"{f}"' for f in hand), work, work / "verible.log")
    viol = [l for l in out.splitlines() if re.search(r"\.sv:\d+:\d+", l)]
    if rc not in (0, 1) and not viol:
        viol = [f"verible did not run (exit {rc}): {out.strip()[:200]}"]
    results["verible"] = ([("lint", v.replace(str(ip_dir) + "/", "")) for v in viol], [], [])
    results["rtl-scan"] = ([("sim-only", f"{w}: {t}") for w, t in sim_only_constructs(hand, ip_dir)], [], [])

    # 2. xsim elaboration of the DUT alone
    rc1, o1 = run(f"xvlog -sv {flist}", work, work / "xvlog.log")
    rc2, o2 = run(f"xelab {top} -s {ip}_gate", work, work / "xelab.log") if rc1 == 0 else (1, "")
    f, i, w = classify("xsim", messages(o1 + o2), waivers)
    if (rc1 or rc2) and not f:
        f = [("exit", f"xvlog exit {rc1}, xelab exit {rc2}")]
    results["xsim"] = (f, i, w)

    # 3. Vivado out-of-context synthesis
    tcl = work / "synth.tcl"
    tcl.write_text(
        f"read_verilog -sv {{{' '.join(str(x) for x in files)}}}\n"
        f"synth_design -top {top} -part {args.part} -mode out_of_context\n"
        f"set fp [open latches.txt w]; puts $fp [llength [get_cells -hier -quiet -filter {{REF_NAME =~ LD*}}]]; close $fp\n"
        f"report_drc -checks {{LUTLP-1}} -file loops.rpt\n"
        f"report_utilization -file utilization.rpt\n")
    rc, _ = run(f"vivado -mode batch -nojournal -log synth.log -source {tcl}", work, work / "vivado.out")
    log = (work / "synth.log").read_text(errors="replace") if (work / "synth.log").exists() else ""
    f, i, w = classify("vivado", messages(log), waivers)
    lat = (work / "latches.txt").read_text().strip() if (work / "latches.txt").exists() else "?"
    if lat not in ("0", "?"):
        f.append(("latch", f"{lat} latch cell(s) in the synthesized design"))
    loops = (work / "loops.rpt").read_text(errors="replace") if (work / "loops.rpt").exists() else ""
    for m in re.finditer(r"^LUTLP-1#\d+\s+\S.*$|^\|\s*LUTLP-1\s*\|.*\|\s*(\d+)\s*\|", loops, re.M):
        f.append(("LUTLP-1", "combinational loop in the synthesized design (dv/static_gate/loops.rpt)"))
        break
    if rc and not f:
        f = [("exit", f"vivado exit {rc} (see dv/static_gate/synth.log)")]
    util = ""
    if (work / "utilization.rpt").exists():
        u = (work / "utilization.rpt").read_text()
        lut = re.search(r"\|\s*Slice LUTs\*?\s*\|\s*(\d+)", u)
        ff = re.search(r"\|\s*Slice Registers\s*\|\s*(\d+)", u)
        util = f"{lut.group(1) if lut else '?'} LUT / {ff.group(1) if ff else '?'} FF on {args.part}"
    results["vivado"] = (f, i, w)

    # report
    ok = all(not r[0] for r in results.values())
    lines = [f"# {ip} static gate — {'PASS' if ok else 'FAIL'}  (Vivado-only: Verible + xsim + Vivado synth)",
             f"# DUT files: {len(files)} ({len(hand)} hand-written)  top: {top}  size: {util or 'n/a'}", ""]
    for tool, (f, i, w) in results.items():
        lines.append(f"{tool:8s} {'PASS' if not f else 'FAIL'}  failing={len(f)} waived={len(w)} info={len(i)}")
        for mid, txt in f:
            lines.append(f"    FAIL   [{mid}] {txt}")
        for mid, txt, why in w:
            lines.append(f"    waived [{mid}] {txt}  -- {why}")
        seen = {}
        for mid, txt in i:
            seen.setdefault(mid, []).append(txt)
        for mid, txts in seen.items():
            lines.append(f"    info   [{mid}] x{len(txts)}: {INFO.get(mid, '')}")
            for t in txts[:6]:
                lines.append(f"             {t}")
            if len(txts) > 6:
                lines.append(f"             ... {len(txts) - 6} more (dv/static_gate/)")
    report = "\n".join(lines) + "\n"
    (ip_dir / "reports").mkdir(exist_ok=True)
    (ip_dir / "reports" / "static_gate.txt").write_text(report)
    print(report, end="")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
