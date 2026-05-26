from ._base import AtmosphereCoreDNA, RoomAdaptationDNA, register_core, register

register_core(AtmosphereCoreDNA(
    atmosphere_id="desert_luxe",
    philosophy="Middle Eastern contemporary luxury inspired by desert architecture and sculptural calm.",
    emotional_intent="Sculptural, warm, monumental, serene, sun-bleached, timelessly opulent.",
    architectural_language="Monolithic forms in sand and terracotta, deep shadow reveals, and tactile plaster surfaces referencing desert vernacular architecture.",
    material_palette=["sand-toned tadelakt or micro-cement plaster", "warm terracotta or sandstone", "walnut or cedar timber", "hammered brass or copper", "raw cotton or camel leather"],
    lighting_behavior="Warm low-angled light — concealed slots mimicking desert sun raking, hammered metal lanterns.",
    luxury_level="Dubai penthouse / Aman desert resort",
    forbidden_elements=["Theme park Morocco styling", "excessive ornamentation", "oversaturated orange tones", "arabesque pattern overuse", "fake gold"],
    atmosphere_keywords=["tadelakt", "sandstone", "desert monolith", "hammered brass", "sculptural warmth"],
))

for _d in [
    RoomAdaptationDNA(
        atmosphere_id="desert_luxe",
        room_type="living_room",
        furniture_language=["raw cotton or camel leather — tactile desert warmth", "solid sandstone or terracotta — sun-drenched surface warmth", "carved wood — artisan surface richness"],
        material_palette=["polished tadelakt floor in sand or warm ivory", "tadelakt plaster walls in terracotta or warm sand", "walnut or cedar timber accents"],
        lighting_behavior="Single hammered brass pendant + concealed warm floor slot; low-angled warm glow.",
        # Wave 5.5.27 — REPLACED textile throw on sofa with seating-footprint
        # rug. Throw + rug overlap ; rug at floor-level more impactful for
        # inhabitation realism.
        decor_language=["single large dark ceramic vessel — empty", "woven raw-cotton or camel-tone rug within the seating footprint"],
        realism_constraints=["sofa low — 40–45 cm — correct desert floor culture scale", "plaster texture visible — not flat paint"],
        # Wave 5.5.40 — minimal TV-only remediation per Wave 5.5.33 audit
        # Option A. Slot [0] becomes standardized TV anchor (WM pattern,
        # atm-coherent options: sandstone niche + artwork + television).
        # Previous "no pattern on walls — tadelakt is the texture" dropped
        # entirely: the "no pattern" anti-pattern intent is already covered
        # by existing negative_rules[0] "no arabesque tile pattern" and the
        # "tadelakt is the texture" half was redundant with material_palette
        # which already mandates tadelakt walls. No fix on kitchen
        # continuity or material override this wave (Desert kept minimal-
        # investment per user direction 2026-05-25 pending Phase 2 review).
        # Wave 5.5.43 — TV-first reorder. Bench 2026-05-25 showed the
        # model picking "sandstone niche" (matching Desert's mineral
        # identity) instead of TV.
        # Wave 5.5.46 — TV baseline pattern. Wave 5.5.43 TV-first reorder
        # still didn't emit TV (Desert mineral identity too dominant).
        # New pattern makes TV the SUBJECT of the constraint, not an
        # option in a list.
        room_specific_constraints=["television positioned on a single clear focal wall — not multiple competing focal walls", "maximum 2 decorative objects in room"],
        visible_transition_logic="tadelakt floor and plaster walls continue into adjacent rooms; warm sand palette unbroken through visible spaces",
        negative_rules=["no arabesque tile pattern", "no cold marble", "no bright orange", "no maximalist Moroccan styling"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="desert_luxe",
        room_type="master_bedroom",
        furniture_language=["warm timber or sandstone — low platform surface warmth", "tadelakt or stone slab — tactile warmth at night level", "hammered brass — warm metallic mirror richness"],
        material_palette=["polished tadelakt floor", "tadelakt plaster walls in warm sand or terracotta", "raw cotton or camel linen bedding"],
        lighting_behavior="Concealed warm slot above headboard wall + single hammered brass wall sconce at bedside.",
        # Wave 5.5.27 — REPLACED carved wooden object with bedside rug.
        # Decor object → essential rug for bedroom inhabitation realism.
        decor_language=["layered raw cotton and natural linen bedding in sand tones", "woven cotton rug at the bedside in sand tones"],
        realism_constraints=["platform bed at correct low height — 35–40 cm", "tadelakt walls with correct reflective polish — not flat"],
        room_specific_constraints=["monochrome sand-toned palette for all bedding", "no artwork — wall left as plaster composition"],
        visible_transition_logic="tadelakt floor and warm plaster flow into ensuite; sand-toned palette continuous",
        negative_rules=["no patterned bedding", "no chrome hardware", "no cold-toned palette", "no ornate headboard"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="desert_luxe",
        room_type="kitchen",
        furniture_language=["tadelakt-fronted cabinetry in warm sand tone", "thick sandstone or terracotta slab countertop", "open cedar or walnut shelf with simple clay vessels"],
        material_palette=["tadelakt cabinet fronts in sand or terracotta", "sandstone or warm stone countertop", "hammered brass hardware"],
        lighting_behavior="Concealed warm under-cabinet strip + single hammered brass pendant over island.",
        decor_language=["three matching clay or terracotta vessels on open shelf", "single carved wooden board on counter"],
        realism_constraints=["countertop at correct 90 cm height", "tadelakt surface with correct polished texture"],
        room_specific_constraints=["hammered brass hardware throughout — no mixing finishes", "countertop in single stone — no tile"],
        visible_transition_logic="warm tadelakt and sandstone echo into dining area; hammered brass hardware palette visible through opening",
        negative_rules=["no white cabinetry", "no chrome hardware", "no cold stone countertop", "no patterned tile backsplash"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="desert_luxe",
        room_type="bathroom",
        furniture_language=["full tadelakt wet room — walls and floor continuous", "freestanding stone soaking tub — sandstone or terracotta composite", "single hammered brass basin on stone slab"],
        material_palette=["tadelakt walls and floor in warm sand or terracotta", "sandstone or stone slab vanity", "hammered brass fixtures throughout"],
        lighting_behavior="Single concealed warm slot at ceiling perimeter; room lit by raking warm glow — hammam-adjacent.",
        # Wave 5.5.27 Phase 3b — REPLACED carved wooden stool (decorative
        # accent) with mirror. Anchored to "the basin" — existing hammered
        # brass basin per furniture_language.
        decor_language=["hammered brass-framed mirror above the basin", "folded raw cotton towels on cedar wall peg"],
        realism_constraints=["tadelakt floor and walls correctly seamless — no grout lines", "stone tub at correct weight and floor-standing scale"],
        room_specific_constraints=["tadelakt throughout — no mixed surface", "all fixtures hammered brass — single finish"],
        visible_transition_logic="tadelakt continues from bedroom floor without threshold; warm sand palette continuous",
        negative_rules=["no white tiles", "no chrome fixtures", "no cold stone", "no Western-bathroom accessories"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="desert_luxe",
        room_type="terrace",
        furniture_language=["low platform bench in carved timber or sandstone", "carved stone or tadelakt low table", "canvas shade sail or timber pergola with fabric drape"],
        material_palette=["large-format sandstone or terracotta paving", "warm cotton outdoor cushions in sand or camel", "cedar or timber overhead structure"],
        lighting_behavior="Hammered brass floor lanterns + warm concealed strip under pergola beam; desert evening warmth.",
        decor_language=["single large ceramic planter with agave or desert plant", "woven cotton cushion pile in sand tones"],
        realism_constraints=["paving at correct level with correct joint lines", "shade structure at correct clearance height"],
        room_specific_constraints=["cushion palette in sand, camel, warm ivory only", "single large planting focal element — not a garden"],
        visible_transition_logic="sandstone paving continues to pool deck; warm tadelakt facade visible through pergola structure",
        negative_rules=["no rattan furniture", "no bright cushion colours", "no coloured lanterns", "no string lights"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="desert_luxe",
        room_type="facade",
        furniture_language=["monolithic smooth tadelakt or sand render facade", "deep-set window reveals casting shadow lines", "heavy solid timber pivot door"],
        material_palette=["smooth tadelakt or sand micro-cement render", "warm sandstone base or threshold detail", "hammered brass or copper door hardware"],
        lighting_behavior="Concealed warm ground uplights washing facade + single hammered brass lantern at entrance.",
        decor_language=["facade as sculptural monolith — no decoration", "single specimen agave or olive in white gravel forecourt"],
        realism_constraints=["render texture smooth but not CGI-perfect — slight material variation", "deep window reveals at correct shadow-casting depth"],
        room_specific_constraints=["single facade material — tadelakt render only", "no decorative elements on facade — mass is the design"],
        visible_transition_logic="warm render continues to boundary wall and gate pillars; sandstone threshold echoes interior floor",
        negative_rules=["no cold grey render", "no Moorish arch decoration", "no mixed materials on facade", "no warm orange over-saturation"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="desert_luxe",
        room_type="dining_room",
        furniture_language=["large sandstone or warm timber dining table — solid monolithic slab", "upholstered chairs in raw cotton or camel leather", "carved timber or tadelakt sideboard"],
        material_palette=["polished tadelakt floor", "tadelakt walls in warm sand", "raw cotton or leather upholstery"],
        lighting_behavior="Single hammered brass pendant hung low over table; warm focused glow — dining as ceremony.",
        decor_language=["single carved stone or ceramic centrepiece — empty vessel", "two hammered brass candleholders flanking centrepiece"],
        realism_constraints=["pendant at correct height — 70–80 cm above table", "chairs at correct seat height for table"],
        room_specific_constraints=["monolithic table — single slab material, not mixed", "centrepiece in single element — not arrangement"],
        visible_transition_logic="tadelakt floor and warm walls echo living room; hammered brass continues through to kitchen fixtures",
        negative_rules=["no cold marble table", "no patterned chair upholstery", "no maximalist table setting", "no chandelier"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="desert_luxe",
        room_type="balcony",
        furniture_language=["single carved timber or stone platform seat", "small sandstone side table", "single large ceramic or terracotta planter with agave"],
        material_palette=["sandstone or tadelakt balcony floor", "warm render or tadelakt balustrade", "warm cotton cushion"],
        lighting_behavior="Single hammered brass wall lantern; warm intimate desert-evening tone.",
        decor_language=["large agave or desert plant in terracotta planter", "woven cotton cushion in sand or camel"],
        realism_constraints=["seat at correct height — 40 cm", "balustrade in render or solid — no glass or metal rail"],
        room_specific_constraints=["single seating element only", "single desert plant — not multiple pots"],
        visible_transition_logic="sandstone floor echoes interior tadelakt; warm glow of interior visible through glass",
        negative_rules=["no rattan", "no plastic", "no coloured cushions", "no multiple plant pots"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="desert_luxe",
        room_type="pool_area",
        furniture_language=["carved stone or timber sun platforms — not loungers", "canvas shade sail on heavy timber post", "stone or tadelakt low side table"],
        material_palette=["large-format sandstone pool deck", "warm stone pool coping", "warm canvas shade material"],
        lighting_behavior="Warm underwater lighting with slight warm tint + hammered brass uplights at coping; dusk desert tone.",
        decor_language=["single large agave or specimen cactus in stone planter at pool end", "deck as pure stone plane — no furniture clutter"],
        realism_constraints=["pool deck at correct level — continuous with surrounding grade", "platform at correct height for repose — not standard lounger"],
        room_specific_constraints=["platform-style repose — not resort-style lounger parade", "warm-toned pool liner — not blue"],
        visible_transition_logic="sandstone deck continues to terrace; tadelakt facade visible as monolithic backdrop",
        negative_rules=["no bright blue pool", "no resort-style lounger row", "no bright parasols", "no cold stone deck"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="desert_luxe",
        room_type="garden",
        furniture_language=["single carved stone bench", "white gravel or crushed stone ground plane", "single specimen agave or olive tree"],
        material_palette=["white crushed stone or pale gravel ground plane", "warm sandstone path", "carved stone bench and planters"],
        lighting_behavior="Single warm ground uplight on specimen plant + concealed path strip; desert garden at dusk.",
        decor_language=["single architectural agave or euphorbia as focal element", "raked white gravel as contemplative ground plane"],
        realism_constraints=["gravel at correct depth — loose but not floating", "plant at correct scale for garden"],
        room_specific_constraints=["desert plant palette only — no lush tropical planting", "maximum 2 plant species"],
        visible_transition_logic="white gravel and sandstone path continue to terrace; warm rendered facade visible at garden edge",
        negative_rules=["no lush tropical planting", "no lawn", "no mixed stone types", "no decorative ornaments"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="desert_luxe",
        room_type="entrance_hall",
        furniture_language=["carved stone or tadelakt console slab — wall-mounted", "large hammered brass mirror", "single large dark ceramic vessel"],
        material_palette=["polished tadelakt floor", "tadelakt plaster walls in warm sand", "hammered brass accents"],
        lighting_behavior="Single concealed warm ceiling slot over console; arrival through raking warm beam.",
        decor_language=["single large dark ceramic — empty, sculptural", "no artwork — warm plaster wall as composition"],
        realism_constraints=["console at correct 80–85 cm height", "mirror height 150 cm+ for proportion"],
        room_specific_constraints=["single sculptural object on console — nothing else", "no coat hooks, no storage visible"],
        visible_transition_logic="tadelakt floor and warm plaster flow into living room; hammered brass hardware echoes throughout",
        negative_rules=["no cold stone or tile floor", "no ornate Moroccan mirror", "no accessory cluster", "no coat rack"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="desert_luxe",
        room_type="home_office",
        furniture_language=["solid sandstone slab desk on warm timber trestle", "upholstered chair in raw cotton or camel leather", "floating cedar or walnut shelf"],
        material_palette=["polished tadelakt floor", "tadelakt walls in warm sand", "cedar or walnut desk and shelf"],
        lighting_behavior="Single warm hammered brass desk lamp + concealed warm cove; no cold task light.",
        decor_language=["single clay vessel as pen holder", "one smooth river stone as paperweight — nothing more"],
        realism_constraints=["desk at correct 72–75 cm working height", "shelf with maximum 5 items — restraint enforced"],
        room_specific_constraints=["zero cable visibility", "no monitor stand clutter — single flush screen only"],
        visible_transition_logic="tadelakt floor and warm plaster flow into adjacent rooms; warm material palette continuous",
        negative_rules=["no cold white LED", "no conventional office chair", "no exposed cable tangle", "no tech accessory clutter"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="desert_luxe",
        room_type="driveway",
        furniture_language=["smooth tadelakt or sand render gate pillars", "compacted sand or warm gravel driveway", "single specimen agave or palm at forecourt"],
        material_palette=["warm compacted sand or beige gravel driveway", "smooth tadelakt render gate pillars", "hammered brass lanterns"],
        lighting_behavior="Hammered brass lanterns on gate pillars + concealed warm ground uplight on specimen; warm desert arrival.",
        decor_language=["single agave or desert palm at forecourt as focal element", "clean gravel forecourt — no clutter"],
        realism_constraints=["gravel at correct depth — not floating stones", "gate pillars at correct proportional height"],
        room_specific_constraints=["warm gravel or sand surface only — no pavement", "gate pillars in same tadelakt render as facade"],
        visible_transition_logic="warm gravel continues to entrance threshold; monolithic tadelakt facade visible from gate",
        negative_rules=["no cold grey paving", "no ornate gate", "no hedging borders", "no cold white rendered boundary"],
    ),
]:
    register(_d)
