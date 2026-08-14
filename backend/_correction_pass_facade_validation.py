"""Correction Pass (Groupe 2026-08-13) — Phase 4 / Lot B : façade inachevée, flag OFF.

100% HORS-LIGNE : aucun `openai` réel n'est appelé (le client de main.py est remplacé
par un objet factice qui capture les kwargs et rend une réponse scriptée). Aucune
écriture dans backend/logs/backend.log autre que l'append normal de l'import de main.

MÉTHODE DE BASELINE (la question centrale de ce harnais : « byte-identique par rapport
à QUOI ? »). Deux sources INDÉPENDANTES, toutes deux issues du code ANTÉRIEUR :
  (1) _correction_pass_facade_baseline.json — figé en exécutant le module
      `git show HEAD:backend/prompt_engine/preservation.py` (donc du code strictement
      pré-modification) : sha256 + longueur de build_stage_contract() pour 6 pièces
      extérieures + 8 intérieures × 5 atmosphères, sha256 + longueur du prompt
      ASSEMBLÉ (composer.compose_generation_prompt → apply_stage_mode) pour les 6
      pièces extérieures × 5 atmosphères, et le TEXTE EXACT des deux prompts de vision
      (unified 4 champs + legacy) avec leur prompt_hash et leur max_tokens.
  (2) BLOC 0 — le même module HEAD est rechargé À CHAUD ici et comparé directement,
      tant que HEAD ne contient pas encore le flag (= tant que le correctif n'est pas
      commité). Baseline RECALCULÉE, pas recopiée : elle ne peut pas devenir
      tautologique sans que le harnais le dise (SKIP explicite).

CONFIGURATION. `import main` est fait AVANT tout calcul de prompt : c'est lui qui force
les flags _BENCHED_DEFAULT_ON (BIMODAL_ENABLED, PROMPT_CONTRACT_LIGHT, DNA_CLEANUP_V1…).
Sans lui, on comparerait des prompts dans une configuration qui ne tourne nulle part —
et une contradiction n'apparaissant qu'en config prod passerait au travers.

Matrice couverte :
  BLOC 0  baseline indépendante (git HEAD)      → flag OFF ⇒ 14 pièces × 5 atmo identiques
  BLOC 1  flag OFF                              → contrats + prompts assemblés identiques,
                                                  Y COMPRIS avec build_state="unfinished"
  BLOC 2  flag ON + build_state=finished        → identiques à la baseline
  BLOC 3  flag ON + unfinished + facade         → complétion ET géométrie dans le même
                                                  bloc, aucune phrase contradictoire
                                                  survivante (verrous 1 ET 2 levés)
  BLOC 4  flag ON + unfinished + 5 autres pièces extérieures + 8 intérieures → identiques
  BLOC 5  prompt de vision                      → OFF byte-identique (chaîne exacte +
                                                  prompt_hash + max_tokens=40) ; ON =
                                                  5 champs + max_tokens relevé
  BLOC 6  fail-safe du canal d'état             → toute anomalie ⇒ "finished"
  BLOC 7  budget                                → mesure avant/après du prompt façade

Run: PYTHONIOENCODING=utf-8 PYTHONPATH=. .venv/Scripts/python.exe _correction_pass_facade_validation.py
"""
import asyncio
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
from types import SimpleNamespace

FLAG = "AYDEN_UNFINISHED_FACADE_COMPLETION"
EXTERIOR = ["facade", "garden", "terrace", "pool_area", "balcony", "driveway"]
INTERIOR = ["living_room", "bedroom", "kitchen", "bathroom",
            "dining_room", "office", "entrance", "hallway"]
ATMO = [("warm_modern", "Warm Modern"), ("soft_luxury", "Soft Luxury"),
        ("japandi_calm", "Japandi Calm"), ("nordic_warmth", "Nordic Warmth"),
        ("tropical_escape", "Tropical Escape")]

_fails = 0
_total = 0


def check(label, cond, got=""):
    """Un check = 1 ligne ; `got` est TOUJOURS imprimé (valeur observée, pas juste PASS)."""
    global _fails, _total
    _total += 1
    ok = bool(cond)
    _fails += (not ok)
    print(f"  [{'OK ' if ok else 'FAIL'}] {label}   observed={got!r}")


