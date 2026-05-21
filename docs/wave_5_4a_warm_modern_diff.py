"""
Wave 5.4a diff — Warm Modern V2 pure atmosphere switch.

Reconstructs both:
  PRE-5.4a:  composer_v2 5-section REBOOT_FRESH path (bypasses the new delegation
             by calling composer_v2's internal section builders directly with
             the exact inputs the dispatcher would have used).
  POST-5.4a: current public API (which delegates to composer.py Path D).

Same source description, room type, atmosphere, and history. Pure switch (no
customization). Mirrors the user's complex benchmark apartment.

Writes docs/wave_5_4a_warm_modern_diff.txt
"""

from __future__ import annotations

import io
import os
import sys
from difflib import unified_diff

HERE = os.path.dirname(os.path.abspath(__file__))
BACKEND = os.path.abspath(os.path.join(HERE, "..", "backend"))
sys.path.insert(0, BACKEND)

os.environ["COMPOSER_VERSION"] = "v2"

from prompt_engine.composer_v2 import (  # noqa: E402
    compose_generation_prompt as compose_current,
    # internal builders — used to reconstruct pre-5.4a REBOOT_FRESH path
    _build_core,
    _build_source_facts,
    _build_style_block,
    _build_user_block,
    _build_switch_header,
    _SwitchStrategy,
    resolve_switch_strategy,
)
from prompt_engine.atmosphere_dna import label_to_atmosphere_id  # noqa: E402
from prompt_engine.realism_layer import build_compact_realism_block  # noqa: E402
from prompt_engine.style_dna import get_style  # noqa: E402
from prompt_engine.edit_intent import (  # noqa: E402
    EditMode,
    classify_edit_mode,
    build_style_refinement_header,
)
from prompt_engine.anchor_detector import detect_anchors  # noqa: E402
from prompt_engine.structural_identity import (  # noqa: E402
    extract_from_description,
    render_clause,
    render_negative_anchors,
)


# ── Fixed inputs (mirror Wave 5.4 audit) ─────────────────────────────────────
ROOM_DESC = (
    "Living room with a large floor-to-ceiling sliding glass door on the "
    "left wall opening to a balcony with vertical louvered shutters visible. "
    "Eye-level single-point perspective, medium spatial depth. Black-framed "
    "glass partition on the right separating the living zone from a rear "
    "room visible through the partition; a window is visible on the rear "
    "wall of the back room. Standard ceiling height. Herringbone wood floor "
    "throughout. Open kitchen visible on the right beyond the partition."
)
ROOM_TYPE = "Living Room"
TARGET_LABEL = "Warm Modern · Vision 2"
HISTORY = [
    {"role": "ai", "content": "Your space is ready. Generating your first Tropical Bali vision now."},
    {"role": "ai", "content": "Here is your first Tropical Bali vision. What would you like to refine?"},
]
USER_INSTR = "switch to Warm Modern"


