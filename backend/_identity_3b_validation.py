"""
Validation Commit 3b (révocation Auth). Déterministe, hors-ligne (faux Supabase).
Importe main (env factice, aucun réseau à l'import) pour tester l'isolation du worker.
À lancer avec le venv (deps backend). Exit 0 = tout passe.
"""
import os, sys, asyncio, inspect, threading
from types import SimpleNamespace

os.environ.setdefault("SUPABASE_URL", "https://dummy.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "dummy")
os.environ.setdefault("OPENAI_API_KEY", "dummy")
os.environ["IDENTITY_AUTH_REVOCATION_ENABLED"] = "true"

WB = r"C:\Projects\AIHomeArchitect-uiv1\backend"
sys.path.insert(0, WB); os.chdir(WB)
import identity  # noqa: E402
import main      # noqa: E402  (pour _reconcile_cycle)
from identity import ClaimBody  # noqa: E402
from auth import CurrentUser  # noqa: E402

M0 = {"merge_id": "m1", "from_user_id": "A", "to_user_id": "B", "status": "revocation_pending"}
BU = "2099-01-01T00:00:00+00:00"


# ── Faux Supabase (stateful) ─────────────────────────────────────────────────
class _Admin:
    def __init__(s, f): s.f = f
    def update_user_by_id(s, uid, attrs):
        s.f.ban_calls.append((uid, dict(attrs)))
        if s.f.ban_barrier is not None:               # force l'interleaving (concurrence)
            try: s.f.ban_barrier.wait(timeout=5)
            except Exception: pass
        if s.f.ban_raises: raise s.f.ban_raises
        if not s.f.confirm_fails: s.f.banned[uid] = True
        rid = s.f.ban_result_id if s.f.ban_result_id is not None else uid
        bu = None if (s.f.ban_result_no_banned_until or s.f.confirm_fails) else BU
        return SimpleNamespace(user=SimpleNamespace(id=rid, banned_until=bu))
    def get_user_by_id(s, uid):
        s.f.get_calls.append(uid)
        if s.f.getuser_raises: raise s.f.getuser_raises
        return SimpleNamespace(user=SimpleNamespace(id=uid, banned_until=(BU if s.f.banned.get(uid) else None)))
    def delete_user(s, uid, *a, **k):
        s.f.delete_calls.append(uid)


class _Q:
    def __init__(s, f, t): s.f = f; s.t = t; s.op = None; s.payload = None; s.filters = {}
    def select(s, *a, **k): s.op = "select"; return s
    def update(s, p): s.op = "update"; s.payload = p; return s
    def eq(s, c, v): s.filters[c] = v; return s
    def limit(s, n): s.f.limit_calls.append(n); return s
    def order(s, c, desc=False): s.f.order_calls.append((c, desc)); return s
    def execute(s):
        m = s.f.merge
        if s.op == "select": s.f.select_filtersets.append(frozenset(s.filters.keys()))
        if s.op == "update":
            with s.f.cas_lock:                        # CAS atomique (compare-and-set)
                if s.t == "identity_merges" and m and all(m.get(k) == v for k, v in s.filters.items()):
                    m.update(s.payload); s.f.update_applied += 1
                    s.f.update_filtersets.append(frozenset(s.filters.keys()))
                return SimpleNamespace(data=[dict(m)] if m else [])
        if s.t == "identity_merges":
            if set(s.filters.keys()) == {"status"}:
                rows = [m] if (m and m.get("status") == s.filters["status"]) else []
                return SimpleNamespace(data=[{"merge_id": r["merge_id"]} for r in rows])
            if m and all(m.get(k) == v for k, v in s.filters.items()):
                return SimpleNamespace(data=[dict(m)])
            return SimpleNamespace(data=[])
        return SimpleNamespace(data=[])


class FakeSupa:
    def __init__(s, merge=None):
        s.merge = dict(merge) if merge else None
        s.banned = {}; s.ban_calls = []; s.get_calls = []; s.delete_calls = []
        s.order_calls = []; s.limit_calls = []; s.update_applied = 0
        s.select_filtersets = []; s.update_filtersets = []
        s.ban_raises = None; s.getuser_raises = None
        s.ban_result_id = None; s.ban_result_no_banned_until = False; s.confirm_fails = False
        s.ban_barrier = None; s.cas_lock = threading.Lock()
        s.auth = SimpleNamespace(admin=_Admin(s))
    def table(s, name): return _Q(s, name)


def _use(f): identity._get_supa = lambda: f  # noqa: E731
def _run(coro): return asyncio.new_event_loop().run_until_complete(coro)
def on(): os.environ["IDENTITY_AUTH_REVOCATION_ENABLED"] = "true"
def off(): os.environ["IDENTITY_AUTH_REVOCATION_ENABLED"] = "false"

_fail = 0
def chk(label, cond, detail=""):
    global _fail
    if not cond: _fail += 1
    print(f"[{'PASS' if cond else 'FAIL'}] {label}" + (f"  ({detail})" if detail and not cond else ""))


print("── finalize_revocation ──")
on()
chk("signature = finalize_revocation(merge_id) uniquement",
    list(inspect.signature(identity.finalize_revocation).parameters) == ["merge_id"])

off(); f = FakeSupa(dict(M0)); _use(f)
chk("flag OFF → flag_off, aucun ban", _run(identity.finalize_revocation("m1")) == "flag_off" and f.ban_calls == [])
on()

f = FakeSupa(None); _use(f)
chk("ligne absente → row_absent, aucun ban", _run(identity.finalize_revocation("m1")) == "row_absent" and not f.ban_calls)

f = FakeSupa({**M0, "status": "completed"}); _use(f)
chk("statut ≠ revocation_pending → not_finalizable, aucun ban", _run(identity.finalize_revocation("m1")) == "not_finalizable" and not f.ban_calls)

for bad, lab in (({**M0, "from_user_id": None}, "from_user_id manquant"),
                 ({**M0, "to_user_id": None}, "to_user_id manquant"),
                 ({**M0, "to_user_id": "A"}, "A == B")):
    f = FakeSupa(bad); _use(f)
    chk(f"{lab} → aucun ban", _run(identity.finalize_revocation("m1")) == "not_finalizable" and not f.ban_calls)

f = FakeSupa("WRONG" and dict(M0)); _use(f)
chk("mauvais merge_id → row_absent, ligne intacte, aucun ban",
    _run(identity.finalize_revocation("WRONG")) == "row_absent" and f.merge["status"] == "revocation_pending" and not f.ban_calls)

# happy path
f = FakeSupa(dict(M0)); _use(f)
r = _run(identity.finalize_revocation("m1"))
chk("ban OK → completed", r == "completed" and f.merge["status"] == "completed")
chk("A banni = from_user_id DB (jamais fourni)", f.ban_calls and f.ban_calls[0][0] == "A")
chk("ban_duration = 876000h", f.ban_calls and f.ban_calls[0][1] == {"ban_duration": "876000h"})
chk("CAS ciblé {merge_id, from_user_id, status}", f.update_filtersets and f.update_filtersets[0] == {"merge_id", "from_user_id", "status"})
chk("confirmation CAS inclut from_user_id", any("from_user_id" in fs for fs in f.select_filtersets))
chk("aucun delete_user (finalize ne supprime jamais)", f.delete_calls == [])

# ban échoue → pending
f = FakeSupa(dict(M0)); f.ban_raises = Exception("boom"); _use(f)
chk("ban échoue → ban_error, reste pending", _run(identity.finalize_revocation("m1")) == "ban_error" and f.merge["status"] == "revocation_pending")
# retry après échec → completed
f2 = FakeSupa(f.merge); _use(f2)
chk("retry après échec → completed", _run(identity.finalize_revocation("m1")) == "completed" and f2.merge["status"] == "completed")
# 2e retry sur completed → no-op
chk("2e retry sur completed → not_finalizable (no-op)", _run(identity.finalize_revocation("m1")) == "not_finalizable")

# update renvoie un autre user.id → id_mismatch, pending
f = FakeSupa(dict(M0)); f.ban_result_id = "OTHER"; _use(f)
chk("update autre user.id → id_mismatch, pending", _run(identity.finalize_revocation("m1")) == "id_mismatch" and f.merge["status"] == "revocation_pending")

# banned_until absent → confirmation via get_user_by_id → completed
f = FakeSupa(dict(M0)); f.ban_result_no_banned_until = True; _use(f)
r = _run(identity.finalize_revocation("m1"))
chk("banned_until absent → get_user_by_id confirme → completed", r == "completed" and f.get_calls == ["A"] and f.merge["status"] == "completed")

# confirmation impossible → ban_unconfirmed, pending
f = FakeSupa(dict(M0)); f.confirm_fails = True; _use(f)
chk("banned_until jamais confirmé → ban_unconfirmed, pending", _run(identity.finalize_revocation("m1")) == "ban_unconfirmed" and f.merge["status"] == "revocation_pending")

print("── sweep_pending_revocations ──")
off(); f = FakeSupa(dict(M0)); _use(f)
chk("sweep flag OFF → 0, aucun ban", _run(identity.sweep_pending_revocations()) == 0 and not f.ban_calls)
on()
f = FakeSupa(dict(M0)); _use(f)
n = _run(identity.sweep_pending_revocations())
chk("sweep flag ON → 1 traité, ligne completed", n == 1 and f.merge["status"] == "completed")
chk("sweep order started_at asc", f.order_calls == [("started_at", False)])
chk("sweep n'ordonne JAMAIS sur created_at (colonne absente de identity_merges)",
    all(col != "created_at" for col, _ in f.order_calls))
chk("sweep limit 20", 20 in f.limit_calls)
f = FakeSupa({**M0, "status": "failed"}); _use(f)
chk("sweep ignore status ≠ revocation_pending", _run(identity.sweep_pending_revocations()) == 0 and not f.ban_calls)

print("── schedule + callback (fire-and-forget) ──")
off()
before = len(identity._revocation_bg)
identity.schedule_revocation("m1")
chk("schedule flag OFF → aucune tâche", len(identity._revocation_bg) == before)
on()

async def _sched():
    called = []
    orig = identity.finalize_revocation
    async def spy(mid): called.append(mid); return "completed"
    identity.finalize_revocation = spy
    try:
        identity.schedule_revocation("mZ")
        assert len(identity._revocation_bg) >= 1
        await asyncio.sleep(0.05)
        return called, len(identity._revocation_bg)
    finally:
        identity.finalize_revocation = orig
called, remaining = _run(_sched())
chk("schedule flag ON → finalize(merge_id) invoqué", called == ["mZ"])
chk("tâche retirée du set après complétion", remaining == 0)

async def _done():
    async def boom(): raise ValueError("x")
    t = asyncio.create_task(boom()); identity._revocation_bg.add(t); t.add_done_callback(identity._revocation_done)
    await asyncio.sleep(0.02)
    async def slow(): await asyncio.sleep(10)
    t2 = asyncio.create_task(slow()); identity._revocation_bg.add(t2); t2.add_done_callback(identity._revocation_done)
    t2.cancel(); await asyncio.sleep(0.02)
    return t.done() and t2.cancelled() and len(identity._revocation_bg) == 0
chk("_revocation_done consomme l'exception + gère l'annulation, set vidé", _run(_done()))

print("── worker : isolation billing / sweep ──")
async def _iso():
    calls = {"r": 0, "s": 0}
    async def r_boom(): calls["r"] += 1; raise RuntimeError("billing boom")
    async def s_ok(): calls["s"] += 1
    main.reconcile_once = r_boom; main.sweep_pending_revocations = s_ok
    await main._reconcile_cycle()
    a = (calls["r"] == 1 and calls["s"] == 1)
    calls2 = {"r": 0, "s": 0}
    async def r_ok(): calls2["r"] += 1
    async def s_boom(): calls2["s"] += 1; raise RuntimeError("sweep boom")
    main.reconcile_once = r_ok; main.sweep_pending_revocations = s_boom
    await main._reconcile_cycle()  # ne doit pas lever
    b = (calls2["r"] == 1 and calls2["s"] == 1)
    return a, b
a, b = _run(_iso())
chk("erreur billing → sweep tourne quand même", a)
chk("erreur sweep → ne remonte pas / n'empêche pas billing", b)

print("── claim → planifie la finalisation ──")
async def _claim():
    on(); os.environ["IDENTITY_MERGE_ENDPOINTS_ENABLED"] = "true"
    called = []
    orig = identity.finalize_revocation
    async def spy(mid): called.append(mid); return "completed"
    identity.finalize_revocation = spy
    class _R:
        def rpc(self, name, params):
            return SimpleNamespace(execute=lambda: SimpleNamespace(
                data=[{"status": "revocation_pending", "merge_id": "mClaim", "metadata": {}}]))
    identity._get_supa = lambda: _R()
    try:
        resp = await identity.claim_merge(body=ClaimBody(ticket="T" * 40), current_user=CurrentUser("B", False))
        await asyncio.sleep(0.05)
        return called, resp.status_code
    finally:
        identity.finalize_revocation = orig
called, code = _run(_claim())
chk("claim revocation_pending → schedule finalize(mClaim)", called == ["mClaim"])
chk("claim renvoie 200 (contrat 3a inchangé)", code == 200)

print("── garde merge_id + batch borné ──")
on()
before = len(identity._revocation_bg)
identity.schedule_revocation(None); identity.schedule_revocation("")
chk("schedule merge_id vide/None → aucune tâche", len(identity._revocation_bg) == before)
f = FakeSupa(dict(M0)); _use(f)
chk("finalize None → invalid_merge_id, aucune lecture DB",
    _run(identity.finalize_revocation(None)) == "invalid_merge_id" and f.select_filtersets == [] and not f.ban_calls)
f = FakeSupa(dict(M0)); _use(f)
chk("finalize '' → invalid_merge_id, aucune lecture DB",
    _run(identity.finalize_revocation("")) == "invalid_merge_id" and f.select_filtersets == [])
f = FakeSupa({**M0, "merge_id": None}); _use(f)
chk("sweep ignore ligne sans merge_id (aucun ban)", _run(identity.sweep_pending_revocations()) == 0 and not f.ban_calls)
chk("REVOCATION_BATCH_SIZE == 20", identity.REVOCATION_BATCH_SIZE == 20)
for lim, exp in ((5000, 20), (0, 1), (5, 5), (100, 20)):
    f = FakeSupa(None); _use(f)
    _run(identity.sweep_pending_revocations(limit=lim))
    chk(f"sweep limit={lim} → borné à {exp}", f.limit_calls == [exp], str(f.limit_calls))

print("── concurrence : deux finalisations simultanées ──")
async def _concurrency():
    f = FakeSupa(dict(M0))
    f.ban_barrier = threading.Barrier(2, timeout=5)   # interleaving réel des 2 tâches
    _use(f)
    results = await asyncio.gather(
        identity.finalize_revocation("m1"),
        identity.finalize_revocation("m1"),
        return_exceptions=True,
    )
    return f, results
fc, results = _run(_concurrency())
chk("concurrence : aucune exception levée", all(not isinstance(r, Exception) for r in results), str(results))
chk("concurrence : les deux → completed (le perdant lit completed, idempotent)", results == ["completed", "completed"], str(results))
chk("concurrence : UNE SEULE transition CAS appliquée", fc.update_applied == 1, f"applied={fc.update_applied}")
chk("concurrence : statut final completed", fc.merge["status"] == "completed")
chk("concurrence : double ban sans conséquence (2 appels)", len(fc.ban_calls) == 2)
chk("concurrence : aucun delete_user", fc.delete_calls == [])

print(f"\n{'ALL PASS' if _fail == 0 else str(_fail) + ' FAILURE(S)'}")
sys.exit(1 if _fail else 0)
