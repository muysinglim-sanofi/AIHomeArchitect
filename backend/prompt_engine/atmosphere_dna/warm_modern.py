from ._base import AtmosphereCoreDNA, RoomAdaptationDNA, register_core, register

register_core(AtmosphereCoreDNA(
    atmosphere_id="warm_modern",
    philosophy="Warm contemporary luxury rooted in emotional comfort, hospitality, softness, and believable urban premium living.",
    emotional_intent="Comforting, refined, welcoming, calm, premium, elegant but livable.",
    architectural_language="Organic forms softened by curves, warm-toned natural materials, and layered indirect light in residential-scale spaces.",
    material_palette=["European oak", "travertine", "warm sand plaster", "brushed brass", "warm linen"],
    lighting_behavior="Warm indirect — concealed coves, tungsten-glow table lamps, no cold or harsh sources.",
    luxury_level="Boutique hotel / premium urban residence",
    forbidden_elements=["Cold minimalism", "sterile white interiors", "ultra glossy marble overload", "fake luxury gold", "overdecorated styling"],
    atmosphere_keywords=["warm contemporary", "boucle", "travertine", "oak", "indirect warmth"],
))

for _d in [
    RoomAdaptationDNA(
        atmosphere_id="warm_modern",
        room_type="living_room",
        furniture_language=["bouclé in oat or camel — warm curved tactile richness", "travertine — warm stone surface depth with brass or oak accent", "warm linen — oak-toned textural warmth"],
        material_palette=["wide-plank European oak floor", "warm sand plaster walls", "travertine slab surfaces"],
        lighting_behavior="Concealed ceiling cove + tungsten-glow table lamps; warm evening tone.",
        # Wave 5.5.21 fix A2 — dropped "oversized ceramic vessel on floating
        # oak shelf" from decor_language. This decor element was occupying
        # the wall focal area (shelf + vessel) and competing with TV
        # placement. Kept floor-length curtains (window-anchored, no
        # conflict with TV).
        # Wave 5.5.27 — APPEND rug essential (only 1 decor item so no
        # replacement needed). Rug anchored to seating footprint.
        decor_language=["floor-length warm linen curtains", "soft wool rug in oat or camel within the seating footprint"],
        realism_constraints=["sofa at residential scale — not model-set proportions", "furniture legs visible and grounded on floor"],
        # Wave 5.5.20 fix #2 — dropped ", not TV-facing row" sub-clause
        # (contradicted the Wave 5.5.19 furnishing signal).
        # Wave 5.5.21 fix A1 — expanded focal-wall constraint from
        # "fireplace or artwork, not both" to include television as a
        # third valid focal option: "fireplace, artwork, or a television,
        # not multiple". This unblocks the prior structural block where
        # the DNA only permitted 2 focal options, none being TV.
        # Wave 5.5.49 — adopting the universal media console flex pattern.
        # Bench 2026-05-25 (round 4) showed the option-list TV anchor
        # caused WM to add a "faux mur" to mount the TV. Same fix
        # pattern as Soft Luxury / Nature / Desert (5.5.48): allow TV
        # placement on EXISTING wall OR media console, never on a
        # newly created wall. Canonical reference profile updated.
        room_specific_constraints=["seating in conversation grouping", "television visible in living area on existing wall surface or media console — never on a newly created wall"],
        visible_transition_logic="oak floor and warm plaster continue into adjacent rooms; brass accents echo through visible kitchen or hallway",
        negative_rules=["no cold grey palette", "no chrome hardware", "no matching 3-piece suite", "no floating furniture without visible support"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="warm_modern",
        room_type="master_bedroom",
        furniture_language=["warm oat linen — layered tactile warmth", "oak timber — floating surface warmth at wall level", "oak and warm-toned timber — warm mirror surface quality"],
        material_palette=["European oak floor", "warm sand plaster finish on existing walls", "travertine bedside surfaces"],
        lighting_behavior="Concealed cove above headboard + bedside table lamps with tungsten glow; no overhead downlights.",
        # Wave 5.5.27 — REPLACED artwork with bedside rug (Option A : essential
        # over decoration). Artwork was decor-only, rug is bedroom essential.
        # Kept layered bedding (bedroom essential).
        decor_language=["layered warm linen and boucle bedding", "soft wool rug at the bedside in oat or camel"],
        realism_constraints=["bed at correct height — not floating too high", "bedding draped naturally, not hotel-stiff"],
        room_specific_constraints=["nightstands matched in height with bedside lamps", "no TV directly facing bed unless wall-mounted flush"],
        visible_transition_logic="oak floor and warm plaster flow into visible ensuite; linen palette continues in towel accents",
        negative_rules=["no cold white bedding", "no mirrored furniture", "no heavy dark drapes", "no hotel-generic sets"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="warm_modern",
        room_type="kitchen",
        furniture_language=["flat-front pale oak cabinetry, upper and lower", "travertine slab island or countertop", "integrated appliances flush with cabinet faces"],
        material_palette=["pale oak cabinetry", "thick travertine countertop", "warm sand tile or plaster backsplash"],
        lighting_behavior="Warm under-cabinet strip light + concealed ceiling track with warm-toned spots over worksurfaces.",
        decor_language=["single oversized ceramic pendant over island", "open oak shelf with curated ceramics — 3 items max"],
        realism_constraints=["cabinet doors at correct residential height, not commercial scale", "island proportioned for kitchen footprint"],
        room_specific_constraints=["handle-free or brushed brass handles only", "no visible appliance clutter on countertop"],
        visible_transition_logic="oak cabinetry palette echoes dining furniture visible beyond; travertine floor or countertop continues",
        negative_rules=["no stainless steel excess", "no dark granite", "no chrome handles", "no open shelf clutter"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="warm_modern",
        room_type="bathroom",
        furniture_language=["floating double oak vanity", "freestanding stone soaking tub", "frameless glass shower screen"],
        material_palette=["travertine floor and wall surfaces", "floating oak vanity", "brushed brass fixtures"],
        lighting_behavior="Concealed cove above vanity mirror + warm wall sconce at shower; no cold white strip lights.",
        decor_language=["slatted oak bath mat", "single warm-framed mirror in brass or oak"],
        realism_constraints=["vanity at correct sink height — not floating too high", "shower screen properly sealed at tile edge"],
        room_specific_constraints=["single material for floor and walls — no mixing stone types", "fittings all in one finish: brushed brass only"],
        visible_transition_logic="travertine and oak palette continue into visible dressing area; brass fixtures echo through door frames",
        negative_rules=["no cold white ceramic tiles", "no chrome fittings", "no plastic accessories", "no over-styled countertop"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="warm_modern",
        room_type="terrace",
        furniture_language=["rattan or teak sofa set with thick warm cushions", "stone or teak coffee table", "structured plant in ceramic pot"],
        material_palette=["travertine or large-format stone paving", "warm linen outdoor cushions", "natural canvas overhead shade"],
        lighting_behavior="Warm strip under pergola beam + single outdoor ceramic pendant; warm evening ambience.",
        decor_language=["warm linen cushion covers in oat or camel", "trailing or potted olive tree as accent"],
        realism_constraints=["outdoor furniture at correct residential scale", "paving stones with correct grout lines"],
        room_specific_constraints=["shade structure — pergola or canvas — defines terrace zone", "transition to garden or interior clearly readable"],
        visible_transition_logic="travertine paving continues to pool deck or garden; interior oak floor visible through sliding doors",
        negative_rules=["no plastic outdoor furniture", "no cold grey tiles", "no corporate hotel terrace feel", "no string light overuse"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="warm_modern",
        room_type="facade",
        furniture_language=["timber-framed windows with deep reveals", "recessed stone entrance threshold", "clipped hedging flanking entrance"],
        material_palette=["warm sand cement render or limestone cladding", "iroko or oak timber window frames", "warm bronze or brass door hardware"],
        lighting_behavior="Concealed ground uplights washing facade + warm lanterns flanking entrance door.",
        decor_language=["single material discipline: render + timber + natural stone", "warm proportioned window rhythm"],
        realism_constraints=["window proportions match interior room heights", "render texture visible — not hyper-smooth CGI"],
        room_specific_constraints=["entrance door clearly legible as focal point", "no more than two cladding materials on facade"],
        visible_transition_logic="warm sand render tone flows to boundary walls; timber window frames echo interior oak palette",
        negative_rules=["no cold grey render", "no UPVC window frames", "no suburban builder aesthetic", "no excessive cladding mix"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="warm_modern",
        room_type="dining_room",
        furniture_language=["oval travertine-top table on brass base", "upholstered dining chairs in warm linen", "oak sideboard with concealed storage"],
        material_palette=["European oak floor", "warm plaster finish on existing walls", "travertine or warm stone table top"],
        lighting_behavior="Single warm brass pendant hung low over table centre; no ambient ceiling wash.",
        decor_language=["single ceramic centrepiece on table", "floor-length warm linen curtains flanking window"],
        realism_constraints=["pendant hung at correct dining height — 70–80 cm above table surface", "chairs at correct seat height for table"],
        room_specific_constraints=["table sized for room — not oversized", "sideboard against wall, not floating in room"],
        visible_transition_logic="oak floor and warm plaster echo through to kitchen; linen chairs palette visible from living room",
        negative_rules=["no cold marble top", "no maximalist tablescaping", "no mismatched chairs", "no chandelier"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="warm_modern",
        room_type="balcony",
        furniture_language=["compact rattan two-seat sofa", "small teak or stone side table", "single ceramic pot with structured plant"],
        material_palette=["composite or natural stone balcony floor", "warm linen cushion fabric", "glass or simple steel balustrade"],
        lighting_behavior="Single warm wall sconce or pendant; warm evening tone, no strip LEDs.",
        decor_language=["warm linen throw draped on sofa", "compact olive tree or trailing plant"],
        realism_constraints=["furniture scale appropriate for balcony — no oversized pieces", "balustrade at correct safety height"],
        room_specific_constraints=["one seating cluster only — no room for two zones", "planting in single structured pot, not random scatter"],
        visible_transition_logic="balcony floor material echoes interior floor; warm interior light visible through glass doors",
        negative_rules=["no plastic chairs", "no artificial grass", "no cluttered storage", "no random style mix"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="warm_modern",
        room_type="pool_area",
        furniture_language=["teak sun loungers with warm canvas cushions", "natural canvas parasol", "stone or teak side table"],
        material_palette=["large-format travertine pool deck", "warm limestone coping", "flush pool edge coping"],
        lighting_behavior="Warm underwater pool lighting + warm concealed deck uplights at lounger zone.",
        decor_language=["flush travertine coping at pool edge", "single restrained olive tree or hedging at deck perimeter"],
        realism_constraints=["pool coping at correct height above deck", "loungers spaced at correct 60–80 cm clearance"],
        room_specific_constraints=["pool coping in single material — no mixing stone types", "deck furniture in one zone — not scattered"],
        visible_transition_logic="travertine deck material continues to terrace or garden; warm facade render visible as backdrop",
        negative_rules=["no plastic sun loungers", "no bright parasols", "no busy pool surrounds", "no cold blue water overemphasis"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="warm_modern",
        room_type="garden",
        furniture_language=["simple oak table and chairs", "stone or terracotta planters", "single specimen tree as focal point"],
        material_palette=["natural limestone or sandstone paving", "warm-toned terracotta pots", "gravel infill between pavers"],
        lighting_behavior="Warm concealed ground uplights on planting beds + warm path lighting at paving edges.",
        decor_language=["edited planting palette in warm greens and silvers", "clean paving-to-planting edge transition"],
        realism_constraints=["paving at correct ground level — not raised or floating", "trees at believable planted scale"],
        room_specific_constraints=["clear circulation path through garden", "focal tree or specimen plant defines garden structure"],
        visible_transition_logic="garden paving continues to terrace deck; warm render of house facade visible as backdrop",
        negative_rules=["no plastic garden furniture", "no mixed paving patterns", "no overdesigned water features", "no garish colour planting"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="warm_modern",
        room_type="entrance_hall",
        furniture_language=["floating oak console table", "large warm-toned round mirror in brass or oak frame", "single structured ceramic vessel"],
        material_palette=["large-format travertine or limestone floor", "warm plaster finish on existing walls", "brushed brass mirror frame"],
        lighting_behavior="Concealed ceiling strip + warm wall sconce flanking mirror; welcoming arrival tone.",
        decor_language=["dried or fresh botanicals in ceramic vessel", "single warm-toned artwork above console"],
        realism_constraints=["console at correct height — 80–90 cm", "mirror sized proportionally to wall, not too small"],
        room_specific_constraints=["clear circulation path to adjacent rooms", "no visual clutter at entry — single focal console"],
        visible_transition_logic="travertine floor continues to living room; oak console echoes living room furniture palette",
        negative_rules=["no visible coat hooks from entry", "no cluttered surfaces", "no cold white tiles", "no mirror below console height"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="warm_modern",
        room_type="home_office",
        furniture_language=["solid oak desk with clean flat profile", "linen upholstered chair on warm oak base", "floating oak shelves above desk"],
        material_palette=["European oak desk surface", "warm sand plaster finish on existing walls", "warm linen upholstery"],
        lighting_behavior="Brushed brass adjustable task lamp on desk + warm ambient ceiling cove; no cold daylight strip.",
        decor_language=["single warm ceramic pen holder", "trailing plant on corner shelf"],
        realism_constraints=["desk at correct 72–75 cm working height", "chair at correct seat height relative to desk"],
        room_specific_constraints=["cable management — no visible cable tangle", "shelves with edited display — not overloaded"],
        visible_transition_logic="oak desk palette echoes hallway or living room flooring; warm plaster walls continuous",
        negative_rules=["no cold grey office aesthetic", "no aggressive ergonomic furniture styling", "no cable clutter", "no tech-showroom feel"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="warm_modern",
        room_type="driveway",
        furniture_language=["stone gate pillars in warm render", "clipped hedging or topiary flanking drive", "simple timber or warm steel gate"],
        material_palette=["natural limestone or sandstone driveway paving", "warm sand cement render for gate pillars and boundary", "warm bronze lanterns"],
        lighting_behavior="Warm bronze lanterns flanking entrance + warm path lighting strips along drive edge.",
        decor_language=["single material consistency: render + stone + warm metal", "restrained specimen planting along boundary"],
        realism_constraints=["driveway width at least 3 m for single vehicle passage", "gate pillars at correct proportional height"],
        room_specific_constraints=["one consistent paving material for full drive", "boundary wall in same render as house facade"],
        visible_transition_logic="limestone paving echoes facade threshold; warm sand render of boundary walls matches house exterior",
        negative_rules=["no grey block paving", "no cold white rendered walls", "no suburban gatehouse aesthetic", "no ornate ironwork"],
    ),
]:
    register(_d)
