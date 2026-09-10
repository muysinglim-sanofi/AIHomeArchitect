"""Measure the SHIPPED PWA reply resolver on its fixed matrix (EN, FR, Khmer).

Usage: backend/.venv/Scripts/python.exe pwa_staging_resolver_eval.py [-v]
It lifts `_resolve_reply` out of pwa_staging_api.py itself, so it measures the
code that is deployed, not a copy. Every case costs two or three gpt-4o-mini
calls, a fraction of a cent. Before shipping (2026-09-10): 52/52, twice.

The OpenAI key is read from the backend's local env files into this process
only. It is never printed, logged or written anywhere.
"""
import ast
import asyncio
import io
import json
import logging
import os
import sys

BACKEND = r'C:\Projects\AIHomeArchitect\backend'


def load_key():
    for name in ('.env.pwa-staging.local', '.env'):
        path = os.path.join(BACKEND, name)
        if not os.path.exists(path):
            continue
        for line in io.open(path, encoding='utf-8', errors='ignore'):
            line = line.strip()
            if line.startswith('OPENAI_API_KEY=') and len(line) > 20:
                os.environ['OPENAI_API_KEY'] = line.split('=', 1)[1].strip().strip('"').strip("'")
                return name
    return None


src_from = load_key()
if not src_from:
    sys.exit('no OPENAI_API_KEY in the backend env files')

from openai import AsyncOpenAI  # noqa: E402

client = AsyncOpenAI()

# the resolver under test, lifted from the backend source (prompt v1)
tree = ast.parse(io.open(os.path.join(BACKEND, 'pwa_staging_api.py'), encoding='utf-8').read())
ns = {"log": logging.getLogger("eval")}
for node in tree.body:
    name = getattr(node, 'name', None) or (
        getattr(node.targets[0], 'id', '') if isinstance(node, ast.Assign) else '')
    if name in ('_OFFER_SYS', '_KIND_SYS', '_PICK_SYS', '_RESOLVE_OFFERS',
                '_RESOLVE_KINDS', '_RESOLVE_LANGS', '_resolve_ask', '_resolve_reply'):
        exec(compile(ast.Module(body=[node], type_ignores=[]), '<x>', 'exec'), ns)

I = 'break the wall on the left and add a living room behind'
RED = ("As your architect, I don't recommend « add a living room behind » — a living "
       "room behind the bedroom would cut the circulation. Would you like to consider "
       "creating a separate living area adjacent to the bedroom instead?")
YEL = ("« add a living room behind » may be difficult to achieve — the space behind is "
       "narrow. Try anyway?")
WARM = 'It reads a little cool for a bedroom. Would you like me to make it warmer?'
TWO = 'Would you prefer a reading nook with an armchair, or a small writing desk?'
V1 = 'Your Warm Modern direction is in — same architecture, warmer materials. What would you like to change?'

CASES = []
for r in ['yes', 'yeah', 'yep', 'sure', 'ok', 'okay', 'go ahead', 'do it', 'proceed',
          'oui', "d'accord", 'vas-y', 'fais-le', 'continue']:
    CASES.append(('A', RED, I, r, 'proposal'))
for r in ['do it anyway', 'proceed anyway', 'fais-le quand même',
          'I still want the living room behind', 'no, do what I asked']:
    CASES.append(('B', RED, I, r, 'original'))
CASES += [('A', RED, I, 'no', 'decline'),
          ('A', RED, I, 'no, make the sofa blue instead', 'none')]
for r in ['yes', 'oui', 'sure']:
    CASES.append(('C', WARM, '', r, 'proposal'))
for r in ['no', 'non', 'not now']:
    CASES.append(('C', WARM, '', r, 'decline'))
for r in ['yes', 'oui', 'ok']:
    CASES.append(('D', TWO, '', r, 'choose'))
for r in ['the desk', 'the second one']:
    CASES.append(('D', TWO, '', r, 'proposal'))
for r in ['yes', 'ok']:
    CASES.append(('Y', YEL, I, r, 'original'))
CASES.append(('Y', YEL, I, 'no', 'decline'))
for r in ['yes', 'make it warmer', 'thanks']:
    CASES.append(('N', V1, '', r, 'none'))
# ── widening: other phrasings, a French assistant, Khmer replies ────────────
for r in ['yes please', 'sounds good', "let's do it", 'perfect, go']:
    CASES.append(('A+', RED, I, r, 'proposal'))
CASES.append(('C+', WARM, '', 'non merci', 'decline'))
RED_FR = ("En tant qu'architecte, je ne recommande pas « ajouter un salon derrière » — "
          "cela couperait la circulation. Voulez-vous plutôt créer un coin salon à côté "
          "de la chambre ?")
I_FR = 'casse le mur de gauche et ajoute un salon derrière'
for r, want in [('oui', 'proposal'), ('vas-y', 'proposal'), ('fais-le quand même', 'original'),
                ('non', 'decline'), ('non, mets plutôt un canapé bleu', 'none')]:
    CASES.append(('FR', RED_FR, I_FR, r, want))
# Khmer: yes (male) / yes (female) / agree / no
for r, want in [('បាទ', 'proposal'), ('ចាស', 'proposal'), ('យល់ព្រម', 'proposal'), ('ទេ', 'decline')]:
    CASES.append(('KM', RED, I, r, want))


async def run(fn, label):
    sem = asyncio.Semaphore(8)

    async def one(case):
        grp, ai, pend, reply, want = case
        async with sem:
            got = await fn(reply, ai, pend)
        return case, got

    results = await asyncio.gather(*(one(c) for c in CASES))
    ok = 0
    lines = []
    for (grp, ai, pend, reply, want), got in results:
        good = got['decision'] == want
        ok += good
        extra = got.get('proposal') or ', '.join(got.get('options') or []) or got.get('reply') or ''
        if not good or grp in ('A', 'C', 'D'):
            lines.append(f"  {'ok ' if good else 'BAD'} {grp} {reply!r:38} want={want:8} got={got['decision']:8} {extra[:70]}")
    print(f"== {label}: {ok}/{len(CASES)}")
    for ln in lines:
        if ln.startswith('  BAD') or '-v' in sys.argv:
            print(ln)
    return ok


async def main():
    await run(lambda m, a, p: ns['_resolve_reply'](m, a, p, client, locale='en'),
              'shipped resolver (pwa_staging_api.py) / gpt-4o-mini')
    await client.close()


asyncio.run(main())
