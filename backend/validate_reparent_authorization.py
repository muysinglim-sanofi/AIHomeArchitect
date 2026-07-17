"""PATCH 3 REDESIGN (2026-07-17) — AUTORISATION du re-parent : tests OBLIGATOIRES.

Prouve que la simple présence d'un entitlement RC actif NE SUFFIT PAS : le re-parent exige
(1) un transfert RC explicitement PROUVÉ côté serveur ET (2) une parenté Guest→Guest, avec
séparation explicite OFF/ON (tout transfert impliquant un Account est interdit en ON). Pur
(0 DB / 0 réseau) : teste billing.reparent_authorized.
"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
import billing

PASS = "\033[92mPASS\033[0m"; FAIL = "\033[91mFAIL\033[0m"
res = []
def check(label, cond, detail=""):
    res.append(bool(cond))
    print(f"  {PASS if cond else FAIL}  {label}{('  ['+str(detail)+']') if detail and not cond else ''}")

def auth(*, mode, frm, to, transfer):
    return billing.reparent_authorized(account_mode=mode, from_is_anon=frm,
                                       to_is_anon=to, has_authorized_rc_transfer=transfer)

GUEST, ACCOUNT = True, False

print("\n=== PATCH 3 redesign · autorisation re-parent (cas obligatoires) ===")

# 1. Guest A → Guest B (reinstall) — OFF : AUTORISÉ (transfert RC prouvé)
ok, why = auth(mode=False, frm=GUEST, to=GUEST, transfer=True)
check("1 OFF Guest→Guest (reinstall) + transfert RC prouvé → AUTORISÉ",
      ok and why == "off_guest_to_guest", why)

# 1b. Guest A → Guest B — ON : AUTORISÉ aussi (un Guest reste un Guest)
ok, why = auth(mode=True, frm=GUEST, to=GUEST, transfer=True)
check("1b ON Guest→Guest + transfert RC prouvé → AUTORISÉ", ok and why == "on_guest_to_guest", why)

# 2. Guest Premium → Account (login) — ON : INTERDIT
ok, why = auth(mode=True, frm=GUEST, to=ACCOUNT, transfer=True)
check("2 ON Guest Premium → Account (login) → INTERDIT (jamais Premium Guest→Account)",
      not ok and why == "on_guest_to_account", why)

# 3. Account Premium → Guest (sign-out) — ON : INTERDIT
ok, why = auth(mode=True, frm=ACCOUNT, to=GUEST, transfer=True)
check("3 ON Account Premium → Guest (sign-out) → INTERDIT (jamais pass Account→Guest)",
      not ok and why == "on_account_to_guest", why)

# 4. Account A → Account B — ON : INTERDIT (merge implicite)
ok, why = auth(mode=True, frm=ACCOUNT, to=ACCOUNT, transfer=True)
check("4 ON Account→Account → INTERDIT (aucun merge implicite)",
      not ok and why == "on_account_to_account", why)

# 5. Restore répété → décision STABLE ; no-double-grant garanti par le RPC billing_reparent_pass
#    (DÉPLACE via UPDATE, ne crédite jamais, idempotent no-op au 2e passage).
d1 = auth(mode=False, frm=GUEST, to=GUEST, transfer=True)
d2 = auth(mode=False, frm=GUEST, to=GUEST, transfer=True)
check("5 Restore répété → décision stable + no-double-grant (RPC déplace, idempotent)",
      d1 == d2 and d1[0] is True)

# 6. Transaction RC différente → aucun transfert enregistré → transfer=False → REFUS
ok, why = auth(mode=False, frm=GUEST, to=GUEST, transfer=False)
check("6 Transaction RC différente (aucun transfert prouvé) → REFUS",
      not ok and why == "no_authorized_rc_transfer", why)

# 7. Entitlement actif mais AUCUNE relation serveur autorisée → REFUS
ok, why = auth(mode=True, frm=GUEST, to=GUEST, transfer=False)
check("7 Entitlement actif SANS transfert RC prouvé → REFUS (entitlement seul ≠ autorisation)",
      not ok and why == "no_authorized_rc_transfer", why)

# 8. fail-closed : identité de type inconnu (None) → REFUS
ok, why = auth(mode=True, frm=None, to=GUEST, transfer=True)
check("8 identité inconnue (None) → REFUS (fail-closed)", not ok and why == "identity_kind_unknown", why)

# 9. OFF défensif : un Account en OFF (ne devrait jamais arriver) → REFUS
ok, why = auth(mode=False, frm=GUEST, to=ACCOUNT, transfer=True)
check("9 OFF + Account inattendu → REFUS (défensif)", not ok and why == "off_unexpected_account", why)

total = len(res); passed = sum(res)
print(f"\n{'='*64}\n  REPARENT-AUTH — TOTAL {total}  PASSED {passed}  FAILED {total-passed}\n{'='*64}")
sys.exit(0 if passed == total else 1)
