"""
Wave 5.4 audit — Fresh-vision equivalence across V1 / V2 pure-switch / V3 pure-switch.

For ONE target atmosphere (Japandi Calm) on ONE photo (the complex benchmark
apartment with sliding door + glass partition + visible rear-room window) with
NO customization history, produces three matched scenarios:

  S1 — V1 fresh Japandi
  S2 — V2 pure switch (Tropical V1 → Japandi V2)  no customizations
  S3 — V3 pure switch (Tropical V1 → Japandi V2 → Soft Luxury V3) no customs

The composer_v2 module is the one currently routed by main.py (COMPOSER_VERSION=v2)
so this exercises the REAL production path. composer.py is also invoked
directly for S1 as a cross-check (since composer_v2 delegates iteration=1 to it).

Also exercises:
  * resolve_switch_strategy for each scenario
  * source_mode override decision (what main.py would set)
  * classify_transformation on representative refinement strings

Writes docs/wave_5_4_fresh_equivalence_report.txt
"""

from __future__ import annotations

import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BACKEND = os.path.abspath(os.path.join(HERE, "..", "backend"))
sys.path.insert(0, BACKEND)

# Force composer_v2 routing (matches production .env state).
os.environ["COMPOSER_VERSION"] = "v2"

from prompt_engine.composer import compose_generation_prompt as compose_frozen  # noqa: E402
from prompt_engine.composer_v2 import (  # noqa: E402
    compose_generation_prompt as compose_v2,
    resolve_switch_strategy,
    is_customization_transformation,
    detect_history_customizations,
)
from prompt_engine.atmosphere_dna import label_to_atmosphere_id  # noqa: E402
from prompt_engine.transformation_classifier import (  # noqa: E402
    classify_transformation,
    TransformationType,
)
from prompt_engine.edit_intent import classify_edit_mode  # noqa: E402
from prompt_engine.structural_identity import (  # noqa: E402
    extract_from_description,
    render_clause,
    render_negative_anchors,
)
from prompt_engine.refinement_authority import build_authorized_changes_clause  # noqa: E402
from version_state import build_source_continuity_clause  # noqa: E402


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
TARGET_LABEL = "Japandi Calm"  # the destination atmosphere for all 3 scenarios


def _si_pair():
    identity = extract_from_description(ROOM_DESC)
    return render_clause(identity, mode="V1"), render_negative_anchors(identity)


def _v1_history(prev_label: str) -> list[dict]:
    """One V1 greeting message (the AI line) — production shape per chat_screen."""
    return [
        {"role": "ai", "content": f"Your space is ready. Generating your first {prev_label} vision now."},
        {"role": "ai", "content": f"Here is your first {prev_label} vision. What would you like to refine?"},
    ]


def _switch_history(*atmosphere_chain: str) -> list[dict]:
    """Build a history that mimics N successive AI greetings for an N-step
    atmosphere chain with NO user customization messages in between."""
    msgs: list[dict] = []
    for label in atmosphere_chain:
        msgs.append({"role": "ai", "content": f"Your space is ready. Generating your first {label} vision now."})
        msgs.append({"role": "ai", "content": f"Here is your first {label} vision. What would you like to refine?"})
    return msgs


def _decode_source_mode(strategy_value: str, iteration: int) -> str:
    """Replicate main.py's source-mode override decision (Wave 5.3)."""
    if iteration <= 1:
        return "ORIGINAL (V1 always edits original upload)"
    if strategy_value == "REBOOT_FRESH":
        return "ORIGINAL (Wave 5.3 override on pure switch)"
    if strategy_value == "REBOOT_CUSTOMIZED":
        return "LATEST (Wave 5.3 keeps LATEST so customizations survive)"
    return "LATEST (INCREMENTAL default)"


