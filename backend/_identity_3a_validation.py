"""
Validation Commit 3a (Unified Identity endpoints + garde). Déterministe, hors-ligne.

PART A — logique (appel direct des handlers/fonctions + faux Supabase).
PART B — HTTP RÉEL sans booter main.py : mini-app FastAPI(include_router) +
         ASGITransport + dependency_overrides → prouve l'ordre flag→JWT→garde,
         les codes HTTP, et le rejet strict du corps.

Run:  python _identity_3a_validation.py     (exit 0 = tout passe)
"""
import asyncio
import hashlib
import inspect
import io
import json
import logging
import os
import sys
from types import SimpleNamespace

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
os.chdir(HERE)
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")  # init JWKS (pas de fetch sans token)

import httpx  # noqa: E402
from fastapi import FastAPI, HTTPException  # noqa: E402
from fastapi.responses import JSONResponse  # noqa: E402
from pydantic import ValidationError  # noqa: E402

import auth  # noqa: E402
import identity  # noqa: E402
from auth import CurrentUser, get_current_user  # noqa: E402
from identity import ClaimBody  # noqa: E402

VALID = "T" * 40  # jeton plausible (URL-safe, 16..256)


# ── Faux client Supabase (compte les lectures) ───────────────────────────────
class _Query:
    def __init__(self, fake, table):
        self.fake, self.table, self._op, self._payload = fake, table, None, None
    def select(self, *a, **k): self._op = "select"; return self
    def eq(self, *a, **k): return self
    def limit(self, *a, **k): return self
    def insert(self, payload): self._op = "insert"; self._payload = payload; return self
    def execute(self):
        if self._op == "select":
            self.fake.reads += 1
            if self.fake.select_error is not None:
                raise self.fake.select_error
            return SimpleNamespace(data=list(self.fake.account_state_rows))
        if self._op == "insert":
            self.fake.inserts.append((self.table, self._payload))
            return SimpleNamespace(data=[self._payload])
        return SimpleNamespace(data=[])


class _Rpc:
    def __init__(self, fake, name, params): self.fake, self.name, self.params = fake, name, params
    def execute(self):
        self.fake.rpc_calls.append((self.name, dict(self.params)))
        if self.fake.rpc_error is not None:
            raise self.fake.rpc_error
        return SimpleNamespace(data=list(self.fake.rpc_data))


class FakeSupa:
    def __init__(self):
        self.account_state_rows = []
        self.select_error = None
        self.reads = 0
        self.inserts = []
        self.rpc_calls = []
        self.rpc_data = []
        self.rpc_error = None
    def table(self, name): return _Query(self, name)
    def rpc(self, name, params): return _Rpc(self, name, params)


def _use(fake): identity._get_supa = lambda: fake  # noqa: E731
def _run(coro): return asyncio.new_event_loop().run_until_complete(coro)

_fail = 0
def check(label, cond, detail=""):
    global _fail
    if not cond:
        _fail += 1
    print(f"[{'PASS' if cond else 'FAIL'}] {label}" + (f"  ({detail})" if detail and not cond else ""))


def expect_http(fn, code, error_code=None):
    try:
        fn(); return (False, "no HTTPException")
    except HTTPException as e:
        if e.status_code != code:
            return (False, f"status {e.status_code}!={code}")
        if error_code is not None:
            got = e.detail.get("error_code") if isinstance(e.detail, dict) else e.detail
            if got != error_code:
                return (False, f"error_code {got!r}!={error_code!r}")
        return (True, "")


print("── PART A — logique ──")

# 1. Hash exact
check("hash = sha256(utf-8).hexdigest()",
      identity._hash_ticket("héllo") == hashlib.sha256("héllo".encode("utf-8")).hexdigest()
      and len(identity._hash_ticket("x")) == 64)

# 2. Corps STRICT ClaimBody (Pydantic extra interdit + alphabet URL-safe)
def bad_body(**kw):
    try:
        ClaimBody(**kw); return False
    except ValidationError:
        return True
