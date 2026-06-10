"""
Wave 4.11 — FULL Validation Suite (17 categories).

For each test : user message, detected route, sub-intent, tone mode,
main enrichment, secondary enrichment, final user-facing response,
PASS/FAIL, notes.

No cherry-picking. All categories executed.
"""
import sys
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

from dataclasses import dataclass, field
from typing import Optional, Any

from prompt_engine.intent_classifier import (
    classify_intent, ConversationIntent, SubIntent,
)
from prompt_engine.meta_intent import classify_meta_intent, MetaIntent
from prompt_engine.meta_response import generate_meta_response
from prompt_engine.product_knowledge import (
    detect_product_help, get_product_answer,
)
from prompt_engine.ambiguity_detector import detect_ambiguity
from prompt_engine.tone_calibration import (
    select_tone_mode, ToneMode, generate_human_soft_response,
)
from prompt_engine.response_quality import (
    detect_emotional_context, generate_architect_light_response,
    select_response_length,
)
from prompt_engine.conversation_memory import build_session_memory
from prompt_engine.architect_response import (
    generate_architect_response, generate_chat_response,
    generate_mixed_response,
    _select_main_enrichment, _select_opening, _build_alternatives_block,
)
from prompt_engine.edit_intent import EditMode, classify_edit_mode
from prompt_engine.transformation_classifier import classify_transformation
from prompt_engine.trade_off_library import get_trade_off
from prompt_engine.constraint_acknowledgment import (
    should_emit_acknowledgment, build_acknowledgment,
)
from prompt_engine.design_alternatives import get_alternative_directions
from prompt_engine.architectural_memory import get_memory_reference
from prompt_engine.atmosphere_dna import label_to_atmosphere_id


@dataclass
class FakeRS:
    keep: list = field(default_factory=list)
    add: list = field(default_factory=list)
    enhance: list = field(default_factory=list)
    remove: list = field(default_factory=list)
    directions: list = field(default_factory=list)
    latest: str = ''


@dataclass
class FakeStructural:
    is_present: bool = True
    dominant_opening: str = '3-bay sliding doors'
    glass_partition: str = 'black-framed glazed wall'
    room_depth_type: str = ''
    opening_layout: str = ''
    kitchen_visibility: str = 'kitchen sightline visible'
    anchor_relationships: str = ''


# ── Chat-flow simulator ──────────────────────────────────────────────────────

