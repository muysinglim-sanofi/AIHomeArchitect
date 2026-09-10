# PWA PRE-PRODUCTION UX / PARITY FIXES — 2026-09-10

Scope: PWA / preprod only. Production, ABA PayWay, Billing, Wallet, grants,
RevenueCat and the native iOS sources (`frontend/lib/**`, `frontend/ios/**`)
were **not modified**. iOS was read as a reference only.

- PWA worktree `c:/Projects/ayden-pwa-web`, branch `pwa-web-ios-alignment`
- Backend `c:/Projects/AIHomeArchitect/backend`, branch `pwa-monetization`
- Deployed: `ayden-api-staging` (Fly, sin) and `preprod.aydenstudio.com`
- Test suite: **1542 / 1542 green** (1528 before this work, +14 new)

---

## 1. AUTH SHEET — the official Facebook mark, and Ayden's own language

`pwa_account_sheet.dart`

- `_FacebookMark`: the official blue glyph (`#1877F2`) on a 22pt white disc,
  sitting inside the dark primary pill — the arrangement Meta's own brand
  guidance uses on a dark button.
- `_PrimaryButton` gained a `leading` slot and lost its generic `icon`, so a
  brand mark is a widget rather than an `IconData`.
- Rhythm: 10pt between the two doors, `PwaGap.lg` before the divider.
- The returning-user line is a `Wrap`: a muted question, then the gold
  `Se connecter` — so LINK and SIGN IN stay two visibly separate intents.

**LINK vs SIGN IN is unchanged.** No auth logic, no Supabase model, no Facebook
architecture was touched — this is the sheet's surface only.

Evidence: `QA/02-link-sheet-390.png`, `QA/D7-link-sheet-1440.png`.

---

## 2. VISION WIDTH — V2 and V3 now render at V1's width

**Root cause, measured.** Vision 1 was laid out at the thread's full width.
Every later vision was nested inside `_V7AydenGroup`, which is a `Row` of a 32pt
avatar + a 10pt gutter + an `Expanded` column — so anything inside it is
indented by **42pt**. On a 390pt phone the render lost 42 of 342 points, **12%**.
That is exactly the reported "V1 large, V2/V3 smaller cards".

**Fix.** `pwa_architect_screen.dart`: the SPEECH keeps its avatar and its
indent; the RENDER is hoisted to the thread's own width, where Vision 1 already
sat. Chronology is untouched — Ayden still answers first and shows second.

Held by `VISION-WIDTH-01/02/03` (390×844 and 1440×900).

> Note on the tests: at 390×844 a three-render thread is far taller than the
> screen, so at most one vision is ever *on stage*. The other two are laid out
> in the list's cache region — real geometry, unpainted — which is why the
> finder uses `skipOffstage: false`. Without it the assertion silently measured
> one widget and proved nothing.

---

## 3. ATMOSPHERE SWITCH / FULL REVEAL — the wait is the canvas

**Root cause.** Only `PwaWorkKind.firstVision` drew the full canvas. A switch or
a refine drew a small ivory bubble with three dots, appended at the end of a
long thread — and `applyAtmosphere` returns the person to the conversation, at
the top of it. So after choosing an atmosphere there was no visible sign that
anything had started.

**Fix.**
- `_V7GeneratingCanvas` — V1's canvas, over the vision being transformed rather
  than the original photo. Same veil (`0xB3141210`), same `PwaWorkingIndicator`,
  same shape. No second loading language was invented.
- `initState` scrolls the thread to the bottom when the screen mounts mid
  generation, which is what leaving the Full Reveal does (ATM-02).

Held by `ATM-01/03`, `ATM-02`, `ATM-05`.
Live V1 reference: `QA/07-v1-working-390.png`.

> **Not verified live.** Switching atmosphere spends a Space, and this guest's
> free vision was consumed by V1; grants are out of scope by instruction, so no
> Space was granted to get past the paywall. The behaviour is held by the three
> widget tests above at both form factors.

---

## 4. REFINE — AYDEN CAN ADVISE. THE USER DECIDES.

