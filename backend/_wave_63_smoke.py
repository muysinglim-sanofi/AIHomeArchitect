"""Wave 6.3 smoke — TEMPORAL CONTINUITY rule + BIMODAL strips for SL/Tropical/Nordic.

Verifies :
  1. Preserve mode FV with no user_instruction → sentence PRESENT
  2. Preserve mode FV with temporal-override keyword → sentence ABSENT
  3. Creative mode → sentence ABSENT (uses CREATIVE contract)
  4. BIMODAL strips applied on SL/Tropical/Nordic preserve prompts
  5. WM (no evening pressure) → no temporal strips affect it
  6. STYLE_REFINEMENT path → not affected (no MODE_CONTRACT)
"""
import sys, os, logging
sys.path.insert(0, os.path.dirname(__file__))
os.environ["BIMODAL_ENABLED"] = "1"
os.environ["APP_ENV"] = "mobile_mvp_baseline"
logging.disable(logging.CRITICAL)

from prompt_engine.composer import compose_generation_prompt
from prompt_engine.edit_intent import EditMode
from prompt_engine.preservation import (
    build_mode_contract,
    _temporal_override_requested,
    _TEMPORAL_CONTINUITY,
)

PASS = "\033[92mPASS\033[0m"
FAIL = "\033[91mFAIL\033[0m"

results = []
def check(label, cond, detail=""):
    s = PASS if cond else FAIL
    sfx = f"  [{detail}]" if detail and not cond else ""
    print(f"  {s}  {label}{sfx}")
    results.append((label, cond))


# ── A. Unit tests for the override regex ──────────────────────────────────
print("\n=== A. Temporal override regex ===")
check("A1  empty instruction → no override",
      not _temporal_override_requested(""))
check("A2  'add a sofa' → no override",
      not _temporal_override_requested("add a sofa"))
check("A3  'make it evening' → override",
      _temporal_override_requested("make it evening"))
check("A4  'cinematic night' → override",
      _temporal_override_requested("cinematic night"))
check("A5  'golden hour' → override",
      _temporal_override_requested("can we try golden hour please"))
check("A6  'moody lighting' → override",
      _temporal_override_requested("more moody lighting"))
check("A7  'morningstar' NOT triggering (word boundary)",
      not _temporal_override_requested("add a morningstar painting"))
check("A8  case-insensitive 'EVENING'",
      _temporal_override_requested("MAKE IT EVENING"))
check("A9  'sunrise mood'",
      _temporal_override_requested("sunrise mood please"))
check("A10 'daylight'",
      _temporal_override_requested("daylight version"))


# ── B. build_mode_contract behavior ──────────────────────────────────────
print("\n=== B. build_mode_contract ===")
mc_preserve = build_mode_contract("preserve", "")
mc_creative = build_mode_contract("creative", "")
mc_override = build_mode_contract("preserve", "make it cinematic night")
mc_normal_user = build_mode_contract("preserve", "add a wool rug")

check("B1  preserve + no override → TEMPORAL CONTINUITY present",
      "TEMPORAL CONTINUITY" in mc_preserve)
check("B2  creative mode → no TEMPORAL CONTINUITY",
      "TEMPORAL CONTINUITY" not in mc_creative)
check("B3  preserve + 'cinematic night' override → no TEMPORAL CONTINUITY",
      "TEMPORAL CONTINUITY" not in mc_override)
check("B4  preserve + benign instruction → TEMPORAL CONTINUITY present",
      "TEMPORAL CONTINUITY" in mc_normal_user)
check("B5  preserve sentence wording matches locked text",
      _TEMPORAL_CONTINUITY in mc_preserve)


# ── C. Composer integration FV+preserve → sentence in prompt ──────────────
print("\n=== C. Composer FV preserve includes TEMPORAL CONTINUITY ===")
for atmo_label, atmo_id in [("Warm Modern · V2", "warm_modern"),
                             ("Soft Luxury · Gold", "soft_luxury"),
                             ("Tropical Escape · Bloom", "tropical_escape"),
                             ("Nordic Warmth · Dawn", "nordic_warmth"),
                             ("Japandi · Calm", "japandi_calm"),
                             ("Nature Retreat · Forest", "nature_retreat")]:
    p = compose_generation_prompt(
        style_label=atmo_label, room_type="Living Room",
        room_description="A residential interior.", user_instruction="",
        iteration=1, history=[], secondary_visible_spaces=[],
        compact_prompts=False, generation_mode="preserve",
        edit_mode=EditMode.FIRST_VISION,
    )
    check(f"C  {atmo_id:18}  FV+preserve  → TEMPORAL CONTINUITY shipped",
          "TEMPORAL CONTINUITY" in p)


# ── D. Composer FV+preserve with override → sentence absent ───────────────
print("\n=== D. User override suppresses the sentence ===")
p_override = compose_generation_prompt(
    style_label="Soft Luxury · Gold", room_type="Living Room",
    room_description="A residential interior.",
    user_instruction="make it cinematic evening",
    iteration=1, history=[], secondary_visible_spaces=[],
    compact_prompts=False, generation_mode="preserve",
    edit_mode=EditMode.FIRST_VISION,
)
check("D1  override 'cinematic evening' → TEMPORAL CONTINUITY absent",
      "TEMPORAL CONTINUITY" not in p_override)


