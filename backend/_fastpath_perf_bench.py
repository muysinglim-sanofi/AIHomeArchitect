"""
CORRECTIF PERF FAST-PATH — BENCHMARK CONTRÔLÉ À LATENCE INJECTÉE.

But : prouver EMPIRIQUEMENT, en isolant la seule variable "garde identité", que le
correctif n'ajoute AUCUN RTT séquentiel vs l'état AVANT Unified Identity — là où le
Commit 3a en ajoutait un.

Méthode : un FakeSupa injecte une latence FIXE par appel (LAT_MS) dans un
time.sleep SYNCHRONE. Comme resolve_generation_access lance ses lectures via
asyncio.to_thread + asyncio.gather, les N lectures parallèles se recouvrent (≈ 1 RTT
mur) tandis qu'une lecture SÉQUENTIELLE (await avant le gather) ajoute 1 RTT plein.
Ceci modélise fidèlement la parallélisation réseau réelle, SANS toucher au Sandbox,
SANS JWT, SANS OpenAI — on mesure UNIQUEMENT le segment identité+resolver, seul
segment que le correctif modifie (ownership/reserve/claim/hold sont identiques).

Trois configurations du segment identité+resolver :
  A · AVANT Unified Identity : resolver 3-way (roles/promo/usage), aucune lecture identité
  B · COMMIT 3a (avant correctif) : 1 lecture account_state SÉQUENTIELLE (dépendance)
      PUIS resolver 3-way
  C · CANDIDAT (correctif) : resolver 4-way (identité FOLDÉE), aucune lecture séquentielle

Attendu : médiane(A) ≈ médiane(C) ≈ 1×LAT ; médiane(B) ≈ 2×LAT.
→ delta(candidat − avant-UI) ≈ 0 ; delta(3a − avant-UI) ≈ +1 RTT.

Exécution :  python _fastpath_perf_bench.py
"""
from __future__ import annotations

import asyncio
import os
import statistics
import sys
import time

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test-key")
os.environ.setdefault("OPENAI_API_KEY", "test-openai")
os.environ.setdefault("REVENUECAT_WEBHOOK_AUTH", "test-secret")

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import identity  # noqa: E402
import promo  # noqa: E402
import quota  # noqa: E402

LAT_MS = 40.0          # latence RTT simulée par appel Supabase
ITERS = 40             # itérations par configuration (caches chauds)
WARMUP = 5


class _Res:
    def __init__(self, data=None, count=None):
        self.data = data
        self.count = count


class _Q:
    def __init__(self, table):
        self._t = table

    def select(self, *a, **k):
        return self

    def eq(self, *a, **k):
        return self

    def neq(self, *a, **k):
        return self

    def limit(self, *a, **k):
        return self

    def execute(self):
        time.sleep(LAT_MS / 1000.0)  # 1 RTT simulé (dans le thread de to_thread)
        if self._t == "usage_log":
            return _Res(data=[], count=0)
        return _Res(data=[])


class _RpcQ:
    def execute(self):
        time.sleep(LAT_MS / 1000.0)
        return _Res(data={})


class LatSupa:
    """Chaque .execute() dort LAT_MS. Les lectures parallèles (gather+to_thread) se
    recouvrent ; une lecture séquentielle ajoute 1×LAT."""
    def table(self, name):
        return _Q(name)

    def rpc(self, name, params=None):
        return _RpcQ()


async def seg_before_ui(supa, uid):
    # A — aucune garde identité ; resolver 3-way (include_identity=False)
    await promo.resolve_generation_access(uid, supa=supa, include_identity=False)


async def seg_commit3a(supa, uid):
    # B — lecture account_state SÉQUENTIELLE (modélise la dépendance require_active_identity)
    #     PUIS resolver 3-way. C'est l'état actuel avant le correctif.
    await identity.fetch_identity_active(uid, supa=supa)          # +1 RTT séquentiel
    await promo.resolve_generation_access(uid, supa=supa, include_identity=False)


async def seg_candidate(supa, uid):
    # C — correctif : resolver 4-way (identité FOLDÉE dans le gather), 0 lecture séquentielle
    await promo.resolve_generation_access(uid, supa=supa, include_identity=True)


async def _bench(fn, label):
    supa = LatSupa()
    # warmup (chauffe la threadpool, le cache rôles, les imports)
    for i in range(WARMUP):
        quota._clear_role_cache()
        await fn(supa, f"warm{i}")
    samples = []
    for i in range(ITERS):
        quota._clear_role_cache()          # RTT réels à chaque itération (pas de cache rôle)
        uid = f"{label}{i}"
        t0 = time.monotonic()
        await fn(supa, uid)
        samples.append((time.monotonic() - t0) * 1000.0)
    samples.sort()
    med = statistics.median(samples)
    p95 = samples[min(len(samples) - 1, int(round(0.95 * (len(samples) - 1))))]
    return med, p95, samples


async def main():
    print("=" * 66)
    print(f"BENCHMARK CONTRÔLÉ — LAT_MS={LAT_MS:.0f}  ITERS={ITERS}  (segment identité+resolver)")
    print("=" * 66)
    a_med, a_p95, _ = await _bench(seg_before_ui, "A")
    b_med, b_p95, _ = await _bench(seg_commit3a, "B")
    c_med, c_p95, _ = await _bench(seg_candidate, "C")

    print(f"A · AVANT Unified Identity  median={a_med:6.1f}ms  p95={a_p95:6.1f}ms")
    print(f"B · COMMIT 3a (séquentiel)  median={b_med:6.1f}ms  p95={b_p95:6.1f}ms")
    print(f"C · CANDIDAT (foldé)        median={c_med:6.1f}ms  p95={c_p95:6.1f}ms")
    print("-" * 66)
    print(f"Δ 3a vs avant-UI  : median {b_med - a_med:+6.1f}ms  (~{(b_med - a_med)/LAT_MS:+.2f} RTT)")
    print(f"Δ candidat vs avant-UI : median {c_med - a_med:+6.1f}ms  (~{(c_med - a_med)/LAT_MS:+.2f} RTT)")
    print("-" * 66)

    # Critères de succès (marges généreuses pour le bruit de la threadpool) :
    #   • 3a ajoute ~1 RTT (b ≥ a + 0.6×LAT)
    #   • candidat n'ajoute PAS de RTT (c ≤ a + 0.5×LAT, càd < un demi-RTT de bruit)
    ok_3a_adds = b_med >= a_med + 0.6 * LAT_MS
    ok_cand_zero = c_med <= a_med + 0.5 * LAT_MS
    print(f"[{'PASS' if ok_3a_adds else 'FAIL'}] 3a ajoute ~1 RTT séquentiel (attendu)")
    print(f"[{'PASS' if ok_cand_zero else 'FAIL'}] candidat n'ajoute AUCUN RTT séquentiel vs avant-UI")
    if not (ok_3a_adds and ok_cand_zero):
        sys.exit(1)
    print("\nCONCLUSION : le correctif ramène le coût identité de +1 RTT (3a) à ~0 RTT.")


if __name__ == "__main__":
    asyncio.run(main())
