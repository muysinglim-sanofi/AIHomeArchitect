"""Premium Center Lot 1 — preuve UNITAIRE (sans DB) du mapping sku → plan_type.

INFORMATIF seulement : plan_type ne participe NI au gate NI au débit NI à la projection.
Run:  python backend/sql/tests/test_plan_type.py
"""
import ast
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:  # noqa: BLE001
    pass

_HERE = os.path.dirname(os.path.abspath(__file__))
_MAIN = os.path.normpath(os.path.join(_HERE, "..", "..", "main.py"))


def _load(fn_name):
    tree = ast.parse(open(_MAIN, encoding="utf-8").read())
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name == fn_name:
            ns: dict = {}
            exec(compile(ast.Module(body=[node], type_ignores=[]), _MAIN, "exec"), ns)  # noqa: S102
            return ns[fn_name]
    raise AssertionError(f"{fn_name} introuvable dans main.py")


plan = _load("_sku_to_plan_type")


def case(name, expected, sku):
    got = plan(sku)
    ok = got == expected
    print(f"  [{'PASS' if ok else 'FAIL'}] {name}: got={got!r} expected={expected!r}")
    return ok


def main():
    results = [
        case("weekly_pass → weekly", "weekly", "weekly_pass"),
        case("annual_pass → annual", "annual", "annual_pass"),
        case("pack_10 → none (pas un abonnement)", "none", "pack_10"),
        case("sku inconnu → none", "none", "whatever"),
        case("None → none (pas de crash)", "none", None),
        case("vide → none", "none", ""),
    ]
    total, passed = len(results), sum(1 for r in results if r)
    print(f"\nplan_type mapping: {passed}/{total} PASS")
    sys.exit(0 if passed == total else 1)


if __name__ == "__main__":
    main()
