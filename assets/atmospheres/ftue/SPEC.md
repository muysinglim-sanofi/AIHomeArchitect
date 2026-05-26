# FTUE Atmosphere Transformation Spec
# `assets/atmospheres/ftue/`

This folder is the visual thesis of AIHomeArchitect.

Every image here must demonstrate the same singular idea:  
**One real space. Infinite architectural futures.**

---

## Core Product Principle

The FTUE Screen 3 hero is not a gallery.  
It is a **transformation demonstration**.

The user must feel:
> "This is MY room. Redesigned. Again. And again. By different architects."

This emotional recognition — same room, different life — is the product's core differentiator.

---

## NON-NEGOTIABLE: The Same-Space Rule

Every image in this folder is the **same physical space**, rendered in a different atmosphere.

**What must stay identical across all 7 images:**

| Element | Requirement |
|---|---|
| Room type | Open-plan contemporary living room |
| Floor plan shape | L-shaped, ~8 m wide × 6 m deep |
| Ceiling height | 3.2 m, flat |
| Left wall | Floor-to-ceiling window wall, full width |
| Front wall | Solid plaster with centered rectangular fireplace opening |
| Right background | Open kitchen counter / island visible in far background |
| Camera position | Right side of room, ~1 m from right wall |
| Camera height | 1.4 m (eye level, slightly elevated seated) |
| Camera angle | Diagonal, looking toward left window wall + sofa zone |
| Lens equivalent | 24 mm full-frame (wide, full room depth visible) |
| Composition | Window wall in left half of frame; fireplace zone in right background; sofa grouping in midground center |
| Perspective | Lines converge toward the left window wall |

**What must change per atmosphere:**

| Element | Per-atmosphere |
|---|---|
| Floor material | Varies (teak, stone, concrete, marble, tatami, terracotta…) |
| Wall finish | Varies (limewash, plaster, clay, dark stone…) |
| Fireplace treatment | Varies (stone, marble, clay niche, water feature…) |
| Window view | Varies (tropical garden, forest, desert, neutral sky…) |
| Sofa form + material | Varies (rattan, linen, velvet, boucle…) |
| Coffee table | Varies (travertine, teak, live-edge, ceramic…) |
| Textiles | Varies (linen, wool, silk, cotton canvas…) |
| Lighting mood | Varies (warm golden, cool grey, dramatic directional, candle glow…) |
| Color palette | Varies per atmosphere |
| Decorative objects | Varies (restrained per Japandi; layered per Nordic; artisanal per desert) |

---

## The Baseline Room

Use this description as the **invariant architectural shell** in every prompt.

```
Contemporary open-plan living room, L-shaped, 8 metres wide by 6 metres deep.
Ceiling height 3.2 metres, flat ceiling.
Left wall: floor-to-ceiling frameless windows spanning the full width,
  overlooking a private terrace or courtyard.
Front wall (short side): smooth plaster with a centered rectangular fireplace
  opening, no mantelpiece, clean architectural reveal.
Right background: long kitchen island counter just visible in the far right,
  stone top, minimal hardware.
Floor: wide-format neutral surface (to be specified per atmosphere).
Seating zone: a sofa grouping in the midground — a two-seater sofa and an
  armchair — arranged facing the window wall.
Coffee table: simple rectangular form in the center of the seating zone.
Camera: positioned in the right rear corner at 1.4 m height, looking
  diagonally toward the left window wall. 24 mm equivalent lens.
The window wall fills the left half of the frame. The fireplace wall is
  visible in the right background. Sofa zone is centered in the frame.
```

---

## Photography Quality Standard

Target reference: **luxury hospitality editorial photography**.

Benchmarks: Rosewood Hotels, Aman Resorts, Six Senses, high-end Airbnb editorial, AD Architectural Digest interior spreads.

Requirements:
- Believable, photorealistic materials
- Correct depth of field (slight — foreground sharp, background slightly soft)
- Physically correct lighting (no impossible light sources)
- No people
- No text or signage
- No AI-signature artifacts (repetition patterns, melting geometry, floating objects)
- No surreal or impossible architectural elements
- Premium restraint — calm, not cluttered

**Forbidden:**
- Yoga practitioners, meditation subjects, people posing
- Grapes, fruit, food, lifestyle accessories
- Pinterest collage energy
- Glossy CGI overrendering
- Overdecorated influencer interiors
- Generic stock photo composition
- Ultra-saturated AI color filters

---

## Format

| Property | Value |
|---|---|
| Format | JPG or WebP |
| Minimum resolution | 900 × 600 px (landscape) |
| Maximum file size | 250 KB |
| Aspect ratio | ~3:2 (fills the FTUE hero container at full width) |
| Color profile | sRGB |

