"""Wave 5.5.6 full verification — 5 atmospheres × 3 cases byte-identity check."""
import logging
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.abspath(os.path.join(HERE, "..", "backend")))

# Capture log output to verify the delegation log fires
log_buf = io.StringIO()
log_handler = logging.StreamHandler(log_buf)
log_handler.setFormatter(logging.Formatter("%(message)s"))
logging.getLogger("aih").addHandler(log_handler)
logging.getLogger("aih").setLevel(logging.INFO)

from prompt_engine.composer_v2 import compose_generation_prompt as compose_v2
from prompt_engine.composer import compose_generation_prompt as compose_py
from prompt_engine.structural_identity import (
    extract_from_description, render_clause, render_negative_anchors,
)

ROOM_DESC = (
    "Living room with a large floor-to-ceiling sliding glass door on the "
    "left wall opening to a balcony with vertical louvered shutters visible. "
    "Eye-level single-point perspective, medium spatial depth. Black-framed "
    "glass partition on the right separating the living zone from a rear "
    "room visible through the partition; a window is visible on the rear "
    "wall of the back room. Standard ceiling height. Herringbone wood floor "
    "throughout. Open kitchen visible on the right beyond the partition."
)
identity = extract_from_description(ROOM_DESC)
si = render_clause(identity, mode="V1")
neg = render_negative_anchors(identity)


def make_v1_history(label):
    return [
        {"role": "ai", "content": f"Your space is ready. Generating your first {label} vision now."},
        {"role": "ai", "content": f"Here's your {label} transformation — Vision 1."},
    ]


def make_chain_history(label_v1, label_v2):
    return make_v1_history(label_v1) + [
        {"role": "user", "content": f"Redesign this space in the {label_v2} style."},
        {"role": "ai", "content": "Vision 2 — applied your direction."},
    ]


def call(atm_label, iteration, history, user_instruction, via):
    fn = compose_v2 if via == "v2" else compose_py
    return fn(
        style_label=f"{atm_label} · Vision {iteration}",
        room_type="Living Room",
        room_description=ROOM_DESC,
        user_instruction=user_instruction,
        iteration=iteration,
        history=history,
        secondary_visible_spaces=["kitchen"],
        compact_prompts=False,
        structural_identity=si,
        source_continuity="",
        structural_negative_anchors=neg,
        authorized_user_changes="",
    )


atms = ["Nordic Warmth", "Warm Modern", "Japandi Calm", "Bali Sanctuary", "Soft Luxury"]
log_buf.truncate(0); log_buf.seek(0)

print(f"{'atmosphere':18}  {'V1 ref':6}  {'V1 via v2':9}  {'V2 switch':9}  {'V3 chain':9}  V1ref=V1v2  V1ref=V2  V1ref=V3")
print("-" * 110)
all_pass = True
for atm in atms:
    other_v1 = "Tropical Escape" if atm != "Tropical Escape" else "Bali Sanctuary"
    other_v2 = "Desert Luxe" if atm != "Desert Luxe" else "Nordic Warmth"

    p_v1_ref = call(atm, 1, [], "", via="py")
    p_v1_v2 = call(atm, 1, [], "", via="v2")
    p_v2_switch = call(atm, 2, make_v1_history(other_v1),
                       f"Redesign this space in the {atm} style.", via="v2")
    p_v3_chain = call(atm, 3, make_chain_history("Dark Contemporary", other_v2),
                      f"Redesign this space in the {atm} style.", via="v2")

    eq_v1_v2 = (p_v1_v2 == p_v1_ref)
    eq_v2 = (p_v2_switch == p_v1_ref)
    eq_v3 = (p_v3_chain == p_v1_ref)
    ok = eq_v1_v2 and eq_v2 and eq_v3
    if not ok:
        all_pass = False

    mark = "✓" if ok else "✗"
    print(f"{atm:18}  {len(p_v1_ref):5d}  {len(p_v1_v2):7d}  {len(p_v2_switch):7d}  "
          f"{len(p_v3_chain):7d}  {str(eq_v1_v2):10}  {str(eq_v2):8}  {str(eq_v3):8}  {mark}")

print()
print(f"GATE 1 (V1=V2/V3 byte-identical on pure switches): "
      f"{'PASS — Wave 5.5.6 confirmed' if all_pass else 'FAIL'}")

# Inspect logs to confirm delegation fired
print()
print("=== Captured backend log lines ===")
log_content = log_buf.getvalue()
reboot_fresh_logs = [l for l in log_content.split("\n")
                     if "REBOOT_FRESH" in l and "delegating" in l]
v1_delegation_logs = [l for l in log_content.split("\n")
                      if "iteration=1" in l and "delegating V1" in l]
print(f"Wave 5.5.6 REBOOT_FRESH delegation log lines fired: {len(reboot_fresh_logs)}")
for line in reboot_fresh_logs[:3]:
    print(f"  {line}")
print(f"Wave 5.3.1 V1 (iteration=1) delegation log lines fired: {len(v1_delegation_logs)}")

# Counter-test: INCREMENTAL must NOT delegate
print()
print("=== Counter-test: INCREMENTAL must NOT delegate ===")
p_v2_incr = call("Warm Modern", 2, make_v1_history("Warm Modern"),
                 "make it warmer", via="v2")
p_v1_warm_ref = call("Warm Modern", 1, [], "", via="py")
print(f"V2 INCREMENTAL 'make it warmer' size: {len(p_v2_incr)} "
      f"(V1 ref: {len(p_v1_warm_ref)})")
print(f"  Different from V1 (good — composer_v2 5-section retained): "
      f"{p_v2_incr != p_v1_warm_ref}")
print(f"  Contains conservative '_STYLE_PREFIX' marker: "
      f"{'re-surface the photographed architecture' in p_v2_incr}")

# Counter-test: REBOOT_CUSTOMIZED must NOT delegate
print()
print("=== Counter-test: REBOOT_CUSTOMIZED must NOT delegate ===")
hist_custom = make_v1_history("Tropical Escape") + [
    {"role": "user", "content": "add a bed to the right"},
    {"role": "ai", "content": "Vision 2 — applied."},
]
p_v3_custom = call("Japandi Calm", 3, hist_custom,
                   "Redesign this space in the Japandi Calm style.", via="v2")
print(f"V3 REBOOT_CUSTOMIZED size: {len(p_v3_custom)}")
print(f"  Contains ATMOSPHERE SWITCH header (composer_v2 marker): "
      f"{'ATMOSPHERE SWITCH' in p_v3_custom}")
print(f"  Contains _STYLE_PREFIX_ATMOSPHERE_SWITCH: "
      f"{'Fully replace the previous vision' in p_v3_custom}")
