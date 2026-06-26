from ._base import AtmosphereCoreDNA, RoomAdaptationDNA, register_core, register

register_core(AtmosphereCoreDNA(
    atmosphere_id="japandi_calm",
    philosophy="Japanese restraint blended with Scandinavian softness and emotional calm.",
    emotional_intent="Still, serene, grounded, quietly refined, breathable, unhurried.",
    architectural_language="Low-profile horizontal forms, natural material honesty, and deliberate negative space in clean residential volumes.",
    material_palette=["pale ash or birch", "wabi-sabi plaster", "dark charcoal ceramic", "natural linen", "honed dark stone"],
    lighting_behavior="Soft diffused ambient — paper lanterns, concealed warm slots; no bright downlights.",
    luxury_level="Quiet luxury boutique hospitality",
    forbidden_elements=["Empty sterile minimalism", "sci-fi white spaces", "excessive decor", "fake zen clichés", "bamboo overuse"],
    atmosphere_keywords=["japandi", "wabi-sabi", "negative space", "natural honesty", "quiet luxury"],
))

for _d in [
    RoomAdaptationDNA(
        atmosphere_id="japandi_calm",
        room_type="living_room",
        furniture_language=["natural linen in stone or fog tones — unhurried tactile calm", "wabi-sabi ceramic or ash — raw surface honesty", "natural rush or jute — organic textural warmth"],
        # Wave 5.5.39 — softened "wabi-sabi plaster walls" → "wabi-sabi
        # plaster finish on existing walls". Investigation (Wave 5.5.33
        # audit + 2026-05-25 bench analysis) identified this as the
        # suspect #1 leak: the "plaster walls" plural noun implied "all
        # walls are wabi-sabi plaster" — model converted the baie vitrée
        # area into a plaster wall to match. Same fix pattern as Nature
        # Retreat Wave 5.5.37 ("accent wall" → "accents on existing
        # surfaces"): explicit "existing walls" anchor.
        material_palette=["pale ash or birch floor", "wabi-sabi plaster finish on existing walls in off-white or putty", "dark charcoal ceramic accents"],
        lighting_behavior="Paper lantern pendant + concealed warm floor slot; no harsh downlights.",
        # Wave 6.14 (2026-06-09) — Emotional Styling Layer (Japandi Living),
        # CALIBRATED LIGHT: decor 2→6 but calm/textural to read "warm and
        # complete, never sparse" while RESPECTING negative space (ma) — no
        # clutter. Anchored-to-existing + conditional-omit art + anchored-corner
        # specimen. Structure / materials / fidelity / TV anchor untouched.
        # Gate: walls invented = 0 AND naturalness >= 4/5, else revert.
        decor_language=[
            "floor-length raw undyed linen curtains in stone or fog clearly framing each existing window, drawn open with the glass left fully clear — never covering, narrowing or blocking it, never on a glass partition",
            "single branch in handmade ceramic vase on the existing low table",
            "raw undyed linen cushions in stone or fog tones on the existing sofa — naturally creased, calm and breathable, not plumped",
            "a softly folded raw linen or wool throw over the existing sofa — unhurried, lived-in calm",
            "a large natural jute or rush textural rug grounding the seating — quiet warmth underfoot",
            "a slender specimen plant — bamboo, maple, or fine birch branch — in a handmade ceramic floor pot anchored in the existing corner adjacent to the window, generous negative space around it, never floating in the room",
            "one framed Japanese ink artwork on the existing wall — only if that wall is solid and free, else omit; let negative space breathe",
        ],
        realism_constraints=["sofa low enough to feel grounded — 40–45 cm seat height", "empty floor space is deliberate, not absent"],
        # Wave 5.5.39 — slot [0] becomes standardized TV anchor (WM
        # pattern: "single clear focal wall — <opt1>, <opt2>, or a
        # television, not multiple"). Atmosphere-coherent options stay
        # minimal (fireplace + artwork) — both compatible with Japandi
        # restraint. Slot [1] "maximum 6 decorative objects" (raised from 3
        # on 2026-06-09). "solid neutral rug or no rug —
        # no pattern" demoted to slot [2] (not emitted by [:2] in
        # build_dna_room_context, accepted trade-off — rug pattern is a
        # secondary concern vs TV + restraint).
        # Wave 5.5.49 — adopting universal media console flex pattern
        # (standardization across all atmospheres). Allows TV on existing
        # wall OR media console; explicitly forbids creating a new wall.
        # 2026-06-09 — decor cap raised 3 → 6 (product decision: richer Japandi
        # Living). Above the historical restraint floor; bench for clutter /
        # wall-invention on interior sources before locking.
        # 2026-06-09 — focal-TV port from Warm Modern: the TV line goes from a
        # conditional placement guard ("if a TV, here") to a PRESENCE directive
        # (TV present as the living focal point, seating oriented to it). Mirrors
        # WM's reliable-TV behaviour. Keeps WM 6.13e anti-invention guard (never
        # a new wall, never converting a glazed partition into a wall) since
        # Japandi sources are also glass-heavy. A TV is furniture/decor → allowed
        # under preserve mode. Bench for forced-TV look on TV-less sources.
        room_specific_constraints=["include a television as the living-room focal point, seating arranged toward it — clearly present on an existing wall or low media console, never a new wall or by converting glazing into a wall", "maximum 6 decorative objects in room", "solid neutral rug or no rug — no pattern"],
        # Wave 5.14c — dropped the "plaster walls" plural noun (mirror
        # of the Wave 5.5.39 material_palette fix that missed this
        # field). The noun was being read as wall entities to
        # materialize, triggering wall invention. Verb-based phrasing
        # ("plaster continue") matches WM's working pattern.
        visible_transition_logic="pale ash floor and soft mineral finish continue into adjacent rooms; ceramic palette echoes through visible kitchen",
        # Wave 5.5.39 — added defensive anti-wall-replacement rule
        # ("preserve existing windows and glass openings as photographed").
        # Defense in depth against the "wabi-sabi plaster walls" leak
        # (now softened in material_palette). Per the "prudence maximale"
        # discipline locked 2026-05-25 for Japandi.
        # POSITIONING : slot [0]. build_dna_block emits negative_rules[:3]
        # only; the defensive rule must be in the first 3 slots to ship.
        # Trade-off : "no warm-orange wood tones" demoted to slot [3]
        # (not emitted in DNA block but kept for documentation).
        # Wave 5.12c — universal wall-preservation rule, replacing the
        # Wave 5.5.39 window-only rule. The new universal covers both
        # walls AND windows so Japandi gets wall-invention protection
        # for the first time without losing window preservation.
        # Wave 5.14c — softened wall rule (see WM for rationale).
        negative_rules=["no cluttered surfaces", "no patterned textiles", "no warm-orange wood tones", "no cold grey minimalism"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="japandi_calm",
        room_type="master_bedroom",
        # Wave 6.6 (2026-06-04) — initial organic-life enrichment kept Japandi
        # at 2 items per audit identity-restraint policy.
        # Wave 6.9 (2026-06-04) — PHOTO-2 enrichment (7 items + pendant +
        # bedside lamp + wall constraint relax).
        # Wave 6.10 (2026-06-04) — A+B micro-tuning post Wave 6.9 bench :
        #   A.1 strengthen artwork position : "above the headboard" →
        #       "mounted directly above and centred over the existing headboard"
        #   A.2 increase pillows : "2 to 3" → "3 to 4 of varied sizes"
        #   A.3 windowsill plant stronger wording : "small potted plant or
        #       trailing branch" → "single specimen plant or large branch
        #       arrangement in handmade ceramic vessel on the existing
        #       windowsill or floor adjacent to window"
        #   B   NEW tall specimen plant — bamboo/maple/birch branch in
        #       handmade ceramic floor pot adjacent to window or wall
        # → 7 → 8 items total. Slice [:8] (Wave 6.8) ships all 8.
        furniture_language=["pale ash timber — warm horizontal tactile calm", "ash or natural timber — minimal wall-mounted surface restraint", "raw wood or unfinished timber — wabi-sabi surface quality"],
        material_palette=["pale ash or birch floor", "wabi-sabi plaster finish on existing walls", "natural linen bedding in stone or fog tones with subtle organic textile irregularities"],
        lighting_behavior="Single paper lantern pendant centred above the existing bed + bedside paper or ceramic shade lamp producing warm amber glow + narrow concealed warm slot; soft natural morning diffusion with delicate light gradients.",
        decor_language=[
            "floor-length raw undyed linen curtains in stone or fog clearly framing each existing window, drawn open with the glass left fully clear — never covering, narrowing or blocking it, never on a glass partition",
            "folded linen throw at bed foot with natural relaxed fall",
            "single ikebana branch in handmade ceramic on bedside shelf — quiet emotional grounding",
            "single tonal ink wash or branch sketch artwork in light wood frame mounted directly above and centred over the existing headboard",
            "natural jute or sisal mat at one bedside on the existing floor",
            "3 to 4 linen pillows of varied sizes in stone, fog, or off-white tones on the existing bed",
            "small dried branch arrangement in handmade ceramic vase on the existing dresser or floating shelf",
            "single specimen plant or large branch arrangement in handmade ceramic vessel on the existing windowsill or floor adjacent to window",
            "tall specimen plant — bamboo, maple, or fine birch branch — in handmade ceramic floor pot adjacent to the existing window or wall",
        ],
        realism_constraints=["platform bed at correct low height — 35–40 cm", "bedding folded with natural weight, not starched flat"],
        room_specific_constraints=["no TV in bedroom", "single tonal artwork above headboard permitted — restrained, light wood frame, no gallery wall"],
        visible_transition_logic="ash floor and wabi-sabi plaster flow into visible ensuite; linen tones echo in towel display",
        negative_rules=["no upholstered headboard", "no patterned bedding", "no chrome bedside lamps", "no hotel turndown aesthetic"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="japandi_calm",
        room_type="kitchen",
        # Wave 6.13b (2026-06-05) — kitchen enrichment (see WM block header).
        # Japandi col 3 : "ne doit PAS sembler enrichi". HELD TO 3 ITEMS — only a
        # single organic branch added vs the existing 2. Asymmetric grouping +
        # generous breathing negative space. No textile, no plant clutter, no art.
        furniture_language=["flat-front pale ash cabinetry, handleless or recessed grip", "honed concrete or raw stone countertop", "open lower shelf with minimal ceramic display"],
        material_palette=["pale ash cabinetry", "honed concrete or raw stone countertop", "wabi-sabi plaster backsplash"],
        lighting_behavior="Soft diffused natural light across the ash and concrete surfaces; warm concealed under-cabinet strip only, no ceiling pendant in kitchen zone; calm even glow with breathing negative space.",
        decor_language=[
            "raw undyed linen curtains in stone or fog framing the existing window, drawn open with the glass clear — never covering or blocking it, never on a glass partition; only where a window exists",
            "three matching wabi-sabi ceramic canisters grouped asymmetrically on the open ash shelf — quiet, not lined up",
            "single clay or cast iron pot on the existing counter — raw natural texture",
            "single organic branch in a slim ceramic vessel on the existing counter — one accent only, generous breathing space around it",
        ],
        realism_constraints=["cabinet doors at residential height — not commercial scale", "countertop empty except for 1–2 intentional objects"],
        # Wave 6.13c (2026-06-05) — kitchen structure-preservation guard at [0] (see WM). Ships [:2].
        room_specific_constraints=["arrange cabinetry and island without covering, narrowing or relocating any existing window, doorway or wall opening — keep photographed openings fully clear", "no upper cabinets to ceiling — open shelf break preferred", "all appliances hidden or flush-integrated"],
        visible_transition_logic="ash cabinet tone flows into dining furniture; stone counter colour echoes dining table surface",
        negative_rules=["no warm oak tone", "no exposed stainless appliances", "no cluttered open shelving", "no patterned tile backsplash"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="japandi_calm",
        room_type="bathroom",
        furniture_language=["wall-hung ash vanity, handleless", "deep soaking tub in raw concrete or stone composite", "frameless glass shower partition"],
        material_palette=["honed natural stone floor", "wabi-sabi plaster finish on existing walls", "matte black or graphite fixtures"],
        lighting_behavior="Concealed warm slot above vanity mirror; diffused side sources only — no ceiling downlights.",
        decor_language=["single ceramic soap dish", "folded natural linen towels on wall peg"],
        realism_constraints=["vanity at correct height — 80–85 cm", "stone floor with correct grout joint width"],
        room_specific_constraints=["matte black fixtures throughout — no finish mixing", "countertop with soap and single plant only"],
        visible_transition_logic="stone floor and wabi-sabi plaster continue into dressing area; matte black fixtures echo door hardware",
        negative_rules=["no glossy white tiles", "no chrome fixtures", "no mirrored vanity cabinet", "no over-accessorised countertop"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="japandi_calm",
        room_type="terrace",
        furniture_language=["low teak or ash platform bench with flat cushion", "simple stone or concrete low table", "single large ceramic planter"],
        material_palette=["honed concrete or natural stone paving", "matte charcoal planter", "natural linen outdoor cushion"],
        lighting_behavior="Low warm ground uplights on planting + single warm lantern on plinth; minimal overhead.",
        decor_language=["anchored to the existing terrace floor, parapet, garde-corps and any existing shade structure — existing architecture and openings kept exactly; no new walls, no enclosure, no building roof, no floor or deck extension", "single specimen tree — maple or birch — in a matte charcoal planter, with a restrained raked gravel or moss ground plane", "a low stone or concrete table with a single ceramic vessel and one warm stone lantern — intentional and uncluttered", "a flat linen cushion and a single natural linen throw on the bench", "one or two matte charcoal planters with sparse, sculptural greenery — never a dense collection", "where the terrace is large enough, a low ash or teak dining table with simple benches or low-back chairs — uncluttered and intentional, never rattan"],
        realism_constraints=["bench at correct low height — 35–40 cm seat", "planting sparse and intentional"],
        room_specific_constraints=["Create only the number of functional outdoor zones that naturally fit the terrace size — a large terrace may add a low dining area beside the seating zone, a small one keeps a single well-composed grouping; never overcrowd — zen restraint throughout", "raked gravel or ground plane clearly defined"],
        visible_transition_logic="stone paving continues from interior ash floor; furniture palette echoes interior joinery visible through glass",
        negative_rules=["no rattan outdoor furniture", "no string lights", "no potted herb collection", "no coloured cushions"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="japandi_calm",
        room_type="facade",
        furniture_language=["timber-clad facade in shou sugi ban or pale ash boards", "recessed entrance with stone threshold", "simple matte steel or timber gate"],
        material_palette=["charred timber or pale ash board cladding", "raw concrete or stone plinth base", "matte black steel window frames"],
        lighting_behavior="Concealed ground uplights washing cladding vertically + single warm entrance lantern.",
        # Wave 6.26 (2026-06-06) — facade enrichment, architecture-safe, zen (guard at [0]; see WM).
        decor_language=["keep the building exactly — never add, alter, narrow, extend, or restyle any wall, window, door, roof, cladding or structure; only ground-level planting, a doormat and warm light on the existing entrance", "clean horizontal board rhythm", "single specimen tree in gravel forecourt", "a single potted maple or bamboo beside the existing entrance"],
        realism_constraints=["timber board joints at correct weathered scale", "window reveals deep enough to cast shadow line"],
        room_specific_constraints=["maximum two materials on facade — no mixing", "entrance door recessed into facade plane"],
        visible_transition_logic="charred timber tone flows to boundary fence; stone threshold echoes interior floor material",
        negative_rules=["no warm sand render", "no decorative ironwork", "no warm brick", "no suburban window proportions"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="japandi_calm",
        room_type="dining_room",
        # Wave 6.13 (2026-06-05) — dining_room enrichment (see WM block header).
        # Japandi target (col 2/3) : organic minimalism — LESS is the signature.
        # Enriched to 5 items only (vs 6 elsewhere) ; prominent centered washi
        # lantern is the focal. Artwork CONDITIONAL OMIT ; plant anchored on credenza.
        furniture_language=["low rectangular ash dining table", "simple benches or low-back ash chairs", "wall-mounted ash credenza"],
        material_palette=["pale ash floor", "wabi-sabi plaster finish on existing walls", "natural linen chair upholstery or bare ash seat"],
        lighting_behavior="Single large washi paper lantern pendant hung low and centered over the existing table; soft diffused warm glow with no direct spot; calm even ambient light, quiet and zen.",
        decor_language=[
            "floor-length raw undyed linen curtains in stone or fog clearly framing each existing window, drawn open with the glass left fully clear — never covering, narrowing or blocking it, never on a glass partition",
            "single handmade ceramic bowl centrepiece on the existing table — wabi-sabi glaze with organic imperfection",
            "PROMINENTLY placed single ikebana branch in a slender ceramic vessel on the existing credenza",
            "one tonal sumi-e or muted abstract artwork above the existing credenza — slim natural frame, only if that wall is free, else omit",
            "a folded undyed linen runner laid across the existing table — softly textured, natural fibre",
            "single low specimen plant — bonsai or moss in a shallow ceramic dish — on the existing credenza",
        ],
        realism_constraints=["pendant at correct dining height — 70–75 cm above table", "bench seat at correct height for table"],
        room_specific_constraints=["table for 4–6 only — not oversized", "credenza top with no more than two intentional objects — zen restraint, never cluttered"],
        visible_transition_logic="ash floor and plaster continue from living room; ceramic palette echoes kitchen visible beyond",
        negative_rules=["no upholstered chair backs", "no tablecloth", "no multi-pendant cluster", "no cluttered credenza display"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="japandi_calm",
        room_type="balcony",
        furniture_language=["low single-seat platform chair in ash", "small raw concrete side table", "single ceramic pot with bonsai or bamboo grass"],
        material_palette=["honed stone or timber-composite balcony floor", "matte charcoal balustrade", "natural linen cushion"],
        lighting_behavior="Single small warm lantern on floor or wall; no overhead electric fixture.",
        # Wave 6.26 (2026-06-06) — balcony enrichment, zen-restrained (guard at [0]; see WM).
        decor_language=["anchored to the existing balcony floor, railing and furniture — existing layout kept exactly; no added walls, new structures, roofs or extensions", "single intentional plant in ceramic pot", "folded natural linen on chair", "a single ceramic cup on the existing side table", "a low stone lantern on the existing floor", "a simple jute or undyed linen mat grounding the seating on the existing floor"],
        realism_constraints=["chair low — 38–42 cm seat height", "balustrade at correct safety height"],
        room_specific_constraints=["single seating piece only — no set", "no storage visible on balcony"],
        visible_transition_logic="balcony floor echoes interior ash or stone floor; warm interior plaster visible through glass doors",
        negative_rules=["no rattan", "no coloured cushions", "no herb garden", "no folding or plastic furniture"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="japandi_calm",
        room_type="pool_area",
        furniture_language=["low teak or ash platform daybed", "simple concrete or stone side plinth", "minimal canvas shade sail"],
        material_palette=["honed concrete or dark stone pool deck", "flush dark-grout stone coping", "natural canvas shade"],
        lighting_behavior="Subdued warm underwater lighting + low ground uplights at deck perimeter only.",
        # Wave 6.25 (2026-06-06) — pool enrichment, zen-restrained (anchoring guard at [0]; see WM).
        decor_language=["anchored to the existing deck, coping and furniture — existing pool and spatial layout kept exactly; no added walls, new structures, roofs, pergolas or architectural extensions", "single specimen tree at pool edge", "raked gravel or moss ground plane beyond deck", "a single folded linen cushion and a ceramic cup on the existing daybed", "a low stone lantern placed on the existing deck"],
        realism_constraints=["pool coping flush with deck — no raised lip", "daybed at correct low height"],
        room_specific_constraints=["dark pool liner preferred — slate or charcoal tone", "maximum 2 daybeds — no furniture overcrowding"],
        visible_transition_logic="dark stone deck continues to terrace; charred timber facade visible as backdrop",
        negative_rules=["no travertine (too warm)", "no bright parasols", "no sun lounger parade", "no colourful pool water"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="japandi_calm",
        room_type="garden",
        furniture_language=["a low ash bench plus a low ash or teak dining table with simple benches or low-back chairs where the garden is large enough — uncluttered, intentional, never rattan", "large specimen Japanese maple or birch tree", "raked gravel or moss ground zone"],
        material_palette=["dark slate stepping stone path", "moss or raked gravel ground plane", "raw concrete or stone planter"],
        lighting_behavior="Low warm uplights on specimen tree + single stone lantern on plinth; no path strip lighting.",
        # Wave 6.26 (2026-06-06) — garden enrichment, zen-restrained (guard at [0]; see WM balcony).
        decor_language=["anchored to the existing paving, beds and garden footprint — existing layout kept exactly; no added walls, new structures, roofs, pergolas or hardscape", "raked gravel as design element", "carefully pruned shrub or topiary mass", "a single folded linen cushion on the existing ash bench", "a low stone lantern beside the existing stepping path"],
        realism_constraints=["stepping stones at correct 50–60 cm pace", "ground plane at correct grade level"],
        room_specific_constraints=["maximum 3 plant species", "no lawn — gravel, moss, or stone ground only"],
        visible_transition_logic="stone stepping path connects to terrace; ash bench echoes interior joinery palette",
        negative_rules=["no lawn grass", "no mixed planting chaos", "no garden furniture set", "no decorative lantern overuse"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="japandi_calm",
        room_type="entrance_hall",
        furniture_language=["wall-mounted ash shelf at 90 cm — no legs", "single hand-thrown ceramic bowl on shelf", "simple ash-framed mirror"],
        material_palette=["large-format honed stone floor", "wabi-sabi plaster finish on existing walls", "matte black or ash door hardware"],
        lighting_behavior="Narrow warm slot above mirror; arrival through focused warm beam — no ceiling light.",
        # Wave 6.24 (2026-06-06) — entrance enrichment, surface/floor only, zen-restrained
        # (see WM note). Wall stays deliberately empty; only a floor runner added.
        decor_language=[
            "raw undyed linen curtains in stone or fog framing the existing window, drawn open with the glass clear — never covering or blocking it, never on a glass partition; only where a window exists",
            "single dried botanical in ceramic",
            "wall left deliberately empty — no artwork",
            "a raw linen or jute runner along the floor",
        ],
        realism_constraints=["shelf wall-anchored with no visible brackets", "mirror sized to match shelf width"],
        # Wave 6.23 (2026-06-06) — entrance opening-preservation guard at [0] (see WM).
        room_specific_constraints=["place the shelf, mirror and wall decor on an existing solid wall only — never cover, wall over, narrow or replace any existing opening, doorway or passage; if the only free wall is an opening, keep it open", "single object on shelf — discipline enforced", "no coat hooks or visible storage"],
        visible_transition_logic="stone floor and plaster flow directly into living room; ash palette echoes throughout",
        negative_rules=["no console with legs", "no coat rack", "no cluttered entry objects", "no warm oak tone"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="japandi_calm",
        room_type="home_office",
        # Wave 6.17 (2026-06-06) — desk upsized (see WM note). "solidly wall-anchored"
        # reinforces the no-sag realism constraint now that the floating desk is wider.
        furniture_language=["large wide wall-mounted ash floating desk — no legs, generous work surface, solidly wall-anchored", "minimal upright chair in ash with linen seat pad", "single floating ash shelf above desk"],
        material_palette=["pale ash floor", "wabi-sabi plaster finish on existing walls", "matte black desk accessories"],
        lighting_behavior="Single adjustable matte black task arm lamp on desk; warm ambient cove only.",
        # Wave 6.14 (2026-06-06) — home_office enrichment (see WM block note).
        # Held to 4 items — zen restraint; shelf max-5-items rule respected.
        # Wave 6.16 (2026-06-06) — full pack, restrained for zen (see WM note).
        decor_language=[
            "floor-length raw undyed linen curtains in stone or fog clearly framing each existing window, drawn open with the glass left fully clear — never covering, narrowing or blocking it, never on a glass partition",
            "a low minimal lounge chair with a small ash stool in the open floor area — clear of any window or door, only if floor space allows, else omit",
            "a raw jute or undyed linen rug grounding the desk and the quiet seating spot",
            "a single ceramic cup, a closed notebook and an ink brush resting on the existing desk — calm, in use",
            "a slender branch or ikebana stem in a narrow vessel on the existing floating shelf",
            "a tonal sumi-e or muted ink artwork on the existing wall — slim frame, only if that wall is free, else omit",
            "a low open ash shelving stack against a free wall — sparse, a few objects only — only if the room is large enough and it covers no opening, else omit",
        ],
        realism_constraints=["floating desk correctly wall-anchored — no visible cantilever sag", "chair at correct desk height"],
        room_specific_constraints=["zero cable visibility — all routed inside wall", "shelf with maximum 5 items total"],
        visible_transition_logic="ash desk and wabi-sabi plaster flow into adjacent hallway; matte black accents echo door hardware",
        negative_rules=["no standard desk with legs", "no ergonomic chair styling", "no monitor stand clutter", "no pin board or sticky notes"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="japandi_calm",
        room_type="driveway",
        furniture_language=["raked gravel forecourt with single specimen tree", "flat dark stone entrance path", "simple matte black gate"],
        material_palette=["dark slate or honed stone driveway surface", "raw concrete gate pillars", "raked gravel infill"],
        lighting_behavior="Low warm ground uplights on specimen tree + single lantern at gate post; no overhead lights.",
        # Wave 6.26 (2026-06-06) — driveway enrichment, architecture-safe, zen (guard at [0]; see WM facade).
        decor_language=["keep the drive, gate, pillars and boundary exactly — never add, alter, widen or extend any wall, gate, pillar, structure or paving; only border planting, potted plants and warm light on existing surfaces", "single Japanese maple or birch at forecourt edge", "raked gravel pattern visible from gate", "a low stone lantern at the existing gate post"],
        realism_constraints=["gravel at correct loose depth — not compacted solid", "tree at correct planted scale for forecourt"],
        room_specific_constraints=["single tree, one boundary element — no cluttered planting", "gate in single material — no mixing"],
        visible_transition_logic="dark stone path continues to entrance threshold; charred timber facade visible from gate",
        negative_rules=["no warm sand render boundary", "no ornate gate", "no manicured hedging rows", "no lantern overuse"],
    ),
]:
    register(_d)