---

## AI Generation Prompt Template

Use this template for each atmosphere. Replace `[ATMOSPHERE BLOCK]` with the per-atmosphere specification below.

```
Photorealistic architectural interior photography. Contemporary open-plan
living room, same architecture preserved: floor-to-ceiling windows on the
left wall, rectangular fireplace opening on the front wall, kitchen island
visible in the far background, sofa grouping in the midground, same 24mm
diagonal camera angle from the right corner at eye level.

[ATMOSPHERE BLOCK]

Luxury hospitality editorial quality. Correct depth of field.
Physically plausible lighting. No people. No text. Ultra-detailed.
No CGI overrendering. No stock photography feeling.
Aspect ratio 3:2, 900x600 pixels minimum.
```

---

## Per-Atmosphere Transformation Specifications

### `ftue_tropical_escape.jpg` — Tropical Escape

**Emotional target:** Barefoot luxury resort. Warm, humid, open-air. The feeling of an Aman or COMO Shambhala villa where indoors and outdoors dissolve.

**Atmosphere block:**
```
Rendered as a luxury open-air tropical living room.
Floor: wide-plank teak or warm fossil limestone.
Sofa: rattan frame, thick cream linen cushions, organic woven form.
Coffee table: woven rattan with glass top, or solid teak.
Wall finish: warm limewash white, slightly textured.
Fireplace opening: replaced by a carved volcanic stone niche or wall-mounted
  stone water feature.
Window wall: the glass panels are open — seamless transition to a private
  terrace with lush tropical vegetation: banana leaves, bird-of-paradise,
  volcanic stone pavers.
Lighting: warm golden late-afternoon equatorial sun flooding from the left.
  Long tropical shadows. Warm amber tone. High humidity atmosphere.
Accents: a single large tropical leaf in a ceramic pot, a rattan floor lamp
  with a natural linen shade.
Palette: warm cream, teak brown, volcanic grey, tropical green.
```

**Differentiation from Tropical Escape neighbours:** Lighter, more open, resort-casual.  
**Avoid:** Beach stock photography, palm trees as wallpaper, thatched roofs.

---

### `ftue_warm_modern.jpg` — Warm Modern

**Emotional target:** The premium contemporary apartment you aspire to live in. Quiet, inviting, residential luxury. A calm Saturday morning.

**Atmosphere block:**
```
Rendered as a warm contemporary luxury apartment.
Floor: wide-plank European oak in a warm honey or caramel tone.
Sofa: curved organic form in warm camel or oat boucle fabric, slightly
  oversized and deeply comfortable.
Coffee table: travertine slab top on a simple brushed brass frame.
Armchair: matching warm linen or boucle, organic form.
Wall finish: smooth warm plaster in sand or barely-there beige.
Window curtains: floor-to-ceiling linen in warm oat, softly gathered.
Fireplace opening: warm brushed brass or aged bronze surround, simple slot.
Kitchen island visible in background: pale oak cabinets, stone top.
Lighting: warm indirect evening light — concealed ceiling track casting
  gentle wash + table lamp with warm tungsten glow on the side table.
Palette: warm white, oat, camel, honey oak, brushed brass.
```

**Differentiation from Japandi Calm:** Warmer, softer, more curves and textural richness.  
**Avoid:** Cold minimalism, grey-dominated palette, sterile hotel-room feeling.

---

### `ftue_japandi_calm.jpg` — Japandi Calm

**Emotional target:** The room where everything is in its right place. Muji elevated. The warmth of Scandinavian wood + the restraint of Japanese aesthetics.

**Atmosphere block:**
```
Rendered as a Japandi (Japanese-Scandinavian) living space.
Floor: wide pale ash or birch planks, matte finish, cool light tone.
Sofa: minimal low-profile form, pale undyed linen upholstery, simple tapered
  solid oak legs. Clean horizontal silhouette.
Coffee table: solid pale oak, rectangular, very simple exposed joinery.
Armchair: matching minimal form, same pale oak and linen.
Wall finish: pale ivory smooth lime plaster, slightly irregular but refined.
Fireplace opening: white-painted thin steel frame, clean slot reveal.
  A simple ceramic log set inside, no fire lit — contemplative.
Floating shelf: one pale ash shelf mounted on the front wall beside the
  fireplace — a single handmade ceramic vessel and one small stone object.
Window curtains: sheer translucent white linen, lightweight, gently moving.
Rug: a simple undyed hand-spun wool rug in a light natural tone.
Lighting: soft cool-to-neutral natural daylight, even, clean. No warm
  artificial light sources visible.
Palette: pale ash, ivory, natural linen, cool white, minimal black detail.
```