def sha(s):
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def set_flag(on):
    if on:
        os.environ[FLAG] = "1"
    else:
        os.environ.pop(FLAG, None)


# ── Imports du code SOUS TEST ────────────────────────────────────────────────
set_flag(False)   # avant tout import : le flag doit être OFF par défaut
sys.path.insert(0, os.getcwd())
# `import main` D'ABORD : il force les flags benchés (_BENCHED_DEFAULT_ON) → tous les
# prompts calculés plus bas le sont dans la configuration réellement servie en prod.
# Il fournit aussi _classify_ayden (BLOCS 5-6). Aucun réseau : le client OpenAI est
# remplacé par _FakeOpenAI avant chaque appel.
import main as backend_main  # noqa: E402
from prompt_engine.preservation import (  # noqa: E402
    apply_stage_mode, build_stage_contract,
    is_unfinished_facade_completion_enabled,
    _DNA_FACADE_ARCH_GUARD, _EXTERIOR_CONTEXT_SITE_CLAUSE,
)
from prompt_engine.composer import compose_generation_prompt  # noqa: E402

_BASE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "_correction_pass_facade_baseline.json")
with open(_BASE_PATH, encoding="utf-8") as _f:
    BASE = json.load(_f)


def assemble(room, aid, alabel, build_state="finished"):
    """Reproduit main.py : compose_generation_prompt(...) puis apply_stage_mode(...)."""
    p = compose_generation_prompt(
        style_label=alabel, room_type=room, room_description="",
        user_instruction="", iteration=1, history=[], compact_prompts=False,
        generation_mode="preserve",
    )
    return apply_stage_mode(p, room_label=room, atmosphere_label=alabel,
                            atmosphere_id=aid, build_state=build_state)


print("=" * 78)
print("BLOC 0 — baseline INDÉPENDANTE recalculée depuis git HEAD (pré-modification)")
print("=" * 78)
_head_mod = None
try:
    _src = subprocess.run(
        ["git", "show", "HEAD:backend/prompt_engine/preservation.py"],
        cwd=os.path.dirname(os.getcwd()), capture_output=True, text=True,
        encoding="utf-8", check=True).stdout
    if FLAG in _src:
        print(f"  [SKIP] HEAD contient déjà {FLAG} → baseline git tautologique ; "
              f"le JSON figé (BLOCS 1-2) reste la référence.")
    else:
        _tmp = os.path.join(tempfile.mkdtemp(), "preservation_baseline.py")
        with open(_tmp, "w", encoding="utf-8") as f:
            f.write(_src)
        _spec = importlib.util.spec_from_file_location("preservation_baseline", _tmp)
        _head_mod = importlib.util.module_from_spec(_spec)
        _spec.loader.exec_module(_head_mod)
except Exception as exc:  # git absent / worktree exotique → le JSON figé suffit
    print(f"  [SKIP] baseline git indisponible ({type(exc).__name__}: {exc})")

if _head_mod is not None:
    set_flag(False)
    _diff = [f"{r}|{a}" for r in EXTERIOR + INTERIOR for a, lab in ATMO
             if build_stage_contract(r, lab, a) != _head_mod.build_stage_contract(r, lab, a)]
    check("flag OFF — 14 pièces × 5 atmo identiques au code de HEAD", not _diff,
          f"{len(EXTERIOR + INTERIOR) * 5} contrats comparés, divergences={_diff}")
    set_flag(True)
    _diff = [f"{r}|{a}" for r in EXTERIOR + INTERIOR for a, lab in ATMO
             if build_stage_contract(r, lab, a) != _head_mod.build_stage_contract(r, lab, a)]
    check("flag ON sans build_state — identiques au code de HEAD", not _diff,
          f"divergences={_diff}")
    set_flag(False)

print("=" * 78)
print("BLOC 1 — flag OFF ⇒ byte-identité totale (y compris build_state='unfinished')")
print("=" * 78)
set_flag(False)
check("le flag est bien OFF par défaut (absent de l'environnement)",
      not is_unfinished_facade_completion_enabled(), os.environ.get(FLAG, "(absent)"))

