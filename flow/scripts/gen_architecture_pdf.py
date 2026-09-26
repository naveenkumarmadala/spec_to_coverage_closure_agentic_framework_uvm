#!/usr/bin/env python3
"""
gen_architecture_pdf.py — render docs/vlsi_agent_flow_architecture.html (including its
client-side mermaid.js diagrams) with a real browser engine and print it to
docs/VLSI_Agent_Pipeline.pdf.

Needs Playwright + a Chromium binary (env/.venv):
    pip install playwright && python3 -m playwright install chromium

Usage: python3 flow/scripts/gen_architecture_pdf.py
"""
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "docs" / "vlsi_agent_flow_architecture.html"
OUT = ROOT / "docs" / "VLSI_Agent_Pipeline.pdf"


def main():
    if not SRC.exists():
        sys.exit(f"ERROR: {SRC} not found")

    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page()
        page.goto(SRC.as_uri())
        # mermaid.initialize({startOnLoad:true}) parses every .mermaid <pre> and
        # replaces it with an <svg> once ready; wait for that to actually happen
        # rather than a fixed sleep.
        page.wait_for_function(
            """() => {
                const blocks = document.querySelectorAll('.mermaid');
                if (blocks.length === 0) return false;
                return Array.from(blocks).every(b => b.querySelector('svg'));
            }""",
            timeout=30000,
        )
        page.pdf(
            path=str(OUT),
            format="A4",
            print_background=True,
            margin={"top": "12mm", "bottom": "14mm", "left": "10mm", "right": "10mm"},
        )
        browser.close()
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