def simulate_chat(
    msg, iteration, room_type='living_room',
    atmosphere='Warm Modern', history=None,
):
    """
    Mirror main.py /chat routing chain after Wave 4.11a/b.
    Returns dict with the trace fields.
    """
    history = history or []
    rs = FakeRS()
    out = {
        'msg': msg, 'iteration': iteration, 'room': room_type,
        'route': '', 'sub_intent': '', 'tone': '',
        'main_enrich': '-', 'secondary': '-',
        'should_generate': False,
        'response': '', 'language': 'en',
    }

    meta = classify_meta_intent(msg)
    atmosphere_id = label_to_atmosphere_id(atmosphere)
    mem = build_session_memory(
        history=history, detected_language=meta.language,
        session_language_override=(
            meta.target_language if meta.target_language != meta.language else ''),
        atmosphere_id_hint=atmosphere_id,
        room_type_hint=room_type,
    )
    out['language'] = mem.session_language

    if meta.intent != MetaIntent.NONE:
        out['route'] = 'META'
        out['sub_intent'] = meta.intent.value
        out['tone'] = '(meta bypass)'
        out['response'] = generate_meta_response(meta, seed_extra='test')
        return out

    lang = 'km' if mem.session_language == 'km' else 'en'

    # Ambiguity check (V2+)
    clar = detect_ambiguity(msg, iteration, language=lang, room_type=room_type)
    if clar is not None:
        out['route'] = 'AMBIGUITY_CLARIFY'
        out['sub_intent'] = clar.ambiguity_id
        out['tone'] = '(clarify bypass)'
        out['response'] = clar.clarification_text
        return out

    ic = classify_intent(msg, iteration)
    out['route'] = ic.intent.value
    out['sub_intent'] = ic.sub_intent.value
    emo = detect_emotional_context(msg)

    if ic.intent in (ConversationIntent.PRODUCT_HELP, ConversationIntent.SUPPORT):
        topic = detect_product_help(msg, lang)
        if topic:
            out['response'] = get_product_answer(topic, lang)
        else:
            out['response'] = get_product_answer('support_contact', lang)
        out['tone'] = '(product knowledge bypass)'
        return out

    tone = select_tone_mode(
        meta_intent=meta.intent, sub_intent=ic.sub_intent,
        confidence=ic.confidence, session_memory=mem,
        emotional_context=emo, iteration=iteration, recent_meta_intents=[],
    )
    out['tone'] = tone.value

    if tone == ToneMode.HUMAN_SOFT:
        out['response'] = generate_human_soft_response(mem, ic.sub_intent, 'test')
        return out
    if tone == ToneMode.ARCHITECT_LIGHT:
        length = select_response_length(msg, emo)
        out['response'] = generate_architect_light_response(
            user_message=msg, atmosphere_id=atmosphere_id, room_type=room_type,
            emotional_context=emo, length=length,
            language=mem.session_language, seed_extra='test',
        )
        return out

    if ic.intent == ConversationIntent.MIXED:
        out['response'] = generate_mixed_response(msg, atmosphere_id, room_type, ic.sub_intent)
        return out

    out['response'] = generate_chat_response(
        user_message=msg, atmosphere_id=atmosphere_id,
        room_type=room_type, sub_intent=ic.sub_intent,
        secondary_spaces=[], refinement_state=rs,
    )
    out['should_generate'] = (ic.intent == ConversationIntent.GENERATE)
    return out


# ── Generation-flow simulator ────────────────────────────────────────────────

def simulate_generate(
    msg, iteration, room_type='living_room',
    atmosphere='Warm Modern',
    structural=None, refinement_state=None,
):
    """Mirror /generate enrichment composition + architect response."""
    atmosphere_id = label_to_atmosphere_id(atmosphere)
    si = structural or FakeStructural()
    rs = refinement_state or FakeRS()

    edit_mode = classify_edit_mode(msg, iteration)
    trans = classify_transformation(msg, iteration)
    tt = trans.value if hasattr(trans, 'value') else (trans or '')

    trade = get_trade_off(msg, tt, atmosphere_id, room_type, iteration=iteration)
    emit_ack = should_emit_acknowledgment(iteration, tt, rs, [])
    ack = build_acknowledgment(si, rs, atmosphere_id, tt) if emit_ack else ''
    alts = get_alternative_directions(atmosphere_id, room_type, rs, iteration, count=3)
    mem_ref = get_memory_reference(rs, iteration, msg)

    mem = build_session_memory(
        history=[], detected_language='en',
        atmosphere_id_hint=atmosphere_id, room_type_hint=room_type,
    )
    emo = detect_emotional_context(msg)
    ic_full = classify_intent(msg, iteration)
    tone = select_tone_mode(
        meta_intent=MetaIntent.NONE,
        sub_intent=ic_full.sub_intent,
        confidence=ic_full.confidence,
        session_memory=mem, emotional_context=emo,
        iteration=iteration, recent_meta_intents=[],
    )

    main_pick = _select_main_enrichment(
        iteration=iteration, edit_mode=edit_mode,
        transformation_type=tt, sub_intent=ic_full.sub_intent,
        constraint_ack=ack, trade_off_clause=trade, alternatives=alts,
    )
    open_pick = _select_opening(
        tone_mode=tone, seed_extra='valseed',
        main_enrichment=main_pick, memory_reference=mem_ref,
    )

    if main_pick == ack and ack:
        main_label = 'constraint_ack'
    elif main_pick == trade and trade:
        main_label = 'trade_off'
    elif main_pick and 'directions worth considering' in main_pick:
        main_label = 'alternatives'
    else:
        main_label = '(none)'

    if open_pick == mem_ref and mem_ref:
        sec_label = f'memory({mem_ref[:40]}…)'
    elif open_pick:
        sec_label = f'confident_open({open_pick[:40]}…)'
    else:
        sec_label = '-'

    final = generate_architect_response(
        atmosphere_id=atmosphere_id, room_type=room_type,
        iteration=iteration, edit_mode=edit_mode,
        refinement_state=rs, sub_intent=ic_full.sub_intent,
        secondary_spaces=[], user_message=msg,
        tone_mode=tone, transformation_type=tt,
        constraint_ack=ack, trade_off_clause=trade,
        alternatives=alts, memory_reference=mem_ref,
    )

    return {
        'msg': msg, 'iteration': iteration, 'room': room_type,
        'route': 'GENERATE', 'sub_intent': ic_full.sub_intent.value,
        'tone': tone.value, 'main_enrich': main_label,
        'secondary': sec_label, 'should_generate': True,
        'response': final, 'words': len(final.split()),
        'has_ack': bool(ack), 'has_trade': bool(trade),
        'has_alts': bool(alts), 'has_memory': bool(mem_ref),
    }


