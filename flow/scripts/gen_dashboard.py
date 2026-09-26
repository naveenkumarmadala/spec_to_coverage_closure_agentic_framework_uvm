#!/usr/bin/env python3
"""
gen_dashboard.py — one HTML page with an IP's verification results: <ip>/reports/coverage_dashboard.html

Why it exists: xcrg's own dashboards are fine for drill-down but their toggle "score" is an
unweighted average over report FILES that includes Vivado's UVM library file at 0% (it cannot be
excluded — report-time or elaboration-time exclusions, module or file form, were all tried on
2025.1). This page shows the correct, bit-weighted numbers the flow computes, and links every
number to the matching xcrg detail page.

Reads only what run_regression.py / static_gate.py already write (no simulation):
    reports/regression.txt, reports/static_gate.txt,
    reports/_cov/functional_report/functionalCoverageReport/{dashboard,groups}.html
    reports/_cov/code_report/codeCoverageReport/{dashboard,files}.html   (stmt/branch/cond)
    reports/_cov/toggle_summary.txt, reports/_cov/reg_bit_toggle.txt     (toggle, bit-weighted)
Anything missing is shown as "not available", never guessed.

Usage:  python3 flow/scripts/gen_dashboard.py ips/<ip>
"""
import datetime, html, os, re, sys
from html.parser import HTMLParser
from pathlib import Path


class Tables(HTMLParser):
    """Every <table> as a list of rows; each cell = (text, first href or None)."""
    def __init__(self):
        super().__init__()
        self.tables, self._row, self._cell, self._href = [], None, None, None

    def handle_starttag(self, tag, attrs):
        if tag == "table":
            self.tables.append([])
        elif tag == "tr" and self.tables:
            self._row = []
        elif tag in ("td", "th") and self._row is not None:
            self._cell, self._href = [], None
        elif tag == "a" and self._cell is not None and self._href is None:
            self._href = dict(attrs).get("href")

    def handle_endtag(self, tag):
        if tag in ("td", "th") and self._cell is not None:
            self._row.append((" ".join("".join(self._cell).split()), self._href))
            self._cell = None
        elif tag == "tr" and self._row is not None:
            if self._row:
                self.tables[-1].append(self._row)
            self._row = None

    def handle_data(self, data):
        if self._cell is not None:
            self._cell.append(data)


def tables_of(path: Path):
    if not path.exists():
        return []
    p = Tables()
    p.feed(path.read_text(encoding="utf-8", errors="replace"))
    return p.tables


def num(s):
    try:
        return float(s)
    except (TypeError, ValueError):
        return None


def labeled_values(path: Path, labels):
    """xcrg dashboards put a header row of labels then a row of values; map label -> value."""
    out = {}
    for t in tables_of(path):
        for i, row in enumerate(t[:-1]):
            names = [c[0].replace("⇅", "").strip() for c in row]
            if any(l in names for l in labels):
                vals = [c[0] for c in t[i + 1]]
                if len(vals) >= len(names):
                    vals = vals[-len(names):]
                for n, v in zip(names, vals):
                    if n in labels and num(v) is not None:
                        out[n] = num(v)
    return out


def esc(s):
    return html.escape(str(s))


def pct(v, digits=2, none="n/a"):
    return none if v is None else f"{v:.{digits}f}%"


