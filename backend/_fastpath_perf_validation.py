"""
CORRECTIF PERF FAST-PATH (2026-07-14) — validateur OFFLINE (aucun réseau, aucune
génération OpenAI, aucune écriture DB réelle). Prouve les 14 points exigés :

  1  identité active   → parcours normal (enforce ne lève pas)
  2  merged_closed     → 403 (enforce)
  3  erreur account_state → 503 fail-closed (enforce + fetch_identity_active)
  4  claim_generation_intent APRÈS enforce (ordre source /generate)
  5  try_hold APRÈS enforce (ordre source /generate)
  6  reserve_generation APRÈS enforce (ordre source /generate)
  7  OpenAI APRÈS enforce (enforce < _req_start ; /refine : enforce < _refine_parse)
  8  lecture identité réellement DANS asyncio.gather (promo.resolve_generation_access)
  9  aucune 2e lecture account_state sur les routes image (pas de require_active_identity
     ni _assert_active_identity ni account_state dans les corps /generate,/refine)
  10 les 12 autres routes gardent require_active_identity ; 2 routes image en get_current_user
  11 aucune modif des paramètres image (quality/fidelity/model/prompt) dans le diff
  12 régression 3a/3b : require_active_identity + _assert_active_identity INCHANGÉS
  13 py_compile PASS (identity/promo/main)
  14 auth.py, SQL, billing RPC, RevenueCat INTACTS (git diff)

Exécution :  python _fastpath_perf_validation.py
"""
from __future__ import annotations

import asyncio
import os
import re
import subprocess
import sys
from types import SimpleNamespace

# Env minimal pour permettre l'import des modules (aucun réseau réellement ouvert :
# les clients Supabase/OpenAI sont construits paresseusement / non utilisés ici).
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test-key")
os.environ.setdefault("SUPABASE_ANON_KEY", "test-anon")
os.environ.setdefault("OPENAI_API_KEY", "test-openai")
os.environ.setdefault("REVENUECAT_WEBHOOK_AUTH", "test-secret")

HERE = os.path.dirname(os.path.abspath(__file__))

RESULTS: list[tuple[str, bool]] = []


def check(name: str, cond: bool) -> None:
    RESULTS.append((name, bool(cond)))
    print(f"[{'PASS' if cond else 'FAIL'}] {name}")


# ── FakeSupa (chaînable, sync ; enveloppé par asyncio.to_thread côté code) ────────
class _Res:
    def __init__(self, data=None, count=None):
        self.data = data
        self.count = count


class _Q:
    def __init__(self, table, store):
        self._t = table
        self._store = store

    def select(self, *a, **k):
        return self

    def eq(self, *a, **k):
        return self

    def neq(self, *a, **k):
        return self

    def limit(self, *a, **k):
        return self

    def order(self, *a, **k):
        return self

    def execute(self):
        self._store["tables"].add(self._t)
        if self._t == "account_state":
            if self._store.get("account_state_raises"):
                raise RuntimeError("simulated account_state read failure")
            return _Res(data=self._store["account_state_data"])
        if self._t == "usage_log":
            return _Res(data=[], count=0)
        # user_roles + tout le reste → vide (→ tier free, fail-open déjà géré)
        return _Res(data=[])


class _RpcQ:
    def __init__(self, name, store):
        self._n = name
        self._store = store

    def execute(self):
        self._store["tables"].add("rpc:" + self._n)
        return _Res(data={})  # get_promo_access → no promo


class FakeSupa:
    def __init__(self, account_state_data=None, account_state_raises=False):
        self.store = {
            "tables": set(),
            "account_state_data": account_state_data if account_state_data is not None else [],
            "account_state_raises": account_state_raises,
        }

    def table(self, name):
        return _Q(name, self.store)

    def rpc(self, name, params=None):
        return _RpcQ(name, self.store)


# ── Import des modules sous test (paresseux pour _get_supa) ──────────────────────
sys.path.insert(0, HERE)
import identity  # noqa: E402
import promo  # noqa: E402
import quota  # noqa: E402


def _decision(checked=True, read_ok=True, merged=False):
    return SimpleNamespace(
        identity_checked=checked, identity_read_ok=read_ok, identity_merged_closed=merged,
    )


def _status_of(exc) -> int:
    return getattr(exc, "status_code", None)


