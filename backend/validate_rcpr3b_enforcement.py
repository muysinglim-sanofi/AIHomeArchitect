"""RC-PR3b (2026-07-10) — enforcement du pass mesuré : le rôle premium n'est PLUS
l'autorité de génération illimitée.

Pur (FakeSupa, 0 DB/0 réseau). Vérifie la décision Python de `reserve_decision` :
  • tier=premium + pass actif, solde ≥ 1 → allow (gén. métrée)
  • tier=premium + pass actif, solde 0   → deny pass_exhausted (aucune gen à 0)
  • tier=premium SANS pass actif         → deny no_active_pass (jamais unlimited silencieux)
  • tier=admin / promo_unlimited / promo_limited → allow (bypass illimité/promo)
  • is_free=True (free) → chemin free INCHANGÉ (bucket free + TRIAL, RC-PR2b)

La séparation réelle bucket pass (pass_id) vs free (pass_id NULL) est portée par le
filtre .eq("pass_id") → E2E DB. Ici on teste la logique de décision.
"""
import os, sys, asyncio, logging
sys.path.insert(0, os.path.dirname(__file__))
logging.disable(logging.CRITICAL)

import billing

PASS = "\033[92mPASS\033[0m"; FAIL = "\033[91mFAIL\033[0m"
res = []
def check(label, cond, detail=""):
    res.append(bool(cond))
    print(f"  {PASS if cond else FAIL}  {label}{('  ['+str(detail)+']') if detail and not cond else ''}")


class _Res:
    def __init__(self, data): self.data = data


class _Query:
    def __init__(self, fake, table): self._f = fake; self._t = table
    def select(self, *a, **k): return self
    def eq(self, *a, **k): return self
    def lte(self, *a, **k): return self
    def gt(self, *a, **k): return self
    def order(self, *a, **k): return self
    def limit(self, *a, **k): return self
    def execute(self):
        if self._t == "passes":
            self._f.passes_queries += 1
            return _Res(self._f.pass_rows)
        if self._t == "ledger_entries":
            self._f.ledger_queries += 1
            return _Res(self._f.ledger_rows)
        return _Res([])


class FakeSupa:
    def __init__(self, pass_rows=None, ledger_rows=None):
        self.pass_rows = pass_rows or []
        self.ledger_rows = ledger_rows or []
        self.passes_queries = 0
        self.ledger_queries = 0
    def table(self, name): return _Query(self, name)


def run(coro): return asyncio.run(coro)

def decide(fs, *, is_free, tier):
    return run(billing.reserve_decision(
        user_id="u1", is_free=is_free, tier=tier, supa=fs))


print("\n=== RC-PR3b · reserve_decision (enforcement pass mesuré) ===")

# 1. premium + pass actif, solde ≥ 1 → allow (métré)
fs = FakeSupa(pass_rows=[{"id": "pass-A"}], ledger_rows=[{"available_delta": 30},
                                                         {"available_delta": -1}])
d = decide(fs, is_free=False, tier="premium")
check("1 premium + pass actif solde=29 → allow (wallet_available=29)",
      d.allow and d.reason == "" and d.wallet_available == 29, (d,))

# 2. premium + pass actif, solde 0 → deny pass_exhausted (aucune gen à 0)
fs = FakeSupa(pass_rows=[{"id": "pass-A"}], ledger_rows=[{"available_delta": 30},
                                                         {"available_delta": -30}])
d = decide(fs, is_free=False, tier="premium")
check("2 premium + pass actif solde=0 → DENY pass_exhausted",
      (not d.allow) and d.reason == "pass_exhausted" and d.wallet_available == 0, (d,))

# 2b. solde négatif (désync historique) → toujours deny (jamais illimité)
fs = FakeSupa(pass_rows=[{"id": "pass-A"}], ledger_rows=[{"available_delta": -2}])
d = decide(fs, is_free=False, tier="premium")
check("2b premium + pass solde<0 → DENY pass_exhausted", (not d.allow) and d.reason == "pass_exhausted")

# 3. premium SANS pass actif → deny no_active_pass (incohérent, jamais unlimited silencieux)
fs = FakeSupa(pass_rows=[])
d = decide(fs, is_free=False, tier="premium")
check("3 premium SANS pass → DENY no_active_pass (jamais unlimited silencieux)",
      (not d.allow) and d.reason == "no_active_pass", (d,))

# 4. admin → allow bypass (illimité réel), aucune lecture pass/ledger
fs = FakeSupa(pass_rows=[{"id": "pass-A"}], ledger_rows=[{"available_delta": 0}])
d = decide(fs, is_free=False, tier="admin")
check("4 admin → allow bypass, aucun lookup pass/ledger",
      d.allow and d.reason == "bypass" and fs.passes_queries == 0 and fs.ledger_queries == 0, (d,))

# 5. promo_unlimited → allow bypass
fs = FakeSupa()
d = decide(fs, is_free=False, tier="promo_unlimited")
check("5 promo_unlimited → allow bypass", d.allow and d.reason == "bypass" and fs.passes_queries == 0)

# 6. promo_limited → allow bypass (borné par le resolver, pas par le pass)
fs = FakeSupa()
d = decide(fs, is_free=False, tier="promo_limited")
check("6 promo_limited → allow bypass", d.allow and d.reason == "bypass" and fs.passes_queries == 0)

# 7. free avec crédits → allow (chemin free RC-PR2b inchangé)
fs = FakeSupa(ledger_rows=[{"entry_type": "TRIAL", "available_delta": 3},
                           {"entry_type": "HOLD", "available_delta": -1}])
d = decide(fs, is_free=True, tier="free")
check("7 free available=2 (trial accordé) → allow", d.allow and d.effective == 2, (d,))

# 8. free épuisé (trial accordé, tout consommé) → deny insufficient_credits
fs = FakeSupa(ledger_rows=[{"entry_type": "TRIAL", "available_delta": 3},
                           {"entry_type": "HOLD", "available_delta": -3}])
d = decide(fs, is_free=True, tier="free")
check("8 free available=0 trial accordé → DENY insufficient_credits",
      (not d.allow) and d.reason == "insufficient_credits", (d,))

# 9. free neuf (pas encore de TRIAL) → +3 pending → allow
fs = FakeSupa(ledger_rows=[])
d = decide(fs, is_free=True, tier="free")
check("9 free neuf (trial pending +3) → allow effective=3", d.allow and d.effective == 3, (d,))

# 10. free ne fait PAS de lookup pass (chemin free ne lit pas passes)
fs = FakeSupa(pass_rows=[{"id": "pass-A"}], ledger_rows=[])
d = decide(fs, is_free=True, tier="free")
check("10 free → aucun lookup passes", fs.passes_queries == 0, fs.passes_queries)

# 11. fail-open lecture pass bucket → allow (fiabilité > double rare)
class _BoomLedger(FakeSupa):
    def table(self, name):
        if name == "ledger_entries":
            class _Boom:
                def select(self,*a,**k): return self
                def eq(self,*a,**k): return self
                def execute(self): raise RuntimeError("db down")
            return _Boom()
        return super().table(name)
fs = _BoomLedger(pass_rows=[{"id": "pass-A"}])
d = decide(fs, is_free=False, tier="premium")
check("11 premium + pass, lecture bucket KO → FAIL-OPEN allow", d.allow, (d,))

total = len(res); passed = sum(res)
print(f"\n{'='*64}\n  TOTAL {total}  PASSED {passed}  FAILED {total-passed}\n{'='*64}")
sys.exit(0 if passed == total else 1)
