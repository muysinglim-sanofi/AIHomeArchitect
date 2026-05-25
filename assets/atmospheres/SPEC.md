# Atmosphere Asset Generation Spec

Source for generating all assets under `assets/atmospheres/`.

---

## TWO SEPARATE IMAGE SYSTEMS

### System A — Atmosphere Card Hero  (`{id}.jpg`)
Used in: upload/design direction selector, fullscreen reveal strip, chat design direction modal.
Shows: a strong, beautiful example of this atmosphere style applied to architecture.
Does NOT need to match any other atmosphere's space or composition.

### System B — FTUE Demo Hero  (`ftue_{id}.jpg`)
Used in: FTUE onboarding Screen 3 large hero area ONLY.
Shows: THE SAME BASELINE SPACE transformed into each different atmosphere.
Architecture, composition, and framing must be IDENTICAL across all 10.
Only the atmosphere style (materials, lighting, mood) changes between images.

**This is the core product proposition: "Same home. Infinite directions."**
Never substitute card heroes for FTUE heroes. They are different assets with different jobs.

---

## Core Rule (Both Systems)

Every image must depict **architecture** — an interior room, house/villa facade, or outdoor architectural space (terrace, garden, pool).

**Rejected content types — do not use:**
- People doing yoga, meditating, or modelling
- Sofa/furniture product shots without a room
- Generic nature landscapes without a building
- Grapes, food, abstract textures
- Stock lifestyle photography of any kind

No humans in any image.

---

## System A — Card Hero Images (`{id}.jpg`)

Format: JPG or WebP  
Resolution: 800 × 1050 px minimum (portrait ~4:5.25)  
File size: under 300 KB each  
Framing: full architectural space — not a cropped detail

---

### `tropical_escape.jpg`
Open-air tropical villa terrace or pool lounge. Rattan daybed. Teak floor. Volcanic stone details. Palms and lush garden at terrace edge. Warm golden late-afternoon light. Barefoot luxury resort feeling.

**AI prompt:** `luxury open-air tropical villa terrace, rattan daybed, teak floor, volcanic stone, lush tropical garden, palm canopy, golden afternoon light, no people, architectural photography, ultra-detailed, cinematic`

**Avoid:** beach stock, jungle-only, sunset silhouettes, people

---

### `warm_modern.jpg`
Warm contemporary living room or open-plan apartment. Curved sofa in warm linen or camel tone. Oak coffee table. Travertine side surfaces. Warm indirect pendant lighting. Beige/sand/oak palette.

**AI prompt:** `warm modern living room, curved linen sofa, oak coffee table, travertine surfaces, warm indirect pendant lighting, beige oak palette, soft shadows, architectural interior photography, no people, ultra-detailed`

**Avoid:** sofa product shots, sterile white rooms, cold minimalism

---

### `zen_retreat.jpg`
Japanese zen room. Tatami mat floor. Shoji paper screen with soft diffused daylight behind it. Low lacquered table. View toward a stone garden or bamboo. Near-monochrome palette.

**AI prompt:** `Japanese zen interior room, tatami floor, shoji screen, soft diffused daylight, low wooden table, stone garden view, pale grey cream palette, no people, architectural photography, ultra-detailed`

**Avoid:** yoga mats, meditation cushions with people, spa models

---

### `japandi_calm.jpg`
Minimal Japanese-Scandinavian bedroom or living room. Pale oak bed frame or low sofa. Handmade ceramic on floating shelf. Natural daylight from large window. Soft plaster walls. Very little decoration.

**AI prompt:** `Japandi interior room, pale oak furniture, white linen upholstery, soft plaster walls, minimal floating shelf with ceramic, natural window daylight, cream pale wood palette, no people, architectural interior photography, ultra-detailed`

**Avoid:** colourful cushions, maximalist decoration, generic western apartments

---

### `soft_luxury.jpg`
Quiet luxury hotel suite or elegant cream living room. Tufted upholstered headboard or curved cream sofa. Cream marble surfaces. Floor-length silk/linen curtains. Warm evening chandelier or sconce light dimmed low.

