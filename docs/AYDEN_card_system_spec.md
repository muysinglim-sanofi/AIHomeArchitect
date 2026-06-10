# AYDEN Studio — Card Visual System — Layout / Typo / Spacing Blueprint

> Status: **design blueprint, no code** · Date: 2026-06-07 · Mobile-first, dark-mode, App-Store-first.
> Encodes the locked identity: **ROOMS = believable architecture · ATMOSPHERES = emotional projection · AI = system actions.**
> Assets sliced → `frontend/assets/cards/rooms` (13) + `/atmospheres` (5). AI cards = rendered in Flutter (no image).

---

## 0. Design tokens (reuse existing)
- **Canvas**: near-black ink `AppColors.textPrimary` (#0A0A0B feel). **Cards pop on it.**
- **Accent**: champagne `AppColors.accent` (selection only — never decorative).
- **Skeleton**: `AppColors.shimmerBase`.
- **Type families**: **Sans** (Inter/SF via google_fonts) = ROOMS + AI (functional/system). **Serif** = Cormorant Garamond (`AppTheme.atmosphereTitle`) = ATMOSPHERES (editorial/emotional).
- **Rhythm**: page margin **16**, gutter **12**, section gap **28**, radius **16** (cards) / **18** (atmo).

---

## 1. ROOMS — *believable architecture*

| Spec | Value |
|---|---|
| Layout | **2-column GRID** (mobile), uniform |
| Card ratio | **3:2 landscape** (real-estate register) |
| Gutter / margin | 12 / 16 dp |
| Radius | 16 dp |
| Grade | **neutral / true colour** (no warm push) |
| Overlay | bottom gradient scrim `transparent → #000 @0.55` over bottom **38%** |
| Label | **name only, NO number** · bottom-left, 12dp inset |
| Label type | **Sans, UPPERCASE, 13sp, w600, tracking +0.5, white** |
| Focal rule | signature object readable in <0.5s (sofa+TV, island, water…) |

**States:** default → press = **scale 0.98 + scrim +0.08** (120ms easeOut) · selected = **champagne 2dp inset border + small ✓ top-right** · (web hover = image zoom 1.03 inside clip). One motion only; no shadows beyond the card's own depth.

```
┌──────────────┐  3:2, neutral, sans-caps, no number
│   [photo]    │
│              │
│▁▁▁▁▁▁▁▁▁▁▁▁▁ │  ← gradient bottom 38%
│ LIVING ROOM  │  ← 13sp sans caps, bottom-left
└──────────────┘
```

### Rooms have TWO sub-types — Indoor vs Outdoor (treated differently)
The 13 rooms split into two functionally-different families. Same card style (grid · 3:2 · sans-caps · no number), but **grouped and graded differently**:

| Sub-group | Rooms | Grading rule |
|---|---|---|
| **🛋 Indoor** (7) | living_room, kitchen, master_bedroom, bathroom, dining_room, home_office, entrance_hall | **Neutral / true colour**, even interior daylight (the strict "rooms neutral" rule) |
| **🌳 Outdoor** (6) | terrace, balcony, pool_area, garden, house_facade, driveway | **Natural light kept** — golden-hour / dusk / sky is *realistic* here, so DON'T force-neutralize (it would look wrong). Still believable real-estate, **not** over-cinematic. |

**Layout:** within the ROOMS section, two labelled sub-grids — **“Indoor Spaces”** then **“Outdoor Spaces”** (same 2-col grid). This adds a clean sub-hierarchy without weakening the rooms↔atmospheres distinction (both stay grids vs the atmosphere carousel). The **AI Decide** card closes the Outdoor sub-grid (end of rooms).

```
ROOMS  CHOOSE THE SPACE
  Indoor Spaces                      ← sub-header (muted)
  [LIVING ROOM][KITCHEN] …
  Outdoor Spaces                     ← sub-header (muted)
  [TERRACE][POOL AREA] … [✦ AI DECIDE]
```

---

## 2. ATMOSPHERES — *emotional projection*

**Carousel, NOT grid** — this single structural choice is the strongest instant ROOM↔ATMO cue.

| Spec | Value |
|---|---|
| Layout | **horizontal CAROUSEL** (snap, peek next ~10%) |
| Card width | **~84% viewport** (e.g. ~315dp on 375pt) → **mini-hero presence**, only a thin peek of the next |
| Card ratio | **16:10 landscape** (cinematic), clearly taller/bigger than rooms |
| Radius | 18 dp |
| Grade | **warm cinematic preserved** (golden lives HERE) |
| Overlay | taller gradient `transparent → #000 @0.65` over bottom **52%** |
| Title | **Serif (Cormorant), 22sp, w500, white** · bottom-left |
| Subtitle | **Serif ITALIC, 12sp, white @0.80** — “Inspired by boutique sunset villas” |

**Why it reads instantly different from rooms:** ① carousel vs grid · ② bigger cards · ③ serif vs sans · ④ warm grade vs neutral · ⑤ emotional subtitle vs bare label. *Five* simultaneous signals.

### Light signatures (each mood must read distinct — not homogeneous)
The 5 atmospheres must separate by **lighting**, not just decor. Grading direction per card (guides hi-res generation + a placeholder grade pass):

| Atmosphere | Light signature |
|---|---|
| **Warm Modern** | **sunset amber warmth** — golden-hour interior glow |
| **Nordic Warmth** | **cold blue daylight + warm orange lamp pools** — cold/warm contrast (snow outside, lit hearth) |
| **Soft Luxury** | **night, darker, glossy, high-contrast** — 5-star hotel *at night*: deep shadows + brass speculars. **Must NOT overlap Warm Modern → push contrast + darken.** |
| **Japandi Calm** | **soft diffused beige daylight** — low contrast, calm, shadowless |
| **Tropical Escape** | **bright tropical sun / resort brightness** — luminous, lush saturated greens |

> Current placeholders are sliced as-is → I can apply a **per-atmosphere grade pass** (Pillow: darken+contrast Soft Luxury toward night, cool Nordic daylight, brighten Tropical, etc.) so the moods separate now; final separation comes with hi-res originals shot to these signatures.

```
ATMOSPHERES  CHOOSE THE FEELING
┌────────────────────┐┌──────────────
│   [warm photo]     ││  [next peeks]
│                    ││
│▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁ ││
│ Warm Modern        ││  Nordic Warmth
│ Inspired by boutique││  Inspired by…
│ sunset villas      ││
└────────────────────┘└──────────────
   ● ○ ○ ○ ○            (page dots, optional)
```

> Placeholder note: current sliced atmo photos are landscape → they fit 16:10 directly. (If we ever go portrait 4:5, regenerate originals portrait.)

---

## 3. AI CARDS — *system actions*

Match the **geometry** of the section they close, **invert the fill** (photo → black) → reads as action, not content.

| Spec | Value |
|---|---|
| Placement | **“AI Decide”** closes the ROOMS grid · **“Surprise Me”** closes the ATMOSPHERES carousel (semantic split; not both in both) |
| Fill | flat black `#0E0E10`, **1dp border white @0.08** |
| Icon | **✦ sparkle**, centered, soft white (or faint champagne), ~22dp |
| Label | Sans, 14sp w600 + tiny 11sp subtitle @0.6 (“Let AI choose…”) |
| Glow | **NO glow.** Optional: a *very* subtle radial sheen + a slow 2.5s sparkle opacity pulse (0.6↔1.0). Restraint > flash. |
| Shape/radius | identical to neighbour cards (grid 16 / carousel 18) |

```
┌──────────────┐   black, 1dp hairline, centered
│      ✦       │
│  AI DECIDE   │   sans 14 w600
│ Let AI choose│   11sp @0.6
└──────────────┘
```
They never compete with photos (no color, no imagery) yet align perfectly (same box) → premium, not cheap.

---

## 4. MOBILE-FIRST VALIDATION

**Full screen mock (375pt portrait):**
```
┌───────────────────────────────┐
│ ROOMS   CHOOSE THE SPACE       │  hdr: sans bold + caps muted
│ ┌────────────┐ ┌────────────┐  │
│ │ LIVING ROOM│ │ KITCHEN    │  │  2-col, 3:2, ~165dp
│ ┌────────────┐ ┌────────────┐  │
│ │ MASTER BED │ │ BATHROOM   │  │
│ ┌────────────┐ ┌────────────┐  │
│ │ … (13 rooms)│ │ ✦ AI DECIDE│  │  AI ends grid
│ └────────────┘ └────────────┘  │
│                                │  ← 28dp section gap
│ ATMOSPHERES  CHOOSE THE FEELING│
│ ┌────────────────┐┌─────────── │  carousel, ~290dp, 16:10
│ │ Warm Modern    ││ Nordic…    │  serif + italic
│ │ Inspired by…   ││            │
│ └────────────────┘└─────────── │  …ends with ✦ Surprise Me
└───────────────────────────────┘
```
- **Thumbnail readability:** 13sp caps on a 165dp card = legible; focal object recognizable; blur-test (mood survives squint) ✓.
- **Dark mode:** near-black canvas, neutral rooms + warm atmos both pop; scrims guarantee AA label contrast.
- **App Store:** this one screen = a strong hero shot ("choose your space / choose the feeling"); screenshots: (1) rooms grid, (2) atmospheres carousel mid-scroll, (3) a reveal.
- **Spacing rhythm:** 16 / 12 / 28 consistent; section headers identical treatment.

---

## 5. INTERACTION / MICRO-UX (premium restraint)
- **Press:** scale 0.98 + slight scrim, 120ms easeOut. Release springs back.
- **Selected:** champagne 2dp border + ✓; deselect on re-tap.
- **Carousel:** `PageScrollPhysics`-style **snap**, peek next ~18%, momentum, no bounce overshoot drama. Optional page dots.
- **Scroll:** rooms grid scrolls vertically inside the page; atmospheres scroll horizontally — the **axis change reinforces the category change**.
- **Loading:** **shimmer skeletons** matching each card shape (shimmerBase), **never spinners**.
- **Rules:** one animation at a time · no parallax · no glow/flares · no auto-playing motion on this screen (it's a chooser, calm).

---

## 6. FINAL HIERARCHY PHILOSOPHY
| | ROOMS | ATMOSPHERES | AI |
|---|---|---|---|
| Question | *“What space?”* | *“What feeling?”* | *“Decide for me”* |
| Register | architectural / functional | editorial / emotional | system |
| Encoded by | grid · neutral · sans-caps · no number · 3:2 | carousel · warm · serif+italic · 16:10 · bigger | black · ✦ · no photo |
| Feeling | believable | aspirational | effortless |

**The system is the message:** a user *feels* the difference (grid↔carousel, neutral↔warm, sans↔serif, scroll-vertical↔horizontal) before reading a single word. That instant, wordless clarity is the AYDEN identity win.

---

# VALIDATION CHECKLIST (approve before code)
- [ ] Rooms = 2-col grid, 3:2, sans-caps, **no number**
- [ ] Rooms split **Indoor (neutral) / Outdoor (natural light kept)**, two labelled sub-grids
- [ ] Atmospheres = **carousel**, **~84% mini-hero** + ~10% peek, 16:10, serif + italic subtitle
- [ ] Atmosphere **light signatures distinct** (Soft Luxury = dark/contrasty night, not Warm-Modern-like)
- [ ] AI = black ✦, no glow, geometry-matched; AI-Decide ends rooms / Surprise-Me ends atmospheres
- [ ] Spacing 16/12/28, radius 16/18, champagne = selection only
- [ ] Micro-UX: press 0.98, snap carousel, shimmer skeletons, no flash