_bad = []
for room in EXTERIOR + INTERIOR:
    for aid, alabel in ATMO:
        c = build_stage_contract(room, alabel, aid)
        ref = BASE["stage_contracts"][f"{room}|{aid}"]
        if sha(c) != ref["sha256"] or len(c) != ref["len"]:
            _bad.append(f"{room}|{aid}")
check("build_stage_contract — 70 cellules identiques à la baseline figée", not _bad,
      f"70 comparées, divergences={_bad}")

_bad = []
for room in EXTERIOR:
    for aid, alabel in ATMO:
        for bs in ("finished", "unfinished", "", "UNFINISHED", "bogus", None):
            out, applied = assemble(room, aid, alabel, build_state=bs)
            ref = BASE["assembled"][f"{room}|{aid}"]
            if sha(out) != ref["sha256"] or not applied:
                _bad.append(f"{room}|{aid}|{bs}")
check("prompt ASSEMBLÉ — 6 pièces ext × 5 atmo × 6 build_state identiques", not _bad,
      f"180 comparés, divergences={_bad}")

print("=" * 78)
print("BLOC 2 — flag ON + build_state='finished' ⇒ byte-identique à la baseline")
print("=" * 78)
set_flag(True)
check("le flag est bien lu à l'appel (pas au chargement du module)",
      is_unfinished_facade_completion_enabled(), os.environ.get(FLAG))
_bad = []
for room in EXTERIOR:
    for aid, alabel in ATMO:
        out, _ = assemble(room, aid, alabel, build_state="finished")
        if sha(out) != BASE["assembled"][f"{room}|{aid}"]["sha256"]:
            _bad.append(f"{room}|{aid}")
check("flag ON + finished — 30 prompts assemblés identiques", not _bad,
      f"30 comparés, divergences={_bad}")

print("=" * 78)
print("BLOC 3 — flag ON + build_state='unfinished' + facade ⇒ le contrat de complétion")
print("=" * 78)
set_flag(True)
# Les 3 ordres qui doivent coexister, + les 2 phrases qui doivent avoir DISPARU.
MUST = {
    "ordre de complétion des finitions manquantes":
        "complete only the visibly missing finish elements",
    "les 3 finitions nommées (vitrage / porte-garage / finitions)":
        "glazing and window frames, doors and the garage closure",
    "préservation exacte de la géométrie des ouvertures":
        "keep the exact existing geometry, position, size and proportion of every "
        "wall, storey, roof and opening",
    "complétion bornée aux limites existantes (MÊME phrase)":
        "WITHIN those exact existing boundaries",
    "interdiction créer/supprimer/déplacer/redimensionner":
        "Never create, remove, move, resize or reshape any opening, wall, storey or "
        "structural element",
    "verrou 2 levé — la clause DNA de remplacement est présente":
        "the visibly missing finish elements (glazing, window frames, doors, garage "
        "closure, facade finishes) may be completed",
}
MUST_NOT = {
    "verrou 2 — phrase de garde DNA (interdit tout restylage)": _DNA_FACADE_ARCH_GUARD,
    "verrou 1 — verrouillage de l'état de surface (cladding)":
        "all facade materials and cladding",
    "verrou 1 — 'glazing' listé comme fait à reproduire pixel-for-pixel":
        "(windows, doors, garage door, glazing)",
    "clause de contexte non portée (interdit de finir le chantier)":
        _EXTERIOR_CONTEXT_SITE_CLAUSE,
}
for aid, alabel in ATMO:
    out, applied = assemble("facade", aid, alabel, build_state="unfinished")
    ok_must = [k for k, v in MUST.items() if v not in out]
    ok_not = [k for k, v in MUST_NOT.items() if v in out]
    check(f"facade × {aid} — les 6 ordres requis présents", not ok_must,
          f"manquants={ok_must}")
    check(f"facade × {aid} — aucune phrase contradictoire survivante", not ok_not,
          f"survivantes={ok_not}")
    check(f"facade × {aid} — le prompt a bien changé vs baseline", applied and
          sha(out) != BASE["assembled"][f"facade|{aid}"]["sha256"],
          f"delta_chars={len(out) - BASE['assembled'][f'facade|{aid}']['len']:+d}")

# La géométrie doit rester verrouillée mot pour mot (le hard-lock n'est PAS levé).
_geo = ["reproduce EXACTLY (pixel-for-pixel)",
        "with their exact positions, sizes and proportions",
        "the roofline and the roof",
        "and the storeys and levels",
        "never add or extend PERMANENT architecture"]
