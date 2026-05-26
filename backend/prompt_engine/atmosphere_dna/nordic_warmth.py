from ._base import AtmosphereCoreDNA, RoomAdaptationDNA, register_core, register

register_core(AtmosphereCoreDNA(
    atmosphere_id="nordic_warmth",
    philosophy="Scandinavian comfort, warmth, coziness, and emotional softness.",
    emotional_intent="Cozy, hygge, warm, intimate, human-scaled, reassuring, softly joyful.",
    architectural_language="Human-scaled rooms with pitched or low ceilings, natural birch and pine, layered wool and sheepskin in a white-to-warm-oat palette.",
    material_palette=["white-painted birch or pine", "natural wool and sheepskin", "warm white plaster", "pale stone or concrete", "amber glass"],
    lighting_behavior="Warm candle-adjacent ambient — floor lamps with amber shades, hanging filament bulbs, no harsh overhead.",
    luxury_level="Premium Scandinavian retreat",
    forbidden_elements=["Cold Ikea minimalism", "ultra modern sharpness", "excessive black accents", "industrial rawness", "high-gloss surfaces"],
    atmosphere_keywords=["hygge", "birch", "wool", "warm white", "candlelight"],
))

for _d in [
    RoomAdaptationDNA(
        atmosphere_id="nordic_warmth",
        room_type="living_room",
        furniture_language=["natural wool in oat or undyed — deep hygge tactile warmth", "birch or pine timber — warm natural surface depth", "sheepskin — natural undyed tactile softness"],
        material_palette=["wide-plank pine or birch floor", "warm white plaster walls", "natural wool upholstery in oat or undyed tones"],
        lighting_behavior="Amber floor lamp behind sofa + hanging filament bulb pendant; candle-warm, no ceiling wash.",
        decor_language=["cluster of amber or clear glass candle holders on coffee table", "woven basket with wool throw at sofa end"],
        realism_constraints=["sofa at normal residential height — 45 cm", "candleholders at varied heights — not matching set"],
        # Wave 5.5.22 — added "a television" as third focal option.
        # Wave 5.5.34 — dropped "if present" + added "not multiple" cap.
        # Wave 5.5.43 — TV-first reorder.
        # Wave 5.5.49 — adopting universal media console flex pattern
        # (same fix as WM 5.5.49 + Soft Luxury / Nature / Desert 5.5.48).
        # Allows TV placement on existing wall OR media console; explicitly
        # forbids creating a new wall. Standardized across all atmospheres
        # to prevent wall-invention side effects.
        room_specific_constraints=["layered rugs permitted — wool flatweave under pile", "television visible in living area on existing wall surface or media console — never on a newly created wall"],
        # Wave 5.5.34b — dropped "visible bedroom door" reference. Bench
        # 2026-05-25 showed the model literally invented a bedroom zone +
        # glass partition when the photo had no bedroom. Replaced with the
        # neutral "adjacent rooms" + a conditional kitchen mention so the
        # kitchen-visibility signal stays without inventing new spaces.
        visible_transition_logic="pine floor and warm white plaster continue into adjacent rooms; wool palette echoes through visible kitchen if present",
        negative_rules=["no sleek dark furniture", "no chrome accents", "no minimalist floating shelves", "no cold grey palette"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="nordic_warmth",
        room_type="master_bedroom",
        furniture_language=["pine or birch timber — warm natural tactile surface", "birch timber — amber glass warmth at low level", "sheepskin — natural undyed floor-level softness"],
        material_palette=["pine or birch floor", "warm white plaster finish on existing walls", "layered natural linen and wool bedding"],
        lighting_behavior="Amber glass bedside table lamps + concealed warm slot above headboard wall.",
        decor_language=["layered linen and wool bedding in oat, ecru, and natural undyed", "small framed botanical print above nightstand"],
        realism_constraints=["bed frame at correct height — 45 cm to mattress top", "bedding layered with visible weight and texture"],
        room_specific_constraints=["sheepskin at one side of bed only — not both sides", "window with simple linen curtains, not full drapes"],
        visible_transition_logic="pine floor and warm white plaster flow into ensuite; linen bedding palette echoes bathroom towels",
        negative_rules=["no dark headboard", "no cold white bedding", "no high-gloss surfaces", "no patterned wallpaper"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="nordic_warmth",
        room_type="kitchen",
        furniture_language=["white-painted shaker or flat-front cabinetry", "solid birch or butcher-block countertop", "open pine shelf with ceramics and glassware"],
        material_palette=["white-painted cabinetry", "birch or pine countertop", "white subway or handmade tile backsplash"],
        lighting_behavior="Warm pendant over island or table + under-cabinet strip in warm 2700K; inviting work light.",
        decor_language=["open pine shelf with 4–6 handmade ceramic pieces", "single potted herb on windowsill — one only"],
        realism_constraints=["butcher block countertop at residential 60 cm depth", "cabinet doors at standard 220 cm height"],
        room_specific_constraints=["open shelf with ceramics — not clutter", "white tile backsplash in handmade format — not industrial"],
        visible_transition_logic="white cabinetry and pine floor echo into dining area; warm ceramic palette visible from living room",
        negative_rules=["no dark cabinetry", "no stainless steel countertop", "no industrial fixtures", "no glossy white tile"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="nordic_warmth",
        room_type="bathroom",
        furniture_language=["white-painted timber vanity with ceramic basin", "freestanding cast iron or steel soaking tub in white", "simple pine slatted bath mat"],
        material_palette=["white handmade tile floor and walls", "white-painted timber vanity", "brushed nickel or matte black fixtures"],
        lighting_behavior="Single pendant in amber glass above tub + warm wall sconce above vanity mirror.",
        # Wave 5.5.27 Phase 3b — REPLACED pine slat bath mat (redundant —
        # already in furniture_language) with mirror (bathroom essential).
        # Mirror anchored to existing white-painted vanity (matches DNA
        # vanity material in furniture_language).
        decor_language=["simple round mirror in matte nickel or pine frame above the white-painted vanity", "folded linen towels in oat or undyed on wall peg"],
        realism_constraints=["cast iron tub at correct floor-standing weight scale", "tile grout lines correct — 3–5 mm, not perfect CGI"],
        room_specific_constraints=["fixtures all in one finish — brushed nickel or matte black, not both", "no chrome"],
        visible_transition_logic="white tile and pine tone continue into dressing area; linen towel palette echoes bedroom bedding",
        negative_rules=["no cold grey tile", "no chrome fixtures", "no hospital-white clinical styling", "no mirrored vanity cabinet"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="nordic_warmth",
        room_type="terrace",
        furniture_language=["painted pine or teak outdoor table and chairs", "thick wool or cotton outdoor cushions in oat or undyed", "simple canvas or pine pergola"],
        material_palette=["natural stone or painted timber decking", "wool or cotton outdoor cushions in warm white or oat", "amber glass outdoor lanterns"],
        lighting_behavior="Amber glass outdoor lanterns on table + warm string lights on pergola beam — hygge outdoor ambience.",
        decor_language=["amber glass candle holders on table", "wool throw draped over chair for cooler evenings"],
        realism_constraints=["outdoor furniture at correct residential scale", "string lights on timber beam — not plastic"],
        room_specific_constraints=["dining set permitted on terrace — Nordic outdoor dining culture", "fire pit or brazier as optional focal element"],
        visible_transition_logic="stone or timber deck continues to garden; warm interior light and white walls visible through glass",
        negative_rules=["no plastic furniture", "no cold grey paving", "no modern angular furniture", "no bright colour cushions"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="nordic_warmth",
        room_type="facade",
        furniture_language=["white-painted timber cladding or white render", "painted timber window frames in white or pale grey", "simple timber entrance door in white or natural pine"],
        material_palette=["white-painted timber board cladding", "pale stone or concrete plinth base", "brushed nickel or matte black door hardware"],
        lighting_behavior="Warm lanterns flanking entrance + concealed warm eave lighting; hygge approach tone.",
        decor_language=["simple planting at entrance — lavender or ornamental grass in stone pot", "single wreath or seasonal botanical at door"],
        realism_constraints=["timber board joints at correct painted weathered scale", "window proportions Nordic — tall and vertical or square"],
        room_specific_constraints=["white or near-white as primary facade colour", "entrance door clearly readable at facade centre"],
        visible_transition_logic="white cladding tone echoes interior white walls; pine door frame matches interior timber palette",
        negative_rules=["no dark timber cladding", "no warm sand render", "no UPVC frames", "no contemporary flat black"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="nordic_warmth",
        room_type="dining_room",
        furniture_language=["solid birch or pine round dining table", "upholstered dining chairs in natural linen or wool", "painted pine or white sideboard"],
        material_palette=["pine floor", "warm white plaster finish on existing walls", "natural linen or wool chair upholstery"],
        lighting_behavior="Pendant in amber glass or paper shade hung low over table; warm evening ambience.",
        decor_language=["cluster of candles as centrepiece", "simple ceramic or wooden bowl with pine cones or seasonal objects"],
        realism_constraints=["pendant at correct height — 70–75 cm above table", "chairs at correct seat height for table"],
        room_specific_constraints=["round or oval table preferred — conversation-friendly", "candles as centrepiece — not flowers"],
        visible_transition_logic="pine floor and white plaster echo kitchen; linen chair upholstery palette continues from living room",
        negative_rules=["no glass or marble table top", "no matching chair-and-table set in dark finish", "no chandelier", "no maximalist tablescaping"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="nordic_warmth",
        room_type="balcony",
        furniture_language=["two painted pine folding chairs or simple armchairs", "small round birch or pine table", "single pot with trailing ivy or lavender"],
        material_palette=["pine or composite timber decking", "white or warm grey balustrade", "wool outdoor cushions in oat"],
        lighting_behavior="Single amber glass lantern on table; warm hygge tone — no wall sconce.",
        decor_language=["amber glass candle holder", "simple wool throw folded on chair back"],
        realism_constraints=["chairs at correct height for small table", "balustrade at safety height"],
        room_specific_constraints=["simple table-and-chairs only — no lounger", "one plant pot — not a collection"],
        visible_transition_logic="pine decking echoes interior floor; white wall and warm interior light visible through glass",
        negative_rules=["no rattan", "no modern angular design", "no plastic", "no coloured cushions"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="nordic_warmth",
        room_type="pool_area",
        furniture_language=["pine or teak sun loungers with natural canvas cushions", "simple timber-frame canvas parasol", "stone or pine side table"],
        material_palette=["natural timber or honed stone pool deck", "natural canvas cushion fabric", "white or pale painted pool surround"],
        lighting_behavior="Warm underwater lighting (soft warm white) + amber lanterns at deck perimeter.",
        decor_language=["simple arrangement of rounded stones at pool corner", "single planted urn with ornamental grass"],
        realism_constraints=["loungers at correct residential scale — not resort-runway", "pool coping at correct level above deck"],
        room_specific_constraints=["natural materials only — no plastic furniture", "light-coloured pool liner — not dark"],
        visible_transition_logic="timber deck continues to terrace; white house facade visible as backdrop",
        negative_rules=["no bright parasols", "no plastic loungers", "no blue chrome water emphasis", "no over-planted surround"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="nordic_warmth",
        room_type="garden",
        furniture_language=["painted pine garden bench", "simple stone or gravel path", "naturalistic planting with wildflowers and ornamental grasses"],
        material_palette=["pale stone or gravel path", "painted pine garden bench", "naturalistic planting in greens and whites"],
        lighting_behavior="Low warm path lights + amber lantern on table; garden in warm evening glow.",
        decor_language=["birdbath in simple stone", "naturalistic wildflower planting at borders"],
        realism_constraints=["gravel path at correct depth and edge", "bench at correct seat height"],
        room_specific_constraints=["naturalistic planting style — not formal clipped", "single grass species as ground layer"],
        visible_transition_logic="stone path continues to terrace; white house facade visible at garden edge",
        negative_rules=["no formal clipped hedging", "no mixed paving materials", "no plastic garden accessories", "no manicured lawn obsession"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="nordic_warmth",
        room_type="entrance_hall",
        furniture_language=["painted pine console or bench with woven basket below", "simple round mirror in pine or white frame", "single hook rail in white-painted pine"],
        material_palette=["pine or stone floor", "warm white plaster finish on existing walls", "white-painted pine joinery"],
        lighting_behavior="Single amber glass pendant + warm wall sconce; welcoming arrival warmth.",
        decor_language=["single dried botanical in ceramic vase on console", "small framed botanical print above console"],
        realism_constraints=["console at correct 80–85 cm height", "mirror at correct eye-level placement"],
        room_specific_constraints=["hook rail for coats — visible but neat", "woven basket below console for shoes"],
        visible_transition_logic="pine floor and white plaster flow into living room; warm palette continuous",
        negative_rules=["no dark or industrial entry", "no cold stone floor", "no minimalist ledge-only entry", "no cluttered coat pile"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="nordic_warmth",
        room_type="home_office",
        furniture_language=["solid birch or pine desk with turned legs", "upholstered chair in natural linen or wool", "open pine bookshelf with edited book collection"],
        material_palette=["pine floor", "warm white plaster finish on existing walls", "natural linen or wool upholstery"],
        lighting_behavior="Amber glass desk lamp + warm ambient from floor lamp in corner; no cold task light.",
        decor_language=["small plant on desk corner — succulent or moss", "curated book spines in neutral tones on shelf"],
        realism_constraints=["desk at correct 72–75 cm working height", "chair at correct seat height"],
        room_specific_constraints=["cable management — minimal visible cables", "bookshelf not overloaded — breathing space between items"],
        visible_transition_logic="pine floor and white walls echo hallway; warm amber lamp palette matches living room floor lamps",
        negative_rules=["no cold white LED task light", "no dark wood desk", "no ergonomic rubber chair", "no cable clutter"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="nordic_warmth",
        room_type="driveway",
        furniture_language=["simple painted timber gate in white or pale grey", "stone or gravel driveway with painted timber edging", "lanterns on painted pine or stone pillars"],
        material_palette=["pale gravel or pale stone driveway", "white or pale grey painted timber gate", "warm amber lanterns at pillars"],
        lighting_behavior="Warm amber lanterns at gate pillars + low warm path lights along drive edge.",
        decor_language=["simple clipped lavender or box flanking gate", "white-painted timber fence along boundary"],
        realism_constraints=["driveway at correct residential width — 3–3.5 m", "gate at correct proportional height"],
        room_specific_constraints=["single driveway material — gravel or pale stone", "white or pale painted fence — not dark"],
        visible_transition_logic="pale gravel continues to house approach; white facade visible from gate approach",
        negative_rules=["no dark render boundary", "no ornate ironwork", "no grey block paving", "no modern angular gate"],
    ),
]:
    register(_d)
