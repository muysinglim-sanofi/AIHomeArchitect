"""BUG 3 (2026-07-11) — preuve UNITAIRE (sans DB) du classifieur access_source.

Racine BUG 3 : la projection wallet met active_pass_id=NULL dès que la fenêtre du pass
lapse → un abonné dont le renouvellement n'a pas été projeté tombait en 'restore_required'
(→ « Restore purchase » trompeur + restore muet). Fix : un pass AYANT existé (ever_had_pass)
→ 'pass' (0 spaces · renews), JAMAIS restore. restore_required réservé au rôle SANS pass.

Run:  python backend/sql/tests/test_bug3_access_source.py
"""
import os
import sys

try:  # console Windows cp1252 → forcer UTF-8 pour les libellés accentués/flèches
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:  # noqa: BLE001
    pass

# Import _classify_access_source depuis main.py SANS booter FastAPI (charge le module
# comme source et extrait la fonction pure — pas d'effet de bord réseau/DB).
_HERE = os.path.dirname(os.path.abspath(__file__))
_MAIN = os.path.normpath(os.path.join(_HERE, "..", "..", "main.py"))


def _load_classifier():
    import ast
    src = open(_MAIN, encoding="utf-8").read()
    tree = ast.parse(src)
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name == "_classify_access_source":
            mod = ast.Module(body=[node], type_ignores=[])
            ns: dict = {}
            exec(compile(mod, _MAIN, "exec"), ns)  # noqa: S102 — fonction pure isolée
            return ns["_classify_access_source"]
    raise AssertionError("_classify_access_source introuvable dans main.py")


classify = _load_classifier()


def case(name, expected, **kw):
    got = classify(**kw)
    ok = got == expected
    print(f"  [{'PASS' if ok else 'FAIL'}] {name}: got={got!r} expected={expected!r}")
    return ok


def main():
    base = dict(is_admin=False, has_active_pass=False, promo_active=False,
                has_premium_role=False, ever_had_pass=False)
    results = [
        # admin/promo/free inchangés
        case("admin illimité", "admin", **{**base, "is_admin": True}),
        case("pass actif mesuré", "pass", **{**base, "has_active_pass": True}),
        case("promo actif", "promo", **{**base, "promo_active": True}),
        case("free (aucun droit)", "free", **base),

        # ── LE FIX BUG 3 ──
        case("rôle premium + un pass a EXISTÉ (fenêtre lapsée) → pass (0 spaces·renews)",
             "pass", **{**base, "has_premium_role": True, "ever_had_pass": True}),
        case("rôle premium + AUCUN pass jamais → restore_required",
             "restore_required", **{**base, "has_premium_role": True, "ever_had_pass": False}),

        # priorités : admin > pass > promo > pass-renewing > restore_required
        case("admin l'emporte sur tout", "admin",
             **{**base, "is_admin": True, "has_premium_role": True, "ever_had_pass": True}),
        case("pass actif l'emporte sur ever_had_pass", "pass",
             **{**base, "has_active_pass": True, "has_premium_role": True, "ever_had_pass": True}),
        case("promo l'emporte sur restore_required", "promo",
             **{**base, "promo_active": True, "has_premium_role": True, "ever_had_pass": False}),
    ]
    total, passed = len(results), sum(1 for r in results if r)
    print(f"\nBUG 3 classifier: {passed}/{total} PASS")
    sys.exit(0 if passed == total else 1)


if __name__ == "__main__":
    main()
