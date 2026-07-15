"""
_freetrial_validation.py — validateur OFFLINE de FT1 (Free Trial 1+2).

Aucune dependance runtime : lit les fichiers source (Python + migrations SQL) et
verifie STATIQUEMENT les invariants FT1. Ne se connecte a AUCUNE base, n'importe
AUCUN module d'app (pas de secrets requis).

    python backend/_freetrial_validation.py   -> exit 0 si tout PASS, 1 sinon.

Couvre : centralisation des constantes (Python <-> SQL), cablage des 2 endpoints
dormants, RPC bonus (idempotence/securite/anonymat serveur), flip trial 3->1,
non-propagation du merge, validite des enums ledger, cloisonnement des namespaces
d'idempotence. Sortie ASCII (robuste console Windows cp1252).
"""

from __future__ import annotations

import os
import re
import sys

BASE = os.path.dirname(os.path.abspath(__file__))
MIG = os.path.join(BASE, "..", "supabase", "migrations")

_results: list[tuple[str, bool, str]] = []


def _read(path: str) -> str:
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def check(name: str, cond: bool, detail: str = "") -> None:
    _results.append((name, bool(cond), detail))


# ── Sources ──────────────────────────────────────────────────────────────────
cfg = _read(os.path.join(BASE, "free_tier_config.py"))
billing = _read(os.path.join(BASE, "billing.py"))
quota = _read(os.path.join(BASE, "quota.py"))
identity = _read(os.path.join(BASE, "identity.py"))
mig_a = _read(os.path.join(MIG, "20260717_ft1a_freetrial_signup_bonus.sql"))
mig_b = _read(os.path.join(MIG, "20260718_ft1b_anon_trial_to_one.sql"))
merge = _read(os.path.join(MIG, "20260714_identity_claim_and_merge_rpc.sql"))
schema = _read(os.path.join(MIG, "20260701_billing_engine_pr0_schema.sql"))

# ── 1) free_tier_config.py : la source unique Python ────────────────────────
check("cfg.ANON=1", re.search(r"ANONYMOUS_FREE_GENERATIONS\s*=\s*1\b", cfg) is not None)
check("cfg.BONUS=2", re.search(r"ACCOUNT_CREATION_FREE_BONUS\s*=\s*2\b", cfg) is not None)
check("cfg.TOTAL=anon+bonus",
      re.search(r"TOTAL_FREE_GENERATIONS\s*=\s*ANONYMOUS_FREE_GENERATIONS\s*\+\s*ACCOUNT_CREATION_FREE_BONUS", cfg) is not None)

# ── 2) billing.py : TRIAL_CREDITS centralise + wrappers RPC ─────────────────
check("billing imports ANON", "from free_tier_config import ANONYMOUS_FREE_GENERATIONS" in billing)
check("billing.TRIAL_CREDITS=ANON", "TRIAL_CREDITS = ANONYMOUS_FREE_GENERATIONS" in billing)
check("billing no literal TRIAL_CREDITS=3", re.search(r"TRIAL_CREDITS\s*=\s*3\b", billing) is None)
check("billing.mark_signup_eligible def", "async def mark_signup_eligible(" in billing)
check("billing.grant_signup_bonus def", "async def grant_signup_bonus(" in billing)
check("billing calls rpc mark", 'rpc("billing_mark_signup_eligible"' in billing)
check("billing calls rpc grant", 'rpc("billing_grant_signup_bonus"' in billing)

# ── 3) quota.py : FREE_TIER_LIMIT centralise ────────────────────────────────
check("quota imports TOTAL", "from free_tier_config import TOTAL_FREE_GENERATIONS" in quota)
check("quota.FREE_TIER_LIMIT=TOTAL", "FREE_TIER_LIMIT = TOTAL_FREE_GENERATIONS" in quota)
check("quota no literal FREE_TIER_LIMIT=3", re.search(r"FREE_TIER_LIMIT\s*=\s*3\b", quota) is None)

