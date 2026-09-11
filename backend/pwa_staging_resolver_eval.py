"""Measure the SHIPPED PWA reply resolver — and, since 2026-09-11, the
instruction an accepted proposal is rendered from.

Usage: backend/.venv/Scripts/python.exe pwa_staging_resolver_eval.py [-v]

Everything measured is lifted out of pwa_staging_api.py itself, so it is the
code that is deployed, not a copy. Four measurements:

  1. DECISION — what a short reply agrees to (proposal / original / choose /
     decline / none). The 52 historical cases, unchanged and still asked in
     English, then the cases the RED-proposal fix added: the warning as the PWA
     now SHOWS it (the canonical template, its seams closed, in French and in
     Khmer), the phone's exact reading-nook sequence, a French YELLOW, a French
     multiple choice.
  2. EXECUTION — for every case resolved to a proposal, what the engine would
     be handed: English, imperative, no question mark, no offer wording, the
     proposal's subject kept, a place for a zone or a piece of furniture — and
     a display text in the screen's language.
  3. ENGINE READING — each execution instruction read by the canonical refine
     parser and the frozen normalizer (read-only imports). No change may land
     on the small-object placement "on the coffee table or main visible
     surface": that is how the phone's accepted proposal was lost.
  4. TEMPLATE SEAMS — the canonical advisor's template really produces "..",
     ".?" and "to Consider", and `_tidy_advisory` closes all three.

Every case costs a few gpt-4o-mini calls, a fraction of a cent. The OpenAI key
is read from the backend's local env files into this process only; it is never
printed, logged or written anywhere.

History: 52/52 twice before the resolver shipped (2026-09-10).
"""
import __future__
import ast
import asyncio
import io
import logging
import os
import re
import sys
import time

BACKEND = r'C:\Projects\AIHomeArchitect\backend'
sys.path.insert(0, BACKEND)
VERBOSE = '-v' in sys.argv


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

from prompt_engine.meta_intent import _detect_language  # noqa: E402
from refine.advisor import (AdviceResult, ChangeAdvice, Verdict,  # noqa: E402
                            build_advisory_message)
# READ-ONLY: the frozen refine engine is imported to be measured, never edited.
from refine.normalizer import _ADD_DEFAULT, normalize  # noqa: E402
from refine.parser import Change, parse_changes  # noqa: E402

client = AsyncOpenAI()

# ── the code under test, lifted from the backend source ─────────────────────
LIFT = ('_OFFER_SYS', '_KIND_SYS', '_PICK_SYS', '_RESOLVE_OFFERS', '_RESOLVE_KINDS',
        '_RESOLVE_LANGS', '_KHMER', '_READ_EN_SYS', '_read_in_english',
        '_resolve_ask', '_resolve_reply',
        '_EXEC_SYS', '_EXEC_HEDGE', '_EXEC_NOT_ENGLISH', '_EXEC_OPENERS', '_one_line',
        '_exec_violation', '_engine_reading', '_proposal_execution',
        '_tidy_advisory', '_L10N_LANGS', '_L10N_SYS', '_QUOTED', '_L10N_CACHE',
        '_localize_text')
tree = ast.parse(io.open(os.path.join(BACKEND, 'pwa_staging_api.py'), encoding='utf-8').read())
ns = {"log": logging.getLogger("eval"), "re": re}
for node in tree.body:
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
        name = node.name
    elif isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name):
        name = node.targets[0].id
    elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
        name = node.target.id
    else:
        continue
    if name in LIFT:
        exec(compile(ast.Module(body=[node], type_ignores=[]), '<pwa_staging_api>', 'exec',
                     flags=__future__.annotations.compiler_flag), ns)
missing = [n for n in LIFT if n not in ns]
if missing:
    sys.exit(f'not found in pwa_staging_api.py: {missing}')