check("ClaimBody valide accepté", (not bad_body(ticket=VALID)) and ClaimBody(ticket=VALID).ticket == VALID)
check("ClaimBody champ 'to_user' rejeté", bad_body(ticket=VALID, to_user="EVIL"))
check("ClaimBody champ 'from_user_id' rejeté", bad_body(ticket=VALID, from_user_id="EVIL"))
check("ClaimBody champ 'p_to_user' rejeté", bad_body(ticket=VALID, p_to_user="EVIL"))
check("ClaimBody ticket manquant rejeté", bad_body())
for bad in ("", "short", "x" * 300, "has space", "tab\there", "new\nline", "star*char", " leadsp"):
    check(f"ClaimBody ticket invalide rejeté ({bad!r})", bad_body(ticket=bad))

# 3. Compte permanent → 400 not_anonymous (handler direct ; le flag est dans la dépendance)
f = FakeSupa(); _use(f)
ok, d = expect_http(lambda: _run(identity.create_merge_ticket(current_user=CurrentUser("B", False))), 400, "not_anonymous")
check("permanent → 400 not_anonymous", ok and f.inserts == [], d or f"inserts={f.inserts}")

# 4. Ticket créé pour le JWT A + hash conforme + brut une fois
f = FakeSupa(); _use(f)
resp = _run(identity.create_merge_ticket(current_user=CurrentUser("A-uuid", True)))
tok = resp.get("ticket", "")
tbl, payload = (f.inserts[0] if len(f.inserts) == 1 else ("", {}))
check("insert unique identity_merge_tickets", len(f.inserts) == 1 and tbl == "identity_merge_tickets")
check("from_user_id = JWT de A", payload.get("from_user_id") == "A-uuid", str(payload))
check("hash stocké = sha256(brut)", payload.get("ticket_hash") == hashlib.sha256(tok.encode()).hexdigest())
check("expires_at présent (TTL 5m)", "expires_at" in payload)
check("brut renvoyé au client", isinstance(tok, str) and len(tok) >= 16)

# 5. merge-ticket sans paramètre de corps
sig = inspect.signature(identity.create_merge_ticket)
check("merge-ticket sans corps", not any(p.name in ("payload", "body") for p in sig.parameters.values()))

# 6. claim → p_to_user = JWT de B, params RPC = {p_ticket_hash, p_to_user} seulement
f = FakeSupa(); f.rpc_data = [{"status": "revocation_pending", "merge_id": "m1", "metadata": {}}]; _use(f)
resp = _run(identity.claim_merge(body=ClaimBody(ticket=VALID), current_user=CurrentUser("B-uuid", False)))
name, params = (f.rpc_calls[0] if len(f.rpc_calls) == 1 else ("", {}))
check("claim appelle identity_claim_and_merge", name == "identity_claim_and_merge")
check("p_to_user = JWT de B", params.get("p_to_user") == "B-uuid", str(params))
check("p_ticket_hash = sha256(ticket)", params.get("p_ticket_hash") == hashlib.sha256(VALID.encode()).hexdigest())
check("RPC params = {p_ticket_hash, p_to_user}", set(params.keys()) == {"p_ticket_hash", "p_to_user"}, str(params))
check("revocation_pending → 200", isinstance(resp, JSONResponse) and resp.status_code == 200)

# 7. Mapping COMPLET des statuts (dont data_merged / failed / abandoned)
def mp(row):
    try:
        return ("resp", identity._map_rpc_row(row))
    except HTTPException as e:
        return ("exc", e)
_M = {
    "completed": (200, None), "revocation_pending": (200, None),
    "data_merged": (202, None), "billing_reconciliation_pending": (202, None),
    "waiting_for_settlement": (409, "settlement_active"),
    "billing_conflict_manual_review": (409, "both_users_premium"),
    "abandoned": (409, "identity_merge_abandoned"),
    "failed": (503, "identity_merge_failed"),
    "totally_unknown": (503, "identity_merge_unavailable"),
}
for st, (code, ec) in _M.items():
    k, v = mp({"status": st, "merge_id": "m", "metadata": {}})
    if code < 400:
        check(f"map {st} → {code}", k == "resp" and v.status_code == code)
    else:
        check(f"map {st} → {code} {ec}", k == "exc" and v.status_code == code and v.detail.get("error_code") == ec)
check("data_merged → status identity_merge_pending",
      json.loads(mp({"status": "data_merged", "merge_id": "m", "metadata": {}})[1].body)["status"] == "identity_merge_pending")
