"""STRUCTURAL_CAPTURE_MODE=off|double — test ASGI (ISOLATION, aucune I/O réelle).

Prouve le kill-switch benché (2026-07-07) :
  off    → 0 capture (V1 gate + recovery V2), token client ignoré, cache jamais
           touché, clause structurelle vide, réponse structural_identity="" +
           structural_capture_disabled=True, ledger token vide.
  double → comportement historique : 2 captures V1, token réutilisé en V2.
  /refine → hérite un token vide en off ; inchangé en double.

I/O mockées (OpenAI images.edit stubée, Supabase fake, auth/quota/intent bypass,
fetch source via serveur local). NE modifie pas main.py.
Run: PYTHONIOENCODING=utf-8 PYTHONPATH=. python structural_capture_mode_test.py
"""
import asyncio, os, sys, io, base64, hashlib, threading, functools, types
import http.server, socket, glob

os.environ["APP_ENV"] = "mobile_mvp_baseline"      # room_description reste ""
os.environ["STRUCT_ID_CACHE"] = "1"                # cache actif → prouve que off le saute
for _k in ["BIMODAL_ENABLED", "SWITCH_BLOCK_COMPACT"]:
    os.environ.setdefault(_k, "1")
import logging
logging.disable(logging.CRITICAL)

from PIL import Image
from httpx import ASGITransport, AsyncClient
import main
import billing

_fails = 0


def check(name, cond, got=""):
    global _fails
    ok = bool(cond); _fails += (not ok)
    print(f"  [{'OK ' if ok else 'FAIL'}] {name}{('  got=' + repr(got)) if (got and not ok) else ''}")


# ── local static server, rooted in a SYSTEM temp dir (never pollutes the repo) ──
import shutil, tempfile
SERVE = tempfile.mkdtemp(prefix="captest_")   # cleaned up in the finally below
os.makedirs(os.path.join(SERVE, "generated"), exist_ok=True)
os.makedirs(os.path.join(SERVE, "src"), exist_ok=True)
# a tiny valid source image
_srcimg = os.path.join(SERVE, "src", "s.jpg")
Image.new("RGB", (1536, 1024), (200, 200, 200)).save(_srcimg, "JPEG")


class _H(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a):
        pass


_p = socket.socket(); _p.bind(("127.0.0.1", 0)); PORT = _p.getsockname()[1]; _p.close()
BASE = f"http://127.0.0.1:{PORT}"
_HTTPD = http.server.ThreadingHTTPServer(
    ("127.0.0.1", PORT), functools.partial(_H, directory=os.path.abspath(SERVE)))
threading.Thread(target=_HTTPD.serve_forever, daemon=True).start()
SRC_URL = f"{BASE}/src/s.jpg"


def _teardown():
    """Guaranteed cleanup — stop the server and delete the temp dir (no repo litter)."""
    try:
        _HTTPD.shutdown(); _HTTPD.server_close()
    except Exception:
        pass
    shutil.rmtree(SERVE, ignore_errors=True)


# ── mocks (aucune I/O réelle) ──
class _Stor:
    def from_(self, b): return self
    def upload(self, path=None, file=None, file_options=None, **k):
        dst = os.path.join(SERVE, "generated", path)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        data = file if isinstance(file, (bytes, bytearray)) else open(file, "rb").read()
        with open(dst, "wb") as _f:   # closed handle → temp dir removable on Windows
            _f.write(data)
        return types.SimpleNamespace(path=path)
    def get_public_url(self, path): return f"{BASE}/generated/{path}"


class _Chain:
    def __getattr__(self, k): return lambda *a, **kw: self
    def execute(self): return types.SimpleNamespace(data=[], count=0)


class _Supa:
    storage = _Stor()
    def from_(self, *a, **k): return _Chain()
    def table(self, *a, **k): return _Chain()
    def rpc(self, *a, **k): return _Chain()
    postgrest = types.SimpleNamespace(session=None)


main.supa = _Supa()


async def _own(*a, **k): return True
main._validate_session_ownership = _own
async def _acc(*a, **k):
    return types.SimpleNamespace(tier="admin", clean_watermark=True, can_generate=True,
        bypass_scope=True, consumes_free_quota=False, consume_promo_on_success=False,
        free_remaining=999, promo_generations_remaining=0, promo_unlimited_active=False)