out_f, _ = assemble("facade", "warm_modern", "Warm Modern", build_state="unfinished")
check("le verrou GÉOMÉTRIQUE reste intégralement en place",
      all(g in out_f for g in _geo), [g for g in _geo if g not in out_f])
check("la clause de contexte reste présente, portée sur le VOISINAGE",
      "never turn a NEIGHBOURING construction site" in out_f,
      "scoped clause present")

print("=" * 78)
print("BLOC 4 — flag ON + unfinished sur toute autre pièce ⇒ byte-identique")
print("=" * 78)
set_flag(True)
_bad = []
for room in [r for r in EXTERIOR if r != "facade"]:
    for aid, alabel in ATMO:
        out, _ = assemble(room, aid, alabel, build_state="unfinished")
        if sha(out) != BASE["assembled"][f"{room}|{aid}"]["sha256"]:
            _bad.append(f"{room}|{aid}")
check("garden/terrace/pool_area/balcony/driveway × 5 atmo — 25 prompts identiques",
      not _bad, f"25 comparés, divergences={_bad}")
_bad = []
for room in INTERIOR:
    for aid, alabel in ATMO:
        c = build_stage_contract(room, alabel, aid, unfinished_facade=True)
        if sha(c) != BASE["stage_contracts"][f"{room}|{aid}"]["sha256"]:
            _bad.append(f"{room}|{aid}")
check("8 pièces INTÉRIEURES × 5 atmo — contrats identiques même unfinished_facade=True",
      not _bad, f"40 comparés, divergences={_bad}")

print("=" * 78)
print("BLOC 5 — prompt de vision (_classify_ayden) : OFF = canari intact, ON = 5 champs")
print("=" * 78)


class _FakeOpenAI:
    """Reproduit la SEULE surface utilisée par _classify_ayden :
    await openai.chat.completions.create(**kw). Aucune socket."""

    def __init__(self, content=None, exc=None):
        self._content, self._exc = content, exc
        self.kwargs = None
        self.chat = SimpleNamespace(completions=SimpleNamespace(create=self._create))

    async def _create(self, **kw):
        self.kwargs = kw
        if self._exc is not None:
            raise self._exc
        return SimpleNamespace(choices=[SimpleNamespace(
            message=SimpleNamespace(content=self._content))])


def run_vision(content=None, exc=None, flag=False, unified="1"):
    fake = _FakeOpenAI(content=content, exc=exc)
    _prev_client, _prev_uni = backend_main.openai, os.environ.get("AYDEN_UNIFIED_VISION")
    backend_main.openai = fake
    os.environ["AYDEN_UNIFIED_VISION"] = unified
    set_flag(flag)
    try:
        out = asyncio.run(backend_main._classify_ayden(b"\xff\xd8fake-jpeg"))
    finally:
        backend_main.openai = _prev_client
        if _prev_uni is not None:
            os.environ["AYDEN_UNIFIED_VISION"] = _prev_uni
    txt = fake.kwargs["messages"][0]["content"][1]["text"]
    return out, txt, fake.kwargs


_out, _txt, _kw = run_vision(content="terrace | tropical_escape | high | x", flag=False)
check("flag OFF — prompt de vision unified IDENTIQUE au caractère près",
      _txt == BASE["vision_prompt_unified"],
      f"len={len(_txt)} vs {len(BASE['vision_prompt_unified'])}")
check("flag OFF — prompt_hash (canari loggé) inchangé",
      hashlib.sha1(_txt.encode()).hexdigest()[:12] == BASE["vision_prompt_unified_sha1_12"],
      hashlib.sha1(_txt.encode()).hexdigest()[:12])
check("flag OFF — max_tokens inchangé", _kw["max_tokens"] == 40, _kw["max_tokens"])
check("flag OFF — déterminisme inchangé (temperature/seed)",
      _kw.get("temperature") == 0 and _kw.get("seed") == 42,
      (_kw.get("temperature"), _kw.get("seed")))
check("flag OFF — build_state par défaut 'finished'",
      _out["build_state"] == "finished", _out["build_state"])

