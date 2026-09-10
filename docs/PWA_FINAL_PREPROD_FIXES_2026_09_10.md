# AYDEN STUDIO PWA — FINAL PRE-PRODUCTION BUG FIX PASS — 2026-09-10

Scope: PREPROD / STAGING only. Production, ABA PayWay, payment credentials,
Billing semantics, Wallet, grants, RevenueCat, the Supabase account model, the
Facebook OAuth architecture and the native iOS sources (`frontend/`) were **not
modified**. iOS was read as a behavioural reference only.

| | |
|---|---|
| Backend | `ayden-api-staging` (Fly, sin) — deployed, health 200 |
| Client | `preprod.aydenstudio.com` — deployed; live `main.dart.js` sha256 `ca81306402cc8389…` **= local build** |
| Flutter | `flutter analyze`: no issues · full suite green (see §10) |
| Resolver | shipped code, fixed 52-case matrix: **52/52** (`backend/pwa_staging_resolver_eval.py`) |

Evidence screenshots: session scratchpad `QA/` (R1/R2 font reproduction, F0–F7).

---

## 1. REFINE — conversational context

### 1.1 What the phone showed, and why (proven)

The sequence: "break the wall on the left and add a living room behind" →
Ayden: "As your architect, I don't recommend « add a living room behind » … Would
you like to consider creating a separate living area adjacent to the bedroom
instead?" → "yes" → "I need more context or a specific question…".

1. **The warning was a RED advisory.** Only the RED branch of
   `refine/advisor.py build_advisory_message` writes "As your architect, I don't
   recommend « … »" and appends "Would you like to {alternative}?".
2. **Nothing was outstanding.** The previous pass's REFINE-04 rule cleared the
   declined instruction on RED, copying mobile's card contract.