main.resolve_generation_access = _acc
async def _res(*a, **k): return types.SimpleNamespace(allow=True, wallet_available=9, reason="ok")
billing.reserve_decision = _res
async def _clm(*a, **k): return types.SimpleNamespace(won=True, status="RUNNING", reclaim_count=0, result_ref=None)
main.claim_generation_intent = _clm
if hasattr(main, "_refine_bill_reserve"):
    async def _rr(*a, **k): return True
    main._refine_bill_reserve = _rr

main.app.dependency_overrides[main.get_current_user] = lambda: types.SimpleNamespace(
    user_id="user-123", is_anonymous=False)

# spies
SPY = {"cap": 0, "orient": 0, "cache_get": 0, "cache_put": 0, "clauses": []}
_real_cap = main._capture_structural_text
_FAKE = ("Living room. Sliding glass door as the primary opening on the left wall. "
         "Two windows back wall. Flat ceiling. Two-point perspective. Interior door right.")
async def _cap(_b):
    SPY["cap"] += 1
    return _FAKE
main._capture_structural_text = _cap
if hasattr(main, "_resolve_orientation_consensus"):
    async def _or(_b):
        SPY["orient"] += 1
        return None
    main._resolve_orientation_consensus = _or
_rg = main._struct_id_cache_get
_rp = main._struct_id_cache_put
def _cg(k): SPY["cache_get"] += 1; return _rg(k)
def _cp(k, t): SPY["cache_put"] += 1; return _rp(k, t)
main._struct_id_cache_get = _cg
main._struct_id_cache_put = _cp
_real_compose = main.compose_generation_prompt
def _compose(**kw):
    SPY["clauses"].append(kw.get("structural_identity", None))
    return _real_compose(**kw)
main.compose_generation_prompt = _compose

# extract_from_description spy — proves off never invokes it (so no room_description,
# structural or not, can become the effective identity). `force_nonempty` makes it
# return a FULL structural identity whenever called, so if off used it the token
# would be non-empty — proving off discards the extraction path entirely.
_STRUCT_DESC = ("Living room. Sliding glass door as the primary opening on the left wall. "
                "Two windows on the back wall. Flat ceiling. Two-point perspective. "
                "Interior door on the right.")
EXTRACT = {"calls": 0, "force_nonempty": False}
_real_extract = main.extract_from_description
def _extract_spy(desc):
    EXTRACT["calls"] += 1
    return _real_extract(_STRUCT_DESC if EXTRACT["force_nonempty"] else desc)
main.extract_from_description = _extract_spy

# stub image gen (no paid call) — valid distinct image
_i = {"n": 0}
async def _edit(**kw):
    _i["n"] += 1
    im = Image.new("RGB", (1536, 1024), (_i["n"] * 7 % 255, 100, 150))
    buf = io.BytesIO(); im.save(buf, "PNG")
    return types.SimpleNamespace(data=[types.SimpleNamespace(
        b64_json=base64.b64encode(buf.getvalue()).decode())])
main.openai.images.edit = _edit
if hasattr(main, "_refine_parse"):
    from refine.parser import Change
    async def _rp2(message, client=None):
        return [Change(type="modify", object="rug", detail="", raw=message)]
    main._refine_parse = _rp2


def _reset():
    SPY.update(cap=0, orient=0, cache_get=0, cache_put=0); SPY["clauses"] = []
    EXTRACT["calls"] = 0
    main._STRUCT_ID_CACHE.clear()


async def _gen(mode, **params):
    os.environ["STRUCTURAL_CAPTURE_MODE"] = mode
    _reset()
    # unique session per call → distinct intent_id (avoids the in-memory
    # idempotency replaying a previous same-intent result across modes).
    params["session_id"] = "sess-" + str(params.get("client_request_id", "x"))
    _before = _i["n"]
    async with AsyncClient(transport=ASGITransport(app=main.app), base_url="http://t", timeout=60) as c:
        r = await c.post("/generate", data={k: str(v) for k, v in params.items()})
    return r.json(), _i["n"] - _before   # (response, exact image-call delta)


