"""Wave 4.11d.1 validation — interrogative-form generation demand must
no longer be mis-classified as STOP_GENERATION, AND real stop-generation
requests must still fire."""
import sys
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

from prompt_engine.meta_intent import classify_meta_intent, MetaIntent
from prompt_engine.intent_classifier import (
    detect_generation_demand,
)

print('═' * 80)
print('Wave 4.11d.1 — Interrogative Generation Demand vs. STOP_GENERATION')
print('═' * 80)

# Group 1 — Real production input + variants that should NOT match STOP_GEN
# and should route via Wave 4.11d to GENERATE.
print('\n[Group 1] Interrogative demands — meta must be NONE, demand must fire')
interrog_demands = [
    "why you don't generate?",     # backend.log 2026-05-30 09:07:02 (verbatim)
    "why don't you generate?",     # canonical EN
    "why aren't you generating?",
    "why won't you generate?",
    "why can't you generate?",
    "how come you don't generate?",
    "are you not going to generate?",
    "pourquoi tu ne génères pas?",      # FR
    "pourquoi tu génères pas?",         # FR (informal)
    "pourquoi tu ne rends pas?",        # FR — "render"
]
group1_pass = 0
for msg in interrog_demands:
    meta = classify_meta_intent(msg)
    demand = detect_generation_demand(msg)
    meta_ok = meta.intent == MetaIntent.NONE
    end_to_end_ok = meta_ok and demand
    mark = '✓' if end_to_end_ok else '✗'
    if end_to_end_ok:
        group1_pass += 1
    print(f'  {mark} {msg!r:50}  meta={meta.intent.value:18} demand={demand}')

# Group 2 — Genuine STOP_GENERATION requests must still fire
print('\n[Group 2] Real STOP_GENERATION requests must still classify correctly')
stop_gen_cases = [
    "don't generate yet",
    "don't generate anything",
    "no, don't render that",
    "please don't make any changes",
    "let's discuss first, don't generate",
    "before generating, let's chat",
    "no image yet",
    "just talk for now",
    "let's discuss before generating",
    "ne génère pas encore",          # FR
    "pas de génération",              # FR
    "discutons d'abord",              # FR
    "juste discuter",                 # FR
]
group2_pass = 0
for msg in stop_gen_cases:
    meta = classify_meta_intent(msg)
    ok = meta.intent == MetaIntent.STOP_GENERATION
    mark = '✓' if ok else '✗'
    if ok:
        group2_pass += 1
    print(f'  {mark} {msg!r:55}  meta={meta.intent.value}')

# Group 3 — Adversarial : message contains "why" but is genuinely STOP
print('\n[Group 3] Adversarial — "why" present but real STOP intent must hold')
adversarial = [
    # Long sentence opening with "the reason why I don't want" — note this
    # was never a STOP_GENERATION case in pre-Wave 4.11d.1 either, because
    # _STOP_GENERATION requires "don't" adjacent to "generate" and here
    # "don't want to generate" interposes "want to". Expected: NONE.
    ("the reason why I don't want to generate yet is the lighting", 'none'),
    # Plain stop with mid-sentence "why" — anchor stays at message start
    # so "hold on — don't generate; …" still fires STOP_GEN normally.
    ("hold on — don't generate; tell me why this works first", 'stop_generation'),
]
group3_pass = 0
for msg, expected in adversarial:
    meta = classify_meta_intent(msg)
    ok = meta.intent.value == expected
    mark = '✓' if ok else '✗'
    if ok:
        group3_pass += 1
    print(f'  {mark} {msg!r:65}')
    print(f'      expected={expected}  got={meta.intent.value}')

# Group 4 — Adversarial : not a demand, must NOT fire generation_demand
print('\n[Group 4] Adversarial — non-demand "why" questions must not trigger demand')
non_demand = [
    "why does this room feel cold?",
    "why is the lighting warmer here?",
    "why did you choose oak?",
]
group4_pass = 0
for msg in non_demand:
    demand = detect_generation_demand(msg)
    meta = classify_meta_intent(msg)
    # These should NOT fire demand AND should NOT be classified as STOP_GEN
    ok = (not demand) and meta.intent != MetaIntent.STOP_GENERATION
    mark = '✓' if ok else '✗'
    if ok:
        group4_pass += 1
    print(f'  {mark} {msg!r:50}  meta={meta.intent.value} demand={demand}')

# Summary
total = (len(interrog_demands) + len(stop_gen_cases)
         + len(adversarial) + len(non_demand))
passed = group1_pass + group2_pass + group3_pass + group4_pass
print()
print('═' * 80)
print(f'Wave 4.11d.1 — Summary : {passed}/{total} pass')
print(f'  Group 1 (interrogative demands → meta NONE + demand)  : {group1_pass}/{len(interrog_demands)}')
print(f'  Group 2 (real STOP_GENERATION still fires)            : {group2_pass}/{len(stop_gen_cases)}')
print(f'  Group 3 (adversarial "why" in stop intent)            : {group3_pass}/{len(adversarial)}')
print(f'  Group 4 (non-demand "why" questions)                  : {group4_pass}/{len(non_demand)}')
print('═' * 80)