# ── E. BIMODAL strips applied ────────────────────────────────────────────
print("\n=== E. BIMODAL temporal strips applied (preserve) ===")
# Soft Luxury Living should NOT contain "warm evening tone" anymore
p_sl_living = compose_generation_prompt(
    style_label="Soft Luxury · Gold", room_type="Living Room",
    room_description="A residential interior.", user_instruction="",
    iteration=1, history=[], secondary_visible_spaces=[],
    compact_prompts=False, generation_mode="preserve",
    edit_mode=EditMode.FIRST_VISION,
)
check("E1  SL Living preserve  → 'warm evening tone' stripped",
      "warm evening tone" not in p_sl_living)
check("E2  SL Living preserve  → 'warm tone' present (replacement)",
      "warm tone" in p_sl_living)

p_sl_dining = compose_generation_prompt(
    style_label="Soft Luxury · Gold", room_type="Dining Room",
    room_description="A residential interior.", user_instruction="",
    iteration=1, history=[], secondary_visible_spaces=[],
    compact_prompts=False, generation_mode="preserve",
    edit_mode=EditMode.FIRST_VISION,
)
check("E3  SL Dining preserve  → 'warm evening dimmed' stripped",
      "warm evening dimmed" not in p_sl_dining)
check("E4  SL Dining preserve  → 'warm dimmed' present (replacement)",
      "warm dimmed" in p_sl_dining)

p_sl_balcony = compose_generation_prompt(
    style_label="Soft Luxury · Gold", room_type="Balcony",
    room_description="A residential interior.", user_instruction="",
    iteration=1, history=[], secondary_visible_spaces=[],
    compact_prompts=False, generation_mode="preserve",
    edit_mode=EditMode.FIRST_VISION,
)
check("E5  SL Balcony preserve → 'warm intimate tone' stripped",
      "warm intimate tone" not in p_sl_balcony)
check("E6  SL Balcony preserve → 'warm refined tone' present (replacement)",
      "warm refined tone" in p_sl_balcony)

# Tropical
p_trop_terrace = compose_generation_prompt(
    style_label="Tropical Escape · Bloom", room_type="Terrace",
    room_description="A residential interior.", user_instruction="",
    iteration=1, history=[], secondary_visible_spaces=[],
    compact_prompts=False, generation_mode="preserve",
    edit_mode=EditMode.FIRST_VISION,
)
check("E7  Tropical Terrace preserve → 'tropical evening' (standalone) stripped",
      "tropical evening" not in p_trop_terrace)

p_trop_balcony = compose_generation_prompt(
    style_label="Tropical Escape · Bloom", room_type="Balcony",
    room_description="A residential interior.", user_instruction="",
    iteration=1, history=[], secondary_visible_spaces=[],
    compact_prompts=False, generation_mode="preserve",
    edit_mode=EditMode.FIRST_VISION,
)
check("E8  Tropical Balcony preserve → 'tropical evening ambience' stripped",
      "tropical evening ambience" not in p_trop_balcony)

p_trop_garden = compose_generation_prompt(
    style_label="Tropical Escape · Bloom", room_type="Garden",
    room_description="A residential interior.", user_instruction="",
    iteration=1, history=[], secondary_visible_spaces=[],
    compact_prompts=False, generation_mode="preserve",
    edit_mode=EditMode.FIRST_VISION,
)
check("E9  Tropical Garden preserve → 'tropical evening garden' stripped",
      "tropical evening garden" not in p_trop_garden)

# Nordic
p_nordic_dining = compose_generation_prompt(
    style_label="Nordic Warmth · Dawn", room_type="Dining Room",
    room_description="A residential interior.", user_instruction="",
    iteration=1, history=[], secondary_visible_spaces=[],
    compact_prompts=False, generation_mode="preserve",
    edit_mode=EditMode.FIRST_VISION,
)
check("E10 Nordic Dining preserve → 'warm evening ambience' stripped",
      "warm evening ambience" not in p_nordic_dining)


# ── F. Strips inactive in creative mode (no-op confirmation) ──────────────
print("\n=== F. Strips inactive in creative mode ===")
p_sl_living_creative = compose_generation_prompt(
    style_label="Soft Luxury · Gold", room_type="Living Room",
    room_description="A residential interior.", user_instruction="",
    iteration=1, history=[], secondary_visible_spaces=[],
    compact_prompts=False, generation_mode="creative",
    edit_mode=EditMode.FIRST_VISION,
)
check("F1  SL Living creative → 'warm evening tone' PRESENT (strips off)",
      "warm evening tone" in p_sl_living_creative)


# ── G. STYLE_REFINEMENT path unaffected (no MODE_CONTRACT) ─────────────────
print("\n=== G. STYLE_REFINEMENT unaffected ===")
p_sr = compose_generation_prompt(
    style_label="Warm Modern · V2", room_type="Living Room",
    room_description="A residential interior.",
    user_instruction="make it warmer",
    iteration=2, history=[], secondary_visible_spaces=[],
    compact_prompts=False, generation_mode="preserve",
    edit_mode=EditMode.STYLE_REFINEMENT,
)
check("G1  STYLE_REFINEMENT → TEMPORAL CONTINUITY absent (FV-only rule)",
      "TEMPORAL CONTINUITY" not in p_sr)


# ── Summary ───────────────────────────────────────────────────────────────
passed = sum(1 for _, ok in results if ok)
total = len(results)
print(f"\n{'='*60}")
print(f"  TOTAL: {total}   PASSED: {passed}   FAILED: {total - passed}")
if passed != total:
    print("  FAILING CHECKS:")
    for l, ok in results:
        if not ok:
            print(f"    - {l}")
print(f"{'='*60}")