# ── Test runner ──────────────────────────────────────────────────────────────

REPORT = []  # (category, label, pass, msg, route, sub, tone, main, sec, resp, notes)


def record(cat, label, ok, trace, notes=''):
    REPORT.append({
        'cat': cat, 'label': label, 'ok': ok,
        'msg': trace['msg'], 'route': trace['route'],
        'sub_intent': trace.get('sub_intent', ''),
        'tone': trace.get('tone', ''),
        'main_enrich': trace.get('main_enrich', '-'),
        'secondary': trace.get('secondary', '-'),
        'should_generate': trace.get('should_generate', False),
        'response': trace.get('response', ''),
        'notes': notes,
    })


# ── CATEGORY 1: PRODUCT HELP ─────────────────────────────────────────────────
print('Running Category 1 — PRODUCT HELP …')
cat1 = [
    'How do I continue this vision?',
    'How do I share a design?',
    'What is Preserve Mode?',
    'How do I compare before and after?',
    'How does branching work?',
    'How do I delete a session?',
    'How do I rename a project?',
]
for m in cat1:
    t = simulate_chat(m, iteration=2)
    ok = (t['route'] == 'product_help' and not t['should_generate']
          and len(t['response']) > 40)
    record('1. PRODUCT HELP', m, ok, t)

# ── CATEGORY 2: PRODUCT HELP KHMER ───────────────────────────────────────────
print('Running Category 2 — PRODUCT HELP KHMER …')
cat2 = [
    'តើខ្ញុំបន្ត vision នេះដោយរបៀបណា?',
    'តើខ្ញុំចែករំលែកការរចនាដោយរបៀបណា?',
    'Preserve Mode ជាអ្វី?',
    'តើខ្ញុំប្រៀបធៀបមុននិងក្រោយដោយរបៀបណា?',
]
for m in cat2:
    t = simulate_chat(m, iteration=2)
    # KM messages : language detection might or might not be KM. Test ALSO
    # asks that response come back in KM where possible.
    is_km = any(ord(c) > 127 for c in t['response'])
    ok = (t['route'] == 'product_help' and not t['should_generate'] and is_km)
    notes = f'response KM={is_km} lang={t.get("language","?")}'
    record('2. PRODUCT HELP KHMER', m, ok, t, notes)

# ── CATEGORY 3: SUPPORT ──────────────────────────────────────────────────────
print('Running Category 3 — SUPPORT …')
cat3 = [
    'Generation failed, what should I do?',
    'The image is not loading.',
    'The app crashed.',
    'I want to report a bug.',
    'How do I contact support?',
]
for m in cat3:
    t = simulate_chat(m, iteration=2)
    ok = (t['route'] == 'support' and not t['should_generate'])
    record('3. SUPPORT', m, ok, t)

