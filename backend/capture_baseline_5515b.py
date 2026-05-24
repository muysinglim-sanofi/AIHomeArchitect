"""Wave 5.5.15b — Baseline prompt capture (BEFORE emotional_realism wiring).

Captures the V1 preserve + V1 creative prompts for 3 atmospheres on a
synthetic but realistic structural identity, saves char count + MD5 hash
+ full content per (atm × mode) cell to JSON. The Wave 5.5.15b byte-
exact validator then asserts that post-change prompts differ from this
baseline ONLY by the inserted EMOTIONAL REALISM sentence (+ separator
newline), nothing else.

This is the discipline Wave 5.5.14i lacked — that wave assumed prompts
were byte-identical based on visual inspection of code diffs, but
empirical bench showed otherwise. Byte-exact validation closes that gap.

Run:
    cd backend
    BIMODAL_ENABLED=1 python capture_baseline_5515b.py
"""

from __future__ import annotations
import hashlib
import json
import os
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from prompt_engine import compose_generation_prompt as v1_compose
from prompt_engine.structural_identity import (
    extract_from_description,
    render_clause,
    render_negative_anchors,
)

_ATMOSPHERES = ("Warm Modern", "Japandi Calm", "Nordic Warmth")
_IDENTITY_DESC = (
    "Living room with wide floor-to-ceiling window dominating the rear "
    "wall and an open kitchen visible on the left, with a glass partition."
)


def _build_prompt(atm: str, mode: str) -> str:
    """Replicate the live composer flow for a V1 prompt with the given mode."""
    identity = extract_from_description(_IDENTITY_DESC)
    return v1_compose(
        style_label=atm,
        room_type="living_room",
        room_description=_IDENTITY_DESC,
        user_instruction="",
        iteration=1,
        history=[],
        structural_identity=render_clause(identity, "V1", mode),
        structural_negative_anchors=render_negative_anchors(identity, mode),
        generation_mode=mode,
    )


def main() -> int:
    if not os.environ.get("BIMODAL_ENABLED"):
        print("BIMODAL_ENABLED not set — bimodal path is DORMANT; "
              "baseline will reflect the flag-off prompt. Set the flag "
              "for the meaningful baseline.", file=sys.stderr)

    baseline: dict[str, dict] = {}
    for atm in _ATMOSPHERES:
        for mode in ("preserve", "creative"):
            prompt = _build_prompt(atm, mode)
            key = f"{atm} | {mode}"
            baseline[key] = {
                "atmosphere": atm,
                "mode": mode,
                "chars": len(prompt),
                "md5": hashlib.md5(prompt.encode("utf-8")).hexdigest(),
                "content": prompt,
            }
            print(f"  {key:<32s}  chars={len(prompt):4d}  md5={baseline[key]['md5'][:12]}")

    out = _HERE / "baseline_5515b.json"
    out.write_text(
        json.dumps(baseline, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"\nBaseline saved to {out}")
    print(f"Cells captured: {len(baseline)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
