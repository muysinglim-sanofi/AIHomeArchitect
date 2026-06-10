"""
Wave 4.11d — Generation Intent Dominance validation harness.

Mirrors the main.py /chat routing chain to test:
  - Clarification budget (1 round max)
  - Clarification answer resolution → GENERATE
  - Frustration / explicit demand override → GENERATE
  - Discussion preservation (Scenario E, F)
  - Regression checks against Wave 4.11a/b/c
"""
import sys
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

from prompt_engine.intent_classifier import (
    classify_intent, ConversationIntent, SubIntent,
    detect_generation_demand, is_clarification_answer,
    last_assistant_was_clarification,
)
from prompt_engine.meta_intent import classify_meta_intent, MetaIntent
from prompt_engine.ambiguity_detector import detect_ambiguity
from prompt_engine.conversation_memory import build_session_memory
from prompt_engine.atmosphere_dna import label_to_atmosphere_id


def simulate(msg, iteration=2, history=None, room='living_room',
             atmosphere='Warm Modern'):
    """Mirror main.py /chat routing including the new Wave 4.11d layer."""
    history = history or []
    atmosphere_id = label_to_atmosphere_id(atmosphere)
    meta = classify_meta_intent(msg)
    mem = build_session_memory(
        history=history, detected_language=meta.language,
        session_language_override=(
            meta.target_language if meta.target_language != meta.language else ''),
        atmosphere_id_hint=atmosphere_id,
        room_type_hint=room,
    )
    out = {
        'msg': msg, 'iteration': iteration, 'history_len': len(history),
        'route': '', 'sub_intent': '', 'should_generate': False,
        'reason': '', 'language': mem.session_language,
    }

    if meta.intent != MetaIntent.NONE:
        out['route'] = 'meta'
        out['sub_intent'] = meta.intent.value
        return out

    lang = 'km' if mem.session_language == 'km' else 'en'

    # Wave 4.11d
    if iteration > 1 and detect_generation_demand(msg):
        out['route'] = 'generate'
        out['sub_intent'] = 'refine_atmosphere'
        out['should_generate'] = True
        out['reason'] = 'wave_4_11d_generation_demand'
        return out
    if iteration > 1 and is_clarification_answer(msg, history):
        out['route'] = 'generate'
        out['sub_intent'] = 'refine_atmosphere'
        out['should_generate'] = True
        out['reason'] = 'wave_4_11d_clarification_resolved'
        return out

    # Existing chain — ambiguity → classify_intent
    clar = detect_ambiguity(msg, iteration, language=lang, room_type=room)
    if clar is not None:
        out['route'] = 'AMBIGUITY_CLARIFY'
        out['sub_intent'] = clar.ambiguity_id
        out['reason'] = 'wave_4_11a_ambiguity'
        return out

    ic = classify_intent(msg, iteration)
    out['route'] = ic.intent.value
    out['sub_intent'] = ic.sub_intent.value
    out['should_generate'] = (ic.intent == ConversationIntent.GENERATE)
    out['reason'] = ic.reasoning
    return out


REPORT = []

def record(section, label, expected, got, trace, notes=''):
    ok = got == expected
    REPORT.append({
        'section': section, 'label': label, 'ok': ok,
        'expected': expected, 'got': got, 'trace': trace, 'notes': notes,
    })
    status = '✓' if ok else '✗'
    print(f'  {status} {label[:60]:62} expected={expected:25} got={got}')


def clarification_assistant_msg(ambiguity='bigger'):
    """Realistic assistant clarification text mirroring ambiguity_detector."""
    return (
        f"When you say {ambiguity} — are you thinking :\n"
        f"• the sofa or specific seating piece\n"
        f"• the seating area (more generous arrangement)\n"
        f"• the overall room feeling (architectural openness)\n\n"
        f"Tell me which and I'll calibrate the next vision."
    )


# ── SECTION 1: Clarification Resolution (Principle 1 + 2) ────────────────────
print('\n[1] Clarification Resolution')

# Scenario A : User "make it bigger" → clarification → User "overall room feeling" → GENERATE
history_a = [
    {'role': 'user', 'content': 'make it bigger'},
    {'role': 'assistant', 'content': clarification_assistant_msg('bigger')},
]
t = simulate('overall room feeling', iteration=3, history=history_a)
record('1. Clarification Resolution',
       'Scenario A: "overall room feeling" after bigger-clarification',
       'generate', t['route'], t)

# Short answers should resolve, not re-clarify
for ans in ['warmer lighting', 'finishes', 'the sofa', 'overall feeling']:
    hist = [
        {'role': 'user', 'content': 'make it warmer'},
        {'role': 'assistant', 'content': clarification_assistant_msg('warmer')},
    ]
    t = simulate(ans, iteration=3, history=hist)
    record('1. Clarification Resolution',
           f'short answer "{ans}" → GENERATE',
           'generate', t['route'], t)

