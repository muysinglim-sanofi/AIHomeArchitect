"""Lance le backend CANONIQUE contre le projet Supabase STAGING — local seulement.

À QUOI SERT CE LANCEUR
----------------------
`main.py` appelle `load_dotenv(override=True)` au moment de son import, et
python-dotenv résout `.env` par rapport à ce module — c'est-à-dire `backend/.env`,
qui pointe la PRODUCTION. Exporter des variables staging dans l'environnement ne
suffit donc pas : `override=True` les écraserait quelques lignes après l'import.
Ce lanceur installe le fichier staging comme la SEULE chose que `load_dotenv`
puisse jamais lire, AVANT que `main` ne soit importé.

CE QU'IL N'EST PAS
------------------
Ce n'est pas `run_pwa_staging.py`. Celui-là monte en plus le routeur
`/pwa/staging/*`, une surface web plus étroite qui n'expose pas `/refine`,
`/me/status`, `/devices`, `/purchases/sync` ni `/v1/intents/latest`. Le mobile
appelle la RACINE. Ce lanceur ne monte donc AUCUN routeur supplémentaire : il
sert `main.py` tel quel, avec les endpoints mobiles canoniques.

FAIL-CLOSED, DANS L'ORDRE
-------------------------
1. le fichier de secrets staging doit exister et être complet ;
2. SUPABASE_URL doit porter la ref staging et NE PAS porter la ref production —
   contrôlé sur la valeur RÉSOLUE, jamais sur un nom de fichier ;
3. la garde de `main.py` (AYDEN_DEPLOY_ENV=staging) revérifie après l'import, si
   bien qu'un rechargement parasite qui repointerait le process sur la production
   ne peut pas atteindre `uvicorn.run`.

Usage :  python backend/run_mobile_staging.py [--port 8000]
"""
from __future__ import annotations

import argparse
import os
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
STAGING_ENV = HERE / '.env.mobile-staging.local'
PRODUCTION_ENV = HERE / '.env'

