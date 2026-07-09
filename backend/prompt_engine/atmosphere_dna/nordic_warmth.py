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
        # Wave 5.12c — anchored "warm white plaster walls" → "warm white
        # plaster finish on existing walls" (mirror of WM / SL / Nature
        # anchor pattern). Resolves the prompt-internal tension where
        # the plural-noun material directive pushed the model to invent
        # new walls to satisfy the Nordic identity.
        material_palette=["wide-plank pine or birch floor", "warm white plaster finish on existing walls", "natural wool upholstery in oat or undyed tones"],
        # Wave 5.12c — lighting_behavior trimmed for budget. Nordic creative
        # was at +2 margin after adding the defensive wall-preservation
        # rule + material_palette anchor. Original wording mentioned
        # "behind sofa" and "hanging filament bulb pendant" — the
        # positioning detail and the "bulb" qualifier are cuttable
        # without losing the Nordic candle-warm character.
        lighting_behavior="Amber floor lamp + filament pendant; candle-warm, no ceiling wash.",
        # Wave 6.2a (2026-06-03) — pilot enrichment ROLLED BACK after bench
        # 1/4 perspective/partition drift (photo 4 reoriented). Even with
        # draped-only items and existing-surface anchoring, the +50% prompt
        # density tipped one generation. Nordic Terrace (same atmosphere,
        # same draped-item pattern) passed cleanly — the constraint is
        # specifically interior living rooms. See [[wave-6-2a-regression]].
        # Wave 6.14 (2026-06-09) — Emotional Styling Layer (Nordic Living). decor
        # 2→6, validated recipe (anchored-to-existing + conditional-omit art +
        # anchored-corner greenery + soft furnishings). Nordic voice: wool/
        # sheepskin, oat/undyed, amber, hygge. Structure / materials / fidelity /
        # TV anchor untouched (room_specific_constraints already permit layered
        # rugs). Gate: walls invented = 0 AND naturalness >= 4/5, else revert.
        decor_language=[
            "floor-length soft wool or linen curtains in oat or undyed clearly framing each existing window, drawn open with the glass left fully clear — never covering, narrowing or blocking it, never on a glass partition",
            "cluster of amber or clear glass candle holders on the existing coffee table",
            "a soft layered wool flatweave and pile rug grounding the seating footprint — warm hygge floor",
            "2 to 3 layered wool and linen cushions in oat, ecru, or warm white on the existing sofa — soft hygge texture, naturally arranged",
            "a chunky wool throw and a natural sheepskin layered over the existing sofa — cozy candle-warm comfort",
            "a potted plant or trailing greenery anchored in the existing corner near the window — single woven or ceramic pot, never floating in the room",
            "a warm-toned or botanical artwork on the existing wall above the sofa — only if that wall is solid and free, else omit",
        ],
        realism_constraints=["sofa at normal residential height — 45 cm", "candleholders at varied heights — not matching set"],
        # Wave 5.5.22 — added "a television" as third focal option.
        # Wave 5.5.34 — dropped "if present" + added "not multiple" cap.
        # Wave 5.5.43 — TV-first reorder.
        # Wave 5.5.49 — adopting universal media console flex pattern
        # (same fix as WM 5.5.49 + Soft Luxury / Nature / Desert 5.5.48).
        # Allows TV placement on existing wall OR media console; explicitly
        # forbids creating a new wall. Standardized across all atmospheres
        # to prevent wall-invention side effects.
        room_specific_constraints=["layered rugs permitted — wool flatweave under pile", "include a television as the living-room focal point, placed on an existing wall or low media console directly in front of the primary seating, never behind the sofa, never behind the main seating, never on the rear wall behind the seating, never a new wall, and never by converting glazing into a wall. When a television is included, the television axis has priority over the garden/window view axis: arrange the main sofa so it faces the TV directly; keep the garden view as a side view or background view, never as the sofa's primary facing direction if that would place the TV behind the seating."],
        # Wave 5.5.34b — dropped "visible bedroom door" reference. Bench
        # 2026-05-25 showed the model literally invented a bedroom zone +
        # glass partition when the photo had no bedroom. Replaced with the
        # neutral "adjacent rooms" + a conditional kitchen mention so the
        # kitchen-visibility signal stays without inventing new spaces.
        visible_transition_logic="pine floor and warm white plaster continue into adjacent rooms; wool palette echoes through visible kitchen if present",
        # Wave 5.12c — universal wall-preservation rule INSERTED at slot
        # [0]. Nordic had no defensive rule before — wall-invention
        # observed in bench (TV mounted on invented right-wall, kitchen
        # opening masked). Trade-off : "no minimalist floating shelves"
        # demoted out of shipped [:3] AVOID (was [2], now [3]). Wall
        # preservation > shelf-style policing.
        # Wave 5.14c — softened wall rule (see WM for rationale).
        negative_rules=["no sleek dark furniture", "no chrome accents", "no minimalist floating shelves", "no cold grey palette"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="nordic_warmth",
        room_type="master_bedroom",
        # Wave 6.6 (2026-06-04) — master_bedroom hygge emotional enrichment.
        # Reinforces textile imperfection + lived-in bedside (sheepskin,
        # candle, paperback). Drops "framed botanical print above nightstand"
        # (wall directive risk) + "above headboard wall" architectural cue.
        # Paperback testable — drop if text artifacts. Room-scoped.
        furniture_language=["pine or birch timber — warm natural tactile surface", "birch timber — amber glass warmth at low level", "sheepskin — natural undyed floor-level softness with relaxed organic fall"],
        material_palette=["pine or birch floor", "warm white plaster finish on existing walls", "layered natural linen and wool bedding with slight natural imperfection"],
        lighting_behavior="Soft Nordic winter daylight from windows + single hanging amber glass pendant or paper lantern + amber glass bedside table lamps + concealed warm slot producing soft ambient glow; quiet lived-in comfort.",
        # Wave 6.6 (2026-06-04) — extended from 2 to 4 items. Drops the
        # "framed botanical print above nightstand" (wall focal risk per
        # user audit) and replaces with grounded lived-in objects :
        # sheepskin at bedside (Wave 6.2a pattern, validated on Nordic
        # Terrace) + amber glass candle holder + open paperback
        # (testable — drop if text artifacts in render).
        # Wave 6.7 (2026-06-04) — A+B initial : assertive anti-staging vocab +
        # 2 additional lived-in items. EMPIRICALLY DEGRADED Nordic bedroom
        # rendering vs Wave 6.6 (bench user 2026-06-04) :
        #   1. 3 items on nightstand (candle + paperback + mug) → competition
        #      on single surface → model rendered 0-1 visibly, dropped others
        #   2. "VISIBLY" / "PROMINENTLY" / "natural moment" assertive vocab
        #      conflicted with Nordic identity restraint → model compensated
        #      by rendering MORE restraint, less decor visible
        #   3. "framed nature photograph on the existing dresser" — dresser
        #      not always present in source frame → hallucination or drop
        # Wave 6.7 Option 2 redistribute (user-locked 2026-06-04) :
        #   - SOFTEN assertive vocab → "naturally relaxed" / drop "PROMINENTLY"
        #   - DROP framed nature photograph (dresser uncertainty)
        #   - REDISTRIBUTE items across surfaces
        # Wave 6.8 A+B+C (user-locked 2026-06-04) — bench post Wave 6.7 Option 2
        # bench showed Nordic still lacking visible enrichment + missing
        # ceiling pendant. User-requested A+B+C combined :
        #   - A : hanging pendant added to lighting_behavior + windowsill plant
        #   - B : 2-3 decorative throw pillows on bed
        #   - C : small painted pine bench at foot of bed
        #   - DROP "small ceramic mug" (never rendered visibly per bench)
        #   - Extended slice [:6] → [:8] in _base.py to ship all 8 items
        # Distribution post-Wave-6.8 : 3 bed (bedding + wool throw + pillows)
        # + 2 floor (sheepskin + bench at foot) + 2 nightstand (candle +
        # paperback) + 1 windowsill (plant) + 1 ceiling (pendant via lighting).
        decor_language=[
            "floor-length soft wool or linen curtains in oat or undyed clearly framing each existing window, drawn open with the glass left fully clear — never covering, narrowing or blocking it, never on a glass partition",
            "naturally relaxed layered linen and wool bedding with slightly imperfect folds and visible textile weight",
            "natural sheepskin at one bedside on the existing floor",
            "amber glass candle holder on the existing nightstand",
            "open paperback on the existing nightstand",
            "wool throw casually draped over the foot of the existing bed",
            "small painted pine bench at the foot of the existing bed",
            "2 to 3 decorative throw pillows in oat, ecru, or warm white on the existing bed",
            "small potted plant or trailing greenery on the existing windowsill",
        ],
        realism_constraints=["bed frame at correct height — 45 cm to mattress top", "linen and wool bedding layered with visible relaxed folds and slight natural imperfection"],
        room_specific_constraints=["sheepskin at one side of bed only — not both sides", "window with simple linen curtains, not full drapes"],
        visible_transition_logic="pine floor and warm white plaster flow into ensuite; linen bedding palette echoes bathroom towels",
        negative_rules=["no dark headboard", "no cold white bedding", "no high-gloss surfaces", "no patterned wallpaper"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="nordic_warmth",
        room_type="kitchen",
        # Wave 6.13b (2026-06-05) — kitchen enrichment (see WM block header).
        # Nordic col 3 : cozy textiles + warm daylight + wool + oak + hygge.
        # AVOID : trop bougies / trop evening / trop chalet — so NO candles added
        # and lighting kept DAYTIME, not evening. Greenery stays the single herb.
        furniture_language=["white-painted shaker or flat-front cabinetry", "solid birch or butcher-block countertop", "open pine shelf with ceramics and glassware"],
        material_palette=["white-painted cabinetry", "birch or pine countertop", "white subway or handmade tile backsplash"],
        lighting_behavior="Bright airy Nordic daylight across the birch worksurfaces + warm under-cabinet strip in soft 2700K; inviting hygge work light — daytime warmth, not evening.",
        decor_language=[
            "soft wool or linen curtains in oat or undyed framing the existing window, drawn open with the glass clear — never covering or blocking it, never on a glass partition; only where a window exists",
            "open pine shelf styled with 5 handmade ceramic pieces in warm neutral tones — curated",
            "single potted herb on the existing windowsill — one only",
            "a soft wool or linen tea towel draped over the existing oven rail — cozy textile layer",
            "a wooden bowl holding seasonal fruit on the existing counter — natural and lived-in",
            "a folded linen runner softening the existing counter or breakfast nook — gentle hygge texture",
        ],
        realism_constraints=["butcher block countertop at residential 60 cm depth", "cabinet doors at standard 220 cm height"],
        # Wave 6.13c (2026-06-05) — kitchen structure-preservation guard at [0] (see WM). Ships [:2].
        room_specific_constraints=["arrange cabinetry and island without covering, narrowing or relocating any existing window, doorway or wall opening — keep photographed openings fully clear", "open shelf with ceramics — not clutter", "white tile backsplash in handmade format — not industrial"],
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
        # Wave 6.2a (2026-06-03) — pilot enrichment +2 items. Sheepskin
        # throw on EXISTING seating ; lantern cluster on EXISTING table.
        # Strengthens the hygge outdoor signature.
        decor_language=["anchored to the existing terrace floor, parapet, garde-corps and any existing shade structure — existing architecture and openings kept exactly; no new walls, no enclosure, no building roof, no floor or deck extension",
                        "painted pine or teak lounge seating layered with thick wool and cotton cushions in oat and undyed white and a natural sheepskin throw",
                        "a low timber table styled with amber glass candle holders and a lantern cluster of two or three amber glass pieces",
                        "potted greenery and a specimen tree in painted timber or stone planters along the perimeter",
                        "a soft wool or cotton outdoor rug in oat grounding the seating zone",
                        "where the terrace is large enough, a painted pine or teak dining table with timber chairs and amber glass lanterns"],
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
        # Wave 6.26 (2026-06-06) — facade enrichment, architecture-safe (guard at [0]; see WM).
        decor_language=["keep the building exactly — never add, alter, narrow, extend, or restyle any wall, window, door, roof, cladding or structure; only ground-level planting, a doormat and warm light on the existing entrance", "simple planting at entrance — lavender or ornamental grass in stone pot", "single wreath or seasonal botanical at door", "a pair of potted grasses flanking the existing door", "a natural coir doormat at the existing threshold"],
        realism_constraints=["timber board joints at correct painted weathered scale", "window proportions Nordic — tall and vertical or square"],
        room_specific_constraints=["white or near-white as primary facade colour", "entrance door clearly readable at facade centre"],
        visible_transition_logic="white cladding tone echoes interior white walls; pine door frame matches interior timber palette",
        negative_rules=["no dark timber cladding", "no warm sand render", "no UPVC frames", "no contemporary flat black"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="nordic_warmth",
        room_type="dining_room",
        # Wave 6.13 (2026-06-05) — dining_room enrichment (see WM block header).
        # Nordic target (col 2/3) : hygge — soft textiles, candlelight, light wood,
        # discreet decor. Candle cluster is the native signature (kept prominent).
        # Woven-shade pendant + airy daylight ; artwork CONDITIONAL OMIT.
        furniture_language=["solid birch or pine round dining table", "upholstered dining chairs in natural linen or wool", "painted pine or white sideboard"],
        material_palette=["pine floor", "warm white plaster finish on existing walls", "natural linen or wool chair upholstery"],
        lighting_behavior="Woven or amber-shade pendant hung low over the existing table + warm candlelight glow rising from the table cluster; bright airy Nordic daylight balanced with cozy hygge warmth.",
        decor_language=[
            "floor-length soft wool or linen curtains in oat or undyed clearly framing each existing window, drawn open with the glass left fully clear — never covering, narrowing or blocking it, never on a glass partition",
            "PROMINENTLY displayed cluster of pillar candles as centrepiece on the existing table — warm flame glow",
            "simple ceramic or wooden bowl with seasonal branches or foliage on the existing table",
            "soft wool or linen runner laid across the existing table — oat or undyed, gently textured",
            "linen seat cushions softened onto the existing dining chairs — natural and inviting",
            "single framed botanical print or muted artwork above the existing sideboard — only if that wall is free, else omit",
            "two curated stoneware pieces and a small vase of branches styled on the existing sideboard",
        ],
        realism_constraints=["pendant at correct height — 70–75 cm above table", "chairs at correct seat height for table"],
        room_specific_constraints=["round or oval table preferred — conversation-friendly", "candles as centrepiece — not flowers"],
        visible_transition_logic="pine floor and white plaster echo kitchen; linen chair upholstery palette continues from living room",
        negative_rules=["no glass or marble table top", "no matching chair-and-table set in dark finish", "no chandelier", "no maximalist or banquet-formal tablescaping"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="nordic_warmth",
        room_type="balcony",
        furniture_language=["two painted pine folding chairs or simple armchairs", "small round birch or pine table", "single pot with trailing ivy or lavender"],
        material_palette=["pine or composite timber decking", "white or warm grey balustrade", "wool outdoor cushions in oat"],
        lighting_behavior="Single amber glass lantern on table; warm hygge tone — no wall sconce.",
        # Wave 6.26 (2026-06-06) — balcony enrichment (anchoring guard at [0]; see WM).
        decor_language=["anchored to the existing balcony floor, railing and furniture — existing layout kept exactly; no added walls, new structures, roofs or extensions", "amber glass candle holder", "simple wool throw folded on chair back", "a wooden tray with a stoneware cup on the existing table", "soft cushions layered on the existing chairs", "a small jute mat on the existing floor"],
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
        # Wave 6.25 (2026-06-06) — pool enrichment (anchoring guard at [0]; see WM).
        decor_language=["anchored to the existing deck, coping and furniture — existing pool and spatial layout kept exactly; no added walls, new structures, roofs, pergolas or architectural extensions", "simple arrangement of rounded stones at pool corner", "single planted urn with ornamental grass", "rolled towels and a wooden tray with a stoneware carafe on the existing side table", "a folded wool throw and soft cushions on the existing loungers", "amber lanterns clustered on the existing deck"],
        realism_constraints=["loungers at correct residential scale — not resort-runway", "pool coping at correct level above deck"],
        room_specific_constraints=["natural materials only — no plastic furniture", "light-coloured pool liner — not dark"],
        visible_transition_logic="timber deck continues to terrace; white house facade visible as backdrop",
        negative_rules=["no bright parasols", "no plastic loungers", "no blue chrome water emphasis", "no over-planted surround"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="nordic_warmth",
        room_type="garden",
        furniture_language=["painted pine or teak outdoor lounge seating with wool cushions around a low table, plus a pine dining table and chairs where the garden is large enough", "simple stone or gravel path", "naturalistic planting with wildflowers and ornamental grasses"],
        material_palette=["pale stone or gravel path", "painted pine garden bench", "naturalistic planting in greens and whites"],
        lighting_behavior="Low warm path lights + amber lantern on table; garden in warm evening glow.",
        # Wave 6.26 (2026-06-06) — garden enrichment (anchoring guard at [0]; see WM balcony).
        decor_language=["anchored to the existing paving, beds and garden footprint — existing layout kept exactly; no added walls, new structures, roofs, pergolas or hardscape", "birdbath in simple stone", "naturalistic wildflower planting at borders", "a wool throw on the existing pine bench", "potted lavender or grasses on the existing paving", "warm path lights along the existing gravel path"],
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
        # Wave 6.24 (2026-06-06) — entrance enrichment, surface/floor only (see WM note).
        decor_language=[
            "soft wool or linen curtains in oat or undyed framing the existing window, drawn open with the glass clear — never covering or blocking it, never on a glass partition; only where a window exists",
            "single dried botanical in ceramic vase on console",
            "small framed botanical print above console",
            "a small woven tray with a stoneware dish on the existing console",
            "a warm table lamp or lantern on the existing console — hygge glow",
            "a soft wool or jute runner along the floor",
        ],
        realism_constraints=["console at correct 80–85 cm height", "mirror at correct eye-level placement"],
        # Wave 6.23 (2026-06-06) — entrance opening-preservation guard at [0] (see WM).
        room_specific_constraints=["place the console, mirror and wall decor on an existing solid wall only — never cover, wall over, narrow or replace any existing opening, doorway or passage; if the only free wall is an opening, keep it open and place the console along a solid wall or omit it", "hook rail for coats — visible but neat", "woven basket below console for shoes"],
        visible_transition_logic="pine floor and white plaster flow into living room; warm palette continuous",
        negative_rules=["no dark or industrial entry", "no cold stone floor", "no minimalist ledge-only entry", "no cluttered coat pile"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="nordic_warmth",
        room_type="home_office",
        # Wave 6.17 (2026-06-06) — desk upsized (see WM home_office note).
        furniture_language=["large solid birch or pine desk with turned legs — generous full-width work surface", "upholstered chair in natural linen or wool", "tall open pine bookcase against a free wall — generous and prominent when the room is large enough, otherwise a compact pine wall shelf"],
        material_palette=["pine floor", "warm white plaster finish on existing walls", "natural linen or wool upholstery"],
        lighting_behavior="Amber glass desk lamp + warm ambient from floor lamp in corner; no cold task light.",
        # Wave 6.14 (2026-06-06) — home_office enrichment (see WM block note).
        # Wave 6.16 (2026-06-06) — full pack (see WM home_office note).
        decor_language=[
            "floor-length soft wool or linen curtains in oat or undyed clearly framing each existing window, drawn open with the glass left fully clear — never covering, narrowing or blocking it, never on a glass partition",
            "a cosy linen-upholstered reading chair with a small pine side table in the open floor area — clear of any window or door, only if floor space allows, else omit",
            "a soft natural-fibre rug spanning the desk and the reading nook",
            "a warm desk lamp, an open book and a stoneware mug set on the existing desk — a lived-in workspace",
            "a wool throw folded over the reading chair",
            "a potted succulent and a few muted-spine books on the existing pine shelf",
            "a simple framed botanical print on the existing wall — only if that wall is free, else omit",
        ],
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
        # Wave 6.26 (2026-06-06) — driveway enrichment, architecture-safe (guard at [0]; see WM facade).
        decor_language=["keep the drive, gate, pillars and boundary exactly — never add, alter, widen or extend any wall, gate, pillar, structure or paving; only border planting, potted plants and warm light on existing surfaces", "simple clipped lavender or box flanking gate", "white-painted timber fence along boundary", "potted lavender along the existing drive edge", "amber lanterns lit on the existing gate pillars"],
        realism_constraints=["driveway at correct residential width — 3–3.5 m", "gate at correct proportional height"],
        room_specific_constraints=["single driveway material — gravel or pale stone", "white or pale painted fence — not dark"],
        visible_transition_logic="pale gravel continues to house approach; white facade visible from gate approach",
        negative_rules=["no dark render boundary", "no ornate ironwork", "no grey block paving", "no modern angular gate"],
    ),
]:
    register(_d)
