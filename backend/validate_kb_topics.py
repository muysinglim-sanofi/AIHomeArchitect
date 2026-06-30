"""
Régression KB Support — couverture des sujets ajoutés/étendus (2026-06-30) +
familles dynamiques (change/preservation → RESULT_EXPLANATION voice).
Component-level (déterministe, pas de serveur).

Run:  backend/.venv/Scripts/python.exe validate_kb_topics.py   (exit 0 = OK)
"""
import sys
from prompt_engine.product_knowledge import detect_product_help as topic
from prompt_engine.conversation_router import detect_result_explanation as is_result_expl

# (question, topic_id attendu) — formulations naturelles utilisateur
KB_CASES = [
    ("how does ayden decide work?", "ayden_decide"),
    ("why did ayden choose the room type?", "ayden_decide"),
    ("what is ayden signature?", "ayden_signature"),
    ("can you pick the best atmosphere for me?", "ayden_signature"),
    ("what photo works best?", "photo_requirements"),
    ("can I upload an occupied room?", "photo_requirements"),
    ("empty room or furnished?", "photo_requirements"),
    ("portrait or landscape?", "photo_requirements"),
    ("why can't I upload?", "photo_requirements"),
    ("how long does it take?", "generation_duration"),
    ("why is it so slow?", "generation_duration"),
    ("why is it still generating?", "generation_duration"),
    ("what is the difference between continue vision and re-upload?", "mode_comparison"),
    ("preserve or creative?", "mode_comparison"),
    ("difference between ayden signature and atmospheres?", "mode_comparison"),
    ("where should I start?", "workflow_coaching"),
    ("what's the best workflow?", "workflow_coaching"),
    ("are my images used to train AI?", "data_privacy"),
    ("are my photos public?", "data_privacy"),
    ("does it work outside?", "supported_room_types"),
    ("can it redesign my garden?", "supported_room_types"),
    ("can it redesign a facade?", "supported_room_types"),
    ("can you keep my layout?", "preserve_mode"),
    ("generation timed out", "support_generation_failed"),
    # garde-fous : non-comparaison → sujet spécifique (pas mode_comparison)
    ("how does continue vision work?", "continue_vision"),
    ("what is re-upload?", "re_upload"),
]

# Familles dynamiques : change/preservation = RESULT_EXPLANATION (voix), PAS un
# topic KB statique (la voix explique CE rendu). True attendu.
RESULT_EXPL_POS = [
    "why did you move my sofa?",
    "why did you remove my TV?",
    "why did you change the windows?",
    "why didn't you preserve my room?",
    "why isn't my architecture preserved?",
    "why did my room change?",
]
# Ne doivent PAS être pris pour une explication de résultat
RESULT_EXPL_NEG = [
    "why should I use preserve?",
    "how do I keep my layout?",
    "why is rectangular better?",
]

fails = 0
for q, exp in KB_CASES:
    got = topic(q, "en")
    if got != exp:
        print(f"[FAIL] KB  {q!r} -> {got} (exp {exp})"); fails += 1
for q in RESULT_EXPL_POS:
    if not is_result_expl(q):
        print(f"[FAIL] result_expl(+) {q!r} not detected"); fails += 1
for q in RESULT_EXPL_NEG:
    if is_result_expl(q):
        print(f"[FAIL] result_expl(-) {q!r} false positive"); fails += 1

print(f"{'ALL PASS' if fails == 0 else str(fails) + ' FAILURE(S)'} "
      f"({len(KB_CASES)} KB + {len(RESULT_EXPL_POS)+len(RESULT_EXPL_NEG)} result-expl checks)")
sys.exit(1 if fails else 0)