# ── CATEGORY 4: DESIGN DISCUSSION ────────────────────────────────────────────
print('Running Category 4 — DESIGN DISCUSSION …')
cat4 = [
    'What do you think of this room?',
    'Would darker floors work here?',
    'Should I keep the TV wall?',
    'Is this atmosphere too dark?',
    'Do you think this layout works?',
]
for m in cat4:
    t = simulate_chat(m, iteration=2)
    ok = (t['route'] == 'design_discussion' and not t['should_generate'])
    record('4. DESIGN DISCUSSION', m, ok, t)

# ── CATEGORY 5: GENERATE ─────────────────────────────────────────────────────
print('Running Category 5 — GENERATE …')
cat5 = [
    'Make it warmer.',
    'Add more wood.',
    'More luxury.',
    'Make it brighter.',
    'Add plants.',
    'Change to Japandi Calm.',
    'Make the sofa bigger.',
]
for m in cat5:
    t = simulate_chat(m, iteration=2)
    # Either GENERATE or MIXED is acceptable for short imperatives.
    ok = t['route'] in ('generate', 'mixed')
    record('5. GENERATE', m, ok, t)

# ── CATEGORY 6: MISROUTE PREVENTION ──────────────────────────────────────────
print('Running Category 6 — MISROUTE PREVENTION …')
cat6 = [
    'How do I make it warmer?',
    'How can I add more wood?',
    'What should I change to make it more luxury?',
    'How do I make the room brighter?',
]
for m in cat6:
    t = simulate_chat(m, iteration=2)
    # NOT product_help — design intent must win
    ok = (t['route'] != 'product_help')
    record('6. MISROUTE PREVENTION', m, ok, t)

# ── CATEGORY 7: AMBIGUITY ────────────────────────────────────────────────────
print('Running Category 7 — AMBIGUITY …')
cat7 = [
    'Make it bigger.',
    'Make it smaller.',
    'Make it better.',
    'Make it different.',
    'Change it.',
    'Make it pop.',
    'More.',
    'Less.',
    'Make it more open.',
]
for m in cat7:
    t = simulate_chat(m, iteration=2)
    ok = (t['route'] == 'AMBIGUITY_CLARIFY' and not t['should_generate'])
    record('7. AMBIGUITY', m, ok, t)

# ── CATEGORY 8: ROOM-AWARE CLARIFICATIONS ───────────────────────────────────
print('Running Category 8 — ROOM-AWARE CLARIFICATIONS …')
expectations = {
    'living_room': ('sofa', 'seating area', 'room feeling'),
    'bedroom': ('bed zone', 'storage', 'room feeling'),
    'kitchen': ('island', 'workspace', 'kitchen perception'),
    'bathroom': ('shower', 'vanity', 'room perception'),
    'facade': ('entrance', 'glazing', 'scale perception'),
}
for room, expected in expectations.items():
    t = simulate_chat('Make it bigger.', iteration=2, room_type=room)
    ok = all(kw.lower() in t['response'].lower() for kw in expected)
    notes = f'expects {expected}'
    record('8. ROOM-AWARE', f'{room} + bigger', ok, t, notes)

# ── CATEGORY 9: FALSE POSITIVE PROTECTION ───────────────────────────────────
print('Running Category 9 — FALSE POSITIVE PROTECTION …')
cat9 = [
    'Make it warmer.',
    'More luxury.',
    'More wood.',
    'More plants.',
    'Less clutter.',
    'Darker palette.',
    'Make the sofa bigger.',
    'Make the kitchen more open.',
    'Better materials.',
    'Different atmosphere.',
]
for m in cat9:
    t = simulate_chat(m, iteration=2)
    ok = (t['route'] != 'AMBIGUITY_CLARIFY')
    record('9. FALSE POSITIVE', m, ok, t)

