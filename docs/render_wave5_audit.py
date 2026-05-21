"""
Wave 5.0 audit -> PDF renderer.

Walks docs/WAVE_5_0_AUDIT.md line-by-line and emits docs/WAVE_5_0_AUDIT.pdf
using fpdf2 + Arial (Windows system font; full BMP unicode coverage so the
audit's em-dashes, arrows and check marks all render).

Run:
    python docs/render_wave5_audit.py
"""

from __future__ import annotations

import os
import re
from fpdf import FPDF


# ── Style constants ─────────────────────────────────────────────────────────────
MARGIN_X = 18
MARGIN_TOP = 18
MARGIN_BOTTOM = 18

H1_SIZE = 20
H2_SIZE = 14
H3_SIZE = 11.5
BODY_SIZE = 10
CODE_SIZE = 8.5
TABLE_HEADER_SIZE = 9
TABLE_BODY_SIZE = 8.5

INK = (28, 28, 30)
MUTED = (90, 90, 94)
RULE = (220, 220, 224)
CODE_BG = (245, 245, 247)
TABLE_HEADER_BG = (240, 240, 244)
TABLE_ROW_ALT = (250, 250, 252)


# ── Fonts ───────────────────────────────────────────────────────────────────────
WIN_FONTS = "C:/Windows/Fonts"
FONT_REGULAR = f"{WIN_FONTS}/arial.ttf"
FONT_BOLD = f"{WIN_FONTS}/arialbd.ttf"
FONT_ITALIC = f"{WIN_FONTS}/ariali.ttf"
FONT_BOLD_ITALIC = f"{WIN_FONTS}/arialbi.ttf"
FONT_MONO = f"{WIN_FONTS}/consola.ttf"
FONT_MONO_BOLD = f"{WIN_FONTS}/consolab.ttf"


def _build_pdf() -> FPDF:
    pdf = FPDF(orientation="P", unit="mm", format="A4")
    pdf.set_margins(MARGIN_X, MARGIN_TOP, MARGIN_X)
    pdf.set_auto_page_break(auto=True, margin=MARGIN_BOTTOM)
    pdf.add_font("Arial", "", FONT_REGULAR, uni=True)
    pdf.add_font("Arial", "B", FONT_BOLD, uni=True)
    pdf.add_font("Arial", "I", FONT_ITALIC, uni=True)
    pdf.add_font("Arial", "BI", FONT_BOLD_ITALIC, uni=True)
    if os.path.exists(FONT_MONO):
        pdf.add_font("Mono", "", FONT_MONO, uni=True)
    if os.path.exists(FONT_MONO_BOLD):
        pdf.add_font("Mono", "B", FONT_MONO_BOLD, uni=True)
    pdf.set_text_color(*INK)
    pdf.add_page()
    return pdf


# ── Helpers ─────────────────────────────────────────────────────────────────────
def _set_font(pdf: FPDF, family: str, style: str, size: float) -> None:
    pdf.set_font(family, style, size)


def _rule(pdf: FPDF, gap_above: float = 1.5, gap_below: float = 1.5) -> None:
    pdf.ln(gap_above)
    pdf.set_draw_color(*RULE)
    pdf.set_line_width(0.2)
    pdf.line(MARGIN_X, pdf.get_y(), pdf.w - MARGIN_X, pdf.get_y())
    pdf.ln(gap_below)


def _h1(pdf: FPDF, text: str) -> None:
    if pdf.get_y() > MARGIN_TOP + 2:
        pdf.ln(6)
    _set_font(pdf, "Arial", "B", H1_SIZE)
    pdf.set_text_color(*INK)
    pdf.multi_cell(0, 9, text)
    _rule(pdf, 1.5, 3)


def _h2(pdf: FPDF, text: str) -> None:
    pdf.ln(4)
    _set_font(pdf, "Arial", "B", H2_SIZE)
    pdf.set_text_color(*INK)
    pdf.multi_cell(0, 6.5, text)
    _rule(pdf, 0.5, 2)


def _h3(pdf: FPDF, text: str) -> None:
    pdf.ln(2.5)
    _set_font(pdf, "Arial", "B", H3_SIZE)
    pdf.set_text_color(*INK)
    pdf.multi_cell(0, 5, text)
    pdf.ln(0.5)


# Inline bold/italic walker — splits a line into runs with style flags so we can
# stream them through pdf.write() and let fpdf2 wrap.
_INLINE_TOKEN = re.compile(
    r"(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`)"
)


