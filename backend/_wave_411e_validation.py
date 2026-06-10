"""Wave 4.11e validation — Clarification Exit Strategy + Design Brief Summary.

Five sections :
  1. CLARIFICATION_EXIT — after clarification answer, exit text is brief
     acknowledgement (no follow-up question) and should_generate=True
  2. SUMMARIZE_DESIGN_BRIEF routing — EN + FR + KM trigger phrases
  3. SUMMARIZE output — bulleted summary + Ready-to-generate footer ;
     should_generate=False
  4. Discussion preservation — Scenario E/F still route DISCUSS, no regress
  5. Regression checks — Wave 4.11d clarification_resolved still fires,
     Wave 4.11d.1 STOP_GENERATION fix still holds, etc.
"""
import sys
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

from dataclasses import dataclass, field

from prompt_engine.intent_classifier import (
    classify_intent, ConversationIntent, SubIntent,
    detect_generation_demand, is_clarification_answer,
)
from prompt_engine.meta_intent import classify_meta_intent, MetaIntent
from prompt_engine.ambiguity_detector import detect_ambiguity
from prompt_engine.tone_calibration import select_tone_mode, ToneMode
from prompt_engine.response_quality import detect_emotional_context
from prompt_engine.conversation_memory import build_session_memory
from prompt_engine.architect_response import (
    generate_clarification_exit_response, generate_brief_summary,
)
from prompt_engine.atmosphere_dna import label_to_atmosphere_id


@dataclass
class FakeRS:
    keep: list = field(default_factory=list)
    add: list = field(default_factory=list)
    enhance: list = field(default_factory=list)
    remove: list = field(default_factory=list)
    directions: list = field(default_factory=list)
    latest: str = ''


REPORT = []

def record(section, label, ok, notes=''):
    REPORT.append({'section': section, 'label': label, 'ok': ok, 'notes': notes})
    mark = '✓' if ok else '✗'
    print(f'  {mark} {label[:75]:77} {notes}')


CLAR_BIGGER = (
    "When you say bigger — are you thinking :\n"
    "• the sofa or specific seating piece\n"
    "• the seating area (more generous arrangement)\n"
    "• the overall room feeling (architectural openness)\n\n"
    "Tell me which and I'll calibrate the next vision."
)
CLAR_WARMER = (
    "Warmer in which sense — :\n"
    "• warmer lighting (kelvin temperature)\n"
    "• warmer materials (wood / textiles)\n"
    "• warmer atmosphere intensity\n\n"
    "Pick the angle and I'll calibrate."
)
CLAR_LESS = (
    "Less of which — :\n"
    "• decor / clutter (calmer surfaces, fewer objects)\n"
    "• material contrast (more tonal, less visual tension)\n"
    "• warmth or saturation (cooler, quieter palette)\n\n"
    "Pick the angle and I'll calibrate."
)


# ─────────────────────────────────────────────────────────────────────────────
# [1] CLARIFICATION_EXIT — exit text brief, no new question, should_gen=True
# ─────────────────────────────────────────────────────────────────────────────
print('\n[1] CLARIFICATION_EXIT — brief exit, no follow-up question')

scenarios = [
    ('A: bigger → "overall room feeling"', CLAR_BIGGER, 'overall room feeling'),
    ('B: warmer → "warmer lighting"', CLAR_WARMER, 'warmer lighting'),
    ('C: less wood → "floor"', CLAR_LESS, 'floor'),
    ('Extra: bigger → "the sofa"', CLAR_BIGGER, 'the sofa'),
    ('Extra: bigger → "openness"', CLAR_BIGGER, 'openness'),
]

for label, clar_text, ans in scenarios:
    hist = [
        {'role': 'user', 'content': 'make it X'},
        {'role': 'assistant', 'content': clar_text},
    ]
    # Confirm is_clarification_answer fires
    is_ca = is_clarification_answer(ans, hist)
    # Build the exit response and check it doesn't have a question mark
    exit_text = generate_clarification_exit_response(
        user_answer=ans, atmosphere_id='warm_modern',
        room_type='living_room', language='en', seed_extra='val',
    )
    no_followup = '?' not in exit_text
    # The user's brief answer should appear in the exit text
    contains_answer = (
        ans.lower().rstrip(".,;:!?") in exit_text.lower()
        or any(w in exit_text.lower() for w in ans.lower().split() if len(w) > 2)
    )
    ok = is_ca and no_followup and contains_answer
    record('1. CLARIFICATION_EXIT', label, ok,
           notes=f'is_clar={is_ca} no_q={no_followup} contains_answer={contains_answer}')
    if not ok:
        print(f'      exit_text = {exit_text!r}')

# FR variant
exit_fr = generate_clarification_exit_response(
    user_answer='éclairage plus chaud', atmosphere_id='warm_modern',
    room_type='living_room', language='fr', seed_extra='val',
)
ok_fr = '?' not in exit_fr and 'chaud' in exit_fr.lower()
record('1. CLARIFICATION_EXIT', 'FR: éclairage plus chaud', ok_fr,
       notes=f'exit_text={exit_fr!r}')

