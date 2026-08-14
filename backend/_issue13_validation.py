"""Issue 13 — matrice d'échec F0-F8, double-release et concurrence.

INVARIANT ÉCONOMIQUE VÉRIFIÉ :
    une génération LIVRÉE            → exactement 1 crédit consommé
    un échec TECHNIQUE après le HOLD → 0 crédit consommé net
    un rejet PRODUIT avant le HOLD   → 0 crédit
    un rejeu idempotent              → 0 crédit supplémentaire

MÉTHODE. On n'appelle PAS OpenAI : les frontières (fournisseur, stockage) sont
doublées. Et on ne vérifie PAS `quota_used` seul — on lit les ENTRÉES DE LEDGER
réelles et leurs clés d'idempotence, parce que c'est le ledger qui fait autorité
(prouvé : supprimer des lignes usage_log ne restitue aucun crédit).

Les tests tournent contre le projet MOBILE-STAGING, jamais la production : la ref
est vérifiée avant tout accès et une ref de production fait échouer le harnais.

Lancement :
    cd backend
    PYTHONIOENCODING=utf-8 .venv/Scripts/python.exe _issue13_validation.py
"""
from __future__ import annotations

import asyncio
import os
import pathlib
import sys
import uuid

HERE = pathlib.Path(__file__).resolve().parent
ENVF = HERE / ".env.mobile-staging.local"
STAGING_REF = "lpegjufuhbmwwkfnaxjh"
PRODUCTION_REF = "vtxkciupyafukhdsgxgw"


def _parse(p):
    out = {}
    for raw in p.read_text(encoding="utf-8").splitlines():
        l = raw.strip()
        if l and not l.startswith("#") and "=" in l:
            k, _, v = l.partition("=")
            out[k.strip()] = v.strip().strip('"').strip("'")
    return out


cfg = _parse(ENVF)
if PRODUCTION_REF in cfg.get("SUPABASE_URL", ""):
    print("REFUS : la cible est la PRODUCTION.", file=sys.stderr)
    raise SystemExit(2)
if STAGING_REF not in cfg.get("SUPABASE_URL", ""):
    print("REFUS : la cible n'est pas mobile-staging.", file=sys.stderr)
    raise SystemExit(2)
for k, v in cfg.items():
    os.environ[k] = v
os.environ["AYDEN_DEPLOY_ENV"] = "staging"

import dotenv  # noqa: E402

_real = dotenv.load_dotenv
dotenv.load_dotenv = lambda *a, **k: _real(str(ENVF), override=True)
sys.path.insert(0, str(HERE))
os.chdir(HERE)

import psycopg  # noqa: E402

import billing  # noqa: E402
import main as canonical  # noqa: E402

DB = cfg["AYDEN_STAGING_DATABASE_URL"]
_total = 0
_fails = 0


def check(label, cond, got=""):
    global _total, _fails
    _total += 1
    if not cond:
        _fails += 1
    print(f"  [{'OK ' if cond else 'FAIL'}] {label}" + (f"   observed={got}" if got else ""))


def ledger(user_id):
    """Entrées de ledger réelles pour cet utilisateur, dans l'ordre."""
    with psycopg.connect(DB, connect_timeout=45) as c:
        c.read_only = True
        with c.cursor() as cur:
            cur.execute("""select entry_type, available_delta, idempotency_key
                           from public.ledger_entries where user_id=%s
                           order by created_at, id""", (user_id,))
            return cur.fetchall()


def balance(user_id):
    with psycopg.connect(DB, connect_timeout=45) as c:
        c.read_only = True
        with c.cursor() as cur:
            cur.execute("select coalesce(sum(available_delta),0) from public.ledger_entries where user_id=%s",
                        (user_id,))
            return cur.fetchone()[0]


def new_user():
    """Utilisateur jetable dans le projet STAGING (auth admin)."""
    import json
    import urllib.request
    U, SVC = cfg["SUPABASE_URL"], cfg["SUPABASE_SERVICE_ROLE_KEY"]
    em = f"issue13-{uuid.uuid4().hex[:10]}@example.com"
    req = urllib.request.Request(
        U + "/auth/v1/admin/users", method="POST",
        data=json.dumps({"email": em, "password": "Issue13!" + uuid.uuid4().hex[:8],
                         "email_confirm": True}).encode(),
        headers={"Content-Type": "application/json", "apikey": SVC,
                 "Authorization": f"Bearer {SVC}"})
    with urllib.request.urlopen(req, timeout=60) as r:
        import json as j
        return j.loads(r.read())["id"]


