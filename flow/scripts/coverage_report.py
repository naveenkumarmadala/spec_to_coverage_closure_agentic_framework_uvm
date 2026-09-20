#!/usr/bin/env python3
"""
coverage_report.py — roll coverage up the traceability spine (bin -> vPlan -> REQ)
into a data-driven Markdown report. IP-agnostic; reads only the IP's own files.

Sources: vplan.yaml (items + status + traces_to), requirements.md (REQ text),
reports/regression.txt, reports/_cov/functional_report/ and code_report/ (xcrg).

Usage:  python3 flow/scripts/coverage_report.py ips/<ip>
Output: ips/<ip>/reports/coverage_summary.md   (headline + per-vPlan + per-REQ tables)

Numbers come from real tool output; nothing is hardcoded. Prose/waiver justification
is added by coverage-closure on top of these tables.
"""
import re, sys
from pathlib import Path
import yaml


def parse_reqs(md: Path):
    reqs = {}
    if md.exists():
        for line in md.read_text(errors="replace").splitlines():
            m = re.match(r"\|\s*(REQ-[A-Z]+-\d+)\s*\|([^|]*)", line)
            if m:
                reqs[m.group(1)] = m.group(2).strip()
    return reqs


def regression_line(reports: Path):
    f = reports / "regression.txt"
    if not f.exists():
        return "not run"
    first = f.read_text(errors="replace").splitlines()[:1]
    return first[0].lstrip("# ").strip() if first else "see regression.txt"


def dash(reports, sub):
    p = reports / "_cov" / sub / ("functionalCoverageReport" if "functional" in sub else "codeCoverageReport") / "dashboard.html"
    if not p.exists():
        return None
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", p.read_text(errors="replace")))


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: coverage_report.py ips/<ip>")
    ip_dir = Path(sys.argv[1]).resolve()
    ip = ip_dir.name
    reports = ip_dir / "reports"
    vplan = yaml.safe_load((ip_dir / "vplan" / "vplan.yaml").read_text())
    items = vplan.get("items", [])
    reqs = parse_reqs(ip_dir / "spec" / "requirements.md")

    # headline numbers (real)
    ft = dash(reports, "functional_report")
    fm = re.search(r"Coverage Summary Score Inst Score ([0-9.]+)", ft) if ft else None
    func = f"{float(fm.group(1)):.1f}%" if fm else "not run"
    ct = dash(reports, "code_report")
    cm = re.search(r"Statement Coverage Score Branch Coverage Score Condition Coverage Score "
                   r"Toggle Coverage Score" + r"\s+([0-9.]+)" * 7, ct) if ct else None
    code = (f"stmt {float(cm.group(4)):.1f}% / branch {float(cm.group(5)):.1f}% / "
            f"cond {float(cm.group(6)):.1f}% / toggle {float(cm.group(7)):.1f}%") if cm else "not run"

    L = [f"# {ip.upper()} — Coverage Summary (generated)", "",
         f"- **Seeded regression:** {regression_line(reports)}",
         f"- **Functional coverage (union):** {func}  (goal {vplan.get('coverage_goal_pct','?')}%)",
         f"- **DUT code coverage:** {code}", "",
         "## Per-vPlan item", "",
         "| VP-ID | Method | Requirement(s) | Status |", "|---|---|---|---|"]
    for it in items:
        L.append(f"| {it.get('id','')} | {it.get('method','')} | "
                 f"{', '.join(it.get('traces_to', []))} | {it.get('status','planned')} |")

    L += ["", "## Per-requirement closure", "", "| REQ | vPlan item(s) | Status |", "|---|---|---|"]
    for rid in reqs:
        cover = [it for it in items if rid in it.get("traces_to", [])]
        if not cover:
            st = "**NO vPlan ITEM**"
        else:
            st = "covered" if {it.get("status", "planned") for it in cover} <= {"covered", "closed", "waived"} else "open"
        L.append(f"| {rid} | {', '.join(it['id'] for it in cover) or '—'} | {st} |")

    L += ["", "> Numbers are read from reports/_cov and reports/regression.txt; waiver justifications "
          "are maintained by coverage-closure. Regenerate with `flow/scripts/coverage_report.py`."]
    out = reports / "coverage_summary.md"
    out.parent.mkdir(exist_ok=True)
    out.write_text("\n".join(L) + "\n")
    print(f"wrote {out}  ({len(items)} vPlan items, {len(reqs)} requirements)")


if __name__ == "__main__":
    main()
