"""Wave 6.7 smoke — A+B applied to 4 master_bedrooms (WM/SL/Nordic/Tropical).

Verifies :
  A. master_bedroom × 4 ships new Wave 6.7 directive phrases (VISIBLY, PROMINENTLY)
  B. 2 lived-in objects present (book + framed photograph)
  C. Japandi UNTOUCHED (identity restraint locked)
  D. Living Room × 5 = no leak (architecture room-scoped)
  E. Kitchen/Dining/Bathroom/Terrace × 5 = no leak
  F. Atmosphere identity preserved + prompt budget OK
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


ATMO = {
    "WM": "Warm Modern · V2",
    "SL": "Soft Luxury · Gold",
    "Japandi": "Japandi · Calm",
    "Nordic": "Nordic Warmth · Dawn",
    "Tropical": "Tropical Escape · Bloom",
}


def compose(label, room):
    return compose_generation_prompt(
        style_label=label, room_type=room,
        room_description="A residential interior.", user_instruction="",
        iteration=1, history=[], secondary_visible_spaces=[],
        compact_prompts=False, generation_mode="preserve",
        edit_mode=EditMode.FIRST_VISION,
    )


# Wave 6.7 assertive vocab + lived-in items per atmosphere
WAVE_67_PHRASES = {
    "WM": [
        "VISIBLY relaxed warm linen and boucle bedding",
        "PROMINENTLY displayed warm-toned ceramic vase",
        "open book or magazine on the existing nightstand",
        "small framed photograph on the existing dresser",
        "natural moment, not hotel turndown",
    ],
    "SL": [
        "VISIBLY relaxed cream-to-ivory bedding",
        "PROMINENTLY displayed sculptural ceramic vase",
        "weighted velvet throw casually draped over the foot corner",
        "open book or magazine on the existing nightstand",
        "small framed photograph on the existing dresser",
    ],
    "Nordic": [
        "VISIBLY relaxed layered linen and wool bedding",
        "PROMINENTLY displayed amber glass candle holder",
        "open paperback on the existing nightstand",
        "small framed nature photograph on the existing dresser",
        "small ceramic mug on the existing nightstand",
    ],
    "Tropical": [
        "VISIBLY relaxed layered white and sage linen bedding",
        "PROMINENTLY displayed small tropical ceramic vase",
        "open book or magazine on the existing nightstand",
        "small framed photograph on the existing dresser",
    ],
}


# ── A. Wave 6.7 phrases ship in 4 bedrooms ───────────────────────────────
print("\n=== A. Wave 6.7 directive vocab + lived-in items shipped ===")
bedroom_prompts = {}
for short in ["WM", "SL", "Nordic", "Tropical"]:
    p = compose(ATMO[short], "Master Bedroom")
    bedroom_prompts[short] = p
    for phrase in WAVE_67_PHRASES[short]:
        check(f"A  {short:8} Master Bedroom contains : {phrase[:50]}...",
              phrase in p)


# ── B. Japandi UNTOUCHED ──────────────────────────────────────────────────
print("\n=== B. Japandi master_bedroom UNCHANGED (identity restraint locked) ===")
p_japandi = compose(ATMO["Japandi"], "Master Bedroom")
for v67 in ["VISIBLY", "PROMINENTLY", "open book", "open paperback", "framed photograph"]:
    check(f"B  Japandi Bedroom should NOT contain Wave 6.7 phrase '{v67}'",
          v67 not in p_japandi)
# Japandi keeps Wave 6.6 identity
check("B  Japandi Bedroom still has Wave 6.6 'quiet emotional grounding'",
      "quiet emotional grounding" in p_japandi)


# ── C. Living Rooms × 5 — no Wave 6.7 leak ───────────────────────────────
print("\n=== C. Living Rooms × 5 : zero Wave 6.7 leak ===")
all_67_phrases = set()
for phrases in WAVE_67_PHRASES.values():
    all_67_phrases.update(phrases)

for short in ATMO:
    p_living = compose(ATMO[short], "Living Room")
    leaks = [ph for ph in all_67_phrases if ph in p_living]
    check(f"C  {short:8} Living Room : 0 Wave 6.7 phrases leak  (len={len(p_living)})",
          not leaks,
          detail=f"leaks: {leaks}" if leaks else "")
    check(f"C  {short:8} Living Room still has TV anchor",
          "television on existing wall surface or media console" in p_living)


# ── D. Other rooms × 5 × 4 = 20 — no leak ────────────────────────────────
print("\n=== D. Kitchen/Dining/Bathroom/Terrace × 5 : zero Wave 6.7 leak ===")
for short in ATMO:
    for room in ["Kitchen", "Dining Room", "Bathroom", "Terrace"]:
        p = compose(ATMO[short], room)
        leaks = [ph for ph in all_67_phrases if ph in p]
        check(f"D  {short:8} {room:13} : 0 leak  (len={len(p)})",
              not leaks,
              detail=f"leaks: {leaks}" if leaks else "")


# ── E. Atmosphere identity preserved ─────────────────────────────────────
print("\n=== E. Atmosphere identity preserved in bedrooms ===")
identity = {
    "WM": ["oak", "linen", "travertine"],
    "SL": ["cashmere", "bouclé", "marble", "brass"],
    "Nordic": ["sheepskin", "amber glass", "pine"],
    "Tropical": ["rattan", "white render", "concrete"],
}
for short, words in identity.items():
    p = bedroom_prompts[short]
    found = sum(1 for w in words if w in p)
    check(f"E  {short:8} bedroom retains ≥2/3 identity anchors  ({found}/{len(words)})",
          found >= 2)


# ── F. Prompt budget < 4000 ──────────────────────────────────────────────
print("\n=== F. Prompt budget < 4000 ===")
for short in ["WM", "SL", "Nordic", "Tropical", "Japandi"]:
    p_len = len(bedroom_prompts[short]) if short in bedroom_prompts else len(p_japandi)
    check(f"F  {short:8} bedroom prompt {p_len:4d} chars < 4000",
          p_len < 4000)


# ── Summary ───────────────────────────────────────────────────────────────
passed = sum(1 for _, ok in results if ok)
total = len(results)
print(f"\n{'='*72}")
print(f"  TOTAL: {total}   PASSED: {passed}   FAILED: {total - passed}")
if passed != total:
    print("  FAILING CHECKS:")
    for l, ok in results:
        if not ok:
            print(f"    - {l}")
print(f"{'='*72}")

print("\nWave 6.7 bedroom prompt sizes :")
for short in ["WM", "SL", "Japandi", "Nordic", "Tropical"]:
    if short == "Japandi":
        print(f"  {short:8} Master Bedroom : {len(p_japandi):4d} chars (UNCHANGED)")
    else:
        print(f"  {short:8} Master Bedroom : {len(bedroom_prompts[short]):4d} chars")
