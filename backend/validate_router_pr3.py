"""
Régression PR3-router (Ayden Companion) — les 2 prompts réels qui régressaient,
+ garde-fous. Teste le VRAI /chat (ASGI in-process, boucle unique). AYDEN_VOICE=0
pour isoler le ROUTING (pas la voix LLM). Auth + quota patchés.

Run:  backend/.venv/Scripts/python.exe validate_router_pr3.py
Exit 0 = tout passe.
"""
import os, sys, asyncio
os.environ["AYDEN_VOICE"] = "0"          # on teste le routing, pas la voix
os.environ["MULTILINGUAL_NORMALIZE"] = "0"
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); os.chdir(HERE)

from types import SimpleNamespace as NS
import main
from auth import CurrentUser, get_current_user
async def _fa(uid, *, supa=None):
    return NS(tier="free", free_remaining=3, promo_unlimited_active=False,
              promo_generations_remaining=0, can_generate=True)
main.resolve_generation_access = _fa
main.app.dependency_overrides[get_current_user] = lambda: CurrentUser(
    user_id="reg", is_anonymous=False, email="r@l", raw_claims={})
import httpx

CASES = [
    # (label, message, room, iteration, assert_fn(j) -> (ok, detail))
    ("TV opinion → DESIGN_ADVICE", "I put the TV in front of the window?", "living_room", "2",
     lambda j: (j["context"]["mode"] == "design_advice" and j["should_generate"] is False,
                f'mode={j["context"]["mode"]} sg={j["should_generate"]}')),
    ("re-upload → PRODUCT_HELP", "What is the re-upload?", "living_room", "1",
     lambda j: (j["context"]["mode"] == "product_help" and "re-upload" in (j["ai_message"] or "").lower(),
                f'mode={j["context"]["mode"]} msg={(j["ai_message"] or "")[:60]!r}')),
    # garde-fous : une vraie commande reste une génération
    ("command stays GENERATE", "make it warmer", "living_room", "2",
     lambda j: (j["should_generate"] is True, f'sg={j["should_generate"]} mode={j["context"]["mode"]}')),
    # OOS inchangé
    ("OOS unchanged", "what is the capital of Japan?", "living_room", "1",
     lambda j: (j["context"]["mode"] == "out_of_scope", f'mode={j["context"]["mode"]}')),
]


async def run():
    failures = 0
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=main.app), base_url="http://t") as c:
        for label, msg, room, it, check in CASES:
            r = await c.post("/chat", data=dict(
                session_id="new", style_label="Warm Modern", message=msg,
                room_type=room, iteration=it, has_vision="1", ui_locale="en"), timeout=30)
            j = r.json()
            ok, detail = check(j)
            print(f"[{'PASS' if ok else 'FAIL'}] {label}  ({detail})")
            if not ok:
                failures += 1
    print(f"\n{'ALL PASS' if failures == 0 else str(failures) + ' FAILURE(S)'}")
    return failures


sys.exit(1 if asyncio.run(run()) else 0)
