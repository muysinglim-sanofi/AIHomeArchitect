"""Canonical Conversation #2 replay : 'make it better' actually triggers
ambiguity in current code, then user answer should resolve to GENERATE."""
import sys
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

from prompt_engine.ambiguity_detector import detect_ambiguity
from prompt_engine.intent_classifier import (
    detect_generation_demand, is_clarification_answer,
    last_assistant_was_clarification,
)

clar = detect_ambiguity('make it better', 2, language='en', room_type='living_room')
print(f"V2 'make it better' → ambiguity = {clar.ambiguity_id if clar else None}")
print()
print("Assistant clarification text (real, from ambiguity_detector):")
print(clar.clarification_text[:120].replace('\n', ' | '))
print()

hist = [
    {'role': 'user', 'content': 'make it better'},
    {'role': 'assistant', 'content': clar.clarification_text},
]
print('--- V3 answer probes (PRE vs POST Wave 4.11d) ---')
for ans in ['the material palette', 'lighting register', 'warmer materials',
            'material palette']:
    last_was_clar = last_assistant_was_clarification(hist)
    is_answer = is_clarification_answer(ans, hist)
    print(f"V3 user: {ans!r:30} last_clar={last_was_clar}  is_answer={is_answer}")
