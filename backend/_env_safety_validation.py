"""Validation hors-ligne de la couche de sûreté d'environnement (staging mobile).

Couvre la matrice décidée le 2026-08-14 :

    AYDEN_DEPLOY_ENV=staging    + Supabase staging   -> DÉMARRE
    AYDEN_DEPLOY_ENV=staging    + Supabase PRODUCTION-> REFUSE (fail-closed)
    AYDEN_DEPLOY_ENV=staging    + projet inconnu     -> REFUSE (fail-closed)
    AYDEN_DEPLOY_ENV=production + Supabase production-> comportement inchangé
    /health en staging  -> environment/service/commit, AUCUN secret
    SHA absent          -> "unknown", jamais une supposition

POURQUOI UN SOUS-PROCESSUS PAR CAS. La garde s'exécute au moment de l'IMPORT de
`main` (elle doit refuser AVANT la création du client Supabase, main.py:908).
Un `importlib.reload` ne rejouerait pas proprement l'état module ; et surtout un
`SystemExit(2)` levé à l'import tuerait le harnais lui-même. Chaque cas tourne
donc dans un interpréteur neuf, avec un environnement fabriqué, et on observe le
CODE DE SORTIE — c'est-à-dire exactement ce que Render observera.

AUCUN RÉSEAU. `main` est lourd à importer mais n'ouvre aucune connexion à
l'import : le client Supabase est construit avec des valeurs factices et
`create_client` ne fait pas d'appel réseau. OpenAI n'est pas contacté. Aucune
requête n'est émise.

Lancement :
    cd backend
    PYTHONIOENCODING=utf-8 PYTHONPATH=. .venv/Scripts/python.exe _env_safety_validation.py
"""
from __future__ import annotations

import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

REF_STAGING = "eedcahzekpgxvvfxufbk"
REF_PRODUCTION = "vtxkciupyafukhdsgxgw"

URL_STAGING = f"https://{REF_STAGING}.supabase.co"
URL_PRODUCTION = f"https://{REF_PRODUCTION}.supabase.co"
URL_UNKNOWN = "https://someotherproject.supabase.co"

_total = 0
_fails = 0


def check(label: str, cond: bool, got: str = "") -> None:
    global _total, _fails
    _total += 1
    if not cond:
        _fails += 1
    tag = "OK " if cond else "FAIL"
    suffix = f"   observed={got}" if got else ""
    print(f"  [{tag}] {label}{suffix}")


def _base_env() -> dict:
    """Environnement minimal pour importer `main` sans réseau ni .env réel.

    load_dotenv(override=True) écraserait nos valeurs avec le .env local, qui
    pointe la PRODUCTION — ce qui inverserait silencieusement chaque cas de test.
    On neutralise donc dotenv en pointant son fichier sur un chemin inexistant.
    """
    env = dict(os.environ)
    env.pop("AYDEN_DEPLOY_ENV", None)
    env.pop("AYDEN_SERVICE_NAME", None)
    env.pop("AYDEN_GIT_SHA", None)
    env.pop("RENDER_GIT_COMMIT", None)
    env["DOTENV_PATH_OVERRIDE_GUARD"] = "1"
    env["SUPABASE_SERVICE_ROLE_KEY"] = "test-not-a-real-key"
    env["SUPABASE_JWT_SECRET"] = "test-not-a-real-secret"
    env["OPENAI_API_KEY"] = "test-not-a-real-key"
    env["PYTHONIOENCODING"] = "utf-8"
    env["PYTHONPATH"] = HERE
    return env


_PROBE = r"""
import os, sys, json, pathlib
# Neutralise le .env local AVANT d'importer main : sinon load_dotenv(override=True)
# réinjecte la PRODUCTION et le test ne prouve plus rien.
import dotenv
dotenv.load_dotenv = lambda *a, **k: False
try:
    import main
except SystemExit as exc:
    print("PROBE_EXIT=" + str(exc.code)); sys.exit(0)
except Exception as exc:
    print("PROBE_ERROR=" + type(exc).__name__ + ":" + str(exc)[:200]); sys.exit(0)
print("PROBE_STARTED=1")
print("PROBE_HEALTH=" + json.dumps({
    "environment": main._DEPLOY_ENV,
    "service": main._SERVICE_NAME,
    "commit": main._GIT_SHA,
    "profile": main._startup_profile.name,
}))
"""


def run_case(env_overrides: dict) -> dict:
    env = _base_env()
    env.update(env_overrides)
    proc = subprocess.run(
        [sys.executable, "-c", _PROBE],
        cwd=HERE, env=env, capture_output=True, text=True, timeout=180,
    )
    out = proc.stdout + proc.stderr
    res = {"started": "PROBE_STARTED=1" in out, "raw": out}
    for line in out.splitlines():
        if line.startswith("PROBE_EXIT="):
            res["exit"] = line.split("=", 1)[1].strip()
        if line.startswith("PROBE_HEALTH="):
            res["health"] = json.loads(line.split("=", 1)[1])
        if line.startswith("PROBE_ERROR="):
            res["error"] = line.split("=", 1)[1]
    res["refused"] = "[ENV-SAFETY] staging backend refused to start" in out
    return res


