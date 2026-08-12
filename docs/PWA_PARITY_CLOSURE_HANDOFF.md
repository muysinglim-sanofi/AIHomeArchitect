# PWA ↔ mobile parity closure — session handoff (2026-08-11)

Working state for whoever continues. Everything below is UNCOMMITTED working tree.

## Where the code lives

| what | where |
|---|---|
| adapter (backend) | `c:/Projects/AIHomeArchitect/backend/pwa_staging_api.py` |
| adapter tests | `backend/pwa_staging_adapter_test.py` — **278 assertions** |
| PWA app (Flutter) | worktree `c:/Projects/ayden-pwa-web`, branch `pwa-web` |
| new client guards | `test/features/pwa/pwa_lifecycle_parity_test.dart` (14) + `pwa_chat_gate_test.dart` (13) |
| new migration | `supabase/staging/pwa/0005_pwa_lineage_ancestry.sql` — **APPLIED** |
| smoke inspector | `backend/_pwa_smoke_state.py` (`PYTHONPATH=. python _pwa_smoke_state.py [project_id]`) |

## Services

* backend `127.0.0.1:8000` — `python backend/run_pwa_staging.py`, single process, **no --reload**.
  Logs append to `backend/logs/backend.log` (NEVER `>`, always `>>`). File is ~2 GB; use `tail -n`.
* PWA `127.0.0.1:8104` — serves `c:/Projects/ayden-pwa-web/build/web`.
  Rebuild with:
  `flutter build web --release -t lib/main_pwa.dart --dart-define-from-file=.env.pwa-staging.json`
  **Never a bare `flutter build web`** — that builds the MOBILE entrypoint over the PWA bundle.
* `8103` is off. Never read `backend/.env`.

## The five gaps — ALL CLOSED

1. **Customized-switch history** — `_history_from()` rebuilds the chat history from the
   BRANCH's `prompt_text` rows and passes it to the composer, which does the filtering
   (`_filter_history_to_customizations`) exactly where mobile does. Guards `HIST01-06`.
2. **PROCESSING** — new `GET /pwa/staging/generation/{key}` (pure read). The client attaches
   and polls (`_awaitHeldGeneration`) instead of showing a failure. Guards `PROC01-07`,
   `PROC-C01-04`.
3. **Resolved room** — `_effective_room()` + `pwa_visions.room_label` +
   `pwa_projects.resolved_room_type`; promoted to the project ONLY when delegated. The client
   adopts it only when nothing was chosen. Guards `ROOM01-09`, `ROOM-C01-03`, `ATMO-C01-02`.
4. **/refine/verify** — new `POST /pwa/staging/refine/verify` calling the same `refine.verify`
   module; fired AFTER the image renders, silent unless `incomplete`. Guards `VERIFY01-09`,
   `VER-C01-05`.
5. **Branch ancestry** — `_ancestry()` / `_customized_from()` read the SOURCE record's stored
   `lineage_customized` (written cumulatively), never a project-wide scan. Guards `BRANCH01-09`.

## Effective runtime (read from the LIVE process, `GET /pwa/staging/engine`)

composer `prompt_engine.composer_v2.compose_generation_prompt` · COMPOSER_VERSION v2 ·
APP_ENV `mobile_mvp_baseline` · profile MOBILE_MVP_BASELINE · model `gpt-image-2` ·
effective quality `low` · input_fidelity NOT sent · all 14 `run.sh` flags = 1.
Mobile's own lock proven at `main.py:4494-4496`.

## Smoke project

`a54325ed-953b-4a25-be8d-7ec013d08205` ("Living Room Concept"), user
`0b1c7e78-89a0-43e2-85ba-2bcb251b0daf`. Source photo
`backend/benchmarks/source/before_new_living_1.png` (empty living room, balcony glazing).

| V | action | parent | atmosphere | customized | note |
|---|---|---|---|---|---|
| 1 | initial | — | warm_modern | false | Ayden Decide → living_room (high); Signature → Warm Modern; STAGE applied |
| 2 | switch | V1 | japandi_calm | false | REBOOT_FRESH, source = V1, history 0 |
| 3 | refine | V2 | japandi_calm | **true** | "make the sofa white"; 1st attempt lost to a transient Storage 400, retried on the SAME claim |
| 4 | switch | V3 | soft_luxury | true | **REBOOT_CUSTOMIZED, source = V3, history 1** — the white sofa survived |
| 5 | refine | V4 | soft_luxury | true | structural: "open the wall on the right and add a kitchen with an island" (changes=2 add,structure) |

## Driving the browser (this is the part that wastes time if rediscovered)

Chrome CDP on `127.0.0.1:9222`. Driver + helpers in this session's scratchpad
(`cdp.mjs`, `shotf.sh`).

**The trap**: the tab reports `document.visibilityState === "hidden"` even when focused
(`hasFocus:true`). Flutter Web drives every frame from `requestAnimationFrame`, which is
throttled there, so *the route changes and the canvas does not repaint*. A screenshot then
shows a stale scene and looks exactly like a broken app. Two of this session's "bugs" were
only that.

