"""Render Wave 5.2 audit Markdown -> PDF using the existing renderer."""

import os
import sys

# Import the generic `render(md_path, pdf_path)` from the Wave 5.0 audit renderer.
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
from render_wave5_audit import render  # noqa: E402

if __name__ == "__main__":
    md = os.path.join(here, "WAVE_5_2_AUDIT.md")
    out = os.path.join(here, "WAVE_5_2_AUDIT.pdf")
    render(md, out)
    print(f"Wrote {out}  ({os.path.getsize(out):,} bytes)")
