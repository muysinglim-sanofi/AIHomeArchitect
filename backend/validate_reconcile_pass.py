"""P0 (2026-07-10) — reconcile_pass_from_subscriber : restore/sync → pass MESURÉ.

Pur (FakeSupa + spy sur grant_purchase, 0 DB/0 réseau). Vérifie les GARDE-FOUS et
l'idempotence PAR CONSTRUCTION (la clé de GRANT = store_transaction_id du cycle,
jamais original_transaction_id → grant_purchase ON CONFLICT dédup → 5x = 1 GRANT,
même cycle que le webhook = pas de double). Le dédup réel en base est prouvé par
grant_purchase (RC-PR2 + E2E). Ici on prouve QUE reconcile appelle grant_purchase
avec le bon tx, et sinon renvoie restore_required sans jamais créer de pass arbitraire.
"""
import os, sys, asyncio, logging
sys.path.insert(0, os.path.dirname(__file__))
logging.disable(logging.CRITICAL)

import billing
from billing import GrantResult, ProductNotMapped

PASS = "\033[92mPASS\033[0m"; FAIL = "\033[91mFAIL\033[0m"
res = []
def check(label, cond, detail=""):
    res.append(bool(cond))
    print(f"  {PASS if cond else FAIL}  {label}{('  ['+str(detail)+']') if detail and not cond else ''}")

# ── spy sur grant_purchase (le chemin idempotent réel) ──────────────────────
calls = []
async def _spy_grant(**kw):
    calls.append(kw)
    if kw["store_product_id"] == "com.unmapped":
        raise ProductNotMapped(kw["store_product_id"])
    return GrantResult(ok=True, status="granted", credited=True, credits=30,
                       order_id="order-1", pass_id="pass-1")
billing.grant_purchase = _spy_grant   # reconcile appelle le global du module → patché

FUTURE = "2099-01-01T00:00:00Z"
PAST = "2000-01-01T00:00:00Z"
WEEKLY = "com.aydenstudio.app.weekly"

def _sub(*, product=WEEKLY, expires=FUTURE, store_tx="TX-CYCLE-123",
         original_tx="ORIG-999", with_ent=True, with_sub=True):
    ent = {"expires_date": expires, "product_identifier": product} if with_ent else {}
    subs = {}
    if with_sub and product:
        s = {}
        if store_tx is not None:
            s["store_transaction_id"] = store_tx
        s["original_transaction_id"] = original_tx
        subs[product] = s
    return {"entitlements": {"premium": ent}, "subscriptions": subs}

def recon(subscriber):
    calls.clear()
    return asyncio.run(billing.reconcile_pass_from_subscriber(
        user_id="user-1", subscriber=subscriber, supa=object()))


print("\n=== P0 · reconcile_pass_from_subscriber ===")

# 1. active weekly + store_tx + expires → grant appelé → pass
r = recon(_sub())
check("1 active weekly + store_tx + expires → state=pass + grant appelé 1x",
      r["state"] == "pass" and r["has_measurable_pass"] and len(calls) == 1, (r, calls))

# 2. clé = store_transaction_id (CYCLE), JAMAIS original_transaction_id
r = recon(_sub(store_tx="TX-CYCLE-123", original_tx="ORIG-999"))
c = calls[0] if calls else {}
check("2 grant provider_transaction_id = store_transaction_id (cycle), pas original",
      c.get("provider_transaction_id") == "TX-CYCLE-123"
      and c.get("provider_transaction_id") != "ORIG-999"
      and c.get("store_product_id") == WEEKLY, c)

# 3. 5x reconcile → 5x grant avec le MÊME tx (ancre idempotente → RPC ON CONFLICT dédup)
txs = []
for _ in range(5):
    recon(_sub(store_tx="TX-SAME"))
    txs.append(calls[0]["provider_transaction_id"] if calls else None)
check("3 5x reconcile → même provider_transaction_id à chaque fois (=> 1 GRANT au niveau RPC)",
      txs == ["TX-SAME"] * 5, txs)

# 4. store_transaction_id absent → restore_required, AUCUN grant
r = recon(_sub(store_tx=None))
check("4 store_transaction_id absent → restore_required + AUCUN grant",
      r["state"] == "restore_required" and r["reason"] == "insufficient_rc_data"
      and len(calls) == 0, (r, calls))

# 5. produit non mappé → grant lève ProductNotMapped → restore_required
r = recon(_sub(product="com.unmapped"))
check("5 produit non mappé → restore_required (reason=product_not_mapped)",
      r["state"] == "restore_required" and r["reason"] == "product_not_mapped", r)

# 6. expiration absente (None = lifetime) → restore_required (pas de pass sans période)
r = recon(_sub(expires=None))
check("6 expires_date absent → restore_required + AUCUN grant",
      r["state"] == "restore_required" and r["reason"] == "insufficient_rc_data"
      and len(calls) == 0, (r, calls))