def _strip_inline_markup(s: str) -> str:
    # Convert markdown link [text](url) -> "text (url)"
    s = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r"\1 (\2)", s)
    return s


def _render_inline(pdf: FPDF, text: str, base_size: float = BODY_SIZE) -> None:
    """Render a single paragraph with inline **bold**, *italic*, `code`."""
    pdf.set_text_color(*INK)
    parts = _INLINE_TOKEN.split(_strip_inline_markup(text))
    line_h = 5
    for part in parts:
        if not part:
            continue
        if part.startswith("**") and part.endswith("**"):
            _set_font(pdf, "Arial", "B", base_size)
            pdf.write(line_h, part[2:-2])
        elif part.startswith("*") and part.endswith("*") and len(part) > 2:
            _set_font(pdf, "Arial", "I", base_size)
            pdf.write(line_h, part[1:-1])
        elif part.startswith("`") and part.endswith("`"):
            _set_font(pdf, "Mono" if os.path.exists(FONT_MONO) else "Arial", "", base_size - 0.5)
            pdf.write(line_h, part[1:-1])
        else:
            _set_font(pdf, "Arial", "", base_size)
            pdf.write(line_h, part)
    pdf.ln(line_h + 1)


def _paragraph(pdf: FPDF, text: str) -> None:
    _render_inline(pdf, text)


def _bullet(pdf: FPDF, text: str, indent: float = 4.0) -> None:
    x0 = pdf.get_x()
    pdf.set_x(MARGIN_X + indent)
    pdf.set_text_color(*MUTED)
    _set_font(pdf, "Arial", "", BODY_SIZE)
    pdf.write(5, "•  ")
    pdf.set_text_color(*INK)
    _render_inline(pdf, text)
    pdf.set_x(x0)


def _code_block(pdf: FPDF, lines: list[str]) -> None:
    """Render a fenced code block with a light background plate."""
    if not lines:
        return
    pdf.ln(1.5)
    family = "Mono" if os.path.exists(FONT_MONO) else "Arial"
    _set_font(pdf, family, "", CODE_SIZE)
    line_h = 4
    box_w = pdf.w - 2 * MARGIN_X
    # Trim trailing blanks
    while lines and not lines[-1].strip():
        lines.pop()
    if not lines:
        return
    # Draw plate
    box_h = line_h * len(lines) + 4
    if pdf.get_y() + box_h > pdf.h - MARGIN_BOTTOM:
        pdf.add_page()
    pdf.set_fill_color(*CODE_BG)
    pdf.set_draw_color(*RULE)
    pdf.set_line_width(0.2)
    pdf.rect(MARGIN_X, pdf.get_y(), box_w, box_h, style="DF")
    pdf.set_xy(MARGIN_X + 2, pdf.get_y() + 2)
    pdf.set_text_color(*INK)
    for raw in lines:
        # render one line; fpdf2 will not wrap inside multi_cell with our settings,
        # but we cap line length conservatively
        line = raw.rstrip("\n")
        if len(line) > 110:
            line = line[:107] + "..."
        pdf.cell(box_w - 4, line_h, line, ln=1)
        pdf.set_x(MARGIN_X + 2)
    pdf.set_xy(MARGIN_X, pdf.get_y() + 2)


# ── Tables ──────────────────────────────────────────────────────────────────────
def _parse_table_block(lines: list[str]) -> tuple[list[str], list[list[str]]]:
    """Given a contiguous block of pipe-table lines, return (headers, rows)."""
    cleaned = [ln.strip().strip("|") for ln in lines]
    # Drop the alignment row (---|---)
    rows = [c for c in cleaned if not re.match(r"^\s*[-: ]+(\|[-: ]+)*\s*$", c)]
    headers = [c.strip() for c in rows[0].split("|")]
    body = [[c.strip() for c in r.split("|")] for r in rows[1:]]
    # Pad rows to header length
    for r in body:
        while len(r) < len(headers):
            r.append("")
    return headers, body


