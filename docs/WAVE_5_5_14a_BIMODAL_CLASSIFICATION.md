# Wave 5.5.14a — Bimodal Architecture vs Decoration Classification

**Date:** 2026-05-23
**Scope:** Per-atmosphere classification of every DNA phrase as 🔴 ARCHITECTURE (strip in preservation mode) or 🟢 DECORATION (keep in preservation mode).
**Companion doc:** [WAVE_5_5_14a_DNA_AUDIT.md](WAVE_5_5_14a_DNA_AUDIT.md) — diagnostic + cross-atmosphere summary.

---

## Intent

Build a **bimodal generation system** with two prompt-assembly paths:

| Mode | DNA content | Preservation voices | Trigger |
|---|---|---|---|
| **Preservation (default)** | Decoration-only (architectural tokens stripped) | Active (3-voice boundary + CAMERA LOCK + STRUCTURAL LOCK + STRUCTURAL IDENTITY) | Standard generation, atmosphere switching, redesign flow |
| **Creative** | Full DNA revived (architectural_language, room_specific_constraints reinjected) | Relaxed or dropped | Surprise Me path |

This document is the **classification source-of-truth** that an implementation would consume to know what to strip vs keep per atmosphere.

---

## Classification rules

🔴 **ARCHITECTURE** = phrase touches geometry, topology, openings, scale-of-room, proportions, ceiling form, wall positioning, floor plan, opening-direction (indoor-outdoor), pavilion/volume language, opening verbs ("open side to…").

🟢 **DECORATION** = materials, lighting fixtures, furniture pieces, decor objects, colours, textures, mood/emotion words, anti-clichés, scale-of-furniture (height in cm, residential scale).

🟨 **MIXED / borderline** = explicit call-out with reasoning.

**Anti-bias rule:** Phrases that *prevent* architecture drift (e.g. "no cold grey minimalism", "Empty sterile minimalism" in `forbidden_elements`) stay in DECORATION because they protect against unwanted spatial expansion.

---

## 1. Tropical Escape (🟧 MED-HIGH bias)

### CORE DNA

| Field | 🔴 ARCHITECTURE | 🟢 DECORATION |
|---|---|---|
| `philosophy` | **"Open-air"** | "tropical living with relaxed contemporary luxury" |
| `emotional_intent` | "breezy" 🟨 | "alive, relaxed-luxurious, sun-soaked, carefree but refined, vibrant-calm" |
| `architectural_language` *(dead — revived in creative mode)* | **"Open-plan volumes dissolving into landscape"** | "tropical timber and whitewash, with a contemporary residential ease" |
| `material_palette` | — | whitewashed walls, tropical hardwood, concrete floor, natural rattan, linen/cotton white-sage |
| `lighting_behavior` | — | "Warm natural ambient — daytime brightness, warm concealed evening coves, rattan pendant lanterns" |
| `luxury_level` | — | "Contemporary tropical villa" |
| `forbidden_elements` | — | Beach clichés, fake resort styling, overdecorated tropical kitsch, bamboo overuse, nautical/coastal motifs |
| `atmosphere_keywords` *(dead)* | "open-air luxury" | tropical villa, whitewash, louvred timber, rattan |

### ROOM DNA — Living Room

| Field | 🔴 ARCHITECTURE | 🟢 DECORATION |
|---|---|---|
| `furniture_language` | — | rattan/cane with white linen, concrete/pale stone, louvred timber |
| `material_palette` | — | polished concrete/pale stone floor, white render walls, louvred timber panels |
| `lighting_behavior` | — | "Warm rattan pendant + concealed warm ceiling slot; bright in day, warm in evening" |
| `decor_language` | — | tropical plant in concrete pot, woven rattan tray |
| `realism_constraints` | — | "sofa at normal residential height — 45 cm", concrete floor texture correct |
| `room_specific_constraints` *(dead)* | **"open side to terrace or garden — tropical villa character"** | "plant as living room's primary accent — one large specimen" |
| `visible_transition_logic` | **"continue into terrace"** (verb implies opening) | white walls, concrete floor, rattan furniture palette echoes outdoor seating |
| `negative_rules` | — | no dark tropical furniture, no nautical motifs, no shell/driftwood, no overly lush plant collection |

### Cross-room architecture leaks

- **Bathroom** `negative_rules`: **"no closed cabinet-heavy bathroom"** (anti-closing) + `room_specific_constraints` (dead): **"open or semi-open if villa allows"**
- **Kitchen** `room_specific_constraints` (dead): **"open shelf mandatory — no upper cabinets to ceiling"** (anti-wall)
- **Dining** `negative_rules`: **"no enclosed dining room feel"**, `room_specific_constraints` (dead): **"open side to terrace or garden if space allows"**
- **Terrace** `room_specific_constraints` (dead): **"outdoor seating facing garden or pool — open orientation"**
- **Facade** `decor_language`: **"louvred shutters as architectural facade element"** (architectural element)

### Preservation-mode output (architecture stripped)

```
ATMOSPHERE (Tropical Escape): Tropical living with relaxed contemporary luxury — alive, relaxed-luxurious, sun-soaked, carefree but refined, vibrant-calm. [Contemporary tropical villa]
ROOM (Living Room): polished concrete or pale stone floor, white render walls, louvred timber panels. LIGHT: Warm rattan pendant + concealed warm ceiling slot; bright in day, warm in evening. ATMOSPHERE STYLE (restyle existing elements): natural rattan or cane with thick white linen; concrete or pale stone; louvred timber; single large tropical plant in concrete pot; woven rattan tray on coffee table. REALISM: sofa at normal residential height — 45 cm; concrete floor with correct texture. AVOID: no dark tropical furniture, no nautical motifs, no shell or driftwood decor, Beach clichés, fake resort styling.
```

### Creative-mode output (full DNA revived)

```
ATMOSPHERE (Tropical Escape): Open-air tropical living with relaxed contemporary luxury — Breezy, alive, relaxed-luxurious, sun-soaked, carefree but refined, vibrant-calm. Open-plan volumes dissolving into landscape, tropical timber and whitewash, with a contemporary residential ease. [Contemporary tropical villa]
ROOM (Living Room): [as above] + open side to terrace or garden — tropical villa character; plant as living room's primary accent — one large specimen.
```

---

## 2. Zen Retreat (🟧 MEDIUM bias)

### CORE DNA