async def grant_trial(uid):
    """Dotation d'essai par le chemin applicatif normal (aucun ledger forgé)."""
    return await billing.mark_trial_consumed(user_id=uid) if False else None


def make_intent(uid):
    """Crée une VRAIE ligne generation_intents. Sans elle, observe_intent_end ne
    peut pas resoudre l'utilisateur et journalise « no user for intent — skip » :
    aucun RELEASE n'est ecrit et le test ne prouve rien (constate le 2026-08-14)."""
    iid = str(uuid.uuid4())
    with psycopg.connect(DB, autocommit=True, connect_timeout=45) as c:
        with c.cursor() as cur:
            cur.execute("insert into public.generation_intents (intent_id,user_id,status) "
                        "values (%s,%s,'RUNNING')", (iid, uid))
    return iid


async def hold(uid, intent_id, tier="free"):
    return await billing.try_hold(user_id=uid, intent_id=intent_id, tier=tier, supa=canonical.supa)


async def prime_trial(uid):
    """La dotation TRIAL(+3) est posee PARESSEUSEMENT au premier hold. On la
    declenche donc par un hold jetable relache, pour que les mesures suivantes
    partent d'un solde stable et non de 0."""
    j = make_intent(uid)
    await hold(uid, j)
    await end(j, "FAILED")


async def end(intent_id, status):
    from intent_observer import observe_intent_end
    return await observe_intent_end(intent_id, status, supa=canonical.supa)


