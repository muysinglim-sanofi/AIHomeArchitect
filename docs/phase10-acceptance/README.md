# Phase 10 — release readiness

**Acceptance preview: <https://ayden-studio--phase10-acceptance-fqusrvko.web.app>**
(expires 2026-09-27 — 30 days, unlike the 7-day phase previews)

This is the consolidated Phases 1–10 PWA. All acceptance testing should happen
here rather than on the phase channels. Live staging and every phase preview
are untouched.

| file | what it shows |
|---|---|
| `01-home-desktop.png` | Home at 1440 — a bounded, centred composition |
| `02-home-phone.png` | Home on a phone, unchanged |
| `03-projects-mock.png` | the Projects grid (mock target, five projects) |
| `04-menu-mock.png` | the card menu — the product's grammar, not the dark screen's |
| `05-rename-mock.png` | Rename — the field is readable again |

---

## THE ONE THING THAT MUST HAPPEN BEFORE CUTOVER

**Live staging is still serving the app shell as immutable for a year.**
Measured today, not inferred:

```
https://ayden-studio.web.app/main.dart.js         → max-age=31536000, immutable
https://ayden-studio.web.app/flutter_bootstrap.js → max-age=31536000, immutable
https://ayden-studio.web.app/version.json         → max-age=31536000, immutable
https://ayden-studio.web.app/                     → no-cache, no-store
```

This is the exact RELEASE-CRITICAL regression flagged in Phase 3. The fix has
been in `firebase.json` since then and is correct on every preview channel —
including this one, verified — but **live has not been redeployed since**, so
the rule that is live is the old one. The HTML is fresh and the JavaScript it
asks for is a year old: anyone who has opened `ayden-studio.web.app` is pinned
to that build and will not see a new release.

It was not fixed here because the brief forbids overwriting live staging. The
remedy at cutover, in order:

1. `./tool/build_pwa.sh staging`
2. `./tool/deploy_pwa.sh --live` — which re-checks the shell rules before it
   uploads, and asks for confirmation
3. re-measure the four URLs above; they must all say `no-cache`
4. anyone already pinned needs one hard reload (⌘⇧R / long-press reload →
   "Empty cache and hard reload"), or to clear the site's data. There is no
   server-side way to un-pin a browser that already holds a year-long entry.

A test parses `firebase.json` and fails if any shell file loses `no-cache`;
`tool/deploy_pwa.sh` re-checks the same thing at deploy time. Neither can
detect a *stale deployment*, which is what this is.

---

## Defects found and fixed

Nine independent read-only audits ran over the whole PWA — typography and
surfaces, iPhone geometry, desktop composition, routing, states, localization,
delivery, payment architecture, weight. Every defect below was then verified by
hand before anything was changed.

**`pwaSerif` named no font.** The helper every sheet uses for its editorial
headline set no `fontFamily` and no fallback, so it inherited the app's default
— Inter. The paywall title, the payment sheet title, the payment success
title and all three account-sheet titles had been set in the body typeface
since the helper was written. Cormorant now, through the same family and
fallback chain `PwaType` uses. Same class of bug as `av7Sans` in Phase 6.

**A third ink-on-ink button.** "Start designing" — the one action offered the
moment a purchase succeeds — was a black label on a black pill. Phase 9 fixed
the paywall's Buy and the ABA hand-off; this call site was missed, and it is
the worst placed of the three.

**The dark screen leaked through the project menu.** Phase 7 reused
`PwaProjectCardMenu` without following where its actions led: the ⋯ on a cream
project card dropped a near-black sheet, and Rename and Delete opened
near-black dialogs — the largest surviving dark surface outside the Full
Reveal, sitting on the destructive action. Repainted; only colours changed, the
actions, keys and controller calls are untouched. The ⋯ disc stays dark
because it sits on the person's own render. A source test now fails if a
dark-screen token or one of the two hard-coded literals reappears in that
block — the literals are there because the first sweep missed them and left a
black text field inside a white dialog.

