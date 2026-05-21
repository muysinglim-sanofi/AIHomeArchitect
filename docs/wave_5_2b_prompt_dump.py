"""
Wave 5.2b audit harness — dumps the REAL final prompts for both composers
across the 5 scenarios, with no truncation / paraphrasing.

Usage:
    python docs/wave_5_2b_prompt_dump.py

Outputs:
    docs/wave_5_2b_prompts_raw.txt  — full raw prompts + section breakdowns

No backend modification. Pure read-only execution of compose_generation_prompt
(v1 frozen + v2) on representative inputs that match the user's complex
benchmark apartment (balcony sliding door + glass partition + visible rear
zone + open-plan continuity).
"""

from __future__ import annotations

import io
import json
import os
import sys

# Make the backend package importable.
HERE = os.path.dirname(os.path.abspath(__file__))
BACKEND = os.path.abspath(os.path.join(HERE, "..", "backend"))
sys.path.insert(0, BACKEND)

from prompt_engine.composer import compose_generation_prompt as compose_v1  # noqa: E402
from prompt_engine.composer_v2 import compose_generation_prompt as compose_v2  # noqa: E402
from prompt_engine.structural_identity import (  # noqa: E402
    extract_from_description,
    render_clause,
    render_negative_anchors,
)
from prompt_engine.refinement_authority import (  # noqa: E402
    accumulate_refinements,
    build_authorized_changes_clause,
)
from version_state import build_source_continuity_clause  # noqa: E402


# ── REPRESENTATIVE INPUTS ────────────────────────────────────────────────────

# Realistic GPT-4o-mini output for the user's complex benchmark apartment:
# the photo they shared (sliding door + balcony + glass partition + visible
# rear-room window). This is the kind of text vision_analysis produces today.
COMPLEX_ROOM_DESCRIPTION = (
    "Living room with a large floor-to-ceiling sliding glass door on the "
    "left wall opening to a balcony with vertical louvered shutters visible. "
    "Eye-level single-point perspective, medium spatial depth. Black-framed "
    "glass partition on the right separating the living zone from a rear "
    "room visible through the partition; a window is visible on the rear "
    "wall of the back room. Standard ceiling height. Herringbone wood floor "
    "throughout. Open kitchen visible on the right beyond the partition."
)

# Simple living-room reference (no rear-zone complexity) — for comparing
# v1 vs v2 on apartments that DON'T trigger the failure mode.
SIMPLE_ROOM_DESCRIPTION = (
    "Living room with a single large window on the back wall. Eye-level "
    "single-point perspective, medium spatial depth. Standard ceiling "
    "height. Oak hardwood floor."
)


def _build_v1_history_for_v2(style_label_v1: str) -> list[dict]:
    """Realistic chat history after one successful V1 generation."""
    return [
        {
            "role": "ai",
            "content": f"Your space is ready. Generating your first "
                       f"{style_label_v1} vision now.",
        },
        {
            "role": "ai",
            "content": f"Here is your first {style_label_v1} vision — "
                       "warmer materials, layered lighting, hospitality "
                       "presence. What would you like to refine?",
        },
    ]


def _structural_identity_clause(room_desc: str) -> tuple[str, str]:
    """Render the structural_identity clause + negative anchors clause exactly
    as main.py would, given a room description string."""
    identity = extract_from_description(room_desc)
    si_clause = render_clause(identity, mode="V1")
    neg_clause = render_negative_anchors(identity)
    return si_clause, neg_clause


def _section_breakdown(prompt: str) -> list[tuple[str, int]]:
    """Split a prompt by blank-line section boundaries and report (label, len).
    Detects section headers from the leading 25 chars of each section."""
    out: list[tuple[str, int]] = []
    sections = [s for s in prompt.split("\n\n") if s.strip()]
    for s in sections:
        head = s.strip()[:60].replace("\n", " ").strip()
        out.append((head, len(s)))
    return out


def _dump_scenario(out, label: str, *, v1_args: dict, v2_args: dict):
    out.write("\n\n" + "=" * 100 + "\n")
    out.write(f"SCENARIO {label}\n")
    out.write("=" * 100 + "\n")

    out.write("\n--- INPUTS (identical for both composers, except internal routing) ---\n")
    safe = {k: (v if not isinstance(v, str) or len(v) < 400 else v[:400] + "…[trunc display]")
            for k, v in v1_args.items() if k not in ("history",)}
    out.write(json.dumps(safe, indent=2, default=str))
    if v1_args.get("history"):
        out.write("\n  history (truncated display): " +
                  json.dumps(v1_args["history"], indent=2)[:500] + "…\n")

    v1_prompt = compose_v1(**v1_args)
    v2_prompt = compose_v2(**v2_args)

    out.write("\n\n--- COMPOSER_V1 FULL PROMPT ---\n")
    out.write(f"size={len(v1_prompt)} chars\n")
    out.write("section breakdown:\n")
    for head, n in _section_breakdown(v1_prompt):
        out.write(f"  [{n:5d}]  {head}\n")
    out.write("\n>>> RAW v1:\n")
    out.write(v1_prompt + "\n<<< end v1\n")

    out.write("\n\n--- COMPOSER_V2 FULL PROMPT ---\n")
    out.write(f"size={len(v2_prompt)} chars\n")
    out.write("section breakdown:\n")
    for head, n in _section_breakdown(v2_prompt):
        out.write(f"  [{n:5d}]  {head}\n")
    out.write("\n>>> RAW v2:\n")
    out.write(v2_prompt + "\n<<< end v2\n")

    out.write(f"\n--- DELTA ---\n")
    out.write(f"v1: {len(v1_prompt):5d} chars  →  v2: {len(v2_prompt):5d} chars   "
              f"({len(v2_prompt) - len(v1_prompt):+d} chars; "
              f"{(len(v2_prompt) - len(v1_prompt)) * 100.0 / len(v1_prompt):+.1f}%)\n")


