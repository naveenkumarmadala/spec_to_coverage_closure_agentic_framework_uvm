#!/usr/bin/env python3
"""
doc_to_text.py — convert a requirement/spec document to plain text/markdown so the
spec-ingestor can read it. IP-agnostic; used at the front door of the flow.

Supported inputs:
  .docx  -> text + tables (pure stdlib zip/XML parse; no external package needed)
  .md / .txt -> passed through unchanged
  .pdf   -> not handled here; the spec-ingestor reads PDFs natively via its Read tool
            (or use the `pdf` skill). This script tells you so rather than failing silently.

Usage:  python3 flow/scripts/doc_to_text.py <input> [> out.md]
Tables render as GitHub-style pipe rows so register/requirement tables survive.
"""
import sys, zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"


def _text(el):
    return "".join(t.text or "" for t in el.iter(W + "t"))


def docx_to_md(path: Path) -> str:
    root = ET.fromstring(zipfile.ZipFile(path).read("word/document.xml"))
    out = []
    for c in root.find(W + "body"):
        if c.tag == W + "p":
            t = _text(c).strip()
            if t:
                out.append(t)
        elif c.tag == W + "tbl":
            rows = [[_text(tc).strip().replace("\n", " ") for tc in tr.findall(W + "tc")]
                    for tr in c.findall(W + "tr")]
            if rows:
                out.append("| " + " | ".join(rows[0]) + " |")
                out.append("|" + "|".join(["---"] * len(rows[0])) + "|")
                for r in rows[1:]:
                    out.append("| " + " | ".join(r) + " |")
                out.append("")
    return "\n".join(out)


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: doc_to_text.py <file.docx|.md|.txt|.pdf>")
    p = Path(sys.argv[1])
    ext = p.suffix.lower()
    if ext == ".docx":
        sys.stdout.write(docx_to_md(p))
    elif ext in (".md", ".txt"):
        sys.stdout.write(p.read_text(errors="replace"))
    elif ext == ".pdf":
        sys.exit("PDF: read it directly with the spec-ingestor's Read tool (or the `pdf` skill); "
                 "this converter handles .docx/.md/.txt only.")
    else:
        sys.exit(f"unsupported extension: {ext}")


if __name__ == "__main__":
    main()