**Home ran to both edges of a monitor.** Projects and Profile were bounded;
Home was not, and its hero took its height from the WINDOW — a phone rule that
produced a 3.4:1 letterbox on a desktop. Home now uses the product's shared
ceiling and then stops narrower still (900), because it is one picture and one
sentence rather than a grid that earns width by fitting more work in. Away
from a phone the hero takes its height from its own width, so it stays a
landscape composition. Phone geometry is unchanged. The footer had to be
bounded separately — it belongs to the scaffold, not to the column.

**"1 redesigns", and three more counts.** `transformationsCount` owns only the
SINGULAR — the plural word stays the frozen mobile dictionary's, which is the
approved terminology in all three languages. `passSpacesLeft(1)`,
`paywallSpaces(1)` and a 31-day-old project ("1 months ago") were the others.
Khmer has no grammatical plural, so its singular and plural are the same
sentence, written out rather than left as a gap.

**`/create` could not be deep-linked by a first-time visitor.** Phase 8
exempted `/profile` from the empty-library fallback and left `/create` behind —
the one link worth sending someone who has never used the product, and whose
library is empty by definition. Both are exempt now, stated once in
`_bootRouteFor`; project routes still fall back, because there is no project.

**The guide sheet was unreachable in landscape.** Its media is 3:2 and takes
its height from the sheet's WIDTH, so on a phone held sideways the poster alone
was taller than the viewport and the caption and replay button were below the
fold with no scroll view and no height cap. Both added, and the media capped so
it cannot eat the sheet. Its frame also moved from the retired `pwaCharcoal` to
the product's `pwaImageFrame`.

**The Architect header printed the room in English.** The stored `room_type` is
canonical English by design; every other surface localises it at display time
through `pwaRoomDisplayLabel`. This header was the last one printing it raw,
which put "Master Bedroom" at the top of a Khmer conversation.

**The secret scan certified places it had not looked.** It reads every
non-binary file in the bundle — correctly, no extension filter — but its needle
list was PayWay-only. §12 asks for more, so a second named verdict now scans
the same files for a service-role JWT, OpenAI/Anthropic key prefixes,
RevenueCat secrets and database URLs. It reports **PASS 11, LEAKS 0**. The
production hostnames are deliberately NOT scanned for: they are compiled in as
a reject-list, so finding them proves the guard exists.

**Nothing stopped a mobile build being deployed.** `firebase.json` publishes
`build/web`, which is exactly where a plain `flutter build web` writes the
MOBILE entrypoint — a bundle that compiles, looks plausible, and has been
deployed by mistake on this branch before. `tool/build_pwa.sh` now writes a
marker naming the entrypoint and mode, and `tool/deploy_pwa.sh` refuses to
deploy without it, refuses a bundle rebuilt over it by hand, and re-checks the
shell cache rules before uploading.

  This was a `predeploy` hook in `firebase.json` first. That hook runs through
  the system shell — cmd.exe here — which does not resolve `node` even though
  the firebase CLI is itself node, so it refused *every* deploy on this
  machine. A guard that blocks the work gets deleted, and then nothing checks.
  It lives in the documented command instead, and `firebase.json` says so.

`/flutter.js` was the last mutable shell file with no cache rule. It has one
now, and the cache regression test covers it and `/index.html`.

---

## Known issues, deliberately left

**Hardcoded English in the conversation.** After an atmosphere switch or a
refine, Ayden's reply comes from the repository's English
(`switchIntro`, `refineApplied`, `mock_pwa_experience_repository.dart:116,144`)
while the FIRST vision's reply is localised through `_l10n.firstVisionIntro`.
So a Khmer reader gets Khmer, then English, in one conversation. **This is the
largest remaining localization gap and I recommend closing it next** — but it
means authoring Ayden's conversational voice in Khmer and French, which is
product copy and belongs to whoever owns that voice, not to a polish pass.
Project titles are composed in English from the English room label the same
way.

**A failed boot reads as "you have no projects".** `pwaResolveBootRestore`
catches everything and returns an empty library, so a dropped connection at
boot shows a person with a dozen projects the empty state, and turns `/profile`
and `/create` back into `/`. Truthful failure here needs a "could not load"
state that does not exist — a new state, not polish.

**`PwaSaveState.error` has no renderer.** A durable write that fails after the
first vision leaves the screen looking successful. Also a missing state.