**AI prompt:** `quiet luxury hotel suite, cream marble, tufted upholstered headboard, curved cream sofa, silk floor-length curtains, warm evening sconce light, soft refined atmosphere, no people, architectural interior photography, ultra-detailed`

**Avoid:** flashy gold, over-decorated baroque, gaudy chandelier excess

---

### `nordic_warmth.jpg`
Scandinavian cozy living room. Stone or brick fireplace as focal point with warm fire glow. Light birch or pine furniture. Chunky knit throw on linen sofa. Sheepskin rug. Candles. Soft winter daylight.

**AI prompt:** `Scandinavian cozy living room, stone fireplace with warm fire, birch furniture, chunky knit throw, sheepskin rug, candles, soft winter daylight, hygge atmosphere, no people, architectural interior photography, ultra-detailed`

**Avoid:** IKEA showroom, isolated furniture without room context

---

### `dark_contemporary.jpg`
Dark contemporary luxury living room or suite. Black marble fireplace surround. Charcoal velvet sofa. Aged brass floor lamp. Parisian ceiling moulding. Low-key cinematic directional lighting.

**AI prompt:** `dark contemporary luxury living room, black marble fireplace, charcoal velvet sofa, aged brass floor lamp, Parisian moulding ceiling, cinematic directional lighting, high contrast, no people, architectural interior photography, ultra-detailed`

**Avoid:** gaming rooms, nightclubs, cyberpunk neon

---

### `nature_retreat.jpg`
Forest cabin or biophilic house interior. Massive floor-to-ceiling windows with pine or birch forest view. Raw wood and stone interior. Live-edge table. Trailing indoor plants or moss wall. Dappled forest daylight.

**AI prompt:** `biophilic forest cabin interior, floor-to-ceiling windows pine forest view, raw wood beams, stone floor, live-edge table, trailing plants, dappled daylight, no people, architectural photography, ultra-detailed`

**Avoid:** camping tents, hiking landscape only, tree-house cartoon aesthetic

---

### `desert_luxe.jpg`
Desert villa interior or terrace. Arched doorways in warm limestone or clay plaster. Sand-coloured curved walls. Hand-knotted rug on terracotta tiles. Cacti or dried botanicals. Desert sunset light through an arch.

**AI prompt:** `desert luxury villa interior, arched limestone doorway, warm clay plaster walls, terracotta tiles, hand-knotted rug, cactus, desert sunset light, no people, Moroccan luxury architecture photography, ultra-detailed`

**Avoid:** cowboy/western desert clichés, dry empty desert photography

---

## System B — FTUE Demo Hero Images (`ftue/ftue_{id}.jpg`)

Location: `assets/atmospheres/ftue/` (separate subdirectory)  
Full spec: see `assets/atmospheres/ftue/SPEC.md`

Format: JPG or WebP  
Resolution: 900 × 600 px minimum (landscape — fills FTUE hero container at full width)  
File size: under 250 KB each

**Critical requirement:** All 10 FTUE images must use THE SAME BASELINE ROOM.
The baseline room is a contemporary open-plan living room with floor-to-ceiling windows,
a rectangular fireplace opening, and a kitchen island visible in the background.
Architecture (walls, ceiling, window placement, camera angle, framing) stays identical.
Only materials, furniture language, lighting, and decorative atmosphere change.

**Fallback order used in code (two-level only):**
`ftue/ftue_{id}.jpg` → `fallbackImageUrl` (Unsplash)

The `showcaseAsset` level is intentionally excluded from the FTUE fallback chain.
Showcase assets show different spaces and would violate the same-space product principle.

**For detailed per-atmosphere generation prompts, see:**
`assets/atmospheres/ftue/SPEC.md`

---

## Icon Spec (`{id}_icon.png`)

Format: PNG with transparent background  
Size: 128 × 128 px (displayed at 28 × 28 pt — must be sharp at 3×)  
Style: Minimal line icon or flat symbol. No text. No humans.