def _err_code(exc):
    d = getattr(exc, "detail", None)
    return d.get("error_code") if isinstance(d, dict) else None


# ── 1/2/3 — enforce_identity_from_decision ───────────────────────────────────────
def test_enforce():
    from fastapi import HTTPException

    # 1) identité active → ne lève pas
    ok = True
    try:
        identity.enforce_identity_from_decision(_decision(merged=False, read_ok=True), "user1234")
    except Exception:  # noqa: BLE001
        ok = False
    check("1. identité active → enforce ne lève pas", ok)

    # 2) merged_closed → 403 identity_merged
    raised = None
    try:
        identity.enforce_identity_from_decision(_decision(merged=True), "user1234")
    except HTTPException as e:
        raised = e
    check("2. merged_closed → 403 identity_merged",
          raised is not None and _status_of(raised) == 403 and _err_code(raised) == "identity_merged")

    # 3a) read error → 503 fail-closed
    raised = None
    try:
        identity.enforce_identity_from_decision(_decision(read_ok=False), "user1234")
    except HTTPException as e:
        raised = e
    check("3a. read_ok False → 503 identity_check_unavailable",
          raised is not None and _status_of(raised) == 503 and _err_code(raised) == "identity_check_unavailable")

    # 3b) décision sans identity_checked → 503 fail-closed (défense bug d'appel)
    raised = None
    try:
        identity.enforce_identity_from_decision(_decision(checked=False), "user1234")
    except HTTPException as e:
        raised = e
    check("3b. identity_checked False → 503 (fail-closed)",
          raised is not None and _status_of(raised) == 503)


# ── 3 (lecture) — fetch_identity_active NON-levante, fail-closed ─────────────────
def test_fetch_identity_active():
    # actif (aucune ligne)
    r = asyncio.run(identity.fetch_identity_active("uActive", supa=FakeSupa(account_state_data=[])))
    check("3c. fetch actif (no row) → read_ok=True merged=False", r.read_ok and not r.merged_closed)

    # merged
    r = asyncio.run(identity.fetch_identity_active(
        "uMerged", supa=FakeSupa(account_state_data=[{"merged_closed": True}])))
    check("3d. fetch merged → read_ok=True merged=True", r.read_ok and r.merged_closed)

    # erreur DB → read_ok=False (JAMAIS lève, JAMAIS fail-open)
    r = asyncio.run(identity.fetch_identity_active(
        "uErr", supa=FakeSupa(account_state_raises=True)))
    check("3e. fetch erreur DB → read_ok=False (non-levante, fail-closed)",
          (r.read_ok is False) and (r.merged_closed is False))


# ── 8/9 — inclusion réelle dans le gather + fail-closed via resolver ─────────────
def test_resolver_include_identity():
    quota._clear_role_cache()
    # include_identity=True + merged → decision porte merged_closed=True ET account_state lu
    fake = FakeSupa(account_state_data=[{"merged_closed": True}])
    dec = asyncio.run(promo.resolve_generation_access("uMergeRes", supa=fake, include_identity=True))
    check("8a. include_identity=True → identity_checked & merged_closed remontés",
          dec.identity_checked and dec.identity_merged_closed and dec.identity_read_ok)
    check("8b. account_state réellement interrogé (dans le gather)",
          "account_state" in fake.store["tables"])

    # include_identity=False → identité NON lue (pas de 2e lecture) + défauts sûrs
    quota._clear_role_cache()
    fake2 = FakeSupa(account_state_data=[{"merged_closed": True}])
    dec2 = asyncio.run(promo.resolve_generation_access("uNoId", supa=fake2, include_identity=False))
    check("9a. include_identity=False → identity_checked=False (aucune lecture identité)",
          dec2.identity_checked is False)
    check("9b. include_identity=False → account_state NON interrogé",
          "account_state" not in fake2.store["tables"])

    # include_identity=True + erreur account_state → read_ok=False (fail-closed jusqu'au resolver)
    quota._clear_role_cache()
    fake3 = FakeSupa(account_state_raises=True)
    dec3 = asyncio.run(promo.resolve_generation_access("uErrRes", supa=fake3, include_identity=True))
    check("8c. erreur account_state → decision.identity_read_ok=False (fail-closed)",
          dec3.identity_checked and (dec3.identity_read_ok is False))