def advisory(*items):
    """The canonical advisor's OWN template, fed structured advice."""
    return build_advisory_message(AdviceResult(advices=[
        ChangeAdvice(change=Change(type=t, object=obj, detail='', raw=raw),
                     verdict=verdict, reason=reason, alternative=alt)
        for verdict, t, raw, obj, reason, alt in items]))


# ── the historical matrix (52) — unchanged ──────────────────────────────────
I = 'break the wall on the left and add a living room behind'
RED = ("As your architect, I don't recommend « add a living room behind » — a living "
       "room behind the bedroom would cut the circulation. Would you like to consider "
       "creating a separate living area adjacent to the bedroom instead?")
YEL = ("« add a living room behind » may be difficult to achieve — the space behind is "
       "narrow. Try anyway?")
WARM = 'It reads a little cool for a bedroom. Would you like me to make it warmer?'
TWO = 'Would you prefer a reading nook with an armchair, or a small writing desk?'
V1 = 'Your Warm Modern direction is in — same architecture, warmer materials. What would you like to change?'
RED_FR = ("En tant qu'architecte, je ne recommande pas « ajouter un salon derrière » — "
          "cela couperait la circulation. Voulez-vous plutôt créer un coin salon à côté "
          "de la chambre ?")
I_FR = 'casse le mur de gauche et ajoute un salon derrière'

# What an execution instruction must keep: (subject pattern, needs a place).
LIVING = (r'\b(living|sitting|lounge|seating)\b', True)
WARMX = (r'\bwarm', False)
DESK = (r'\bdesk\b', True)
NOOK = (r'\breading\b', True)

# (group, Ayden's message, pending original, reply, wanted decision, locale, expect)
CASES = []
for r in ['yes', 'yeah', 'yep', 'sure', 'ok', 'okay', 'go ahead', 'do it', 'proceed',
          'oui', "d'accord", 'vas-y', 'fais-le', 'continue']:
    CASES.append(('A', RED, I, r, 'proposal', 'en', LIVING))
for r in ['do it anyway', 'proceed anyway', 'fais-le quand même',
          'I still want the living room behind', 'no, do what I asked']:
    CASES.append(('B', RED, I, r, 'original', 'en', None))
CASES += [('A', RED, I, 'no', 'decline', 'en', None),
          ('A', RED, I, 'no, make the sofa blue instead', 'none', 'en', None)]
for r in ['yes', 'oui', 'sure']:
    CASES.append(('C', WARM, '', r, 'proposal', 'en', WARMX))
for r in ['no', 'non', 'not now']:
    CASES.append(('C', WARM, '', r, 'decline', 'en', None))
for r in ['yes', 'oui', 'ok']:
    CASES.append(('D', TWO, '', r, 'choose', 'en', None))
for r in ['the desk', 'the second one']:
    CASES.append(('D', TWO, '', r, 'proposal', 'en', DESK))
for r in ['yes', 'ok']:
    CASES.append(('Y', YEL, I, r, 'original', 'en', None))
CASES.append(('Y', YEL, I, 'no', 'decline', 'en', None))
for r in ['yes', 'make it warmer', 'thanks']:
    CASES.append(('N', V1, '', r, 'none', 'en', None))
for r in ['yes please', 'sounds good', "let's do it", 'perfect, go']:
    CASES.append(('A+', RED, I, r, 'proposal', 'en', LIVING))
CASES.append(('C+', WARM, '', 'non merci', 'decline', 'en', None))
for r, want in [('oui', 'proposal'), ('vas-y', 'proposal'), ('fais-le quand même', 'original'),
                ('non', 'decline'), ('non, mets plutôt un canapé bleu', 'none')]:
    CASES.append(('FR', RED_FR, I_FR, r, want, 'en', LIVING if want == 'proposal' else None))
for r, want in [('បាទ', 'proposal'), ('ចាស', 'proposal'), ('យល់ព្រម', 'proposal'), ('ទេ', 'decline')]:
    CASES.append(('KM', RED, I, r, want, 'en', LIVING if want == 'proposal' else None))