# 7. active + (rôle premium sans pass) → reconcile crée le pass (indépendant du rôle)
r = recon(_sub())
check("7 abo actif (rôle sans pass) → reconcile CRÉE le pass mesuré",
      r["state"] == "pass" and r["has_measurable_pass"], r)

# 8. pas d'abo actif (entitlement expiré) → free, AUCUN grant, jamais premium
r = recon(_sub(expires=PAST))
check("8 entitlement expiré → state=free, AUCUN grant, jamais premium",
      r["state"] == "free" and not r["has_measurable_pass"] and len(calls) == 0, (r, calls))

# 8b. pas d'entitlement du tout → free
r = recon(_sub(with_ent=False))
check("8b aucun entitlement premium → state=free", r["state"] == "free" and len(calls) == 0)

# 9. annual → grant appelé avec le produit annual (mapping distinct)
r = recon(_sub(product="com.aydenstudio.app.annual"))
check("9 active annual → grant appelé (store_product_id=annual)",
      r["state"] == "pass" and calls and calls[0]["store_product_id"] == "com.aydenstudio.app.annual", r)

# ── PATCH 2 (2026-07-16) — OWNERSHIP : un pass MESURÉ n'est déclaré QUE si le user COURANT
#     possède le pass. La clé order:provider:tx est USER-AGNOSTIQUE → une transaction déjà
#     accordée sous un AUTRE user renvoie un result.pass_id ÉTRANGER (grant already_processed,
#     credited=False). Sans le garde, reconcile renvoyait 'pass' à tort (faux « Purchase
#     restored » alors que le guest reste free). ──────────────────────────────────────────────
print("\n=== PATCH 2 · reconcile ownership (bloque le faux 'restored' cross-user) ===")

_owner_calls = []
def _make_grant(credited, pass_id="pass-x"):
    async def _g(**kw):
        calls.append(kw)
        return GrantResult(ok=True, status="granted" if credited else "already_processed",
                           credited=credited, credits=30, order_id="order-x", pass_id=pass_id)
    return _g
def _make_owner(owner):
    async def _po(supa, pass_id):
        _owner_calls.append(pass_id)
        return owner
    return _po

# A. credited=False (already_processed) + pass appartenant au user COURANT → state=pass
billing.grant_purchase = _make_grant(credited=False)
billing._pass_owner = _make_owner("user-1")
r = recon(_sub())
check("A already_processed + pass appartient au user courant → state=pass",
      r["state"] == "pass" and r["has_measurable_pass"], r)

# B. credited=False + pass appartenant à un AUTRE user → restore_required (AUCUN faux 'pass')
billing.grant_purchase = _make_grant(credited=False)
billing._pass_owner = _make_owner("other-user")
r = recon(_sub())
check("B already_processed + pass d'un AUTRE user → restore_required (aucun faux restored)",
      r["state"] == "restore_required" and not r["has_measurable_pass"]
      and r["reason"] == "pass_owned_by_other_user", r)

# C. credited=True (nouveau grant) → state=pass SANS consulter _pass_owner (short-circuit)
_owner_calls.clear()
billing.grant_purchase = _make_grant(credited=True)
billing._pass_owner = _make_owner("should-not-be-called")
r = recon(_sub())
check("C grant crédité (nouveau) → state=pass SANS lookup _pass_owner (pass forcément au user)",
      r["state"] == "pass" and r["has_measurable_pass"] and len(_owner_calls) == 0, (r, _owner_calls))

# D. credited=False + _pass_owner renvoie None (lecture DB KO / pass introuvable) → restore_required
#    (fail-CLOSED : jamais un faux 'pass' sur incertitude de propriété).
billing.grant_purchase = _make_grant(credited=False)
billing._pass_owner = _make_owner(None)
r = recon(_sub())
check("D already_processed + owner indéterminé (None) → restore_required (fail-closed)",
      r["state"] == "restore_required" and not r["has_measurable_pass"], r)

# ── PATCH 3 REDESIGN (2026-07-17) — RE-PARENT autorisé UNIQUEMENT si (1) transfert RC PROUVÉ côté
#     serveur ET (2) parenté Guest→Guest. Un entitlement RC actif NE SUFFIT PAS. Séparation OFF/ON :
#     tout transfert impliquant un Account est INTERDIT en ON (login / sign-out / merge). ──────────
print("\n=== PATCH 3 redesign · reconcile re-parent (autorisation stricte) ===")

_reparent_calls = []
def _make_reparent(return_val):
    async def _rp(supa, *, pass_id, from_user, to_user):
        _reparent_calls.append({"pass_id": pass_id, "from": from_user, "to": to_user})
        return return_val
    return _rp