| Atmosphere | Symbol |
|---|---|
| `tropical_escape_icon.png` | Palm frond + open pavilion roofline |
| `warm_modern_icon.png` | Rounded armchair + pendant lamp |
| `zen_retreat_icon.png` | Stacked stones + single bamboo stalk |
| `japandi_calm_icon.png` | Shoji screen grid + low table silhouette |
| `nordic_warmth_icon.png` | Fireplace arch + small flame |
| `dark_contemporary_icon.png` | Townhouse facade with chandelier in window |
| `nature_retreat_icon.png` | Cabin outline + pine tree |
| `desert_luxe_icon.png` | Pointed arch + cactus + sun arc |
| `soft_luxury_icon.png` | Elegant doorway arch + sconce lamp |

---

## Complete File Checklist

```
assets/atmospheres/
│
│  ── System A: Card hero images ──
├── tropical_escape.jpg
├── warm_modern.jpg
├── zen_retreat.jpg
├── japandi_calm.jpg
├── soft_luxury.jpg
├── nordic_warmth.jpg
├── dark_contemporary.jpg
├── nature_retreat.jpg
├── desert_luxe.jpg
│
│  ── System B: FTUE demo heroes (SAME SPACE, different atmospheres) ──
│   (lives in assets/atmospheres/ftue/ — see ftue/SPEC.md for full spec)
├── ftue/ftue_tropical_escape.jpg
├── ftue/ftue_warm_modern.jpg
├── ftue/ftue_zen_retreat.jpg
├── ftue/ftue_japandi_calm.jpg
├── ftue/ftue_soft_luxury.jpg
├── ftue/ftue_nordic_warmth.jpg
├── ftue/ftue_dark_contemporary.jpg
├── ftue/ftue_nature_retreat.jpg
└── ftue/ftue_desert_luxe.jpg
│
│  ── Icons ──
├── tropical_escape_icon.png
├── warm_modern_icon.png
├── zen_retreat_icon.png
├── japandi_calm_icon.png
├── soft_luxury_icon.png
├── nordic_warmth_icon.png
├── dark_contemporary_icon.png
├── nature_retreat_icon.png
└── desert_luxe_icon.png
```

Total: 27 files

---

## Quality Gate (before committing)

- [ ] No human subjects in any image
- [ ] Every card hero shows a complete architectural space
- [ ] All 9 FTUE heroes use the SAME baseline architecture
- [ ] No stock lifestyle photography
- [ ] Card heroes under 300 KB each
- [ ] FTUE heroes under 250 KB each
- [ ] Icons are 128 × 128 px with transparent background
- [ ] Icons sharp at 28 × 28 pt on 3× screen (84 × 84 px effective)
- [ ] All 27 files present with exact snake_case filenames

---

## Integration — How Assets Activate

Drop any file into `assets/atmospheres/` and hot-reload. No code changes needed.

**Card hero loading order** (`_AtmosphereHeroImage` in `atmosphere_card.dart`):
1. `heroImagePath` → `assets/atmospheres/{id}.jpg`
2. `showcaseAsset` → `assets/showcase/*_after.jpg` (4 atmospheres only, always present)
3. `fallbackImageUrl` → Unsplash network

**FTUE hero loading order** (`_SpaceImage` in `onboarding_screen.dart`):
1. `ftueHeroImagePath` → `assets/atmospheres/ftue/ftue_{id}.jpg`
2. `fallbackImageUrl` → Unsplash network
(showcaseAsset excluded — different spaces violate the same-space principle)

**These two systems are completely separate.** Card thumbnails never appear in the FTUE hero, and FTUE heroes never appear in the card grid.

**Screens using `AtmosphereCard` (System A):**
1. Upload / Design Direction sheet (`upload_screen.dart`, `chat_screen.dart`)
2. Fullscreen reveal atmosphere strip (`before_after_screen.dart`)
3. FTUE Screen 3 card strip (`onboarding_screen.dart`) — compact 100 × 140 pt

**Screen using FTUE hero (System B):**
1. FTUE Screen 3 large hero only (`onboarding_screen.dart`)