k, v = mp({"status": "conflict", "failure_code": "duplicate_merge_attempt", "metadata": {"existing_merge_id": "e1"}})
check("conflict/duplicate → 409 + existing_merge_id",
      v.status_code == 409 and v.detail["error_code"] == "duplicate_merge_attempt" and v.detail.get("existing_merge_id") == "e1")

# 8. Mapping des exceptions RPC (aucun texte brut renvoyé)
def rexc(msg):
    try:
        identity._raise_rpc_exception(Exception(msg))
    except HTTPException as e:
        return e
check("ticket_expired → 410", rexc("ERROR: ticket_expired").status_code == 410)
check("ticket_not_found → 404 ticket_invalid",
      rexc("ticket_not_found").status_code == 404 and rexc("ticket_not_found").detail["error_code"] == "ticket_invalid")
check("ticket_source_changed → 404", rexc("ticket_source_changed").status_code == 404)
check("PGRST202 → 503 identity_rpc_unavailable",
      rexc("PGRST202 could not find the function").detail["error_code"] == "identity_rpc_unavailable")
e = rexc("relation boom weird 42")
check("inconnu → 503 identity_merge_unavailable", e.status_code == 503 and e.detail["error_code"] == "identity_merge_unavailable")
check("aucun texte brut renvoyé", "relation boom weird 42" not in json.dumps(e.detail))

# 9. Garde merged_closed (unité)
f = FakeSupa(); f.account_state_rows = [{"merged_closed": True}]; _use(f)
ok, d = expect_http(lambda: identity.require_active_identity(current_user=CurrentUser("A", True)), 403, "identity_merged")
check("garde merged_closed=true → 403", ok, d)
f = FakeSupa(); _use(f)
check("garde ligne absente → passe", identity.require_active_identity(current_user=CurrentUser("A", True)).user_id == "A")
f = FakeSupa(); f.select_error = Exception("db down"); _use(f)
ok, d = expect_http(lambda: identity.require_active_identity(current_user=CurrentUser("A", True)), 503, "identity_check_unavailable")
check("garde erreur DB → 503 fail-closed", ok, d)

# 10. Couverture + garde indépendant du flag + logs propres + auth.py intact
main_src = open(os.path.join(HERE, "main.py"), encoding="utf-8").read()
check("14 routes basculées / 0 restante",
      main_src.count("Depends(require_active_identity)") == 14 and main_src.count("Depends(get_current_user)") == 0)
guard_src = inspect.getsource(identity._assert_active_identity) + inspect.getsource(identity.require_active_identity)
check("garde indépendant du flag", "IDENTITY_MERGE_ENDPOINTS_ENABLED" not in guard_src and "_merge_endpoints_enabled" not in guard_src)
buf = io.StringIO(); h = logging.StreamHandler(buf)
lg = logging.getLogger("aih.identity"); lg.addHandler(h); lg.setLevel(logging.DEBUG)
f = FakeSupa(); _use(f)
resp = _run(identity.create_merge_ticket(current_user=CurrentUser("A", True)))
tok = resp["ticket"]; th = hashlib.sha256(tok.encode()).hexdigest()
logs = buf.getvalue(); lg.removeHandler(h)
check("ticket brut jamais loggé", tok not in logs)
check("ticket_hash jamais loggé", th not in logs)
src = inspect.getsource(auth)
check("auth.py sans code de garde (optional intact)",
      "require_active_identity" not in src and "_assert_active_identity" not in src and "account_state" not in src)


# ── PART B — HTTP RÉEL (mini-app, dépendances FastAPI exécutées) ─────────────
print("── PART B — HTTP réel (mini-app) ──")

test_app = FastAPI()
test_app.include_router(identity.identity_router)
_STATE = {"fake": None}
identity._get_supa = lambda: _STATE["fake"]


def hreq(path, *, flag, user=None, json_body="__none__", content=None, fake=None):
    """Un appel HTTP réel contre la mini-app. user=None → pas d'override (auth
    réelle → 401 si flag ON). Renvoie (response, fake)."""
    os.environ["IDENTITY_MERGE_ENDPOINTS_ENABLED"] = "true" if flag else "false"
    fk = fake if fake is not None else FakeSupa()
    _STATE["fake"] = fk
    test_app.dependency_overrides.pop(get_current_user, None)
    if user is not None:
        test_app.dependency_overrides[get_current_user] = lambda u=user: u

    async def _go():
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=test_app), base_url="http://t") as c:
            kw = {}
            if content is not None:
                kw = {"content": content, "headers": {"content-type": "application/json"}}
            elif json_body != "__none__":
                kw = {"json": json_body}
            return await c.post(path, **kw)
    return _run(_go()), fk