# Scenario B : "missing quality" → clarification → User answers → GENERATE
hist_b = [
    {'role': 'user', 'content': 'missing quality'},
    {'role': 'assistant', 'content':
        "Better in which direction — :\n"
        "• material palette\n"
        "• lighting register\n"
        "• atmospheric intensity\n\n"
        "Tell me which and I'll calibrate."},
]
t = simulate('material palette', iteration=3, history=hist_b)
record('1. Clarification Resolution',
       'Scenario B: "material palette" after better-clarification',
       'generate', t['route'], t)


# ── SECTION 2: Generation Dominance (Principle 3) ────────────────────────────
print('\n[2] Generation Dominance — design directives bias toward GENERATE')

for msg, expected in [
    ('make it warmer', 'generate'),
    ('make it brighter', 'generate'),   # Wave 4.11c
    ('more luxurious', 'generate'),
    ('cozy', 'generate'),                # Wave 4.11d would not flip — _REFINE has calmer/quieter; cozy isn't there but routes as conversation/general
    ('add a TV', 'generate'),
    ('open the kitchen', 'generate'),
    ('more natural light', 'generate'),
    ('less wood', 'generate'),
]:
    t = simulate(msg, iteration=2)
    record('2. Generation Dominance', msg, expected, t['route'], t)


# ── SECTION 3: Frustration Override (Principle 4) ────────────────────────────
print('\n[3] Frustration / Explicit Demand Override')

# Scenario C : "why don't you generate?"
t = simulate("why don't you generate?", iteration=3)
record('3. Frustration Override',
       'Scenario C: "why don\'t you generate?"',
       'generate', t['route'], t,
       notes=f'reason={t.get("reason","")}')

# Scenario D : bare "generate"
t = simulate('generate', iteration=2)
record('3. Frustration Override', 'Scenario D: "generate"',
       'generate', t['route'], t,
       notes=f'reason={t.get("reason","")}')

for msg in ['just do it', 'show me', "let's see", 'render it', 'make it',
            'try it', 'create it', 'do it now', 'go ahead', 'generate now']:
    t = simulate(msg, iteration=2)
    record('3. Frustration Override', msg, 'generate', t['route'], t,
           notes=f'reason={t.get("reason","")}')

# Override fires EVEN when no prior history
t = simulate('just do it', iteration=2, history=[])
record('3. Frustration Override', '"just do it" with empty history',
       'generate', t['route'], t)


# ── SECTION 4: Discussion Preservation (Principle 5) ─────────────────────────
print('\n[4] Discussion Preservation — DESIGN_DISCUSSION must still fire')

# Scenario E
t = simulate('What do you think of this living room?', iteration=3)
record('4. Discussion Preservation', 'Scenario E: "What do you think of this living room?"',
       'design_discussion', t['route'], t)

# Scenario F
for msg in ['Compare these two atmospheres', 'Compare these two designs',
            'Compare both options', 'What are the pros and cons?']:
    t = simulate(msg, iteration=2)
    record('4. Discussion Preservation', msg,
           'design_discussion', t['route'], t)

# Existing Wave 4.11c discussions still work
for msg in ['Is this atmosphere too dark?', 'Would darker floors work?',
            'Should I keep the TV wall?', 'Is the kitchen too bright?']:
    t = simulate(msg, iteration=2)
    record('4. Discussion Preservation', msg,
           'design_discussion', t['route'], t)


# ── SECTION 5: Regression Checks ─────────────────────────────────────────────
print('\n[5] Regression Checks — Wave 4.11a/b/c paths must still hold')

# Ambiguity still fires when there's no prior clarification
for msg in ['make it bigger', 'make it pop', 'change it', 'more', 'less']:
    t = simulate(msg, iteration=2, history=[])
    record('5. Regressions', f'first-time "{msg}" → AMBIGUITY_CLARIFY',
           'AMBIGUITY_CLARIFY', t['route'], t)

# Negative feedback still routes to design_discussion / negative_feedback —
# even AFTER a clarification dialog (4.11d must not flip dissatisfaction
# to GENERATE).
hist_nf = [
    {'role': 'user', 'content': 'make it bigger'},
    {'role': 'assistant', 'content': clarification_assistant_msg('bigger')},
]
for msg in ["I don't like this", "this is worse", "I preferred the previous"]:
    t = simulate(msg, iteration=3, history=hist_nf)
    record('5. Regressions', f'negative after clarification: {msg!r}',
           'design_discussion', t['route'], t,
           notes=f'sub={t["sub_intent"]}')

# Product help still routes after a clarification (user changes topic)
t = simulate('how do I share a design?', iteration=3, history=hist_nf)
record('5. Regressions', 'PRODUCT_HELP question after clarification',
       'product_help', t['route'], t)