STAGING_REF = 'lpegjufuhbmwwkfnaxjh'
PRODUCTION_REF = 'vtxkciupyafukhdsgxgw'
REQUIRED = ('SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'OPENAI_API_KEY')


def _die(msg: str) -> None:
    """N'imprime QUE le nom de ce qui a échoué — jamais une valeur."""
    print(f'REFUSING TO START: {msg}', file=sys.stderr)
    raise SystemExit(2)


def _parse(path: pathlib.Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for raw in path.read_text(encoding='utf-8').splitlines():
        line = raw.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        k, _, v = line.partition('=')
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def _assert_staging(url: str, where: str) -> None:
    if PRODUCTION_REF in url:
        _die(f'{where}: SUPABASE_URL points at the PRODUCTION project.')
    if STAGING_REF not in url:
        _die(f'{where}: SUPABASE_URL is not the authorized staging project '
             f'({STAGING_REF}).')


def _git_sha() -> str:
    """SHA court, résolu UNE fois au lancement — jamais par requête.

    Le sous-processus git tourne ici, dans le lanceur, pas dans un handler HTTP.
    Sur Render c'est RENDER_GIT_COMMIT qui remplit ce rôle ; en local on lit le
    dépôt. Échec ⇒ on laisse main.py retomber sur "unknown", jamais une invention.
    """
    try:
        out = subprocess.run(
            ['git', 'rev-parse', '--short=7', 'HEAD'],
            cwd=str(HERE), capture_output=True, text=True, timeout=10,
        )
        return out.stdout.strip() if out.returncode == 0 else ''
    except Exception:
        return ''


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8000)
    parser.add_argument('--host', default='0.0.0.0',
                        help="0.0.0.0 pour que l'émulateur Android puisse "
                             "joindre l'hôte via 10.0.2.2")
    args = parser.parse_args()

    if not STAGING_ENV.exists():
        _die(f'{STAGING_ENV.name} does not exist.')

    values = _parse(STAGING_ENV)
    missing = [k for k in REQUIRED if not values.get(k)]
    if missing:
        _die(f'{STAGING_ENV.name} is missing values for: {", ".join(missing)}')

    _assert_staging(values['SUPABASE_URL'], 'staging secrets file')

    # 1) Amorce l'environnement du process depuis le fichier staging.
    for k, v in values.items():
        os.environ[k] = v

    # 1b) Identité de déploiement — imposée par le lanceur, pas laissée au hasard.
    #     Un fichier .env peut les déclarer ; on les force ici pour qu'un fichier
    #     incomplet ne fasse pas démarrer un process qui se croit en production.
    os.environ['AYDEN_DEPLOY_ENV'] = 'staging'
    os.environ.setdefault('AYDEN_SERVICE_NAME', 'ayden-backend-local-staging')
    _sha = _git_sha()
    if _sha:
        os.environ.setdefault('AYDEN_GIT_SHA', _sha)

    # 1c) Les flags moteur ne sont PAS épinglés ici, délibérément.
    #     À cette baseline, `main.py` force lui-même la config benchée via
    #     `_BENCHED_DEFAULT_ON` au niveau module (un "0" explicite gagne toujours).
    #     Les répliquer ici créerait une seconde liste à maintenir, et donc une
    #     occasion de diverger de la production. Une seule liste, un seul endroit.

    # 2) Faire du fichier staging le SEUL fichier que load_dotenv puisse lire.
    #    `main.py` fait `from dotenv import load_dotenv` à SON import : patcher
    #    l'attribut du module ICI, avant d'importer main, est ce qu'il liera.
    import dotenv  # noqa: PLC0415

    _real_load = dotenv.load_dotenv

    def _staging_only_load(*_args, **kwargs):  # noqa: ANN002, ANN003
        kwargs.pop('dotenv_path', None)
        kwargs['override'] = True
        return _real_load(str(STAGING_ENV), **kwargs)

    dotenv.load_dotenv = _staging_only_load
    if PRODUCTION_ENV.exists():
        print(f'[mobile-staging] {PRODUCTION_ENV.name} exists and is NOT loaded '
              f'(production config, deliberately bypassed).')

    # 3) Importer l'app canonique. Aucun moteur n'est copié, rien n'est redéfini,
    #    AUCUN routeur supplémentaire n'est monté (contrairement au lanceur PWA).
    sys.path.insert(0, str(HERE))
    os.chdir(HERE)
    import main as canonical  # noqa: PLC0415

    # 4) Revérification APRÈS import — un rechargement parasite qui aurait
    #    repointé le process sur la production ne doit pas atteindre uvicorn.
    _assert_staging(os.environ.get('SUPABASE_URL', ''), 'post-import environment')

    # Dire QUEL moteur ce process fait tourner. COMPOSER_VERSION est lu à
    # l'import, et la ligne que main.py journalise pour lui est émise avant que
    # le handler de fichier existe — son absence de backend.log ne prouve rien.
    print('[mobile-staging] composer   : '
          + canonical.compose_generation_prompt.__module__)
    print('[mobile-staging] deploy_env : '
          + os.environ['AYDEN_DEPLOY_ENV']
          + '  service=' + os.environ['AYDEN_SERVICE_NAME'])
    print('[mobile-staging] app_env    : '
          + os.environ.get('APP_ENV', 'unset')
          + '  (profil de génération — doit être celui de la production)')
    print(f'[mobile-staging] listening  : http://{args.host}:{args.port}')
    print('[mobile-staging] emulateur Android -> http://10.0.2.2:'
          f'{args.port}   (l\'hôte, vu depuis l\'AVD)')

    import uvicorn  # noqa: PLC0415

    # Pas de --reload : sous Windows il orpheline des workers multiprocessing qui
    # servent une DNA périmée (cf. run.sh). Process unique, redémarrage explicite.
    uvicorn.run(canonical.app, host=args.host, port=args.port, reload=False)


if __name__ == '__main__':
    main()