> **CORRECTION — same day, after a real iPhone test.** Three statements in this
> section were wrong, and the refine fix they supported was incomplete:
>
> 1. **RC1 as stated did not hold.** The "conversation → GENERATE (0.92)"
>    measurement below used a history that ENDS WITH AYDEN'S TURN. The client
>    shipped here sent mobile's shape, with the line being answered as the LAST
>    entry — and with that shape `pending_design_sub_intent` and
>    `_last_assistant_text` still return nothing (re-measured: "yes", "vas-y",
>    "do it anyway", "oui" → `None`). The canonical resolvers stayed dead.
> 2. **T4 ("vas-y" → `generate/refine_atmosphere`) was not Wave 4.7.7.** It is
>    `classify_intent("vas-y")` classifying the word on its own (0.90).
> 3. **"Resume the original" was the wrong model of a go-ahead.** When Ayden
>    proposes an ALTERNATIVE ("Would you like to create a living area next to
>    the bedroom instead?"), "yes" agrees to the alternative, not to the
>    original. The phone test that proved it: RED advisory, "yes", words back
>    (`intent=conversation/general should_generate=False`).
>
> Also reversed on the owner's rule: REFINE-04 ("RED is not forceable by
> typing") — "do it anyway" after a RED warning now executes the original, on
> the card as well as typed. The replacement design, its measurements and the
> live evidence are in `docs/PWA_FINAL_PREPROD_FIXES_2026_09_10.md`.

### 4.1 REFINE PARITY — DEEP DIFF

| Dimension | Native iOS | PWA (before) | Same? | Note |
|---|---|---|---|---|
| Refine **system/assistant prompt** | `refine/advisor.py` `_L2_SYS` | same module, same constant | **SAME** | the PWA imports `refine.advisor`, it does not re-implement it |
| Refine **parser prompt** | `refine/parser.py` `_SYS` | same module, same constant | **SAME** | `parse_changes`, one call, one reading |
| **Model config** | advisor `gpt-4o-mini`, `temperature=0`, `max_tokens=160`; parser `gpt-4o-mini`, `temperature=0`, `max_tokens=500` | identical | **SAME** | no PWA-specific model or temperature anywhere |
| **Render endpoint** | `POST /refine` (`main.py:5375`) | `pwa_staging_api` `_refine_advisory` + `_refine_render`, calling the same `refine.*` modules | **SAME ENGINE** | mobile's `/generate` chat path is a *different* engine (`accumulate_refinements`); neither product uses the other's |
| **Chat gate** (does this line deserve an image?) | `POST /chat` → `should_generate` | `POST /pwa/staging/chat` → `main.chat`, the same async function | **SAME BRAIN** | the adapter calls it, it does not reimplement it |
| **What `/chat` receives as `history`** | the CONVERSATION: `chat_screen.dart` `_send` builds `contextMessages` from `_messages` and posts `[{role: user\|ai, content}]` | `_history_from(chain)` — one `{role: user}` entry per stored VISION, **never an assistant turn** | **DIFFERENT** ⟵ **ROOT CAUSE 1** | |
| **Bare go-ahead → generate** | Wave 4.7.7 `resolve_confirmation(message, history)`, gated on `pending_design_sub_intent(history)` which requires `history[-1]` to be an assistant turn | structurally dead: the lineage list has no assistant turn, so the resolver always returned `None` | **DIFFERENT** | consequence of root cause 1 |
| **Clarification dominance** | Wave 4.11d `is_clarification_answer(message, history)` | dead for the same reason | **DIFFERENT** | same consequence |
| **MIXED handling** | `main.py` maps MIXED → `should_generate=False` by design ("chips guide toward it") | identical | **SAME** | but see root cause 2 |
| **Advisory override** | advisory CARD holding `AdvisoryInfo.originalMessage`; [Try anyway] resends it with `confirm=true` — *"de façon DÉTERMINISTE, sans repasser par le classifieur /chat"* | `_V7RefineConfirmCard` with `pendingRefine`; [Continue anyway] resends with `confirm: true` | **SAME** | the BUTTON was already at parity |
| **Typed** override ("do it anyway" in the composer) | none — iOS has the button only | none | **NEITHER HAD IT** ⟵ **ROOT CAUSE 3** | the brief requires it (REFINE-02/03) |
| **RED is not forceable** | `chat_screen.dart:1811` refuses `confirm` from a RED card | card refuses it | **SAME** | and the new typed route now refuses it too |

### 4.2 Root causes, each proven by direct measurement

**RC1 — the conversation was never sent.** `pending_design_sub_intent(history)`
returns `None` unless `history[-1]` is an assistant turn. Measured, same
message, both history shapes:

```
history = lineage rows   "do it anyway" -> resolve_confirmation = None
history = conversation   "do it anyway" -> GENERATE (0.92)
history = conversation   "vas-y"        -> GENERATE (0.92)
history = conversation   "yes" after a QUESTION -> None
```

**RC2 — MIXED is the classifier's FALLBACK, not a verdict.**
`classify_intent("break the wall on the left and do a living room", 2)` answers
`MIXED / GENERAL, confidence 0.40, "Unclassified longer message"`, and `main.py`
maps MIXED to `should_generate=False`. So a real instruction came back as words.
The refine ADVISOR, asked the same sentence, answers **GREEN** — the block was
never a safety verdict.

**RC3 — reviving the canonical chain is necessary and NOT sufficient.**
Measured, not assumed: `pending_design_sub_intent` scores the pending line
against `_DESIGN_CONVERSION` / `_STRUCTURAL` / `_LOCAL_EDIT` / `_REFINE` /
`_WISH`, and *this very sentence matches none of them* — "living room" is absent
from the shared `_FUNCTIONAL_ROOM` taxonomy. On mobile that is precisely why the
advisory CARD exists: the go-ahead never reaches the classifier at all.

### 4.3 The fix

`pwa_staging_api.py`, two gates, no phrase list in the product path:

- **GATE 1** — a MIXED line is referred to the module whose job is reading
  instructions (`refine.parser`). If it parses real changes, the line is an
  instruction. CONVERSATION and DESIGN_DISCUSSION keep answering, which is what
  stops "what do you think?" from buying an image. The advisor still runs on the
  render path and can still object.
- **GATE 2** — while a declined instruction is outstanding, a go-ahead resumes
  it with `confirm`. The detector is **canonical**: `is_confirmation`
  (Wave 4.9.4) — every bare go-ahead shape in EN and FR, with the veto that
  keeps "ok but explain first" and "maybe later" out — with one small model call
  as the tail for the languages it does not read (Khmer).

And the conversation is now sent (`PwaChatRequest.history`,
`pwa_controller._conversationForChat()`), in mobile's exact shape:
`MessageType.text` only, `{role: user|ai, content}`, oldest first, the line
being sent included, bounded to 24 turns. `_history_from(chain)` is untouched
and still feeds the COMPOSER on the render path — the composer wants the
lineage's instructions, the conversation wants the conversation.

`is_confirmation`, measured over 25 phrasings: 15/15 go-aheads TRUE
(`do it anyway`, `proceed anyway`, `go ahead`, `just do it`, `vas-y`,
`d'accord`, `oui`, `ouais vas-y`, …), 10/10 non-go-aheads FALSE
(`ok but explain first`, `maybe later`, `wait`, `actually make it warmer
instead`, `plutôt du japandi`, …).

### 4.4 Live evidence — staging, real classifier, no Space spent

`/chat` is free and is not quota-gated, so the whole decision was exercised
against the deployed backend without buying a render:

| # | message | history / pending | `should_generate` | `intent` | `override_instruction` |
|---|---|---|---|---|---|
| T1 | "break the wall on the left and create a living room" | none | **true** | mixed/general | — |
| T2 | "do it anyway" | OLD shape (lineage, nothing outstanding) | **false** | conversation | — |
| T3 | "do it anyway" | conversation + outstanding | **true** | conversation | the original sentence |
| T4 | "vas-y" | conversation + outstanding | **true** | **generate/refine_atmosphere** | the original sentence |
| T5 | "what do you think of this space?" | — | **false** | design_discussion | — |
| T6 | "ok but explain first" | outstanding present | **false** | conversation/clarification | — |

T2 reproduces the reported bug. T3 fixes it. **T4 came back as
`generate/refine_atmosphere`** — that is the canonical Wave 4.7.7 firing on its
own, i.e. the history fix working independently of GATE 2. T5 and T6 are the
no-regression side: a question buys nothing, and a hedge is not a go-ahead.

End to end through the UI, the same instruction now reaches the refine path and
is stopped only by the free-tier quota (`QA/10-after-paywall-390.png`) — words
are no longer the answer.

### 4.5 A hole closed on the way

The typed override would have let someone past a **RED** advisory, which the
card refuses by contract. `_declinedInstruction` is now cleared on a red verdict,
so a second route cannot pass what the button cannot. Held by `REFINE-04`.

### 4.6 Known limitation

The PWA does not persist chat messages (mobile does, via
`_svc.insertMessage`). The conversation, and therefore the outstanding
instruction, live for the session: a go-ahead must follow the objection without
a page reload. Out of scope here — it needs a messages table.

---

## 5. FULLSCREEN IMAGE VIEWER

`pwa_image_viewer.dart` — an opaque pushed route, so closing lands back on the
exact project, scroll position and selected vision, and the browser Back button
means "leave the photo".

- `InteractiveViewer` (pinch / trackpad zoom, `minScale: 1`, `maxScale: 5`)
- `BoxFit.contain` on black — a fullscreen viewer that cropped would hide the
  part of the room the person opened it to see
- close affordance, title, safe areas, no page scroll behind (the route is
  opaque and full-screen)

Reached from the Full Reveal's new `pwa-reveal-fullscreen` control. **The vision
card's expand control was deliberately left pointing at the Full Reveal** — that
is the accepted contract (`pwa_architect_test`, `pwa_result_parity_test` both
hold it) and the gesture iOS settled on.

Live: `QA/12-fullscreen-390.png`, `QA/D3-fullscreen-1440.png`.

---

## 6. SHARE + SAVE — the generated image, not a screenshot and not a link

`pwa_image_export.dart` (contract) + `WebPwaImageExporter` (browser).

- Capability is **probed, never assumed**: `navigator.canShare({files})` with a
  real one-byte JPEG, because agents that expose `share` for text still refuse
  files.
- SHARE hands the actual file to the platform sheet.
- SAVE: the sheet **where the sheet can save**, a download everywhere else.

### Two defects found by the live test, and fixed

**D1 — "Enregistrer l'image" shared instead of saving, on desktop.** Measured on
preprod: Windows Chrome answers `canShare({files}) == true`, and the tap opened
the Windows share flyout — apps to send the picture to, and no way to save it. A
control labelled "Save image" that shares is wrong. SAVE now prefers the sheet
only on a touch platform (`(pointer: coarse)`) — the phones whose sheet carries
"Save Image" / "Add to Photos", which is the iOS behaviour the brief asks for —
and downloads on a pointer platform. A capability query, not a user-agent brand.

**D2 — the file name dropped the room.** Delivered as
`Ayden-Studio-Warm-Modern-v1.jpg` while the contract documents
`Ayden-Studio-Living-Room-Warm-Modern-v2.jpg`. Both call sites omitted
`roomLabel`; the room is now resolved through a single named helper,
`pwaSessionRoomLabel`, shared with the session context line.

Verified live at 1440×900, instrumented at the DOM: the click produces
`<a download="Ayden-Studio-Salon-Warm-Modern-v1.jpg" href="blob:…">`.

**Hardening, stated as such.** `prefetch` warms the bytes when the picture is
opened, because `navigator.share` is gated on transient user activation and a
multi-megabyte fetch inside the tap is what spends it. The `NotAllowedError` was
measured directly, but in a gesture-less probe — not in the product path — so
this is defence against a documented constraint, not the repair of an observed
defect.

Held by `SHARE-03/04/05/06`.

---

## 7. iOS PARITY REVIEW (read-only)

Nothing under `frontend/` was modified. What the review established, beyond the
refine table in §4.1:

- **Refine request construction** — identical modules and model config; the
  difference was never in the prompt.
- **Atmosphere switching** — iOS's contract is `before_after_screen.dart` doing
  `context.pop(_selectedAtmosphere)` on Generate, with the CHAT starting the
  switch. The PWA already matches it; what it lacked was the *waiting surface*
  (§3).
- **Advisory** — `AdvisoryInfo` carries `originalMessage` so [Try anyway] is
  deterministic; RED is never forceable. Both already matched, and the new
  typed route was brought under the same rule.
- **`_looksLikeDesignInstruction`** — iOS keeps a prefix-verb heuristic, but it
  fires **only when `/chat` throws**. It is a network-failure fallback, not part
  of the decision, and was deliberately not copied.

---

## 8. TESTING

- **1542 / 1542** green. New: `test/features/pwa/pwa_preprod_polish_test.dart`
  (VISION-WIDTH-01/02/03, ATM-01/03, ATM-02, ATM-05, REFINE-01/02/04/05,
  SHARE-03/04/05/06).
- Visual QA at **390×844** and **1440×900** on `preprod.aydenstudio.com`, driven
  over CDP. Screenshots in the session scratchpad under `QA/`.

### Two regressions I introduced and closed

- **HOME23 / REVEAL14** — both assert a source substring containing a literal
  `\n`. My edits had converted 14 files from LF to CRLF, so the patterns stopped
  matching. No product defect; the files were renormalised to LF.
- The first pass of the polish tests measured **one** vision instead of three
  (`skipOffstage` — see §2) and could never observe the waiting state (the mock
  renders in zero milliseconds; `generate` is now held open by a `Completer`).

---

## 9. WHAT IS NOT COVERED

- **Atmosphere switch, live.** Needs a Space; the guest's free vision was spent
  on V1 and grants are out of scope by instruction. Held by widget tests at both
  form factors (§3).
- **Share sheet completing, live.** `navigator.share()` opens a native OS sheet
  that a driven browser cannot complete. The call path, the file and the file
  name were verified; the sheet's own UI was not.
- **iOS Safari / real iPhone.** The save rule is written for it and reasoned
  from its documented behaviour; it was not exercised on a device.