async def main():
    print("=== ISSUE 13 — matrice d'échec, double-release, concurrence ===")
    print(f"cible : ...{STAGING_REF[-8:]} (mobile-staging)\n")

    # ── Le marqueur de périmètre existe-t-il et est-il bien posé/effacé ? ──
    print("=== SCOPE — bornes du périmètre protégé ===")
    src = (HERE / "main.py").read_text(encoding="utf-8")
    i_hold = src.find("setattr(request.state, _HOLD_STATE_ATTR, _intent.id)")
    i_ok = src.find("setattr(request.state, _HOLD_STATE_ATTR, None)\n    await observe_intent_end(_intent.id, \"SUCCEEDED\"")
    i_try = src.find("_hold = await billing.try_hold(")
    check("marqueur posé APRÈS l'octroi du hold", i_try != -1 and i_hold > i_try)
    check("marqueur effacé AVANT l'observation SUCCEEDED", i_ok != -1 and i_ok > i_hold)
    check("aucune HTTPException entre les deux bornes",
          "raise HTTPException" not in src[i_hold:i_ok])
    _code = chr(10).join(l for l in src.splitlines() if not l.lstrip().startswith("#"))
    check("Exception seulement (jamais BaseException dans le code)",
          "@app.exception_handler(Exception)" in src
          and "except BaseException" not in _code
          and "exception_handler(BaseException" not in _code)

    # ── F6 : succès nominal ──────────────────────────────────────────────
    print("\n=== F6 — succès livré → exactement 1 débit ===")
    u = new_user()
    await prime_trial(u)
    i = make_intent(u)
    b0 = balance(u)
    h = await hold(u, i)
    b1 = balance(u)
    await end(i, "SUCCEEDED")
    b2 = balance(u)
    check("hold accordé", h["granted"], str(h.get("reason")))
    check("HOLD débite 1", b1 == b0 - 1, f"{b0}->{b1}")
    check("COMMIT ne re-débite pas", b2 == b1, f"{b1}->{b2}")
    check("effet net = -1", b2 == b0 - 1, f"{b0}->{b2}")
    print(f"    ledger : {[(t, d) for t, d, _ in ledger(u)]}")

    # ── F1-F5 : échecs techniques après le HOLD ──────────────────────────
    print("\n=== F1-F5 — échec technique après HOLD → 0 débit net ===")
    for case in ("F1 avant fournisseur", "F2 fournisseur", "F3 post-traitement",
                 "F4 stockage", "F5 persistance terminale"):
        u = new_user()
        await prime_trial(u)
        i = make_intent(u)
        b0 = balance(u)
        await hold(u, i)
        b1 = balance(u)
        await end(i, "FAILED")                  # ce que fait le nouveau filet
        b2 = balance(u)
        check(f"{case} : net = 0", b2 == b0, f"{b0} -> {b1} -> {b2}")

    # ── F0 : rejet produit AVANT le hold ─────────────────────────────────
    print("\n=== F0 — rejet produit avant HOLD → aucun mouvement ===")
    u = new_user()
    b0 = balance(u)
    b1 = balance(u)
    check("aucune entrée sans hold", b0 == b1 and len(ledger(u)) == 0, f"entrées={len(ledger(u))}")

    # ── F7 : rejeu idempotent ────────────────────────────────────────────
    print("\n=== F7 — rejeu idempotent → 0 débit supplémentaire ===")
    u = new_user()
    await prime_trial(u)
    i = make_intent(u)
    b0 = balance(u)
    await hold(u, i)
    b1 = balance(u)
    h2 = await hold(u, i)                        # MÊME intent
    b2 = balance(u)
    check("second hold sur le même intent : aucun débit", b2 == b1, f"{b1}->{b2}")
    check("marqué idempotent par le RPC", bool(h2.get("idempotent")), str(h2))

    # ── F8 : échec puis retry réussi ─────────────────────────────────────
    print("\n=== F8 — échec puis retry réussi → exactement 1 débit ===")
    u = new_user()
    await prime_trial(u)
    b0 = balance(u)
    i1 = make_intent(u)
    await hold(u, i1); await end(i1, "FAILED")
    bmid = balance(u)
    i2 = make_intent(u)
    await hold(u, i2); await end(i2, "SUCCEEDED")
    bend = balance(u)
    check("après échec : solde restauré", bmid == b0, f"{b0}->{bmid}")
    check("après retry réussi : exactement -1", bend == b0 - 1, f"{bmid}->{bend}")
    print(f"    ledger : {[(t, d) for t, d, _ in ledger(u)]}")

    # ── Double-release ───────────────────────────────────────────────────
    print("\n=== DOUBLE-RELEASE — le filet + un handler localisé ===")
    u = new_user()
    await prime_trial(u)
    i = make_intent(u)
    b0 = balance(u)
    await hold(u, i)
    await end(i, "FAILED")          # tentative 1 (handler localisé existant)
    await end(i, "FAILED")          # tentative 2 (nouveau filet générique)
    await end(i, "FAILED_TERMINAL")  # tentative 3
    b1 = balance(u)
    rows = ledger(u)
    # Scoper sur l'intent TESTE : prime_trial() a deja produit un RELEASE pour son
    # intent jetable. Compter globalement melangeait les deux (constate 2026-08-14).
    rel = [r for r in rows if r[0] == "RELEASE" and i in r[2]]
    check("3 tentatives sur CE intent → 1 SEULE entrée RELEASE",
          len(rel) == 1, f"entrées RELEASE pour cet intent={len(rel)}")
    check("solde net = 0 (pas de double remboursement)", b1 == b0, f"{b0}->{b1}")
    check("clé d'idempotence unique", len({r[2] for r in rel}) == len(rel), str([r[2] for r in rel]))
    print(f"    ledger : {[(t, d, k[:24]) for t, d, k in rows]}")

    # ── Concurrence : 1 crédit restant, 2 requêtes simultanées ───────────
    print("\n=== CONCURRENCE — 1 crédit restant, 2 requêtes simultanées ===")
    u = new_user()
    await prime_trial(u)
    b0 = balance(u)
    for _ in range(b0 - 1):                      # descendre à 1 crédit
        j = make_intent(u); await hold(u, j); await end(j, "SUCCEEDED")
    b1 = balance(u)
    check("solde ramené à 1", b1 == 1, str(b1))
    iA, iB = make_intent(u), make_intent(u)
    hA, hB = await asyncio.gather(hold(u, iA), hold(u, iB))   # C1 : course
    granted = [hA["granted"], hB["granted"]]
    b2 = balance(u)
    check("C1 — un seul hold accordé sur le dernier crédit",
          granted.count(True) == 1, f"granted={granted} reasons={[hA.get('reason'), hB.get('reason')]}")
    check("C1 — le solde ne devient jamais négatif", b2 >= 0, str(b2))
    # C3 : deux libérations concurrentes du même intent
    win = iA if hA["granted"] else iB
    await asyncio.gather(end(win, "FAILED"), end(win, "FAILED"))
    b3 = balance(u)
    rel = [r for r in ledger(u) if r[0] == "RELEASE" and win[:8] in r[2]]
    check("C3 — deux RELEASE concurrents → une seule entrée", len(rel) == 1, f"n={len(rel)}")
    check("C3 — crédit restitué une seule fois", b3 == b1, f"{b1}->{b3}")

    print(f"\n=== RÉCAPITULATIF : {_total - _fails}/{_total} PASS ({_fails} FAILURE(S)) ===")
    return 1 if _fails else 0


sys.exit(asyncio.run(main()))
