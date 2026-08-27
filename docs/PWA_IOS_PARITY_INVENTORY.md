# PWA → iOS parity inventory

> Phase 0 diagnosis, 2026-08-27. **No UI was modified.** iOS (`frontend/`, HEAD
> `f3a6fa2`) was read only. The PWA was inspected as source AND as the live
> deployment at <https://ayden-studio.web.app>.

---

## The headline: this is less of a redesign than it looks

Three measurements changed the shape of the work.

**1. The PWA already imports the iOS palette.** `pwa_theme.dart` does not define
a rival colour system — it aliases the iOS one:

```dart
const Color pwaIvory   = AppColors.background;   // #F9F6F1
const Color pwaSurface = AppColors.surface;      // #FFFFFF
const Color pwaGold    = AppColors.accent;       // #C8A86A
const Color pwaInk     = AppColors.textPrimary;  // #1C1917
const Color pwaMuted   = AppColors.textSecondary;// #78716C
const Color pwaHairline= AppColors.border;       // #E7E5E4
```

…and then adds **three dark tokens of its own** — `pwaBlack #0B0B0C`,
`pwaCharcoal #161513`, `pwaCharcoalSoft #201E1B` — and paints the canvas with
those. The divergence is not a palette. It is *which token the canvas uses*.

**2. Half the PWA is already cream.** Measured on the live site:

| surface | canvas today |
|---|---|
| Home, Create, Projects, Full Reveal | **dark** (`pwaBlack` / `pwaCharcoal`) |
| Generation loading | **cream** — already |
| Design Session ("DESIGN WORKSPACE") | **cream** — already |
| Paywall sheet | **white/cream** — already |

The conversational surfaces migrated already; the navigational ones did not. The
product is visually bilingual, which is also why it reads as inconsistent today.

**3. The iOS creation flow is ALSO one scrolling page.** `upload_screen.dart`
holds `List<GlobalKey> _stepKeys = List.generate(4, ...)` and anchors four
sections — STEP 1 upload, STEP 2 room, STEP 3 atmosphere, STEP 4 your vision —
in a single scroll view, scrolling between them. It is **not** four routes.

The PWA's `/create` is already a single scrolling page with numbered sections
(`1. ROOM`, `2. ATMOSPHERE`). So the architectures match. What differs is
labelling and step count, not routing. **No route restructuring is required for
the creation flow.**

---

## Parity matrix

| # | iOS screen | PWA today | Major differences | Reuse logic? | PWA exception | Risk |
|---|---|---|---|---|---|---|
| 1 | Home (`home_screen.dart`) | `/` | dark canvas; hero is a stock interior, not the user's own Featured Vision with compare | **Yes** — state layer is right | — | **M** |
| 2 | Navigation: `ShellRoute` + `MainShell`, tabs `/home` `/projects` `/profile` | header icon row; **no `/profile` route**, no tab bar | must add a Profile destination and a persistent nav | Partly | web may keep a header on desktop | **M** |
| 3 | Create STEP 1 upload | `/create` upload zone + "start with an example" | no "STEP 1 OF 4" label; PWA adds an example-photo path iOS lacks | **Yes** | keep the example path — it is a web-visitor affordance | **L** |
| 4 | Create STEP 2 room | `1. ROOM` card row + "More rooms" | numbering/labelling only | **Yes** | — | **L** |
| 5 | Create STEP 3 atmosphere | `2. ATMOSPHERE` card row | numbering/labelling only | **Yes** | — | **L** |
| 6 | Create STEP 4 describe your vision (optional) | **absent** | the free-text intent step does not exist on `/create` | New UI, existing field | voice only if already supported | **M** |
| 7 | Design Session | `/projects/:id/architect` | already cream, already conversational, close in spirit | **Yes** | — | **L** |
| 8 | Generation loading | cream "Preparing your photo" + bar | disconnected from the session; does not show the source photo | **Yes** | — | **M** |
| 9 | Result | vision card inside the session | close; Ayden's comment is long | **Yes** | — | **L** |
| 10 | Full Reveal | `/projects/:id/reveal` | dark; **is an editorial explanation page** — "VISION DETAILS" repeats Ayden's full prose under the image | **Yes** | — | **H** |
| 11 | Projects | `/projects` | dark; search + sort chrome = asset-manager feel | **Yes** | — | **M** |
| 12 | Profile | **does not exist** | no route, no screen | New | web identity ≠ Apple identity | **M** |
| 13 | Save-work / identity upgrade | account chip → sheet | semantics proven; visual only | **Yes — do not touch semantics** | anonymous → linkIdentity, same UID | **L** |
| 14 | Paywall | sheet, correct catalogue | **shows the two app-store products prominently** (§14 says do not) | **Yes** | ABA packs only; Apple flow stays on iOS | **L** |

Legend: **L**ow / **M**edium / **H**igh implementation risk.

---

## Highest-risk screens

1. **Full Reveal** — the only screen whose *information architecture* is wrong,
   not just its colours. iOS treats it as the wow moment; the PWA turned it into
   a reading page. Rebuild, do not restyle.
2. **Home** — needs a real Featured Vision (the user's own before/after with
   compare) where a decorative stock hero sits today. Data exists; the
   composition does not.