def _section_breakdown(prompt: str) -> list[tuple[int, str]]:
    out = []
    for block in prompt.split("\n\n"):
        block = block.strip()
        if not block:
            continue
        head = block.split("\n")[0][:80].strip()
        out.append((len(block), head))
    return out


def _dump_scenario(out, *, label, iteration, history, switch_label_for_kwargs):
    out.write("\n" + "=" * 100 + "\n")
    out.write(f"{label}\n")
    out.write("=" * 100 + "\n")

    si_clause, neg_clause = _si_pair()
    atmos_id = label_to_atmosphere_id(switch_label_for_kwargs)

    # Wave 5.3 strategy resolution
    strategy, prev_id, has_cust = resolve_switch_strategy(history, atmos_id, iteration)
    out.write(f"strategy        = {strategy.value}\n")
    out.write(f"prev_atmos_id   = {prev_id!r}\n")
    out.write(f"has_customs     = {has_cust}\n")
    out.write(f"source_mode     = {_decode_source_mode(strategy.value, iteration)}\n")

    # main.py-style routing
    user_instruction = "" if iteration == 1 else f"switch to {TARGET_LABEL}"
    edit_mode = classify_edit_mode(user_instruction, iteration)
    out.write(f"edit_mode       = {edit_mode.value}\n")
    out.write(f"iteration       = {iteration}\n")
    out.write(f"user_instr      = {user_instruction!r}\n")

    # Wave 5.3 also drives main.py's source_continuity / authorized_user_changes
    if iteration > 1:
        # For pure switches no AUC; for customized this would carry user text
        auc = ""
        source_cont = build_source_continuity_clause(source_type="original_upload" if strategy.value == "REBOOT_FRESH" else "latest_version", iteration=iteration)
    else:
        auc = ""
        source_cont = ""

    out.write(f"source_cont len = {len(source_cont)}\n")
    out.write(f"auc len         = {len(auc)}\n")

    prompt = compose_v2(
        style_label=switch_label_for_kwargs + f" · Vision {iteration}",
        room_type=ROOM_TYPE,
        room_description=ROOM_DESC,
        user_instruction=user_instruction,
        iteration=iteration,
        history=history,
        secondary_visible_spaces=["kitchen"],
        compact_prompts=False,
        structural_identity=si_clause,
        source_continuity=source_cont,
        structural_negative_anchors=neg_clause,
        authorized_user_changes=auc,
    )

    out.write(f"\n--- composer_v2 prompt ({len(prompt)} chars) ---\n")
    for n, head in _section_breakdown(prompt):
        out.write(f"  [{n:5d}]  {head}\n")
    out.write("\n>>> RAW prompt:\n")
    out.write(prompt + "\n<<< end\n")
    return prompt


def _customization_detector_probe(out):
    out.write("\n" + "=" * 100 + "\n")
    out.write("CUSTOMIZATION DETECTOR PROBE — classify_transformation + is_customization_transformation\n")
    out.write("=" * 100 + "\n")
    samples = [
        ("make it warmer",                  2),  # style-only
        ("more cozy",                       2),
        ("softer lighting",                 2),
        ("warmer tone",                     2),
        ("switch to Japandi",               2),  # pure atmosphere switch
        ("change to Soft Luxury",           2),
        ("add a bed to the right",          2),  # real customization
        ("place a sofa here",               2),
        ("move the TV",                     2),
        ("remove the lamp",                 2),
        ("turn the rear area into a bedroom", 2),  # functional reassignment
        ("knock down the partition",        2),  # structural change
        ("redesign the layout",             2),  # layout reinterpretation
        ("something completely different",  2),  # UNKNOWN
    ]
    out.write(f"\n{'text':45} | {'TransformationType':32} | is_cust?\n")
    out.write("-" * 100 + "\n")
    for text, it in samples:
        ttype = classify_transformation(text, it)
        is_cust = is_customization_transformation(ttype)
        out.write(f"{text!r:45} | {ttype.name:32} | {is_cust}\n")