async def _refine(mode, **params):
    os.environ["STRUCTURAL_CAPTURE_MODE"] = mode
    _reset()
    params["session_id"] = "sess-" + str(params.get("client_request_id", "x"))
    _before = _i["n"]
    async with AsyncClient(transport=ASGITransport(app=main.app), base_url="http://t", timeout=60) as c:
        r = await c.post("/refine", data={k: str(v) for k, v in params.items()})
    return r.json(), _i["n"] - _before


V1 = dict(session_id="s1", prompt="", before_image_url=SRC_URL, style_label="Warm Modern",
          room_type="living room", room_type_id="living_room", atmosphere_id="warm_modern",
          iteration=1, original_image_url=SRC_URL, generation_trigger="button")
OLDTOK = ('{"dominant_opening":"sliding glass door as the apartment\'s primary opening on the '
          'left wall","windows":"two windows","ceiling":"flat"}')


async def main_tests():
    _total_reqs = 0

    print("── OFF ──")
    r, d = await _gen("off", **{**V1, "client_request_id": "o1"}); _total_reqs += 1
    check("off V1: EXACTEMENT 1 appel image (delta==1)", d == 1, d)
    check("off V1 no-token: 0 capture", SPY["cap"] == 0, SPY["cap"])
    check("off V1: extract_from_description JAMAIS appelé", EXTRACT["calls"] == 0, EXTRACT["calls"])
    check("off V1: cache get/put jamais appelé", SPY["cache_get"] == 0 and SPY["cache_put"] == 0,
          (SPY["cache_get"], SPY["cache_put"]))
    check("off V1: réponse structural_identity vide", r.get("structural_identity") == "",
          r.get("structural_identity"))
    check("off V1: structural_capture_disabled=True", r.get("structural_capture_disabled") is True,
          r.get("structural_capture_disabled"))
    check("off V1: clause structurelle vide dans le prompt",
          SPY["clauses"] and all((c or "") == "" for c in SPY["clauses"]), SPY["clauses"])
    check("off V1: ledger token vide", '"structural_identity_token": ""' in r.get("versions", "")
          or '"structural_identity_token":""' in r.get("versions", ""), r.get("versions", "")[:120])

    r2, d2i = await _gen("off", **{**V1, "structural_identity": OLDTOK, "client_request_id": "o2"}); _total_reqs += 1
    check("off V1 + ancien token: delta==1", d2i == 1, d2i)
    check("off V1 + ancien token non vide: token ignoré, 0 capture", SPY["cap"] == 0, SPY["cap"])
    check("off V1 + ancien token: réponse vide (passeport tué)", r2.get("structural_identity") == "",
          r2.get("structural_identity"))

    _, d3i = await _gen("off", **{**V1, "iteration": 2, "structural_identity": OLDTOK,
                                  "generation_trigger": "switch", "client_request_id": "o3"}); _total_reqs += 1
    check("off V2 + token: delta==1", d3i == 1, d3i)
    check("off V2 + token: ignoré, 0 capture", SPY["cap"] == 0, SPY["cap"])

    _, d4i = await _gen("off", **{**V1, "iteration": 2, "generation_trigger": "switch",
                                  "client_request_id": "o4"}); _total_reqs += 1
    check("off V2 sans token: delta==1", d4i == 1, d4i)
    check("off V2 sans token: recovery DÉSACTIVÉE, 0 capture", SPY["cap"] == 0, SPY["cap"])
    check("off V2: orientation consensus jamais appelé", SPY["orient"] == 0, SPY["orient"])
    check("off V2: extract_from_description JAMAIS appelé (pas de recovery)", EXTRACT["calls"] == 0,
          EXTRACT["calls"])

    print("── OFF + room_description STRUCTUREL (extraction forcée non vide) ──")
    EXTRACT["force_nonempty"] = True   # extract() renverrait une identité PLEINE si appelée
    ro5, d5i = await _gen("off", **{**V1, "client_request_id": "o5"}); _total_reqs += 1
    EXTRACT["force_nonempty"] = False
    check("off + desc structurelle: extract jamais appelé", EXTRACT["calls"] == 0, EXTRACT["calls"])
    check("off + desc structurelle: token de sortie VIDE (extraction non exploitée)",
          ro5.get("structural_identity") == "", ro5.get("structural_identity"))
    check("off + desc structurelle: clause structurelle vide",
          all((c or "") == "" for c in SPY["clauses"]), SPY["clauses"])

    print("── MODE INVALIDE → fail-safe off (generate) ──")
    rb, dbi = await _gen("banana", **{**V1, "structural_identity": OLDTOK, "client_request_id": "ob"}); _total_reqs += 1
    check("invalid mode /generate: delta==1", dbi == 1, dbi)
    check("invalid mode /generate: 0 capture (fail-safe off)", SPY["cap"] == 0, SPY["cap"])
    check("invalid mode /generate: disabled=True + token vide",
          rb.get("structural_capture_disabled") is True and rb.get("structural_identity") == "",
          (rb.get("structural_capture_disabled"), rb.get("structural_identity")))

    print("── DOUBLE ──")
    d1, dd1 = await _gen("double", **{**V1, "client_request_id": "d1"}); _total_reqs += 1
    check("double V1: delta==1", dd1 == 1, dd1)
    check("double V1: exactement 2 captures", SPY["cap"] == 2, SPY["cap"])
    check("double V1: extract appelé (≥1) — chemin structurel actif", EXTRACT["calls"] >= 1,
          EXTRACT["calls"])
    check("double V1: token non vide retourné", bool(d1.get("structural_identity")),
          d1.get("structural_identity"))
    check("double V1: clause structurelle NON vide", any((c or "") != "" for c in SPY["clauses"]),
          SPY["clauses"])
    tok = d1.get("structural_identity")

    d2, dd2 = await _gen("double", **{**V1, "iteration": 2, "structural_identity": tok,
                                      "generation_trigger": "switch", "client_request_id": "d2"}); _total_reqs += 1
    check("double V2: delta==1", dd2 == 1, dd2)
    check("double V2 + token: réutilisé, 0 capture", SPY["cap"] == 0, SPY["cap"])
    check("double V2: token conservé (réutilisé)", bool(d2.get("structural_identity")),
          d2.get("structural_identity"))

    print("── /refine ──")
    ro, dro = await _refine("off", session_id="s1", message="ajoute un tapis", before_image_url=SRC_URL,
                            room_type="living room", confirm="true", structural_identity=OLDTOK,
                            style_label="Japandi Calm", iteration=3, client_request_id="r1"); _total_reqs += 1
    check("refine off: delta==1", dro == 1, dro)
    check("refine off: structural_capture_disabled=True", ro.get("structural_capture_disabled") is True,
          ro.get("structural_capture_disabled"))
    check("refine off: token hérité vidé", ro.get("structural_identity") == "",
          ro.get("structural_identity"))

    rbf, drbf = await _refine("banana", session_id="s1", message="ajoute un tapis", before_image_url=SRC_URL,
                              room_type="living room", confirm="true", structural_identity=OLDTOK,
                              style_label="Japandi Calm", iteration=3, client_request_id="rb"); _total_reqs += 1
    check("invalid mode /refine: fail-safe off (disabled=True + token vidé)",
          rbf.get("structural_capture_disabled") is True and rbf.get("structural_identity") == "",
          (rbf.get("structural_capture_disabled"), rbf.get("structural_identity")))

    rd, drd = await _refine("double", session_id="s1", message="ajoute un tapis", before_image_url=SRC_URL,
                            room_type="living room", confirm="true", structural_identity=OLDTOK,
                            style_label="Japandi Calm", iteration=3, client_request_id="r2"); _total_reqs += 1
    check("refine double: delta==1", drd == 1, drd)
    check("refine double: token hérité verbatim", rd.get("structural_identity") == OLDTOK,
          rd.get("structural_identity"))

    print("── invariant : total appels image == nombre de requêtes ──")
    check(f"total images == {_total_reqs} requêtes (exact, pas >=)", _i["n"] == _total_reqs,
          (_i["n"], _total_reqs))

    print(f"\n{'ÉCHECS: ' + str(_fails) if _fails else 'TOUS LES TESTS PASSENT'}")
    sys.exit(1 if _fails else 0)


if __name__ == "__main__":
    try:
        asyncio.run(main_tests())   # calls sys.exit → SystemExit propagates
    finally:
        _teardown()                 # server stopped + temp dir removed, always