3. **Navigation + Profile** — the only genuinely *missing* structure. Adding a
   shell and a third destination touches routing, which everything else rides on.

Already correct, and worth not breaking:

* **§6 user-state rule is satisfied.** With history, Home renders "CONTINUE
  DESIGNING / Pick up where you left off" and a project card — verified live,
  screenshot `14-home-with-history.png`. It does **not** claim the user is new.
* Design Session, loading and paywall are already on the cream side.
* The catalogue renders exactly as specified: STARTER 10/$4.99, POPULAR 30/$7.99,
  BEST VALUE 300 ~~$79.99~~ **$47.99 40% OFF** — screenshot `11-paywall.png`.

---

## Typography — the one real gap in the token layer

| | iOS | PWA |
|---|---|---|
| display / headings | **Cormorant Garamond** (`GoogleFonts.cormorantGaramond`) | platform default |
| body | **Inter** (`GoogleFonts.interTextTheme`) | platform default |
| fetching | runtime, from Google Fonts | **disabled**: `GoogleFonts.config.allowRuntimeFetching = false` |

`pwaSerif()` exists but its own comment admits it "renders in the platform
default". So the PWA has iOS's colours and none of its typography — which is
most of why it does not read as the same product.

**This must be fixed by bundling, not by re-enabling runtime fetching.** A
payment surface that blocks on `fonts.gstatic.com` is a payment surface that
breaks behind a firewall, and runtime fetching was disabled deliberately.
Precedent exists: `NotoSansKhmer-Regular.ttf` is already bundled and served from
`/fonts/`. Cost: roughly 150–400 KB for the two families subset to Latin.

---

## Strategy

**Tokens.** Add semantic tokens (`pwaCanvas`, `pwaOnCanvas`, `pwaCardSurface`)
and repoint them from the dark trio to the iOS trio. Do **not** delete
`pwaBlack`/`pwaCharcoal` — the reveal surfaces legitimately want a dark frame
around an image, and the archive tag is the way back if the flip goes wrong.

**Routes and state.** Keep both. `PwaRoute` already models `/`, `/create`,
`/projects`, `/projects/:id/{draft,architect,reveal}`. Only two additions are
needed: a `profile` page and a nav shell. Riverpod controllers, the persistence
repository, the entitlement/payment controllers and the billing seam are all
untouched by a visual migration.

**Scroll architecture.** No restructuring. Both apps are single-scroll pages
with anchored sections.

**Business logic.** Nothing in this phase should touch the creative engine, the
Billing Engine, the ABA rail, the catalogue, or the identity semantics.

---

## Mobile Safari / installed-PWA risks

| risk | why it bites | mitigation |
|---|---|---|
| Bundled fonts inflate first paint | CanvasKit already ships ~1.5 MB | subset to Latin; `font-display: swap`; measure before/after |
| `100vh` vs Safari's collapsing toolbar | a sticky CTA jumps or hides | `100dvh` / `MediaQuery.viewInsets`, never a raw `vh` |
| Safe areas in standalone mode | status bar and home indicator overlap content | `SafeArea` on every full-bleed surface, verified installed — not in a tab |
| Keyboard on the Design Session input | Safari resizes the visual viewport, not the layout viewport | test the composer with the keyboard up, on a real device |
| Before/after drag vs Safari's back-swipe | horizontal drag from the left edge navigates back | keep the handle away from the edge, or `touch-action` guard |
| Cream canvas + `theme_color` | manifest still says `#0B0B0C`; the installed shell would frame a cream app in black | update `theme_color`/`background_color` with the flip |
| Service-worker staleness | a cached shell serves the old design | already fixed — `/` and `/index.html` are `no-cache` |

---

## Proposed sequence

Each step ends deployable and visually comparable against the archive.

| # | step | why here |
|---|---|---|
| 0 | ✅ archive | done — tags, branches, 18 screenshots, restore verified |
| 1 | ✅ parity audit | this document |
| 2 | tokens + bundled fonts + shell | nothing above looks right until type and canvas are right |
| 3 | Navigation + Profile | the only missing structure; everything else routes through it |
| 4 | Home (Featured Vision) | the first screen anyone judges |
| 5 | Create STEP 1–4 labelling + the missing STEP 4 | low risk, high recognisability |
| 6 | Design Session polish | already close |
| 7 | Loading → session continuity | remove the disconnected hand-off |
| 8 | Result | trim the prose, let the image dominate |
| 9 | **Full Reveal — rebuild** | the highest-risk screen; do it once the language is settled |
| 10 | Projects | drop the asset-manager chrome |
| 11 | Paywall | hide the app-store rows (§14) |
| 12 | tablet / desktop | widen deliberately, never into a dashboard |
| 13 | polish + real-iPhone comparison | side by side with the archive |

---

## Build guard (§17)

The web build must never be `flutter build web` bare — that compiles
`lib/main.dart`, the **mobile** entrypoint, which boots the production stack. It
compiles cleanly, which is exactly what makes it dangerous; it has already
happened once in this branch.

Recommended before step 2: a `tool/build_pwa_staging.sh` that hard-codes
`-t lib/main_pwa.dart` and the staging defines, so the correct command is the
easy one. No mobile code is involved in adding it.
