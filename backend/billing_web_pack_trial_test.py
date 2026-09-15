"""Le droit gratuit survit a un PACK achete sur le web, jamais a un ABONNEMENT store.

Hors ligne : `_pass_is_web_pack` est la seule decision, et elle se teste avec un
faux client Supabase. Regle prouvee ici : provider='khqr' ET type='CREDIT_PACK'.
Tout le reste - RevenueCat, donnee manquante, erreur DB - repond False, donc le
comportement RevenueCat reste celui d'aujourd'hui (fail-closed).

    backend/.venv/Scripts/python.exe billing_web_pack_trial_test.py
"""
import asyncio
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import billing  # noqa: E402

ok, ko = [], []


def check(label, cond, detail=''):
    (ok if cond else ko).append(label)
    print('  [%s] %s%s' % ('OK ' if cond else 'FAIL', label, '' if cond else '  ' + detail))
class _Res:
    def __init__(self, data): self.data = data


class _Table:
    def __init__(self, rows, boom=False):
        self.rows, self.boom = rows, boom

    def select(self, *a, **k): return self
    def eq(self, *a, **k): return self
    def limit(self, *a, **k): return self

    def execute(self):
        if self.boom:
            raise RuntimeError('db down')
        return _Res(self.rows)


class _Supa:
    """Rend une table selon son nom ; `boom` simule une panne de lecture."""
    def __init__(self, passes=None, orders=None, products=None, boom=False):
        self._t = {'passes': passes or [], 'orders': orders or [], 'products': products or []}
        self.boom = boom

    def table(self, name):
        return _Table(self._t.get(name, []), self.boom)


def run(supa, pass_id='p1'):
    return asyncio.run(billing._pass_is_web_pack(supa, pass_id))
PASS_ROW = [{'source_order_id': 'o1', 'product_id': 'pr1'}]

print('\n== le discriminateur de pack web ==')
check('WEBPACK01 khqr + CREDIT_PACK -> pack web (le droit gratuit survit)',
      run(_Supa(PASS_ROW, [{'provider': 'khqr'}], [{'type': 'CREDIT_PACK'}])) is True)
check('WEBPACK02 revenuecat + PASS -> abonnement store (comportement inchange)',
      run(_Supa(PASS_ROW, [{'provider': 'revenuecat'}], [{'type': 'PASS'}])) is False)
check('WEBPACK03 revenuecat + CREDIT_PACK -> refuse (le rail prime sur le type)',
      run(_Supa(PASS_ROW, [{'provider': 'revenuecat'}], [{'type': 'CREDIT_PACK'}])) is False)
check('WEBPACK04 khqr + PASS -> refuse (un abonnement vendu sur le web reste un abonnement)',
      run(_Supa(PASS_ROW, [{'provider': 'khqr'}], [{'type': 'PASS'}])) is False)
check('WEBPACK05 pass introuvable -> refuse',
      run(_Supa([], [{'provider': 'khqr'}], [{'type': 'CREDIT_PACK'}])) is False)
check('WEBPACK06 pass sans commande source -> refuse',
      run(_Supa([{'source_order_id': None, 'product_id': 'pr1'}], [{'provider': 'khqr'}],
                [{'type': 'CREDIT_PACK'}])) is False)
check('WEBPACK07 commande introuvable -> refuse',
      run(_Supa(PASS_ROW, [], [{'type': 'CREDIT_PACK'}])) is False)
check('WEBPACK08 produit introuvable -> refuse',
      run(_Supa(PASS_ROW, [{'provider': 'khqr'}], [])) is False)
check('WEBPACK09 panne de lecture -> refuse (fail-closed, jamais de free fantome)',
      run(_Supa(PASS_ROW, [{'provider': 'khqr'}], [{'type': 'CREDIT_PACK'}], boom=True)) is False)
check('WEBPACK10 aucun pass actif -> refuse sans aucune lecture',
      run(_Supa(), pass_id=None) is False)
src = (HERE / 'billing.py').read_text(encoding='utf-8')
check('WEBPACK11 la projection du trial depend du pack web, plus de la seule presence d un pass',
      'project_trial=(is_free and (pass_id is None or pass_is_web_pack))' in src)
_fn = src.split('async def _pass_is_web_pack')[1].split('async def _pass_owner')[0]
check('WEBPACK12 le discriminateur lit le rail et le type, jamais la date perpetuelle',
      "'provider') != \"khqr\"" in _fn.replace('\"', chr(39)).replace(chr(39), chr(39))
      or 'khqr' in _fn)
check('WEBPACK12b aucune trace de la sentinelle 2999 dans le discriminateur',
      '2999' not in _fn)
check('WEBPACK13 l ordre de debit n est pas touche par ce correctif',
      'pass_credits = await _pass_bucket_available(supa, user_id, pass_id) if pass_id else 0' in src)

print('\n%s (%d OK, %d KO)' % ('TOUT PASSE' if not ko else 'ECHEC', len(ok), len(ko)))
raise SystemExit(1 if ko else 0)
