"""Wave 6.2 budget audit — per-cell current vs enriched prompt length."""
import sys, logging, os
sys.path.insert(0, os.path.dirname(__file__))
# Match production runtime (logs show BIMODAL_ENABLED=1 + mobile_mvp_baseline)
os.environ["BIMODAL_ENABLED"] = "1"
os.environ["APP_ENV"] = "mobile_mvp_baseline"
logging.disable(logging.CRITICAL)

from prompt_engine.composer import compose_generation_prompt
from prompt_engine.edit_intent import EditMode
from prompt_engine.atmosphere_dna import _base as base
from prompt_engine.atmosphere_dna._base import _ADAPTATION_REGISTRY

ATMOSPHERES = ["warm_modern", "soft_luxury", "japandi_calm", "nordic_warmth", "nature_retreat", "tropical_escape"]
ROOMS = ["living_room", "master_bedroom", "kitchen", "bathroom", "dining_room",
         "home_office", "entrance_hall", "terrace", "balcony",
         "facade", "garden", "pool_area", "driveway"]

ENRICH = {
    ("warm_modern", "living_room"): [],
    ("warm_modern", "master_bedroom"): ["matched warm-toned ceramic bedside lamps producing soft ambient bedside glow"],
    ("warm_modern", "kitchen"): ["warm ceramic bowl with seasonal fruit on the existing island", "small herb planter on the existing windowsill"],
    ("warm_modern", "bathroom"): ["rolled cotton towels in a small woven basket at the existing tub edge"],
    ("warm_modern", "dining_room"): ["warm linen runner on the existing table with travertine accents", "trio of brass pillar candle holders down the runner centre"],
    ("warm_modern", "home_office"): ["curated stack of design books on the existing desk corner", "single small framed architectural drawing on the existing wall"],
    ("warm_modern", "entrance_hall"): ["warm linen runner on the existing console with a brushed brass tray", "single brushed brass table lamp on the existing console"],
    ("warm_modern", "terrace"): ["lantern cluster of 2 to 3 ceramic or brass pieces on the existing table", "rolled warm linen throw on existing seating"],
    ("warm_modern", "balcony"): ["warm woven cushion on existing seating", "single ceramic candle holder on the existing side table"],
    ("warm_modern", "facade"): [],
    ("warm_modern", "garden"): [],
    ("warm_modern", "pool_area"): ["rolled warm linen pool towels folded on existing loungers"],
    ("warm_modern", "driveway"): [],
    ("soft_luxury", "living_room"): [],
    ("soft_luxury", "master_bedroom"): [],
    ("soft_luxury", "kitchen"): ["honed marble fruit bowl on the existing island", "brushed brass espresso ritual tray on the existing counter"],
    ("soft_luxury", "bathroom"): ["single sculptural alabaster candle on the existing vanity", "small white orchid in cream ceramic on the existing surface"],
    ("soft_luxury", "dining_room"): ["ivory linen runner on the existing table", "brushed brass candle holders along the runner centre"],
    ("soft_luxury", "home_office"): ["honed marble tray on the existing desk with a boucle pen pot", "single boucle cushion on the existing chair"],
    ("soft_luxury", "entrance_hall"): ["honed marble tray on the existing console"],
    ("soft_luxury", "terrace"): ["ivory linen throw on existing seating", "single sculptural lantern in honed stone base on the existing surface"],
    ("soft_luxury", "balcony"): ["rolled cashmere or boucle throw on existing chair", "single brass candle lantern on the existing side table"],
    ("soft_luxury", "facade"): [],
    ("soft_luxury", "garden"): [],
    ("soft_luxury", "pool_area"): ["rolled ivory pool towels folded on existing loungers", "single honed stone tray between loungers"],
    ("soft_luxury", "driveway"): [],
    ("nordic_warmth", "living_room"): ["natural sheepskin draped over the existing seating", "small stack of design or poetry books on the existing coffee table"],
    ("nordic_warmth", "master_bedroom"): ["natural sheepskin at one bedside on the existing floor", "amber glass candle holder on the existing nightstand"],
    ("nordic_warmth", "kitchen"): ["wood cutting board on the existing counter with a small bowl of fruit", "warm linen dish towel folded on the existing handle"],
    ("nordic_warmth", "bathroom"): ["amber glass candle holder on the existing vanity", "single small potted plant in a warm ceramic pot"],
    ("nordic_warmth", "dining_room"): ["stack of seasonal botanicals such as eucalyptus or dried wheat in a low ceramic vessel"],
    ("nordic_warmth", "home_office"): ["wool throw on the existing chair", "amber glass candle holder on the existing desk corner"],
    ("nordic_warmth", "entrance_hall"): ["woven basket at the foot of the existing console"],
    ("nordic_warmth", "terrace"): ["natural sheepskin throw on existing seating", "lantern cluster of 2 to 3 amber glass pieces on the existing table"],
    ("nordic_warmth", "balcony"): ["natural sheepskin draped on existing seating", "small potted lavender or rosemary on the existing surface"],
    ("nordic_warmth", "facade"): [],
    ("nordic_warmth", "garden"): [],
    ("nordic_warmth", "pool_area"): ["rolled wool or linen towels folded on existing loungers", "amber glass lantern on existing side surface"],
    ("nordic_warmth", "driveway"): [],
    ("nature_retreat", "living_room"): ["carved wood or driftwood object on the existing coffee table", "raw stone styling accents on the existing surfaces"],
    ("nature_retreat", "master_bedroom"): ["natural jute or sisal mat at the bedside on the existing floor", "small carved wood or natural stone object on the existing nightstand"],
    ("nature_retreat", "kitchen"): ["hand-thrown ceramic fruit bowl on the existing counter", "linen dish towel folded on the existing oven handle"],
    ("nature_retreat", "bathroom"): ["single matte stone or terracotta vessel on the existing vanity", "small succulent or air plant in a natural ceramic pot"],
    ("nature_retreat", "dining_room"): ["earth-toned handcrafted ceramics on the existing table"],
    ("nature_retreat", "home_office"): ["small carved wood or natural stone object on the existing desk corner"],
    ("nature_retreat", "entrance_hall"): ["single natural woven basket at the foot of the existing console", "carved wood object on the existing console"],
    ("nature_retreat", "terrace"): ["carved wood or stone candle holder cluster on the existing table", "weathered stone accent objects on the existing surfaces"],
    ("nature_retreat", "balcony"): ["small carved wood object or stone vessel on the existing side table"],
    ("nature_retreat", "facade"): [],
    ("nature_retreat", "garden"): [],
    ("nature_retreat", "pool_area"): ["rolled undyed linen towels folded on existing loungers", "single carved wood or stone object on existing side surface"],
    ("nature_retreat", "driveway"): [],
    ("tropical_escape", "living_room"): ["second tropical plant such as a palm or fern in a white ceramic pot on the existing floor adjacent to seating", "natural rattan tray with carafe and tumblers on the existing coffee table"],
    ("tropical_escape", "master_bedroom"): ["rattan or woven natural basket at the foot of the existing bed", "single small tropical plant in a white pot on the existing floor"],
    ("tropical_escape", "kitchen"): ["white ceramic bowl with seasonal tropical fruit on the existing counter", "small woven natural-fibre basket on the existing counter or shelf"],
    ("tropical_escape", "bathroom"): ["single small tropical plant in a white ceramic pot on the existing vanity", "natural woven basket with rolled towels at the existing tub edge"],
    ("tropical_escape", "dining_room"): ["single tropical centrepiece in a low white ceramic vessel on the existing table"],
    ("tropical_escape", "home_office"): ["rattan or natural-fibre throw on the existing chair", "small additional tropical plant on the existing shelf"],
    ("tropical_escape", "entrance_hall"): ["natural rattan tray on the existing console with simple white ceramic objects", "single small woven basket at the foot of the existing console"],
    ("tropical_escape", "terrace"): ["additional tropical plant in a concrete pot on the existing deck adjacent to seating", "rattan lantern cluster of 2 to 3 pieces on the existing table"],
    ("tropical_escape", "balcony"): ["natural rattan throw on existing seating", "small additional tropical plant in a white ceramic pot"],
    ("tropical_escape", "facade"): [],
    ("tropical_escape", "garden"): [],
    ("tropical_escape", "pool_area"): ["rolled white linen pool towels folded on existing loungers", "natural rattan tray on the existing side surface"],
    ("tropical_escape", "driveway"): [],
}
for r in ROOMS:
    ENRICH[("japandi_calm", r)] = []