def _pre_54a_emission() -> str:
    """Reconstruct the prompt composer_v2 emitted PRE Wave 5.4a for a pure
    atmosphere switch (REBOOT_FRESH). Direct calls to composer_v2's internal
    section builders with the exact same inputs the old dispatcher used."""
    identity = extract_from_description(ROOM_DESC)
    si_clause = render_clause(identity, mode="V1")
    neg_clause = render_negative_anchors(identity)  # unused by 5-section path (absorbed)

    atmosphere_id = label_to_atmosphere_id(TARGET_LABEL)
    edit_mode = classify_edit_mode(USER_INSTR, 2)   # → STYLE_REFINEMENT

    # Resolve strategy from the same inputs main.py uses
    strategy, prev_id, has_cust = resolve_switch_strategy(HISTORY, atmosphere_id, 2)
    assert strategy == _SwitchStrategy.REBOOT_FRESH, f"expected REBOOT_FRESH, got {strategy}"

    # [1] CORE (iter=2, STYLE_REFINEMENT)
    core = _build_core(2, edit_mode)

    # [2] SOURCE FACTS (with anchor-detector dedup as Wave 5.2c shipped)
    anchor_profile = detect_anchors(ROOM_DESC)
    source_facts = _build_source_facts(si_clause, anchor_profile.clause)

    # [3] STYLE TRANSFORMATION (atmosphere-switch variant — _STYLE_PREFIX_ATMOSPHERE_SWITCH)
    style_block = _build_style_block(
        atmosphere_id=atmosphere_id,
        room_type=ROOM_TYPE,
        style_label=TARGET_LABEL,
        compact_prompts=False,
        is_atmosphere_switch=True,
    )

    # [4] QUALITY FLOOR
    quality_floor = build_compact_realism_block()

    # [5] USER DIRECTION — refinement_memory suppressed (REBOOT_FRESH)
    user_block = _build_user_block(
        user_instruction=USER_INSTR,
        iteration=2,
        history=HISTORY,
        authorized_user_changes="",
        suppress_refinement_memory=True,
    )

    # Header — atmosphere-switch local header (Wave 5.2c replacement for SR header)
    header = _build_switch_header(prev_id, get_style(TARGET_LABEL).name, ROOM_TYPE)

    sections = [
        ("header", header),
        ("core_contract", core),
        ("source_facts", source_facts),
        ("style_transformation", style_block),
        ("quality_floor", quality_floor),
        ("user_direction", user_block),
    ]
    present = [(n, t) for n, t in sections if t and t.strip()]
    return "\n\n".join(t for _, t in present)


def _post_54a_emission() -> str:
    """Current public API. With Wave 5.4a active, REBOOT_FRESH delegates to
    composer.py Path D with sanitized inputs."""
    identity = extract_from_description(ROOM_DESC)
    si_clause = render_clause(identity, mode="V1")
    neg_clause = render_negative_anchors(identity)
    return compose_current(
        style_label=TARGET_LABEL,
        room_type=ROOM_TYPE,
        room_description=ROOM_DESC,
        user_instruction=USER_INSTR,
        iteration=2,
        history=HISTORY,
        secondary_visible_spaces=["kitchen"],
        compact_prompts=False,
        structural_identity=si_clause,
        source_continuity="",
        structural_negative_anchors=neg_clause,
        authorized_user_changes="",
    )


def _section_breakdown(prompt: str) -> list[tuple[int, str]]:
    out = []
    for block in prompt.split("\n\n"):
        block = block.strip()
        if not block:
            continue
        head = block.split("\n")[0][:90].strip()
        out.append((len(block), head))
    return out


