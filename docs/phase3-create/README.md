# Phase 3 — Creation flow, steps 1–4

Preview: <https://ayden-studio--phase3-create-j28pnlap.web.app> (expires 2026-09-04)
Live staging is **untouched** and still serves the archived design.

| file | what it shows |
|---|---|
| `00-create-full-en.png` | **the whole page in one frame** — all four steps, English |
| `00-create-full-fr.png` | the same, French |
| `00-create-full-km.png` | the same, Khmer — the regression check that matters |
| `01-step1-fr.png` … `04-step4-fr.png` | each step at a phone viewport (390×844), reached by tapping the rail |
| `05-desktop-fr.png` | ≥720: the rail moves to the side, as it does on iOS |

The per-step captures are French on purpose: it is the locale whose copy wraps
to the most lines, so it is where the step frame is under the most pressure.

---

## The shape of it

iOS's `upload_screen.dart` is **one** `SingleChildScrollView` holding four
`_StepSection`s separated by `AppSpacing.xxl`, with a stepper above that tracks
which one you are reading. It is not a wizard: nothing is gated, and you can
scroll straight past 2, 3 and 4 to the CTA.

That is exactly the fast path the web was built around, so the single-page
architecture was not something to preserve *despite* iOS — it is what iOS does.
What was missing was the **perception** of four steps, and Step 4 itself.

---

## Step by step, measured

Numbers read from `frontend/lib/features/upload/upload_screen.dart` at mobile
HEAD `f3a6fa2`, not re-derived.

### The frame each step sits in

| | iOS `_StepSection` | PWA before | PWA now |
|---|---|---|---|
| badge | ink pill, r999, h10/v5, 10/w600/ls 1.0 on surface | none | **identical** (`PwaStepPill`) |
| badge → title | 10 | — | **10** |
| title | `displayEditorial(22, w500, 1.18, −0.2)` | `1. ROOM` sans caps | **22/w500/1.18/−0.2, Cormorant** |
| title → subtitle | 6 | — | **6** |
| subtitle | `bodyMedium` secondary, height 1.5 | none | **identical** |
| subtitle → content | `lg` 24 | — | **24** |
| between steps | `xxl` 48 | 20–26 | **48** |
| page padding | 24 / 24 / 24 / 16 | 20 | **24 / 24 / 24 / 16** |
| canvas | `#F9F6F1` | `#201E1B` charcoal | **`#F9F6F1`** |

### Step 1 — Upload your space

| | iOS | PWA now |
|---|---|---|
| zone | 4:3, `surfaceVariant`, hairline | **identical** |
| filled | `surface` + 1.5px gold border, photo **letterboxed** | **identical** |
| icon | `add_photo_alternate_outlined` 30, tertiary | **identical** |
| formats | `JPG · PNG · HEIC` | **`JPG, PNG or WebP · up to 10 MB`** — see divergences |
| privacy | shield 14 + `uplPrivacy`, `bodySmall` tertiary | **identical** |
| examples | — | **kept** (web-only, see below) |

### Step 2 — What type of space

| | iOS | PWA before | PWA now |
|---|---|---|---|
| layout | grid, 3 cols ≥600 else 2, ratio 6/5, gap 12 | one horizontal row + More/Fewer accordion | **identical to iOS** |
| lead tile | `AiActionCard`, `ayden_decide_card.png` | `PwaSelectCard` | **the same iOS widget** |
| rooms | `RoomCard` — label inside the image, serif 17/w500 | caption **below** a 3:2 thumb | **the same iOS widget** |
| overflow | `More spaces →` + horizontal strip at 0.78× | second row behind an accordion | **identical to iOS** |
| locks | premium-gated, tap → StoreKit paywall | none | **none** — see divergences |

### Step 3 — Choose your atmosphere

| | iOS | PWA before | PWA now |
|---|---|---|---|
| layout | `PageView`, viewportFraction 0.80, ratio 1.2 | 158px cards in a scroll row | **identical to iOS** |
| card | `AtmosphereHeroCard` | `PwaSelectCard` | **the same iOS widget** |
| order | Signature first, then the catalogue | same | **same** |
| Signature | name blank (wordmark is in the art) + subtitle | title + subtitle | **identical to iOS** |
| custom tile | premium `AiActionCard` free-text | — | **omitted** — see divergences |

