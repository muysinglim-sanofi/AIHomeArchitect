"""Compare le schéma d'une base CIBLE à celui de la PRODUCTION — lecture seule des deux côtés.

POURQUOI CET OUTIL. Deux fois de suite, un schéma reconstitué « à partir du code »
puis « à partir des migrations du dépôt » s'est révélé faux :
  • account_state inféré du code    = 2 colonnes ;
  • account_state de la migration   = 5 colonnes ;
  • account_state RÉELLEMENT en prod = 7 colonnes.
La seule autorité est la base vivante. Cet outil interroge les deux catalogues et
refuse de conclure sur autre chose que ce qu'il a lu.

SÛRETÉ. Les deux connexions sont ouvertes en lecture seule (`read_only = True`),
et la PRODUCTION est en outre reconnue par sa ref : si l'URL cible porte la ref de
production, l'outil REFUSE de tourner — on ne compare jamais la prod à elle-même
par accident, et on n'écrit jamais.

AUCUN SECRET N'EST IMPRIMÉ : ni URL, ni mot de passe, ni clé. Seuls des noms
d'objets et des types apparaissent.

Usage :
    python schema_parity.py --target-env <fichier .env>   # clé AYDEN_STAGING_DATABASE_URL
    python schema_parity.py --inventory-only              # dump l'inventaire PROD seul
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys

import psycopg

PRODUCTION_REF = "vtxkciupyafukhdsgxgw"
PROD_ENV = pathlib.Path(r"C:/Projects/AIHomeArchitect/backend/.env")
OUT_DIR = pathlib.Path(__file__).parent / ".local-db" / "schema_inventory"

# Chaque requête ne lit QUE des catalogues. Aucune table applicative n'est touchée.
QUERIES = {
    "columns": """
        select table_name, column_name, data_type, is_nullable,
               coalesce(column_default,'') as column_default
        from information_schema.columns
        where table_schema='public'
        order by table_name, ordinal_position
    """,
    "constraints": """
        select tc.table_name, tc.constraint_type, tc.constraint_name,
               coalesce(cc.check_clause,'') as check_clause
        from information_schema.table_constraints tc
        left join information_schema.check_constraints cc
               on cc.constraint_name = tc.constraint_name
              and cc.constraint_schema = tc.constraint_schema
        where tc.table_schema='public'
        order by tc.table_name, tc.constraint_type, tc.constraint_name
    """,
    "indexes": """
        select tablename, indexname, indexdef
        from pg_indexes where schemaname='public'
        order by tablename, indexname
    """,
    "functions": """
        select p.proname,
               pg_get_function_identity_arguments(p.oid) as args,
               p.prosecdef as security_definer
        from pg_proc p join pg_namespace n on n.oid=p.pronamespace
        where n.nspname='public'
        order by p.proname, args
    """,
    "triggers": """
        select event_object_table, trigger_name, action_timing, event_manipulation
        from information_schema.triggers
        where trigger_schema='public'
        order by event_object_table, trigger_name
    """,
    "rls": """
        select c.relname, c.relrowsecurity
        from pg_class c join pg_namespace n on n.oid=c.relnamespace
        where n.nspname='public' and c.relkind='r'
        order by c.relname
    """,
    "policies": """
        select tablename, policyname, cmd, coalesce(qual,'') as qual
        from pg_policies where schemaname='public'
        order by tablename, policyname
    """,
    "views": """
        select table_name from information_schema.views
        where table_schema='public' order by table_name
    """,
}


def read_env(path: pathlib.Path, key: str) -> str:
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith(f"{key}="):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    return ""


def snapshot(url: str, label: str) -> dict:
    """Lit les catalogues. Connexion FORCÉE en lecture seule."""
    out: dict[str, list] = {}
    with psycopg.connect(url, connect_timeout=40) as conn:
        conn.read_only = True
        with conn.cursor() as cur:
            for name, sql in QUERIES.items():
                cur.execute(sql)
                out[name] = [tuple(r) for r in cur.fetchall()]
    total = sum(len(v) for v in out.values())
    print(f"  {label:<16} {total} lignes de catalogue lues")
    return out


def compare(prod: dict, target: dict) -> int:
    diffs = 0
    print("\n" + "=" * 78)
    print("PARITÉ  —  PROD  vs  CIBLE")
    print("=" * 78)
    for group in QUERIES:
        p, t = set(prod[group]), set(target[group])
        only_prod, only_target = sorted(p - t), sorted(t - p)
        if not only_prod and not only_target:
            print(f"  {group:<14} MATCH        ({len(p)} objets)")
            continue
        diffs += len(only_prod) + len(only_target)
        print(f"  {group:<14} DIFF         manquants={len(only_prod)}  en trop={len(only_target)}")
        for row in only_prod[:12]:
            print(f"      MANQUE EN CIBLE : {row}")
        if len(only_prod) > 12:
            print(f"      … et {len(only_prod)-12} autres")
        for row in only_target[:6]:
            print(f"      EN TROP EN CIBLE : {row}")
        if len(only_target) > 6:
            print(f"      … et {len(only_target)-6} autres")
    print("=" * 78)
    print(f"TOTAL DIFFÉRENCES : {diffs}")
    return diffs


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--target-env", help="fichier .env portant AYDEN_STAGING_DATABASE_URL")
    ap.add_argument("--inventory-only", action="store_true")
    args = ap.parse_args()

    prod_url = read_env(PROD_ENV, "SUPABASE_DB_URL")
    if PRODUCTION_REF not in prod_url:
        print("REFUS : la source ne porte pas la ref de production attendue.", file=sys.stderr)
        return 2

    print("lecture des catalogues (les deux connexions sont en LECTURE SEULE) :")
    prod = snapshot(prod_url, "PRODUCTION")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    inv = OUT_DIR / "prod_inventory.json"
    inv.write_text(json.dumps({k: [list(r) for r in v] for k, v in prod.items()},
                              indent=1, ensure_ascii=False), encoding="utf-8")
    print(f"  inventaire PROD écrit : {inv.name}")

    if args.inventory_only or not args.target_env:
        print("\nAucune cible fournie — inventaire seul.")
        for g in QUERIES:
            print(f"  {g:<14} {len(prod[g])}")
        return 0

    target_url = read_env(pathlib.Path(args.target_env), "AYDEN_STAGING_DATABASE_URL")
    if not target_url:
        print("REFUS : AYDEN_STAGING_DATABASE_URL absent du fichier cible.", file=sys.stderr)
        return 2
    if PRODUCTION_REF in target_url:
        print("REFUS : la CIBLE porte la ref de PRODUCTION.", file=sys.stderr)
        return 2

    target = snapshot(target_url, "CIBLE")
    return 1 if compare(prod, target) else 0


if __name__ == "__main__":
    sys.exit(main())