# ── 4) identity.py : 2 endpoints dormants, gate flag, user_id=JWT ───────────
check("identity flag FREE_TRIAL_SIGNUP_BONUS_ENABLED", "FREE_TRIAL_SIGNUP_BONUS_ENABLED" in identity)
check("identity route /anon-init", '@identity_router.post("/anon-init")' in identity)
check("identity route /claim-signup-bonus", '@identity_router.post("/claim-signup-bonus")' in identity)
check("identity gate uses require_active_identity",
      re.search(r"def signup_bonus_gate\(.*?require_active_identity", identity, re.S) is not None)
check("identity anon-init user_id from JWT",
      "billing.mark_signup_eligible(user_id=current_user.user_id)" in identity)
check("identity claim user_id from JWT",
      "billing.grant_signup_bonus(user_id=current_user.user_id)" in identity)
# aucun corps de requete sur les 2 endpoints (user_id ne peut venir que du JWT)
_ep = re.findall(r"async def (?:anon_init|claim_signup_bonus)\((.*?)\):", identity, re.S)
check("identity endpoints have NO request body",
      len(_ep) == 2 and all(("body" not in s.lower() and "Body(" not in s) for s in _ep),
      detail=f"signatures={_ep}")

# ── 5) Migration A : config + colonnes + 2 RPC securisees ───────────────────
check("migA billing_free_config 1,2,3", re.search(r"select\s+1,\s*2,\s*3", mig_a) is not None)
check("migA alter add signup_bonus_eligible", "add column if not exists signup_bonus_eligible" in mig_a)
check("migA alter add signup_bonus_granted_at", "add column if not exists signup_bonus_granted_at" in mig_a)
check("migA def mark", "function public.billing_mark_signup_eligible(p_user_id uuid)" in mig_a)
check("migA def grant", "function public.billing_grant_signup_bonus(p_user_id uuid)" in mig_a)
check("migA security definer x2", mig_a.count("security definer") >= 2)
check("migA search_path='' x2", mig_a.count("set search_path = ''") >= 2)
check("migA reads auth.users.is_anonymous",
      "auth.users" in mig_a and "is_anonymous" in mig_a)
check("migA grant entry_type GRANT/signup (bonus_due amount)",
      re.search(r"'GRANT',\s*v_bonus_due,\s*null,\s*'PROMO',\s*'signup'", mig_a) is not None)
check("migA ensures TRIAL trial key",
      re.search(r"'TRIAL',\s*v_anon_free,\s*null,\s*'PROMO',\s*'trial',\s*v_trial_key", mig_a) is not None)
check("migA signup idempotency key", "'signup:'" in mig_a)
check("migA NO advisory lock in FT1a (interdit)", "pg_advisory_xact_lock" not in mig_a)
check("migA granted_at guard", "v_granted_at is not null" in mig_a)
check("migA merged_closed guard", "'merged_closed'" in mig_a)
check("migA revoke from public/anon/authenticated", mig_a.count("from public, anon, authenticated") >= 3)
check("migA grant to service_role", mig_a.count("to service_role") >= 3)
check("migA reprojects wallet", "perform public.billing_reproject_wallet(p_user_id)" in mig_a)

# ── 6) Migration B : flip trial 3->1 via config, rien d'autre change ─────────
check("migB replaces billing_try_hold", "create or replace function public.billing_try_hold" in mig_b)
check("migB trial uses v_anon_free", "'TRIAL', v_anon_free, null, 'PROMO', 'trial', v_trial_key" in mig_b)
check("migB reads billing_free_config", "select anon_free into v_anon_free from public.billing_free_config()" in mig_b)
check("migB no literal 'TRIAL', 3", re.search(r"'TRIAL',\s*3\b", mig_b) is None)
check("migB keeps wallet reproject", "perform public.billing_reproject_wallet(p_user_id)" in mig_b)
check("migB keeps HOLD -1", "'HOLD', -1, v_target_pass" in mig_b)

# ── 7) Merge RPC (existant) ne propage PAS signup_bonus_* ────────────────────
check("merge RPC never touches signup_bonus", "signup_bonus" not in merge)