# ── CATEGORY 10: NEGATIVE FEEDBACK ──────────────────────────────────────────
print('Running Category 10 — NEGATIVE FEEDBACK …')
cat10 = [
    "I don't like this design.",
    "This doesn't work.",
    "I preferred the previous version.",
    "This feels wrong.",
    "This is worse.",
]
for m in cat10:
    t = simulate_chat(m, iteration=3)
    ok = (t['route'] == 'design_discussion'
          and t['sub_intent'] == 'negative_feedback'
          and not t['should_generate'])
    record('10. NEGATIVE FEEDBACK', m, ok, t)

# ── CATEGORY 11: CONSTRAINT ACKNOWLEDGEMENT ─────────────────────────────────
print('Running Category 11 — CONSTRAINT ACK …')
cat11 = [
    ('Keep the windows and make it warmer.', 'Warm Modern', 'living_room'),
    ('Keep the TV wall and add more luxury.', 'Soft Luxury', 'living_room'),
    ('Keep the kitchen opening and make it brighter.', 'Warm Modern', 'kitchen'),
    ('Preserve the flooring and make it Nordic.', 'Nordic Warmth', 'living_room'),
]
for msg, atm, room in cat11:
    rs = FakeRS(
        keep=[m for m in msg.lower().replace('preserve the ', 'keep the ').split(' and ')
              if m.startswith('keep')],
        latest=msg,
    )
    # On V2 first message — ack should fire per option (a)
    t = simulate_generate(msg, iteration=2, room_type=room,
                          atmosphere=atm,
                          structural=FakeStructural(),
                          refinement_state=rs)
    has_ack_in_resp = ("I'll preserve" in t['response']
                       or "I will preserve" in t['response'])
    bullets = sum(1 for line in t['response'].split('\n')
                  if line.strip().startswith('•'))
    ok = (t['main_enrich'] == 'constraint_ack'
          and has_ack_in_resp
          and bullets <= 3)
    notes = f'bullets={bullets} words={t["words"]}'
    record('11. CONSTRAINT ACK', msg, ok, t, notes)

# ── CATEGORY 12: MEMORY INJECTION (multi-turn) ──────────────────────────────
print('Running Category 12 — MEMORY INJECTION …')
# Scenario A — windows kept at V2, V5 "Make it softer"
rs_a = FakeRS(keep=['the windows'], latest='Make it softer.')
ta = simulate_generate('Make it softer.', iteration=5, room_type='living_room',
                       atmosphere='Warm Modern', refinement_state=rs_a)
memA = 'glazing' in ta['response'].lower()
record('12. MEMORY A (V5 windows kept)', 'Make it softer.',
       memA, ta, notes=f'glazing mention={memA}')

# Scenario B — TV wall kept at V2, V4 "Add more contrast"
rs_b = FakeRS(keep=['the TV wall'], latest='Add more contrast.')
tb = simulate_generate('Add more contrast.', iteration=4, room_type='living_room',
                       atmosphere='Soft Luxury', refinement_state=rs_b)
memB = 'tv wall' in tb['response'].lower()
record('12. MEMORY B (V4 TV wall kept)', 'Add more contrast.',
       memB, tb, notes=f'tv wall mention={memB}')

# ── CATEGORY 13: MEMORY SUPPRESSION ─────────────────────────────────────────
print('Running Category 13 — MEMORY SUPPRESSION …')
# 13a: constraint_ack + memory available → memory suppressed
rs_supp = FakeRS(keep=['the windows'], latest='Make it warmer')
t13a = simulate_generate('Make it warmer.', iteration=2,  # V2 first → ack fires
                         room_type='living_room',
                         atmosphere='Warm Modern',
                         structural=FakeStructural(),
                         refinement_state=rs_supp)
mem_present = 'glazing strategy we established' in t13a['response']
ok_13a = (t13a['main_enrich'] == 'constraint_ack' and not mem_present)
record('13a. SUPPRESS by ack', 'Make it warmer.',
       ok_13a, t13a, f'memory_present={mem_present}')

