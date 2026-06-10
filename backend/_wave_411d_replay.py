"""
Wave 4.11d — Real conversation replay harness with side-by-side old/new
behavior. Bypasses the 4.11d layer when `wave_411d=False` to reproduce
the exact code path that produced the original bad behavior.

For each user turn this emits :
  meta_intent | generation_demand | clarification_answer | ambiguity
    | intent_classifier | final_route | assistant_response_excerpt

So you can read EXACTLY why each routing decision was made.
"""
import sys
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

from dataclasses import dataclass, field

from prompt_engine.intent_classifier import (
    classify_intent, ConversationIntent, SubIntent,
    detect_generation_demand, is_clarification_answer,
    last_assistant_was_clarification,
)
from prompt_engine.meta_intent import classify_meta_intent, MetaIntent
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
    generate_chat_response, generate_mixed_response,
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


@dataclass
class TurnTrace:
    role: str
    content: str
    iteration: int = 0
    # Set when role == 'user' (the routing decision for this user turn)
    wave_411d_active: bool = False
    meta_intent: str = '-'
    gen_demand_fired: bool = False
    last_assistant_was_clar: bool = False
    clar_answer_fired: bool = False
    ambiguity_id: str = '-'
    classify_intent_route: str = '-'
    classify_intent_sub: str = '-'
    classify_intent_reason: str = '-'
    final_route: str = '-'
    final_sub: str = '-'
    should_generate: bool = False
    response_excerpt: str = ''


def replay_turn(user_msg, iteration, history, atmosphere, room,
                wave_411d=True) -> TurnTrace:
    """Mirror main.py /chat with optional bypass of the 4.11d layer."""
    trace = TurnTrace(
        role='user', content=user_msg, iteration=iteration,
        wave_411d_active=wave_411d,
    )

    atmosphere_id = label_to_atmosphere_id(atmosphere)
    meta = classify_meta_intent(user_msg)
    trace.meta_intent = meta.intent.value

    mem = build_session_memory(
        history=history, detected_language=meta.language,
        session_language_override=(
            meta.target_language if meta.target_language != meta.language else ''),
        atmosphere_id_hint=atmosphere_id, room_type_hint=room,
    )

    # Always run the detectors so we can show their state even when the
    # layer is bypassed.
    trace.gen_demand_fired = bool(detect_generation_demand(user_msg)) if iteration > 1 else False
    trace.last_assistant_was_clar = bool(last_assistant_was_clarification(history))
    trace.clar_answer_fired = bool(is_clarification_answer(user_msg, history)) if iteration > 1 else False

    # Meta intent short-circuit (both old and new behave identically here)
    if meta.intent != MetaIntent.NONE:
        trace.final_route = 'meta'
        trace.final_sub = meta.intent.value
        trace.response_excerpt = f'<meta:{meta.intent.value}>'
        return trace

    # Wave 4.11d layer — only fires when the flag is on
    if wave_411d and iteration > 1:
        if trace.gen_demand_fired:
            trace.final_route = 'generate'
            trace.final_sub = 'refine_atmosphere'
            trace.should_generate = True
            trace.classify_intent_reason = 'wave_4_11d_generation_demand'
            trace.response_excerpt = _gen_response_excerpt(
                user_msg, atmosphere_id, room, SubIntent.REFINE_ATMOSPHERE)
            return trace
        if trace.clar_answer_fired:
            trace.final_route = 'generate'
            trace.final_sub = 'refine_atmosphere'
            trace.should_generate = True
            trace.classify_intent_reason = 'wave_4_11d_clarification_resolved'
            trace.response_excerpt = _gen_response_excerpt(
                user_msg, atmosphere_id, room, SubIntent.REFINE_ATMOSPHERE)
            return trace

    # Standard chain — ambiguity → classify_intent
    lang = 'km' if mem.session_language == 'km' else 'en'
    clar = detect_ambiguity(user_msg, iteration, language=lang, room_type=room)
    if clar is not None:
        trace.ambiguity_id = clar.ambiguity_id
        trace.final_route = 'AMBIGUITY_CLARIFY'
        trace.final_sub = clar.ambiguity_id
        trace.response_excerpt = clar.clarification_text[:200].replace('\n', ' | ')
        return trace

    ic = classify_intent(user_msg, iteration)
    trace.classify_intent_route = ic.intent.value
    trace.classify_intent_sub = ic.sub_intent.value
    trace.classify_intent_reason = ic.reasoning
    trace.final_route = ic.intent.value
    trace.final_sub = ic.sub_intent.value
    trace.should_generate = (ic.intent == ConversationIntent.GENERATE)

    # Produce a representative response excerpt
    emo = detect_emotional_context(user_msg)
    tone = select_tone_mode(
        meta_intent=meta.intent, sub_intent=ic.sub_intent,
        confidence=ic.confidence, session_memory=mem, emotional_context=emo,
    )
    if tone == ToneMode.HUMAN_SOFT:
        text = generate_human_soft_response(mem, ic.sub_intent, 'replay')
    elif tone == ToneMode.ARCHITECT_LIGHT:
        text = generate_architect_light_response(
            user_message=user_msg, atmosphere_id=atmosphere_id,
            room_type=room, emotional_context=emo,
            length=select_response_length(user_msg, emo),
            language=mem.session_language, seed_extra='replay',
        )
    elif ic.intent == ConversationIntent.MIXED:
        text = generate_mixed_response(user_msg, atmosphere_id, room, ic.sub_intent)
    else:
        text = generate_chat_response(
            user_message=user_msg, atmosphere_id=atmosphere_id,
            room_type=room, sub_intent=ic.sub_intent,
            secondary_spaces=[], refinement_state=FakeRS(latest=user_msg),
        )
    trace.response_excerpt = text[:200].replace('\n', ' | ')
    return trace