**The fix that works**: force a RESIZE — it relayouts and repaints outside rAF.
```bash
node cdp.mjs metrics 1400 1099; sleep 0.5; node cdp.mjs metrics 1400 1100; sleep 0.8
node cdp.mjs shot out.png            # ← `shotf.sh` does exactly this
```
Always re-measure click coordinates from the frame you JUST captured.
Screenshot px → CSS px: **× 0.7** (viewport 1400×1100, dpr 1.5).

Real file upload: `node cdp.mjs upload <x> <y> <abs-path>` (CDP file-chooser interception).

## Known limitations

* **Transient Storage 400** on the generated-image upload (seen once, on V3). Proven NOT
  deterministic: the identical request shape/token/size/mime/path returns 200 when replayed
  from the page. The adapter now logs the response BODY on failure so a recurrence is
  diagnosable. Deliberately NOT retried: mobile retries transport errors only, and diverging
  would break the very parity this work is about.
* ~~A refine recovered through the RETRY path skips the verify second call.~~ FIXED — the
  retry path now fires it too. (Mobile has no counterpart: it deliberately never replays a
  refine, so a failed refine there stays lost. Recovering it and then withholding the
  "still missing" report would have made this path weaker than the direct one.)
* `pwa_visions.atmosphere_label` is written by the CLIENT as the atmosphere ID (pre-existing).
  Never read back — the project-level `selected_atmosphere_label` is what the UI uses.

## ✅ CLOSED — the conversational turn (found AND fixed 2026-08-11)

**Was: a question cost the user an image render. Now: it costs a sentence.**

Mobile has TWO steps for typed text (`chat_screen.dart:_send`):

```
typed text → POST /chat  →  { ai_message, should_generate, suggestions }
                          →  show the reply; generate ONLY if should_generate
```

The PWA HAD one: `sendUserText()` called `applyRefine()` directly, i.e.
`POST /pwa/staging/generate` with `action_type=refine`. There was no `/chat` turn.

The adapter's fallback (`_refine_advisory`: *no change parsed → answer, 0 render*) was meant
to cover this, but it almost never fires. Probed directly against the canonical
`refine.parser.parse_changes` (gpt-4o-mini, temperature 0) on 2026-08-11:

| phrase | parsed |
|---|---|
| `"what do you think?"` | **1 change** (`modify`) |
| `"what do you think of this space?"` | **1 change** (`modify`) |
| `"how does this room feel to you?"` | **1 change** (`modify`) |

`"What do you think?"` is a chip the app itself offers. Confirmed live in the smoke: it
produced `canonical refine — changes=1 types=modify` and a full paid render (vision 6 of the
smoke project).

**Why the earlier audit thought this was closed**: the mechanism (`status:"answer"`) exists
and is tested — with a *stubbed* parser that returns `[]`. Nothing proved the real parser
ever returns `[]` for a real question. It does not.

**Fix (SHIPPED)**: `POST /pwa/staging/chat` **calls `main.chat` itself** — the same async
function the mobile route calls, with `current_user` passed explicitly so FastAPI's
production auth dependency never runs. None of the decision chain (Wave 4.11d dominance,
meta-intent, quota gate, `classify_intent`, the PR3 opinion downgrade, confirmation,
ambiguity, MIXED) is reproduced in the adapter. `PwaController.sendUserText` calls it and
only renders when `should_generate` is true; chips go through the same method, so
"What do you think?" is correct without being special-cased. Fails CLOSED everywhere: an
unreachable backend, a malformed field and an exception all answer `should_generate=false`.

Guards: `CHAT01-10` + advisory/confirm/RED in `test/features/pwa/pwa_chat_gate_test.dart`,
`CHAT-B01-11` in the adapter suite, `PARITY12/12b/12c` (no local heuristic may decide a
render; the UI may not reach the paid path except `confirm: true`).

## Still to do

* Advisory / no-render case + "Continue anyway".
* Branch-from-V1 (new branch off a pre-customisation vision) in the REAL app.
* F5 + Home reopen + read-only navigation (0 OpenAI calls, no DB mutation).
* Re-run the full gate and rebuild `build/web` after the last edits.

## What the canonical brain says (measured 2026-08-11, `classify_intent`)

The gate is the canonical classifier, so its verdicts are the product's verdicts on BOTH
platforms. Two are worth knowing before anyone reports a "bug":

| line | iteration 1 | iteration 2+ |
|---|---|---|
| `What do you think?` | generate | **conversation** — answered, free |
| `make it warmer` | generate | generate |
| `add a floor lamp` | generate | generate (local_edit) |
| `open the wall … kitchen with an island` | generate | generate (structural_change) |
| **`make the sofa white`** | generate | **conversation** — answered, NOT rendered |

`make the sofa white` not generating at V2+ is CANONICAL behaviour, identical on mobile
(`classify_intent` is the shared frozen classifier — verified at iterations 2 and 7). It is
not a PWA divergence and must not be "fixed" locally: doing so would re-introduce exactly the
kind of local brain this work removed. If the product wants it to generate, the change
belongs in `prompt_engine/intent_classifier.py` and changes mobile too.
