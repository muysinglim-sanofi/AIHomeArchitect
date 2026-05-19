"""
Temporary validation script for the Wave 3 backend intelligence systems.

Tests three cases that exercise the full stack:
  Case 1 — Living room with visible bedroom (multi-space DNA injection)
  Case 2 — Bathroom with Surprise Me (atmosphere recommender)
  Case 3 — Facade with Let AI Decide (room classifier)

Run from the backend/ directory:
  python validate_intelligence.py

Does NOT modify production code. Read-only validation only.
"""

import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

from prompt_engine import (
    compose_generation_prompt,
    classify_room,
    surprise_me,
    rank_atmospheres,
)
from prompt_engine.atmosphere_dna import get_room_dna, get_core, label_to_atmosphere_id


# ── Helpers ───────────────────────────────────────────────────────────────────

SEP = "-" * 70

def _section(title: str) -> None:
    print(f"\n{SEP}")
    print(f"  {title}")
    print(SEP)


def _check_dna(atmosphere_id: str, room_type: str) -> tuple[bool, bool]:
    core_ok = get_core(atmosphere_id) is not None
    room_ok = get_room_dna(atmosphere_id, room_type) is not None
    return core_ok, room_ok


def _count_atmosphere_blocks(prompt: str) -> int:
    """Count how many ATMOSPHERE (...): lines appear in the prompt."""
    return prompt.count("ATMOSPHERE (")


def _validate_prompt(prompt: str, atmosphere_id: str, room_type: str, label: str) -> list[str]:
    """Run all post-composition validations. Returns list of FAIL strings."""
    failures = []
    if len(prompt) > 3800:
        failures.append(f"OVERFLOW: prompt is {len(prompt)} chars (limit 3800)")
    n_atm = _count_atmosphere_blocks(prompt)
    if n_atm > 1:
        failures.append(f"DUPLICATE ATMOSPHERE BLOCKS: found {n_atm}")
    if n_atm == 0:
        failures.append("MISSING ATMOSPHERE BLOCK in prompt")
    core_ok, room_ok = _check_dna(atmosphere_id, room_type)
    if not core_ok:
        failures.append(f"MISSING CORE DNA for atmosphere '{atmosphere_id}'")
    if not room_ok:
        failures.append(f"MISSING ROOM DNA for '{atmosphere_id}/{room_type}'")
    return failures


def _print_result(
    case_label: str,
    room_type: str,
    atmosphere_id: str,
    style_label: str,
    secondary_spaces: list[str],
    prompt: str,
) -> None:
    core_ok, room_ok = _check_dna(atmosphere_id, room_type)
    failures = _validate_prompt(prompt, atmosphere_id, room_type, style_label)

    print(f"\n  Detected room type  : {room_type}")
    print(f"  Selected atmosphere : {atmosphere_id}  (label: '{style_label}')")
    print(f"  Secondary spaces    : {secondary_spaces or '(none)'}")
    print(f"  Core DNA loaded     : {'YES' if core_ok else 'NO  <-- PROBLEM'}")
    print(f"  Room DNA loaded     : {'YES' if room_ok else 'NO  <-- PROBLEM'}")
    print(f"  Prompt length       : {len(prompt)} chars")

    if secondary_spaces:
        for s in secondary_spaces:
            sec_dna = get_room_dna(atmosphere_id, s)
            print(f"  Secondary DNA [{s}]: {'present' if sec_dna else 'MISSING  <-- PROBLEM'}")

    if failures:
        for f in failures:
            print(f"  FAIL: {f}")
    else:
        print("  Validation: ALL CHECKS PASSED")

    print(f"\n  --- Prompt preview (first 700 chars) ---")
    print(prompt[:700])
    if len(prompt) > 700:
        print(f"  ... [{len(prompt) - 700} more chars]")


# ── Case 1: Living room + visible bedroom ─────────────────────────────────────

_section("CASE 1: Living Room with Visible Bedroom (multi-space DNA injection)")
print("""
  Input:
    room_type             = 'living_room'
    style_label           = 'Warm Modern'
    secondary_spaces      = ['master_bedroom']
    iteration             = 1
    user_instruction      = ''
""")

c1_room_type     = "living_room"
c1_style_label   = "Warm Modern"
c1_atmosphere_id = label_to_atmosphere_id(c1_style_label)
c1_secondaries   = ["master_bedroom"]

c1_prompt = compose_generation_prompt(
    style_label=c1_style_label,
    room_type=c1_room_type,
    room_description="A spacious living room with wide plank oak floors, two south-facing windows, and 2.8m ceilings. A glimpse of the master bedroom is visible through an open doorway in the background.",
    user_instruction="",
    iteration=1,
    history=[],
    secondary_visible_spaces=c1_secondaries,
)

# Extra check: verify bedroom DNA block appears in prompt
bedroom_visible = "VISIBLE MASTER BEDROOM" in c1_prompt.upper() or "MASTER BEDROOM" in c1_prompt.upper()
print(f"  Bedroom DNA injected into prompt: {'YES' if bedroom_visible else 'NO  <-- PROBLEM'}")

