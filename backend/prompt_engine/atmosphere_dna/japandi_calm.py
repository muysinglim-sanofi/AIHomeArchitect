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
        decor_language=["single branch in handmade ceramic vase", "one framed Japanese ink artwork"],
        realism_constraints=["sofa low enough to feel grounded — 40–45 cm seat height", "empty floor space is deliberate, not absent"],
        # Wave 5.5.39 — slot [0] becomes standardized TV anchor (WM
        # pattern: "single clear focal wall — <opt1>, <opt2>, or a
        # television, not multiple"). Atmosphere-coherent options stay
        # minimal (fireplace + artwork) — both compatible with Japandi
        # restraint. Slot [1] "maximum 3 decorative objects" preserved
        # (decor restraint discipline). "solid neutral rug or no rug —
        # no pattern" demoted to slot [2] (not emitted by [:2] in
        # build_dna_room_context, accepted trade-off — rug pattern is a
        # secondary concern vs TV + restraint).
        # Wave 5.5.49 — adopting universal media console flex pattern
        # (standardization across all atmospheres). Allows TV on existing
        # wall OR media console; explicitly forbids creating a new wall.
        room_specific_constraints=["television visible in living area on existing wall surface or media console — never on a newly created wall", "maximum 3 decorative objects in room", "solid neutral rug or no rug — no pattern"],
        visible_transition_logic="pale ash floor and plaster walls extend into adjacent rooms; ceramic palette echoes through visible kitchen",
        # Wave 5.5.39 — added defensive anti-wall-replacement rule
        # ("preserve existing windows and glass openings as photographed").
        # Defense in depth against the "wabi-sabi plaster walls" leak
        # (now softened in material_palette). Per the "prudence maximale"
        # discipline locked 2026-05-25 for Japandi.
        # POSITIONING : slot [0]. build_dna_block emits negative_rules[:3]
        # only; the defensive rule must be in the first 3 slots to ship.
        # Trade-off : "no warm-orange wood tones" demoted to slot [3]
        # (not emitted in DNA block but kept for documentation).
        negative_rules=["preserve existing windows and glass openings as photographed", "no cluttered surfaces", "no patterned textiles", "no warm-orange wood tones", "no cold grey minimalism"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="japandi_calm",
        room_type="master_bedroom",
        furniture_language=["pale ash timber — warm horizontal tactile calm", "ash or natural timber — minimal wall-mounted surface restraint", "raw wood or unfinished timber — wabi-sabi surface quality"],
        material_palette=["pale ash or birch floor", "wabi-sabi plaster finish on existing walls", "natural linen bedding in stone or fog tones"],
        lighting_behavior="Single paper lantern pendant off-centre + narrow concealed cove above headboard wall.",
        decor_language=["folded linen throw at bed foot", "single ikebana branch in ceramic on bedside shelf"],
        realism_constraints=["platform bed at correct low height — 35–40 cm", "bedding folded with natural weight, not starched flat"],
        room_specific_constraints=["no TV in bedroom", "single artwork or none — wall left deliberately spare"],
        visible_transition_logic="ash floor and plaster walls flow into visible ensuite; linen tones echo in towel display",
        negative_rules=["no upholstered headboard", "no patterned bedding", "no chrome bedside lamps", "no hotel turndown aesthetic"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="japandi_calm",
        room_type="kitchen",
        furniture_language=["flat-front pale ash cabinetry, handleless or recessed grip", "honed concrete or raw stone countertop", "open lower shelf with minimal ceramic display"],
        material_palette=["pale ash cabinetry", "honed concrete or raw stone countertop", "wabi-sabi plaster backsplash"],
        lighting_behavior="Warm concealed under-cabinet strip only; no ceiling pendant in kitchen zone.",
        decor_language=["three matching ceramic canisters on open shelf", "single clay or cast iron pot on counter"],
        realism_constraints=["cabinet doors at residential height — not commercial scale", "countertop empty except for 1–2 intentional objects"],
        room_specific_constraints=["no upper cabinets to ceiling — open shelf break preferred", "all appliances hidden or flush-integrated"],
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
        visible_transition_logic="stone floor and plaster walls continue into dressing area; matte black fixtures echo door hardware",
        negative_rules=["no glossy white tiles", "no chrome fixtures", "no mirrored vanity cabinet", "no over-accessorised countertop"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="japandi_calm",
        room_type="terrace",
        furniture_language=["low teak or ash platform bench with flat cushion", "simple stone or concrete low table", "single large ceramic planter"],
        material_palette=["honed concrete or natural stone paving", "matte charcoal planter", "natural linen outdoor cushion"],
        lighting_behavior="Low warm ground uplights on planting + single warm lantern on plinth; minimal overhead.",
        decor_language=["single specimen tree — maple or birch", "raked gravel or moss ground plane"],
        realism_constraints=["bench at correct low height — 35–40 cm seat", "planting sparse and intentional"],
        room_specific_constraints=["single furniture grouping only — seating zone only", "raked gravel or ground plane clearly defined"],
        visible_transition_logic="stone paving continues from interior ash floor; furniture palette echoes interior joinery visible through glass",
        negative_rules=["no rattan outdoor furniture", "no string lights", "no potted herb collection", "no coloured cushions"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="japandi_calm",
        room_type="facade",
        furniture_language=["timber-clad facade in shou sugi ban or pale ash boards", "recessed entrance with stone threshold", "simple matte steel or timber gate"],
        material_palette=["charred timber or pale ash board cladding", "raw concrete or stone plinth base", "matte black steel window frames"],
        lighting_behavior="Concealed ground uplights washing cladding vertically + single warm entrance lantern.",
        decor_language=["clean horizontal board rhythm", "single specimen tree in gravel forecourt"],
        realism_constraints=["timber board joints at correct weathered scale", "window reveals deep enough to cast shadow line"],
        room_specific_constraints=["maximum two materials on facade — no mixing", "entrance door recessed into facade plane"],
        visible_transition_logic="charred timber tone flows to boundary fence; stone threshold echoes interior floor material",
        negative_rules=["no warm sand render", "no decorative ironwork", "no warm brick", "no suburban window proportions"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="japandi_calm",
        room_type="dining_room",
        furniture_language=["low rectangular ash dining table", "simple benches or low-back ash chairs", "wall-mounted ash credenza"],
        material_palette=["pale ash floor", "wabi-sabi plaster finish on existing walls", "natural linen chair upholstery or bare ash seat"],
        lighting_behavior="Single washi paper pendant hung low over table; warm diffused glow, no direct spot.",
        decor_language=["single ceramic bowl centrepiece", "one ikebana branch on credenza"],
        realism_constraints=["pendant at correct dining height — 70–75 cm above table", "bench seat at correct height for table"],
        room_specific_constraints=["table for 4–6 only — not oversized", "credenza top with single object only"],
        visible_transition_logic="ash floor and plaster continue from living room; ceramic palette echoes kitchen visible beyond",
        negative_rules=["no upholstered chair backs", "no tablecloth", "no multi-pendant cluster", "no displayed sideboard objects"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="japandi_calm",
        room_type="balcony",
        furniture_language=["low single-seat platform chair in ash", "small raw concrete side table", "single ceramic pot with bonsai or bamboo grass"],
        material_palette=["honed stone or timber-composite balcony floor", "matte charcoal balustrade", "natural linen cushion"],
        lighting_behavior="Single small warm lantern on floor or wall; no overhead electric fixture.",
        decor_language=["single intentional plant in ceramic pot", "folded natural linen on chair"],
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
        decor_language=["single specimen tree at pool edge", "raked gravel or moss ground plane beyond deck"],
        realism_constraints=["pool coping flush with deck — no raised lip", "daybed at correct low height"],
        room_specific_constraints=["dark pool liner preferred — slate or charcoal tone", "maximum 2 daybeds — no furniture overcrowding"],
        visible_transition_logic="dark stone deck continues to terrace; charred timber facade visible as backdrop",
        negative_rules=["no travertine (too warm)", "no bright parasols", "no sun lounger parade", "no colourful pool water"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="japandi_calm",
        room_type="garden",
        furniture_language=["single low ash bench", "large specimen Japanese maple or birch tree", "raked gravel or moss ground zone"],
        material_palette=["dark slate stepping stone path", "moss or raked gravel ground plane", "raw concrete or stone planter"],
        lighting_behavior="Low warm uplights on specimen tree + single stone lantern on plinth; no path strip lighting.",
        decor_language=["raked gravel as design element", "carefully pruned shrub or topiary mass"],
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
        decor_language=["single dried botanical in ceramic", "wall left deliberately empty — no artwork"],
        realism_constraints=["shelf wall-anchored with no visible brackets", "mirror sized to match shelf width"],
        room_specific_constraints=["single object on shelf — discipline enforced", "no coat hooks or visible storage"],
        visible_transition_logic="stone floor and plaster flow directly into living room; ash palette echoes throughout",
        negative_rules=["no console with legs", "no coat rack", "no cluttered entry objects", "no warm oak tone"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="japandi_calm",
        room_type="home_office",
        furniture_language=["wall-mounted ash floating desk — no legs", "minimal upright chair in ash with linen seat pad", "single floating ash shelf above desk"],
        material_palette=["pale ash floor", "wabi-sabi plaster finish on existing walls", "matte black desk accessories"],
        lighting_behavior="Single adjustable matte black task arm lamp on desk; warm ambient cove only.",
        decor_language=["single ceramic pen pot", "one small moss ball or air plant in ceramic"],
        realism_constraints=["floating desk correctly wall-anchored — no visible cantilever sag", "chair at correct desk height"],
        room_specific_constraints=["zero cable visibility — all routed inside wall", "shelf with maximum 5 items total"],
        visible_transition_logic="ash desk and plaster walls flow into adjacent hallway; matte black accents echo door hardware",
        negative_rules=["no standard desk with legs", "no ergonomic chair styling", "no monitor stand clutter", "no pin board or sticky notes"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="japandi_calm",
        room_type="driveway",
        furniture_language=["raked gravel forecourt with single specimen tree", "flat dark stone entrance path", "simple matte black gate"],
        material_palette=["dark slate or honed stone driveway surface", "raw concrete gate pillars", "raked gravel infill"],
        lighting_behavior="Low warm ground uplights on specimen tree + single lantern at gate post; no overhead lights.",
        decor_language=["single Japanese maple or birch at forecourt edge", "raked gravel pattern visible from gate"],
        realism_constraints=["gravel at correct loose depth — not compacted solid", "tree at correct planted scale for forecourt"],
        room_specific_constraints=["single tree, one boundary element — no cluttered planting", "gate in single material — no mixing"],
        visible_transition_logic="dark stone path continues to entrance threshold; charred timber facade visible from gate",
        negative_rules=["no warm sand render boundary", "no ornate gate", "no manicured hedging rows", "no lantern overuse"],
    ),
]:
    register(_d)
