"""Wave 6.13d (C1) — non-regression snapshot of the STRUCTURAL IDENTITY parser.

Reads every real [StructuralCapture] raw_text=... from logs/backend.log, runs it
through extract_from_description + render_clause, and dumps the rendered clause
per unique capture. Run BEFORE and AFTER the door-quote parser fix, then diff:
ONLY quoted-door captures should change (gaining the dropped door position).
Everything else must stay byte-identical — proof the fix is purely additive.
"""
import ast
import json
import sys

import prompt_engine.atmosphere_dna  # noqa: F401  triggers registration
from prompt_engine.structural_identity import (
    extract_from_description,
    render_clause,
)

raws = []
with open("logs/backend.log", encoding="utf-8", errors="replace") as fh:
    for line in fh:
        idx = line.find("raw_text=")
        if idx < 0:
            continue
        lit = line[idx + len("raw_text="):].rstrip("\r\n")
        try:
            val = ast.literal_eval(lit)
        except Exception:
            continue
        if isinstance(val, str) and val.strip():
            raws.append(val)

# dedupe, preserve order
seen = set()
uniq = []
for r in raws:
    if r not in seen:
        seen.add(r)
        uniq.append(r)

snapshot = {}
for i, raw in enumerate(uniq):
    idy = extract_from_description(raw)
    snapshot[f"cap{i:03d}"] = {
        "raw": raw,
        "clause": render_clause(idy),
        "interior_door": idy.interior_door,
        "dominant_opening": idy.dominant_opening,
    }

out = sys.argv[1] if len(sys.argv) > 1 else "_wave_613d_before.json"
with open(out, "w", encoding="utf-8") as fh:
    json.dump(snapshot, fh, ensure_ascii=False, indent=2, sort_keys=True)
print(f"{len(uniq)} unique captures -> {out}")