def status(v, goal=100.0):
    if v is None:
        return "na"
    return "ok" if v >= goal - 1e-9 else "warn"


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: gen_dashboard.py ips/<ip>")
    ip_dir = Path(sys.argv[1]).resolve()
    ip = ip_dir.name
    rep = ip_dir / "reports"
    cov = rep / "_cov"
    fdir = cov / "functional_report" / "functionalCoverageReport"
    cdir = cov / "code_report" / "codeCoverageReport"
    tdir = cov / "toggle_report" / "codeCoverageReport"

    # ---- regression ----------------------------------------------------------------------
    reg_txt = (rep / "regression.txt").read_text(encoding="utf-8", errors="replace") if (rep / "regression.txt").exists() else ""
    runs = [dict(re.findall(r"(\w+)=(\S+)", l)) for l in reg_txt.splitlines() if l.startswith("seed=")]
    n_pass = sum(r.get("ok") == "True" for r in runs)
    per_test = {}
    for r in runs:
        t = per_test.setdefault(r.get("test", "?"), [0, 0, []])
        t[0] += 1
        if r.get("ok") == "True":
            t[1] += 1
        else:
            t[2].append(r.get("seed"))
    tog_line = next((l for l in reg_txt.splitlines() if l.startswith("# toggle-build")), "")
    tog_same = "identical_to_normal_run=True" in tog_line
    scb = re.search(r"scb_checks=(\S+)", tog_line)
    reg_ok = bool(runs) and n_pass == len(runs)

    # ---- static gate ---------------------------------------------------------------------
    sg_txt = (rep / "static_gate.txt").read_text(encoding="utf-8", errors="replace") if (rep / "static_gate.txt").exists() else ""
    m = re.search(r"static gate\W+(PASS|FAIL)", sg_txt.splitlines()[0]) if sg_txt else None
    sg_pass = bool(m) and m[1] == "PASS"
    sg_size = re.search(r"size: (.*)$", sg_txt, re.M)
    sg_tools = re.findall(r"^(\S+)\s+(PASS|FAIL)\s+failing=(\d+) waived=(\d+) info=(\d+)", sg_txt, re.M)

    # ---- functional ----------------------------------------------------------------------
    fv = labeled_values(fdir / "dashboard.html", ["Score", "Inst Score"])
    groups = []
    for t in tables_of(fdir / "groups.html"):
        for row in t:
            if len(row) >= 4 and "::" in row[0][0] and num(row[1][0]) is not None:
                # xcrg lists a bound covergroup once per module it is bound into but counts every
                # instance under the first row; the others show 0 instances / 0% -- not real holes
                if row[2][0].strip() == "0":
                    continue
                name = row[0][0]
                scope, _, cg = name.rpartition("::")
                if "." in scope:                      # tb...dut.u_ch0.u_cov::cg -> u_cov::cg (the row
                    name = scope.split(".")[-1] + "::" + cg   # covers every instance of the bound module)
                groups.append((name, row[0][1], num(row[1][0]), row[2][0], num(row[3][0])))

    # ---- code coverage (statement / branch / condition; toggle comes from toggle_summary) -
    cv = labeled_values(cdir / "dashboard.html",
                        ["Statement Coverage Score", "Branch Coverage Score", "Condition Coverage Score"])
    code_files = []
    for t in tables_of(cdir / "files.html"):
        for row in t:
            if len(row) >= 9 and row[1][0].endswith((".sv", ".v", ".svh")):
                path, href = row[1][0], row[1][1]
                if f"/{ip}/" not in path.replace("\\", "/"):
                    continue                          # e.g. Vivado's UVM library file: not the design
                # xcrg prints 0 for "nothing to measure"; tell that apart from 0% covered: no
                # statements -> n/a; no Branch/Condition section on the file's page -> n/a
                detail = (cdir / href).read_text(encoding="utf-8", errors="replace") if href and (cdir / href).exists() else ""
                stmt = num(row[4][0]) if num(row[6][0]) else None
                br = num(row[7][0]) if "Branch Coverage Summary for File" in detail else None
                cond = num(row[8][0]) if "Condition Coverage Summary for File" in detail else None
                code_files.append((Path(path).name, href, stmt, br, cond))

    # ---- toggle --------------------------------------------------------------------------
    ts = (cov / "toggle_summary.txt").read_text(encoding="utf-8", errors="replace") if (cov / "toggle_summary.txt").exists() else ""
    m = re.search(r"bits_covered=(\d+) bits_total=(\d+) pct=([\d.]+) net_of_documented=([\d.]+)", ts)
    tog = dict(cov=int(m[1]), tot=int(m[2]), pct=float(m[3]), net=float(m[4])) if m else None
    tog_files = re.findall(r"^file (\S+) (\d+)/(\d+) ([\d.]+)", ts, re.M)
    tog_holes = [l[len("uncovered "):] for l in ts.splitlines() if l.startswith("uncovered ")]
    rb = (cov / "reg_bit_toggle.txt").read_text(encoding="utf-8", errors="replace") if (cov / "reg_bit_toggle.txt").exists() else ""
    m = re.search(r"covered=(\d+) total=(\d+) pct=([\d.]+) fields=(\d+)", rb)
    rbt = dict(cov=int(m[1]), tot=int(m[2]), pct=float(m[3]), fields=int(m[4])) if m else None
    rb_holes = [l.strip() for l in rb.splitlines()[1:] if l.strip() and not l.startswith("uncovered:")]

    # ---- page ----------------------------------------------------------------------------
    def rel(p: Path):
        return os.path.relpath(p, rep).replace(os.sep, "/")

    def link(p: Path, text):
        return f'<a href="{esc(rel(p))}">{esc(text)}</a>' if p.exists() else esc(text)

    def tile(label, value, sub, cls, href=None):
        v = f'<a href="{esc(href)}">{esc(value)}</a>' if href else esc(value)
        return (f'<div class="tile {cls}"><div class="lbl">{esc(label)}</div>'
                f'<div class="val">{v}</div><div class="sub">{sub}</div></div>')

    gen = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    run_date = (datetime.datetime.fromtimestamp((rep / "regression.txt").stat().st_mtime).strftime("%Y-%m-%d %H:%M")
                if (rep / "regression.txt").exists() else "n/a")

    tiles = [
        tile("Regression", f"{n_pass}/{len(runs)}" if runs else "n/a",
             ("all runs pass" if reg_ok else "failures — see below") if runs else "no regression.txt",
             "ok" if reg_ok else ("bad" if runs else "na"), "regression.txt"),
        tile("Static gate", "PASS" if sg_pass else ("FAIL" if sg_txt else "n/a"),
             esc(sg_size[1]) if sg_size else "Verible + xsim + Vivado synth",
             "ok" if sg_pass else ("bad" if sg_txt else "na"), "static_gate.txt" if sg_txt else None),
        tile("Functional", pct(fv.get("Score")), f"instance score {pct(fv.get('Inst Score'))}",
             status(fv.get("Score")), rel(fdir / "groups.html") if fdir.exists() else None),
        tile("Statement", pct(cv.get("Statement Coverage Score")), "DUT code", status(cv.get("Statement Coverage Score")),
             rel(cdir / "files.html") if cdir.exists() else None),
        tile("Branch", pct(cv.get("Branch Coverage Score")), "DUT code", status(cv.get("Branch Coverage Score")),
             rel(cdir / "files.html") if cdir.exists() else None),
        tile("Condition", pct(cv.get("Condition Coverage Score")), "DUT code", status(cv.get("Condition Coverage Score")),
             rel(cdir / "files.html") if cdir.exists() else None),
        tile("Code toggle", pct(tog["pct"]) if tog else "n/a",
             f'{tog["cov"]}/{tog["tot"]} bits · {tog["net"]:.2f}% net of documented constants' if tog else "no toggle_summary.txt",
             status(tog["net"]) if tog else "na", "#toggle"),
        tile("Register-bit toggle", pct(rbt["pct"]) if rbt else "n/a",
             f'{rbt["cov"]}/{rbt["tot"]} bit-directions · {rbt["fields"]} fields' if rbt else "no reg_bit_toggle.txt",
             status(rbt["pct"]) if rbt else "na", "#regtoggle"),
    ]

    def cls_of(v):
        return {"ok": "c-ok", "warn": "c-warn", "na": ""}[status(v)]

    reg_rows = "".join(
        f'<tr><td>{esc(t)}</td><td class="n">{s[0]}</td><td class="n {"c-ok" if s[1] == s[0] else "c-bad"}">{s[1]}</td>'
        f'<td>{esc(", ".join(s[2])) or "—"}</td></tr>' for t, s in sorted(per_test.items()))
    grp_rows = "".join(
        f'<tr><td>{link(fdir / h, n) if h else esc(n)}</td><td class="n {cls_of(sc)}">{pct(sc)}</td>'
        f'<td class="n">{esc(ni)}</td><td class="n {cls_of(ai)}">{pct(ai)}</td></tr>'
        for n, h, sc, ni, ai in groups)
    code_rows = "".join(
        f'<tr><td>{link(cdir / h, f) if h else esc(f)}</td><td class="n {cls_of(s)}">{pct(s, none="—")}</td>'
        f'<td class="n {cls_of(b)}">{pct(b, none="—")}</td><td class="n {cls_of(c)}">{pct(c, none="—")}</td></tr>'
        for f, h, s, b, c in code_files)
    tog_rows = "".join(
        f'<tr><td>{esc(f)}</td><td class="n">{c}/{t}</td><td class="n {cls_of(float(p))}">{float(p):.2f}%</td></tr>'
        for f, c, t, p in tog_files)
    sg_rows = "".join(
        f'<tr><td>{esc(t)}</td><td class="{"c-ok" if r == "PASS" else "c-bad"}">{r}</td><td class="n">{f}</td>'
        f'<td class="n">{w}</td><td class="n">{i}</td></tr>' for t, r, f, w, i in sg_tools)

    def holes(items, empty):
        return ("<ul>" + "".join(f"<li><code>{esc(h)}</code></li>" for h in items) + "</ul>") if items else f'<p class="muted">{empty}</p>'

    page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{esc(ip)} verification dashboard</title>
