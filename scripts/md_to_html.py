"""Convert a markdown file to a standalone HTML file with print-friendly CSS.

Usage:
    python md_to_html.py <input.md> <output.html>

Chrome can then print the HTML to PDF via:
    chrome --headless --disable-gpu --print-to-pdf=out.pdf --no-margins file:///path/to/out.html
"""

from __future__ import annotations
import sys
from pathlib import Path

try:
    import markdown
except ImportError:
    print("Install: pip install markdown", file=sys.stderr)
    sys.exit(1)


_CSS = """
:root { color-scheme: light; }
* { box-sizing: border-box; }
body {
    font-family: 'Inter', -apple-system, 'Segoe UI', Roboto, sans-serif;
    color: #1a1a1a;
    background: #ffffff;
    line-height: 1.55;
    max-width: 900px;
    margin: 0 auto;
    padding: 24px 36px 48px 36px;
    font-size: 11pt;
}
h1 { font-size: 22pt; margin: 0 0 12px 0; font-weight: 700; border-bottom: 2px solid #1a1a1a; padding-bottom: 10px; }
h2 { font-size: 16pt; margin: 28px 0 12px 0; font-weight: 700; color: #1a1a1a; border-bottom: 1px solid #ddd; padding-bottom: 6px; }
h3 { font-size: 13pt; margin: 22px 0 10px 0; font-weight: 600; color: #2a2a2a; }
h4 { font-size: 11pt; margin: 18px 0 8px 0; font-weight: 600; color: #3a3a3a; }
p { margin: 8px 0; }
strong { font-weight: 600; color: #000; }
code {
    font-family: 'JetBrains Mono', 'Fira Code', Consolas, monospace;
    background: #f4f4f6;
    padding: 1px 5px;
    border-radius: 3px;
    font-size: 9.5pt;
    color: #c7254e;
}
pre {
    background: #f6f6f8;
    padding: 12px 14px;
    border-radius: 4px;
    border: 1px solid #e3e3e5;
    overflow-x: auto;
    font-size: 9pt;
    line-height: 1.4;
    page-break-inside: avoid;
}
pre code { background: transparent; padding: 0; color: #1a1a1a; }
table {
    border-collapse: collapse;
    margin: 12px 0;
    font-size: 10pt;
    width: 100%;
}
th, td {
    border: 1px solid #d8d8d8;
    padding: 6px 10px;
    text-align: left;
    vertical-align: top;
}
th { background: #f4f4f6; font-weight: 600; }
tr:nth-child(even) { background: #fafafa; }
ul, ol { margin: 8px 0 8px 22px; padding-left: 6px; }
li { margin: 3px 0; }
hr { border: none; border-top: 1px solid #ddd; margin: 24px 0; }
blockquote {
    border-left: 3px solid #888;
    margin: 12px 0;
    padding: 4px 14px;
    color: #555;
    background: #fafafa;
}
a { color: #0a6fcf; text-decoration: none; }
a:hover { text-decoration: underline; }
em { color: #444; }
.page-break { page-break-after: always; }

@media print {
    body { max-width: none; padding: 18px 24px; font-size: 9.5pt; }
    h1 { font-size: 18pt; }
    h2 { font-size: 13pt; page-break-after: avoid; }
    h3 { font-size: 11pt; page-break-after: avoid; }
    pre, table { page-break-inside: avoid; }
    a { color: inherit; text-decoration: none; }
}
"""


def convert(md_path: Path, out_path: Path) -> None:
    text = md_path.read_text(encoding="utf-8")
    html_body = markdown.markdown(
        text,
        extensions=["fenced_code", "tables", "toc", "sane_lists"],
        output_format="html5",
    )
    title = md_path.stem.replace("_", " ")
    html = (
        f"<!DOCTYPE html>\n<html lang='en'>\n<head>\n"
        f"<meta charset='utf-8'>\n<title>{title}</title>\n"
        f"<style>{_CSS}</style>\n</head>\n<body>\n{html_body}\n</body>\n</html>\n"
    )
    out_path.write_text(html, encoding="utf-8")
    print(f"Wrote {out_path} ({len(html):,} chars)")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    convert(Path(sys.argv[1]), Path(sys.argv[2]))
