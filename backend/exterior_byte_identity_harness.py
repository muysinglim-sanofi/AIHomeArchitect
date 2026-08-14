"""Byte-identity harness for EXTERIOR STAGE contracts (run from backend/).

Miroir extérieur de stage_byte_identity_harness.py (Lot B, 2026-08-13). Dumps the
6 exterior STAGE rooms x 5 atmospheres with length + sha, so a before/after diff
proves the "unfinished facade completion" work did NOT move a single byte outside
the 5 facade cells it is allowed to move.

POURQUOI PASSER PAR LE PROMPT COMPLET (et pas par build_stage_contract seul, comme
le fait le harnais intérieur). Deux raisons dures, toutes deux issues de l'audit
2026-08-13 :
  • _build_exterior_stage_contract(room_key) ne reçoit PAS l'atmosphère
    (preservation.py:645) : appelé seul, il rendrait les 5 atmosphères d'une même
    pièce byte-identiques, et le harnais serait AVEUGLE à toute régression portée
    par la DNA ;
  • le verrou 2 de Lot B — le garde DNA decor_language[0] de la cellule facade,
    byte-identique dans les 5 atmosphères (warm_modern.py:210, japandi_calm.py:181,
    nordic_warmth.py:204, soft_luxury.py:221, tropical_escape.py:200) — est émis
    dans le bloc ATMOSPHERE STYLE, donc HORS du contrat. Une substitution y est
    faite par apply_stage_mode : seul le prompt COMPLET la voit.
Le harnais reproduit donc exactement l'enchaînement de prod (main.py:4177-4201) :
compose_generation_prompt(...) puis apply_stage_mode(...). Aucun appel réseau : le
composer est un assembleur de chaînes pur et aucun client OpenAI n'est instancié.

COMPAT BASELINE. apply_stage_mode n'a gagné son paramètre `build_state` qu'avec le
Lot B. La signature est donc introspectée : le MÊME fichier de harnais tourne tel
quel sur l'arbre d'origine (git worktree HEAD) et sur l'arbre modifié, ce qui est
la condition pour que le diff ait une valeur de preuve.

Usage :
    cd backend
    # (1) référence — flag OFF (défaut)
    PYTHONIOENCODING=utf-8 PYTHONPATH=. .venv/Scripts/python.exe exterior_byte_identity_harness.py > off.txt
    # (2) flag ON, bâtiment terminé — DOIT être identique à (1)
    AYDEN_UNFINISHED_FACADE_COMPLETION=1 HARNESS_BUILD_STATE=finished ... > on_finished.txt
    # (3) flag ON, bâtiment inachevé — SEULES les 5 lignes facade doivent différer
    AYDEN_UNFINISHED_FACADE_COMPLETION=1 HARNESS_BUILD_STATE=unfinished ... > on_unfinished.txt
    diff off.txt on_finished.txt      # MUST be empty
    diff off.txt on_unfinished.txt    # MUST show exactly the 5 'facade' lines
"""
import sys, os, hashlib, inspect
sys.path.insert(0, os.getcwd())
from prompt_engine.composer import compose_generation_prompt  # noqa: E402
from prompt_engine.preservation import apply_stage_mode  # noqa: E402

# Les 6 pièces extérieures STAGE (= les clés de _EXTERIOR_STAGE_ITEMS). Ordre figé :
# facade en tête, car c'est la seule cellule que Lot B a le droit de faire bouger.
EXTERIOR = ["facade", "garden", "terrace", "pool_area", "balcony", "driveway"]
ATMO = [("warm_modern", "Warm Modern"), ("soft_luxury", "Soft Luxury"),
        ("japandi_calm", "Japandi Calm"), ("nordic_warmth", "Nordic Warmth"),
        ("tropical_escape", "Tropical Escape")]

# État du bâti injecté (canal Lot B). "finished" = comportement d'aujourd'hui.
BUILD_STATE = os.environ.get("HARNESS_BUILD_STATE", "finished").strip().lower()
# L'arbre d'origine ignore tout de `build_state` : on ne le passe que s'il existe.
_ACCEPTS_BUILD_STATE = "build_state" in inspect.signature(apply_stage_mode).parameters

# Témoin d'aveuglement : la phrase EXACTE du garde DNA facade. Si elle disparaît du
# prompt composé, le harnais ne prouve plus rien sur le verrou 2 — on l'imprime.
_DNA_GUARD = ("keep the building exactly — never add, alter, narrow, extend, or "
              "restyle any wall, window, door, roof, cladding or structure")

print(f"# build_state={BUILD_STATE} "
      f"flag={os.environ.get('AYDEN_UNFINISHED_FACADE_COMPLETION', '0')} "
      f"build_state_supported={_ACCEPTS_BUILD_STATE}")

for room in EXTERIOR:
    for aid, alabel in ATMO:
        prompt = compose_generation_prompt(
            style_label=alabel, room_type=room, room_description="",
            user_instruction="", iteration=1, history=[],
            generation_mode="preserve", edit_mode=None,
        )
        kw = {"build_state": BUILD_STATE} if _ACCEPTS_BUILD_STATE else {}
        out, staged = apply_stage_mode(
            prompt, room_label=room, atmosphere_label=alabel,
            atmosphere_id=aid, **kw)
        h = hashlib.sha1(out.encode("utf-8")).hexdigest()
        # 'n/a' hors façade : le garde appartient à la cellule DNA facade, il n'a
        # aucune raison d'apparaître ailleurs. 'orig' = verrou 2 intact (attendu
        # partout sauf sur les 5 cellules facade en build_state=unfinished + flag ON).
        guard = ("orig" if _DNA_GUARD in out else "SUBST") if room == "facade" else "n/a"
        print(f"{room:10} {aid:16} staged={int(staged)} guard={guard:5} "
              f"len={len(out):5} sha={h}")