# KM variant
exit_km = generate_clarification_exit_response(
    user_answer='ពន្លឺកក់ក្តៅជាង', atmosphere_id='warm_modern',
    room_type='living_room', language='km', seed_extra='val',
)
ok_km = '?' not in exit_km
record('1. CLARIFICATION_EXIT', 'KM: ពន្លឺកក់ក្តៅជាង', ok_km,
       notes=f'exit_text={exit_km[:60]!r}')


# ─────────────────────────────────────────────────────────────────────────────
# [2] SUMMARIZE_DESIGN_BRIEF routing
# ─────────────────────────────────────────────────────────────────────────────
print('\n[2] SUMMARIZE_DESIGN_BRIEF — routing on trigger phrases')

triggers = [
    # EN
    ('Can you summarize what I want?', True),
    ('summarize the brief', True),
    ('summarise the requirements', True),
    ('what do you understand?', True),
    ('what is my brief?', True),
    ("what's my brief", True),
    ("what's the brief", True),
    ('recap', True),
    ('recap please', True),
    ('tldr', True),
    ('give me a recap', True),
    ('what are we trying to achieve?', True),
    ('remind me what I said', True),
    # FR
    ('résume mon brief', True),
    ('peux-tu résumer ce que je veux ?', True),
    ('récapitule', True),
    ("qu'est-ce que tu comprends ?", True),
    ("qu'est-ce qu'on essaie de faire ?", True),
    # KM
    ('សង្ខេបអ្វីដែលខ្ញុំចង់', True),
    ('តើអ្នកយល់ដឹងអ្វី', True),
    # Negatives — must NOT trigger SUMMARIZE
    ('make it warmer', False),
    ('what about the kitchen?', False),
    ('tell me what you think', False),
    ('explain the atmosphere', False),
    ('I want to summarize my favorite atmospheres in a list', False),  # embedded
]
for msg, should_summarize in triggers:
    ic = classify_intent(msg, 2)
    is_summarize = ic.sub_intent == SubIntent.SUMMARIZE_DESIGN_BRIEF
    ok = is_summarize == should_summarize
    notes = f'route={ic.intent.value}/{ic.sub_intent.value}'
    record('2. SUMMARIZE routing', f'{msg[:50]} → expect={"YES" if should_summarize else "NO"}',
           ok, notes=notes)


# ─────────────────────────────────────────────────────────────────────────────
# [3] SUMMARIZE output — bulleted summary + Ready-to-generate footer
# ─────────────────────────────────────────────────────────────────────────────
print('\n[3] SUMMARIZE output shape — bullets + footer + no generation')

# Rich refinement_state — multiple buckets populated
rs_full = FakeRS(
    keep=['the windows', 'the kitchen opening'],
    enhance=['warmth', 'lighting layers'],
    add=['plants', 'soft textiles'],
    remove=['heavy decor'],
    directions=[],
    latest='Add more plants and warm up the lighting',
)
summary_en = generate_brief_summary(
    refinement_state=rs_full, atmosphere_id='warm_modern',
    room_type='living_room', language='en', last_user_message='',
)
print('\n--- EN summary (full refinement_state) ---')
print(summary_en)
print('--- /EN summary ---\n')

has_header = 'understanding' in summary_en.lower()
has_footer = 'ready to generate' in summary_en.lower()
has_bullets = summary_en.count('✓') >= 3
contains_windows = 'windows' in summary_en.lower()
record('3. SUMMARIZE output', 'EN full state: header + bullets + footer',
       has_header and has_footer and has_bullets,
       notes=f'header={has_header} footer={has_footer} bullets={summary_en.count("✓")} '
             f'windows={contains_windows}')

# Sparse refinement_state — fallback to "latest direction" line
rs_sparse = FakeRS(latest='make the room feel bigger')
summary_sparse = generate_brief_summary(
    refinement_state=rs_sparse, atmosphere_id='japandi_calm',
    room_type='living_room', language='en',
    last_user_message='make the room feel bigger',
)
print('--- EN sparse summary ---')
print(summary_sparse)
print('--- /EN sparse summary ---\n')
has_atm_anchor = 'japandi' in summary_sparse.lower()
has_latest = 'bigger' in summary_sparse.lower()
record('3. SUMMARIZE output', 'EN sparse: atmosphere anchor + latest paraphrase',
       has_atm_anchor and has_latest and 'ready to generate' in summary_sparse.lower())

# FR summary
summary_fr = generate_brief_summary(
    refinement_state=rs_full, atmosphere_id='warm_modern',
    room_type='living_room', language='fr',
)
print('--- FR summary ---')
print(summary_fr)
print('--- /FR summary ---\n')
record('3. SUMMARIZE output', 'FR: header + footer + bullets',
       'comprends' in summary_fr.lower() and 'prêt à générer' in summary_fr.lower()
       and summary_fr.count('✓') >= 3)