| Field | 🔴 ARCHITECTURE | 🟢 DECORATION |
|---|---|---|
| `philosophy` | **"Meditative architectural silence"** ("architectural" is the only direct word) | "and visual restraint" |
| `emotional_intent` | **"emptied"** 🟨 (direct emptiness directive) | meditative, still, contemplative, restorative, deeply calm |
| `architectural_language` *(dead)* | **"Spatial emptiness as architectural intention, … light as the primary design element"** | "natural material austerity" |
| `material_palette` | — | grey/white wabi plaster, dark slate/basalt stone, pale unfinished timber, natural rush/tatami, water as surface |
| `lighting_behavior` | — | "Near-darkness punctuated by single warm shafts — skylights, candles, narrow wall slots" |
| `luxury_level` | — | "Private Japanese retreat" |
| `forbidden_elements` | — | Decor clutter, fake spa styling, yoga studio clichés, ultra modern tech minimalism, over-styled emptiness |
| `atmosphere_keywords` *(dead)* | **"architectural silence"** | meditative, wabi plaster, basalt, stillness |

### ROOM DNA — Living Room

| Field | 🔴 ARCHITECTURE | 🟢 DECORATION |
|---|---|---|
| `furniture_language` | — | unbleached linen, slate/basalt stone, rush/jute |
| `material_palette` | — | grey slate floor, grey wabi plaster walls, unfinished pale timber accents |
| `lighting_behavior` | — | "Single narrow skylight beam + one floor-level warm candle or lantern; room near-dark" |
| `decor_language` | — | one stone/ceramic vessel — empty, single branch/stone arrangement on floor |
| `realism_constraints` | **"floor space dominant — furniture minimal"** | "furniture low enough to feel floored — 35–40 cm seats" |
| `room_specific_constraints` *(dead)* | — | "maximum 2 furniture pieces in room", "zero wall decoration — walls bare plaster only" |
| `visible_transition_logic` | — | slate floor and grey plaster continue uninterrupted through adjacent rooms; no material change at thresholds |
| `negative_rules` | — | no throw pillows or cushion styling, no plants, no wall art, no technology visible |

### Cross-room architecture leaks

- **Bedroom** `realism_constraints`: **"sleeping platform at floor or near-floor level — 15–25 cm"** 🟨 (extreme height = floor culture, could be read as topology)
- **Bathroom** `room_specific_constraints` (dead): **"no vanity cabinet — basin on stone slab or wall-supported"** (anti-cabinet)
- **Kitchen** `realism_constraints`: **"countertop empty — nothing on surface except one intentional object"** 🟨 (anti-clutter, mild)
- **Terrace** `room_specific_constraints` (dead): **"no furniture in Western sense — platform and ground only"**, **"open sky visible — no overhead shade"**
- **Driveway** `room_specific_constraints` (dead): **"no gate — open entry, marked by stone"** (anti-gate)
- **Dining** `room_specific_constraints` (dead): **"floor dining only — no chairs"** 🟨 (furniture topology — no chairs implies floor-level living)

### Preservation-mode output

```
ATMOSPHERE (Zen Retreat): Meditative silence and visual restraint — meditative, still, contemplative, restorative, deeply calm. [Private Japanese retreat]
ROOM (Living Room): large-format grey slate floor, grey wabi plaster walls, unfinished pale timber accents. LIGHT: Single narrow skylight beam + one floor-level warm candle or lantern; room near-dark. ATMOSPHERE STYLE: natural unbleached linen; flat slate or basalt stone; neutral rush or jute; one stone or ceramic vessel — empty; single branch or stone arrangement on floor. REALISM: furniture low enough to feel floored — 35–40 cm seats. AVOID: no throw pillows or cushion styling, no plants, no wall art, Decor clutter, fake spa styling.
```

### Creative-mode output (architectural directives revived)

Adds back: "architectural silence", "Spatial emptiness as architectural intention, light as the primary design element", "floor space dominant — furniture minimal", and "emptied" emotion.

---

## 3. Bali Sanctuary (🟧 MEDIUM bias — DO NOT DILUTE per matrix)

### CORE DNA

| Field | 🔴 ARCHITECTURE | 🟢 DECORATION |
|---|---|---|
| `philosophy` | **"sanctuary"** 🟨 (spatial-emotional, mild) | "Luxury tropical inspired by refined Balinese hospitality" |
| `emotional_intent` | — | sacred, immersive, lush, warm, ceremonially refined, deeply restful |
| `architectural_language` *(dead)* | **"Open-pavilion volumes with alang-alang or timber ceilings, … indoor-outdoor dissolving boundaries"** | "volcanic stone, tropical timber" |
| `material_palette` | — | volcanic grey stone, reclaimed teak/ironwood, alang-alang thatch or timber plank ceiling, handwoven textiles, tropical hardwood |
| `lighting_behavior` | — | "Warm concealed uplights behind stone features, pendant lanterns in brass or rattan, candlelight" |
| `luxury_level` | — | "Luxury Bali resort villa" |
| `forbidden_elements` | — | Tiki bar aesthetics, beach resort kitsch, bamboo overuse, fake tropical props, tourist souvenir styling |
| `atmosphere_keywords` *(dead)* | **"open pavilion"** | balinese, volcanic stone, teak, tropical sacred |

### ROOM DNA — Living Room

| Field | 🔴 ARCHITECTURE | 🟢 DECORATION |
|---|---|---|
| `furniture_language` | — | teak with cotton in indigo/stone, volcanic stone/carved timber, woven rattan/handwoven textile |
| `material_palette` | — | volcanic grey stone or polished terrazzo floor, reclaimed teak joinery and ceiling structure, handwoven cotton/linen upholstery |
| `lighting_behavior` | — | "Concealed warm uplights behind stone wall feature + rattan or brass pendant lantern" |
| `decor_language` | — | single large stone/clay vessel with tropical foliage, woven wall hanging |
| `realism_constraints` | — | "sofa low — 40–45 cm — Balinese floor-culture scale", stone floor texture |
| `room_specific_constraints` *(dead)* | **"open side to garden or pool — pavilion character"** | "maximum 2 decorative objects plus one plant" |
| `visible_transition_logic` | **"continue into adjacent pavilion"**, **"open living pavilion"** | volcanic stone floor and teak ceiling continue, stone palette echoes through visible pool area |
| `negative_rules` | — | no bamboo furniture, no bright tropical colour, no tourist ornament collection, no cold modern surfaces |

