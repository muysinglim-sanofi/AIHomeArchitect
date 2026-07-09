from ._base import AtmosphereCoreDNA, RoomAdaptationDNA, register_core, register

register_core(AtmosphereCoreDNA(
    atmosphere_id="tropical_escape",
    philosophy="Open-air tropical living with relaxed contemporary luxury.",
    emotional_intent="Breezy, alive, relaxed-luxurious, sun-soaked, carefree but refined, vibrant-calm.",
    architectural_language="Open-plan volumes dissolving into landscape, tropical timber and whitewash, with a contemporary residential ease.",
    material_palette=["whitewashed or white render finish on existing walls", "tropical hardwood or louvred timber", "concrete or stone floor", "natural rattan or cane", "linen and cotton in white and sage"],
    lighting_behavior="Warm natural ambient — daytime brightness, warm concealed evening coves, rattan pendant lanterns.",
    luxury_level="Contemporary tropical villa",
    forbidden_elements=["Beach clichés", "fake resort styling", "overdecorated tropical kitsch", "bamboo overuse", "nautical or coastal motifs"],
    atmosphere_keywords=["tropical villa", "whitewash", "louvred timber", "rattan", "open-air luxury"],
))

for _d in [
    RoomAdaptationDNA(
        atmosphere_id="tropical_escape",
        room_type="living_room",
        furniture_language=["natural rattan or cane with thick white linen — tactile tropical warmth", "concrete or pale stone — cool surface texture depth", "louvred timber — warm tropical surface quality"],
        # Wave 5.5.51 preventive — "white render walls" -> "white render
        # finish on existing walls". Tropical hasn't shown wall invention
        # in bench, but the same plural-walls noun pattern that caused
        # issues for Japandi (5.5.39), Nature (5.5.37), and Desert
        # (5.5.51) was present here too. Applied preventively per user
        # direction 2026-05-25 to harden against future regressions on
        # different source photos.
        material_palette=["polished concrete or pale stone floor", "white render finish on existing walls", "louvred timber panels or shutters"],
        lighting_behavior="Warm rattan pendant + concealed warm ceiling slot; bright in day, warm in evening.",
        # Wave 5.5.27 — REPLACED rattan tray with seating-footprint rug.
        # Tray cosmetic ; rug essential. User-locked wording drops "or sisal"
        # for Tropical to reduce preserve-sensitive semantic pressure.
        # Wave 6.2a (2026-06-03) — pilot enrichment ROLLED BACK after bench
        # 2/4 wall invention. Root cause : Tropical core philosophy is
        # architecturally-permissive ("Open-plan volumes dissolving into
        # landscape", "Open-air luxury") and additional Tropical-coded items
        # amplify the "open villa" frame → model invents corner/wall to host
        # the floor-standing second plant. See [[wave-6-2a-regression]].
        decor_language=[
            "floor-length light natural linen or cotton curtains in off-white clearly framing each existing window, drawn open with the glass left fully clear — never covering, narrowing or blocking it, never on a glass partition",
            "single large tropical plant — bird of paradise or monstera in concrete pot",
            "simple jute rug within the seating footprint",
        ],
        realism_constraints=["sofa at normal residential height — 45 cm", "concrete floor with correct texture — not CGI smooth"],
        # Wave 5.5.25 fix #1 — softened "open side to terrace or garden" from
        # architectural directive to conditional. Original wording would
        # instruct the model to OPEN walls on indoor apartments without
        # terrace → wall modification. Now conditional on existing photo.
        # Wave 5.5.35 — WM-parity rewrite. Slot [0] becomes the
        # standardized TV anchor ("single clear focal wall - <opt1>, <opt2>,
        # or a television, not multiple"). Atmosphere-coherent options:
        # fireplace + plant. Conditional terrace moves to slot [1] (still
        # emitted by build_dna_room_context which uses [:2]). The previous
        # "plant as primary accent" slot is dropped because it duplicates
        # the plant option already in the TV anchor and competes for the
        # focal area.
        # Wave 5.5.43 — TV-first reorder.
        # Wave 5.5.49 — adopting universal media console flex pattern
        # (standardization across all atmospheres). Allows TV on existing
        # wall OR media console; explicitly forbids creating a new wall.
        room_specific_constraints=["include a television as the living-room focal point, placed on an existing wall or low media console directly in front of the primary seating, never behind the sofa, never behind the main seating, never on the rear wall behind the seating, never a new wall, and never by converting glazing into a wall. When a television is included, the television axis has priority over the garden/window view axis: arrange the main sofa so it faces the TV directly; keep the garden view as a side view or background view, never as the sofa's primary facing direction if that would place the TV behind the seating.", "where the photographed apartment shows an open side to terrace or garden, preserve and emphasize that opening"],
        # Wave 5.5.35 — drop hard "into terrace" (assumed terrace exists,
        # leak source on indoor apartments). Add explicit "visible kitchen"
        # continuity matching the WM pattern. Terrace kept as conditional.
        visible_transition_logic="white walls and concrete floor continue into adjacent rooms; rattan accents echo through visible kitchen or terrace if present",
        # Wave 5.12c — universal wall-preservation rule INSERTED at slot
        # [0]. Tropical had no defensive rule before — wall-invention
        # risk identified in audit. Trade-off : "no shell or driftwood
        # decor" demoted out of shipped [:3] AVOID (was [2], now [3]).
        # The room_specific_constraints already protect terrace openings
        # conditionally ; this rule adds the wall preservation half.
        # Wave 5.14c — softened wall rule (see WM for rationale).
        negative_rules=["no dark tropical furniture", "no nautical motifs", "no shell or driftwood decor", "no overly lush plant collection"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="tropical_escape",
        room_type="master_bedroom",
        # Wave 6.6 (2026-06-04) — master_bedroom VERY CAREFUL emotional
        # enrichment. Forbidden : resort/villa escalation, open-air wording,
        # louvred escalation. Only soft tropical textile + filtered daylight
        # + 1 restrained ceramic vase added. furniture_language[2] louvred
        # timber UNTOUCHED (Wave 6.4 family caution). room_specific_constraints
        # UNTOUCHED ("louvred shutters as primary window treatment" stays
        # per user task — no architectural pressure change). Room-scoped.
        furniture_language=["timber or rattan with white linen — tropical tactile warmth with relaxed natural folds", "cane or timber — natural surface warmth at low level", "louvred timber — warm shutter surface quality"],
        material_palette=["polished concrete or pale stone floor", "white render finish on existing walls", "white and sage linen bedding with light natural folds and airy texture"],
        lighting_behavior="Soft tropical daylight filtered through linen curtains + single rattan or woven pendant hung centrally above the existing bed + bedside ceramic or rattan shade lamp producing warm amber glow + concealed warm ceiling slot; calm tropical serenity.",
        # Wave 5.5.27 — REPLACED tropical leaf vase with bedside rug. Leaf
        # cosmetic ; rug essential.
        # Wave 6.6 (2026-06-04) — extended from 2 to 3 items (max per
        # FORBIDDEN villa escalation rule). Adds restrained ceramic vase
        # anchored on existing nightstand. Textile slot enriched with
        # "relaxed natural folds and airy texture".
        # Wave 6.7 (2026-06-04) — A+B applied CAREFULLY : 5 items.
        # Wave 6.11 (2026-06-04) — user-requested PHOTO-2 enrichment (tropical
        # villa restrained-richness reference). 5 → 8 items :
        #   • item 2 modified : "at the bedside" → "at the foot" (larger rug)
        #   • item 3 modified : "small tropical ceramic vase" → "with branches
        #     or tropical leaves" (matches photo bedside greenery)
        #   • NEW item 6 : tonal landscape/botanical artwork above headboard
        #   • NEW item 7 : 3-4 pillows of varied sizes (white+sage)
        #   • NEW item 8 : tall specimen plant (palm/monstera/leafy branch)
        #     in handmade ceramic or concrete floor pot
        #   • lighting : pendant centered + bedside lamp explicit
        #   • room_specific_constraints : "single plant" → "1-2 specimens
        #     (bedside + tall floor) + landscape artwork above headboard
        #     permitted" — relax for photo-2 alignment
        # Identity preserved : tropical palette (white+sage+jute+rattan+
        # ceramic+palm), louvred shutters constraint kept, NO villa/open-air
        # vocab added, NO louvred timber escalation.
        decor_language=[
            "floor-length light natural linen or cotton curtains in off-white clearly framing each existing window, drawn open with the glass left fully clear — never covering, narrowing or blocking it, never on a glass partition",
            "VISIBLY relaxed layered white and sage linen bedding with clearly natural asymmetric folds and airy texture — natural moment, not hotel turndown",
            "natural jute or sisal rug at the foot of the existing bed",
            "PROMINENTLY displayed small tropical ceramic vase with branches or tropical leaves on the existing nightstand",
            "open book or magazine on the existing nightstand",
            "small framed photograph on the existing dresser",
            "single tonal tropical landscape or botanical artwork in light wood frame above the existing headboard — only if bed wall is free, else omit",
            "3 to 4 linen pillows of varied sizes in white and sage tones on the existing bed",
            "tall tropical specimen plant — palm, monstera, or large leafy branch — in handmade ceramic or concrete floor pot adjacent to the existing window or wall",
        ],
        realism_constraints=["bed at correct height — 45 cm", "linen bedding with airy natural folds — not stiff"],
        room_specific_constraints=["louvred shutters as primary window treatment — no heavy curtains", "restrained tropical staging — 1-2 plant specimens (bedside accent + tall floor specimen) and single tonal landscape artwork above headboard permitted"],
        visible_transition_logic="white walls and concrete floor flow into ensuite; linen palette echoes bathroom towels",
        negative_rules=["no patterned bedding", "no dark furniture", "no air-con-box in scene", "no cluttered surfaces"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="tropical_escape",
        room_type="kitchen",
        # Wave 6.13b (2026-06-05) — kitchen enrichment (see WM block header).
        # Tropical col 3 AVOID ABSOLUMENT : jungle / Bali-Pinterest / trop plantes /
        # OBJETS AU SOL. So greenery is a SINGLE windowsill herb (no floor plant —
        # safety encoded directly in the decor item text, which always ships).
        # Held to 4 items ; airy linen + woven texture + light resort daylight.
        furniture_language=["white or whitewash cabinetry — shaker or flat-front", "pale concrete or white stone countertop", "open timber or rattan shelf with ceramic display"],
        material_palette=["white or whitewash cabinetry", "pale concrete or white stone countertop", "white or handmade tile backsplash"],
        lighting_behavior="Warm woven rattan pendant over the existing island + soft resort daylight flooding from the window + concealed under-cabinet strip; bright airy relaxed kitchen.",
        decor_language=[
            "light natural linen or cotton curtains in off-white framing the existing window, drawn open with the glass clear — never covering or blocking it, never on a glass partition; only where a window exists",
            "open shelf with 4 white or earth-tone ceramics — airy and uncrowded",
            "single small potted herb or tropical sprig in a white pot on the existing windowsill — one only, never on the floor",
            "a woven rattan tray or airy natural-linen tea towel on the existing counter — light resort texture",
            "single low bowl of tropical fruit in white ceramic on the existing island — one vessel only",
        ],
        realism_constraints=["cabinetry at correct residential height", "countertop at correct 90 cm height"],
        # Wave 6.13c (2026-06-05) — kitchen structure-preservation guard at [0] (see WM). Ships [:2].
        room_specific_constraints=["arrange cabinetry and island without covering, narrowing or relocating any existing window, doorway or wall opening — keep photographed openings fully clear", "open shelf mandatory — no upper cabinets to ceiling", "white or near-white only for cabinetry", "all greenery on windowsill or counter only — no floor-standing plants"],
        visible_transition_logic="white cabinetry and concrete floor echo dining area; tropical garden visible through kitchen window",
        negative_rules=["no dark cabinetry", "no stainless steel excess", "no busy tile pattern", "no chrome hardware"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="tropical_escape",
        room_type="bathroom",
        furniture_language=["white render or pale stone wet room", "freestanding stone or concrete tub", "simple timber or concrete vanity with white basin"],
        material_palette=["pale concrete or white render floor and walls", "white or off-white fixtures", "timber or concrete vanity"],
        lighting_behavior="Bright natural daytime light + concealed warm evening slot; clean tropical bathroom.",
        # Wave 5.5.27 Phase 3b — REPLACED tropical flower/leaf (decorative
        # accent) with mirror. User-locked wording : "above the existing
        # vanity" (simpler than "white-basin vanity").
        decor_language=["simple timber-framed mirror above the existing vanity", "folded white linen towels on timber peg"],
        realism_constraints=["wet room at correct seamless level — no step to shower", "tub at correct scale for room"],
        # Wave 5.5.25 fix #2 — softened "open or semi-open if villa allows"
        # from architectural directive to conditional. Original could push
        # model to open walls on apartments without villa context.
        room_specific_constraints=["white or near-white throughout — light and airy", "if the photographed bathroom is open-villa style, preserve openness"],
        visible_transition_logic="white render and concrete continue from bedroom; tropical garden visible if open outdoor bathroom",
        negative_rules=["no dark stone", "no chrome fixtures", "no closed cabinet-heavy bathroom", "no overly styled vanity top"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="tropical_escape",
        room_type="terrace",
        furniture_language=["rattan or cane outdoor sofa with thick white linen cushions", "concrete or pale stone low table", "timber pergola with louvred roof or shade sail"],
        material_palette=["large-format pale stone or concrete paving", "white linen outdoor cushions", "timber or louvred overhead structure"],
        lighting_behavior="Concealed warm strip under pergola beam + warm lanterns in rattan or brass; tropical evening.",
        # Wave 6.2a (2026-06-03) — pilot enrichment ROLLED BACK after bench
        # catastrophic regression : model REINVENTED the entire terrace scene
        # (new pergola, new surroundings, source NOT preserved at all). Root
        # cause : Tropical core ("open-plan dissolving into landscape" +
        # "open-air luxury") combined with +2 outdoor-coded items
        # (additional plant + lantern cluster) tipped the prompt into
        # "resort villa terrace from scratch" mode. See [[wave-6-2a-regression]].
        decor_language=["anchored to the existing terrace floor, parapet, garde-corps and any existing shade structure — existing architecture and openings kept exactly; no new walls, no enclosure, no building roof, no floor or deck extension",
                        "lush layered tropical planting filling the perimeter and any bare ground — heliconia, bird of paradise, banana leaf and palms in concrete or rattan planters",
                        "a pale stone or timber low table styled with rattan lanterns, a woven tray with a carafe and glasses and a bowl",
                        "thick white linen cushions and a woven throw layered on the sofa",
                        "a natural-fibre outdoor rug grounding the lounge zone",
                        "where the terrace is large enough, a teak or rattan dining table with cane chairs, set with rattan lanterns",
                        "a soft linen drape on the pergola or shade structure and rattan lanterns along the floor edge"],
        realism_constraints=["outdoor sofa at correct scale for terrace", "paving at correct level with correct joints"],
        room_specific_constraints=["outdoor seating facing garden or pool — open orientation", "tropical planting as terrace edge feature"],
        visible_transition_logic="pale stone paving continues to pool deck; interior white walls and rattan furniture visible through open plan",
        negative_rules=["no dark furniture", "no string lights", "no bright cushion colours", "no resort-clichéd decor"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="tropical_escape",
        room_type="facade",
        furniture_language=["white render or whitewash facade", "louvred timber or shuttered windows", "simple timber entrance door with louvred screen"],
        material_palette=["white render or whitewash facade finish", "natural timber louvres and window frames", "pale concrete or stone entrance threshold"],
        lighting_behavior="Warm concealed facade uplights + simple brass lanterns flanking entrance; welcoming tropical evening.",
        # Wave 6.26 (2026-06-06) — facade enrichment, architecture-safe (guard at [0]; see WM).
        decor_language=["keep the building exactly — never add, alter, narrow, extend, or restyle any wall, window, door, roof, cladding or structure; only ground-level planting, a doormat and warm light on the existing entrance", "tropical planting cascading at facade base — not clipped", "louvred shutters as architectural facade element", "potted palms or ferns flanking the existing entrance", "a woven coir doormat at the existing threshold"],
        realism_constraints=["white render with slight texture — not perfect CGI smooth", "louvres at correct depth and shadow interval"],
        room_specific_constraints=["white as primary facade colour — no mixed dark materials", "louvred element visible — facade identity"],
        visible_transition_logic="white render continues to boundary wall; pale stone threshold echoes interior floor",
        negative_rules=["no dark facade", "no cold grey render", "no formal entrance canopy", "no mixed dark cladding on white facade"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="tropical_escape",
        room_type="dining_room",
        # Wave 6.13 (2026-06-05) — dining_room enrichment (see WM block header).
        # Tropical target (col 2/3) : resort calm — natural fibres, light tropical
        # greenery, warm daylight, organic accessories. HIGHEST regression risk
        # (permissive core per Wave 6.2a + floor plant). Double safety :
        #   - floor palm ANCHORED to existing corner AND conditional-omit
        #   - sideboard plant + artwork conditional-omit. Same pattern as 6.11b bedroom.
        furniture_language=["solid timber or concrete dining table", "rattan or cane dining chairs with white cushions", "open timber or concrete sideboard"],
        material_palette=["polished concrete or pale stone floor", "white render finish on existing walls", "rattan or cane chair structure with white upholstery"],
        lighting_behavior="Single woven rattan pendant hung low over the existing table + warm natural daylight flooding from the existing window; bright relaxed resort dining warmth.",
        decor_language=[
            "floor-length light natural linen or cotton curtains in off-white clearly framing each existing window, drawn open with the glass left fully clear — never covering, narrowing or blocking it, never on a glass partition",
            "PROMINENTLY displayed low centrepiece of tropical flowers — heliconia or frangipani — in white ceramic on the existing table",
            "woven rattan table runner or tray on the existing table — natural fibre texture",
            "relaxed natural-linen place settings on the existing chairs — easy resort styling",
            "single framed botanical or landscape artwork above the existing sideboard — only if that wall is free, else omit",
            "potted small palm or monstera in a woven or white pot on the existing sideboard",
            "tall potted palm specimen anchored in an existing room corner — only if floor space is clearly free, else omit",
        ],
        realism_constraints=["pendant at correct height — 70–75 cm above table", "chairs at correct height for table"],
        room_specific_constraints=["open side to terrace or garden if space allows", "white or natural linen chair upholstery only", "tall corner palm anchored against an existing wall corner — never floating in circulation space"],
        visible_transition_logic="white walls and concrete floor echo living area; tropical garden visible beyond open side",
        negative_rules=["no dark dining table", "no formal chandelier", "no patterned upholstery", "no enclosed dining room feel"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="tropical_escape",
        room_type="balcony",
        furniture_language=["two rattan armchairs with white linen cushions", "small concrete or stone side table", "single large tropical planter"],
        material_palette=["pale concrete or stone balcony floor", "white or off-white balustrade", "white linen cushions"],
        lighting_behavior="Single warm rattan or brass lantern; tropical evening ambience.",
        # Wave 6.26 (2026-06-06) — balcony enrichment (anchoring guard at [0]; see WM).
        decor_language=["anchored to the existing balcony floor, railing and furniture — existing layout kept exactly; no added walls, new structures, roofs or extensions", "white linen cushions", "single large tropical plant in white or concrete pot", "a rattan tray with two glasses on the existing side table", "a woven throw layered on the existing armchairs", "a rattan lantern on the existing floor", "a natural jute or seagrass rug grounding the seating on the existing floor"],
        realism_constraints=["chairs at correct height for table", "balustrade at safety height"],
        room_specific_constraints=["two chairs with side table — casual seating zone", "single tropical plant as balcony accent"],
        visible_transition_logic="pale concrete floor echoes interior floor; white walls and tropical garden visible through glass",
        negative_rules=["no dark furniture", "no coloured cushions", "no plastic", "no suburban balcony chair set"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="tropical_escape",
        room_type="pool_area",
        furniture_language=["wide rattan or teak sun loungers with thick white cushions", "canvas or timber shade sail", "concrete or stone side tables"],
        material_palette=["large-format pale stone or concrete pool deck", "white canvas cushion fabric", "pale stone or concrete pool coping"],
        lighting_behavior="Warm underwater lighting (warm white tint) + concealed warm cove at shade structure edge.",
        # Wave 6.25 (2026-06-06) — pool enrichment (anchoring guard at [0]; see WM).
        decor_language=["anchored to the existing deck, coping and furniture — existing pool and spatial layout kept exactly; no added walls, new structures, roofs, pergolas or architectural extensions", "lush layered tropical planting filling the deck perimeter and any open or bare ground — heliconia, banana leaf, palms and grouped planters for verdant landscaped depth", "white canvas cushions on loungers — consistent colour", "rolled white towels and a rattan tray with a carafe and glasses on the existing side table", "a woven throw and extra cushions layered on the existing loungers", "rattan lanterns set along the existing deck edge"],
        realism_constraints=["loungers at correct residential scale", "pool coping at correct level above deck"],
        room_specific_constraints=["light pool liner — light blue or white", "white or natural cushion colour only on loungers", "no bare or unplanted ground around the deck — landscape it with tropical planting"],
        visible_transition_logic="pale stone deck continues to terrace; white villa facade visible as backdrop",
        negative_rules=["no dark pool liner", "no bright parasols", "no plastic loungers"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="tropical_escape",
        room_type="garden",
        furniture_language=["a rattan or teak outdoor lounge sofa with white cushions around a low table, plus a teak or rattan dining table with cane chairs where the garden is large enough", "lush tropical planting — palms, heliconias, banana plants", "concrete or stone path through the planting"],
        material_palette=["pale stone or concrete path", "tropical planting palette — greens and whites", "simple timber or concrete garden furniture"],
        lighting_behavior="Warm uplights on tropical planting + warm path strips; lush tropical evening garden.",
        # Wave 6.26 (2026-06-06) — garden enrichment (anchoring guard at [0]; see WM balcony).
        decor_language=["anchored to the existing paving, beds and garden footprint — existing layout kept exactly; no added walls, new structures, roofs, pergolas or hardscape", "naturalistic tropical planting as primary design", "single specimen palm or tropical tree as focal element", "a woven cushion on the existing timber bench", "potted palms and ferns along the existing path", "warm uplights on the existing tropical planting"],
        realism_constraints=["path at correct level with edge", "tropical plants at correct naturalistic scale — lush but not overgrown"],
        room_specific_constraints=["tropical species only — no European garden plants", "planting lush but with clear paths through"],
        visible_transition_logic="stone path continues to terrace and pool deck; white villa facade visible at garden edge",
        negative_rules=["no formal clipped hedging", "no lawn obsession", "no European garden style", "no potted herb garden"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="tropical_escape",
        room_type="entrance_hall",
        furniture_language=["white render console table or simple timber bench", "round mirror in rattan or white-painted timber frame", "single large tropical plant in concrete pot"],
        material_palette=["pale concrete or stone floor", "white render finish on existing walls", "rattan or timber mirror frame"],
        lighting_behavior="Warm rattan or brass pendant + warm ambient; bright welcoming tropical arrival.",
        # Wave 6.24 (2026-06-06) — entrance enrichment, surface/floor only (see WM note).
        decor_language=[
            "light natural linen or cotton curtains in off-white framing the existing window, drawn open with the glass clear — never covering or blocking it, never on a glass partition; only where a window exists",
            "single large-leaf tropical plant as entry accent",
            "woven rattan tray with simple objects on console",
            "a small rattan or ceramic table lamp on the existing console — warm welcome glow",
            "a natural jute or seagrass runner along the floor",
        ],
        realism_constraints=["console at correct 80–85 cm height", "plant at correct scale for hall — not too small"],
        # Wave 6.23 (2026-06-06) — entrance opening-preservation guard at [0] (see WM).
        room_specific_constraints=["place the console, mirror and wall decor on an existing solid wall only — never cover, wall over, narrow or replace any existing opening, doorway or passage; if the only free wall is an opening, keep it open and place the console along a solid wall or omit it", "tropical plant as primary entry feature", "bright and open — not dark or enclosed"],
        visible_transition_logic="concrete floor and white walls flow into living area; rattan and timber accents echo through",
        negative_rules=["no dark entry", "no ornate mirror", "no cluttered accessory collection", "no nautical decor"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="tropical_escape",
        room_type="home_office",
        # Wave 6.17 (2026-06-06) — desk upsized (see WM home_office note).
        furniture_language=["large timber or concrete desk — generous full-width work surface", "rattan or cane chair with linen seat pad", "open timber shelf with books and single plant"],
        material_palette=["pale concrete or stone floor", "white render finish on existing walls", "timber desk and natural linen"],
        lighting_behavior="Single rattan or ceramic desk lamp + bright natural window light; tropical daytime workspace.",
        # Wave 6.14 (2026-06-06) — home_office enrichment (see WM block note).
        # Wave 6.16 (2026-06-06) — full pack (see WM note). NB: Tropical home_office
        # stays fidelity=low (only WM bumped) — floor furniture here has more latitude.
        decor_language=[
            "floor-length light natural linen or cotton curtains in off-white clearly framing each existing window, drawn open with the glass left fully clear — never covering, narrowing or blocking it, never on a glass partition",
            "a rattan or cane lounge chair with a small woven side table in the open floor area — clear of any window or door, only if floor space allows, else omit",
            "a natural jute or seagrass rug spanning the desk and the lounge corner",
            "a rattan desk lamp, an open notebook and a smooth stone paperweight set on the existing desk — an easy, lived-in workspace",
            "a small potted palm or monstera sprig and a woven tray of organic objects on the existing timber shelf",
            "a framed botanical or landscape artwork on the existing wall — only if that wall is free, else omit",
            "a low leafy plant softening the floor beside the lounge corner",
            "a tall rattan-and-timber open bookcase against a free wall — books and woven baskets — only if the room is large enough and it covers no window or door, else omit",
        ],
        realism_constraints=["desk at correct 72–75 cm working height", "chair at correct seat height"],
        room_specific_constraints=["bright and airy — window as primary light source", "minimal cable visibility"],
        visible_transition_logic="white walls and concrete floor echo hallway; garden or tropical foliage visible through window",
        negative_rules=["no dark office furniture", "no cold LED task light", "no enclosed enclosed feeling", "no cable clutter"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="tropical_escape",
        room_type="driveway",
        furniture_language=["simple white render gate pillars", "pale stone or concrete driveway", "tropical planting flanking drive — palms and heliconias"],
        material_palette=["pale stone or concrete driveway", "white render gate pillars and boundary wall", "warm brass or timber lanterns"],
        lighting_behavior="Warm lanterns on white pillars + low warm uplights on tropical drive-edge planting.",
        # Wave 6.26 (2026-06-06) — driveway enrichment, architecture-safe (guard at [0]; see WM facade).
        decor_language=["keep the drive, gate, pillars and boundary exactly — never add, alter, widen or extend any wall, gate, pillar, structure or paving; only border planting, potted plants and warm light on existing surfaces", "tropical planting flanking full drive length — lush arrival", "single specimen palm at forecourt", "potted palms at the existing gate pillars", "warm lanterns lit along the existing drive edge"],
        realism_constraints=["driveway at correct residential width — 3–3.5 m", "gate pillars at proportional height"],
        room_specific_constraints=["white or off-white render boundary — matches facade", "tropical edge planting — not formal hedging"],
        visible_transition_logic="pale stone continues to entrance threshold; white villa facade visible from gate",
        negative_rules=["no dark render boundary", "no formal clipped hedging", "no ornate gate", "no cold grey paving"],
    ),
]:
    register(_d)