def _render_table(pdf: FPDF, headers: list[str], rows: list[list[str]]) -> None:
    if not headers:
        return
    pdf.ln(1.5)
    ncols = len(headers)
    avail = pdf.w - 2 * MARGIN_X
    # Allocate column widths proportional to max-content length, with min/max clamps
    max_lens = [max(len(headers[i]), *(len(r[i]) for r in rows)) for i in range(ncols)]
    total = sum(max_lens) or 1
    widths = [max(20.0, min(80.0, avail * (m / total))) for m in max_lens]
    scale = avail / sum(widths)
    widths = [w * scale for w in widths]

    line_h = 4.6

    def render_row(cells: list[str], header: bool, alt: bool) -> None:
        # Pre-measure cell heights
        family = "Arial"
        size = TABLE_HEADER_SIZE if header else TABLE_BODY_SIZE
        style = "B" if header else ""
        _set_font(pdf, family, style, size)
        # multi_cell will be used per cell, so we need a manual height calc
        cell_heights = []
        for i, c in enumerate(cells):
            text = _strip_inline_markup(c).replace("**", "")
            # approximate wrap
            # Use multi_cell with split_only to count lines
            n_lines = max(1, len(pdf.multi_cell(widths[i], line_h, text, split_only=True)))
            cell_heights.append(n_lines * line_h)
        row_h = max(cell_heights) + 0.8
        # Page break guard
        if pdf.get_y() + row_h > pdf.h - MARGIN_BOTTOM:
            pdf.add_page()
        x_start = MARGIN_X
        y_start = pdf.get_y()
        # Background
        bg = TABLE_HEADER_BG if header else (TABLE_ROW_ALT if alt else (255, 255, 255))
        pdf.set_fill_color(*bg)
        pdf.set_draw_color(*RULE)
        pdf.set_line_width(0.15)
        pdf.rect(x_start, y_start, sum(widths), row_h, style="DF")
        # Cells
        cx = x_start
        for i, c in enumerate(cells):
            text = _strip_inline_markup(c).replace("**", "")
            pdf.set_xy(cx + 1, y_start + 0.5)
            pdf.set_text_color(*INK)
            _set_font(pdf, family, style, size)
            pdf.multi_cell(widths[i] - 2, line_h, text, align="L")
            cx += widths[i]
        pdf.set_xy(x_start, y_start + row_h)

    render_row(headers, header=True, alt=False)
    for j, row in enumerate(rows):
        render_row(row, header=False, alt=(j % 2 == 0))
    pdf.ln(2)


# ── Main walker ─────────────────────────────────────────────────────────────────
def render(md_path: str, pdf_path: str) -> None:
    with open(md_path, "r", encoding="utf-8") as f:
        src = f.read().splitlines()

    pdf = _build_pdf()

    i = 0
    in_code = False
    code_buf: list[str] = []
    table_buf: list[str] = []

    def flush_table():
        nonlocal table_buf
        if table_buf:
            headers, rows = _parse_table_block(table_buf)
            _render_table(pdf, headers, rows)
            table_buf = []

    while i < len(src):
        line = src[i]
        stripped = line.strip()

        # ── code fences ────────────────────────────────────────────────────────
        if stripped.startswith("```"):
            flush_table()
            if in_code:
                _code_block(pdf, code_buf)
                code_buf = []
                in_code = False
            else:
                in_code = True
            i += 1
            continue
        if in_code:
            code_buf.append(line)
            i += 1
            continue

        # ── tables ─────────────────────────────────────────────────────────────
        if stripped.startswith("|") and stripped.endswith("|"):
            table_buf.append(line)
            i += 1
            continue
        else:
            flush_table()

        # ── blank line ─────────────────────────────────────────────────────────
        if not stripped:
            pdf.ln(2)
            i += 1
            continue

        # ── horizontal rule ────────────────────────────────────────────────────
        if stripped in ("---", "***"):
            _rule(pdf, 2, 2)
            i += 1
            continue

        # ── headings ───────────────────────────────────────────────────────────
        if stripped.startswith("### "):
            _h3(pdf, stripped[4:].strip())
            i += 1
            continue
        if stripped.startswith("## "):
            _h2(pdf, stripped[3:].strip())
            i += 1
            continue
        if stripped.startswith("# "):
            _h1(pdf, stripped[2:].strip())
            i += 1
            continue

        # ── bullets ────────────────────────────────────────────────────────────
        m = re.match(r"^(\s*)[-*]\s+(.*)", line)
        if m:
            indent_level = len(m.group(1)) // 2
            _bullet(pdf, m.group(2), indent=4.0 + indent_level * 4)
            i += 1
            continue

        # ── paragraph ──────────────────────────────────────────────────────────
        _paragraph(pdf, stripped)
        i += 1

    flush_table()
    if in_code:
        _code_block(pdf, code_buf)

    pdf.output(pdf_path)


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    md = os.path.join(here, "WAVE_5_0_AUDIT.md")
    out = os.path.join(here, "WAVE_5_0_AUDIT.pdf")
    render(md, out)
    print(f"Wrote {out}  ({os.path.getsize(out):,} bytes)")
