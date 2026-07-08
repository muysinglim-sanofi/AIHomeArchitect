"""Fix "adopt completed generations" — backend LECTURE SEULE.

Prouve que get_latest_intent_for_session enrichit sa réponse avec after_image_url
dérivé de result_ref, SANS jamais écrire :
  • V1 /generate : result_ref = payload complet → after_image_url (clé directe)
  • /refine      : result_ref → generated_image_url mappé vers after_image_url
  • RUNNING sans result_ref → after_image_url == "" , has_result == False
  • SUCCEEDED avec result_ref sans URL → after_image_url == "" (ne pas inventer)
  • owner check : mauvais user_id → None (filtre eq)
0 réseau, faux Supabase.
"""
import os, sys, asyncio, logging
from types import SimpleNamespace
sys.path.insert(0, os.path.dirname(__file__))
logging.disable(logging.CRITICAL)

import intent_observer as IO

PASS = "\033[92mPASS\033[0m"; FAIL = "\033[91mFAIL\033[0m"
res = []
def check(label, cond, detail=""):
    res.append(cond)
    print(f"  {PASS if cond else FAIL}  {label}{('  ['+str(detail)+']') if detail and not cond else ''}")


class FQ:
    def __init__(self, rows): self._rows = rows; self._f = {}; self._n = None; self._o = None
    def select(self, *a, **k): return self
    def eq(self, c, v): self._f[c] = v; return self
    def order(self, col, desc=False, **k): self._o = (col, desc); return self
    def limit(self, n): self._n = n; return self
    def execute(self):
        out = [r for r in self._rows if all(r.get(k) == v for k, v in self._f.items())]
        if self._o:
            out = sorted(out, key=lambda r: r.get(self._o[0]) or "", reverse=self._o[1])
        return SimpleNamespace(data=out[: self._n] if self._n else out)


class FakeSupa:
    def __init__(self, intents, messages=None):
        self.tables = {"generation_intents": intents, "messages": messages or []}
    def table(self, name): return FQ(self.tables.get(name, []))


SID = "d953698c-8852-4914-9153-d34b517e118e"
UID = "user-abc"