def _gen_response_excerpt(msg, atm_id, room, sub_intent):
    """Build the chat response the user would see on a 4.11d-generated turn."""
    text = generate_chat_response(
        user_message=msg, atmosphere_id=atm_id, room_type=room,
        sub_intent=sub_intent, secondary_spaces=[],
        refinement_state=FakeRS(latest=msg),
    )
    return text[:200].replace('\n', ' | ')


# ── Conversation replays ─────────────────────────────────────────────────────

def render_turn_trace(t: TurnTrace) -> str:
    """Pretty-print a single turn trace."""
    lines = []
    lines.append(f"  [{('PRE-4.11d', 'POST-4.11d')[int(t.wave_411d_active)]}]"
                 f"  V{t.iteration}  user: {t.content!r}")
    lines.append(f"    meta_intent           : {t.meta_intent}")
    lines.append(f"    generation_demand     : {t.gen_demand_fired}")
    lines.append(f"    last_assistant_was_clar: {t.last_assistant_was_clar}")
    lines.append(f"    clarification_answer  : {t.clar_answer_fired}"
                 f"  {'(4.11d disabled)' if not t.wave_411d_active else ''}")
    lines.append(f"    ambiguity_id          : {t.ambiguity_id}")
    lines.append(f"    classify_intent       : {t.classify_intent_route}/{t.classify_intent_sub}"
                 f" — {t.classify_intent_reason}")
    lines.append(f"    FINAL ROUTE           : {t.final_route}/{t.final_sub}"
                 f"  should_generate={t.should_generate}")
    lines.append(f"    response excerpt      : \"{t.response_excerpt[:180]}\"")
    return '\n'.join(lines)


# ── Real conversation #1 ─────────────────────────────────────────────────────
# Source : Wave 4.11d brief, "Real Examples Observed — Example 1".
# Verbatim 5-turn excerpt from the user's brief.

print('═' * 80)
print('REAL CONVERSATION #1 — make it bigger and brighter (5 turns)')
print('Source: Wave 4.11d brief, "Real Examples Observed — Example 1"')
print('═' * 80)

# Reconstruct realistic assistant clarifications. Text mirrors
# ambiguity_detector._RULES output.
CLAR_BIGGER_LIV = (
    "When you say bigger — are you thinking :\n"
    "• the sofa or specific seating piece\n"
    "• the seating area (more generous arrangement)\n"
    "• the overall room feeling (architectural openness)\n\n"
    "Tell me which and I'll calibrate the next vision."
)
SECOND_CLAR_AFTER_OPENNESS = (
    "Got it — openness. In which direction :\n"
    "• architectural (remove a partition, widen an opening)\n"
    "• visual (lighter palette, less visual weight)\n"
    "• foreground (clear the seating zone, fewer pieces)\n\n"
    "Pick the angle and I'll calibrate."
)

conv1_turns = [
    ('user',      'make it bigger and brighter', 2),
    ('assistant', CLAR_BIGGER_LIV, 2),
    ('user',      'overall room feeling', 3),
    ('assistant', SECOND_CLAR_AFTER_OPENNESS, 3),  # reconstructed (what happened in user's brief)
    ('user',      'yes', 4),
]
conv1_atmosphere = 'Warm Modern'
conv1_room = 'living_room'

# Replay each user turn twice : pre-4.11d (broken) vs post-4.11d (fixed).
print()
print('--- Per-turn routing trace (PRE vs POST Wave 4.11d) ---')
history_acc = []
for role, content, iteration in conv1_turns:
    if role == 'user':
        # Run twice
        t_pre = replay_turn(content, iteration, history_acc,
                            conv1_atmosphere, conv1_room, wave_411d=False)
        t_post = replay_turn(content, iteration, history_acc,
                             conv1_atmosphere, conv1_room, wave_411d=True)
        print()
        print(render_turn_trace(t_pre))
        print()
        print(render_turn_trace(t_post))
        history_acc.append({'role': 'user', 'content': content})
    else:
        history_acc.append({'role': 'assistant', 'content': content})

# ── Real conversation #2 ─────────────────────────────────────────────────────
# Source : Wave 4.11d brief, "Real Examples Observed — Example 2".
# Verbatim part : User : "missing quality" → A : clarification → User : <answer>
# RECONSTRUCTION : the brief said "user provides clarification" without
# verbatim text. We use "the material palette" as a representative answer.
# Marked clearly in the deliverable.