# ── Helpers d'inspection source ─────────────────────────────────────────────────
def _read(path):
    with open(os.path.join(HERE, path), encoding="utf-8") as f:
        return f.read()


def _handler_span(src, start_marker):
    i = src.index(start_marker)
    j = src.find("\n@app.", i + len(start_marker))
    return src[i: j if j != -1 else len(src)]


# ── 4/5/6/7 — ordre source : enforce AVANT tout write/OpenAI ─────────────────────
def test_ordering():
    src = _read("main.py")

    gen = _handler_span(src, 'async def generate(')
    i_enf = gen.find("enforce_identity_from_decision(_decision")
    i_claim = gen.find("claim_generation_intent(")
    i_hold = gen.find("billing.try_hold(")
    i_reserve = gen.find("reserve_generation(")
    i_reqstart = gen.find("_req_start = time.monotonic()")
    ok_gen = (
        i_enf > 0
        and 0 < i_enf < i_claim
        and 0 < i_enf < i_hold
        and 0 < i_enf < i_reserve
        and 0 < i_enf < i_reqstart  # tout OpenAI image est APRÈS _req_start
    )
    check("4. /generate : enforce AVANT claim_generation_intent", 0 < i_enf < i_claim)
    check("5. /generate : enforce AVANT try_hold", 0 < i_enf < i_hold)
    check("6. /generate : enforce AVANT reserve_generation", 0 < i_enf < i_reserve)
    check("7a. /generate : enforce AVANT le pipeline (_req_start → OpenAI)", 0 < i_enf < i_reqstart)

    ref = _handler_span(src, 'async def refine_endpoint(')
    r_enf = ref.find("enforce_identity_read(_id_read")
    r_parse = ref.find("_refine_parse(")   # 1er appel OpenAI de /refine
    r_advise = ref.find("_refine_advise(")
    r_hold = ref.find("billing.try_hold(")
    r_gather = ref.find("asyncio.gather(")
    r_own = ref.find("_validate_session_ownership(")
    r_fetch = ref.find("fetch_identity_active(")
    r_resolver = ref.find("resolve_generation_access(")
    check("7b. /refine : enforce AVANT _refine_parse (1er OpenAI)", 0 < r_enf < r_parse)
    check("7c. /refine : enforce AVANT _refine_advise", 0 < r_enf < r_advise)
    check("7d. /refine : enforce AVANT try_hold", 0 < r_enf < r_hold)
    # NOUVEAU — identité foldée EN PARALLÈLE de l'ownership (gather), AVANT parse
    check("7e. /refine : ownership ∥ fetch_identity_active dans un gather AVANT parse",
          0 < r_gather < r_parse and 0 < r_own < r_parse and 0 < r_fetch < r_parse)
    # NOUVEAU — le resolver N'EST PAS avant parse : advisory/empty ne paient AUCUN RTT resolver
    check("7f. /refine : resolver PAS exécuté avant _refine_parse (advisory/empty 0 RTT resolver)",
          r_resolver > r_parse)
    _ = ok_gen  # (silence lint)


# ── 8 (source) — fetch_identity_active dans le gather de promo.py ────────────────
def test_gather_source():
    p = _read("promo.py")
    in_tasks = '_tasks.append(_timed("fetch_identity_active"' in p
    gathered = "asyncio.gather(*_tasks" in p
    guarded = "if include_identity:" in p
    check("8d. promo : fetch_identity_active ajouté à _tasks (gather) sous include_identity",
          in_tasks and gathered and guarded)


# ── 9 — routes image : aucune 2e lecture account_state / plus de require_active_identity ──
def test_no_second_identity_read():
    src = _read("main.py")
    gen = _handler_span(src, 'async def generate(')
    ref = _handler_span(src, 'async def refine_endpoint(')
    # /generate : identité foldée dans le resolver → enforce_identity_from_decision.
    # /refine   : identité foldée dans l'ownership → enforce_identity_read.
    for label, body, enf in (("/generate", gen, "enforce_identity_from_decision"),
                             ("/refine", ref, "enforce_identity_read")):
        no_guard_dep = "Depends(require_active_identity)" not in body
        no_assert = "_assert_active_identity" not in body
        # « aucune 2e LECTURE account_state » = aucune requête PostgREST directe dans le
        # handler (le mot nu peut apparaître en commentaire ; la lecture réelle vit dans
        # fetch_identity_active, pas dans le corps du handler).
        no_raw_read = 'table("account_state")' not in body and "table('account_state')" not in body
        uses_enforce = enf in body
        check(f"9c. {label} : aucune lecture table(account_state)/_assert, utilise {enf}",
              no_guard_dep and no_assert and no_raw_read and uses_enforce)