**Bundle weight, measured, not fixed.** `build/web` is 110 MiB deployed;
first paint is ~3.4 MB gzip. The three largest recoverable items are all
either forbidden or risky mid-freeze: 32.9 MB of CanvasKit is deployed but
never requested because the build uses Google's CDN (changing that changes a
boot dependency); 33.9 MB of create-flow PNGs and 7.2 MB of PNGs misnamed
`.jpg` can only be reduced by re-encoding, which the brief forbids; 6.8 MB of
orphaned and 5.5 MB of byte-duplicated assets ship because `pubspec.yaml`
declares whole directories — and that file is shared with the frozen mobile
app. None of this is downloaded by a visitor except the CDN CanvasKit.
Fonts are clean: subset, variable, all three families used, none fetched
remotely.

**Flutter Web ignores iOS safe-area insets.** Every `SafeArea` in the app is a
no-op on this target — `MediaQuery.padding` is zero — so the clearance around
the home indicator is whatever iOS itself grants. This is a Flutter platform
limitation, not a layout bug, and closing it means feeding
`env(safe-area-inset-*)` in from CSS. Worth doing before an installed-PWA
launch; not a screen redesign, so it is flagged rather than attempted here.

**Sheets are full-window on a large monitor** (they inherit no max width), and
the generation error bar spans the window. Both are wide-screen only.

---

## Guide entry — the recommendation §7 asks for

**Leave it in Profile only. Do not add a help icon to Home.**

Profile is one tap from every screen, its SUPPORT section is where a person
looks for help, and "See how it works" is discoverable there. Home is one
headline, one picture and one button — the composition Phases 2 and 10 both
worked to protect — and a help icon in its header would be the fourth control
in a top bar that currently has two. iOS has the icon because iOS has a
different header; copying it would be parity for its own sake, which is the
thing this alignment has refused at every step.

---

## Audit results

**Payment architecture — the invariant holds.** PWA → Ayden checkout endpoint →
backend PayWay adapter → official ABA Purchase API. The browser makes zero
requests to any ABA host except the hosted checkout page it is handed. Proof
on both sides: the client's four calls all go through one helper against the
Ayden base URL (`pwa_generation_api.dart:621`), whose origin allowlist contains
no ABA host; the backend's `POST /checkout` calls
`payway.purchase(...)` → `PATH_PURCHASE = "/api/payment-gateway/v1/payments/purchase"`,
signs with `sign(purchase_hash_payload(body), cfg.api_key)`, and is pointed at
`SANDBOX_BASE`. `generate-qr` appears nowhere in `lib/` and an existing test
scans the whole of `lib/` for it, `check-transaction`, `payway_api_key`,
`merchant_id`, `hmac` and `sha512`. The client sends a **sku**; the amount is
read server-side from `products.price_usd`. `/payments/open` re-verifies with
PayWay before answering, so a browser return alone can never read as paid.

**Routes.** `/`, `/create`, `/projects`, `/profile` all return 200 on the
acceptance channel and open their own screen cold. Project routes normalize
against the durable library as before.

**Cache, on this channel.** `/main.dart.js`, `/flutter.js`,
`/flutter_bootstrap.js`, `/version.json` → `no-cache, must-revalidate`; `/` →
`no-cache, no-store`. Only `/canvaskit/**` remains immutable.

**Localization.** Key parity is clean: 286 PWA keys in each of en/km/fr with an
empty set difference, 424 in each shared dictionary, every referenced key
resolves, every `{n}` placeholder present in all three. The gaps are the
conversation copy above, and fixed-width labels that FR and KM can overflow
(the example-room strip, the room cards, the session status line, the
atmosphere subtitles) — all noted, none redesigned.

---

## Gate

* `flutter test` — **1290 passed, 0 failed**
* `flutter analyze` — 2 issues, both pre-existing `info` lints in
  `pwa_i18n_test.dart`, a file no phase has touched
* `./tool/build_pwa.sh staging` — clean, writes the build marker
* `./tool/deploy_pwa.sh phase10-acceptance` — both guards pass
* `backend/pwa_secret_scan.py` — **PASS 11, LEAKS 0**