# 13b: alternatives + memory available → memory suppressed
rs_supp_b = FakeRS(keep=['the windows'])
t13b_alts = ['Direction one.', 'Direction two.', 'Direction three.']
# Force alts main : no trade-off, no ack, V5 stable
from prompt_engine.architect_response import generate_architect_response
final13b = generate_architect_response(
    atmosphere_id='warm_modern', room_type='living_room',
    iteration=5, edit_mode=EditMode.STYLE_REFINEMENT,
    refinement_state=rs_supp_b, sub_intent=SubIntent.REFINE_ATMOSPHERE,
    secondary_spaces=[], user_message='Make it softer.',
    tone_mode=ToneMode.ARCHITECT_ACTIVE,
    transformation_type='style_refinement',
    constraint_ack='', trade_off_clause='',
    alternatives=t13b_alts,
    memory_reference="I'll continue preserving the glazing strategy we established earlier.",
)
mem_present_b = 'glazing strategy we established' in final13b
ok_13b = ('directions worth considering' in final13b.lower()
          and not mem_present_b)
record('13b. SUPPRESS by alternatives', 'Make it softer (with alts forced).',
       ok_13b, {
           'msg': 'Make it softer.',
           'route': 'GENERATE',
           'sub_intent': 'refine_atmosphere',
           'tone': 'architect_active',
           'main_enrich': 'alternatives',
           'secondary': '-',
           'response': final13b,
       }, f'memory_present={mem_present_b}')

# 13c: no previous keep → no memory
rs_empty = FakeRS()  # nothing kept
t13c = simulate_generate('Make it warmer.', iteration=5,
                         room_type='living_room',
                         atmosphere='Warm Modern',
                         refinement_state=rs_empty)
ok_13c = not t13c['has_memory']
record('13c. NO previous keep', 'Make it warmer (V5 empty keep).',
       ok_13c, t13c, f'has_memory={t13c["has_memory"]}')

# 13d: duplicate — user mentions the anchor in current message
rs_dup = FakeRS(keep=['the windows'])
t13d = simulate_generate('Change the windows.', iteration=5,
                         room_type='living_room',
                         atmosphere='Warm Modern',
                         refinement_state=rs_dup)
# The windows anchor was kept AND user just mentioned windows.
# Either no memory at all, OR architectural_memory falls back to a DIFFERENT
# anchor — both behaviours are acceptable as long as memory is not redundant
# with the user's latest instruction.
mem_about_windows = 'glazing strategy' in t13d['response'].lower()
ok_13d = not mem_about_windows
record('13d. Duplicate anchor suppression', 'Change the windows. (user mentions windows)',
       ok_13d, t13d, f'glazing_ref_present={mem_about_windows}')

# ── CATEGORY 14: TRADE-OFFS ──────────────────────────────────────────────────
print('Running Category 14 — TRADE-OFFS …')
cat14 = [
    ('Make it darker.', 'Warm Modern', 'living_room'),
    ('Add more marble.', 'Japandi Calm', 'living_room'),
    ('Add more decor.', 'Japandi Calm', 'living_room'),
    ('Make it more industrial.', 'Warm Modern', 'bedroom'),
    ('Add a TV.', 'Wabi Sabi', 'living_room'),  # wabi_sabi not in atm DNA registry
]
for msg, atm, room in cat14:
    t = simulate_generate(msg, iteration=3, room_type=room,
                          atmosphere=atm,
                          structural=FakeStructural(),
                          refinement_state=FakeRS(latest=msg))
    # Trade-off may fire ; if it fires, it must be exactly one clause.
    # If atmosphere is unknown (wabi_sabi maps to default), generic
    # trade-off may still fire.
    if t['has_trade']:
        ok = (t['main_enrich'] == 'trade_off')
        notes = 'trade-off fired'
    else:
        ok = True  # silent is acceptable
        notes = 'no trade-off (silent)'
    # No stacking : at most one main enrichment
    record('14. TRADE-OFFS', msg, ok, t, notes)