print("=== SÛRETÉ D'ENVIRONNEMENT — validation hors-ligne ===\n")

print("=== CAS 1 — staging + Supabase staging → DÉMARRE ===")
r1 = run_case({"AYDEN_DEPLOY_ENV": "staging", "SUPABASE_URL": URL_STAGING,
               "AYDEN_SERVICE_NAME": "ayden-backend-staging",
               "AYDEN_GIT_SHA": "341b5e7ed76468be68dc898b4064562dfb91210c"})
check("le backend démarre", r1["started"], r1.get("error", "")[:80])
check("la garde a validé le projet staging",
      "[ENV-SAFETY] staging Supabase project verified" in r1["raw"])
check("aucun refus", not r1["refused"])

print("\n=== CAS 2 — staging + Supabase PRODUCTION → REFUSE ===")
r2 = run_case({"AYDEN_DEPLOY_ENV": "staging", "SUPABASE_URL": URL_PRODUCTION})
check("le backend REFUSE de démarrer", not r2["started"])
check("code de sortie 2", r2.get("exit") == "2", str(r2.get("exit")))
check("message [ENV-SAFETY] émis", r2["refused"])
check("la raison mentionne le projet de production",
      "production project referenced" in r2["raw"])
check("AUCUNE valeur d'URL Supabase dans la sortie",
      REF_PRODUCTION not in r2["raw"] and "supabase.co" not in r2["raw"])

print("\n=== CAS 3 — staging + projet inconnu → REFUSE ===")
r3 = run_case({"AYDEN_DEPLOY_ENV": "staging", "SUPABASE_URL": URL_UNKNOWN})
check("le backend REFUSE de démarrer", not r3["started"])
check("code de sortie 2", r3.get("exit") == "2", str(r3.get("exit")))
check("la raison mentionne le projet staging attendu",
      "expected staging project not referenced" in r3["raw"])
check("AUCUNE valeur d'URL Supabase dans la sortie",
      "supabase.co" not in r3["raw"])

print("\n=== CAS 4 — production + Supabase production → comportement inchangé ===")
r4 = run_case({"SUPABASE_URL": URL_PRODUCTION})          # AYDEN_DEPLOY_ENV absent
check("le backend démarre", r4["started"], r4.get("error", "")[:80])
check("environment vaut 'production' par défaut",
      r4.get("health", {}).get("environment") == "production",
      str(r4.get("health", {}).get("environment")))
check("service vaut 'ayden-backend' par défaut",
      r4.get("health", {}).get("service") == "ayden-backend",
      str(r4.get("health", {}).get("service")))
check("AUCUNE garde exécutée (pas de ligne ENV-SAFETY)",
      "[ENV-SAFETY]" not in r4["raw"])

print("\n=== CAS 5 — /health en staging : contenu et absence de secret ===")
h = r1.get("health", {})
check("environment=staging", h.get("environment") == "staging", str(h.get("environment")))
check("service=ayden-backend-staging",
      h.get("service") == "ayden-backend-staging", str(h.get("service")))
check("commit = SHA COURT (7 caractères)",
      h.get("commit") == "341b5e7", str(h.get("commit")))
check("aucune clé/URL/secret dans la réponse",
      not any(k in json.dumps(h) for k in
              ("supabase.co", "SUPABASE", "eyJ", "sk-", "key", "secret", "token")),
      json.dumps(h))

print("\n=== CAS 6 — SHA indisponible → 'unknown' ===")
r6 = run_case({"AYDEN_DEPLOY_ENV": "staging", "SUPABASE_URL": URL_STAGING})
check("commit='unknown' quand aucune source n'est fournie",
      r6.get("health", {}).get("commit") == "unknown",
      str(r6.get("health", {}).get("commit")))
r6b = run_case({"AYDEN_DEPLOY_ENV": "staging", "SUPABASE_URL": URL_STAGING,
                "RENDER_GIT_COMMIT": "abcdef1234567890"})
check("RENDER_GIT_COMMIT est utilisé et tronqué à 7",
      r6b.get("health", {}).get("commit") == "abcdef1",
      str(r6b.get("health", {}).get("commit")))

print("\n=== CAS 7 — le profil de génération est INDÉPENDANT du deploy env ===")
check("staging et production exposent le MÊME generation_profile",
      r1.get("health", {}).get("profile") == r4.get("health", {}).get("profile"),
      f"staging={r1.get('health',{}).get('profile')} "
      f"production={r4.get('health',{}).get('profile')}")

passed = _total - _fails
print(f"\n=== RÉCAPITULATIF : {passed}/{_total} PASS ({_fails} FAILURE(S)) ===")
sys.exit(1 if _fails else 0)