HISTORICAL = len(CASES)
assert HISTORICAL == 52, HISTORICAL

# ── added by the RED-proposal fix: the warning as the PWA SHOWS it now ──────
LIVE_RAW = advisory(
    (Verdict.RED, 'structure', 'break the wall on the left', 'wall',
     'the left wall is likely load-bearing, and removing it would require major '
     'structural changes.', ''),
    (Verdict.RED, 'add', 'add a living room behind', 'living room',
     'there is no space behind the bedroom to extend into.',
     'Consider creating a cozy reading nook in the master bedroom instead.'))
YEL_RAW = advisory(
    (Verdict.YELLOW, 'structure', 'remove the partition', 'partition',
     "I can't tell exactly which partition you mean — which side or which one "
     "should I change?", ''))
TWO_FR = ("Préférez-vous un coin lecture avec un fauteuil, ou un petit bureau pour "
          "écrire ?")
I_YEL = 'remove the partition'

PLACE = re.compile(r'\b(corner|wall|window|left|right|side|beside|next to|near|against|'
                   r'along|by the|end of|foot of|in front of|behind|opposite|centre|'
                   r'center|middle|between|alcove)\b', re.I)


async def build_added():
    tidy = ns['_tidy_advisory']
    loc = ns['_localize_text']
    live = tidy(LIVE_RAW)
    yel = tidy(YEL_RAW)
    live_fr, live_km, yel_fr = await asyncio.gather(
        loc(client, live, 'fr'), loc(client, live, 'km'), loc(client, yel, 'fr'))
    added = []
    for r, want in [('yes', 'proposal'), ('do it anyway', 'original'), ('no', 'decline')]:
        added.append(('LIVE', live, I, r, want, 'en', NOOK if want == 'proposal' else None))
    for r, want in [('oui', 'proposal'), ('vas-y', 'proposal'),
                    ('fais-le quand même', 'original'), ('non', 'decline')]:
        added.append(('LIVE-FR', live_fr, I, r, want, 'fr', NOOK if want == 'proposal' else None))
    for r, want in [('បាទ', 'proposal'), ('ចាស', 'proposal'), ('ទេ', 'decline')]:
        added.append(('LIVE-KM', live_km, I, r, want, 'km', NOOK if want == 'proposal' else None))
    added.append(('YEL', yel, I_YEL, 'yes', 'original', 'en', None))
    for r, want in [('oui', 'original'), ('essaie quand même', 'original'), ('non', 'decline')]:
        added.append(('YEL-FR', yel_fr, I_YEL, r, want, 'fr', None))
    for r, want in [('oui', 'choose'), ('le bureau', 'proposal')]:
        added.append(('TWO-FR', TWO_FR, '', r, want, 'fr', DESK if want == 'proposal' else None))
    texts = {'LIVE (en, tidied)': live, 'LIVE (fr)': live_fr, 'LIVE (km)': live_km,
             'YELLOW (en, tidied)': yel, 'YELLOW (fr)': yel_fr}
    return added, texts


def execution_problems(ex, expect, locale):
    if not ex:
        return ['no instruction passed the checks (fail-closed)']
    instr, display = ex['instruction'], ex['display']
    probs = []
    broken = ns['_exec_violation'](instr)
    if broken:
        probs.append(broken)
    subject, needs_place = expect
    if not re.search(subject, instr, re.I):
        probs.append('subject lost')
    if needs_place and not PLACE.search(instr):
        probs.append('no place')
    if '?' in display or '？' in display:
        probs.append('display is a question')
    if _detect_language(display) != locale:
        probs.append(f'display not in {locale}')
    return probs


