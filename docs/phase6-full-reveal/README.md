# Phase 6 — the Full Reveal

Preview: <https://ayden-studio--phase6-full-reveal-wh4owp3b.web.app> (expires 2026-09-04)
Live staging and the Phase 2 / 3 / 4 / 5 previews are all **untouched**.

| file | what it shows |
|---|---|
| `01-reveal-fr.png` | **the screen** — a real staging generation, at rest |
| `02-divider-30-fr.png` | dragged to ~30%: almost all result |
| `03-divider-70-fr.png` | dragged to ~70%: almost all original |
| `04-reveal-km.png` | Khmer, phone |
| `05-reveal-desktop-fr.png` | 1440×900 — a genuinely larger comparison surface |
| `06-reveal-desktop-km.png` | Khmer at desktop, with the atmosphere cards |

All six are the **real staging build** and a real generated render. The drags in
`02`/`03` are real pointer drags through CDP, not a rebuilt state — which is
also how surface-mode dragging was confirmed to work in a browser.

---

## What it was, and what it is

The old screen was a reading surface with a picture on it:

```
[ header bar: back · AYDEN STUDIO · Vision 1 of 1 · ‹ › ]
[ the render                                            ]
[ Vision 1 • Warm Modern • Created just now             ]
[ VISION DETAILS                                        ]
[ Vision 1 / reason label                               ]
[ ▸ a paragraph from Ayden                              ]
[ ▸ Refine with Ayden      — continue in conversation   ]
[ ▸ Try another atmosphere — explore a different style  ]
[ ATMOSPHERES  ▪▪▪▪                                     ]
```

Nearly every word of that had already been said on the Result screen one tap
earlier. It is now:

```
 ←                              [Original | Warm Modern]
              the render, uncropped, in its own halo
                    Drag to reveal
                 ( Refine with Ayden )
 Explore other atmospheres
 ▐ Ayden Signature ▌▐ Warm Modern ✓ ▌▐ Soft Luxury ▌ …
```

---

## Measured against iOS

`frontend/lib/features/result/before_after_screen.dart` — waves 5.15d/5.15l,
whose decisions its own header comments call locked.

| | iOS | PWA before | PWA now |
|---|---|---|---|
| canvas | walnut gradient `#3F3220 → #181410` | flat `#0D0C0A` | **iOS's four stops** |
| hero height | `screenH × 0.50`, clamp 340–500, −34 | ~4/3 or 16/10 box | **identical on a phone** |
| image fit | `contain` — "zero crop guarantee" | `contain` | **contain, at 3:2** |
| letterbox | blurred `cover` copy of the render, σ36 | dead charcoal | **identical** |
| corner | 22 | 16 | **22** |
| top chrome | none; a floating back control | a full header bar | **floating controls** |
| in-hero CTA | one | none | **one** |
| section title | `exploreOtherAtmospheres`, 14/w600/ls .2 | `ATMOSPHERES` eyebrow | **iOS's title** |
| cards | `AtmosphereHeroCard`, `fillPhoto` | a PWA-only card | **the same iOS widget** |
| card width | `h × 1.35`, capped at 86% of screen | fixed 132/156 | **iOS's rule** |
| action slot | reserved, below the carousel | a bar pinned to the page | **reserved slot** |
| details panel | none | a panel | **none** |
| vertical scroll | none | the whole page scrolled | **none** |

### It is dark, and that is parity

Every other migrated screen moved to the cream canvas. This one does not,
because iOS's does not: `before_after_screen.dart` paints walnut and calls the
result "galleria, not dashboard". A gallery dims the room to light the picture.

### Desktop is not iOS's rule

iOS's `0.50 × screenH` is a **phone** rule — there, height is what limits the
render. Applied literally to a 1440px window it produced a small picture adrift
in a large blurred matte, which is the opposite of the larger comparison
surface a wide window should buy. So the hero also asks what height the render
would need to fill the column, and takes whichever is larger, bounded by what
the atmospheres need. Phone geometry is unchanged; desktop goes from a ~480px
render to ~830px. A test pins the ratio.

---

## Interaction

**Drag to compare, on the whole surface.** Everywhere else in this product the
handle alone takes the drag so it cannot fight a scrolling page. This screen
does not scroll — which is exactly the condition `RevealHero` documents for
`RevealDragMode.surface` — so the whole render is draggable, and a test asserts
both halves of that: surface mode, and no `SingleChildScrollView` anywhere in
the screen.

**No hold-to-peek.** iOS long-presses the render to flash the original upload.
`RevealHero` is shared with the frozen mobile app and exposes no way to drive
its divider from outside, so imitating that would mean forking the widget or
remounting it mid-gesture — the fragile copy of a native gesture the brief
explicitly prefers not to have. Dragging compares, both sides are labelled, and
one short line says so.

---

## Nothing underneath moved

* **Before/after pair**: the canonical resolvers, `pwaBeforeImage(source,
  project, vision:, versions:)` and `pwaAfterImage(vision)`. On a first vision
  the "before" is the person's own upload; on a later one it is the parent
  render. This screen picks neither — it asks.
* **Atmosphere tap** → `stageAtmosphere(id)` → `pendingAtmosphereId` → the
  reserved slot asks → `applyAtmosphere()`. Staging spends nothing; only the
  confirmation does, and the copy states the cost first. Which atmospheres
  exist, when a switch is allowed and what it costs are decided elsewhere and
  are untouched.
* **The in-hero CTA** → `startRefineContext(versionId)`. It generates nothing
  and says nothing on the person's behalf.
* **Vision navigation** → `previewPrevious` / `previewNext`, and it is drawn
  only when there is more than one vision: a navigator that can never move is
  chrome for its own sake.

---

## The `av7Sans` correction — approved, and its collateral

`av7Sans` and `av7Eyebrow` set a `fontFamilyFallback` and **no `fontFamily`**,
so every screen using them rendered in the platform's default sans while the
rest of the product had been on Inter since Phase 1. On CanvasKit that is a
different typeface, not a subtle hint.

Both now name `kPwaTextFamily`. The fallback chain is untouched, so Khmer still
resolves through it, and nothing fetches a font at runtime.

**Collateral, as approved: Projects picks up the correction too.** Its layout,
copy and behaviour are untouched — only the typeface it was always meant to
use. Projects is not redesigned here and its own phase still owns it.

---

## Defects found by looking

1. **The instruction line sat ON the render.** The hint and CTA were positioned
   at the foot of the hero while the render was centred in the same box; they
   overlapped by six pixels. The render now reserves the foot band, so words
   are never laid over an image nobody chose.
2. **The confirmation truncated the price.** "Ayden Signature sélectionnée ·
   Crée la Vision 2 · Utilise 1 Space" beside two buttons left the sentence
   about eighty pixels wide, and the cost — the one thing that must be read
   before it is paid — ellipsised to "· ...". It is two lines now, buttons
   beneath.
3. **A double bullet.** `createsVisionN` and `usesOneSpace` each already carry
   a leading "·"; joining them with another produced "· Crée la Vision 2 · ·
   Utilise 1 Space".
4. **Desktop wasted the surface** — see above.

---

## Observed, not fixed

**Projects is still the legacy dark screen** (now in Inter). That is the stated
stopping boundary.

**A billing refusal still raises two surfaces** — the paywall and the generic
error banner. Out of scope since Phase 4; reported again for final polish.

**The CDP capture harness drops taps intermittently.** It cost several retries
across this phase and is worth knowing about for future evidence runs; it is a
property of the automation, not of the product — the same taps work by hand and
in the widget tests.
