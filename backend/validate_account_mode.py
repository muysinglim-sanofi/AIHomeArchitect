"""ON-mode (2026-07-17) — validation OFFLINE du socle Account-mode backend.

Prouve, sans DB/réseau (FilterSupa + fakes), les contrats VÉRIFIABLES ici :
  • autorité de mode ACCOUNT_SYSTEM_ENABLED → TRIAL effectif 3 (OFF) / 1 (ON) ;
  • grant_signup_bonus : +2 une seule fois (idempotent), compte free=2 (pas de +3 fantôme) ;
  • mark_signup_eligible : eligible=false si déjà accordé ;
  • ticket signé HS256 (secret dédié) : roundtrip, falsification, mauvais secret, expiré, typ ;
  • claim_guest_and_bonus (wrapper Python) : passe p_trial_credits/p_signup_bonus au RPC et
    relaie son dict.

NON couvert ici (apply-au-deploy / device) : l'exécution réelle du RPC SQL claim_guest_and_bonus
et de billing_try_hold paramétré (Postgres) — validés à l'application de la migration + E2E,
comme les RPC P0. Lancer : python validate_account_mode.py
"""
import os, sys, asyncio, json, time, hmac, hashlib
sys.path.insert(0, os.path.dirname(__file__))
import billing  # noqa: E402
from _billing_fakes import FilterSupa  # noqa: E402

PASS = "\033[92mPASS\033[0m"; FAIL = "\033[91mFAIL\033[0m"; res = []
def check(l, c, d=""):
    res.append(bool(c)); print(f"  {PASS if c else FAIL}  {l}{('  ['+str(d)+']') if d and not c else ''}")
def run(c): return asyncio.run(c)

print("\n=== ON-mode · socle Account-mode ===")

# ── Autorité de mode + TRIAL effectif ────────────────────────────────────────
os.environ.pop("ACCOUNT_SYSTEM_ENABLED", None)
check("OFF: account_system_enabled=false", billing.account_system_enabled() is False)
check("OFF: effective_trial_credits=3", billing.effective_trial_credits() == 3)
check("OFF: guest frais free=3", run(billing._free_bucket_available(FilterSupa(), "u1")) == 3)

os.environ["ACCOUNT_SYSTEM_ENABLED"] = "true"
check("ON: account_system_enabled=true", billing.account_system_enabled() is True)
check("ON: effective_trial_credits=1", billing.effective_trial_credits() == 1)
check("ON: guest frais free=1", run(billing._free_bucket_available(FilterSupa(), "u2")) == 1)

# ── grant_signup_bonus : +2 une seule fois, sans +3 fantôme ───────────────────
fs = FilterSupa()
r1 = run(billing.grant_signup_bonus(user_id="acct", supa=fs))
r2 = run(billing.grant_signup_bonus(user_id="acct", supa=fs))
check("bonus +2 (1er)", r1.get("decision") == "granted" and r1.get("bonus_granted") == 2)
check("bonus idempotent (2e no-op)", r2.get("decision") == "already_processed" and r2.get("bonus_granted") == 0)
check("compte free=2 (bonus=TRIAL → pas de +3 fantôme)", run(billing._free_bucket_available(fs, "acct")) == 2)
elig = run(billing.mark_signup_eligible(user_id="acct", supa=fs))
check("mark_signup_eligible: déjà accordé → eligible=false", elig.get("eligible") is False)
elig2 = run(billing.mark_signup_eligible(user_id="brand-new", supa=FilterSupa()))
check("mark_signup_eligible: neuf → eligible=true", elig2.get("eligible") is True)

# ── Ticket signé HS256 (secret dédié) ────────────────────────────────────────
os.environ["CLAIM_TICKET_SECRET"] = "dedicated-secret-xyz"
import identity as I  # noqa: E402
tok, exp = I.issue_claim_ticket("guest-abc")
check("ticket roundtrip → guest-abc", I.verify_claim_ticket(tok) == "guest-abc")
body, sig = tok.split(".", 1)
check("ticket signature falsifiée → None", I.verify_claim_ticket(body + ".BAD") is None)
os.environ["CLAIM_TICKET_SECRET"] = "different"
check("ticket mauvais secret → None", I.verify_claim_ticket(tok) is None)
os.environ["CLAIM_TICKET_SECRET"] = "dedicated-secret-xyz"
def _forge(payload):
    b = I._b64u(json.dumps(payload, separators=(",", ":")).encode())
    s = I._b64u(hmac.new(b"dedicated-secret-xyz", b.encode(), hashlib.sha256).digest())
    return b + "." + s
check("ticket expiré → None",
      I.verify_claim_ticket(_forge({"typ": "guest_claim", "guest_id": "g", "exp": int(time.time()) - 5})) is None)
check("ticket mauvais typ → None",
      I.verify_claim_ticket(_forge({"typ": "auth", "guest_id": "g", "exp": int(time.time()) + 99})) is None)
os.environ.pop("CLAIM_TICKET_SECRET", None)
try:
    I.issue_claim_ticket("g"); check("secret manquant → RuntimeError", False)
except RuntimeError:
    check("secret manquant → RuntimeError", True)

# ── claim_guest_and_bonus (wrapper Python) : passe les params + relaie le dict RPC ──
class _RpcSpy:
    def __init__(self): self.calls = []
    def rpc(self, name, params):
        self.calls.append((name, params)); outer = self
        class _E:
            def execute(self_inner):
                class _R: data = [{"status": "claimed", "claimed": 1, "bonus": 2,
                                   "account_total": 3, "guest_after": 0}]
                return _R()
        return _E()
os.environ["ACCOUNT_SYSTEM_ENABLED"] = "true"
spy = _RpcSpy()
out = run(billing.claim_guest_and_bonus(account_id="A", guest_id="G", supa=spy))
name, params = spy.calls[0]
check("wrapper appelle RPC claim_guest_and_bonus", name == "claim_guest_and_bonus")
check("wrapper passe p_trial_credits=1 (ON) + p_signup_bonus=2 + ids",
      params.get("p_trial_credits") == 1 and params.get("p_signup_bonus") == 2
      and params.get("p_account_id") == "A" and params.get("p_guest_id") == "G", params)
check("wrapper relaie le dict RPC (claimed=1, total=3)",
      out.get("claimed") == 1 and out.get("account_total") == 3, out)
os.environ.pop("ACCOUNT_SYSTEM_ENABLED", None)

total = len(res); passed = sum(res)
print(f"\n{'='*64}\n  ACCOUNT-MODE — TOTAL {total}  PASSED {passed}  FAILED {total-passed}\n{'='*64}")
sys.exit(0 if passed == total else 1)