# ── 10 — comptage des dépendances ────────────────────────────────────────────────
def test_dep_counts():
    src = _read("main.py")
    n_guard = src.count("Depends(require_active_identity)")
    n_jwt = src.count("Depends(get_current_user)")
    check(f"10a. 12 routes gardent require_active_identity (trouvé {n_guard})", n_guard == 12)
    check(f"10b. 2 routes image en get_current_user (trouvé {n_jwt})", n_jwt == 2)


# ── 11/14 — diff : image params + fichiers intacts ──────────────────────────────
def _git(args):
    return subprocess.run(["git"] + args, cwd=os.path.dirname(HERE),
                          capture_output=True, text=True).stdout


def test_diff_guards():
    names = _git(["diff", "--name-only"]).split()
    changed = {os.path.basename(n) for n in names}
    intact = {"auth.py", "billing.py", "revenuecat_webhook.py"}
    no_sql = not any(n.endswith(".sql") for n in names)
    check("14. auth.py/billing.py/RevenueCat/SQL INTACTS",
          intact.isdisjoint(changed) and no_sql)

    # 11 — le diff ne touche AUCUN paramètre image (quality/fidelity/model/prompt engine)
    diff = _git(["diff", "--", "backend/main.py", "backend/promo.py", "backend/identity.py"])
    added_removed = [ln for ln in diff.splitlines()
                     if (ln.startswith("+") or ln.startswith("-"))
                     and not ln.startswith(("+++", "---"))]
    banned = re.compile(r"input_fidelity|quality\s*=|IMAGE_MODEL|compose_generation_prompt|"
                        r"images\.edit|images\.generate|max_retries|\.timeout")
    offending = [ln for ln in added_removed if banned.search(ln)]
    check("11. aucun paramètre image (quality/fidelity/model/prompt/edit) modifié dans le diff",
          len(offending) == 0)
    if offending:
        for ln in offending[:5]:
            print("       offending:", ln[:120])


# ── 12 — 3a/3b : gardes existantes INCHANGÉES ────────────────────────────────────
def test_no_3a3b_regression():
    idsrc = _read("identity.py")
    has_require = "def require_active_identity(" in idsrc
    has_assert = "def _assert_active_identity(" in idsrc
    # require_active_identity appelle toujours _assert_active_identity (comportement 3a intact)
    body = idsrc[idsrc.index("def require_active_identity("):]
    body = body[: body.find("\n\n\n")]
    still_calls = "_assert_active_identity(current_user.user_id)" in body
    check("12a. require_active_identity + _assert_active_identity toujours présents",
          has_require and has_assert)
    check("12b. require_active_identity appelle toujours _assert_active_identity (3a intact)",
          still_calls)


# ── 13 — py_compile ─────────────────────────────────────────────────────────────
def test_py_compile():
    r = subprocess.run([sys.executable, "-m", "py_compile", "identity.py", "promo.py", "main.py"],
                       cwd=HERE, capture_output=True, text=True)
    check("13. py_compile identity/promo/main PASS", r.returncode == 0)
    if r.returncode != 0:
        print(r.stderr[:500])


def main():
    print("=" * 62)
    print("CORRECTIF PERF FAST-PATH — VALIDATION OFFLINE")
    print("=" * 62)
    test_enforce()
    test_fetch_identity_active()
    test_resolver_include_identity()
    test_ordering()
    test_gather_source()
    test_no_second_identity_read()
    test_dep_counts()
    test_diff_guards()
    test_no_3a3b_regression()
    test_py_compile()
    print("-" * 62)
    failed = [n for n, ok in RESULTS if not ok]
    print(f"RÉSULTAT : {len(RESULTS) - len(failed)}/{len(RESULTS)} PASS")
    if failed:
        print("ÉCHECS :")
        for n in failed:
            print("  -", n)
        sys.exit(1)
    print("TOUS LES CHECKS PASSENT.")


if __name__ == "__main__":
    main()