**Differentiation from Nordic Warmth:** Cooler restraint vs hygge warmth; fewer textiles; Japanese minimalism vs Scandinavian cosiness.  
**Avoid:** Colourful cushions, maximalist styling, generic IKEA aesthetic.

---

### `ftue_nordic_warmth.jpg` — Nordic Warmth

**Emotional target:** Hygge made architectural. The coziest room you have ever been in. Winter evening. Fire lit. Nowhere to be.

**Atmosphere block:**
```
Rendered as a Scandinavian hygge living room.
Floor: wide pale birch planks, slightly worn and warm.
Rug: large hand-woven undyed wool rug in natural cream and warm grey tones.
Sofa: chunky, deep, warm boucle or thick cotton in oat/cream. Oversized.
  A thick cable-knit throw draped casually over one arm.
Coffee table: solid birch or pine, honest construction, slightly rustic.
Armchair: sheepskin draped over a simple wooden armchair.
Wall finish: smooth warm plaster in soft off-white.
Fireplace: the rectangular opening now contains a lit wood-burning fire —
  warm orange flame visible, logs stacked inside, ash on the hearth.
Fireplace surround: pale brushed plaster or simple pale stone.
Window: soft grey-blue winter daylight through sheer white curtains.
  Snow or bare birch branches just barely visible outside.
Additional light: three pillar candles on the coffee table. One taper
  candle on the windowsill. One floor lamp with a warm linen drum shade.
Palette: oat, cream, warm grey, birch blonde, amber fire glow.
```

**Differentiation from Warm Modern:** Much more textural and tactile, firelight is dominant, cozy informality vs quiet contemporary elegance.  
**Avoid:** IKEA showroom quality, furniture product shots, cold grey Nordic cliché.

---

### `ftue_nature_retreat.jpg` — Nature Retreat

**Emotional target:** Architecture that disappears into the forest. A room that feels like a clearing in the woods. Organic, grounded, alive.

**Atmosphere block:**
```
Rendered as a biophilic forest cabin interior.
Floor: rough-sawn solid oak with a matte natural oil finish. Wide planks
  showing natural grain and occasional knots.
Rug: a large hand-knotted jute or sisal rug in warm natural tones.
Sofa: organic sculptural form in heavy natural linen or cotton canvas.
  Cushions in undyed linen.
Coffee table: live-edge timber slab — natural edge preserved — on simple
  forged steel legs.
Armchair: woven rattan or solid oak with a canvas cushion.
Wall finish: warm sandy plaster with embedded straw or hemp texture.
  Or raw natural linen stretched over the walls.
Ceiling: visible rough-sawn timber beams.
Fireplace surround: raw stone or fieldstone, honest construction. Logs
  stacked beside it. No fire lit — daylight mode.
Window wall: the view outside is now a dense birch or pine forest.
  Dappled green forest light coming through. Leaves just outside the glass.
Interior planting: trailing pothos or philodendron along one corner,
  growing naturally, not styled.
Lighting: dappled green-filtered forest daylight dominant. Cool natural tone.
Palette: warm oak, natural linen, forest green, raw stone, warm earth.
```

**Differentiation from Nordic Warmth:** Green-filtered natural light vs amber firelight; forest view vs winter sky; biophilic organic vs hygge cozy.  
**Avoid:** Camping tent aesthetic, pine tree cartoon motifs, excessive succulents on every surface.

---

### `ftue_desert_luxe.jpg` — Desert Luxe

**Emotional target:** A villa at the edge of the desert. Sun-bleached. Artisanal. Tulum meets Morocco. The luxury of mineral textures and slow time.

**Atmosphere block:**
```
Rendered as a desert luxury interior.
Floor: warm terracotta hexagonal tiles or sand-colored honed limestone.
Rug: hand-knotted Berber-inspired rug in geometric pattern — undyed wool,
  cream and warm sand tones.
Sofa: curved organic form upholstered in warm sand or tobacco linen.
  Low, wide, relaxed profile.
Coffee table: handmade ceramic base (organic sculptural form) with a rattan
  inlay top. Or carved volcanic stone with a sand-colored surface.
Armchair: carved solid rattan or organic olive wood frame with woven seat.
Wall finish: warm tadelakt (Moroccan polished plaster) or clay plaster
  in clay, amber, or warm ochre tones — slightly uneven, artisanal texture.
Fireplace surround: arched plaster niche in warm clay tone — pointed arch
  or horseshoe arch reveal, deeply set.
Window reveals: deep-set window frames with warm clay plaster reveals.
  The view outside: a sculptural garden with Agave americana, olive trees,
  and warm terracotta pots. Desert dusk light — long shadows, amber glow.
Lighting: warm amber desert sunset light from the left. Long shadows.
  A ceramic table lamp with a terracotta shade.
Palette: warm terracotta, sand, clay amber, warm cream, woven natural tones.
```