### Cross-room architecture leaks

- **Bedroom** `room_specific_constraints` (dead): **"four-poster bed as room's defining element"** 🟨 (furniture as architectural element — borderline DECORATION since it's a piece, not geometry)
- **Bathroom** `furniture_language`: **"open-air or semi-open wet room"** + `room_specific_constraints` (dead): **"open or semi-open shower — no full enclosure in pavilion bathroom"**, **`visible_transition_logic`: "garden or tropical foliage visible from open bathroom side"**
- **Kitchen** `room_specific_constraints` (dead): **"open shelf mandatory — no upper cabinets to ceiling"**
- **Terrace** `furniture_language`: implicit pavilion structure; `visible_transition_logic`: **"teak ceiling extends from indoor living room"** (ceiling continuity = architecture)
- **Pool** `room_specific_constraints` (dead): **"palm thatch or teak shade pavilion — not canvas parasol"** (architectural form)
- **Facade** `room_specific_constraints` (dead): **"volcanic stone as primary facade material"** + **"carved entrance feature"** (architectural elements)

### Preservation-mode output

Strip every "pavilion", "open side to…", "open-air bathroom", "ceiling extends".

```
ATMOSPHERE (Bali Sanctuary): Luxury tropical inspired by refined Balinese hospitality — sacred, immersive, lush, warm, ceremonially refined, deeply restful. [Luxury Bali resort villa]
ROOM (Living Room): volcanic grey stone or polished terrazzo floor, reclaimed teak joinery and ceiling structure, handwoven cotton or linen upholstery. LIGHT: Concealed warm uplights behind stone wall feature + rattan or brass pendant lantern. ATMOSPHERE STYLE: teak or tropical hardwood with cotton in indigo or stone; volcanic stone or carved timber; woven rattan or handwoven textile; single large stone or clay vessel with tropical foliage; woven wall hanging in natural undyed textile. REALISM: sofa low — 40–45 cm; stone floor with correct texture — not hyper-polished CGI. AVOID: no bamboo furniture, no bright tropical colour, no tourist ornament collection, Tiki bar aesthetics, beach resort kitsch.
```

### Creative-mode output

Reinject: "Open-pavilion volumes with alang-alang or timber ceilings, indoor-outdoor dissolving boundaries", "open side to garden or pool — pavilion character", "open living pavilion", "teak ceiling extends from indoor".

---

## 4. Desert Luxe (🟧 MEDIUM bias)

### CORE DNA

| Field | 🔴 ARCHITECTURE | 🟢 DECORATION |
|---|---|---|
| `philosophy` | **"desert architecture and sculptural calm"** 🟨 (architectural-aspirational) | "Middle Eastern contemporary luxury" |
| `emotional_intent` | **"sculptural"**, **"monumental"** | warm, serene, sun-bleached, timelessly opulent |
| `architectural_language` *(dead)* | **"Monolithic forms in sand and terracotta, deep shadow reveals"** | "tactile plaster surfaces referencing desert vernacular" |
| `material_palette` | — | sand-toned tadelakt/micro-cement plaster, warm terracotta/sandstone, walnut/cedar timber, hammered brass/copper, raw cotton/camel leather |
| `lighting_behavior` | — | "Warm low-angled light — concealed slots mimicking desert sun raking, hammered metal lanterns" |
| `luxury_level` | — | "Dubai penthouse / Aman desert resort" |
| `forbidden_elements` | — | Theme park Morocco styling, excessive ornamentation, oversaturated orange tones, arabesque pattern overuse, fake gold |
| `atmosphere_keywords` *(dead)* | **"desert monolith"** | tadelakt, sandstone, hammered brass, sculptural warmth |

### ROOM DNA — Living Room

| Field | 🔴 ARCHITECTURE | 🟢 DECORATION |
|---|---|---|
| `furniture_language` | — | raw cotton or camel leather, solid sandstone or terracotta, carved wood |
| `material_palette` | — | polished tadelakt floor, tadelakt plaster walls, walnut/cedar timber accents |
| `lighting_behavior` | — | "Single hammered brass pendant + concealed warm floor slot" |
| `decor_language` | — | single large dark ceramic vessel — empty, woven camel/natural textile throw on sofa |
| `realism_constraints` | — | "sofa low — 40–45 cm — correct desert floor culture scale", plaster texture visible |
| `room_specific_constraints` *(dead)* | — | "no pattern on walls — tadelakt is the texture", "maximum 2 decorative objects in room" |
| `visible_transition_logic` | — | tadelakt floor and plaster walls continue into adjacent rooms |
| `negative_rules` | — | no arabesque tile pattern, no cold marble, no bright orange, no maximalist Moroccan styling |

### Cross-room architecture leaks

- **Facade** `furniture_language`: **"monolithic smooth tadelakt or sand render facade"**, **"deep-set window reveals casting shadow lines"** (opening proportion directive); `room_specific_constraints` (dead): **"single facade material — tadelakt render only"**, **"no decorative elements on facade — mass is the design"**
- **Bathroom** `furniture_language`: **"full tadelakt wet room — walls and floor continuous"** (wet-room topology); `room_specific_constraints` (dead): **"tadelakt throughout — no mixed surface"**
- **Dining** `furniture_language`: **"large sandstone or warm timber dining table — solid monolithic slab"** 🟨 (monolithic refers to table material, not architecture — DECORATION)

### Preservation-mode output

Strip "monumental", "sculptural" from `emotional_intent`; strip dead `architectural_language` "Monolithic forms" entirely; strip facade architectural directives.

```
ATMOSPHERE (Desert Luxe): Middle Eastern contemporary luxury — warm, serene, sun-bleached, timelessly opulent. [Dubai penthouse / Aman desert resort]
ROOM (Living Room): polished tadelakt floor in sand or warm ivory, tadelakt plaster walls in terracotta or warm sand, walnut or cedar timber accents. LIGHT: Single hammered brass pendant + concealed warm floor slot; low-angled warm glow. ATMOSPHERE STYLE: raw cotton or camel leather; solid sandstone or terracotta; carved wood; single large dark ceramic vessel — empty; woven camel or natural textile throw on sofa. REALISM: sofa low — 40–45 cm — correct desert floor culture scale; plaster texture visible — not flat paint. AVOID: no arabesque tile pattern, no cold marble, no bright orange, Theme park Morocco styling, excessive ornamentation.
```

### Creative-mode output

Reinject "sculptural, monumental" emotion + "Monolithic forms in sand and terracotta, deep shadow reveals" + "deep-set window reveals casting shadow lines" + "single facade material — tadelakt render only".

---

## 5. Japandi Calm (🟧 MEDIUM bias — HIGH priority calibration target)

### CORE DNA

| Field | 🔴 ARCHITECTURE | 🟢 DECORATION |
|---|---|---|
| `philosophy` | — | "Japanese restraint blended with Scandinavian softness and emotional calm" |
| `emotional_intent` | **"breathable"** 🟨 (mild spatial) | still, serene, grounded, quietly refined, unhurried |
| `architectural_language` *(dead)* | **"Low-profile horizontal forms, deliberate negative space in clean residential volumes"** | "natural material honesty" |
| `material_palette` | — | pale ash/birch, wabi-sabi plaster, dark charcoal ceramic, natural linen, honed dark stone |
| `lighting_behavior` | — | "Soft diffused ambient — paper lanterns, concealed warm slots; no bright downlights" |
| `luxury_level` | — | "Quiet luxury boutique hospitality" |
| `forbidden_elements` | — | Empty sterile minimalism, sci-fi white spaces, excessive decor, fake zen clichés, bamboo overuse |
| `atmosphere_keywords` *(dead)* | **"negative space"** 🟨 | japandi, wabi-sabi, natural honesty, quiet luxury |

### ROOM DNA — Living Room

| Field | 🔴 ARCHITECTURE | 🟢 DECORATION |
|---|---|---|
| `furniture_language` | — | natural linen in stone/fog tones, wabi-sabi ceramic or ash, natural rush or jute |
| `material_palette` | — | pale ash/birch floor, wabi-sabi plaster walls in off-white or putty, dark charcoal ceramic accents |
| `lighting_behavior` | — | "Paper lantern pendant + concealed warm floor slot; no harsh downlights" |
| `decor_language` | — | single branch in handmade ceramic vase, one framed Japanese ink artwork |
| `realism_constraints` | **"empty floor space is deliberate, not absent"** | "sofa low enough to feel grounded — 40–45 cm seat height" |
| `room_specific_constraints` *(dead)* | — | "maximum 3 decorative objects in room", "solid neutral rug or no rug — no pattern" |
| `visible_transition_logic` | — | pale ash floor and plaster walls extend into adjacent rooms; ceramic palette echoes through visible kitchen |
| `negative_rules` | — | no cluttered surfaces, no patterned textiles, no warm-orange wood tones, no cold grey minimalism |

### Cross-room architecture leaks

- **Bedroom** `realism_constraints`: **"platform bed at correct low height — 35–40 cm"** 🟨 (extreme height); `room_specific_constraints` (dead): **"no TV in bedroom"**, **"single artwork or none — wall left deliberately spare"**
- **Kitchen** `room_specific_constraints` (dead): **"no upper cabinets to ceiling — open shelf break preferred"** (anti-wall)
- **Bathroom** `furniture_language`: **"frameless glass shower partition"** (low-glass partition = architecture); `room_specific_constraints` (dead): — none architectural
- **Entrance** `room_specific_constraints` (dead): — none architectural
- **Office** `furniture_language`: **"wall-mounted ash floating desk — no legs"**, **"single floating ash shelf above desk"** 🟨 (furniture cantilever — borderline architecture but reads as furniture style)

### Preservation-mode output

Strip "breathable", strip "empty floor space is deliberate, not absent", strip "no upper cabinets to ceiling".

```
ATMOSPHERE (Japandi Calm): Japanese restraint blended with Scandinavian softness and emotional calm — still, serene, grounded, quietly refined, unhurried. [Quiet luxury boutique hospitality]
ROOM (Living Room): pale ash or birch floor, wabi-sabi plaster walls in off-white or putty, dark charcoal ceramic accents. LIGHT: Paper lantern pendant + concealed warm floor slot; no harsh downlights. ATMOSPHERE STYLE: natural linen in stone or fog tones; wabi-sabi ceramic or ash; natural rush or jute; single branch in handmade ceramic vase; one framed Japanese ink artwork. REALISM: sofa low enough to feel grounded — 40–45 cm seat height. AVOID: no cluttered surfaces, no patterned textiles, no warm-orange wood tones, Empty sterile minimalism, sci-fi white spaces.
```

### Creative-mode output

Reinject "breathable" emotion + "Low-profile horizontal forms, deliberate negative space in clean residential volumes" + "empty floor space is deliberate, not absent" + "no upper cabinets to ceiling".

---

## 6. Warm Modern (🟩 LOW bias)

### CORE DNA

| Field | 🔴 ARCHITECTURE | 🟢 DECORATION |
|---|---|---|
| `philosophy` | — | "Warm contemporary luxury rooted in emotional comfort, hospitality, softness, and believable urban premium living" |
| `emotional_intent` | — | comforting, refined, welcoming, calm, premium, elegant but livable |
| `architectural_language` *(dead)* | **"Organic forms softened by curves, … layered indirect light in residential-scale spaces"** ("residential-scale" is mild scale directive) | "warm-toned natural materials, indirect light" |
| `material_palette` | — | European oak, travertine, warm sand plaster, brushed brass, warm linen |
| `lighting_behavior` | — | "Warm indirect — concealed coves, tungsten-glow table lamps, no cold or harsh sources" |
| `luxury_level` | — | "Boutique hotel / premium urban residence" |
| `forbidden_elements` | — | Cold minimalism, sterile white interiors, ultra glossy marble overload, fake luxury gold, overdecorated styling |
| `atmosphere_keywords` *(dead)* | — | warm contemporary, boucle, travertine, oak, indirect warmth |

### ROOM DNA — Living Room

| Field | 🔴 ARCHITECTURE | 🟢 DECORATION |
|---|---|---|
| `furniture_language` | — | bouclé in oat or camel, travertine with brass/oak accent, warm linen |
| `material_palette` | — | wide-plank European oak floor, warm sand plaster walls, travertine slab surfaces |
| `lighting_behavior` | — | "Concealed ceiling cove + tungsten-glow table lamps; warm evening tone" |
| `decor_language` | — | oversized ceramic vessel on floating oak shelf, floor-length warm linen curtains |
| `realism_constraints` | — | "sofa at residential scale — not model-set proportions", "furniture legs visible and grounded on floor" |
| `room_specific_constraints` *(dead)* | — | "seating in conversation grouping, not TV-facing row", "single clear focal wall — fireplace or artwork, not both" |
| `visible_transition_logic` | — | oak floor and warm plaster continue into adjacent rooms; brass accents echo across visible kitchen/hallway |
| `negative_rules` | — | no cold grey palette, no chrome hardware, no matching 3-piece suite, no floating furniture without visible support |

### Cross-room architecture leaks

**None significant.** Warm Modern is the cleanest decoration-only atmosphere. Even `architectural_language` (dead) only mentions "residential-scale spaces" which is mild and anti-bias (prevents oversizing).

### Preservation-mode output (same as today — no stripping needed)

```
ATMOSPHERE (Warm Modern): Warm contemporary luxury rooted in emotional comfort, hospitality, softness, and believable urban premium living — comforting, refined, welcoming, calm, premium, elegant but livable. [Boutique hotel / premium urban residence]
ROOM (Living Room): wide-plank European oak floor, warm sand plaster walls, travertine slab surfaces. LIGHT: Concealed ceiling cove + tungsten-glow table lamps; warm evening tone. ATMOSPHERE STYLE: bouclé in oat or camel — warm curved tactile richness; travertine — warm stone surface depth with brass or oak accent; warm linen — oak-toned textural warmth; oversized ceramic vessel on floating oak shelf; floor-length warm linen curtains. REALISM: sofa at residential scale — not model-set proportions; furniture legs visible and grounded on floor. AVOID: no cold grey palette, no chrome hardware, no matching 3-piece suite, Cold minimalism, sterile white interiors.
```

### Creative-mode output

Adds "Organic forms softened by curves, layered indirect light in residential-scale spaces" + room-specific constraints. Minimal delta — Warm Modern's identity is already decoration-driven.

---

## 7. Soft Luxury (🟩 LOW bias — reference atmosphere DO NOT DILUTE)

### CORE DNA

| Field | 🔴 ARCHITECTURE | 🟢 DECORATION |
|---|---|---|
| `philosophy` | — | "Refined hospitality luxury emphasizing softness, elegance, tactile richness, and timeless sophistication" |
| `emotional_intent` | — | indulgent, serene, tactile, quietly opulent, feminine-refined, sensorially rich |
| `architectural_language` *(dead)* | **"Curved forms and soft volumes, … silk-to-stone material transitions in generous proportions"** ("generous proportions" = scale directive) | "layered textured surfaces" |
| `material_palette` | — | fluted ivory plaster, bouclé/cashmere textiles, honed marble in cream/blush, brushed champagne metal, raw silk/velvet |
| `lighting_behavior` | — | "Warm diffused glow — concealed perimeter coves, silk lampshades, no exposed bulbs" |
| `luxury_level` | — | "Rosewood / Aman / luxury suite" |
| `forbidden_elements` | — | Bling luxury, crystal chandelier clichés, fake palace aesthetics, excessive gold, hard-edge minimalism |
| `atmosphere_keywords` *(dead)* | — | soft luxury, bouclé, fluted plaster, ivory, tactile refinement |

### ROOM DNA — Living Room

| Field | 🔴 ARCHITECTURE | 🟢 DECORATION |
|---|---|---|
| `furniture_language` | — | warm bouclé in ivory/blush, honed marble or stone with champagne brass, cashmere/velvet in cream |
| `material_palette` | — | fluted ivory plaster walls, honed cream marble floor, brushed champagne metal accents |
| `lighting_behavior` | — | "Concealed perimeter cove + silk shade floor lamps; warm evening tone" |
| `decor_language` | — | oversized ceramic vessel with dried pampas/lunaria, layered silk/bouclé cushions in cream/blush |
| `realism_constraints` | — | "sofa sized to room — not oversized for space", "marble floor with correct 3–5 mm grout lines" |
| `room_specific_constraints` *(dead)* | **"seating centred on focal element — fireplace or art wall"**, **"symmetry in furniture placement — not haphazard"** 🟨 (composition directive borderline) | — |
| `visible_transition_logic` | — | ivory plaster walls and marble floor flow continuously into dining and hallway |
| `negative_rules` | — | no jewel-tone colour pops, no gold leaf, no asymmetric art gallery wall, no visible TV above fireplace |

### Cross-room architecture leaks

- **Garden** `room_specific_constraints` (dead): **"formal symmetry in layout — not naturalistic garden style"** (topology)
- **Pool** `room_specific_constraints` (dead): **"symmetrical layout — not scattered"** (topology)
- **Facade** `furniture_language`: **"arched or elegant window profiles"** (opening shape); `room_specific_constraints` (dead): **"entrance canopy or porch if present in classical proportions"**

### Preservation-mode output

Strip "generous proportions" from dead arch_language (if revived); strip facade "arched window profiles" if injected; strip "symmetry in furniture placement" from rooms where present.

```
ATMOSPHERE (Soft Luxury): Refined hospitality luxury emphasizing softness, elegance, tactile richness, and timeless sophistication — indulgent, serene, tactile, quietly opulent, feminine-refined, sensorially rich. [Rosewood / Aman / luxury suite]
ROOM (Living Room): fluted ivory plaster walls, honed cream marble floor, brushed champagne metal accents. LIGHT: Concealed perimeter cove + silk shade floor lamps; warm evening tone, no ceiling spotlights. ATMOSPHERE STYLE: warm bouclé in ivory or blush; honed marble or stone with champagne brass; cashmere or velvet in cream; oversized ceramic vessel with dried pampas or lunaria; layered silk and bouclé cushions. REALISM: sofa sized to room — not oversized for space; marble floor with correct 3–5 mm grout lines. AVOID: no jewel-tone colour pops, no gold leaf or metallic wallpaper, no asymmetric art gallery wall, Bling luxury, crystal chandelier clichés.
```

### Creative-mode output

Adds "Curved forms and soft volumes, generous proportions" + "arched window profiles" on facade + symmetry directives.

---

## 8. Dark Contemporary (🟩 LOW bias — reference atmosphere DO NOT DILUTE)

### CORE DNA

| Field | 🔴 ARCHITECTURE | 🟢 DECORATION |
|---|---|---|
| `philosophy` | **"Architectural sophistication"** 🟨 (metaphor) | "through depth, contrast, material richness, and restraint" |
| `emotional_intent` | **"architecturally confident"** 🟨 | dramatic, sophisticated, powerful, sensory, moody but refined |
| `architectural_language` *(dead)* | **"Deep tonal volumes with high-contrast material surfaces, … gallery-level spatial control"** | "concealed warm light" |
| `material_palette` | — | dark charcoal plaster, black/dark grey marble, smoked oak/wenge, brushed bronze/gunmetal, concrete |
| `lighting_behavior` | — | "Concealed precision lighting — warm glow against dark surfaces; darkness as design element" |
| `luxury_level` | — | "Contemporary penthouse luxury" |
| `forbidden_elements` | — | Nightclub atmosphere, cyberpunk lighting, black void interiors, aggressive contrast, horror-dark rooms |
| `atmosphere_keywords` *(dead)* | — | dark luxury, charcoal plaster, smoked oak, bronze, precision light |

### ROOM DNA — Living Room

| Field | 🔴 ARCHITECTURE | 🟢 DECORATION |
|---|---|---|
| `furniture_language` | — | dark charcoal bouclé/leather, dark marble/stone, dark velvet |
| `material_palette` | — | dark charcoal plaster walls, smoked oak or dark stone floor, dark marble or bronze accent surfaces |
| `lighting_behavior` | — | "Concealed warm ceiling cove + single sculptural bronze floor lamp; room lit by glow, not flood" |
| `decor_language` | — | large-scale abstract artwork in dark/muted tones, single sculptural ceramic vessel |
| `realism_constraints` | — | "sofa sized correctly", "floor in correct proportion — wood grain or stone texture visible" |
| `room_specific_constraints` *(dead)* | — | "artwork as single focal wall — not gallery cluster", "balanced dark-to-warm lighting ratio — not pure darkness" |
| `visible_transition_logic` | — | charcoal plaster and smoked oak floor continue into adjacent rooms |
| `negative_rules` | — | no all-black room, no neon/coloured accent light, no chrome or silver hardware, no grey rather than charcoal |

### Cross-room architecture leaks

- **Bedroom** `room_specific_constraints` (dead): **"no decorative ceiling feature — ceiling plain dark"** (ceiling treatment)
- **Facade** `furniture_language`: **"steel or concrete cantilevered canopy at entrance"** (architectural element), **"pivot door"** (opening type); `room_specific_constraints` (dead): **"no visible entrance porch — canopy only"**
- **Bathroom** `furniture_language`: **"floating dark stone or concrete vanity top with recessed basin"** 🟨 (furniture cantilever — borderline DECORATION)

### Preservation-mode output

Strip "Architectural sophistication" → "Sophistication"; strip "architecturally confident" → "confident"; strip dead arch_language "Deep tonal volumes … gallery-level spatial control"; strip facade architectural element directives.

```
ATMOSPHERE (Dark Contemporary): Sophistication through depth, contrast, material richness, and restraint — dramatic, sophisticated, powerful, sensory, moody but refined, confident. [Contemporary penthouse luxury]
ROOM (Living Room): dark charcoal plaster walls, smoked oak or dark stone floor, dark marble or bronze accent surfaces. LIGHT: Concealed warm ceiling cove + single sculptural bronze floor lamp; room lit by glow, not flood. ATMOSPHERE STYLE: dark charcoal bouclé or leather — deep low tactile richness; dark marble or stone — sculptural surface depth; dark velvet — high-contrast atmospheric depth; large-scale abstract artwork in dark or muted tones; single sculptural ceramic vessel in dark or metallic finish. REALISM: sofa sized correctly — not modelling-scale oversized; floor in correct proportion — wood grain or stone texture visible. AVOID: no all-black room, no neon or coloured accent light, no chrome or silver hardware, Nightclub atmosphere, cyberpunk lighting.
```

### Creative-mode output

Adds "Architectural sophistication" + "architecturally confident" + "Deep tonal volumes with high-contrast material surfaces, gallery-level spatial control" + facade "cantilevered canopy".

---

## 9. Nature Retreat (🟩 LOW bias)

### CORE DNA

| Field | 🔴 ARCHITECTURE | 🟢 DECORATION |
|---|---|---|
| `philosophy` | **"architectural realism"** 🟨 (borderline) | "Biophilic calm integrated with earthy luxury" |
| `emotional_intent` | — | grounded, alive, restorative, earthy, connected to nature, quietly luxurious |
| `architectural_language` *(dead)* | **"… in architecturally resolved proportions"** 🟨 | "Organic materiality — raw stone, reclaimed timber, living plant integration" |
| `material_palette` | — | reclaimed oak/elm timber, rough-cut stone/slate, rammed earth/clay plaster, jute/natural linen, living moss/plant wall |
| `lighting_behavior` | — | "Warm diffused natural-adjacent light — concealed warm slots, timber-shaded pendants, candlelight" |
| `luxury_level` | — | "Luxury eco retreat" |
| `forbidden_elements` | — | Fake jungle overload, plant spam, tropical theme park aesthetics, synthetic/artificial materials, sterile minimalism |
| `atmosphere_keywords` *(dead)* | — | biophilic, reclaimed oak, rammed earth, living plant, earthy luxury |

### ROOM DNA — Living Room

| Field | 🔴 ARCHITECTURE | 🟢 DECORATION |
|---|---|---|
| `furniture_language` | — | undyed natural linen, rough-cut stone/slate, woven rattan/jute |
| `material_palette` | — | wide-plank reclaimed oak floor, rammed earth/clay plaster walls, rough-cut stone accent wall |
| `lighting_behavior` | — | "Warm concealed cove above stone wall + timber-shaded floor lamp" |
| `decor_language` | — | single large ceramic vessel with dried botanicals, hanging woven wall textile |
| `realism_constraints` | — | "sofa at residential scale", "stone wall texture visible — not flat CGI" |
| `room_specific_constraints` *(dead)* | **"single statement stone or timber wall — not all four walls"** 🟨 (wall treatment scope — mild architecture) | "planting: maximum 2 large statement plants" |
| `visible_transition_logic` | — | reclaimed oak floor and clay plaster continue into adjacent rooms; stone and plant accents echo through visible dining area |
| `negative_rules` | — | no plastic or synthetic pot, no plant collection overload, no polished surfaces, no cold grey palette |

### Cross-room architecture leaks

- **Bathroom** `furniture_language`: **"open wet room with pebble or slate floor"** (wet-room topology)
- **Facade** `furniture_language`: **"rough stone or rammed earth facade"** (facade material); `room_specific_constraints` (dead): **"two materials maximum — stone and timber"**
- **Living** `room_specific_constraints` (dead): "single statement stone or timber wall" (mild)

### Preservation-mode output

Strip "architectural realism" → "realism"; strip dead arch_language "architecturally resolved proportions" if revived; strip "open wet room" topology.

```
ATMOSPHERE (Nature Retreat): Biophilic calm integrated with realism and earthy luxury — grounded, alive, restorative, earthy, connected to nature, quietly luxurious. [Luxury eco retreat]
ROOM (Living Room): wide-plank reclaimed oak floor, rammed earth or clay plaster walls, rough-cut stone accent wall. LIGHT: Warm concealed cove above stone wall + timber-shaded floor lamp; warm organic tone. ATMOSPHERE STYLE: undyed natural linen — deep biophilic tactile warmth; rough-cut stone or slate — raw surface honesty; woven rattan or jute — organic textural depth; single large ceramic vessel with dried botanicals; hanging woven wall textile — natural undyed. REALISM: sofa at residential scale — not modelling scale; stone wall texture visible — not flat CGI. AVOID: no plastic or synthetic pot, no plant collection overload, no polished surfaces, Fake jungle overload, plant spam.
```

### Creative-mode output

Adds back "architectural realism" + "architecturally resolved proportions" + "open wet room" + dead room_specific_constraints.

---

## 10. Nordic Warmth (🟩 LOW bias — clean once dead fields stay dead)

### CORE DNA

| Field | 🔴 ARCHITECTURE | 🟢 DECORATION |
|---|---|---|
| `philosophy` | — | "Scandinavian comfort, warmth, coziness, and emotional softness" |
| `emotional_intent` | **"human-scaled"** 🟨 (scale word, mild) | cozy, hygge, warm, intimate, reassuring, softly joyful |
| `architectural_language` *(dead — HIGH bias if revived)* | **"Human-scaled rooms with pitched or low ceilings, … integrated storage"** | "natural birch and pine, layered wool and sheepskin in a white-to-warm-oat palette" |
| `material_palette` | — | white-painted birch/pine, natural wool/sheepskin, warm white plaster, pale stone/concrete, amber glass |
| `lighting_behavior` | — | "Warm candle-adjacent ambient — floor lamps with amber shades, hanging filament bulbs, no harsh overhead" |
| `luxury_level` | — | "Premium Scandinavian retreat" |
| `forbidden_elements` | — | Cold Ikea minimalism, ultra modern sharpness, excessive black accents, industrial rawness, high-gloss surfaces |
| `atmosphere_keywords` *(dead)* | — | hygge, birch, wool, warm white, candlelight |

### ROOM DNA — Living Room

| Field | 🔴 ARCHITECTURE | 🟢 DECORATION |
|---|---|---|
| `furniture_language` | — | natural wool in oat/undyed, birch/pine timber, sheepskin |
| `material_palette` | — | wide-plank pine/birch floor, warm white plaster walls, natural wool upholstery |
| `lighting_behavior` | — | "Amber floor lamp behind sofa + hanging filament bulb pendant; candle-warm, no ceiling wash" |
| `decor_language` | — | cluster of amber/clear glass candle holders, woven basket with wool throw |
| `realism_constraints` | — | "sofa at normal residential height — 45 cm", "candleholders at varied heights — not matching set" |
| `room_specific_constraints` *(dead)* | — | "layered rugs permitted", "fireplace or wood stove as focal point if present" |
| `visible_transition_logic` | — | pine floor and warm white plaster continue into kitchen; wool palette echoes through visible bedroom door |
| `negative_rules` | — | no sleek dark furniture, no chrome accents, no minimalist floating shelves, no cold grey palette |

### Cross-room architecture leaks

- **Facade** `furniture_language`: **"painted timber window frames"**, **"timber board cladding"** (facade material — decorative); `room_specific_constraints` (dead): **"white or near-white as primary facade colour"** (decoration, not topology)
- **Garden** `room_specific_constraints` (dead): **"naturalistic planting style — not formal clipped"** (planting topology — borderline DECORATION)

**Nordic is the cleanest atmosphere in current rendered prompts.** The only HIGH-bias content ("Human-scaled rooms with pitched or low ceilings") is in the dead `architectural_language` field and does not ship.

### Preservation-mode output (same as today — minimal stripping needed)

```
ATMOSPHERE (Nordic Warmth): Scandinavian comfort, warmth, coziness, and emotional softness — cozy, hygge, warm, intimate, reassuring, softly joyful. [Premium Scandinavian retreat]
ROOM (Living Room): wide-plank pine or birch floor, warm white plaster walls, natural wool upholstery in oat or undyed tones. LIGHT: Amber floor lamp behind sofa + hanging filament bulb pendant; candle-warm, no ceiling wash. ATMOSPHERE STYLE: natural wool in oat or undyed — deep hygge tactile warmth; birch or pine timber — warm natural surface depth; sheepskin — natural undyed tactile softness; cluster of amber or clear glass candle holders on coffee table; woven basket with wool throw at sofa end. REALISM: sofa at normal residential height — 45 cm; candleholders at varied heights — not matching set. AVOID: no sleek dark furniture, no chrome accents, no minimalist floating shelves, Cold Ikea minimalism, ultra modern sharpness.
```

### Creative-mode output (CAUTION — this is where Wave 5.5.1 regression came from)

Reinjecting "Human-scaled rooms with pitched or low ceilings" + "human-scaled" emotion brings back the field that matrix Principle #6 cited as the source of Nordic-room-compression regression in Wave 5.5.1. **In creative mode, this is acceptable** because the goal there is creative architectural reinterpretation. But this confirms that the bimodal split is the correct design: keep the architectural directives available for creative mode, off by default.

---

## Cross-atmosphere summary

### Where the architectural bias is concentrated (shipping fields only)

| Bias category | Atmospheres affected (currently rendered) |
|---|---|
| **Direct topology word in `philosophy`** | Tropical Escape ("Open-air") |
| **Spatial/scale word in `emotional_intent`** | Desert Luxe ("sculptural, monumental"), Zen ("emptied"), Japandi ("breathable"), Nordic ("human-scaled"), Dark ("architecturally confident") |
| **Opening-pressure in `realism_constraints`** | Zen ("floor space dominant"), Japandi ("empty floor space is deliberate") |
| **"open" / "pavilion" in `visible_transition_logic`** | Bali (recurring), Tropical (mild) |
| **Anti-closing in `negative_rules`** | Tropical ("no closed cabinet-heavy bathroom", "no enclosed dining room feel") |

### Where the architectural bias hides in dead fields (not currently shipped)

| Field | High-bias content per atmosphere |
|---|---|
| `architectural_language` | Tropical "Open-plan volumes dissolving into landscape", Bali "Open-pavilion volumes … indoor-outdoor dissolving boundaries", Nordic "Human-scaled rooms with pitched or low ceilings", Desert "Monolithic forms … deep shadow reveals", Zen "Spatial emptiness as architectural intention", Soft Luxury "generous proportions" |
| `room_specific_constraints` (room-level) | Tropical/Bali "open side to garden/terrace", Japandi "no upper cabinets to ceiling", Bali "open or semi-open shower", Zen "no vanity cabinet", Tropical "open or semi-open if villa allows", Soft Luxury "formal symmetry in layout", Bali "palm thatch shade pavilion" |
| `atmosphere_keywords` | Tropical "open-air luxury", Bali "open pavilion", Zen "architectural silence", Desert "desert monolith" |

### Atmospheres ranked by total architectural surface (rendered + dead)

| Rank | Atmosphere | Rendered bias | Dead bias | Total |
|---|---|---|---|---|
| 1 | Tropical Escape | HIGH (philosophy, negatives) | HIGH (arch_language, room constraints) | 🔴 most loaded |
| 2 | Bali Sanctuary | MED (visible_transition pavilion) | HIGH (open-pavilion, dissolving) | 🟧 high but matrix-reference |
| 3 | Zen Retreat | MED (emptied, floor dominant) | HIGH (spatial emptiness) | 🟧 |
| 4 | Japandi Calm | MED (empty floor) | MED (Low-profile horizontal, neg space) | 🟧 |
| 5 | Desert Luxe | MED (sculptural monumental) | MED (Monolithic, deep reveals) | 🟧 |
| 6 | Nordic Warmth | LOW | HIGH (Human-scaled pitched ceilings) | 🟨 dormant |
| 7 | Soft Luxury | LOW | LOW (generous proportions only) | 🟩 |
| 8 | Dark Contemporary | LOW (mild metaphor) | MED (gallery-level spatial control) | 🟩 |
| 9 | Nature Retreat | LOW | LOW | 🟩 |
| 10 | Warm Modern | none | none significant | 🟩 cleanest |

---

## What this classification enables (next-wave implementation sketch)

> ⚠️ **Out of scope of this audit.** Not implementing. Sketch only for reference.

A bimodal composer would consume this classification by:

1. **Adding a `_ARCHITECTURE_TOKENS_BY_ATMOSPHERE` constant** in a new file (e.g. `prompt_engine/atmosphere_dna/bimodal_classifier.py`), mapping `atmosphere_id` → list of regex patterns matching the 🔴 phrases identified per atmosphere in this doc.

2. **Adding a mode flag** propagated through `compose_prompt(...)`: `preservation_mode: bool = True` (default). Surprise Me path passes `False`.

3. **Modifying `build_dna_block(dna, preservation_mode=True)`** in `_base.py` to:
   - If `preservation_mode`: filter out 🔴 phrases from the assembled string post-render
   - If creative: skip the boundary voices in upstream layers (`fidelity_layer.build_first_vision_task`, `wow_layer.build_atmosphere_dna_boundary`, `_PHOTO_EDIT_WOW` tail)

4. **Reviving the dead fields** by extending `build_dna_block` to optionally inject `core.architectural_language`, `dna.room_specific_constraints`, `core.atmosphere_keywords` when `preservation_mode=False`.

5. **Routing the mode**:
   - From `main.py /generate`: pass `mode="surprise_me"` when frontend sends the Surprise Me flag
   - Default for all other paths: preservation mode

6. **Freeze contract**: All of the above touches frozen files (`_base.py`, `composer.py`, `composer_v2.py`). Would require explicit freeze exception **and** must keep preservation-mode output **byte-identical** to today's output for regression safety. New behaviour confined to `preservation_mode=False` branch only.

7. **Rollback**: One flag flip + revert of mode propagation. Surface ~50 lines across 4 files.

8. **Validation gate**: Benchmark protocol — 9-shot V1 generation on the user's benchmark apartment in BOTH modes; preservation mode must remain 100% hit-rate "good or better"; creative mode evaluated for "wow surprise" subjective score (no objective threshold defined yet).

---

## Honest caveats

1. **Some 🔴 calls are judgment.** "human-scaled" in Nordic `emotional_intent` is ambiguous — emotional warmth or scale instruction? I tagged it 🟨 in core. Same for "sculptural" in Desert. Reasonable people could re-tag these.

2. **Stripping changes identity.** Removing "Open-air" from Tropical's philosophy makes it "Tropical living with relaxed contemporary luxury" — still recognisable but loses the breezy resort character. The matrix says Tropical is a DO-NOT-DILUTE reference. The bimodal design says "in preservation mode we accept the dilution because preservation is the priority; in creative mode we keep the identity intact". The user's framing supports this trade-off.

3. **Dead-field revival may not produce expected creative output.** gpt-image-1's response to `architectural_language` "Open-pavilion volumes with dissolving boundaries" is untested — adding it to creative mode is a hypothesis, not a measured improvement. Would need its own benchmark.

4. **No production benchmark of bimodal yet.** Everything in this doc is design-time analysis. The actual creative-mode vs preservation-mode comparison requires running both paths on real photos with real visual evaluation. This audit does not commit to that work.

5. **Surprise Me is currently a recommender, not a mode.** Mapping Surprise Me → creative mode is a UX product decision, not a backend technical one. The recommender picks an atmosphere; whether that atmosphere is rendered in creative mode is orthogonal. The user may want Surprise Me to ALWAYS be creative mode, or to offer "Surprise Me · Preserve" vs "Surprise Me · Creative" as two flavours.

---

*End of bimodal classification. 10 atmospheres × CORE fields + Living Room representative + cross-room leaks documented. No code modified. Companion doc [WAVE_5_5_14a_DNA_AUDIT.md](WAVE_5_5_14a_DNA_AUDIT.md) has the diagnostic context.*