# ── 8) Enums ledger : GRANT/TRIAL et PROMO valides ──────────────────────────
_entry_block = re.search(r"entry_type[^)]*check\s*\(entry_type in([^)]*)\)", schema, re.S)
_ref_block = re.search(r"reference_type\s+text\s+check\s*\(reference_type in([^)]*)\)", schema, re.S)
check("ledger entry_type allows GRANT", _entry_block is not None and "'GRANT'" in _entry_block.group(1))
check("ledger entry_type allows TRIAL", _entry_block is not None and "'TRIAL'" in _entry_block.group(1))
check("ledger reference_type allows PROMO", _ref_block is not None and "'PROMO'" in _ref_block.group(1))

# ── 9) Namespaces d'idempotence cloisonnes ──────────────────────────────────
check("grant does not reuse hold namespace", "'hold:'" not in mig_a)
check("signup key distinct from trial key",
      "'signup:'" in mig_a and "'trial:'" in mig_a)

# ── 10) TRIAL_CREDITS gate sur le flag FT2 (couplage display<->enforcement) ──
check("cfg.PRE_FT2=3", re.search(r"PRE_FT2_ANON_FREE_GENERATIONS\s*=\s*3\b", cfg) is not None)
check("billing imports PRE_FT2", "PRE_FT2_ANON_FREE_GENERATIONS" in billing)
check("billing _free_trial_active reads flag",
      "FREE_TRIAL_SIGNUP_BONUS_ENABLED" in billing and "def _free_trial_active" in billing)
check("billing TRIAL_CREDITS gated on flag",
      "if _free_trial_active() else PRE_FT2_ANON_FREE_GENERATIONS" in billing)

# ── 11) Conventions migrations (pas de begin/commit) + gardes ───────────────
check("migA no explicit begin/commit",
      re.search(r"(?m)^\s*begin;", mig_a) is None and re.search(r"(?m)^\s*commit;", mig_a) is None)
check("migB no explicit begin/commit",
      re.search(r"(?m)^\s*begin;", mig_b) is None and re.search(r"(?m)^\s*commit;", mig_b) is None)
check("migA mark upsert conditional (no re-arm after grant)",
      "where public.account_state.signup_bonus_granted_at is null" in mig_a)
check("migB apply-order guard on billing_free_config",
      "to_regprocedure('public.billing_free_config()')" in mig_b)

# ── 12) Claim atomique sans verrou + bonus plafonné (anti sur-crédit legacy) ─
check("migA atomic claim CAS (update ... returning, no advisory)",
      re.search(r"update public\.account_state.*?set signup_bonus_eligible\s*=\s*false.*?"
                r"where user_id\s*=\s*p_user_id.*?and signup_bonus_eligible\s*=\s*true.*?"
                r"and signup_bonus_granted_at is null.*?and merged_closed\s*=\s*false.*?"
                r"returning user_id into v_claimed", mig_a, re.S) is not None)
check("migA bonus_due capped by total_free",
      "greatest(0, least(v_signup, v_total - v_trial_ent - v_signup_ent))" in mig_a)
check("migA already_entitled decision (legacy +3 → 0)", "'already_entitled'" in mig_a)
check("migA zero GRANT guarded (if v_bonus_due > 0)", "if v_bonus_due > 0 then" in mig_a)
check("migA reads trial/signup entitlements (not HOLD)",
      "idempotency_key = v_trial_key" in mig_a and "idempotency_key = v_signup_key" in mig_a)
check("migA mark returns already_eligible", "'already_eligible'" in mig_a)
# migB (billing_try_hold) CONSERVE son verrou HISTORIQUE — non touché par FT1
check("migB keeps historical advisory lock", "pg_advisory_xact_lock(hashtext(p_user_id::text))" in mig_b)

# ── 13) Harnais de test : FT1a autonome, flip FT1b entierement reversible ────
test_a = _read(os.path.join(MIG, "_TEST_ft1_freetrial.sql"))
test_b = _read(os.path.join(MIG, "_TEST_ft1b_flip_rollback.sql"))