_out, _txt_l, _kw = run_vision(content="living_room | warm_modern | high | x",
                               flag=True, unified="0")
check("flag ON mais UNIFIED off — prompt legacy 4 champs inchangé",
      _txt_l == BASE["vision_prompt_legacy"] and _kw["max_tokens"] == 40,
      f"len={len(_txt_l)} max_tokens={_kw['max_tokens']}")

_out, _txt_on, _kw = run_vision(
    content="facade | warm_modern | high | raw shell, no glazing | unfinished", flag=True)
check("flag ON — 5 champs annoncés dans le contrat de sortie",
      "room_type | recommended_atmosphere | confidence | reason | build_state" in _txt_on
      and "EXACTLY five fields" in _txt_on, "5-field contract present")
check("flag ON — définition opérationnelle stricte présente (§5.2)",
      "- build_state: finished or unfinished" in _txt_on
      and "If in doubt, answer finished." in _txt_on
      and "brutalism" in _txt_on, "strict definition present")
check("flag ON — max_tokens relevé pour ne pas tronquer le 5ᵉ champ",
      _kw["max_tokens"] == 56, _kw["max_tokens"])
check("flag ON — build_state='unfinished' correctement parsé",
      _out["build_state"] == "unfinished" and _out["room"] == "facade",
      (_out["room"], _out["build_state"]))

print("=" * 78)
print("BLOC 6 — fail-safe du canal d'état : toute anomalie retombe sur 'finished'")
print("=" * 78)
_cases = [
    ("champ absent (4 champs seulement)", dict(content="facade | warm_modern | high | x")),
    ("valeur inconnue", dict(content="facade | warm_modern | high | x | half-built")),
    ("champ vide", dict(content="facade | warm_modern | high | x | ")),
    ("confiance low + unfinished", dict(content="facade | warm_modern | low | x | unfinished")),
    ("réponse vide", dict(content="")),
    ("réponse hors format", dict(content="I cannot analyse this image.")),
    ("exception client", dict(exc=RuntimeError("boom"))),
    ("réponse None", dict(content=None)),
]
for label, kw in _cases:
    out, _, _ = run_vision(flag=True, **kw)
    check(f"fail-safe — {label}", out["build_state"] == "finished", out["build_state"])
out, _, _ = run_vision(content="facade | warm_modern | high | x | unfinished", flag=False)
check("fail-safe — flag OFF : le 5ᵉ champ est ignoré même s'il est renvoyé",
      out["build_state"] == "finished", out["build_state"])

# Le canal d'état ne doit rien déclencher hors facade, même avec un modèle bavard.
set_flag(True)
_bad = [r for r in [x for x in EXTERIOR if x != "facade"] + INTERIOR
        if apply_stage_mode(
            compose_generation_prompt(style_label="Warm Modern", room_type=r,
                                      room_description="", user_instruction="",
                                      iteration=1, history=[], compact_prompts=False,
                                      generation_mode="preserve"),
            room_label=r, atmosphere_label="Warm Modern", atmosphere_id="warm_modern",
            build_state="unfinished")[0]
        != apply_stage_mode(
            compose_generation_prompt(style_label="Warm Modern", room_type=r,
                                      room_description="", user_instruction="",
                                      iteration=1, history=[], compact_prompts=False,
                                      generation_mode="preserve"),
            room_label=r, atmosphere_label="Warm Modern", atmosphere_id="warm_modern",
            build_state="finished")[0]]
check("fail-safe — build_state='unfinished' est INERTE sur les 13 autres pièces",
      not _bad, f"divergences={_bad}")

print("=" * 78)
print("BLOC 7 — budget prompt (le prompt façade échappe déjà au budget : ~6,8-7,2k)")
print("=" * 78)
set_flag(True)
for aid, alabel in ATMO:
    before = BASE["assembled"][f"facade|{aid}"]["len"]
    after = len(assemble("facade", aid, alabel, build_state="unfinished")[0])
    print(f"  [MEASURE] facade × {aid:16} avant={before:5} après={after:5} "
          f"delta={after - before:+5} ({100.0 * (after - before) / before:+.1f} %)")

set_flag(False)
print("=" * 78)
print(f"TOTAL: {_total - _fails}/{_total} OK   ({_fails} FAIL)")
sys.exit(1 if _fails else 0)
