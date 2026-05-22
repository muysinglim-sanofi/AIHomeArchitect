"""
Frontend Audit 2026-05-22 -> PDF renderer.

Reuses the render() function from render_wave5_audit.py to emit
docs/FRONTEND_AUDIT_2026_05_22.pdf with consistent styling.

Run:
    python docs/render_frontend_audit.py
"""

from __future__ import annotations

import os
from render_wave5_audit import render


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    md = os.path.join(here, "FRONTEND_AUDIT_2026_05_22.md")
    out = os.path.join(here, "FRONTEND_AUDIT_2026_05_22.pdf")
    render(md, out)
    print(f"Wrote {out}  ({os.path.getsize(out):,} bytes)")