check("test FT1a: no billing_try_hold call", "public.billing_try_hold(" not in test_a)
check("test FT1a: no Tth", "Tth" not in test_a)
check("test FT1a: no ft1b prerequisite (20260718)", "20260718" not in test_a)
check("test FT1a: T13 targets EXACT pg_advisory_xact_lock",
      "position('pg_advisory_xact_lock'" in test_a)
check("test FT1a: final rollback (cleans only fixtures)",
      re.search(r"(?m)^\s*rollback;", test_a) is not None)

check("test flip: savepoint sp_flip", "savepoint sp_flip" in test_b)
check("test flip: rollback to savepoint (annule le flip)", "rollback to savepoint sp_flip" in test_b)
check("test flip: baseline pg_get_functiondef AVANT le savepoint",
      "pg_get_functiondef" in test_b
      and test_b.index("_ft1b_baseline") < test_b.index("savepoint sp_flip"))
check("test flip: comparaison md5 avant/apres", "md5(v_now) <> md5(v_base)" in test_b)
check("test flip: applique FT1b create-or-replace TEMPORAIREMENT",
      "create or replace function public.billing_try_hold" in test_b)
check("test flip: asserte TRIAL/HOLD/wallet",
      "entry_type='TRIAL'" in test_b and "entry_type='HOLD'" in test_b and "available_credits" in test_b)
check("test flip: verrou historique compte=1 asserte", "'pg_advisory_xact_lock', 'g'" in test_b)
check("test flip: ne COMMIT jamais (rollback final)",
      re.search(r"(?m)^\s*commit;", test_b) is None and re.search(r"(?m)^\s*rollback;", test_b) is not None)

# ── 14) Le test de flip embarque EXACTEMENT la definition FT1b de billing_try_hold
#    Extrait le bloc `create or replace function public.billing_try_hold(` … `$$;`
#    dans les DEUX fichiers, normalise (CRLF→LF, trailing-ws, lignes vides finales)
#    et compare OCTET PAR OCTET. Garantit que le test reversible valide EXACTEMENT
#    le code qui sera applique, pas une copie divergente.
def _extract_try_hold(sql: str) -> str:
    marker = "create or replace function public.billing_try_hold("
    i = sql.index(marker)                      # ValueError si absent
    j = sql.index("$$;", i) + len("$$;")       # 1er $$; apres le create = fin de fonction
    return sql[i:j]

def _norm_sql(block: str) -> str:
    block = block.replace("\r\n", "\n").replace("\r", "\n")   # CRLF -> LF
    block = "\n".join(line.rstrip() for line in block.split("\n"))  # trailing ws
    return block.rstrip("\n")                                  # lignes vides finales

try:
    _blk_mig = _norm_sql(_extract_try_hold(mig_b))
    _blk_test = _norm_sql(_extract_try_hold(test_b))
    check("test flip embeds exact FT1b billing_try_hold definition",
          _blk_mig == _blk_test, detail=f"mig={len(_blk_mig)}B test={len(_blk_test)}B")
except ValueError:
    check("test flip embeds exact FT1b billing_try_hold definition", False,
          detail="bloc billing_try_hold introuvable dans un des fichiers")

# ── 15) Garde anti-regression syntaxe : 'is distinct from' toujours espace ──
check("tests: 'is distinct from' correctly spaced (pas de 'fromN')",
      re.search(r"is distinct from[\d-]", test_a) is None
      and re.search(r"is distinct from[\d-]", test_b) is None)

# ── Rapport ──────────────────────────────────────────────────────────────────
fails = [r for r in _results if not r[1]]
print("=" * 64)
for name, ok, detail in _results:
    line = f"[{'PASS' if ok else 'FAIL'}] {name}"
    if detail and not ok:
        line += f"  ({detail})"
    print(line)
print("=" * 64)
print(f"FT1 offline validation: {len(_results) - len(fails)}/{len(_results)} PASS")
if fails:
    print("FAILURES: " + ", ".join(r[0] for r in fails))
    sys.exit(1)
print("ALL PASS")
sys.exit(0)
