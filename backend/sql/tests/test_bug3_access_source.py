"""FIX B (2026-07-18) — preuve UNITAIRE (sans DB) du classifieur access_source.

SUPERSEDE BUG 3 : l'heuristique `ever_had_pass` classait « rôle premium + un pass a existé »
en 'pass' (0 spaces · renews) pour éviter un restore trompeur pendant un renouvellement. Mais
elle MASQUAIT le cas réel « le pass de l'abo est sur une AUTRE identité (RC-transféré, tx déjà
consommée) / webhook manqué » : l'app affichait un ancien produit comme actif et ne proposait
jamais de restore. FIX B : un rôle premium SANS pass actif possédé → 'restore_required'
explicite (un restore/sync déclenche le reconcile). On ne déduit JAMAIS 'pass' de l'historique.

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
                has_premium_role=False)
    results = [
        # admin/promo/free inchangés
        case("admin illimité", "admin", **{**base, "is_admin": True}),
        case("pass actif mesuré", "pass", **{**base, "has_active_pass": True}),
        case("promo actif", "promo", **{**base, "promo_active": True}),
        case("free (aucun droit)", "free", **base),

        # ── LE FIX B ── premium reconnu MAIS aucun pass actif possédé → restore_required
        #    (auparavant 'pass' via ever_had_pass ; désormais on propose TOUJOURS un restore).
        case("rôle premium + AUCUN pass actif possédé → restore_required",
             "restore_required", **{**base, "has_premium_role": True}),

        # priorités : admin > pass (mesuré) > promo > restore_required > free
        case("admin l'emporte sur tout", "admin",
             **{**base, "is_admin": True, "has_premium_role": True}),
        case("pass actif l'emporte sur le rôle premium", "pass",
             **{**base, "has_active_pass": True, "has_premium_role": True}),
        case("promo l'emporte sur restore_required", "promo",
             **{**base, "promo_active": True, "has_premium_role": True}),
    ]
    total, passed = len(results), sum(1 for r in results if r)
    print(f"\nFIX B classifier: {passed}/{total} PASS")
    sys.exit(0 if passed == total else 1)


if __name__ == "__main__":
    main()