def main() -> None:
    pre = _pre_54a_emission()
    post = _post_54a_emission()

    out = io.StringIO()
    out.write("=" * 100 + "\n")
    out.write("WARM MODERN V2 (pure atmosphere switch from Tropical Bali V1, complex apartment)\n")
    out.write("PRE-5.4a (composer_v2 5-section REBOOT_FRESH) vs POST-5.4a (composer.py Path D delegation)\n")
    out.write("=" * 100 + "\n")

    out.write(f"\nPRE-5.4a  total size: {len(pre):5d} chars\n")
    out.write(f"POST-5.4a total size: {len(post):5d} chars\n")
    out.write(f"DELTA            : {len(post) - len(pre):+d} chars "
              f"({(len(post) - len(pre)) * 100.0 / len(pre):+.1f}%)\n")

    out.write("\n--- PRE-5.4a section breakdown ---\n")
    for n, h in _section_breakdown(pre):
        out.write(f"  [{n:5d}]  {h}\n")
    out.write("\n--- POST-5.4a section breakdown ---\n")
    for n, h in _section_breakdown(post):
        out.write(f"  [{n:5d}]  {h}\n")

    out.write("\n\n" + "=" * 100 + "\n")
    out.write("RAW PRE-5.4a PROMPT (composer_v2 5-section + atmosphere-switch header + STYLE_PREFIX_ATMOSPHERE_SWITCH)\n")
    out.write("=" * 100 + "\n")
    out.write(pre + "\n")

    out.write("\n\n" + "=" * 100 + "\n")
    out.write("RAW POST-5.4a PROMPT (composer.py Path D — full V1 emission)\n")
    out.write("=" * 100 + "\n")
    out.write(post + "\n")

    out.write("\n\n" + "=" * 100 + "\n")
    out.write("UNIFIED DIFF (PRE → POST)\n")
    out.write("=" * 100 + "\n")
    diff = list(unified_diff(
        pre.splitlines(keepends=True),
        post.splitlines(keepends=True),
        fromfile="PRE-5.4a (composer_v2 REBOOT_FRESH)",
        tofile="POST-5.4a (composer.py Path D)",
        lineterm="",
    ))
    out.writelines(diff if diff else ["(identical)\n"])

    out.write("\n\n" + "=" * 100 + "\n")
    out.write("CONCEPTUAL DELTA (what the user actually pays for in image quality)\n")
    out.write("=" * 100 + "\n")
    deltas = [
        ("ATMOSPHERE SWITCH header (179 chars)",
         "PRE has it — explicit Tropical-Bali→Warm-Modern framing. POST has nothing."),
        ("CORE preamble 'Continue evolving the current vision'",
         "PRE has V2+ continuity preamble. POST has direct V1 task framing."),
        ("STYLE_PREFIX_ATMOSPHERE_SWITCH (290 chars)",
         "PRE: 'Fully replace the previous vision's styling identity (furniture silhouette, "
         "decor density, material palette, lighting language) with the new atmosphere's identity'. "
         "POST: no STYLE prefix. This is the main atmospheric authority signal."),
        ("Full wow_directive (382 chars)",
         "PRE has short 89-char AMBITION line. POST has full wow_directive incl. "
         "'Visible architecture stays recognizable: windows, openings, partitions, existing equipment'."),
        ("NATURAL ENRICHMENT (217 chars)",
         "PRE: absent. POST: present — light decor authority."),
        ("OPENINGS ANCHOR (201 chars)",
         "PRE: absorbed as one clause in CORE. POST: own named P1 block with "
         "'Do not resize, narrow, simplify, or standardize any opening'."),
        ("STRUCTURAL NEGATIVE ANCHORS (340 chars)",
         "PRE: absorbed as one clause in CORE. POST: own named P1 block with "
         "'Do not insert walls between them' explicit phrasing."),
        ("ARCHITECTURAL ANCHORS — LOCKED: (95 chars)",
         "PRE: deduped away by _anchors_fully_in_si on complex apartment. "
         "POST: present — anchor reinforcement repetition."),
        ("VISIBLE SPACES (kitchen continuity, 241 chars)",
         "PRE: absent. POST: present — cross-zone atmospheric continuity."),
        ("ATMOSPHERE BOUNDARY hierarchy assertion (~150 chars)",
         "PRE: deleted. POST: present — 'geometry, openings, and topology override atmosphere'."),
        ("USER DIRECTION: switch to Warm Modern (38 chars)",
         "PRE: present (meta-text emitted as design direction). "
         "POST: '' sanitized — not emitted."),
    ]
    for title, body in deltas:
        out.write(f"\n• {title}\n    {body}\n")

    out.write("\n\nSUMMARY — TRADE-OFF DIRECTION\n")
    out.write("PRE-5.4a path: LESS preservation authority + MORE atmospheric / style authority\n")
    out.write("POST-5.4a path: MORE preservation authority + LESS atmospheric / style authority\n")
    out.write("Visual evidence (Warm Modern V2 screenshots): PRE produced richer atmosphere on this photo.\n")

    path = os.path.join(HERE, "wave_5_4a_warm_modern_diff.txt")
    with open(path, "w", encoding="utf-8") as f:
        f.write(out.getvalue())
    print(f"Wrote {path}  ({os.path.getsize(path):,} bytes)")


if __name__ == "__main__":
    main()