<style>
:root {{ --bg:#f6f7f5; --panel:#fff; --ink:#1b2220; --muted:#5d6865; --line:#dfe3df;
        --ok:#1f7a4d; --okbg:#e3f3ea; --warn:#8a5a00; --warnbg:#fbf0d9; --bad:#b3261e; --badbg:#fbe4e2; --link:#1d5fae; }}
@media (prefers-color-scheme: dark) {{ :root {{ --bg:#141817; --panel:#1d2321; --ink:#e7ecea; --muted:#9aa5a2;
        --line:#2f3835; --ok:#6fd3a1; --okbg:#18382a; --warn:#f0c46a; --warnbg:#3a2f14; --bad:#ff8f86; --badbg:#3d1d1b; --link:#8ab8ff; }} }}
* {{ box-sizing:border-box; }}
body {{ margin:0; background:var(--bg); color:var(--ink); font:14px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif; }}
main {{ max-width:1100px; margin:0 auto; padding:24px 16px 48px; }}
h1 {{ font-size:22px; margin:0 0 4px; }} h2 {{ font-size:16px; margin:32px 0 10px; }}
.muted {{ color:var(--muted); }} a {{ color:var(--link); }}
.tiles {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(170px,1fr)); gap:10px; margin-top:18px; }}
.tile {{ background:var(--panel); border:1px solid var(--line); border-left:4px solid var(--line); border-radius:8px; padding:10px 12px; }}
.tile.ok {{ border-left-color:var(--ok); }} .tile.warn {{ border-left-color:var(--warn); }} .tile.bad {{ border-left-color:var(--bad); }}
.lbl {{ font-size:12px; color:var(--muted); text-transform:uppercase; letter-spacing:.04em; }}
.val {{ font-size:24px; font-weight:650; font-variant-numeric:tabular-nums; }} .val a {{ color:inherit; text-decoration:none; }}
.sub {{ font-size:12px; color:var(--muted); }}
.card {{ background:var(--panel); border:1px solid var(--line); border-radius:8px; padding:4px 14px 12px; overflow-x:auto; }}
table {{ border-collapse:collapse; width:100%; }} th,td {{ text-align:left; padding:6px 8px; border-bottom:1px solid var(--line); }}
th {{ font-size:12px; color:var(--muted); font-weight:600; }} td.n {{ text-align:right; font-variant-numeric:tabular-nums; }}
.c-ok {{ color:var(--ok); }} .c-warn {{ color:var(--warn); font-weight:600; }} .c-bad {{ color:var(--bad); font-weight:600; }}
.note {{ background:var(--warnbg); border-radius:6px; padding:8px 12px; font-size:13px; margin:10px 0 0; }}
code {{ font-size:12px; }} ul {{ margin:6px 0; padding-left:20px; }}
</style></head><body><main>
<h1>{esc(ip)} — verification dashboard</h1>
<div class="muted">Regression run {esc(run_date)} · page generated {esc(gen)} · all numbers from the files in <code>reports/</code>;
click a number for the underlying xcrg report.</div>
<div class="tiles">{"".join(tiles)}</div>

<h2>Regression</h2>
<div class="card"><table><tr><th>Test</th><th>Runs</th><th>Passed</th><th>Failed seeds</th></tr>{reg_rows or '<tr><td colspan=4 class="muted">no regression.txt</td></tr>'}</table>
<p class="muted">Code-toggle build: {"identical to the normal run" if tog_same else "NOT verified identical"}{f" (scoreboard checks {esc(scb[1])})" if scb else ""} ·
per-run logs in {link(rep / "_runs", "_runs/")}</p></div>

<h2>Functional coverage</h2>
<div class="card"><table><tr><th>Covergroup</th><th>Score</th><th>Instances</th><th>Avg instance score</th></tr>{grp_rows or '<tr><td colspan=4 class="muted">no functional report</td></tr>'}</table>
<p class="muted">Score = covergroup-type average; instance score = average over instances (xcrg's two headline numbers).
Details: {link(fdir / "groups.html", "xcrg functional report")}</p></div>

<h2>Code coverage — statement / branch / condition (DUT)</h2>
<div class="card"><table><tr><th>File</th><th>Statement</th><th>Branch</th><th>Condition</th></tr>{code_rows or '<tr><td colspan=4 class="muted">no code report</td></tr>'}</table>
<p class="muted">— = nothing of that kind in the file. Details: {link(cdir / "files.html", "xcrg code report")}</p></div>

<h2 id="toggle">Code toggle (DUT, bit-weighted)</h2>
<div class="card"><table><tr><th>File</th><th>Bits toggled</th><th>Toggle</th></tr>{tog_rows or '<tr><td colspan=3 class="muted">no toggle_summary.txt</td></tr>'}
{f'<tr><th>Total</th><th class="n">{tog["cov"]}/{tog["tot"]}</th><th class="n">{tog["pct"]:.2f}% ({tog["net"]:.2f}% net of documented constants)</th></tr>' if tog else ""}</table>
<p><b>Uncovered bits</b></p>{holes(tog_holes, "none")}
<p class="note">Measured on the separate code-toggle snapshot (no binds, no <code>$dumpvars</code>). The "Toggle Coverage Score" on
xcrg's own dashboards is an unweighted average over report files that includes Vivado's UVM library file at 0% — do not
quote it. Per-signal detail: {link(tdir / "files.html", "xcrg toggle report")}.</p></div>

<h2 id="regtoggle">Register-bit toggle (generated register block)</h2>
<div class="card"><p>{f'{rbt["cov"]}/{rbt["tot"]} bit-directions over {rbt["fields"]} register fields = <b>{rbt["pct"]:.2f}%</b>' if rbt else "no reg_bit_toggle.txt"}</p>
<p><b>Uncovered</b></p>{holes(rb_holes, "none")}
<p class="muted">Every RAL field bit seen rising and falling in DUT read-back (reg_bit_toggle_cov); xsim cannot measure the
generated register block's code toggle.</p></div>

<h2>Static gate</h2>
<div class="card"><table><tr><th>Check</th><th>Result</th><th>Failing</th><th>Waived</th><th>Info</th></tr>{sg_rows or '<tr><td colspan=5 class="muted">no static_gate.txt</td></tr>'}</table>
<p class="muted">Full report: {link(rep / "static_gate.txt", "static_gate.txt")}</p></div>

<h2>More</h2>
<div class="card"><ul>
<li>{link(rep / "coverage_summary.md", "coverage_summary.md")} — per vPlan item and per requirement</li>
<li>{link(rep / "coverage_waivers.md", "coverage_waivers.md")} — every waiver and known hole, with its justification</li>
<li>{link(ip_dir / "vplan" / f"{ip}_testplan.xlsx", f"{ip}_testplan.xlsx")} — test plan, traceability, coverage (Excel)</li>
<li>{link(rep / "regression.txt", "regression.txt")} — one line per test and seed</li>
</ul></div>
</main></body></html>
"""
    out = rep / "coverage_dashboard.html"
    out.write_text(page, encoding="utf-8")
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
