# AYDEN STUDIO PWA — REFINE RED-PROPOSAL FIX — 2026-09-11

Scope: PREPROD / STAGING only. Production, Billing semantics, ABA PayWay and the
native iOS sources (`frontend/`) were **not modified**. The frozen refine engine
(`backend/refine/**` — parser, normalizer, advisor, verify, engine, executor) was
**not modified**: it is imported read-only, to be measured and to check
instructions against.

| | |
|---|---|
| Backend | `ayden-api-staging` (Fly, sin) — image `deployment-01M27CBPSETMPGF2ZPZA2K6YHW`, boot clean |
| Client | `preprod.aydenstudio.com` — see §7 for the live hash |
| Flutter | `flutter analyze`: no issues · `flutter test`: **1586 passed, 0 failed** |
| Backend offline suites | adapter **301/0** (was 278) · billing 81/0 · billing contract OK · payments 240/0 · lifecycle DB 13/0 · ordinal 17/17 · orientation OK |
| Resolver bench | **52/52** historical, **16/16** added, execution **34/34**, engine reading **34/34** — two consecutive runs on the final code |

---

## 1. The defect, as the phone saw it (2026-09-10)

RED advisory proposing an alternative → the person types "yes" → `/chat` resolves
`resolution=proposal` → one Space charged, one Vision persisted — and the image is
**pixel-identical** to its parent, verify `incomplete`.

The executed plan (from the `/generate` response of V7 `5f1024c2`):

```
changes = [{"type": "add", "object": "coin lecture",
            "raw": "Créer un coin lecture confortable dans la chambre principale ?",
            "normalized": "… ? on the coffee table or main visible surface."}]
```

## 2. Root cause (confirmed)

Two links, both proven:

1. **Adapter** (`pwa_staging_api.py`): the offer reader (`_OFFER_SYS`) returns the
   proposal "in the message's language, using the message's own words" — Ayden's
   French QUESTION — and `pwa_chat` handed that string to the engine as
   `override_instruction`. The display text and the execution instruction were
   one string.
2. **Engine reading** (frozen, read-only): the canonical parser reads such a
   sentence as an `add` with no place the normalizer recognises, and the
   normalizer gives every such `add` the small-object placement
   `_ADD_DEFAULT = "on the coffee table or main visible surface"`. A reading nook
   "on the coffee table" is not drawn.

Bench proof that link 2 is general, not a one-off (`pwa_staging_resolver_eval.py`,
first runs of the new layer, before the engine-reading check): even correct
English imperatives lost their zone when written as a list — "Create a separate
living area adjacent to the bedroom **by placing** a sofa, a coffee table and a
floor lamp…" is split into four `add`s; "adjacent to the bedroom" is not a place
the normalizer recognises, so the living area itself got the coffee-table
template. **7/33 and 13/34** instructions on two runs. A zone "with a comfortable
armchair" that passed a check once was split by the next reading (armchair on the
coffee table): the render re-parses, so the instruction must read the same way
every time.

## 3. The fix — backend, two representations

`pwa_chat`, on `resolution == "proposal"` (Ayden's one change, or an option the
person picked), calls `_proposal_execution(...)`:

| | DISPLAY TEXT | EXECUTION INSTRUCTION |
|---|---|---|
| reader | the person | the refine engine |
| language | the UI locale (FR / KM / EN) | canonical English |
| form | short title, no `?` | ONE change, ONE clause, imperative, place inside the photo |
| field | `override_display` | `override_instruction` |
| stored as | vision `action_summary` (title) | vision `prompt_text` |

The rewrite (gpt-4o-mini, temperature 0, JSON) reads the offer, Ayden's message,
the person's original request (for WHERE) and the room. It is **checked before
anything is authorised**:

* form — `_exec_violation`: no `?`, no offer wording (would you, consider, perhaps,
  maybe, should we, try, instead…), not French/Khmer, an action verb first;
* engine — `_engine_reading`: the canonical `refine.parser` + frozen
  `refine.normalizer` read it; refused if any change lands on `_ADD_DEFAULT`, or if
  it reads as more than one change.

A refused rewrite is asked once more with the broken rule; then it **fails
closed**: `should_generate=False`, no override, nothing spent. The offer as Ayden
worded it never reaches the engine. No structured form exists on this path (the
canonical chat's offers are prose; the advisor's `alternative` is prose too and
never reaches `/chat`), so the rewrite reads the offer semantically — no phrase
lists, no string surgery.

**Three inputs stay distinct:**

* A — ORIGINAL request ("do it anyway"): the client's verbatim copy
  (`pending_instruction`), untouched, no display text.
* B — PROPOSAL ("yes" after RED): execution + display, as above.
* C — DIRECT instruction: travels as typed.

**Khmer.** The offer reader misread a Khmer warning: gpt-4o-mini took the request
Ayden advised AGAINST as a second "option" (0/10, 2/10, 9/10 on three
translations of the same warning; never in English or French). A message written
in Khmer script is now read through English for the offer only
(`_read_in_english`); the reply is still judged in its own words and everything
shown stays Khmer. English and French are read exactly as before.

## 4. Non-blocking fixes (same pass, outside the engine)