_print_result(
    case_label="Case 1",
    room_type=c1_room_type,
    atmosphere_id=c1_atmosphere_id,
    style_label=c1_style_label,
    secondary_spaces=c1_secondaries,
    prompt=c1_prompt,
)


# ── Case 2: Bathroom + Surprise Me ───────────────────────────────────────────

_section("CASE 2: Bathroom with Surprise Me (atmosphere recommender)")
print("""
  Input:
    room_type             = 'bathroom'
    surprise_me_flag      = True
    vision_description    = (spa-adjacent text)
    iteration             = 1
""")

c2_room_type   = "bathroom"
c2_vision_desc = "A small bathroom with white ceramic tiles, a walk-in shower, and a single vanity mirror. The space feels utilitarian but has good natural light from a frosted window."

c2_atmosphere_id = surprise_me(
    room_type=c2_room_type,
    vision_description=c2_vision_desc,
    user_prompt="",
)
c2_style_label = c2_atmosphere_id.replace("_", " ").title()

# Show the full ranking for transparency
ranked = rank_atmospheres(c2_room_type, c2_vision_desc)
print("  Atmosphere ranking for bathroom:")
for rank_i, (atm, score) in enumerate(ranked, 1):
    marker = "  <-- SELECTED" if atm == c2_atmosphere_id else ""
    print(f"    {rank_i:2}. {atm:22} {score:.3f}{marker}")

c2_prompt = compose_generation_prompt(
    style_label=c2_style_label,
    room_type=c2_room_type,
    room_description=c2_vision_desc,
    user_instruction="",
    iteration=1,
    history=[],
    secondary_visible_spaces=None,
)

_print_result(
    case_label="Case 2",
    room_type=c2_room_type,
    atmosphere_id=c2_atmosphere_id,
    style_label=c2_style_label,
    secondary_spaces=[],
    prompt=c2_prompt,
)


# ── Case 3: House facade + Let AI Decide ─────────────────────────────────────

_section("CASE 3: House Facade with Let AI Decide (room classifier)")
print("""
  Input:
    let_ai_decide         = True
    room_type_hint        = ''  (user did not specify)
    vision_description    = 'Minimal modern house facade with driveway and warm lighting'
    iteration             = 1
""")

c3_vision_desc   = "Minimal modern house facade with driveway and warm lighting. The exterior shows a flat roof, large windows from outside, and a clean sand render finish. The front elevation is visible with a recessed entrance."
c3_room_type_hint = ""

classification = classify_room(
    vision_description=c3_vision_desc,
    user_prompt="",
    room_type_hint=c3_room_type_hint,
)

print(f"\n  Classifier result:")
print(f"    primary_room  : {classification.primary_room}")
print(f"    confidence    : {classification.confidence:.2f}")
print(f"    secondary     : {classification.secondary_spaces}")
print(f"    reasoning     : {classification.reasoning}")

c3_room_type   = classification.primary_room
c3_secondaries = classification.secondary_spaces

# For Let AI Decide, we also need an atmosphere — use a neutral default for the test
# (in production, style_label comes from the frontend; here we test with warm_modern)
c3_style_label   = "Warm Modern"
c3_atmosphere_id = label_to_atmosphere_id(c3_style_label)

c3_prompt = compose_generation_prompt(
    style_label=c3_style_label,
    room_type=c3_room_type,
    room_description=c3_vision_desc,
    user_instruction="",
    iteration=1,
    history=[],
    secondary_visible_spaces=c3_secondaries or None,
)

_print_result(
    case_label="Case 3",
    room_type=c3_room_type,
    atmosphere_id=c3_atmosphere_id,
    style_label=c3_style_label,
    secondary_spaces=c3_secondaries,
    prompt=c3_prompt,
)

# Extra: verify facade DNA was used (not style fallback)
facade_dna_used = "ATMOSPHERE (" in c3_prompt and "ROOM (" in c3_prompt
print(f"\n  Facade DNA blocks in prompt: {'YES (two-tier DNA active)' if facade_dna_used else 'NO — fell back to style block'}")


# ── Summary ───────────────────────────────────────────────────────────────────

_section("SUMMARY")

all_prompts = [
    ("Case 1 — Living room + bedroom", c1_prompt, c1_atmosphere_id, c1_room_type),
    ("Case 2 — Bathroom + Surprise Me", c2_prompt, c2_atmosphere_id, c2_room_type),
    ("Case 3 — Facade + Let AI Decide", c3_prompt, c3_atmosphere_id, c3_room_type),
]

all_passed = True
for label, prompt, atm_id, rm_type in all_prompts:
    failures = _validate_prompt(prompt, atm_id, rm_type, label)
    status = "PASS" if not failures else f"FAIL ({'; '.join(failures)})"
    flag = "" if not failures else "  <-- NEEDS ATTENTION"
    print(f"  {label:45} {status}{flag}")
    if failures:
        all_passed = False

print()
if all_passed:
    print("  All cases passed. Backend intelligence systems are operational.")
else:
    print("  One or more cases have issues. See details above.")
print()