async def engine_reading(instr):
    """The canonical parser, then the frozen normalizer — read, never changed."""
    changes = await parse_changes(instr, client=client)
    plan = [(c.type, c.object, normalize(c)) for c in changes]
    if not plan:
        return plan, ['the engine read no change']
    small = [p for p in plan if _ADD_DEFAULT in p[2]]
    return plan, ([f'small-object placement on {small[0][1]!r}'] if small else [])


async def main():
    t0 = time.time()
    added, texts = await build_added()
    cases = CASES + added
    sem = asyncio.Semaphore(8)

    async def one(case):
        grp, ai, pend, reply, want, locale, expect = case
        async with sem:
            got = await ns['_resolve_reply'](reply, ai, pend, client, locale=locale)
            ex = plan = None
            probs, engine = [], []
            if got['decision'] == 'proposal' and expect:
                ex = await ns['_proposal_execution'](got['proposal'], ai, pend, 'Bedroom',
                                                     client, locale=locale)
                probs = execution_problems(ex, expect, locale)
                if ex:
                    plan, engine = await engine_reading(ex['instruction'])
                else:
                    engine = ['nothing to read']
        return case, got, ex, probs, plan, engine

    results = await asyncio.gather(*(one(c) for c in cases))

    hist_ok = sum(1 for (c, got, *_r) in results[:HISTORICAL] if got['decision'] == c[4])
    add_ok = sum(1 for (c, got, *_r) in results[HISTORICAL:] if got['decision'] == c[4])
    execs = [r for r in results if r[2] is not None or (r[1]['decision'] == 'proposal' and r[0][6])]
    exec_ok = sum(1 for r in execs if not r[3])
    engine_ok = sum(1 for r in execs if not r[5])

    raw_has = ['..' in LIVE_RAW.replace('...', ''), '.?' in LIVE_RAW, 'to Consider' in LIVE_RAW]
    tidy = ns['_tidy_advisory'](LIVE_RAW)
    closed = ['..' not in tidy.replace('...', ''), '.?' not in tidy, 'to Consider' not in tidy]
    seams_ok = sum(1 for had, gone in zip(raw_has, closed) if had and gone)

    print(f"== DECISION  historical {hist_ok}/{HISTORICAL}  ·  added {add_ok}/{len(added)}"
          f"  ·  total {hist_ok + add_ok}/{len(cases)}")
    print(f"== EXECUTION {exec_ok}/{len(execs)}  (English imperative, no '?', no offer "
          f"wording, subject kept, place for zones/furniture, display in the screen's language)")
    print(f"== ENGINE READING {engine_ok}/{len(execs)}  (refine.parser + frozen normalizer: "
          f"no small-object placement)")
    print(f"== TEMPLATE SEAMS {seams_ok}/3  (the template produced them: {raw_has}; "
          f"closed: {closed})")

    for (grp, ai, pend, reply, want, locale, expect), got, ex, probs, plan, engine in results:
        good = got['decision'] == want and not probs and not engine
        live = grp.startswith('LIVE') and got['decision'] == 'proposal'
        if good and not live and not VERBOSE:
            continue
        mark = 'ok ' if good else 'BAD'
        print(f"  {mark} {grp:7} {reply!r:32} want={want:8} got={got['decision']:8}"
              + (f"  problems={probs + engine}" if probs or engine else ''))
        if ex:
            print(f"        display    ({locale}): {ex['display']}")
            print(f"        execution  (en): {ex['instruction']}")
        if plan:
            for t, obj, norm in plan:
                print(f"        engine     {t}/{obj}: {norm}")
    if VERBOSE:
        for k, v in texts.items():
            print(f"\n-- {k}:\n{v}")
    print(f"\n({len(cases)} cases, {time.time() - t0:.0f}s)")
    await client.close()
    total_ok = (hist_ok == HISTORICAL and add_ok == len(added) and exec_ok == len(execs)
                and engine_ok == len(execs) and seams_ok == 3)
    return 0 if total_ok else 1


sys.exit(asyncio.run(main()))