def _make_is_anon(mapping):
    async def _ia(supa, uid):
        return mapping.get(uid)
    return _ia
def _make_transfer(val):
    async def _ht(supa, *, from_user, to_user, store_tx):
        return val
    return _ht
_orig_flag = billing.billing_reparent_enabled
_orig_mode = billing.account_system_enabled

def _setup(*, flag, from_anon=True, to_anon=True, transfer=True, reparent_ok=True,
           mode_on=False, credited=False, owner="other-user"):
    billing.billing_reparent_enabled = (lambda: flag)
    billing.account_system_enabled = (lambda: mode_on)
    billing.grant_purchase = _make_grant(credited=credited, pass_id="pass-strand")
    billing._pass_owner = _make_owner(owner)
    billing._is_anonymous = _make_is_anon({"other-user": from_anon, "user-1": to_anon})
    billing._has_authorized_rc_transfer = _make_transfer(transfer)
    _reparent_calls.clear(); billing.reparent_pass_to_current = _make_reparent(reparent_ok)

# E. flag OFF → re-parent JAMAIS tenté (PATCH 2 strict)
_setup(flag=False)
r = recon(_sub())
check("E flag OFF → restore_required + re-parent NON tenté (PATCH 2 strict)",
      r["state"] == "restore_required" and len(_reparent_calls) == 0, (r, _reparent_calls))

# F. flag ON + Guest→Guest + transfert RC PROUVÉ → RE-PARENT (other→user-1) → pass
_setup(flag=True, from_anon=True, to_anon=True, transfer=True)
r = recon(_sub())
check("F flag ON + Guest→Guest + transfert RC prouvé → RE-PARENT → state=pass",
      r["state"] == "pass" and len(_reparent_calls) == 1
      and _reparent_calls[0]["from"] == "other-user" and _reparent_calls[0]["to"] == "user-1", (r, _reparent_calls))

# F2. flag ON + Guest→Guest MAIS aucun transfert RC prouvé → REFUS (entitlement seul ≠ autorisation)
_setup(flag=True, from_anon=True, to_anon=True, transfer=False)
r = recon(_sub())
check("F2 flag ON + Guest→Guest SANS transfert RC prouvé → REFUS → restore_required",
      r["state"] == "restore_required" and len(_reparent_calls) == 0, (r, _reparent_calls))

# F3. ON + Guest→Account (login) → REFUS (jamais Premium Guest→Account)
_setup(flag=True, from_anon=True, to_anon=False, transfer=True, mode_on=True)
r = recon(_sub())
check("F3 ON + Guest→Account (login) → REFUS re-parent → restore_required",
      r["state"] == "restore_required" and len(_reparent_calls) == 0, (r, _reparent_calls))

# F4. ON + Account→Guest (sign-out) → REFUS (jamais pass Account→Guest)
_setup(flag=True, from_anon=False, to_anon=True, transfer=True, mode_on=True)
r = recon(_sub())
check("F4 ON + Account→Guest (sign-out) → REFUS re-parent → restore_required",
      r["state"] == "restore_required" and len(_reparent_calls) == 0, (r, _reparent_calls))

# G. flag ON + autorisé mais RPC re-parent ÉCHOUE → restore_required (fail-safe)
_setup(flag=True, reparent_ok=False)
r = recon(_sub())
check("G flag ON + autorisé + RPC re-parent échoue → restore_required (fail-safe)",
      r["state"] == "restore_required" and len(_reparent_calls) == 1, (r, _reparent_calls))

# H. flag ON + AUCUN entitlement actif (expiré) → free, re-parent JAMAIS atteint (anti-vol)
_setup(flag=True)
r = recon(_sub(expires=PAST))
check("H flag ON + entitlement EXPIRÉ → free + re-parent JAMAIS atteint (anti-vol)",
      r["state"] == "free" and len(_reparent_calls) == 0, (r, _reparent_calls))

# I. flag ON + pass DÉJÀ au user courant → pass, re-parent NON tenté
_setup(flag=True, owner="user-1")
r = recon(_sub())
check("I flag ON + pass déjà au user courant → state=pass, re-parent NON tenté",
      r["state"] == "pass" and len(_reparent_calls) == 0, (r, _reparent_calls))

# J. flag ON + credited=True (nouveau) → pass, re-parent NON tenté
_setup(flag=True, credited=True)
r = recon(_sub())
check("J flag ON + grant crédité (nouveau) → state=pass, re-parent NON tenté",
      r["state"] == "pass" and len(_reparent_calls) == 0, (r, _reparent_calls))

billing.billing_reparent_enabled = _orig_flag
billing.account_system_enabled = _orig_mode

total = len(res); passed = sum(res)
print(f"\n{'='*64}\n  TOTAL {total}  PASSED {passed}  FAILED {total-passed}\n{'='*64}")
sys.exit(0 if passed == total else 1)