print()
print('═' * 80)
print('REAL CONVERSATION #2 — "missing quality" (3 turns)')
print('Source: Wave 4.11d brief, "Real Examples Observed — Example 2"')
print('Note: turn 3 user content "the material palette" is RECONSTRUCTED ;')
print('      the brief said "user provides clarification" without verbatim text.')
print('═' * 80)

CLAR_BETTER = (
    "Better in which direction — :\n"
    "• material palette (richer / lighter / more cohesive)\n"
    "• lighting register (warmer / more layered / softer)\n"
    "• atmospheric intensity (push the chosen atmosphere harder)\n\n"
    "Or another axis ?"
)

conv2_turns = [
    ('user',      'missing quality', 2),
    ('assistant', CLAR_BETTER, 2),
    ('user',      'the material palette', 3),
]
conv2_atmosphere = 'Warm Modern'
conv2_room = 'living_room'

print()
print('--- Per-turn routing trace (PRE vs POST Wave 4.11d) ---')
history_acc = []
for role, content, iteration in conv2_turns:
    if role == 'user':
        t_pre = replay_turn(content, iteration, history_acc,
                            conv2_atmosphere, conv2_room, wave_411d=False)
        t_post = replay_turn(content, iteration, history_acc,
                             conv2_atmosphere, conv2_room, wave_411d=True)
        print()
        print(render_turn_trace(t_pre))
        print()
        print(render_turn_trace(t_post))
        history_acc.append({'role': 'user', 'content': content})
    else:
        history_acc.append({'role': 'assistant', 'content': content})

# ── Real conversation #3 ─────────────────────────────────────────────────────
# Source : Wave 4.11d brief, "Real Examples Observed — Example 3".
# Single user message ; the brief gave no follow-up.

print()
print('═' * 80)
print('REAL CONVERSATION #3 — "why don\'t you generate?" (1 turn)')
print('Source: Wave 4.11d brief, "Real Examples Observed — Example 3"')
print('═' * 80)

conv3_turns = [
    ('user', "why don't you generate?", 3),
]
# Reconstruction: assume the conversation already has SOME prior context
# (the user is asking "why don't you generate" — implies prior turns).
# We seed a minimal prior turn so iteration=3 makes sense.
conv3_seed_history = [
    {'role': 'user', 'content': 'add more warmth'},
    {'role': 'assistant', 'content': "Yeah, that direction makes sense. What element would you push further?"},
]

print()
print('--- Per-turn routing trace (PRE vs POST Wave 4.11d) ---')
print('Seed history (for V≥3 context):')
for m in conv3_seed_history:
    print(f'    [{m["role"]}] {m["content"]!r}')

for role, content, iteration in conv3_turns:
    if role == 'user':
        t_pre = replay_turn(content, iteration, conv3_seed_history,
                            'Warm Modern', 'living_room', wave_411d=False)
        t_post = replay_turn(content, iteration, conv3_seed_history,
                             'Warm Modern', 'living_room', wave_411d=True)
        print()
        print(render_turn_trace(t_pre))
        print()
        print(render_turn_trace(t_post))

# ── Regression block ─────────────────────────────────────────────────────────

print()
print('═' * 80)
print('REGRESSION BLOCK — must hold after Wave 4.11d')
print('═' * 80)

regression_cases = [
    ('architectural discussion (Scenario E)',
     'What do you think of this living room?', 2, []),
    ('comparison request (Scenario F)',
     'Compare these two atmospheres', 2, []),
    ('support question',
     'The image is not loading.', 2, []),
    ('meta intent — frustration',
     "this is not right", 2, []),
    ('meta intent — greeting',
     'hello', 1, []),
    ('first-time ambiguity (must still clarify)',
     'make it bigger', 2, []),
    ('negative feedback after clarification (must NOT auto-generate)',
     "I don't like this", 3, [
         {'role': 'user', 'content': 'make it bigger'},
         {'role': 'assistant', 'content': CLAR_BIGGER_LIV},
     ]),
    ('product help',
     'How do I share a design?', 2, []),
]

print()
for label, msg, it, hist in regression_cases:
    t_post = replay_turn(msg, it, hist, 'Warm Modern', 'living_room',
                         wave_411d=True)
    expected_categories = {
        'architectural discussion (Scenario E)': 'design_discussion',
        'comparison request (Scenario F)': 'design_discussion',
        'support question': 'support',
        'meta intent — frustration': 'meta',
        'meta intent — greeting': 'meta',
        'first-time ambiguity (must still clarify)': 'AMBIGUITY_CLARIFY',
        'negative feedback after clarification (must NOT auto-generate)': 'design_discussion',
        'product help': 'product_help',
    }
    expected = expected_categories[label]
    ok = t_post.final_route == expected
    mark = '✓' if ok else '✗'
    print(f'  {mark} {label}')
    print(f'      msg={msg!r}  iteration={it}  hist_len={len(hist)}')
    print(f'      final_route={t_post.final_route}  sub={t_post.final_sub}'
          f'  expected={expected}  ok={ok}')

print()
print('═' * 80)
print('DONE')
print('═' * 80)