### Step 4 — Describe your vision — **NEW**

| | iOS `_DescriptionField` | PWA before | PWA now |
|---|---|---|---|
| exists | yes | **no** | **yes** |
| badge | `Optional`, `surfaceVariant` r999 h8/v3, 11/w500 tertiary | — | **identical** (`PwaOptionalBadge`) |
| field | min 3 / max 5 lines, `surfaceVariant`, pad 16, r16 | — | **identical** |
| focus | 1.5px gold ring | — | **identical** |
| text | `bodyMedium` 15, height 1.5 | — | **identical** |
| hint | hardcoded EN in `upload_screen.dart` | — | **localised**, en/fr/km |
| microphone | `VoiceService` (Apple STT) | — | **absent** — see divergences |
| skippable | yes | — | **yes**: empty is the default |

**Step 4 adds no capability.** `PwaGenerationRequest.userInstruction` →
`user_instruction` already existed end to end, and
`pwa_staging_api.py` already feeds it to `_run_canonical_engine` for a first
vision, exactly as mobile's `desc` query parameter does. The only change on the
controller is one optional named argument:

```dart
Future<void> generateFirstVision({String userInstruction = ''})
…
userInstruction: userInstruction.trim(),
```

Trimmed, and empty when skipped — mobile's own rule — so a blank Step 4 sends
byte-for-byte the request the web sent before this phase. All sixty existing
call sites compile untouched.

### The stepper

| | iOS | PWA now |
|---|---|---|
| narrow | top rail, 4 nodes, hairline under | **identical** |
| wide (≥720) | side rail + content | **identical** |
| node | 28px circle, ink when current or past, 1.6px ring + halo when current | **identical** |
| tracking | deepest header past a reading line 120px down | **identical** |
| tap | jumps to that step | **identical**, with the correction below |

---

## The one that mattered most: every deploy was invisible

This is not a Phase 3 defect — it came in with the deployment work — but Phase 3
is what surfaced it, and nothing else here could be trusted until it was fixed.

`firebase.json` carried a single header rule matching **every** `js`/`json`/image
by extension and serving it `public, max-age=31536000, immutable`. Flutter web's
app shell — `main.dart.js`, `flutter_bootstrap.js`, `version.json` — keeps the
**same filename on every build**. So a browser that had opened the site once was
told to keep that build for a year and never ask again.

The symptom was fixes that were provably live on the server and absent on
screen. It cost most of an afternoon chasing a scroll bug in code the browser
was not running.

`immutable` is only ever safe for a URL that changes when its bytes do. The rule
is now scoped to `canvaskit/**` (versioned by the Flutter release); `assets/**`
and media get a week; and the app shell revalidates:

```
/main.dart.js          no-cache, must-revalidate
/flutter_bootstrap.js  no-cache, must-revalidate
/version.json          no-cache, must-revalidate
/manifest.json         no-cache, must-revalidate
```

Verified against the deployed channel with `curl -D -`.

**This is worth carrying to production before launch.** Any customer who has
opened the site once would otherwise be frozen on that build — including through
a pricing change or a payment fix.

---

## The defects the browser found that the tests did not

Each was found by looking at the deployed build, and each is now pinned by a
test that would have caught it.

1. **The flow floated on tall viewports.** The content column was wrapped in
   `Center`, which centres on *both* axes. On any viewport taller than the page
   there was a band of dead canvas above Step 1 and below the CTA. Now
   `Align(topCenter)`.

2. **The lead card of Step 3 was a black rectangle.** Ayden Signature is not in
   `kAtmosphereCardById` — it is a delegation, not an atmosphere — so the
   generic `assets/cards/atmospheres/<id>.png` fallback resolved to a file that
   does not exist. It now names `assets/atmospheres/ayden_signature.jpg`, the
   file iOS names, and a test asserts every atmosphere's card art is really in
   the bundle.