* **Warnings in the UI language.** `/generate` advisory: the canonical template is
  called unchanged, its output is tidied then translated when `ui_locale` is FR/KM
  (`_localize_text`; not `localize_reply`, which keeps any text containing a
  French word — and an advisory quotes the person's own words). The verify report
  ("Still missing") likewise: `PwaVerifyRequest.ui_locale`, sent by the client.
* **Punctuation.** `_tidy_advisory` closes the template's seams: `changes..` →
  `changes.`, `instead.?` → `instead?`, `to Consider` → `to consider`; an ellipsis
  and clean questions are left alone. The bench proves the canonical template
  really produces all three.
* **390 px buttons.** `_V7CardActions`: side by side only when both labels fit on
  one line at the size the buttons draw them; otherwise stacked, primary first.
  The old fixed 1:2 row left the secondary pill ~36 px of text after the theme's
  32 px padding ("Annul/er", "Modif/ier la/dema/nde").

## 5. Client (minimal)

`PwaChatTurn.overrideDisplay`; `applyRefine(instruction, display:)` — the engine
gets the instruction, the chat line and the vision title get the display text;
`display_instruction` travels to `/generate` (stored as `action_summary`) and in
the pending record (a render landed after a reload keeps its title);
`verify(uiLocale:)`. An ordinary refine request and pending record are
byte-identical to before (the new key is only written when non-empty).

## 6. Tests

* Backend adapter (offline): PROP01–12, TIDY01–02, L10N01–04, READ01–03, ADV01–02.
* Flutter: REFINE-09 (English execution to the engine, display in the title and
  reveal, the engine's English never in the conversation), REFINE-10 (direct
  instruction and "do it anyway" unchanged), REFINE-11 (pending/request/turn
  round-trips), CARD-01/02/03 (390 px FR RED and YELLOW labels whole and on one
  line; wide screen keeps the row).
* Bench (`backend/pwa_staging_resolver_eval.py`, real gpt-4o-mini): decision on the
  52 historical cases unchanged; 16 added — the warning as the PWA now SHOWS it
  (canonical template, tidied, EN/FR/KM), RED + yes / oui / vas-y / បាទ / ចាស,
  YELLOW + yes / oui, "do it anyway" / "fais-le quand même", multiple choice +
  oui, rejected + no / non / ទេ; execution checks on every proposal; the engine's
  own reading of every execution instruction.

## 7. Live test (funded account, staging)

Account Mike Lim (`253f7fa6…`, Facebook), preprod client `main.dart.js` sha256
`056b7c9db2d0e58f…` **= local build**, backend image
`deployment-01M27CYM6C9AZ67X71FJ5WSND8`, UI in French, 390 × 844.
Evidence images: `docs/pwa-red-proposal-2026-09-11/`.

**Which project.** The frozen advisor is deterministic per room on this sentence
(measured, no render): `Master Bedroom` → YELLOW 8/8, `Bedroom` → RED 8/8, never
GREEN. The phone's project `e33955b3` is now `Master Bedroom`: it answered YELLOW
live ("« add a living room behind » … Essayer quand même ?" — correctly
localized, not answered, nothing spent). The RED run used Bedroom project
`e71efb24` (V2 Soft Luxury → V3). Incident projects `440a715e` / `c0ee05e9` were
left untouched.

| Step | Evidence |
|---|---|
| original → `/generate` | `status=advisory verdict=red`, message in French, the person's words verbatim: « En tant qu'architecte, je ne recommande pas « add a living room behind » — … Souhaitez-vous envisager de créer un coin lecture confortable ou un petit espace lounge dans la chambre à la place ? » — no `..`, no `.?` |
| card at 390 px | RED stacks: « Créer la vision » and « Modifier la demande » each whole on one line (YELLOW: « Annuler » / « Créer la vision » side by side, whole) |
| "yes" → `/chat` | `resolution=proposal`, `override_instruction` **"Create a comfortable reading nook in the left corner."**, `override_display` "Créez un coin lecture confortable dans le coin gauche." |
| `/generate` request | `user_instruction` = the English imperative, `display_instruction` = the French title, `confirm=true`, parent V2 `95b9a920` |
| executed plan | `[{"type":"add","object":"reading nook","detail":"left corner","normalized":"Create a comfortable reading nook in the left corner."}]` — **no coffee-table placement** |
| DB | V3 `b2a9579e`, `action_summary` = French title, `prompt_text` = English instruction; **1 claim** `b22ec84c` COMPLETED; ledger HOLD −1 → COMMIT; balance **280 → 279**; no other claim or ledger row since 04:45:08 (the YELLOW and a lost tap spent nothing) |
| image | V3 ≠ V2: mean abs diff 11.1/255, 9.3 % of pixels > 30; **20.9 % of the left third** vs 4.9 % centre / 2.7 % right. Visually: a reading nook — armchair, arc floor lamp, bookshelf with plant — added in the left corner (`01-parent-V2-vs-child-V3.jpg`). The phone's V7 was pixel-identical to V6. |
| verify (live) | `incomplete` → "Toujours manquant □ Créer un coin lecture confortable dans le coin gauche." (localized) |

**The live verify verdict is a false negative of the frozen verify module.**
Replayed on the exact live pair, same change: `verified` **19/20**. Its own
control (EDITED = ORIGINAL, nothing changed) answered `verified` **8/20**:
gpt-4o-mini at `detail: low` is a weak judge for this change (the parent already
shows a sitting area at the back). Not modified — it is part of the frozen
engine; a verify bench/decision is a separate item.

Residuals (non-blocking): the verify retry card quotes the executed English
("Create a comfortable reading nook…") in a French UI; the Khmer translation of
technical terms is poor (gpt-4o-mini); the Fly log buffer had rotated before the
execution-instruction log line could be captured (the instruction is proven by
the `/chat` response, the `/generate` request and `prompt_text`).

## 8. Verdict

**REFINE RED-PROPOSAL — LIVE VALIDATED** (image changed as proposed, one Space,
no duplicate; verify's live `incomplete` is a documented false negative of the
frozen verifier, 19/20 `verified` on replay).