room_desc = "A residential interior."
label_map = {
    "warm_modern":     "Warm Modern · V2",
    "soft_luxury":     "Soft Luxury · Gold",
    "japandi_calm":    "Japandi · Calm",
    "nordic_warmth":   "Nordic Warmth · Dawn",
    "nature_retreat":  "Nature Retreat · Forest",
    "tropical_escape": "Tropical Escape · Bloom",
}

def get_len(atm, room):
    return len(compose_generation_prompt(
        style_label=label_map[atm], room_type=room,
        room_description=room_desc, user_instruction="",
        iteration=1, history=[], secondary_visible_spaces=[],
        compact_prompts=False, generation_mode="preserve",
        edit_mode=EditMode.FIRST_VISION,
    ))

# Step 1: baseline
baseline = {}
for atm in ATMOSPHERES:
    for room in ROOMS:
        baseline[(atm, room)] = get_len(atm, room)

# Step 2: hot-patch decor_language + build_dna_block slicing
original_decor = {}
for (atm, room), new_items in ENRICH.items():
    if not new_items:
        continue
    if atm in _ADAPTATION_REGISTRY and room in _ADAPTATION_REGISTRY[atm]:
        dna = _ADAPTATION_REGISTRY[atm][room]
        original_decor[(atm, room)] = list(dna.decor_language)
        dna.decor_language[:] = list(dna.decor_language) + new_items