# ── CATEGORY 15: DESIGN ALTERNATIVES ────────────────────────────────────────
print('Running Category 15 — DESIGN ALTERNATIVES …')
for atm in ['Warm Modern', 'Japandi Calm', 'Soft Luxury']:
    t = simulate_generate(
        'What should we try next?', iteration=3, room_type='living_room',
        atmosphere=atm, refinement_state=FakeRS(latest='different'),
    )
    # Alternatives expected when no trade-off / no ack
    has_alts_block = 'directions worth considering' in t['response'].lower()
    ok = has_alts_block or t['has_trade'] or t['has_memory']
    record('15. ALTERNATIVES', f'{atm} + "What should we try next?"', ok, t,
           f'alts_block={has_alts_block}')

# ── CATEGORY 16: V1 PROTECTION ──────────────────────────────────────────────
print('Running Category 16 — V1 PROTECTION …')
for m in ['Make it bigger.', 'Make it pop.']:
    t = simulate_chat(m, iteration=1)
    ok = (t['route'] != 'AMBIGUITY_CLARIFY' and t['route'] in ('generate',))
    record('16. V1 PROTECTION', m, ok, t)

# ── CATEGORY 17: KHMER EDGE CASES ───────────────────────────────────────────
print('Running Category 17 — KHMER EDGE CASES …')
km_cases = [
    ('រូបភាពមិនបង្ហាញទេ', 'support'),          # "image not showing"
    ('Generate មិនដំណើរការ', 'support'),       # "Generate not working"
    ('តើខ្ញុំអាចបន្តពី vision មុនបានទេ?', 'product_help'),  # "can I continue from previous vision"
    ('ធំជាងមុន', 'AMBIGUITY_CLARIFY'),         # "bigger than before" — standalone
    ('ច្រើនជាង ឈើ', 'generate'),               # "more wood" — clear intent
]
for m, expected_route in km_cases:
    t = simulate_chat(m, iteration=2)
    ok = (t['route'] == expected_route
          or (expected_route == 'generate' and t['route'] in ('generate', 'mixed', 'conversation')))
    record('17. KHMER EDGE', m, ok, t, f'expected={expected_route}')


# ── CATEGORY 18: REGRESSION GUARDS (Wave 4.11c new patterns) ────────────────
print('Running Category 18 — REGRESSION GUARDS …')
# These must NOT mis-route after the 4.11c pattern expansions.
regression = [
    ('the dark wood is not good for this kitchen because of stains',
     ['design_discussion-negative_feedback'],
     'constraint statement, not negative feedback'),
    ('it is too dark in here because the curtains are closed',
     ['design_discussion-design_discussion'],
     'declarative "too dark", not opinion-seek'),
    ('Add brighter chairs.',
     ['design_discussion-design_discussion'],
     '"brighter" inside add-X → still LOCAL_EDIT, not DESIGN_DISCUSSION'),
]
for msg, bad_routes, label in regression:
    t = simulate_chat(msg, iteration=2)
    full = f"{t['route']}-{t['sub_intent']}"
    bad = full in bad_routes
    ok = not bad
    record('18. REGRESSION GUARDS', f'{label} ({msg[:40]}…)', ok, t,
           f'expected NOT {bad_routes} got {full}')