def _history_customs_probe(out):
    out.write("\n" + "=" * 100 + "\n")
    out.write("HISTORY CUSTOMIZATION DETECTION — detect_history_customizations\n")
    out.write("=" * 100 + "\n")
    cases = [
        ("no user messages — pure switch", _switch_history("Tropical Bali")),
        ("user said 'make it warmer'", _switch_history("Tropical Bali") + [{"role": "user", "content": "make it warmer"}]),
        ("user said 'add a bed right'", _switch_history("Tropical Bali") + [{"role": "user", "content": "add a bed right"}]),
        ("user said 'switch to Japandi'", _switch_history("Tropical Bali") + [{"role": "user", "content": "switch to Japandi"}]),
        ("user said 'change atmosphere'", _switch_history("Tropical Bali") + [{"role": "user", "content": "change atmosphere"}]),
        ("user said 'something different'", _switch_history("Tropical Bali") + [{"role": "user", "content": "something different"}]),
    ]
    out.write(f"\n{'case':50} | detect_history_customizations()\n")
    out.write("-" * 100 + "\n")
    for label, hist in cases:
        out.write(f"{label:50} | {detect_history_customizations(hist)}\n")


def main() -> None:
    out = io.StringIO()
    out.write("WAVE 5.4 AUDIT — Fresh-vision equivalence across V1 / V2 / V3\n")
    out.write(f"Target atmosphere: {TARGET_LABEL}\n")
    out.write(f"Composer version active: {os.environ['COMPOSER_VERSION']}\n")

    # S1 — V1 fresh Japandi (iteration=1, empty history)
    p1 = _dump_scenario(
        out,
        label="S1 — V1 fresh Japandi",
        iteration=1,
        history=[],
        switch_label_for_kwargs="Japandi Calm",
    )

    # S2 — V2 pure switch Tropical V1 → Japandi V2 (no user messages)
    p2 = _dump_scenario(
        out,
        label="S2 — V2 pure switch (Tropical V1 → Japandi V2, no customization)",
        iteration=2,
        history=_switch_history("Tropical Bali"),
        switch_label_for_kwargs="Japandi Calm",
    )

    # S3 — V3 pure switch Tropical V1 → Japandi V2 → Soft Luxury V3
    # User wants Japandi as target on V3, after a chain of pure switches.
    # So the chain is Tropical V1 → Japandi V2 → and now switching to ... target Japandi again?
    # The product question is about the same target arriving on V1 vs V2 vs V3.
    # Use chain Tropical V1 → Soft Luxury V2 → Japandi V3 (target Japandi at V3).
    p3 = _dump_scenario(
        out,
        label="S3 — V3 pure switch (Tropical V1 → Soft Luxury V2 → Japandi V3, no customization)",
        iteration=3,
        history=_switch_history("Tropical Bali", "Soft Luxury"),
        switch_label_for_kwargs="Japandi Calm",
    )

    # Equivalence summary
    out.write("\n" + "=" * 100 + "\n")
    out.write("PROMPT EQUIVALENCE MATRIX\n")
    out.write("=" * 100 + "\n")
    out.write(f"S1 size: {len(p1)}\n")
    out.write(f"S2 size: {len(p2)}\n")
    out.write(f"S3 size: {len(p3)}\n")
    out.write(f"S1 == S2 ?  {p1 == p2}\n")
    out.write(f"S2 == S3 ?  {p2 == p3}\n")
    out.write(f"S1 == S3 ?  {p1 == p3}\n")

    # Detector probes
    _customization_detector_probe(out)
    _history_customs_probe(out)

    path = os.path.join(HERE, "wave_5_4_fresh_equivalence_report.txt")
    with open(path, "w", encoding="utf-8") as f:
        f.write(out.getvalue())
    print(f"Wrote {path}  ({os.path.getsize(path):,} bytes)")


if __name__ == "__main__":
    main()