original_build_dna_block = base.build_dna_block
def patched_build_dna_block(dna):
    core = base.get_core(dna.atmosphere_id)
    atm_name = dna.atmosphere_id.replace("_", " ").title()
    room_name = dna.room_type.replace("_", " ").title()
    mat = ", ".join(dna.material_palette[:3])
    style_items = (dna.furniture_language[:3] + dna.decor_language[:4])
    style = "; ".join(style_items)
    real = "; ".join(dna.realism_constraints[:2])
    room_avoid = dna.negative_rules[:3]
    if core:
        core_forbidden = [x for x in core.forbidden_elements[:2] if x not in room_avoid]
        avoid = ", ".join(room_avoid + core_forbidden)
        atm_line = f"ATMOSPHERE ({atm_name}): {core.philosophy} - {core.emotional_intent}. [{core.luxury_level}]"
    else:
        avoid = ", ".join(room_avoid)
        atm_line = f"ATMOSPHERE ({atm_name}): {atm_name} design intelligence."
    room_line = f"ROOM ({room_name}): {mat}. LIGHT: {dna.lighting_behavior} ATMOSPHERE STYLE (restyle existing elements): {style}. REALISM: {real}. AVOID: {avoid}."
    return atm_line + "\n" + room_line

base.build_dna_block = patched_build_dna_block
import prompt_engine.atmosphere_dna as atmodna_mod
import prompt_engine.composer as composer_mod
atmodna_mod.build_dna_block = patched_build_dna_block
composer_mod.build_dna_block = patched_build_dna_block  # bound name inside composer

enriched = {}
for atm in ATMOSPHERES:
    for room in ROOMS:
        enriched[(atm, room)] = get_len(atm, room)

base.build_dna_block = original_build_dna_block
atmodna_mod.build_dna_block = original_build_dna_block
composer_mod.build_dna_block = original_build_dna_block
for (atm, room), original in original_decor.items():
    _ADAPTATION_REGISTRY[atm][room].decor_language[:] = original

print()
print("WAVE 6.2 BUDGET AUDIT - per cell current vs enriched (FV preserve mode)")
print("=" * 84)
print(f"{'Atmosphere':<18}{'Room':<18}{'Current':>10}{'Enriched':>10}{'Delta':>8}  {'+items'}")
print("-" * 84)
total_curr = 0
total_enr = 0
total_items = 0
for atm in ATMOSPHERES:
    print(f"--- {atm} ---")
    for room in ROOMS:
        c = baseline[(atm, room)]
        e = enriched[(atm, room)]
        n = len(ENRICH.get((atm, room), []))
        total_curr += c
        total_enr += e
        total_items += n
        items_str = f"+{n}" if n else " 0"
        print(f"  {atm:<16}{room:<18}{c:>10}{e:>10}{e-c:>+8}     {items_str}")
print("-" * 84)
print(f"{'TOTAL (78 cells)':<36}{total_curr:>10}{total_enr:>10}{total_enr-total_curr:>+8}     +{total_items}")
print()
print(f"  Avg current  : {total_curr/78:.0f} chars")
print(f"  Avg enriched : {total_enr/78:.0f} chars")
print(f"  Avg delta    : +{(total_enr-total_curr)/78:.0f} chars per cell")
print(f"  Cells enriched: {sum(1 for k in ENRICH if ENRICH[k])} / 78")
print(f"  FV budget cap : 4000 chars")
max_e = max(enriched.values())
max_key = [k for k,v in enriched.items() if v == max_e][0]
print(f"  Worst case   : {max_e}c on {max_key} (headroom {4000-max_e}c)")