async def main():
    print("\n=== 1. V1 SUCCEEDED : result_ref = payload complet → after_image_url ===")
    rows = [{"intent_id": "584bd718", "status": "SUCCEEDED", "iteration": 1,
             "user_id": UID, "session_id": SID,
             "result_ref": {"after_image_url": "https://s/generated/v1.jpg",
                            "thumbnail_url": "https://s/generated/v1.jpg", "versions": "[]"}}]
    r = await IO.get_latest_intent_for_session(user_id=UID, session_id=SID, supa=FakeSupa(rows))
    check("1a status SUCCEEDED + has_result", r and r["status"] == "SUCCEEDED" and r["has_result"] is True, r)
    check("1b after_image_url = payload.after_image_url", r and r["after_image_url"] == "https://s/generated/v1.jpg", r)

    print("\n=== 2. /refine SUCCEEDED : result_ref.generated_image_url → after_image_url ===")
    rows = [{"intent_id": "refine:xyz", "status": "SUCCEEDED", "iteration": 2,
             "user_id": UID, "session_id": SID,
             "result_ref": {"generated_image_url": "https://s/generated/refine.jpg",
                            "result_version_id": "vrf_x"}}]
    r = await IO.get_latest_intent_for_session(user_id=UID, session_id=SID, supa=FakeSupa(rows))
    check("2a after_image_url = generated_image_url (mapping refine)",
          r and r["after_image_url"] == "https://s/generated/refine.jpg", r)

    print("\n=== 3. RUNNING sans result_ref → after_image_url vide, has_result False ===")
    rows = [{"intent_id": "run1", "status": "RUNNING", "iteration": 1,
             "user_id": UID, "session_id": SID, "result_ref": None}]
    r = await IO.get_latest_intent_for_session(user_id=UID, session_id=SID, supa=FakeSupa(rows))
    check("3a RUNNING : after_image_url == '' et has_result False",
          r and r["after_image_url"] == "" and r["has_result"] is False, r)

    print("\n=== 4. SUCCEEDED mais result_ref sans URL → after_image_url vide (ne pas inventer) ===")
    rows = [{"intent_id": "s2", "status": "SUCCEEDED", "iteration": 1,
             "user_id": UID, "session_id": SID,
             "result_ref": {"intent_id": "s2", "iteration": 1}}]  # aucune clé image
    r = await IO.get_latest_intent_for_session(user_id=UID, session_id=SID, supa=FakeSupa(rows))
    check("4a after_image_url == '' quand result_ref n'a pas d'URL", r and r["after_image_url"] == "", r)
    check("4b has_result reste True (result_ref présent)", r and r["has_result"] is True, r)

    print("\n=== 5. owner check : mauvais user_id → None ===")
    rows = [{"intent_id": "s3", "status": "SUCCEEDED", "iteration": 1,
             "user_id": UID, "session_id": SID,
             "result_ref": {"after_image_url": "https://s/x.jpg"}}]
    r = await IO.get_latest_intent_for_session(user_id="someone-else", session_id=SID, supa=FakeSupa(rows))
    check("5a autre user → None (filtre user_id+session_id conservé)", r is None, r)

    print("\n=== 6. session inconnue ('new') → None (jamais de requête) ===")
    r = await IO.get_latest_intent_for_session(user_id=UID, session_id="new", supa=FakeSupa(rows))
    check("6a session_id='new' → None", r is None, r)

    print("\n=== 7. V1 RÉPARÉ par le reconcile : SUCCEEDED + result_ref=None → repli message image_result ===")
    intents = [{"intent_id": "rep1", "status": "SUCCEEDED", "iteration": 1,
                "user_id": UID, "session_id": SID, "result_ref": None}]
    messages = [  # ordre volontairement mélangé : le repli doit prendre le PLUS RÉCENT
        {"session_id": SID, "message_type": "image_result",
         "after_image_url": "https://s/generated/OLDER.jpg", "created_at": "2026-07-08T04:00:00+00:00"},
        {"session_id": SID, "message_type": "image_result",
         "after_image_url": "https://s/generated/reconciled.jpg", "created_at": "2026-07-08T04:21:00+00:00"},
        {"session_id": "AUTRE", "message_type": "image_result",  # autre session → ignoré
         "after_image_url": "https://s/generated/LEAK.jpg", "created_at": "2026-07-08T05:00:00+00:00"},
    ]
    r = await IO.get_latest_intent_for_session(user_id=UID, session_id=SID, supa=FakeSupa(intents, messages))
    check("7a SUCCEEDED sans result_ref → after_image_url dérivé du dernier image_result de la session",
          r and r["after_image_url"] == "https://s/generated/reconciled.jpg", r)
    check("7b has_result reste False (result_ref est None)", r and r["has_result"] is False, r)

    print("\n=== 8. RUNNING sans result_ref → PAS de repli message (after vide) ===")
    intents = [{"intent_id": "run2", "status": "RUNNING", "iteration": 1,
                "user_id": UID, "session_id": SID, "result_ref": None}]
    messages = [{"session_id": SID, "message_type": "image_result",
                 "after_image_url": "https://s/x.jpg", "created_at": "2026-07-08T04:21:00+00:00"}]
    r = await IO.get_latest_intent_for_session(user_id=UID, session_id=SID, supa=FakeSupa(intents, messages))
    check("8a RUNNING : pas de repli (gaté SUCCEEDED) → after_image_url ''", r and r["after_image_url"] == "", r)

    total = len(res); passed = sum(res)
    print(f"\n{'='*60}\n  TOTAL {total}  PASSED {passed}  FAILED {total-passed}\n{'='*60}")
    sys.exit(0 if passed == total else 1)


asyncio.run(main())
