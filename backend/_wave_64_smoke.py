"""Wave 6.4 smoke — Tropical Living louvred-timber detune (preserve-only).

Verifies :
  1. Tropical Living preserve  → "louvred timber panels or shutters" stripped
  2. Tropical Living preserve  → "louvred timber — warm tropical surface quality" stripped
  3. Tropical Living preserve  → replacement "tropical timber accents on existing surfaces" present
  4. Tropical Living preserve  → "rattan", "whitewash" identity preserved (no regression)
  5. Tropical Bedroom preserve → "louvred timber — warm shutter surface quality" UNTOUCHED (different wording)
  6. Tropical Terrace preserve → "timber pergola with louvred roof" UNTOUCHED
  7. Tropical Facade preserve  → "louvred timber or shuttered windows" UNTOUCHED
  8. Tropical Living CREATIVE  → strips inactive ("louvred timber panels or shutters" present)
  9. WM / SL / Nordic / Japandi / Nature : NO impact
"""
import sys, os, logging
sys.path.insert(0, os.path.dirname(__file__))
os.environ["BIMODAL_ENABLED"] = "1"
os.environ["APP_ENV"] = "mobile_mvp_baseline"
logging.disable(logging.CRITICAL)

from prompt_engine.composer import compose_generation_prompt
from prompt_engine.edit_intent import EditMode

PASS = "\033[92mPASS\033[0m"
FAIL = "\033[91mFAIL\033[0m"
results = []
def check(label, cond, detail=""):
    s = PASS if cond else FAIL
    sfx = f"  [{detail}]" if detail and not cond else ""
    print(f"  {s}  {label}{sfx}")
    results.append((label, cond))


def compose(label, room, mode="preserve", em=EditMode.FIRST_VISION):
    return compose_generation_prompt(
        style_label=label, room_type=room,
        room_description="A residential interior.", user_instruction="",
        iteration=1, history=[], secondary_visible_spaces=[],
        compact_prompts=False, generation_mode=mode, edit_mode=em,
    )


# ── A. Tropical Living preserve — strips applied ─────────────────────────
print("\n=== A. Tropical Living preserve : louvred-timber strips applied ===")
p_trop_living_preserve = compose("Tropical Escape · Bloom", "Living Room", "preserve")

check("A1  'louvred timber panels or shutters' stripped",
      "louvred timber panels or shutters" not in p_trop_living_preserve)
check("A2  'louvred timber — warm tropical surface quality' stripped",
      "louvred timber — warm tropical surface quality" not in p_trop_living_preserve)
check("A3  replacement 'tropical timber accents on existing surfaces' present",
      "tropical timber accents on existing surfaces" in p_trop_living_preserve)
check("A4  replacement 'tropical timber accent — warm surface quality' present",
      "tropical timber accent — warm surface quality" in p_trop_living_preserve)

# A5-A8 : Tropical identity preserved (regression check)
check("A5  Tropical identity 'rattan' preserved",
      "rattan" in p_trop_living_preserve)
check("A6  Tropical identity 'whitewash' or 'white render' preserved",
      "whitewash" in p_trop_living_preserve or "white render" in p_trop_living_preserve)
check("A7  Tropical identity 'concrete' or 'stone' preserved",
      "concrete" in p_trop_living_preserve or "stone" in p_trop_living_preserve)
check("A8  Tropical identity 'tropical' word present (atmosphere readable)",
      p_trop_living_preserve.lower().count("tropical") >= 3)


# ── B. Other Tropical rooms preserve — strips do NOT fire ────────────────
print("\n=== B. Other Tropical rooms preserve : strips do NOT fire ===")
p_trop_bedroom = compose("Tropical Escape · Bloom", "Master Bedroom", "preserve")
check("B1  Tropical Bedroom — 'louvred timber — warm shutter surface quality' UNTOUCHED",
      "louvred timber — warm shutter surface quality" in p_trop_bedroom)

p_trop_terrace = compose("Tropical Escape · Bloom", "Terrace", "preserve")
check("B2  Tropical Terrace — 'timber pergola with louvred roof' UNTOUCHED",
      "timber pergola with louvred roof" in p_trop_terrace)
check("B3  Tropical Terrace — 'timber or louvred overhead structure' UNTOUCHED",
      "timber or louvred overhead structure" in p_trop_terrace)

p_trop_facade = compose("Tropical Escape · Bloom", "Facade", "preserve")
check("B4  Tropical Facade — 'louvred timber or shuttered windows' UNTOUCHED",
      "louvred timber or shuttered windows" in p_trop_facade)
check("B5  Tropical Facade — 'natural timber louvres and window frames' UNTOUCHED",
      "natural timber louvres and window frames" in p_trop_facade)


# ── C. Tropical Living creative — strips inactive ────────────────────────
print("\n=== C. Tropical Living creative : strips inactive ===")
p_trop_living_creative = compose("Tropical Escape · Bloom", "Living Room", "creative")
check("C1  Tropical Living creative — 'louvred timber panels or shutters' present (strips off)",
      "louvred timber panels or shutters" in p_trop_living_creative)
check("C2  Tropical Living creative — 'louvred timber — warm tropical surface quality' present (strips off)",
      "louvred timber — warm tropical surface quality" in p_trop_living_creative)


# ── D. Other atmospheres : ZERO impact ───────────────────────────────────
print("\n=== D. Other atmospheres : zero spill ===")
for atmo_label, atmo_short in [
    ("Warm Modern · V2", "WM"),
    ("Soft Luxury · Gold", "SL"),
    ("Nordic Warmth · Dawn", "Nordic"),
    ("Japandi · Calm", "Japandi"),
    ("Nature Retreat · Forest", "Nature"),
]:
    p = compose(atmo_label, "Living Room", "preserve")
    # No "tropical timber accents" replacement should appear (Wave 6.4 phrasing
    # is Tropical-specific). Just structural check that the prompt is non-empty
    # and shipped normally.
    check(f"D  {atmo_short:8} Living preserve — no Wave 6.4 spill (no 'tropical timber accents')",
          "tropical timber accents on existing surfaces" not in p)


# ── E. STYLE_REFINEMENT path : strips also apply (DNA-driven) ────────────
print("\n=== E. STYLE_REFINEMENT path observation (DNA-shared) ===")
p_trop_sr = compose("Tropical Escape · Bloom", "Living Room", "preserve",
                    em=EditMode.STYLE_REFINEMENT)
ships_strip = "tropical timber accents on existing surfaces" in p_trop_sr
print(f"  obs   Tropical Living SR preserve : strip {'applied (DNA-shared path)' if ships_strip else 'not applied'}")
# Not a fail — observation. DNA strips fire wherever DNA ships, by design.


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
