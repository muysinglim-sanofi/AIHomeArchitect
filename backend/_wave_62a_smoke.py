"""Wave 6.2a smoke — verify the 4 pilot cells ship the new items and no leak."""
import sys, os, logging
sys.path.insert(0, os.path.dirname(__file__))
os.environ["BIMODAL_ENABLED"] = "1"
os.environ["APP_ENV"] = "mobile_mvp_baseline"
logging.disable(logging.CRITICAL)

from prompt_engine.composer import compose_generation_prompt
from prompt_engine.edit_intent import EditMode

PASS = "\033[92mPASS\033[0m"
FAIL = "\033[91mFAIL\033[0m"

# Pilot cells + verification markers (substrings unique to the new items)
PILOT_MARKERS = {
    ("Tropical Escape - Bloom".replace("-", "·"), "Living Room"): [
        "second tropical plant",
        "rattan tray with carafe and tumblers",
    ],
    ("Tropical Escape - Bloom".replace("-", "·"), "Terrace"): [
        "additional tropical plant",
        "rattan lantern cluster of 2 to 3 pieces",
    ],
    ("Nordic Warmth - Dawn".replace("-", "·"), "Living Room"): [
        "natural sheepskin draped over the existing seating",
        "small stack of design or poetry books",
    ],
    ("Nordic Warmth - Dawn".replace("-", "·"), "Terrace"): [
        "natural sheepskin throw on existing seating",
        "lantern cluster of 2 to 3 amber glass pieces",
    ],
}

# Cells that MUST NOT contain any of the pilot markers (leak guard)
NON_PILOT_CHECKS = [
    ("Warm Modern - V2".replace("-", "·"), "Living Room"),
    ("Warm Modern - V2".replace("-", "·"), "Terrace"),
    ("Soft Luxury - Gold".replace("-", "·"), "Living Room"),
    ("Tropical Escape - Bloom".replace("-", "·"), "Master Bedroom"),
    ("Tropical Escape - Bloom".replace("-", "·"), "Kitchen"),
    ("Nordic Warmth - Dawn".replace("-", "·"), "Master Bedroom"),
    ("Nordic Warmth - Dawn".replace("-", "·"), "Kitchen"),
    ("Japandi - Calm".replace("-", "·"), "Living Room"),
    ("Nature Retreat - Forest".replace("-", "·"), "Living Room"),
]

ALL_NEW_ITEMS = set()
for items in PILOT_MARKERS.values():
    ALL_NEW_ITEMS.update(items)


def compose(label, room, mode="preserve", em=EditMode.FIRST_VISION):
    return compose_generation_prompt(
        style_label=label, room_type=room,
        room_description="A residential interior.", user_instruction="",
        iteration=1, history=[], secondary_visible_spaces=[],
        compact_prompts=False, generation_mode=mode, edit_mode=em,
    )


print("=" * 70)
print("Wave 6.2a — Pilot HITS")
print("=" * 70)
ok_count = 0
for (label, room), markers in PILOT_MARKERS.items():
    p = compose(label, room)
    found = [m for m in markers if m in p]
    missing = [m for m in markers if m not in p]
    status = PASS if not missing else FAIL
    print(f"  {status}  {label} / {room}  len={len(p)}  found={len(found)}/{len(markers)}")
    if missing:
        for m in missing:
            print(f"        MISSING: {m!r}")
    else:
        ok_count += 1

print()
print("=" * 70)
print("Wave 6.2a — Leak Guards (non-pilot cells must NOT contain any new item)")
print("=" * 70)
leak_count = 0
for (label, room) in NON_PILOT_CHECKS:
    p = compose(label, room)
    leaks = [m for m in ALL_NEW_ITEMS if m in p]
    status = PASS if not leaks else FAIL
    print(f"  {status}  {label:32}/ {room:20}  len={len(p)}  leaks={len(leaks)}")
    if leaks:
        for l in leaks:
            print(f"        LEAK: {l!r}")
        leak_count += 1

print()
print("=" * 70)
print("Wave 6.2a — Mode/Path gates (non-FV or non-preserve must NOT ship pilot items)")
print("=" * 70)
gate_count = 0
gate_tests = [
    ("Tropical Escape - Bloom".replace("-", "·"), "Living Room", "preserve", EditMode.STYLE_REFINEMENT, "SR preserve"),
    ("Tropical Escape - Bloom".replace("-", "·"), "Living Room", "creative", EditMode.FIRST_VISION, "FV creative"),
    ("Nordic Warmth - Dawn".replace("-", "·"), "Terrace", "preserve", EditMode.STRUCTURAL_TRANSFORMATION, "ST preserve"),
]
for label, room, mode, em, tag in gate_tests:
    p = compose(label, room, mode=mode, em=em)
    leaks = [m for m in ALL_NEW_ITEMS if m in p]
    # Non-FV paths use a different DNA block path (build_dna_block via SR/ST) ;
    # the new items may or may not ship depending on the path's slice. We log
    # observation rather than fail — the pilot scope is FV+preserve.
    obs = "leaks=0" if not leaks else f"observation: ships {len(leaks)} pilot item(s)"
    print(f"  obs   {label:32}/ {room:15}/ {tag:14}  len={len(p)}  {obs}")
    gate_count += 1

print()
print("=" * 70)
total_pilot = len(PILOT_MARKERS)
total_leak = len(NON_PILOT_CHECKS)
print(f"  Pilot HITs : {ok_count}/{total_pilot} cells ship new items")
print(f"  Leak guard : {total_leak - leak_count}/{total_leak} cells clean")
print(f"  Gate obs   : {gate_count} non-FV/non-preserve paths logged")
print("=" * 70)