**Differentiation from Tropical/Nature neighbours:** Dry, mineral, North African-Latin American rather than humid tropical or green forest.  
**Avoid:** Cowboys, cacti as kitsch, generic Moroccan souk feel, overdecorated riad excess.

---

### `ftue_soft_luxury.jpg` — Soft Luxury

**Emotional target:** A grand hotel suite you never want to leave. Quiet luxury. Cream on cream on cream. The absence of excess as the ultimate excess.

**Atmosphere block:**
```
Rendered as a quiet luxury hotel suite living area.
Floor: large-format cream marble — polished, fine veining in warm grey.
  Or polished ivory limestone in very large format.
Sofa: curved tufted sofa in champagne or ivory velvet. Sculptural organic
  form. Oversized bolster cushions in silk or high-thread linen.
Coffee table: polished cream marble top on an antique brass or gilded base.
Armchair: matching cream velvet, tight upholstery, elegant leg.
Wall finish: smooth pale cream plaster or ivory shagreen-look wallcovering.
  Very refined, no visible texture at a distance.
Fireplace surround: cream marble panel — refined, simple rectangular profile,
  thin surround. No objects on the mantel. Perfect proportion.
Window: floor-to-ceiling panels with floor-length silk or heavyweight linen
  curtains in ivory/champagne, pooling slightly on the marble floor.
Kitchen counter in background: pale stone top, cream lacquer cabinetry.
Lighting: warm refined evening light — concealed ceiling coves emitting
  warm wash + a pair of antique brass sconces flanking the fireplace,
  casting warm pools of light. No overhead spotlights visible.
Palette: ivory, champagne, cream marble, warm white, aged brass.
```

**Differentiation from Warm Modern:** Cooler palette, more formal posture, hotel-suite refinement vs residential warmth, marble vs travertine.  
**Avoid:** Flashy gold, baroque ornament, chandelier excess, cold luxury.

---

## Generation Priority Order

Generate in this order to establish same-space consistency early:

1. `ftue_warm_modern.jpg` — most neutral atmosphere; establishes baseline room clearly
2. `ftue_japandi_calm.jpg` — minimal transformation; validates camera/geometry
3. `ftue_soft_luxury.jpg` — cream marble version; tests light handling
4. `ftue_nordic_warmth.jpg` — warm fire variant; tests artificial light
5. `ftue_nature_retreat.jpg` — forest view; tests window-view replacement
6. `ftue_desert_luxe.jpg` — clay/terracotta; tests material range
7. `ftue_tropical_escape.jpg` — open-air extreme; tests indoor/outdoor dissolution

---

## Quality Gates (before committing)

For each image, verify:

- [ ] Same camera angle as all other FTUE images (diagonal from right corner)
- [ ] Same room proportions (walls, windows, ceiling visible)
- [ ] Same fireplace opening position visible in background
- [ ] Same kitchen counter depth visible in far right background
- [ ] Same sofa zone position in midground
- [ ] No people visible
- [ ] No text or signage
- [ ] No impossible architecture or AI artifacts
- [ ] Correct file size (under 250 KB)
- [ ] Correct resolution (900 × 600 px minimum)
- [ ] Photorealistic quality — not CGI-obvious
- [ ] Atmosphere is distinct from its nearest neighbour

---

## Atmosphere Differentiation Check

Run this comparison matrix before finalizing. Each pair should feel clearly different:

| Pair | Key Differentiator |
|---|---|
| Warm Modern vs Soft Luxury | Residential warmth vs hotel refinement; travertine vs marble |
| Nordic Warmth vs Nature Retreat | Firelight cozy vs forest daylight; winter vs green |
| Desert Luxe vs Tropical Escape | Dry artisanal earthen vs humid open-air resort; clay vs teak/rattan |

---

## Integration (how assets activate)

Drop any `ftue_*.jpg` file into this folder and hot-reload — no code changes needed.

**FTUE loading chain** (`_SpaceImage` in `onboarding_screen.dart`):
1. `ftueHeroImagePath` → `assets/atmospheres/ftue/ftue_{id}.jpg`
2. `fallbackImageUrl` → Unsplash network (last resort only)

Note: the `showcaseAsset` level is intentionally absent from the FTUE chain.
Showcase assets show different spaces and would break the same-space principle.
They remain in use only for the card hero fallback in `atmosphere_card.dart`.

**File naming:**
```
ftue_tropical_escape.jpg
ftue_warm_modern.jpg
ftue_japandi_calm.jpg
ftue_soft_luxury.jpg
ftue_nordic_warmth.jpg
ftue_nature_retreat.jpg
ftue_desert_luxe.jpg
```