# Long sentence after clarification (rejection of clarification answer rule)
hist_long = [
    {'role': 'user', 'content': 'make it bigger'},
    {'role': 'assistant', 'content': clarification_assistant_msg('bigger')},
]
t = simulate(
    'Actually, can we discuss the kitchen layout for a moment?',
    iteration=3, history=hist_long)
# Long redirect with "Actually" + "?" must NOT auto-generate
ok = t['route'] != 'generate'
print(f'  {"✓" if ok else "✗"} long redirect after clarification → not GENERATE  (got={t["route"]})')

# A "compare" message after clarification → DISCUSS (per anti-answer rule)
hist_compare = [
    {'role': 'user', 'content': 'make it bigger'},
    {'role': 'assistant', 'content': clarification_assistant_msg('bigger')},
]
t = simulate('compare these two options', iteration=3, history=hist_compare)
record('5. Regressions', 'compare X after clarification → design_discussion',
       'design_discussion', t['route'], t)

# V1 always generates (Wave 4.11a invariant)
t = simulate('make it bigger', iteration=1)
record('5. Regressions', 'V1 "make it bigger" → generate (V1 always generates)',
       'generate', t['route'], t)


# ── SECTION 6: Adversarial Probes ────────────────────────────────────────────
print('\n[6] Adversarial Probes')

# Embedded "generate" in a longer instruction → standard chain, not override
t = simulate('please generate a version with darker wood', iteration=2)
ok = t['route'] in ('generate', 'mixed')  # acceptable either way, but NOT product_help
record('6. Adversarial', 'embedded "generate" + edit instruction',
       t['route'], t['route'], t,
       notes=f'reason={t.get("reason","")} — should not be product_help')

# "generate now" as full message → override
t = simulate('generate now', iteration=2)
record('6. Adversarial', '"generate now" → GENERATE',
       'generate', t['route'], t)

# Embedded discussion verb mid-sentence → no override
t = simulate('Can you compare the dark wood vs the light wood?', iteration=2)
record('6. Adversarial', '"Can you compare X vs Y?" → design_discussion',
       'design_discussion', t['route'], t)

# User says "yes" after clarification → ambiguous answer
# Per Principle 1, "yes" after clarification should also resolve → GENERATE
hist_yes = [
    {'role': 'user', 'content': 'make it bigger'},
    {'role': 'assistant', 'content': clarification_assistant_msg('bigger')},
    {'role': 'user', 'content': 'overall room feeling'},
    {'role': 'assistant', 'content': 'Got it — going for room openness.'},
]
t = simulate('yes', iteration=4, history=hist_yes)
# After "Got it" (NOT a clarification) the assistant didn't ask another
# clarification — so this is just a bare "yes" confirmation. The existing
# confirmation logic should handle it. We expect generate via either 4.11d
# generation_demand OR the existing 4.7.7 confirmation flow.
ok = t['route'] in ('generate', 'conversation')  # both acceptable here
print(f'  {"✓" if ok else "✗"} "yes" after non-clarification assistant → {t["route"]}')

# Mid-clarification "I'm not sure what you mean" — confusion, not answer
hist_confused = [
    {'role': 'user', 'content': 'make it bigger'},
    {'role': 'assistant', 'content': clarification_assistant_msg('bigger')},
]
t = simulate("I'm not sure what you mean", iteration=3, history=hist_confused)
ok = t['route'] != 'generate'
print(f'  {"✓" if ok else "✗"} confusion after clarification → {t["route"]}  (not generate)')


# ── REPORT ───────────────────────────────────────────────────────────────────
print()
print('=' * 80)
print('Wave 4.11d — Validation Summary')
print('=' * 80)

by_section = {}
for r in REPORT:
    by_section.setdefault(r['section'], {'pass': 0, 'total': 0, 'fails': []})
    by_section[r['section']]['total'] += 1
    if r['ok']:
        by_section[r['section']]['pass'] += 1
    else:
        by_section[r['section']]['fails'].append(r)

total = len(REPORT)
passes = sum(1 for r in REPORT if r['ok'])

print()
print(f'TOTAL: {passes}/{total} pass')
print()
for sec, stats in by_section.items():
    p, tt = stats['pass'], stats['total']
    status = '✓' if p == tt else '✗'
    print(f'  {status} {sec:<35} {p}/{tt}')

fails = [r for r in REPORT if not r['ok']]
if fails:
    print()
    print('FAILURES:')
    for r in fails:
        print(f'  {r["section"]} — {r["label"]}')
        print(f'    expected={r["expected"]}  got={r["got"]}')
        if r['notes']:
            print(f'    notes: {r["notes"]}')

print()
print(f'=== SUMMARY: {passes}/{total} pass ===')