A_ANON = CurrentUser("A-http", True)
B_PERM = CurrentUser("B-http", False)
A_CLOSED = CurrentUser("A-closed", True)

# flag OFF → 404 sans JWT, et AUCUNE lecture account_state
r, fk = hreq("/identity/merge-ticket", flag=False)
check("flag OFF sans JWT → 404", r.status_code == 404, f"got {r.status_code}")
check("flag OFF → aucune lecture account_state", fk.reads == 0, f"reads={fk.reads}")

# flag OFF avec compte fermé → 404, toujours aucune lecture
fc = FakeSupa(); fc.account_state_rows = [{"merged_closed": True}]
r, fk = hreq("/identity/claim", flag=False, user=A_CLOSED, json_body={"ticket": VALID}, fake=fc)
check("flag OFF + compte fermé → 404", r.status_code == 404, f"got {r.status_code}")
check("flag OFF + fermé → aucune lecture account_state", fk.reads == 0, f"reads={fk.reads}")

# flag ON sans JWT → 401 (auth réelle)
r, _ = hreq("/identity/merge-ticket", flag=True)
check("flag ON sans JWT → 401", r.status_code == 401, f"got {r.status_code}")

# flag ON + A fermé → 403 (garde exécuté)
fc = FakeSupa(); fc.account_state_rows = [{"merged_closed": True}]
r, fk = hreq("/identity/merge-ticket", flag=True, user=A_CLOSED, fake=fc)
check("flag ON + A fermé → 403", r.status_code == 403 and r.json()["detail"]["error_code"] == "identity_merged", f"got {r.status_code}")
check("flag ON + fermé → lecture account_state exécutée", fk.reads == 1, f"reads={fk.reads}")

# flag ON + A anonyme actif → 200 (ticket créé)
r, fk = hreq("/identity/merge-ticket", flag=True, user=A_ANON)
check("flag ON + A anon actif → 200", r.status_code == 200 and "ticket" in r.json(), f"got {r.status_code}")
check("insert from_user_id = JWT A", fk.inserts and fk.inserts[0][1]["from_user_id"] == "A-http")

# claim : corps avec champ supplémentaire → 422
r, _ = hreq("/identity/claim", flag=True, user=B_PERM, json_body={"ticket": VALID, "to_user": "EVIL"})
check("claim corps champ supplémentaire → 422", r.status_code == 422, f"got {r.status_code}")

# claim : corps liste → 422 ; corps null → 422
r, _ = hreq("/identity/claim", flag=True, user=B_PERM, json_body=[1, 2, 3])
check("claim corps liste → 422", r.status_code == 422, f"got {r.status_code}")
r, _ = hreq("/identity/claim", flag=True, user=B_PERM, content="null")
check("claim corps null → 422", r.status_code == 422, f"got {r.status_code}")

# claim : ticket avec espace / tab / newline → 422
for bad in ("has space", "tab\ttab", "new\nline"):
    r, _ = hreq("/identity/claim", flag=True, user=B_PERM, json_body={"ticket": bad})
    check(f"claim ticket invalide → 422 ({bad!r})", r.status_code == 422, f"got {r.status_code}")

# claim : corps correct → RPC appelé avec p_to_user = JWT de B, réponse 200
fok = FakeSupa(); fok.rpc_data = [{"status": "revocation_pending", "merge_id": "m9", "metadata": {}}]
r, fk = hreq("/identity/claim", flag=True, user=B_PERM, json_body={"ticket": VALID}, fake=fok)
check("claim valide → 200", r.status_code == 200 and r.json()["status"] == "revocation_pending", f"got {r.status_code} {r.text}")
check("claim → p_to_user = JWT de B (HTTP)", fk.rpc_calls and fk.rpc_calls[0][1]["p_to_user"] == "B-http", str(fk.rpc_calls))

test_app.dependency_overrides.clear()

print(f"\n{'ALL PASS' if _fail == 0 else str(_fail) + ' FAILURE(S)'}")
sys.exit(1 if _fail else 0)
