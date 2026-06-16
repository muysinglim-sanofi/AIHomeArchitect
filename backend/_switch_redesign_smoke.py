"""SWITCH_REDESIGN_PILOT smoke — proves switch-only behavior + V1 freeze."""
from prompt_engine.preservation import build_atmosphere_switch_contract
from prompt_engine.switch_redesign import build_switch_hero_block
from prompt_engine.composer import compose_generation_prompt
from prompt_engine.edit_intent import EditMode

_fail = 0
def check(label, cond):
    global _fail
    print(f"  {'PASS' if cond else 'FAIL'} {label}")
    if not cond:
        _fail += 1

# ── Contract (R1) ─────────────────────────────────────────────────────────────
print("[1] switch contract redesign flag")
base = build_atmosphere_switch_contract("Living Room", "", redesign=False)
redes = build_atmosphere_switch_contract("Living Room", "", redesign=True)
check("baseline unchanged (CHANGE ONLY materials)", "CHANGE ONLY: materials" in base)
check("baseline has NO redesign wording", "REDESIGN THE FURNISHING" not in base)
check("redesign replaces furniture in place", "REDESIGN THE FURNISHING" in redes and "KEEP LAYOUT" in redes)
check("redesign still locks architecture", "walls, windows, doors" in redes)

# ── Hero signatures (R3) ──────────────────────────────────────────────────────
print("[2] hero signatures")
for atm in ("warm_modern", "japandi_calm", "soft_luxury", "nordic_warmth", "tropical_escape"):
    check(f"{atm} hero non-empty", "HERO FURNISHING" in build_switch_hero_block(atm))
check("unknown atmosphere -> empty", build_switch_hero_block("nope") == "")
check("warm_modern != japandi (distinct)", build_switch_hero_block("warm_modern") != build_switch_hero_block("japandi_calm"))

# ── compose: STYLE_REFINEMENT (switch path) ───────────────────────────────────
print("[3] compose STYLE_REFINEMENT switch_redesign flag")
common = dict(
    style_label="Warm Modern", room_type="Living Room",
    room_description="a living room with a sofa on the left and a window on the right",
    user_instruction="", iteration=2, history=[],
    edit_mode=EditMode.STYLE_REFINEMENT,
)
sr_off = compose_generation_prompt(**common, switch_redesign=False)
sr_on = compose_generation_prompt(**common, switch_redesign=True)
check("flag OFF: no pilot content", "REDESIGN THE FURNISHING" not in sr_off and "HERO FURNISHING" not in sr_off)
check("flag ON: redesign contract injected", "REDESIGN THE FURNISHING" in sr_on)
check("flag ON: hero signatures injected", "HERO FURNISHING" in sr_on)

# ── V1 FREEZE: FIRST_VISION must be byte-identical regardless of the flag ──────
print("[4] V1 freeze (FIRST_VISION byte-identical)")
v1_common = dict(
    style_label="Warm Modern", room_type="Living Room",
    room_description="a living room", user_instruction="", iteration=1, history=[],
    edit_mode=EditMode.FIRST_VISION,
)
v1_off = compose_generation_prompt(**v1_common, switch_redesign=False)
v1_on = compose_generation_prompt(**v1_common, switch_redesign=True)
check("FIRST_VISION identical with flag on/off (V1 untouched)", v1_off == v1_on)
check("V1 has NO pilot content", "HERO FURNISHING" not in v1_off and "REDESIGN THE FURNISHING" not in v1_off)

print()
print("ALL PASS" if _fail == 0 else f"{_fail} FAILED")
raise SystemExit(1 if _fail else 0)