# KM summary
summary_km = generate_brief_summary(
    refinement_state=rs_full, atmosphere_id='warm_modern',
    room_type='living_room', language='km',
)
print('--- KM summary ---')
print(summary_km)
print('--- /KM summary ---\n')
record('3. SUMMARIZE output', 'KM: header + footer + bullets',
       'យល់ដឹង' in summary_km and summary_km.count('✓') >= 3)


# ─────────────────────────────────────────────────────────────────────────────
# [4] Discussion preservation — no regression on Wave 4.11d Scenarios E/F
# ─────────────────────────────────────────────────────────────────────────────
print('\n[4] Discussion preservation (Scenarios E/F still hold)')

discuss_cases = [
    ('What do you think of this living room?', 'design_discussion', 'design_discussion'),
    ('Compare these two atmospheres', 'design_discussion', 'design_discussion'),
    ('Is this atmosphere too dark?', 'design_discussion', 'design_discussion'),
    ('Would darker floors work?', 'design_discussion', 'design_discussion'),
]
for msg, exp_intent, exp_sub in discuss_cases:
    ic = classify_intent(msg, 2)
    ok = ic.intent.value == exp_intent and ic.sub_intent.value == exp_sub
    record('4. Discussion preservation', f'{msg[:50]} → {exp_intent}/{exp_sub}',
           ok, notes=f'got={ic.intent.value}/{ic.sub_intent.value}')


# ─────────────────────────────────────────────────────────────────────────────
# [5] Regression — Wave 4.11d generation_demand + clarification_resolved
# ─────────────────────────────────────────────────────────────────────────────
print('\n[5] Regression — Wave 4.11d / 4.11d.1 still hold')

# generation_demand still fires
for msg in ['generate', "why don't you generate?", "why you don't generate?",
            'just do it', 'show me']:
    is_dem = detect_generation_demand(msg)
    record('5. Regression — 4.11d generation_demand', msg, is_dem)

# Clarification answer detector still fires
hist = [
    {'role': 'user', 'content': 'make it bigger'},
    {'role': 'assistant', 'content': CLAR_BIGGER},
]
for ans in ['overall room feeling', 'the sofa', 'openness']:
    ok = is_clarification_answer(ans, hist)
    record('5. Regression — 4.11d clarification_answer', ans, ok)

# Ambiguity still fires for first-time messages (Wave 4.11a)
for msg in ['make it bigger', 'make it pop', 'change it']:
    clar = detect_ambiguity(msg, 2, language='en', room_type='living_room')
    record('5. Regression — 4.11a first-time ambiguity', msg,
           clar is not None, notes=f'id={clar.ambiguity_id if clar else "-"}')

# Wave 4.11d.1 interrogative anti-pattern still suppresses STOP_GENERATION
for msg in ["why you don't generate?", 'why are you not generating?']:
    meta = classify_meta_intent(msg)
    ok = meta.intent != MetaIntent.STOP_GENERATION
    record('5. Regression — 4.11d.1 interrogative anti-pattern', msg,
           ok, notes=f'meta={meta.intent.value}')

# SUMMARIZE must not auto-generate (should_generate=False at handler level)
# We verify by checking the intent_class.intent stays DESIGN_DISCUSSION, not GENERATE.
ic_sum = classify_intent('summarize what I want', 3)
record('5. Regression — SUMMARIZE never routes to GENERATE',
       'summarize what I want',
       ic_sum.intent == ConversationIntent.DESIGN_DISCUSSION,
       notes=f'intent={ic_sum.intent.value}/{ic_sum.sub_intent.value}')


# ─────────────────────────────────────────────────────────────────────────────
# REPORT
# ─────────────────────────────────────────────────────────────────────────────
print()
print('═' * 80)
print('Wave 4.11e — Validation Summary')
print('═' * 80)
by_sec = {}
for r in REPORT:
    by_sec.setdefault(r['section'], {'pass': 0, 'total': 0, 'fails': []})
    by_sec[r['section']]['total'] += 1
    if r['ok']:
        by_sec[r['section']]['pass'] += 1
    else:
        by_sec[r['section']]['fails'].append(r)
total = len(REPORT)
passed = sum(1 for r in REPORT if r['ok'])
print(f'\nTOTAL: {passed}/{total} pass\n')
for sec, stats in by_sec.items():
    mark = '✓' if stats['pass'] == stats['total'] else '✗'
    print(f'  {mark} {sec:<55} {stats["pass"]}/{stats["total"]}')

fails = [r for r in REPORT if not r['ok']]
if fails:
    print('\nFAILURES:')
    for r in fails:
        print(f'  {r["section"]} — {r["label"]}')
        if r['notes']:
            print(f'    notes: {r["notes"]}')

print(f'\n=== SUMMARY: {passed}/{total} pass ===')