3. **Tapping a step under-scrolled — partly a ghost.** Most of what was
   observed was the stale-bundle problem above: the browser was running an
   older build. The hardening done while chasing it is kept, because it is
   correct on its own terms and the widget test pins it. iOS's
   `ensureVisible(alignment: 0.05)` on the whole *section* reveals less than the
   leading edge once the target is taller than the viewport, and on the web the
   sections routinely are — the copy wraps to more lines in French and Khmer
   and the rooms are a grid. The anchor is now the badge (26px in every
   language), the offset is computed from two absolute positions rather than
   the `ancestor:` overload of `localToGlobal`, and the landing is re-measured
   after the settled frame and corrected. Verified on the current build:
   tapping 3 lands Step 3 at the top with the rail on 3. The test asserts
   *where* it lands, not merely that it moved.

5. **The sticky CTA spanned the whole window on desktop** — a 1400px pill under
   a 760px flow. Capped to the content column.

4. **The example thumbnails took seconds to appear.** They are the full-size
   example rooms (2.4 MB and 2.5 MB), decoded at native resolution to paint an
   84px box. Capped with `cacheWidth`.

---

## Deliberate divergences

Every one of these is a decision, not an omission.

**No microphone, and no sentence offering one.** iOS's `_DescriptionField`
wraps `VoiceService` (Apple speech-to-text) and its subtitle reads "Brief the
architect in your own words. **You can speak or type.**" The web build has no
such service and Phase 3 does not add one, so the button is absent *and* the
offer is absent — `PwaL10n.step4Sub` is the one Create string the web does not
forward from the mobile dictionary. Copying the sentence without the button
would have been the worst of the three options.

**No locks on rooms or atmospheres.** iOS gates them behind `premiumProvider`
and opens a StoreKit paywall on a locked tap. The web sells one-time ABA credit
packs and meters at generation time, so every room is selectable and the
Billing Engine answers at Generate. Reproducing the padlocks would be
reproducing the appearance of a business model the web does not have.

**No "Custom" atmosphere tile.** iOS ends its carousel with a premium
free-text tile. On the web that is Step 4, which is free and always present, so
the tile would be a locked duplicate of the field directly below it.

**File formats.** iOS says `JPG · PNG · HEIC`. The staging bucket's MIME
allowlist is `image/jpeg|png|webp` with a 10 MB cap, so the web states what it
will actually accept. A HEIC offered here would be refused on upload.

**"or drag & drop it here" is gone.** The old zone advertised it; there is no
drop target in this build and there never was — no `DropTarget`, no drag
listener, the whole panel is an `InkWell`. Following iOS retires a claim that
silently did nothing on the desktop browsers most likely to try it. Real drop
support needs a package, and `pubspec.yaml` is shared with the frozen mobile
app, so it is a separate change rather than something to bolt on here.

**The examples strip stays.** Web-only, and kept: a browser visitor with no
photo to hand still has to be able to see what the product does. It leaves with
the empty zone, exactly as before.

**The header.** iOS has a `close` and a title. The web adds the language
switcher and the identity chip, which a browser tab needs and a phone app does
not, plus a Projects shortcut. Same leading `close`, same title role.

---

## Not fixed, and why

**Step 3 downloads ~14 MB of card art.** Five atmosphere PNGs at 2.2–3.0 MB
each plus the 2.2 MB Signature JPEG. This is **not** introduced by Phase 3 —
the old carousel used the same files — and the `PageView` actually improves it,
since only the pages near the viewport are built where the old strip built all
six. But on a Cambodian mobile connection it is a real cost, and it is the
single largest performance item on this screen. Re-encoding is out of scope
here: those files are shared with the frozen mobile app.

---

## What was retired from the test suite, and why

Roughly twenty tests in `pwa_entry_test.dart` described the old web mechanic in
detail: two horizontal carousels, a More/Fewer accordion, desktop arrow buttons
that paged by whole cards, and a promotion rule that moved a selected optional
card to the end of the popular row. None of that exists on iOS, and iOS is the
source of truth, so they were not migrated — there is nothing left for them to
describe.

Everything that outlived the mechanic was carried across and restated against
the new screen: the defaults, the pre-upload legibility, the Generate wiring,
the offline assets, and no overflow at the mandated breakpoints. The suite is
green at **1119** tests.