def main() -> None:
    out = io.StringIO()
    out.write("WAVE 5.2b — REAL FINAL PROMPTS (composer v1 vs composer_v2)\n")
    out.write("Complex benchmark apartment: sliding door + balcony + glass "
              "partition + visible rear-room window.\n")

    # Pre-render the V1 structural_identity + negative-anchors clauses,
    # as main.py does before calling the composer.
    si_clause_v1, neg_clause_v1 = _structural_identity_clause(COMPLEX_ROOM_DESCRIPTION)

    out.write(f"\nstructural_identity clause ({len(si_clause_v1)} chars):\n  {si_clause_v1}\n")
    out.write(f"structural_negative_anchors ({len(neg_clause_v1)} chars):\n  {neg_clause_v1}\n")

    # ── SCENARIO A — V1 + Warm Modern ────────────────────────────────────────
    common_v1 = dict(
        style_label="Warm Modern · Vision 1",
        room_type="Living Room",
        room_description=COMPLEX_ROOM_DESCRIPTION,
        user_instruction="",
        iteration=1,
        history=[],
        secondary_visible_spaces=["kitchen"],
        compact_prompts=False,
        structural_identity=si_clause_v1,
        source_continuity="",
        structural_negative_anchors=neg_clause_v1,
        authorized_user_changes="",
    )
    _dump_scenario(out, "A — V1 Warm Modern (complex apartment)",
                   v1_args=common_v1, v2_args=common_v1)

    # ── SCENARIO B — V1 + Japandi Calm ───────────────────────────────────────
    sB = dict(common_v1, style_label="Japandi Calm · Vision 1")
    _dump_scenario(out, "B — V1 Japandi Calm (complex apartment)",
                   v1_args=sB, v2_args=sB)

    # ── SCENARIO C — V1 + Bali Sanctuary (closest registered to "Tropical Bali")
    sC = dict(common_v1, style_label="Bali Sanctuary · Vision 1")
    _dump_scenario(out, "C — V1 Bali Sanctuary (complex apartment)",
                   v1_args=sC, v2_args=sC)

    # ── SCENARIO D — V2 refinement "make it warmer" ──────────────────────────
    history_d = _build_v1_history_for_v2("Warm Modern")
    refinement_text = "make it warmer"
    auc_clause = build_authorized_changes_clause(refinement_text, iteration=2)
    source_continuity_clause = build_source_continuity_clause(
        source_type="latest_version", iteration=2,
    )
    sD = dict(
        style_label="Warm Modern · Vision 2",
        room_type="Living Room",
        room_description=COMPLEX_ROOM_DESCRIPTION,
        user_instruction=refinement_text,
        iteration=2,
        history=history_d,
        secondary_visible_spaces=["kitchen"],
        compact_prompts=False,
        structural_identity=si_clause_v1,
        source_continuity=source_continuity_clause,
        structural_negative_anchors=neg_clause_v1,
        authorized_user_changes=auc_clause,
    )
    _dump_scenario(out, "D — V2 refinement 'make it warmer' (complex apartment)",
                   v1_args=sD, v2_args=sD)

    # ── SCENARIO E — V2 atmosphere switch: Soft Luxury → Japandi Calm ────────
    history_e = _build_v1_history_for_v2("Soft Luxury")
    refinement_e = "switch to Japandi Calm"
    auc_e = build_authorized_changes_clause(refinement_e, iteration=2)
    sE = dict(
        style_label="Japandi Calm · Vision 2",
        room_type="Living Room",
        room_description=COMPLEX_ROOM_DESCRIPTION,
        user_instruction=refinement_e,
        iteration=2,
        history=history_e,
        secondary_visible_spaces=["kitchen"],
        compact_prompts=False,
        structural_identity=si_clause_v1,
        source_continuity=source_continuity_clause,
        structural_negative_anchors=neg_clause_v1,
        authorized_user_changes=auc_e,
    )
    _dump_scenario(out, "E — V2 atmosphere switch Soft Luxury → Japandi (complex)",
                   v1_args=sE, v2_args=sE)

    # ── SUPPLEMENT: V1 simple apartment for behavioural comparison ───────────
    si_simple, neg_simple = _structural_identity_clause(SIMPLE_ROOM_DESCRIPTION)
    sSimple = dict(common_v1,
                   style_label="Japandi Calm · Vision 1",
                   room_description=SIMPLE_ROOM_DESCRIPTION,
                   structural_identity=si_simple,
                   structural_negative_anchors=neg_simple,
                   secondary_visible_spaces=[])
    _dump_scenario(out, "F (supplement) — V1 Japandi Calm SIMPLE apartment",
                   v1_args=sSimple, v2_args=sSimple)

    out_path = os.path.join(HERE, "wave_5_2b_prompts_raw.txt")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(out.getvalue())
    print(f"Wrote {out_path}  ({os.path.getsize(out_path):,} bytes)")


if __name__ == "__main__":
    main()