3. **The canonical resolvers could not fire.** `pending_design_sub_intent` (Wave
   4.7.7) and `_last_assistant_text` (Wave 4.11d) give up when the newest
   history entry is a user turn — and the client sent the line being answered as
   the last entry (mobile's shape). Re-measured, same thread:
   `line INCLUDED "yes" → None`; `line EXCLUDED "yes" → GENERATE`.
4. **Even alive, they only flip `should_generate`.** They never say WHAT to
   render and cannot read a proposal Ayden made — so "yes" could at best have
   replayed the ORIGINAL, which is the wrong answer to "would you like X
   instead?".
5. The server log for the phone's "yes": `12:52:22 [pwa-staging] chat —
   intent=conversation/general should_generate=False room=Bedroom iter=3`.

The previous report's "RC1" claimed that sending the conversation revived the
canonical chain. It did not (point 3); a correction note now heads §4 of
`PWA_PREPROD_UX_PARITY_2026_09_10.md`.

### 1.2 iOS parity, read-only (`frontend/lib/features/chat/chat_screen.dart`)

| # | Dimension | Native iOS | PWA before | PWA now |
|---|---|---|---|---|
| 1 | History payload | `contextMessages` = `_messages` filtered to `MessageType.text`, **line being sent included** | same shape (this was mirrored) | **prior turns only**; the server strips a trailing copy of the line from either shape |
| 2 | Role ordering | oldest first, `ai`/`user` | same | same |
| 3 | Previous assistant turns | advisory cards are `MessageType.advisory` → **excluded**; result cards excluded | advisory text included, result speech excluded | advisory text **and** Ayden's words on a result card included |
| 4 | `pending_design_sub_intent` | unreachable for this sequence (trailing user turn) — measured with iOS's own shape | same | reachable (prior turns), but no longer what decides |
| 5 | Pending proposal / action state | `AdvisoryInfo.originalMessage` only; the advisor's alternative is not kept | none | the original kept verbatim on every verdict; Ayden's proposal read from his last turn |
| 6 | Confirmation handling | Wave 4.7.7, unreachable (row 4) | same | reference resolver (§1.3) |
| 7 | Override handling | [Try anyway] button on YELLOW; RED has [Edit request] only | typed override, not on RED | typed and card override on every verdict |
| 8 | Generation decision | `should_generate` from `/chat` | same | `/chat`, then the resolver for a short reply to something Ayden said |
| 9 | Refine instruction sent | the typed text; an alternative cannot be accepted by typing | the original only | Ayden's proposal, or the original — replayed with `confirm` |
| 10 | Endpoint / model / config | `POST /refine`, `refine.parser` + `refine.advisor`, gpt-4o-mini, temperature 0 | same modules and config | unchanged |

iOS is not a reference that already works here: for this exact sequence it
cannot resolve "yes" either. The PWA now implements the brief's rule rather than
copying a gap.

### 1.3 The fix — the model reads, the code decides

- **Client** (`pwa_controller.dart`): `_conversationForChat(excludeId:)` sends
  the prior conversation, ending with Ayden's turn; the original stays
  outstanding on every verdict, verbatim.
- **Server** (`pwa_staging_api.py`): for a short reply that follows something
  Ayden said, two concurrent gpt-4o-mini reads — what Ayden's LAST QUESTION
  offers (from his message alone: one change / the original / several options /
  nothing) and what kind of reply this is (from the reply's own words: agree /
  insist / refuse / pick / other) — then a decision table. The original is never
  written by a model. Fail-closed: any error is `none`.
- **Card** (`pwa_architect_screen.dart`): [Create vision] on RED too.

Why this shape — measured on the same fixed matrix, not chosen:

| Resolver | Score |
|---|---|
| one fused decision (the version first deployed) | 22/38 |
| procedural prompt, gpt-4o-mini / gpt-4o | 18/38 · 25/38 |
| both facts in one call | 34/38 |
| two calls (offer isolated from the reply) | 44/52 |
| the reply judged on its own words | 51/52 |
| + "a no followed by a request is not a refusal" | **52/52, twice** |
| the SHIPPED code (lifted from `pwa_staging_api.py`) | **52/52** |

The 52 cases include the phone's exact sequence, 14 EN/FR go-aheads, 5
insistences, refusals, choices between options, a French RED warning and
Khmer replies (បាទ, ចាស, យល់ព្រម, ទេ).

### 1.4 Live — deployed backend, real classifier, no Space spent

| Case | Reply | Result |
|---|---|---|
| A — RED proposes an alternative | "yes" | `should=true res=proposal` → "create a separate living area adjacent to the bedroom instead" |
| B — same warning | "do it anyway" | `should=true res=original` → "break the wall on the left and add a living room behind" |
| C — "Would you like me to make it warmer?" | "yes" | `res=proposal` → "Make it warmer" |
| C′ — same | "no" | `should=false res=decline` → "Nothing will change." |
| D — "a reading nook, or a small writing desk?" | "yes" | `should=false res=choose` → "Which one would you prefer?" |
| EN after A | yeah, yep, sure, ok, okay, go ahead, do it, proceed | all `proposal` |
| EN after A | proceed anyway | `original` |
| FR after A | oui, d'accord, vas-y, fais-le, continue | all `proposal` |
| FR after A | fais-le quand même | `original` |
| a question | "what do you think of this space?" | `should=false`, nothing rendered |
| a new instruction | "no, make the sofa blue instead" | not swallowed — canonical GENERATE |

**The request the deployed client really sends** (captured over CDP, "yes"
after the V1 message): `history = [ai: "Votre direction Warm Modern est en place
— …"]`, the line being sent **not** inside, `pending_instruction = ""`; answer
`should_generate=false resolution=none` (an open question offers nothing).

For the exact RED sequence the same property is held by `REFINE-06`: the
warning is the **last** entry the server receives, and the original travels in
`pending_instruction`.

### 1.5 Not done: the actual generated image

Every refine render spends a Space. The staging guest used for QA has spent its
free vision, and grants are out of scope, so no refine image was generated here.
The decision layer is proven live (above); the render path it hands over to is
the existing, unchanged `applyRefine(…, confirm: true)`. **REFINE-LIVE-01/02
with an image: pending — needs the funded account (§9).**

---

## 2. AUTHENTICATED ACCOUNT MENU

**Root cause.** In `pwa_account_chip.dart` the identified user's "Signed in as
Mike Lim" row carried `value: 'account'`, which opens `showPwaAccountSheet` — and
the sheet had no identified-state branch, so it rendered the Guest chooser:
"Secure your Ayden account", "Continue with Facebook". (Profile's sign-in-method
rows were already non-actionable when attached.)

**Fix.**
- Identified menu: the identity **stated** — name + "Connected with Facebook", a
  disabled item — then **Profile** and **Sign out**. No path to the sheet.
- The sheet derives its doors from the identities actually attached
  (`app_metadata.providers` + verified e-mail/phone): an attached provider is
  never offered; when nothing is left to add it says so (`accountLinkedTitle` +
  "Connected with …"). Placed before the method steps, so an e-mail-only
  deployment cannot ask an account with an e-mail for one.
- Guests unchanged: "Save my creations" (LINK) and "Sign in" (SIGN IN) stay two
  doors.

Tests AUTH-STATE-01…05. Live: the Guest menu (F4). The Facebook account's menu
is widget-tested; on the device it is §9 step A.

---

## 3. UPLOAD PICKER — app-controlled anchor (not an OS mystery)

"Photo Library · Take Photo · Choose File" is WebKit's menu, but it grows from a
rectangle the page controls — `WebKit/UIProcess/ios/forms/WKFileUploadPanel.mm`:

```
CGRect elementRect = parameters->elementRectInMainFrameViewCoordinates();
bool elementIsVisible = page && CGRectIntersectsRect(elementRect, page->unobscuredContentRect());
_menuPresentationRect = elementIsVisible ? elementRect : CGRect { [view lastInteractionLocation], CGSizeZero };
```

`image_picker_for_web` appends its `<input type=file>` to `<body>` unstyled.
Measured at 390×844: **`0,0 253×21`, visible** — so the menu grew from the
page's top-left corner, or, whenever that corner left the unobscured rect, from
the last touch point: "sometimes high, sometimes low".

**Fix** (`pwa_file_picker_anchor.dart`): inside the tap, before the picker
opens, the plugin's host is made fixed, transparent and deaf to touches and
parked on a 2pt band across the middle of the tapped zone. Live on the
deployed client: **`24,393 342×2`, `position:fixed opacity:0
pointer-events:none`**. No Ayden pre-picker was added (it could not replace the
OS menu and would double the choice).

Test UPLOAD-02 (anchored on the zone, before the picker opens). The menu's final
position on an iPhone is WebKit's to draw — **confirm on device (§9)**.

---

## 4. PROFILE GENERATION COUNT

**Root cause.** The stat was `visibleProjects.length` — the number of
**projects** — under the label `projectsCount` ("Redesigns"). Three renders in
two projects read "2 Redesigns". (iOS's `_StatsRow` does the same.)

**Fix.** `completedVisionCount`: every finished vision off the durable vision
rows the library is hydrated from, plus the session in hand, **deduplicated by
id**. Label **"Visions"** — the product's own word for a render (Vision 1,
"Votre vision gratuite"); KM ទស្សនៈ. A failed or rolled-back generation never
becomes a vision row, so it cannot count. Nothing is read from the wallet.

Tests COUNT-01/02, `pwa_round4_profile_test` updated. On Mike Lim's account the
expected value is **3** — §9 step B.

---

## 5. FULL REVEAL — breathing room

`kPwaRevealChromeGap = 12` — the canvas's own side inset, so the render sits in
one even margin on three sides. Live: toolbar 16–48pt, canvas from 60pt, at 390
and 1440 (F1, F6).

- Width: unchanged — the canvas is the column minus 24 at every size; V1, V2, V3
  identical (REVEAL-SPACING-01/02 at 390×844 and 1440×900).
- Trade-off, stated: on a height-bound phone the canvas is 12pt shorter; a
  landscape render keeps its exact width; a portrait render scales ~4%.

**Found and fixed on the way:** with two or more visions the toolbar (7
controls + "Vision 1 of 3") overflowed a phone's 374pt — **110px** in the test
font — pushing Share off the edge. The fullscreen control added in the previous
pass tipped it over. A narrow row now tightens to 4pt gaps and a "1/3" counter
(the full sentence kept for screen readers).

---

## 6. FULLSCREEN — the empty button

**Root cause (proven).** `MaterialIcons-Regular.otf` is tree-shaken per build —
only referenced glyphs, ~16 KB — under a **fixed name**; `/assets/**` was served
`public, max-age=604800`; Flutter 3.41's `flutter_service_worker.js` caches
nothing (it unregisters itself). `Icons.fullscreen_rounded` had **0 references
at HEAD**, so every earlier subset lacked U+F7A6. A returning iPhone ran the new
`main.dart.js` (no-cache) against last week's font → a circle with no glyph.

**Reproduced** on preprod: serving the live font minus U+F7A6 through CDP
`Fetch.fulfillRequest` draws exactly the phone's empty circle (R1); the real
font draws the icon (R2). The download icon (U+F6DF) was exposed the same way.

**Fix (preprod only).** `/assets/**` → `no-cache` (ETag revalidation), and no
other rule may cache a font — Firebase does not document which of two matching
header rules wins, so the overlap was removed rather than ordered. The deploy
guard enforces it. Live: the font, `FontManifest.json` and
`AssetManifest.bin.json` answer `Cache-Control: no-cache`; the live font
contains U+F7A6, U+F6DF and U+E255.

> **One manual step per affected device.** A copy already cached is fresh for
> up to 7 days and is never re-requested, so no server change can reach it:
> on each test iPhone (and the ABA testers'), clear the website data for
> preprod.aydenstudio.com (Settings → Safari → Advanced → Website Data), or
> remove and re-add the home-screen app.

Behaviour: FULLSCREEN-01…05 on V1, V2, V3 (icon, viewer opens, zoom, back to
the same vision, nothing lost); live F2, F3, F7.

---

## 7. SHARE / SAVE

- Share: the image **file** to `navigator.share` where `canShare({files})`
  holds; text otherwise.
- Save: the share sheet on touch platforms (where it carries "Save Image"); a
  download elsewhere. Live on desktop after the toolbar changes:
  `Ayden-Studio-Salon-Warm-Modern-v1.jpg` from a `blob:` of the render.
- No claim of Photo Library access.

The iPhone share sheet itself: **pending real iPhone (§9 step E)**.

---

## 8. NON-REGRESSION

VISION-WIDTH-01…03, ATM-01/02/03/05 and the accepted Reveal geometry tests
(ORI, REVEAL14, round-3) are green; ORI04's hard-coded block height became
derived from the chrome constants.

---

## 9. REAL-DEVICE SEQUENCE (prepared)

Before starting: clear the website data for preprod.aydenstudio.com (§6).

| Step | Action | Expected |
|---|---|---|
| A | Signed in with Facebook → Profile → top-right menu | "Mike Lim" / "Connected with Facebook", then Profile, Sign out; nothing opens "Continue with Facebook" |
| B | New design → V1 | Profile shows **4 Visions** (3 + this one) |
| C | V2 by atmosphere switch | same width as V1; waiting canvas in view; count +1 |
| D | V3 | same width; count +1 |
| E | Full Reveal | 12pt under the toolbar; ⛶ visible; viewer opens and returns to the same vision; Share opens the iOS sheet with the image; Save offers "Save Image" |
| F1 | "break the wall on the left and add a living room behind" | if Ayden proposes an alternative → "Yes" → the render follows the **proposal** |
| F2 | same instruction again → "do it anyway" | the render follows the **original** |
| — | Upload area | the photo menu grows from the middle of the upload zone, every time |

---

## 10. TESTS

- `flutter analyze`: no issues.
- New: `test/features/pwa/pwa_final_preprod_test.dart` — AUTH-STATE-01…05,
  COUNT-01/02, REVEAL-SPACING-01/02 (390 and 1440), FULLSCREEN-01…05,
  UPLOAD-02, REFINE-06/07/08.
- Updated on purpose: `pwa_chat_gate_test` (RED offers the override),
  `pwa_round4_profile_test` (the stat), `pwa_orientation_test` ORI04 (derived
  heights), `pwa_preprod_polish_test` REFINE-01/04.
- Backend: decision table 13/13 with a stub client (fail-closed included);
  resolver 52/52 on the shipped code.

---

## 11. KNOWN LIMITS AND FOLLOW-UPS

- The **live** Firebase target still has the old week-long `/assets/**` cache;
  it needs the same rule before its next deploy.
- The chat thread is not persisted across a reload (mobile persists it), so a
  go-ahead must follow Ayden's question in the same session.
- RED is now overridable in the PWA (card and typing) — a deliberate, owner-set
  divergence from mobile's card contract.
- Mobile has the same history-shape gap (Wave 4.7.7 unreachable) — frozen, not
  touched.
- Nothing is committed or pushed.
