"""
Wave 4.11a — Ambiguity Detector.

Catches truly ambiguous V2+ refinement requests and emits a concise
clarification template in the user's language. Goal : stop the
architect from guessing what "make it bigger" means and generating a
vision the user didn't ask for.

Design rules (Wave 4.11a North Star : "The architect understands what
I mean."):

    1. V1 messages are NEVER clarified — the first user brief is taken
       at face value, even if ambiguous. The architect makes a
       judgement call on V1 ; this module fires only on V2+.

    2. Confidence-gated emission. Each rule produces a confidence score
       (0.0–1.0). Only matches with confidence >= 0.7 fire. Clear
       directional intents — "warmer", "more luxury", "more wood",
       "darker", "more plants" — score low and pass through to the
       normal generation path.

    3. Single match per message. The first rule that triggers above
       threshold wins ; later rules don't pile clarifications.

    4. Anti-pattern guard. Each rule carries a list of disambiguating
       nouns / materials / atmospheres. "make it bigger" fires
       (confidence 0.9) ; "make the sofa bigger" does NOT (anti-pattern
       drops confidence to 0.2).

    5. EN + KM mandatory. Cambodia launch priority.

    6. Brevity. Clarifications are bullet-style, 3-line max, mirror the
       wording of the architect's tone library.

Public API:
    detect_ambiguity(message, iteration, language) -> Optional[ClarificationResult]
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Optional


# ── Output shape ─────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class ClarificationResult:
    """Returned by detect_ambiguity when a rule fires above threshold."""
    ambiguity_id: str
    clarification_text: str
    language: str
    confidence: float


# Threshold below which a match is suppressed. Tuned conservative — better
# to generate something the user didn't quite want than to interrupt every
# slightly fuzzy refinement with a clarification dialog.
_CONFIDENCE_THRESHOLD = 0.7


# Wave 4.11b — room-type normalisation. The frontend may send variants
# (e.g. "houseFacade", "house_facade", "exterior"), so we normalise to a
# small fixed vocabulary before looking up room-aware clarifications.
def _normalise_room(room_type: Optional[str]) -> Optional[str]:
    if not room_type:
        return None
    r = room_type.strip().lower().replace("-", "_").replace(" ", "_")
    aliases = {
        "living_room": "living_room",
        "livingroom": "living_room",
        "lounge": "living_room",
        "salon": "living_room",
        "kitchen": "kitchen",
        "kitchenette": "kitchen",
        "bedroom": "bedroom",
        "master_bedroom": "bedroom",
        "main_bedroom": "bedroom",
        "bathroom": "bathroom",
        "ensuite": "bathroom",
        "shower_room": "bathroom",
        "facade": "facade",
        "house_facade": "facade",
        "housefacade": "facade",
        "exterior": "facade",
        "outside": "facade",
    }
    return aliases.get(r)


# ── Rule registry ────────────────────────────────────────────────────────────
# Each rule has :
#   trigger_en / trigger_km    — regex that matches the candidate ambiguity
#   anti_patterns_en/_km       — regex list that DROPS confidence when present
#                                 (object specified, material named, atmosphere
#                                 named — anything that resolves the ambiguity)
#   clarification_en / _km     — the 3-bullet question we emit
#   category                   — for tests / introspection
#
# Confidence scoring (in detect_ambiguity below) :
#   trigger matches + zero anti-patterns          → 0.9  (fires)
#   trigger matches + 1 anti-pattern              → 0.4  (suppressed)
#   trigger matches + 2+ anti-patterns            → 0.15 (suppressed)
#   trigger doesn't match                          → skip
#
# The threshold (0.7) is chosen so a single anti-pattern always suppresses
# the rule. We default to "don't clarify" when there's any disambiguating
# context.

_RULES: dict[str, dict] = {

    # ── 1. "bigger" without specified object ─────────────────────────────
    # Triggered by : "make it bigger", "a bit bigger", "go bigger"
    # Suppressed by : sofa / table / chair / room / etc.
    "bigger_unscoped": {
        "category": "scale",
        "trigger_en": r"\b(bigger|larger)\b",
        "trigger_km": r"ធំ(ជាង|ឡើង|ៗ)",
        "anti_patterns_en": [
            r"\b(sofa|chair|table|bed|rug|tv|wall|window|door|cabinet|"
            r"shelf|mirror|lamp|light|plant|vase|painting|art|frame|"
            r"curtain|carpet|piece|object|sink|island|partition|opening|"
            r"kitchen|bathroom|bedroom|living\s*room|dining|hallway|"
            r"balcony|terrace|garden|pool|facade)\b",
        ],
        "anti_patterns_km": [
            r"(សាឡុង|តុ|ជញ្ជាំង|បង្អួច|គ្រែ|ឯកាសន្ធា|ផ្ទះបាយ|"
            r"បន្ទប់ទឹក|បន្ទប់គេង|បន្ទប់ទទួលភ្ញៀវ|អាងហែលទឹក)",
        ],
        "clarification_en": (
            "When you say bigger — are you thinking :\n"
            "• a specific piece (sofa, table, lamp)\n"
            "• the seating zone or kitchen footprint (more open arrangement)\n"
            "• the perceived room scale (architectural depth, ceiling, openings)\n\n"
            "Tell me which and I'll calibrate the next vision."
        ),
        "clarification_km": (
            "ពេលអ្នកនិយាយធំជាង — តើអ្នកគិតពី :\n"
            "• គ្រឿងសង្ហារឹមជាក់លាក់ (សាឡុង តុ ឯកាសន្ធា)\n"
            "• តំបន់អង្គុយឬផ្ទៃផ្ទះបាយ (ការរៀបចំបើកចំហជាង)\n"
            "• វិមាត្របន្ទប់ដែលគេមើលឃើញ (ជម្រៅស្ថាបត្យកម្ម ពិដាន ការបើកចំហ)\n\n"
            "ប្រាប់ខ្ញុំមួយណា ហើយខ្ញុំនឹងសម្រួលទស្សនៈបន្ទាប់។"
        ),
        # Wave 4.11b — room-aware clarifications for "bigger". When the
        # request's room_type matches one of these, this template is used
        # instead of the generic clarification_en above. EN-only Phase 1.
        "room_clarifications_en": {
            "living_room": (
                "When you say bigger — are you thinking :\n"
                "• the sofa or specific seating piece\n"
                "• the seating area (more generous arrangement)\n"
                "• the overall room feeling (architectural openness)\n\n"
                "Tell me which and I'll calibrate the next vision."
            ),
            "kitchen": (
                "When you say bigger — are you thinking :\n"
                "• the island or the prep counter\n"
                "• the workspace footprint (more circulation)\n"
                "• the overall kitchen perception (openness to the room)\n\n"
                "Tell me which and I'll calibrate the next vision."
            ),
            "bedroom": (
                "When you say bigger — are you thinking :\n"
                "• the bed zone or specific piece\n"
                "• the storage and dressing footprint\n"
                "• the overall room feeling (perceived volume)\n\n"
                "Tell me which and I'll calibrate the next vision."
            ),
            "bathroom": (
                "When you say bigger — are you thinking :\n"
                "• the shower or bath\n"
                "• the vanity and storage zone\n"
                "• the overall room perception (sightlines, height)\n\n"
                "Tell me which and I'll calibrate the next vision."
            ),
            "facade": (
                "When you say bigger — are you thinking :\n"
                "• the entrance and approach\n"
                "• the glazing on the facade\n"
                "• the overall scale perception (volume, proportions)\n\n"
                "Tell me which and I'll calibrate the next vision."
            ),
        },
    },

    # ── 2. "smaller" without specified object ────────────────────────────
    "smaller_unscoped": {
        "category": "scale",
        "trigger_en": r"\b(smaller|tighter)\b",
        "trigger_km": r"តូច(ជាង|ឡើង|ៗ)",
        "anti_patterns_en": [
            r"\b(sofa|chair|table|bed|rug|tv|wall|window|door|cabinet|"
            r"shelf|mirror|lamp|light|plant|vase|painting|art|frame|"
            r"curtain|carpet|piece|object|sink|island|partition|opening|"
            r"kitchen|bathroom|bedroom|living\s*room|dining|hallway|"
            r"balcony|terrace|garden|pool|facade)\b",
        ],
        "anti_patterns_km": [
            r"(សាឡុង|តុ|ជញ្ជាំង|បង្អួច|គ្រែ|ឯកាសន្ធា|ផ្ទះបាយ|"
            r"បន្ទប់ទឹក|បន្ទប់គេង|បន្ទប់ទទួលភ្ញៀវ|អាងហែលទឹក)",
        ],
        "clarification_en": (
            "When you say smaller — are you thinking :\n"
            "• a specific piece (sofa, dining table, kitchen island)\n"
            "• the footprint of a zone (tighter seating, narrower kitchen)\n"
            "• a less imposing overall composition\n\n"
            "Tell me which and I'll calibrate the next vision."
        ),
        "clarification_km": (
            "ពេលអ្នកនិយាយតូចជាង — តើអ្នកគិតពី :\n"
            "• គ្រឿងសង្ហារឹមជាក់លាក់ (សាឡុង តុទទួលទាន ឯកាសន្ធាផ្ទះបាយ)\n"
            "• ផ្ទៃនៃតំបន់ (ការអង្គុយតឹង ផ្ទះបាយចង្អៀត)\n"
            "• សមាសភាពទាំងមូលដែលមិនសង្កត់\n\n"
            "ប្រាប់ខ្ញុំមួយណា ហើយខ្ញុំនឹងសម្រួលទស្សនៈបន្ទាប់។"
        ),
        # Wave 4.11b — room-aware clarifications for "smaller".
        "room_clarifications_en": {
            "living_room": (
                "When you say smaller — are you thinking :\n"
                "• the sofa or a specific seating piece\n"
                "• the seating area (more compact arrangement)\n"
                "• the overall room feeling (cozier, less imposing)\n\n"
                "Tell me which and I'll calibrate the next vision."
            ),
            "kitchen": (
                "When you say smaller — are you thinking :\n"
                "• the island or a specific appliance footprint\n"
                "• the workspace zone (tighter circulation)\n"
                "• the overall kitchen presence (less dominant)\n\n"
                "Tell me which and I'll calibrate the next vision."
            ),
            "bedroom": (
                "When you say smaller — are you thinking :\n"
                "• the bed or a specific piece\n"
                "• the storage / dressing footprint\n"
                "• the overall room feeling (more intimate)\n\n"
                "Tell me which and I'll calibrate the next vision."
            ),
            "bathroom": (
                "When you say smaller — are you thinking :\n"
                "• the vanity or shower footprint\n"
                "• the storage zone\n"
                "• the overall room presence (less imposing)\n\n"
                "Tell me which and I'll calibrate the next vision."
            ),
            "facade": (
                "When you say smaller — are you thinking :\n"
                "• the entrance composition\n"
                "• the glazing area\n"
                "• the overall scale perception (less monolithic)\n\n"
                "Tell me which and I'll calibrate the next vision."
            ),
        },
    },

    # ── 3. "better" without aspect ───────────────────────────────────────
    # "Make it better" = which dimension? materials, lighting, decor,
    # spatial flow ? Always ambiguous when alone.
    "better_unscoped": {
        "category": "vague_quality",
        "trigger_en": r"\b(better|improve)\b",
        "trigger_km": r"ល្អជាង|ប្រសើរ",
        "anti_patterns_en": [
            r"\b(material|materials|lighting|light|decor|atmosphere|"
            r"wood|stone|tile|fabric|color|colour|composition|layout|"
            r"flow|balance|warmth|contrast|texture|palette)\b",
        ],
        "anti_patterns_km": [
            r"(សម្ភារៈ|ពន្លឺ|តុបតែង|បរិយាកាស|ឈើ|ថ្ម|ក្រាស់|ពណ៌|សមាសភាព)",
        ],
        "clarification_en": (
            "Better in which direction — :\n"
            "• material palette (richer / lighter / more cohesive)\n"
            "• lighting register (warmer / more layered / softer)\n"
            "• atmospheric intensity (push the chosen atmosphere harder)\n\n"
            "Or describe what feels off and I'll work from that."
        ),
        "clarification_km": (
            "ល្អជាងតាមទិសដៅណា — :\n"
            "• សម្ភារៈ (សម្បូរជាង ស្រាលជាង រួមរម៉ាត់ជាង)\n"
            "• ពន្លឺ (កក់ក្តៅជាង ស្រទាប់ជាង ទន់ជាង)\n"
            "• បរិយាកាស (រុញបរិយាកាសដែលជ្រើសខ្លាំងជាង)\n\n"
            "ឬពិពណ៌នាអ្វីដែលមើលទៅមិនត្រូវ ហើយខ្ញុំនឹងធ្វើការពីនោះ។"
        ),
    },

    # ── 4. "nicer" / "more elegant" without aspect ───────────────────────
    "nicer_unscoped": {
        "category": "vague_quality",
        "trigger_en": r"\b(nicer|more\s+elegant|more\s+refined|more\s+polished|classier)\b",
        "trigger_km": r"ល្អមើល(ជាង|ឡើង)|ប្រណិត(ជាង|ឡើង)",
        "anti_patterns_en": [
            r"\b(material|materials|lighting|light|decor|atmosphere|"
            r"wood|stone|tile|fabric|color|colour|piece|composition)\b",
        ],
        "anti_patterns_km": [
            r"(សម្ភារៈ|ពន្លឺ|តុបតែង|បរិយាកាស|ឈើ|ថ្ម|ពណ៌)",
        ],
        "clarification_en": (
            "More elegant where — :\n"
            "• tighter material palette (fewer textures, more discipline)\n"
            "• calmer lighting (softer, more architectural)\n"
            "• decor restraint (one sculptural piece instead of clusters)\n\n"
            "Pick the angle and the next vision targets it."
        ),
        "clarification_km": (
            "ប្រណិតជាងនៅកន្លែងណា — :\n"
            "• សម្ភារៈតឹងជាង (texture តិច មានវិន័យជាង)\n"
            "• ពន្លឺស្ងប់ជាង (ទន់ ស្ថាបត្យកម្មជាង)\n"
            "• ការតុបតែងតិច (ស្នាដៃមួយ ជាជាងជាក្រុម)\n\n"
            "ជ្រើសមុំ ហើយទស្សនៈបន្ទាប់នឹងផ្តោតលើវា។"
        ),
    },

    # ── 5. "make it pop" — visual goal unclear ───────────────────────────
    "pop_unscoped": {
        "category": "vague_quality",
        "trigger_en": r"\b(make\s+it\s+pop|stand\s+out\s+more|more\s+impact)\b",
        "trigger_km": r"មាន(ឥទ្ធិពល|ឥទ្ធិពលជាង)",
        "anti_patterns_en": [
            r"\b(color|colour|accent|art|painting|lighting|focal|piece|"
            r"contrast)\b",
        ],
        "anti_patterns_km": [
            r"(ពណ៌|ផ្ទាំង|ពន្លឺ|ផ្តោត)",
        ],
        "clarification_en": (
            "What kind of impact — :\n"
            "• a focal accent piece (artwork, sculptural light, statement chair)\n"
            "• stronger material contrast (darker stone, deeper wood)\n"
            "• punctuating lighting (a wall sconce, a focused pendant)\n\n"
            "Tell me which and I'll build the next vision around it."
        ),
        "clarification_km": (
            "ឥទ្ធិពលប្រភេទណា — :\n"
            "• ស្នាដៃផ្តោត (ផ្ទាំងគំនូរ ពន្លឺស្ថាបត្យកម្ម កៅអីប្រកាស)\n"
            "• កម្រិតផ្ទុយសម្ភារៈខ្លាំងជាង (ថ្មងងឹត ឈើជ្រៅ)\n"
            "• ពន្លឺផ្តោត (ពន្លឺជញ្ជាំង ពន្លឺផ្តោត)\n\n"
            "ប្រាប់ខ្ញុំមួយណា ហើយខ្ញុំនឹងបង្កើតទស្សនៈជុំវិញវា។"
        ),
    },

    # ── 6. "different" without direction ─────────────────────────────────
    "different_unscoped": {
        "category": "vague_direction",
        "trigger_en": r"\b(different|something\s+else|try\s+something)\b",
        "trigger_km": r"ផ្សេង(ៗ)?",
        "anti_patterns_en": [
            r"\b(atmosphere|style|material|lighting|color|colour|layout|"
            r"decor|piece|direction)\b",
        ],
        "anti_patterns_km": [
            r"(បរិយាកាស|ស្ទីល|សម្ភារៈ|ពន្លឺ|ពណ៌|ការរៀបចំ|តុបតែង)",
        ],
        "clarification_en": (
            "Different in which sense — :\n"
            "• a new atmosphere altogether (switch from your current direction)\n"
            "• same atmosphere, different material weight or lighting\n"
            "• a more radical layout reinterpretation\n\n"
            "Sketch the direction and I'll take it from there."
        ),
        "clarification_km": (
            "ផ្សេងតាមអត្ថន័យណា — :\n"
            "• បរិយាកាសថ្មីទាំងអស់ (ប្តូរពីទិសដៅបច្ចុប្បន្ន)\n"
            "• បរិយាកាសដដែល ប៉ុន្តែទម្ងន់សម្ភារៈឬពន្លឺផ្សេង\n"
            "• ការបកស្រាយរូបរាងរុនជាង\n\n"
            "គូសទិសដៅ ហើយខ្ញុំនឹងបន្តពីទីនោះ។"
        ),
    },

    # ── 7. "change it" with no specifics ─────────────────────────────────
    "change_unscoped": {
        "category": "vague_direction",
        "trigger_en": r"\b(change\s+it|change\s+the\s+whole|redo\s+it)\b",
        "trigger_km": r"ផ្លាស់(ប្តូរ)\s*(វា|ទាំងអស់)",
        "anti_patterns_en": [
            r"\b(sofa|chair|table|wall|window|door|tv|atmosphere|color|"
            r"material|lighting|decor|layout|piece)\b",
        ],
        "anti_patterns_km": [
            r"(សាឡុង|តុ|ជញ្ជាំង|បង្អួច|បរិយាកាស|ពណ៌|សម្ភារៈ|ពន្លឺ|"
            r"តុបតែង|ការរៀបចំ)",
        ],
        "clarification_en": (
            "Change which layer — :\n"
            "• the atmosphere (swap to a different design language entirely)\n"
            "• materials and decor (keep the atmosphere, refresh the surfaces)\n"
            "• the spatial layout (re-block the room)\n\n"
            "Pick the layer and I'll lead with that."
        ),
        "clarification_km": (
            "ផ្លាស់ប្តូរស្រទាប់ណា — :\n"
            "• បរិយាកាស (ប្តូរទៅភាសារចនាខុសគ្នាទាំងស្រុង)\n"
            "• សម្ភារៈនិងតុបតែង (រក្សាបរិយាកាស ធ្វើឱ្យផ្ទៃថ្មី)\n"
            "• រូបរាងលំហ (រៀបចំបន្ទប់ឡើងវិញ)\n\n"
            "ជ្រើសស្រទាប់ ហើយខ្ញុំនឹងនាំជាមួយវា។"
        ),
    },

    # ── 8. "more" without object ─────────────────────────────────────────
    # Critical : "more wood", "more luxury", "more plants", "more light"
    # are ALL clear intents and must NOT trigger. Only "more" standing
    # alone with no following noun fires.
    "more_unscoped": {
        "category": "vague_quantity",
        "trigger_en": r"\b(more|add\s+more)\b(?!\s+\w+)",  # "more" + nothing
        "trigger_km": r"\bច្រើនជាង\b(?!\s)",
        "anti_patterns_en": [
            # "more X" — broad guard against any noun following
            r"\bmore\s+(wood|stone|tile|marble|metal|brass|glass|leather|"
            r"velvet|linen|cotton|fabric|texture|color|colour|light|"
            r"lighting|warmth|contrast|depth|space|openness|plants|art|"
            r"decoration|decor|furniture|seating|storage|character|"
            r"luxury|elegance|modern|traditional|scandinavian|japandi|"
            r"warm|warmth|natural|organic|industrial|rustic|minimalist|"
            r"layered|polished|raw|refined|cosy|cozy|spacious)\b",
        ],
        "anti_patterns_km": [
            r"ច្រើនជាង\s*(ឈើ|ថ្ម|កញ្ចក់|សក់|ផ្ការណាក់|ពណ៌|"
            r"ពន្លឺ|កក់ក្តៅ|បរិយាកាស)",
        ],
        "clarification_en": (
            "More of which layer — :\n"
            "• material density (richer textures, layered surfaces)\n"
            "• decor and objects (sculptural pieces, plants, art)\n"
            "• lighting presence (warmer ambient, more focal points)\n\n"
            "Name the layer and the next iteration deepens it."
        ),
        "clarification_km": (
            "ច្រើនជាងស្រទាប់ណា — :\n"
            "• ដង់ស៊ីតេសម្ភារៈ (texture សម្បូរ ផ្ទៃជាស្រទាប់)\n"
            "• តុបតែងនិងវត្ថុ (ស្នាដៃ ផ្ការណាក់ សិល្បៈ)\n"
            "• ពន្លឺ (បរិយាកាសកក់ក្តៅ ចំណុចផ្តោតច្រើនជាង)\n\n"
            "ដាក់ឈ្មោះស្រទាប់ ហើយការរុករកបន្ទាប់នឹងជម្រៅវា។"
        ),
    },

    # ── 9. "less" without object ─────────────────────────────────────────
    "less_unscoped": {
        "category": "vague_quantity",
        "trigger_en": r"\b(less|reduce)\b(?!\s+\w+)",
        "trigger_km": r"តិចជាង(?!\s)",
        "anti_patterns_en": [
            r"\bless\s+(wood|stone|tile|fabric|texture|color|colour|"
            r"light|lighting|warmth|contrast|decoration|decor|furniture|"
            r"seating|clutter|noise|dense|busy|cluttered|maximalist)\b",
        ],
        "anti_patterns_km": [
            r"តិចជាង\s*(ឈើ|ថ្ម|សក់|ពណ៌|ពន្លឺ|តុបតែង|ច្របូកច្របល់)",
        ],
        "clarification_en": (
            "Less of which — :\n"
            "• decor / clutter (calmer surfaces, fewer objects)\n"
            "• material contrast (more tonal, less visual tension)\n"
            "• warmth or saturation (cooler, quieter palette)\n\n"
            "Pick the angle and I'll dial it back."
        ),
        "clarification_km": (
            "តិចជាងអ្វី — :\n"
            "• តុបតែង / ច្របូកច្របល់ (ផ្ទៃស្ងប់ វត្ថុតិច)\n"
            "• ភាពផ្ទុយសម្ភារៈ (ស្ថិតិតុង តានតឹងភ្នែកតិច)\n"
            "• កក់ក្តៅឬភាពតិត្ថភាព (ត្រជាក់ស្ងាត់ជាង)\n\n"
            "ជ្រើសមុំ ហើយខ្ញុំនឹងបន្ថយវា។"
        ),
    },

    # ── 10. "open" / "more open" without zone or kind ────────────────────
    "open_unscoped": {
        "category": "vague_layout",
        "trigger_en": r"\b(more\s+open|open\s+it\s+up|opener)\b",
        "trigger_km": r"បើក(ចំហ|ឱ្យបើក|ច្រើនជាង)",
        "anti_patterns_en": [
            r"\b(wall|partition|kitchen|window|opening|sliding|door|"
            r"facade|palette|color|colour|tone|composition|layout|"
            r"floor\s*plan|sightline)\b",
        ],
        "anti_patterns_km": [
            r"(ជញ្ជាំង|ឯកាសន្ធា|ផ្ទះបាយ|បង្អួច|ទ្វារ|ពណ៌)",
        ],
        "clarification_en": (
            "Open in which sense — :\n"
            "• architecturally (remove a partition, widen an opening)\n"
            "• visually (lighter palette, less visual weight)\n"
            "• in the foreground (clear the seating zone, fewer pieces)\n\n"
            "The next vision reads very differently depending on which one."
        ),
        "clarification_km": (
            "បើកតាមអត្ថន័យណា — :\n"
            "• ស្ថាបត្យកម្ម (ដកឯកាសន្ធា ពង្រីកការបើកចំហ)\n"
            "• មើលឃើញ (សម្ភារៈស្រាលជាង ទម្ងន់ភ្នែកតិច)\n"
            "• នៅពីមុខ (សម្អាតតំបន់អង្គុយ វត្ថុតិចជាង)\n\n"
            "ទស្សនៈបន្ទាប់អានខុសគ្នាខ្លាំងអាស្រ័យលើមួយណា។"
        ),
    },
}


# ── Confidence scorer ────────────────────────────────────────────────────────

def _score(message: str, rule: dict, language: str) -> float:
    """
    Score a single rule against a message.

    Returns 0.0 if trigger doesn't match, otherwise drops the base 0.9 for
    every anti-pattern present. Single anti-pattern is enough to push the
    rule below the 0.7 threshold.
    """
    trigger_key = f"trigger_{language}"
    if trigger_key not in rule:
        return 0.0
    if not re.search(rule[trigger_key], message, re.IGNORECASE):
        return 0.0

    anti_key = f"anti_patterns_{language}"
    anti_patterns = rule.get(anti_key, [])
    anti_hits = sum(
        1 for p in anti_patterns if re.search(p, message, re.IGNORECASE)
    )

    # Confidence schedule :
    #   0 anti-pattern  → 0.9 (fires)
    #   1 anti-pattern  → 0.4 (suppressed)
    #   2+ anti-pattern → 0.15 (suppressed)
    if anti_hits == 0:
        return 0.9
    if anti_hits == 1:
        return 0.4
    return 0.15


# ── Public API ───────────────────────────────────────────────────────────────

def detect_ambiguity(
    message: str,
    iteration: int,
    language: str = "en",
    room_type: Optional[str] = None,
) -> Optional[ClarificationResult]:
    """
    Test the message against all ambiguity rules and emit a clarification
    if any rule scores above the confidence threshold.

    Returns None when :
      - message is empty
      - iteration <= 1 (V1 never clarifies — first brief is law)
      - language not supported (returns None, caller falls back to EN
        downstream)
      - no rule scores above _CONFIDENCE_THRESHOLD (default 0.7)

    Returns the highest-scoring match otherwise. Single result per call —
    no piling of clarifications.

    Wave 4.11b — room-aware clarifications. When a rule defines
    `room_clarifications_<lang>` and the request's `room_type` matches
    (after _normalise_room aliasing), that room-specific template is
    used instead of the generic one. Falls back gracefully to the
    generic template when the room is unknown or not covered.

    Performance : O(rules × patterns) with cached compiled regex (Python
    caches automatically). Typical cost <2 ms.
    """
    if not message or iteration <= 1:
        return None
    lang = language if language in ("en", "km") else "en"

    best: Optional[tuple[str, dict, float]] = None
    for ambiguity_id, rule in _RULES.items():
        confidence = _score(message, rule, lang)
        if confidence < _CONFIDENCE_THRESHOLD:
            continue
        if best is None or confidence > best[2]:
            best = (ambiguity_id, rule, confidence)

    if best is None:
        return None

    ambiguity_id, rule, confidence = best

    # Wave 4.11b — prefer room-aware clarification when the rule has one
    # for the request's room_type. Phase 1 ships EN room-aware templates ;
    # other languages fall back to the generic clarification path below.
    clarification = ""
    normalised_room = _normalise_room(room_type) if lang == "en" else None
    if normalised_room is not None:
        room_map = rule.get(f"room_clarifications_{lang}", {}) or {}
        clarification = room_map.get(normalised_room, "")

    if not clarification:
        clarification = rule.get(f"clarification_{lang}") or rule.get(
            "clarification_en", ""
        )

    return ClarificationResult(
        ambiguity_id=ambiguity_id,
        clarification_text=clarification,
        language=lang,
        confidence=confidence,
    )


def list_rules() -> list[str]:
    """Return all rule IDs — for tests / introspection."""
    return list(_RULES.keys())


def confidence_threshold() -> float:
    """Expose the fire threshold — for tests + future tuning waves."""
    return _CONFIDENCE_THRESHOLD