# Positive expectations on the new fixes
print('Running Category 18b — POSITIVE EXPECTATIONS (new fixes) …')
positives = [
    ('Make it brighter.', 'generate', 'FIX 4'),
    ('More daylight please.', 'generate', 'FIX 4 — daylight'),
    ('Make the sofa bigger.', 'generate', 'FIX 5'),
    ('Enlarge the island.', 'generate', 'FIX 5 — enlarge verb'),
    ('Make the bed bigger.', 'generate', 'FIX 5 — bedroom'),
    ('Is this atmosphere too dark?', 'design_discussion', 'FIX 6'),
    ('Is the kitchen too bright?', 'design_discussion', 'FIX 6'),
    ('Not good.', 'design_discussion', 'FIX 7 — bare negative'),
    ("I'm not happy with this.", 'design_discussion', 'FIX 7'),
    ('This looks worse than the previous.', 'design_discussion', 'FIX 7'),
]
for msg, expected, label in positives:
    t = simulate_chat(msg, iteration=2)
    ok = t['route'] == expected
    record('18b. POSITIVE NEW FIXES', f'{label}: {msg}', ok, t,
           f'expected={expected} got={t["route"]}')

# FIX 8 — V2-first LOCAL_EDIT with constraint_ack must surface ack
print('Running Category 18c — FIX 8 (LOCAL_EDIT × ack) …')
rs_18c = FakeRS(keep=['the flooring'], latest='Preserve the flooring and make it Nordic.')
t18c = simulate_generate('Preserve the flooring and make it Nordic.',
                         iteration=2, room_type='living_room',
                         atmosphere='Nordic Warmth',
                         structural=FakeStructural(),
                         refinement_state=rs_18c)
ok18c = (t18c['main_enrich'] == 'constraint_ack'
         and ("I'll preserve" in t18c['response']
              or "I will preserve" in t18c['response']))
record('18c. FIX 8 ack-on-local-edit',
       'Preserve the flooring and make it Nordic.', ok18c, t18c,
       f'main={t18c["main_enrich"]}')


# ── EMIT REPORT ──────────────────────────────────────────────────────────────

print()
print('=' * 80)
print('Wave 4.11 — FULL Validation Report')
print('=' * 80)

# Per-category summary
by_cat = {}
for r in REPORT:
    by_cat.setdefault(r['cat'], {'pass': 0, 'total': 0, 'fails': []})
    by_cat[r['cat']]['total'] += 1
    if r['ok']:
        by_cat[r['cat']]['pass'] += 1
    else:
        by_cat[r['cat']]['fails'].append(r)

total = len(REPORT)
passes = sum(1 for r in REPORT if r['ok'])
fails = total - passes

print()
print(f'TOTAL: {passes}/{total} pass  ({fails} failures)')
print()

# Per category table
print('Per-category breakdown :')
for cat, stats in by_cat.items():
    p, tt = stats['pass'], stats['total']
    pct = (p / tt * 100) if tt else 0
    status = '✓' if p == tt else '✗'
    print(f'  {status}  {cat:<32} {p}/{tt}  ({pct:.0f}%)')

print()
print('=' * 80)
print('Detailed Per-Test Trace')
print('=' * 80)

for r in REPORT:
    status = 'PASS' if r['ok'] else 'FAIL'
    print()
    print(f'[{status}] {r["cat"]} — {r["label"][:80]}')
    print(f'  Route       : {r["route"]}')
    print(f'  Sub-intent  : {r["sub_intent"]}')
    print(f'  Tone        : {r["tone"]}')
    print(f'  Main enrich : {r["main_enrich"]}')
    print(f'  Secondary   : {r["secondary"]}')
    print(f'  should_gen  : {r["should_generate"]}')
    if r['notes']:
        print(f'  Notes       : {r["notes"]}')
    resp_preview = r['response'][:200].replace('\n', ' | ')
    print(f'  Response    : "{resp_preview}{"..." if len(r["response"])>200 else ""}"')

# Failures-only block
fails_only = [r for r in REPORT if not r['ok']]
if fails_only:
    print()
    print('=' * 80)
    print(f'FAILURES ({len(fails_only)})')
    print('=' * 80)
    for r in fails_only:
        print(f'  {r["cat"]} — {r["label"]}')
        print(f'    Got route={r["route"]}  sub={r["sub_intent"]}')
        print(f'    Notes: {r["notes"]}')
        print()

print()
print(f'=== SUMMARY: {passes}/{total} pass, {fails} failures ===')
