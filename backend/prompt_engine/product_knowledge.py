"""
Wave 4.11a — Product Knowledge (Single Source of Truth).

This module is the ONE canonical place where the architect "knows" about the
product. It answers questions about features, support, billing and meta
("who are you?") in the user's language without ever triggering a
generation.

Design constraints (Wave 4.11a North Star):
    "I'm talking to an architect."           → tone of answers
    "The architect understands what I mean." → strict pattern matching +
                                                language-aware lookup

Mandatory product rules baked in:
    • Zero new OpenAI calls — every answer is pre-authored, deterministic.
    • Zero external services — pure Python regex + dict lookup.
    • Single file — no FAQ shards. Adding a topic = adding ONE dict entry.
    • English + Khmer support for every topic (Cambodia launch priority).
    • Fallback : if Khmer answer missing for any reason, falls back to
      English rather than blocking the response.

Public API:
    detect_product_help(message, language) -> Optional[str]
        Tries to match a topic_id from regex patterns in the chosen language.
    get_product_answer(topic_id, language) -> str
        Returns architect-voice answer in the requested language.
    is_product_query(message, language) -> bool
        Lightweight pre-check ("does this look like a product question?")
        before running the full detector — used by main.py to short-circuit
        the standard intent_classifier when appropriate.
    list_topics(category=None) -> list[str]
        For tests / introspection.

Wired into main.py /chat endpoint after meta_intent classification and
ambiguity check, before the standard GENERATE / CONVERSATION routing.
When a topic matches, the response sets should_generate=False so the
user never sees an image generation triggered by a product question.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Optional


# ── Data shape ───────────────────────────────────────────────────────────────
# Each topic carries detection patterns and answers for both languages.
# Patterns are compiled lazily at first lookup and cached in
# _COMPILED_PATTERNS for reuse across requests.

@dataclass(frozen=True)
class ProductTopic:
    """In-memory shape of a topic for typed access in main.py."""
    topic_id: str
    category: str
    answer_en: str
    answer_km: str


# ── Feature & design topics (17) ─────────────────────────────────────────────
# These cover the everyday "how do I…?" questions about using the design
# experience itself : evolving a vision, atmospheres, branching, the reveal
# surface, voice, sessions, naming, saving, restoring.

_FEATURE_TOPICS: dict[str, dict] = {
    "continue_vision": {
        "category": "feature",
        "patterns_en": [
            r"\bhow\s+(do|can)\s+i\s+continue\b",
            r"\bcontinue\s+(this\s+)?vision\b",
            r"\bevolve\s+(this|the)\s+(design|vision)\b",
            r"\bkeep\s+going\s+(from|with)\b",
            r"\biterate\s+(on|from)\b",
        ],
        "patterns_km": [
            r"បន្ត\s*ទស្សនៈ",
            r"តើ\s*ខ្ញុំ\s*បន្ត",
            r"វិវឌ្ឍន៍\s*(ការ)?រចនា",
        ],
        "answer_en": (
            "When you find a version you like, tap **Continue this vision** "
            "below the reveal. The next refinement evolves from that image "
            "rather than starting fresh — the architectural anchors (windows, "
            "kitchen opening, glazing) carry across the chain. If you'd rather "
            "branch a new direction from the same starting point, you can do "
            "that from any prior vision in the chat timeline."
        ),
        "answer_km": (
            "នៅពេលអ្នករកឃើញកំណែដែលអ្នកចូលចិត្ត ចុចប៊ូតុង **Continue this vision** "
            "នៅខាងក្រោមការបង្ហាញ។ ការកែលម្អបន្ទាប់នឹងវិវឌ្ឍន៍ពីរូបភាពនោះ — "
            "ធាតុស្ថាបត្យកម្ម (បង្អួច បើកចំហផ្ទះបាយ កញ្ចក់) នឹងបន្តតាមខ្សែ។ "
            "បើអ្នកចង់បំបែកទិសដៅថ្មីពីចំណុចចាប់ផ្តើមដដែល "
            "អ្នកអាចធ្វើបានពីទស្សនៈពីមុនណាមួយក្នុងបន្ទាត់ chat។"
        ),
    },

    "preserve_mode": {
        "category": "feature",
        "patterns_en": [
            r"\bwhat\s+(is|does)\s+preserve\s+mode\b",
            r"\bpreserve\s+mode\s+(do|mean|work)\b",
            r"\bwhat\s+does\s+preserve\b",
            r"\bhow\s+does\s+preserve\b",
        ],
        "patterns_km": [
            r"រក្សា\s*ទុក\s*(លំនៅដ្ឋាន|លក្ខណៈ)",
            r"តើ\s*Preserve\s*ជា\s*អ្វី",
            r"ការ\s*រក្សា\s*ស្ថាបត្យកម្ម",
        ],
        "answer_en": (
            "Preserve mode locks the photographed architecture — walls, "
            "windows, openings, layout, ceiling height — and reworks only the "
            "materials, furniture, lighting, decor and atmosphere. It's the "
            "default starting point because it gives you a refined version of "
            "**your** space rather than a different room. If you do want to "
            "actually move walls or reshape the layout, describe it in the "
            "brief and I'll handle that as a structural change."
        ),
        "answer_km": (
            "Preserve mode ចាក់សោស្ថាបត្យកម្មដែលថត — ជញ្ជាំង បង្អួច ការបើកចំហ "
            "ការរៀបចំ កម្ពស់ពិដាន — ហើយធ្វើការឡើងវិញតែលើសម្ភារៈ គ្រឿងសង្ហារឹម "
            "ពន្លឺ តុបតែង និងបរិយាកាស។ វាជាចំណុចចាប់ផ្តើមលំនាំដើម "
            "ព្រោះវាផ្តល់ឱ្យអ្នកនូវកំណែដែលបានសម្រួលនៃ**លំនៅដ្ឋានរបស់អ្នក** "
            "ជាជាងបន្ទប់ផ្សេង។ បើអ្នកពិតជាចង់ផ្លាស់ប្តូរជញ្ជាំងឬរូបរាងរៀបចំ "
            "សូមរៀបរាប់ក្នុងសារ ហើយខ្ញុំនឹងដោះស្រាយជាការផ្លាស់ប្តូរស្ថាបត្យកម្ម។"
        ),
    },

    "re_upload": {
        "category": "feature",
        "patterns_en": [
            r"\bre.?upload\b",
            r"\bwhat\s+is\s+(the\s+)?re.?upload\b",
            r"\breplace\s+(the\s+)?(source|original)\s+(photo|image|picture)\b",
            r"\bupload\s+(a\s+)?(new|different)\s+(photo|image|picture)\b",
            r"\bchange\s+(the\s+)?(source|original)\s+(photo|image)\b",
            r"\bstart\s+(over\s+)?(with\s+)?(a\s+)?(new|different)\s+(photo|image)\b",
        ],
        "patterns_km": [
            r"re.?upload",
            r"ផ្ទុក\s*រូបភាព\s*ឡើង\s*វិញ",
            r"ប្ដូរ\s*រូបភាព\s*ដើម",
        ],
        "answer_en": (
            "Re-upload lets you replace the original source photo of a project "
            "with a new one while staying in the same project. Because the new "
            "photo is a different starting point, the version history is reset to "
            "it — the earlier visions don't carry over (they belonged to the old "
            "photo). Use it when you want to redesign a different room or a new "
            "picture of the same space from a clean slate."
        ),
        "answer_km": (
            "Re-upload អនុញ្ញាតឱ្យអ្នកជំនួសរូបភាពដើមរបស់គម្រោងដោយរូបភាពថ្មី "
            "ខណៈនៅក្នុងគម្រោងដដែល។ ដោយសាររូបភាពថ្មីជាចំណុចចាប់ផ្តើមផ្សេង "
            "ប្រវត្តិកំណែត្រូវកំណត់ឡើងវិញ — ទស្សនៈចាស់មិនបន្តទេ។ "
            "ប្រើវានៅពេលអ្នកចង់រចនាបន្ទប់ផ្សេង ឬរូបភាពថ្មីពីដំបូង។"
        ),
    },

    "branching": {
        "category": "feature",
        "patterns_en": [
            r"\bhow\s+does\s+branching\b",
            r"\bwhat\s+is\s+branching\b",
            r"\bbranch\s+(from|a)\s+(vision|design)\b",
            r"\bfork\s+(a|the)\s+(vision|design)\b",
            r"\btry\s+(a\s+)?different\s+direction\b",
        ],
        "patterns_km": [
            r"ការ\s*បំបែក\s*ទស្សនៈ",
            r"ដាក់\s*ទិសដៅ\s*ផ្សេង",
            r"branch",
        ],
        "answer_en": (
            "Branching lets you explore multiple directions from the same "
            "starting point without losing earlier work. Tap any previous "
            "vision in the chat timeline and choose **Continue from this "
            "vision** — the next generation evolves from that one. You can "
            "branch as many times as you want ; each branch keeps its own "
            "architectural anchors and history, so you can compare directions "
            "later in the reveal screen."
        ),
        "answer_km": (
            "ការបំបែកអនុញ្ញាតឱ្យអ្នកស្វែងរកទិសដៅជាច្រើនពីចំណុចចាប់ផ្តើមដដែល "
            "ដោយមិនបាត់បង់ការងារពីមុន។ ចុចលើទស្សនៈពីមុនណាមួយក្នុង chat ហើយជ្រើស "
            "**Continue from this vision** — ការបង្កើតបន្ទាប់នឹងវិវឌ្ឍន៍ពីទស្សនៈនោះ។ "
            "អ្នកអាចបំបែកបានច្រើនដងតាមចង់ ; មែកនីមួយៗរក្សាធាតុស្ថាបត្យកម្មនិងប្រវត្តិ "
            "ដូច្នេះអ្នកអាចប្រៀបធៀបទិសដៅនៅអេក្រង់បង្ហាញពេលក្រោយ។"
        ),
    },

    "reveal_compare": {
        "category": "feature",
        "patterns_en": [
            r"\bhow\s+(do|can)\s+i\s+compare\b",
            r"\bbefore\s+(and|/)?\s*after\b",
            r"\bsee\s+the\s+(original|change)\b",
            r"\bcompare\s+(the\s+)?(designs|versions|visions)\b",
            r"\bswipe\s+(to\s+)?compare\b",
        ],
        "patterns_km": [
            # Wave 4.11c — added ក្រោយ (after) variant and a bare verb form
            # for natural KM phrasings like "តើខ្ញុំប្រៀបធៀបមុននិងក្រោយ…".
            r"ប្រៀបធៀប\s*(មុន|បន្ទាប់|ក្រោយ)",
            r"ឃើញ\s*រូបភាព\s*ដើម",
            r"swipe",
            r"តើ\s*ខ្ញុំ.*ប្រៀបធៀប",
        ],
        "answer_en": (
            "Tap any generated vision and you land on the reveal screen. "
            "Swipe the divider left or right to compare the BEFORE (your "
            "original photo) and the AI VISION side by side. Touch and hold "
            "the image to peek at the very first photo you uploaded. The "
            "swipe is calibrated so you can scrub slowly to inspect material "
            "details — wood grain, lighting falloff, window frames — that the "
            "AI carried over from your space."
        ),
        "answer_km": (
            "ចុចលើទស្សនៈដែលបានបង្កើតណាមួយ អ្នកនឹងទៅដល់អេក្រង់បង្ហាញ។ "
            "អូសខ្សែបែងចែកទៅឆ្វេងឬស្តាំដើម្បីប្រៀបធៀប BEFORE (រូបថតដើមរបស់អ្នក) "
            "និង AI VISION ចំហៀង។ ចុចហើយសង្កត់លើរូបភាពដើម្បីឃើញរូបថតដំបូងបំផុត "
            "ដែលអ្នកបានផ្ទុកឡើង។ ការអូសត្រូវបានសម្រួលដូច្នេះអ្នកអាចមើលលម្អិតយឺតៗ "
            "នូវសម្ភារៈ — ស្នាមឈើ ការធ្លាក់ពន្លឺ ស៊ុមបង្អួច។"
        ),
    },

    "share_design": {
        "category": "feature",
        "patterns_en": [
            r"\bhow\s+(do|can)\s+i\s+share\b",
            r"\bshare\s+(a|the|my)\s+(design|vision|image)\b",
            r"\bsend\s+(this|the)\s+(design|image|render)\b",
            r"\bexport\s+(the|my)\s+(design|image|vision)\b",
        ],
        "patterns_km": [
            r"ចែករំលែក\s*ការ\s*រចនា",
            r"ផ្ញើ\s*រូប\s*ភាព",
            r"share",
        ],
        "answer_en": (
            "From the reveal screen, the share icon at the top-right exports "
            "the current vision (or the side-by-side BEFORE/AI VISION view) "
            "to any app on your device — Messenger, Telegram, Drive, email. "
            "If you want a permanent copy first, long-press the vision in the "
            "chat timeline and choose Save."
        ),
        "answer_km": (
            "ពីអេក្រង់បង្ហាញ រូបតំណាងចែករំលែកនៅខាងស្តាំខាងលើនាំចេញទស្សនៈបច្ចុប្បន្ន "
            "(ឬទិដ្ឋភាពចំហៀង BEFORE/AI VISION) ទៅកម្មវិធីណាមួយនៅលើឧបករណ៍របស់អ្នក — "
            "Messenger, Telegram, Drive, អ៊ីមែល។ បើអ្នកចង់បានច្បាប់ចម្លងជាមុនសិន "
            "ចុចសង្កត់លើទស្សនៈក្នុង chat ហើយជ្រើស Save។"
        ),
    },

    "atmosphere_system": {
        "category": "feature",
        "patterns_en": [
            r"\bwhat\s+(is|are)\s+(the\s+)?atmospheres?\b",
            r"\bhow\s+(do|does)\s+atmospheres?\s+work\b",
            r"\bexplain\s+atmospheres?\b",
            r"\batmosphere\s+system\b",
        ],
        "patterns_km": [
            r"អ្វី\s*ទៅ\s*ជា\s*បរិយាកាស",
            r"តើ\s*បរិយាកាស",
            r"atmosphere",
        ],
        "answer_en": (
            "An atmosphere is a complete design language — material palette, "
            "lighting register, decor density, spatial mood — that I apply to "
            "your photographed space. Each atmosphere (Warm Modern, Japandi "
            "Calm, Soft Luxury, Nordic Warmth, Tropical Escape) has its own "
            "character. The architecture of your space stays anchored ; the "
            "atmosphere is what changes around it."
        ),
        "answer_km": (
            "បរិយាកាសគឺជាភាសារចនាពេញលេញ — សម្ភារៈ ពន្លឺ ដង់ស៊ីតេតុបតែង "
            "អារម្មណ៍លំហ — ដែលខ្ញុំអនុវត្តចំពោះលំនៅដ្ឋានដែលថត។ បរិយាកាសនីមួយៗ "
            "(Warm Modern, Japandi Calm, Soft Luxury, Nordic Warmth, "
            "Tropical Escape) មានចរិតលក្ខណៈរបស់ខ្លួន។ "
            "ស្ថាបត្យកម្មនៃលំនៅដ្ឋានរបស់អ្នក នៅដដែល ; "
            "បរិយាកាសគឺជាអ្វីដែលប្តូរនៅជុំវិញវា។"
        ),
    },

    "atmosphere_switching": {
        "category": "feature",
        "patterns_en": [
            r"\bhow\s+(do|can)\s+i\s+(change|switch)\s+atmospheres?\b",
            r"\bswitch\s+(to|the)\s+atmospheres?\b",
            r"\bchange\s+(the\s+)?(style|atmosphere)\b",
            r"\btry\s+(another|a\s+different)\s+atmospheres?\b",
        ],
        "patterns_km": [
            r"ប្តូរ\s*បរិយាកាស",
            r"ផ្លាស់ប្តូរ\s*ស្ទីល",
        ],
        "answer_en": (
            "You can switch atmosphere anytime — tap **Explore other "
            "atmospheres** under the reveal, or say the new atmosphere name "
            "in chat (\"redesign this in Japandi\"). On a pure switch from "
            "your original photo, the system reboots cleanly so the result "
            "reads as a fresh interpretation, not a filter on top of the "
            "previous one. Architectural anchors carry across."
        ),
        "answer_km": (
            "អ្នកអាចប្តូរបរិយាកាសពេលណាក៏បាន — ចុច **Explore other atmospheres** "
            "នៅខាងក្រោមការបង្ហាញ ឬនិយាយឈ្មោះបរិយាកាសថ្មីក្នុង chat "
            "(\"រចនាឡើងវិញតាមបែប Japandi\")។ ពេលប្តូរសុទ្ធពីរូបថតដើម "
            "ប្រព័ន្ធនឹងចាប់ផ្តើមឡើងវិញដោយស្អាត ដូច្នេះលទ្ធផលអាន "
            "ជាការបកស្រាយថ្មី មិនមែនជាការត្រងលើកំណែមុនទេ។ "
            "ធាតុស្ថាបត្យកម្មបន្តរក្សា។"
        ),
    },

    "restore_previous_vision": {
        "category": "feature",
        "patterns_en": [
            r"\b(go|come)\s+back\s+to\s+(a\s+)?(previous|earlier)\s+(vision|version)\b",
            r"\bundo\s+(the\s+)?(last\s+)?(generation|change|vision)\b",
            r"\brestore\s+(a\s+)?previous\b",
            r"\brevert\s+to\s+(a\s+|the\s+)?(previous|earlier)\b",
        ],
        "patterns_km": [
            r"ត្រឡប់\s*ទៅ\s*ទស្សនៈ\s*មុន",
            r"ស្តារ\s*ឡើង\s*វិញ",
        ],
        "answer_en": (
            "Every vision you generated is kept in the chat timeline above "
            "this conversation. Scroll up and tap any earlier vision to open "
            "the reveal — from there you can continue evolving from THAT "
            "version. Nothing is ever overwritten ; the timeline is your "
            "history and your branch point."
        ),
        "answer_km": (
            "ទស្សនៈនីមួយៗដែលអ្នកបានបង្កើតត្រូវបានរក្សាទុកក្នុង chat ខាងលើ "
            "ការសន្ទនានេះ។ រំកិលឡើងលើហើយចុចទស្សនៈពីមុនណាមួយដើម្បីបើកការបង្ហាញ — "
            "ពីទីនោះអ្នកអាចបន្តវិវឌ្ឍន៍ពីកំណែនោះ។ គ្មានអ្វីត្រូវបានសរសេរជាន់ឡើយ ; "
            "បន្ទាត់ពេលគឺជាប្រវត្តិនិងចំណុចបំបែករបស់អ្នក។"
        ),
    },

    "why_image_changed": {
        "category": "feature",
        "patterns_en": [
            r"\bwhy\s+did\s+(my\s+|the\s+)?(image|render|design|vision)\s+change\b",
            r"\bwhy\s+is\s+(my\s+|the\s+)?(image|render|design|vision)\s+different\b",
            r"\bwhy\s+(does|did)\s+it\s+look\s+different\b",
            r"\bunexpected\s+(change|result)\b",
        ],
        "patterns_km": [
            r"ហេតុ\s*អ្វី\s*រូប\s*ភាព\s*ផ្លាស់",
            r"ហេតុ\s*អ្វី\s*ខុស\s*ពី",
        ],
        "answer_en": (
            "Each generation is a fresh interpretation, not a copy edit. The "
            "model preserves the architectural anchors (windows, openings, "
            "ceiling lines) but materials, furniture and lighting are "
            "re-composed each time according to the atmosphere and your "
            "brief. If something specific drifted that you wanted to keep, "
            "tell me which element and I'll lock it explicitly for the next "
            "iteration."
        ),
        "answer_km": (
            "ការបង្កើតនីមួយៗគឺជាការបកស្រាយថ្មី មិនមែនជាការកែច្បាប់ចម្លងទេ។ "
            "Model រក្សាធាតុស្ថាបត្យកម្ម (បង្អួច បើកចំហ បន្ទាត់ពិដាន) "
            "ប៉ុន្តែសម្ភារៈ គ្រឿងសង្ហារឹម និងពន្លឺត្រូវបានតែងឡើងវិញរៀងរាល់ដង។ "
            "បើមានអ្វីជាក់លាក់ដែលផ្លាស់ប្តូរហើយអ្នកចង់រក្សា "
            "ប្រាប់ខ្ញុំធាតុមួយណា ហើយខ្ញុំនឹងចាក់សោវាសម្រាប់ការរុករកបន្ទាប់។"
        ),
    },

    "delete_session": {
        "category": "feature",
        "patterns_en": [
            r"\bhow\s+(do|can)\s+i\s+delete\s+(a\s+|my\s+|this\s+)?(session|project|design)\b",
            r"\bdelete\s+(a\s+|my\s+|this\s+)?(session|project)\b",
            r"\bremove\s+(a\s+|this\s+)?(session|project|design)\b",
        ],
        "patterns_km": [
            r"លុប\s*(សម័យ|គម្រោង|ការ\s*រចនា)",
        ],
        "answer_en": (
            "Go to your project list, swipe a project row left and choose "
            "Delete — or long-press the row for the same menu. Deletion is "
            "permanent ; the generated visions and your original photo for "
            "that project are removed. If you only want to start a new "
            "direction without losing the old one, branch instead from any "
            "existing vision."
        ),
        "answer_km": (
            "ទៅកាន់បញ្ជីគម្រោងរបស់អ្នក អូសជួរគម្រោងទៅឆ្វេងហើយជ្រើស Delete — "
            "ឬចុចសង្កត់លើជួរសម្រាប់ម៉ឺនុយដូចគ្នា។ ការលុបគឺអចិន្ត្រៃយ៍ ; "
            "ទស្សនៈដែលបានបង្កើត និងរូបថតដើមសម្រាប់គម្រោងនោះត្រូវបានដក។ "
            "បើអ្នកគ្រាន់តែចង់ចាប់ផ្តើមទិសដៅថ្មីដោយមិនបាត់បង់ទស្សនៈចាស់ "
            "សូមបំបែកមែកពីទស្សនៈដែលមានស្រាប់ណាមួយជំនួសវិញ។"
        ),
    },

    "rename_project": {
        "category": "feature",
        "patterns_en": [
            r"\b(how\s+(do|can)\s+i\s+)?rename\s+(a\s+|my\s+|this\s+)?(project|session|design)\b",
            r"\bchange\s+(the\s+)?(name|title)\s+of\b",
            r"\bedit\s+(the\s+)?project\s+name\b",
        ],
        "patterns_km": [
            r"ប្តូរ\s*ឈ្មោះ\s*គម្រោង",
            r"កែ\s*ឈ្មោះ",
        ],
        "answer_en": (
            "Tap the project title at the top of the chat screen — a small "
            "pencil icon sits next to it. Type the new name and confirm. The "
            "rename applies immediately and survives an app restart. Names "
            "are local to your device for now ; nothing is published or "
            "shared by renaming."
        ),
        "answer_km": (
            "ចុចលើចំណងជើងគម្រោងនៅខាងលើអេក្រង់ chat — រូបតំណាងខ្មៅដៃតូចមួយ "
            "នៅជាប់នឹងវា។ វាយឈ្មោះថ្មីហើយបញ្ជាក់។ ការប្តូរឈ្មោះអនុវត្តភ្លាមៗ "
            "និងរស់រានពីការចាប់ផ្តើមកម្មវិធីឡើងវិញ។ ឈ្មោះគឺនៅក្នុងឧបករណ៍របស់អ្នក "
            "សម្រាប់ពេលឥឡូវ ; គ្មានអ្វីត្រូវបានចេញផ្សាយឬចែករំលែកដោយការប្តូរឈ្មោះទេ។"
        ),
    },

    "session_restore": {
        "category": "feature",
        "patterns_en": [
            r"\bdoes\s+(the\s+)?app\s+remember\b",
            r"\bsession\s+(restore|save|persist|survive)\b",
            r"\b(lose|lost)\s+(my|the)\s+(work|session|design)\b",
            r"\bcome\s+back\s+later\b",
        ],
        "patterns_km": [
            r"រក្សា\s*ទុក\s*សម័យ",
            r"ត្រឡប់\s*មក\s*វិញ",
        ],
        "answer_en": (
            "Your project — room type, atmosphere, every vision generated, "
            "the chat — survives app restarts and device reboots. When you "
            "come back, your most recent project opens automatically and you "
            "can keep refining from where you left off. Each project is "
            "stored on your device, so closing the app mid-generation is "
            "safe."
        ),
        "answer_km": (
            "គម្រោងរបស់អ្នក — ប្រភេទបន្ទប់ បរិយាកាស រាល់ទស្សនៈដែលបានបង្កើត chat — "
            "រស់រានពីការចាប់ផ្តើមកម្មវិធីឡើងវិញនិងការចាប់ផ្តើមឧបករណ៍ឡើងវិញ។ "
            "ពេលអ្នកត្រឡប់មកវិញ គម្រោងថ្មីបំផុតរបស់អ្នកនឹងបើកដោយស្វ័យប្រវត្តិ "
            "ហើយអ្នកអាចបន្តកែលម្អពីកន្លែងដែលអ្នកឈប់។ "
            "គម្រោងនីមួយៗត្រូវបានរក្សាទុកនៅឧបករណ៍របស់អ្នក ដូច្នេះការបិទកម្មវិធី "
            "កណ្ដាលនៃការបង្កើតគឺមានសុវត្ថិភាព។"
        ),
    },

    "voice_input": {
        "category": "feature",
        "patterns_en": [
            r"\b(can\s+i\s+)?(use\s+)?voice\s+(input|dictation|control)\b",
            r"\bspeak\s+(to|my\s+brief)\b",
            r"\bdictate\s+(the\s+)?brief\b",
            r"\bmicrophone\b",
        ],
        "patterns_km": [
            r"និយាយ\s*ដោយ\s*សំឡេង",
            r"មីក្រូ\s*ហ្វូន",
        ],
        "answer_en": (
            "Tap the microphone icon in the brief field and dictate naturally "
            "in English or Khmer. The system transcribes and feeds your words "
            "to the next generation as if you typed them. Useful when you're "
            "describing a complex change and don't want to thumb-type — "
            "\"open the kitchen wall, keep the glazing, push toward Japandi "
            "calm.\""
        ),
        "answer_km": (
            "ចុចលើរូបតំណាងមីក្រូហ្វូននៅក្នុងវាលសារ ហើយនិយាយដោយធម្មជាតិ "
            "ជាភាសាអង់គ្លេសឬខ្មែរ។ ប្រព័ន្ធនឹងសរសេរចម្លងហើយផ្ញើពាក្យរបស់អ្នក "
            "ទៅការបង្កើតបន្ទាប់ ដូចជាអ្នកវាយវាដោយខ្លួនឯង។ មានប្រយោជន៍ "
            "នៅពេលអ្នកពិពណ៌នាការផ្លាស់ប្តូរស្មុគស្មាញហើយមិនចង់វាយដោយមេដៃ — "
            "\"បើកជញ្ជាំងផ្ទះបាយ រក្សាកញ្ចក់ ផ្លាស់ទៅ Japandi calm\"។"
        ),
    },

    "generation_workflow": {
        "category": "feature",
        "patterns_en": [
            r"\bhow\s+(does|do)\s+generation\s+work\b",
            r"\bwhat\s+happens\s+when\s+i\s+(tap|press)\s+generate\b",
            r"\bgeneration\s+pipeline\b",
            r"\bhow\s+long\s+does\s+(it|generation)\s+take\b",
        ],
        "patterns_km": [
            r"តើ\s*ការ\s*បង្កើត",
            r"យូរ\s*ប៉ុណ្ណា",
        ],
        "answer_en": (
            "When you tap Generate, your photo plus the brief and atmosphere "
            "are sent to an image-editing model. It reads your space's "
            "architecture, applies the chosen atmosphere as a material and "
            "lighting language, and returns a new vision. Typical wait is "
            "about a minute. The architectural anchors are preserved across "
            "generations so the result stays recognisable as your space."
        ),
        "answer_km": (
            "ពេលអ្នកចុច Generate រូបថតរបស់អ្នកជាមួយសារនិងបរិយាកាស "
            "ត្រូវបានបញ្ជូនទៅ image-editing model។ វាអានស្ថាបត្យកម្មលំនៅដ្ឋានរបស់អ្នក "
            "អនុវត្តបរិយាកាសដែលបានជ្រើសជាភាសាសម្ភារៈនិងពន្លឺ និងផ្តល់ទស្សនៈថ្មី។ "
            "ការរង់ចាំធម្មតាប្រហែលមួយនាទី។ ធាតុស្ថាបត្យកម្មត្រូវបានរក្សា "
            "ឆ្លងកាត់ការបង្កើត ដូច្នេះលទ្ធផលនៅតែស្គាល់ថាជាលំនៅដ្ឋានរបស់អ្នក។"
        ),
    },

    "edit_intent": {
        "category": "feature",
        "patterns_en": [
            r"\bcan\s+(i|you)\s+(edit|change|modify)\s+(a|the)\s+(specific|particular|certain)\b",
            r"\bedit\s+(just|only)\s+(the|one)\b",
            r"\bchange\s+only\s+the\b",
            r"\blocal\s+edit\b",
        ],
        "patterns_km": [
            r"កែ\s*ត្រឹម\s*តែ",
            r"ផ្លាស់ប្តូរ\s*ត្រឹម\s*តែ",
        ],
        "answer_en": (
            "Yes — describe the local change naturally (\"add a TV on the "
            "right wall\", \"replace the sofa with a sectional\", \"make the "
            "rug darker\"). I'll keep everything else untouched and edit only "
            "the area you described. The rest of the room, the atmosphere "
            "language, and the architectural anchors stay exactly as in the "
            "current vision."
        ),
        "answer_km": (
            "បាទ — រៀបរាប់ការផ្លាស់ប្តូរក្នុងតំបន់ដោយធម្មជាតិ (\"បន្ថែម TV "
            "នៅជញ្ជាំងស្តាំ\", \"ប្តូរសាឡុងជាមួយ sectional\", \"ធ្វើឱ្យកំរាល "
            "ងងឹតជាង\")។ ខ្ញុំនឹងរក្សាអ្វីៗផ្សេងទៀតមិនកែ និងកែតែតំបន់ដែលអ្នករៀបរាប់។ "
            "ផ្នែកនៅសល់នៃបន្ទប់ ភាសាបរិយាកាស និងធាតុស្ថាបត្យកម្ម "
            "នៅដដែលដូចក្នុងទស្សនៈបច្ចុប្បន្ន។"
        ),
    },

    "save_image": {
        "category": "feature",
        "patterns_en": [
            r"\b(how\s+(do|can)\s+i\s+)?save\s+(a\s+|the\s+|my\s+)?(image|vision|design|render)\b",
            r"\bdownload\s+(a\s+|the\s+|my\s+)?(image|vision|design)\b",
            r"\bexport\s+(the\s+|a\s+)?(image|vision)\b",
        ],
        "patterns_km": [
            r"រក្សា\s*ទុក\s*រូប\s*ភាព",
            r"ទាញ\s*យក",
        ],
        "answer_en": (
            "Tap the download icon at the top of the reveal screen, or long-"
            "press a vision in the chat timeline and choose Save. The image "
            "lands in your device's photo library. The AI VISION saves at "
            "high resolution ; the side-by-side comparison saves as a single "
            "wider image you can post directly."
        ),
        "answer_km": (
            "ចុចលើរូបតំណាងទាញយកនៅខាងលើអេក្រង់បង្ហាញ ឬចុចសង្កត់លើទស្សនៈក្នុង chat "
            "ហើយជ្រើស Save។ រូបភាពនឹងទៅដល់បណ្ណាល័យរូបថតនៃឧបករណ៍របស់អ្នក។ "
            "AI VISION រក្សាទុកដោយគុណភាពខ្ពស់ ; ការប្រៀបធៀបចំហៀង "
            "រក្សាទុកជារូបភាពធំទូលាយមួយដែលអ្នកអាចបង្ហោះដោយផ្ទាល់។"
        ),
    },

    "supported_room_types": {
        "category": "feature",
        "patterns_en": [
            r"\bwhat\s+(rooms?|spaces?)\s+(can|do)\s+you\s+(do|support|handle)\b",
            r"\bwhich\s+(rooms?|spaces?)\b",
            r"\bsupported\s+(rooms?|spaces?)\b",
        ],
        "patterns_km": [
            r"បន្ទប់\s*អ្វី\s*ខ្លះ",
            r"គាំទ្រ\s*បន្ទប់",
        ],
        "answer_en": (
            "I work with living rooms, bedrooms, kitchens, bathrooms, dining "
            "rooms, home offices, hallways, balconies, gardens, pool areas "
            "and house facades. The atmosphere translation is calibrated per "
            "room type — Soft Luxury in a bedroom reads differently from Soft "
            "Luxury in a living room, by design."
        ),
        "answer_km": (
            "ខ្ញុំធ្វើការជាមួយបន្ទប់ទទួលភ្ញៀវ បន្ទប់គេង ផ្ទះបាយ បន្ទប់ទឹក "
            "បន្ទប់ទទួលទាន ការិយាល័យក្នុងផ្ទះ ច្រកដើរ យាន ឧទ្យាន អាងហែលទឹក "
            "និងផ្នែកមុខផ្ទះ។ ការបកប្រែបរិយាកាសត្រូវបានសម្រួលតាមប្រភេទបន្ទប់ — "
            "Soft Luxury ក្នុងបន្ទប់គេងអានខុសពី Soft Luxury "
            "ក្នុងបន្ទប់ទទួលភ្ញៀវ ដោយចេតនា។"
        ),
    },
}


# ── Support topics (6) ───────────────────────────────────────────────────────
# Triggered when intent_classifier returns SUPPORT. These never trigger
# a generation. Most route the user toward concrete recovery actions
# (retry, screenshot, contact channel) rather than vague reassurance.

_SUPPORT_TOPICS: dict[str, dict] = {
    "support_contact": {
        "category": "support",
        "patterns_en": [
            r"\b(how\s+(do|can)\s+i\s+)?contact\s+(support|the\s+team|you)\b",
            r"\b(reach|email)\s+(support|the\s+team)\b",
            r"\bcustomer\s+service\b",
            r"\bget\s+help\b",
        ],
        "patterns_km": [
            r"ទាក់ទង\s*ការ\s*គាំទ្រ",
            r"ទាក់ទង\s*ក្រុម",
        ],
        "answer_en": (
            "The fastest channel is the feedback option in the app menu — it "
            "captures your project context automatically so the team can "
            "diagnose without back-and-forth. For anything urgent during the "
            "Cambodia launch window, send a screenshot and a short "
            "description ; the team responds within a working day."
        ),
        "answer_km": (
            "ឆានែលលឿនបំផុតគឺជម្រើសផ្តល់យោបល់ក្នុងម៉ឺនុយកម្មវិធី — "
            "វាចាប់យកបរិបទគម្រោងរបស់អ្នកដោយស្វ័យប្រវត្តិ ដូច្នេះក្រុមអាចធ្វើរោគវិនិច្ឆ័យ "
            "ដោយមិនមានការផ្ញើទៅមកច្រើន។ សម្រាប់រឿងបន្ទាន់ក្នុងពេលបើកដំណើរការ "
            "នៅកម្ពុជា ផ្ញើ screenshot និងការពិពណ៌នាខ្លី ; ក្រុមនឹងឆ្លើយតប "
            "ក្នុងពេលមួយថ្ងៃធ្វើការ។"
        ),
    },

    "support_report_issue": {
        "category": "support",
        "patterns_en": [
            r"\b(report|file)\s+(a\s+|an\s+)?(bug|issue|problem)\b",
            r"\bsomething\s+is\s+(wrong|broken)\b",
            r"\bfound\s+(a\s+)?bug\b",
        ],
        "patterns_km": [
            r"រាយការណ៍\s*(បញ្ហា|កំហុស)",
            r"មាន\s*អ្វី\s*ខុស",
        ],
        "answer_en": (
            "Use the feedback option in the app menu and start the message "
            "with **BUG** — that flags it for the engineering channel. A "
            "screenshot of the affected screen plus a one-line description "
            "of what you expected vs what you saw is usually enough for the "
            "team to reproduce."
        ),
        "answer_km": (
            "ប្រើជម្រើសផ្តល់យោបល់ក្នុងម៉ឺនុយកម្មវិធី ហើយចាប់ផ្តើមសារដោយ **BUG** — "
            "វាសម្គាល់វាសម្រាប់ឆានែលវិស្វកម្ម។ Screenshot នៃអេក្រង់ដែលរងផលប៉ះពាល់ "
            "ជាមួយការពិពណ៌នាមួយបន្ទាត់នៃអ្វីដែលអ្នករំពឹងទុកធៀបនឹងអ្វីដែលអ្នកឃើញ "
            "ជាធម្មតាគ្រប់គ្រាន់សម្រាប់ក្រុមដើម្បីផលិតឡើងវិញ។"
        ),
    },

    "support_feedback": {
        "category": "support",
        "patterns_en": [
            r"\b(give|send|share|leave)\s+(my\s+)?feedback\b",
            r"\bsuggest(ion)?\s+(a\s+)?(feature|improvement)\b",
            r"\bfeature\s+request\b",
        ],
        "patterns_km": [
            r"ផ្តល់\s*យោបល់",
            r"សុំ\s*មុខងារ",
        ],
        "answer_en": (
            "Open the feedback option in the app menu and write freely — what "
            "you'd want the architect to do better, what features would help, "
            "which atmospheres feel off. The team reads every entry before "
            "the next product wave is shaped, so concrete examples (a "
            "specific room, a specific atmosphere) carry the most weight."
        ),
        "answer_km": (
            "បើកជម្រើសផ្តល់យោបល់ក្នុងម៉ឺនុយកម្មវិធី ហើយសរសេរដោយសេរី — "
            "អ្វីដែលអ្នកចង់ឱ្យស្ថាបនិកធ្វើបានល្អជាង មុខងារអ្វីដែលនឹងជួយ "
            "បរិយាកាសណាមួយដែលមិនត្រូវ។ ក្រុមអានរាល់ការបញ្ចូលមុនការរូបរាងផលិតផល "
            "បន្ទាប់ ដូច្នេះឧទាហរណ៍ជាក់លាក់ (បន្ទប់ជាក់លាក់ បរិយាកាសជាក់លាក់) "
            "ផ្ទុកទម្ងន់ច្រើនបំផុត។"
        ),
    },

    "support_generation_failed": {
        "category": "support",
        "patterns_en": [
            r"\bgeneration\s+failed\b",
            r"\b(image|render|design)\s+(failed|didn'?t\s+(work|load|generate))\b",
            r"\bcan'?t\s+generate\b",
            r"\berror\s+(generating|when\s+(i\s+)?(tap|press))\b",
        ],
        "patterns_km": [
            r"ការ\s*បង្កើត\s*បរាជ័យ",
            r"មិន\s*អាច\s*បង្កើត",
            # Wave 4.11c — mixed EN+KM "Generate មិនដំណើរការ" and pure-KM
            # generation-broken phrasings.
            r"(generate|render|create)\s*មិន\s*(ដំណើរការ|ដំណើរ)",
            r"បង្កើត.*មិន\s*(ដំណើរការ|បាន|សម្រេច)",
        ],
        "answer_en": (
            "Try Generate once more — most failures resolve on a single retry "
            "(model timeout, network blip). If it fails a second time, the "
            "issue is usually one of : the source photo is very low "
            "resolution or rotated, the brief is empty or extremely long, or "
            "the device's network is unstable. If retry doesn't help, send a "
            "screenshot via feedback."
        ),
        "answer_km": (
            "សាកល្បង Generate ម្តងទៀត — បរាជ័យភាគច្រើនត្រូវបានដោះស្រាយ "
            "នៅពេលព្យាយាមឡើងវិញ (model timeout, បណ្តាញ)។ បើបរាជ័យជាលើកទីពីរ "
            "បញ្ហាជាធម្មតាគឺមួយក្នុងចំណោម : រូបថតដើមមានគុណភាពទាប ឬត្រូវបានបង្វិល "
            "សារទទេឬវែងពេក ឬបណ្តាញនៃឧបករណ៍មិនមានស្ថេរភាព។ "
            "បើព្យាយាមឡើងវិញមិនជួយ ផ្ញើ screenshot តាមរយៈផ្តល់យោបល់។"
        ),
    },

    "support_image_not_loading": {
        "category": "support",
        "patterns_en": [
            r"\b(image|photo|render|vision)\s+(not|isn'?t)\s+loading\b",
            r"\bcan'?t\s+see\s+(the\s+|my\s+)?(image|render)\b",
            r"\b(image|render)\s+(stuck|blank|missing)\b",
        ],
        "patterns_km": [
            r"រូប\s*ភាព\s*មិន\s*ដំណើរ",
            r"មិន\s*ឃើញ\s*រូប",
            # Wave 4.11c — "image / picture not showing/loading/appearing".
            r"រូប(ភាព)?\s*មិន\s*(បង្ហាញ|ផ្ទុក|ដំណើរ|ដើរ|ចេញ)",
            r"(image|photo|picture|vision)\s*មិន\s*(បង្ហាញ|ផ្ទុក|ដំណើរ)",
        ],
        "answer_en": (
            "Pull down on the chat screen to refresh, or close and reopen the "
            "project. If the image still won't load, your network may be the "
            "issue — try switching from cellular to Wi-Fi (or vice versa). "
            "Generated visions are stored on a CDN and need an active "
            "connection to display the first time ; after loading once they "
            "cache locally."
        ),
        "answer_km": (
            "អូសចុះក្រោមលើអេក្រង់ chat ដើម្បីធ្វើឱ្យឡើងវិញ ឬបិទនិងបើកគម្រោងឡើងវិញ។ "
            "បើរូបភាពនៅតែមិនអាចផ្ទុក បណ្តាញរបស់អ្នកអាចជាបញ្ហា — សាកល្បងប្តូរ "
            "ពីបណ្តាញចល័តទៅ Wi-Fi (ឬផ្ទុយមកវិញ)។ ទស្សនៈដែលបានបង្កើតត្រូវបានរក្សា "
            "ទុកលើ CDN ហើយត្រូវការការតភ្ជាប់សកម្មដើម្បីបង្ហាញលើកដំបូង ; "
            "បន្ទាប់ពីផ្ទុកម្តង វាខាស់នៅក្នុងឧបករណ៍។"
        ),
    },

    "support_app_issue": {
        "category": "support",
        "patterns_en": [
            r"\bapp\s+(crash|froze|frozen|hang|stuck|not\s+(working|responding))\b",
            r"\b(force\s+)?close\s+(the\s+)?app\b",
            r"\brestart\s+(the\s+)?app\b",
        ],
        "patterns_km": [
            r"កម្មវិធី\s*(បិទ|គាំង|ផ្អាក)",
        ],
        "answer_en": (
            "Force-close the app and reopen it ; your work is auto-saved so "
            "nothing is lost. If the freeze keeps happening, restarting the "
            "device clears anything held in memory. Send a screenshot via "
            "feedback if it persists — the team can read the crash signature "
            "from the device logs."
        ),
        "answer_km": (
            "បង្ខំបិទកម្មវិធីហើយបើកវាឡើងវិញ ; ការងាររបស់អ្នកត្រូវបានរក្សាទុក "
            "ដោយស្វ័យប្រវត្តិ ដូច្នេះគ្មានអ្វីបាត់បង់។ បើការផ្អាកនៅតែបន្ត "
            "ការចាប់ផ្តើមឧបករណ៍ឡើងវិញសម្អាតអ្វីៗដែលរក្សាក្នុងអង្គចងចាំ។ "
            "ផ្ញើ screenshot តាមរយៈផ្តល់យោបល់បើវានៅតែបន្ត — "
            "ក្រុមអាចអានហត្ថលេខាគាំងពី device logs។"
        ),
    },
}


# ── Billing & subscription topics (2) ────────────────────────────────────────
# Phase 1 placeholder copy — billing/subscription infrastructure ships in a
# later wave. Answers redirect to the support channel rather than promise
# pricing that may shift before Cambodia launch.

_BILLING_TOPICS: dict[str, dict] = {
    "billing": {
        "category": "billing",
        "patterns_en": [
            r"\bhow\s+(much|do\s+i\s+pay)\b",
            r"\bcost\b",
            r"\bbilling\b",
            r"\bpaid\s+(plan|feature|tier)\b",
            r"\bpayment\b",
            r"\bprice\b",
        ],
        "patterns_km": [
            r"តម្លៃ",
            r"តើ\s*ថ្លៃ",
            r"ការ\s*បង់\s*ប្រាក់",
        ],
        "answer_en": (
            "Pricing details are being finalized for the Cambodia launch. "
            "Until then, your access during preview is free. If you'd like to "
            "register early-access interest or hear when subscription tiers "
            "go live, use the feedback option in the app menu."
        ),
        "answer_km": (
            "ព័ត៌មានលម្អិតអំពីតម្លៃកំពុងត្រូវបានបញ្ចប់សម្រាប់ការបើកដំណើរការនៅកម្ពុជា។ "
            "រហូតទាល់តែពេលនោះ ការចូលប្រើរបស់អ្នកក្នុងការមើលជាមុនគឺឥតគិតថ្លៃ។ "
            "បើអ្នកចង់ចុះឈ្មោះចំណាប់អារម្មណ៍ការចូលប្រើដំបូង "
            "ឬដឹងពេលដំណាក់កាលជាវរស់នៅ សូមប្រើជម្រើសផ្តល់យោបល់ក្នុងម៉ឺនុយកម្មវិធី។"
        ),
    },

    "subscription": {
        "category": "billing",
        "patterns_en": [
            r"\b(how\s+(do|can)\s+i\s+)?(cancel|unsubscribe|stop)\s+(my\s+)?subscription\b",
            r"\bsubscription\s+(work|plan|cost)\b",
            r"\bhow\s+does\s+(the\s+)?subscription\b",
            r"\bmonthly\s+plan\b",
        ],
        "patterns_km": [
            r"ការ\s*ជាវ",
            r"បោះ\s*បង់\s*ជាវ",
        ],
        "answer_en": (
            "The subscription model is still being shaped ahead of the "
            "Cambodia launch. Right now you have full preview access without "
            "a plan. Once subscription tiers ship, you'll see the options in "
            "your profile screen with clear pricing in Khmer Riel and US "
            "Dollar."
        ),
        "answer_km": (
            "គំរូការជាវនៅតែកំពុងត្រូវបានរូបរាងមុនពេលបើកដំណើរការនៅកម្ពុជា។ "
            "ឥឡូវនេះអ្នកមានការចូលប្រើពេញលេញនៃការមើលជាមុនដោយគ្មានគម្រោង។ "
            "ពេលដំណាក់កាលជាវដឹក អ្នកនឹងឃើញជម្រើសក្នុងអេក្រង់ប្រវត្តិរូប "
            "ជាមួយតម្លៃច្បាស់លាស់ជារៀលនិងដុល្លារអាមេរិក។"
        ),
    },
}


# ── Meta topics (2) ──────────────────────────────────────────────────────────
# "Who/what are you" + "how does the AI work" framed in architect voice.

_META_TOPICS: dict[str, dict] = {
    "meta_who_are_you": {
        "category": "meta",
        "patterns_en": [
            r"\bwho\s+are\s+you\b",
            r"\bwhat\s+are\s+you\b",
            r"\bare\s+you\s+(an?\s+)?(architect|ai|human|bot)\b",
            r"\byour\s+name\b",
        ],
        "patterns_km": [
            r"អ្នក\s*ជា\s*អ្នក\s*ណា",
            r"អ្នក\s*ជា\s*អ្វី",
        ],
        "answer_en": (
            "I'm your AI architect — a design companion trained to read "
            "photographed spaces and translate atmospheres (Warm Modern, "
            "Japandi Calm, Soft Luxury and others) onto your room while "
            "preserving its real architecture. I work alongside you : you "
            "bring the photo and the intent, I bring the spatial reading and "
            "the material palette."
        ),
        "answer_km": (
            "ខ្ញុំជា AI architect របស់អ្នក — ដៃគូរចនាដែលត្រូវបានបណ្តុះបណ្តាល "
            "អានកន្លែងដែលថត និងបកប្រែបរិយាកាស (Warm Modern, Japandi Calm, "
            "Soft Luxury និងផ្សេងទៀត) ទៅលើបន្ទប់របស់អ្នក "
            "ដោយរក្សាស្ថាបត្យកម្មពិតរបស់វា។ ខ្ញុំធ្វើការជាមួយអ្នក : "
            "អ្នកនាំរូបថត និងបំណង ខ្ញុំនាំការអាននិងសម្ភារៈ។"
        ),
    },

    "meta_how_ai_works": {
        "category": "meta",
        "patterns_en": [
            r"\bhow\s+(does|do)\s+(the\s+)?ai\s+work\b",
            r"\bhow\s+(does|do)\s+you\s+(work|think|generate)\b",
            r"\bwhat\s+(model|technology)\b",
            r"\bunder\s+the\s+hood\b",
        ],
        "patterns_km": [
            r"AI\s*ដំណើរ\s*ការ",
            r"តើ\s*អ្នក\s*ដំណើរ\s*ការ",
        ],
        "answer_en": (
            "Two layers cooperate. A vision pass reads your photo's "
            "architecture — windows, openings, ceiling, depth — and locks "
            "that as a structural anchor. An image-editing model then "
            "re-composes materials, furniture, lighting and decor according "
            "to the atmosphere and your brief, while staying inside the "
            "anchored architecture. The architectural reading carries across "
            "every iteration so refinements stay consistent with your space."
        ),
        "answer_km": (
            "ស្រទាប់ពីរធ្វើការសហការ។ វគ្គ vision អានស្ថាបត្យកម្មនៃរូបថត — "
            "បង្អួច បើកចំហ ពិដាន ជម្រៅ — និងចាក់សោវាជាធាតុស្ថាបត្យកម្ម។ "
            "បន្ទាប់មក image-editing model តែងសម្ភារៈ គ្រឿងសង្ហារឹម ពន្លឺ និងតុបតែង "
            "ឡើងវិញ តាមបរិយាកាសនិងសារ ដោយនៅខាងក្នុងស្ថាបត្យកម្មដែលបានចាក់សោ។ "
            "ការអានស្ថាបត្យកម្មបន្តឆ្លងកាត់រាល់ការរុករក ដូច្នេះការកែលម្អនៅជាមួយ "
            "កន្លែងរបស់អ្នក។"
        ),
    },
}


# ── Misc topics (3) ──────────────────────────────────────────────────────────
# Data privacy, Cambodia localisation context, the iteration concept.

_MISC_TOPICS: dict[str, dict] = {
    "data_privacy": {
        "category": "misc",
        "patterns_en": [
            r"\bdata\s+privacy\b",
            r"\bis\s+(my|the)\s+(data|photo|image)\s+(private|secure|safe)\b",
            r"\bwhat\s+do\s+you\s+do\s+with\s+my\s+(data|photo)\b",
            r"\bare\s+my\s+photos?\s+(stored|shared|public)\b",
        ],
        "patterns_km": [
            r"ឯកជនភាព",
            r"ទិន្នន័យ\s*របស់\s*ខ្ញុំ",
        ],
        "answer_en": (
            "Your photo is used to generate visions for your project and is "
            "stored alongside your project on your device. Generated images "
            "are stored on a CDN tied to your project session. Nothing is "
            "shared publicly or used to train any third-party model. You can "
            "delete a project at any time, which removes its photo and "
            "generated visions."
        ),
        "answer_km": (
            "រូបថតរបស់អ្នកត្រូវបានប្រើដើម្បីបង្កើតទស្សនៈសម្រាប់គម្រោងរបស់អ្នក "
            "និងត្រូវបានរក្សាទុកជាមួយគម្រោងនៅឧបករណ៍របស់អ្នក។ រូបភាពដែលបានបង្កើត "
            "ត្រូវបានរក្សាទុកលើ CDN ដែលភ្ជាប់ទៅសម័យគម្រោងរបស់អ្នក។ គ្មានអ្វី "
            "ត្រូវបានចែករំលែកជាសាធារណៈ ឬប្រើដើម្បីបណ្តុះបណ្តាល model របស់ភាគីទីបី។ "
            "អ្នកអាចលុបគម្រោងណាមួយពេលណាក៏បាន ដែលនឹងដករូបថត "
            "និងទស្សនៈដែលបានបង្កើត។"
        ),
    },

    "cambodia_localization": {
        "category": "misc",
        "patterns_en": [
            r"\b(do\s+you\s+speak|in)\s+khmer\b",
            r"\bcambodia(n)?\b",
            r"\blocal(iz|is)ation\b",
        ],
        "patterns_km": [
            r"ភាសា\s*ខ្មែរ",
            r"កម្ពុជា",
        ],
        "answer_en": (
            "Yes — write or speak to me in Khmer or English and I'll match "
            "your language for product questions and clarifications. The "
            "atmosphere library and architectural critique are currently in "
            "English ; Khmer expansion of that vocabulary is on the roadmap "
            "for the next wave."
        ),
        "answer_km": (
            "បាទ — សរសេរឬនិយាយជាមួយខ្ញុំជាភាសាខ្មែរឬអង់គ្លេស ហើយខ្ញុំនឹងផ្គូផ្គង "
            "ភាសារបស់អ្នកសម្រាប់សំណួរផលិតផលនិងការបញ្ជាក់។ បណ្ណាល័យបរិយាកាស "
            "និងការវាយតម្លៃស្ថាបត្យកម្មបច្ចុប្បន្នជាភាសាអង់គ្លេស ; "
            "ការពង្រីកវាក្យសព្ទនោះជាខ្មែរស្ថិតនៅលើផែនទីផ្លូវសម្រាប់ wave បន្ទាប់។"
        ),
    },

    "iteration_concept": {
        "category": "misc",
        "patterns_en": [
            r"\bwhat\s+(is|does)\s+(an?\s+)?iteration\b",
            r"\b(v1|v2|v3|version\s+\d)\b",
            r"\biteration\s+(mean|work)\b",
        ],
        "patterns_km": [
            r"តើ\s*ការ\s*រុករក",
            r"iteration",
        ],
        "answer_en": (
            "Each time you tap Generate, a new iteration is born. V1 is the "
            "first vision off your original photo. V2 evolves from V1, V3 "
            "from V2, and so on — every iteration carries the architectural "
            "anchors forward so the space stays recognisable while the "
            "design language deepens. You can branch sideways from any "
            "iteration at any time."
        ),
        "answer_km": (
            "រាល់ពេលអ្នកចុច Generate ការរុករកថ្មីត្រូវបានកើត។ V1 គឺជាទស្សនៈដំបូង "
            "ពីរូបថតដើមរបស់អ្នក។ V2 វិវឌ្ឍន៍ពី V1 V3 ពី V2 ហើយដូច្នេះទៅ — "
            "រាល់ការរុករកនាំធាតុស្ថាបត្យកម្មទៅមុខ ដូច្នេះកន្លែងនៅតែស្គាល់ "
            "ខណៈពេលដែលភាសារចនាជម្រៅ។ អ្នកអាចបំបែកមែកពីការរុករកណាមួយ "
            "ពេលណាក៏បាន។"
        ),
    },
}


# ── Single Source-of-Truth registry ──────────────────────────────────────────
# All four sub-dicts merge here. Public API reads from _PRODUCT_KB only ; the
# sub-dicts are an authoring convenience.

_PRODUCT_KB: dict[str, dict] = {
    **_FEATURE_TOPICS,
    **_SUPPORT_TOPICS,
    **_BILLING_TOPICS,
    **_META_TOPICS,
    **_MISC_TOPICS,
}


# ── Pattern compilation cache ────────────────────────────────────────────────
# Compile lazily on first call ; reused across all subsequent calls.

_COMPILED_PATTERNS: dict[str, dict[str, list[re.Pattern]]] = {}


def _compiled_for(topic_id: str, language: str) -> list[re.Pattern]:
    """Compile patterns once per (topic, language) and cache."""
    if topic_id not in _COMPILED_PATTERNS:
        _COMPILED_PATTERNS[topic_id] = {}
    cache = _COMPILED_PATTERNS[topic_id]
    if language not in cache:
        topic = _PRODUCT_KB.get(topic_id, {})
        raw = topic.get(f"patterns_{language}", [])
        cache[language] = [re.compile(p, re.IGNORECASE) for p in raw]
    return cache[language]


# ── Public API ───────────────────────────────────────────────────────────────

def detect_product_help(message: str, language: str = "en") -> Optional[str]:
    """
    Try to match a product topic from the user's message.

    Iterates topics in registry order, returning the first topic_id whose
    pattern matches. Pattern lists are language-specific ; if `language` is
    not "en" or "km", falls back to English.

    Returns None when no topic matches. Caller (main.py) then routes the
    message through the existing intent classifier path.

    Performance : compiled regex cache + early return on first match ;
    typical cost <1 ms for the full 30-topic scan.
    """
    if not message:
        return None
    lang = language if language in ("en", "km") else "en"
    for topic_id in _PRODUCT_KB:
        for pattern in _compiled_for(topic_id, lang):
            if pattern.search(message):
                return topic_id
    return None


def get_product_answer(topic_id: str, language: str = "en") -> str:
    """
    Return the architect-voice answer for a topic in the requested language.

    If the Khmer answer is missing for any reason, falls back to the English
    answer rather than returning an empty string — better to answer in EN
    than to silence the architect.

    Raises KeyError if topic_id is not in the registry (caller bug, not user
    bug — should never happen if topic_id came from detect_product_help).
    """
    topic = _PRODUCT_KB[topic_id]
    if language == "km":
        answer = topic.get("answer_km") or topic.get("answer_en", "")
    else:
        answer = topic.get("answer_en", "")
    return answer


def is_product_query(message: str, language: str = "en") -> bool:
    """
    Cheap pre-check : does this message look like a product question?

    Used by main.py /chat to decide whether to run the full topic scan or
    skip straight to the standard intent classifier path. Returns True on
    common product question shapes ("how do I", "what is", "can I",
    "where is", "តើ" Khmer interrogative, etc.) and on support keywords.

    A True result does NOT guarantee detect_product_help() will match —
    just that the message warrants the scan. False = skip the scan.
    """
    if not message:
        return False
    lang = language if language in ("en", "km") else "en"
    if lang == "en":
        cheap = (
            "how do i", "how can i", "how does", "how do you", "how is",
            "what is", "what does", "what are",
            "where is", "where are", "where do",
            "can i ", "can you ",
            "why did", "why is", "why does",
            "explain", "tell me about",
            "support", "feedback", "bug", "issue", "problem", "report",
            "failed", "not loading", "not working", "crash", "frozen",
            "billing", "subscription", "cost", "price",
            "preserve mode", "atmosphere", "branching", "iteration",
            "rename", "delete",
        )
        low = message.lower()
        return any(token in low for token in cheap)
    if lang == "km":
        cheap_km = (
            "តើ", "យ៉ាង", "អ្វី", "ហេតុ", "ប៉ុណ្ណា",
            "ការគាំទ្រ", "បញ្ហា", "កំហុស", "បរាជ័យ",
            "តម្លៃ", "ការជាវ", "បរិយាកាស", "បន្ត",
            "លុប", "ប្តូរឈ្មោះ",
        )
        return any(token in message for token in cheap_km)
    return False


def list_topics(category: Optional[str] = None) -> list[str]:
    """
    Return all topic IDs, optionally filtered by category.

    Categories : "feature", "support", "billing", "meta", "misc".
    Useful for tests, introspection, and for future wave additions that
    need to enumerate topics (e.g. surfacing them as suggestion chips).
    """
    if category is None:
        return list(_PRODUCT_KB.keys())
    return [
        tid for tid, topic in _PRODUCT_KB.items()
        if topic.get("category") == category
    ]


def get_topic(topic_id: str) -> ProductTopic:
    """
    Typed accessor for tests / structured callers. Raises KeyError if the
    topic_id is unknown.
    """
    raw = _PRODUCT_KB[topic_id]
    return ProductTopic(
        topic_id=topic_id,
        category=raw.get("category", "misc"),
        answer_en=raw.get("answer_en", ""),
        answer_km=raw.get("answer_km", ""),
    )
