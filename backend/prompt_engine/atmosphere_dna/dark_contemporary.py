from ._base import AtmosphereCoreDNA, RoomAdaptationDNA, register_core, register

register_core(AtmosphereCoreDNA(
    atmosphere_id="dark_contemporary",
    philosophy="Architectural sophistication through depth, contrast, material richness, and restraint.",
    emotional_intent="Dramatic, sophisticated, powerful, sensory, moody but refined, architecturally confident.",
    architectural_language="Deep tonal volumes with high-contrast material surfaces, concealed warm light, and gallery-level spatial control.",
    # Wave 5.5.47 — softened paradoxical "dark"/"black" vocabulary in
    # material_palette. Bench 2026-05-25 (round 2) showed Dark Contemp
    # still rendering "trop sombre" despite Wave 5.5.38 + 5.5.45 fixes.
    # The material_palette darkness saturation (6 "dark"/"black"
    # occurrences across core+room) was the residual driver. Replaced
    # "dark charcoal" -> "warm charcoal", "black or dark grey" -> "deep
    # grey or smoked". Mood preserved (charcoal + smoked still convey
    # depth), readability gained.
    # Wave 5.5.48 Path 2 — surgical floor/accent softening. User feedback
    # round 3: "l'intérieur a l'air bien sauf que c'est trop sombre".
    # Walls keep charcoal (mood identity preserved). Floor softened:
    # "smoked oak or wenge" -> "warm walnut or smoked oak" (drop "wenge"
    # which is the darkest wood). Wenge alone was driving floor-level
    # darkness on top of charcoal walls.
    material_palette=["warm charcoal plaster", "deep grey or smoked marble", "warm walnut or smoked oak", "brushed bronze or gunmetal", "concrete"],
    # Wave 5.5.38 — dropped "darkness as design element". The phrase
    # licensed pure-darkness renders (bench 2026-05-25 showed "trop sombre,
    # on voit quasiment rien"). Replaced with "cinematic warmth with
    # maintained architectural readability" — keeps the moody-luxury intent
    # while establishing a readability floor at the core level.
    lighting_behavior="Concealed precision lighting — warm glow against dark surfaces; cinematic warmth with maintained architectural readability.",
    luxury_level="Contemporary penthouse luxury",
    # Wave 5.5.45 — removed paradoxical "dark"/"black" words from
    # forbidden_elements. Even in negative formulations, these tokens
    # were priming the model toward darkness (paradoxical reinforcement
    # = "don't think of an elephant"). "black void interiors" → "void
    # interiors" (drop "black", keep "void" anti-emptiness). "horror-
    # dark rooms" → "horror-aesthetic interiors" (drop "dark", keep the
    # horror reference).
    forbidden_elements=["Nightclub atmosphere", "cyberpunk lighting", "void interiors", "aggressive contrast", "horror-aesthetic interiors"],
    # Wave 5.5.38 — "dark luxury" → "cinematic luxury" (drop the "dark"
    # framing which was reinforcing pure-darkness interpretations). Added
    # "warm" to "precision light" so the keyword pair stays consistent
    # with the new lighting_behavior emphasis.
    # Wave 5.5.47 — "charcoal plaster" → "warm charcoal plaster" for
    # consistency with material_palette softening.
    atmosphere_keywords=["cinematic luxury", "warm charcoal plaster", "smoked oak", "bronze", "warm precision light"],
))

for _d in [
    RoomAdaptationDNA(
        atmosphere_id="dark_contemporary",
        room_type="living_room",
        # Wave 5.5.47 — material vocab softening (room-level mirror of
        # core changes). "dark" / "black" removed everywhere they
        # appeared in positive descriptors. Mood preserved via "warm
        # charcoal", "deep marble", "smoked", "rich velvet" — all still
        # convey moody luxury depth without the over-dark cue.
        # Wave 5.5.48 Path 2 — floor softening at room level (mirror
        # of core change). "smoked oak or deep stone floor" -> "warm
        # walnut or honed stone floor". Lighter floor reflects more
        # ambient light, reducing overall darkness while keeping walls
        # charcoal for mood.
        furniture_language=["warm charcoal bouclé or leather — deep low tactile richness", "deep marble or stone — sculptural surface depth", "rich velvet — high-contrast atmospheric depth"],
        material_palette=["warm charcoal plaster walls", "warm walnut or honed stone floor", "deep marble or bronze accent surfaces"],
        # Wave 5.5.38 — dropped "room lit by glow, not flood". The "not
        # flood" framing was too aggressive — the model interpreted it as
        # "minimize all light sources" → underexposed renders. Replaced
        # with "warm cinematic glow with maintained natural daylight from
        # windows" so windows-as-light-source remains a primary signal.
        lighting_behavior="Concealed warm ceiling cove + single sculptural bronze floor lamp; warm cinematic glow with maintained natural daylight from windows.",
        # Wave 5.5.26 — "large-scale abstract artwork" → "deep dark velvet
        # throw layered on the sofa". Original artwork occupied wall focal
        # area competing with TV (per Wave 5.5.22 audit). Sofa-anchored
        # throw preserves Dark Contemporary moody identity without wall
        # competition. Sculptural vessel kept as second decor element.
        # NOTE : artwork is still permitted as focal-wall option via
        # room_specific_constraints (Wave 5.5.22) ; not removed from
        # atmosphere, just not mandated as decor.
        # Wave 5.5.27 — REPLACED vessel with seating-footprint rug. Vessel
        # was less critical than rug for inhabitation realism. Kept velvet
        # throw (sofa-anchored, moody character).
        # Wave 5.5.47 — "deep dark velvet" → "rich velvet";
        # "charcoal or dark tonal" → "charcoal tones". Same mood-
        # preserving cleanup.
        decor_language=["rich velvet throw layered on the sofa", "deep-pile rug in charcoal tones within the seating footprint"],
        realism_constraints=["sofa sized correctly — not modelling-scale oversized", "floor in correct proportion — wood grain or stone texture visible"],
        # Wave 5.5.22 — added "a television" as alternative focal option.
        # Originally "artwork as single focal wall" implicitly excluded TV.
        # Wave 5.5.38 — WM-parity rewrite. [0] standardized TV anchor
        # ("single clear focal wall — ..., not multiple") forces a clear
        # focal choice (resolves the TV emission paradox observed in bench
        # 2026-05-25 despite the anchor existing — dark atmosphere was
        # overwhelming the focal directive). [1] luminosity floor
        # strengthened: explicit "maintain natural daylight from windows"
        # signal added so window-as-light-source survives the dark mood.
        # Wave 5.5.45 — [0] TV-first reorder (same pattern as 5.5.43/44).
        # [1] dropped trailing "not pure darkness" - the word "darkness"
        # was reinforcing what it was trying to forbid. Replaced with
        # positive framing "preserve visible interior detail".
        # Wave 5.5.47 — [1] strengthened daylight preservation directive.
        # User feedback: "met de jour toujours" (always render daytime).
        # Wave 5.5.49 — [0] adopting universal media console flex pattern
        # for consistency across all 8 atmospheres.
        room_specific_constraints=["television visible in living area on existing wall surface or media console — never on a newly created wall", "maintain photographed natural daylight from windows + warm interior glow — render daytime scene matching photographed time of day"],
        # Wave 5.5.38 — added "visible kitchen" continuity matching WM
        # pattern. Previous wording mentioned only "visible dining area".
        visible_transition_logic="charcoal plaster and smoked oak floor continue into adjacent rooms; bronze accents echo through visible kitchen or dining area if present",
        # Wave 5.5.45 — paradoxical "black"/"dark" words removed from
        # negative_rules. Even in anti-formulations these prime the model.
        # [0] "no all-black room" → "no monochrome saturation" (positive
        # framing of same intent without "black").
        # [3] "no grey rather than charcoal — must be warm dark" → "no
        # neutral grey — warm charcoal tones only" (drops "dark").
        # Slots [1] + [2] unchanged.
        # Wave 5.5.48 Path 1 — daylight photography stylistic directive
        # added at slot [0] (most-emitted position). The model was treating
        # the photo as a "cinematic night shot of a dark luxury space"
        # instead of "daytime modern living room with dark luxury
        # aesthetic". Explicit "architectural daylight photography" tag
        # blocks the cinematic-mood-shot interpretation. Trade-off : "no
        # chrome or silver hardware" demoted to slot [3] (not emitted in
        # AVOID line). Daylight readability is the higher product priority.
        negative_rules=["render as architectural daylight photography — NOT cinematic night or evening mood shot — preserve photographic exposure level", "no monochrome saturation", "no neon or coloured accent light", "no chrome or silver hardware", "no neutral grey — warm charcoal tones only"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="dark_contemporary",
        room_type="master_bedroom",
        furniture_language=["dark velvet or leather — low tactile surface depth", "smoked oak or dark stone — floating surface drama", "dark bronze — metallic mirror depth"],
        material_palette=["dark charcoal plaster walls", "smoked oak or dark stone floor", "dark velvet or leather upholstery"],
        lighting_behavior="Concealed warm slot above headboard + bedside table lamps with dark shade and warm bulb.",
        # Wave 5.5.27 — REPLACED artwork with bedside rug. Same logic as
        # living : essential over decoration.
        decor_language=["dark tonal layered bedding — charcoal, slate, deep taupe", "deep-pile rug at the bedside in charcoal or dark tonal"],
        realism_constraints=["platform bed at correct height — 40–45 cm", "bedding layers visible and weighted, not flat"],
        room_specific_constraints=["dark tonal palette throughout — no light contrast piece breaking mood", "no decorative ceiling feature — ceiling plain dark"],
        visible_transition_logic="dark plaster and smoked oak flow into ensuite; tonal dark palette maintains continuity through visible dressing area",
        negative_rules=["no light or white bedding", "no chrome hardware", "no mirrored furniture", "no cold grey tone"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="dark_contemporary",
        room_type="kitchen",
        furniture_language=["dark charcoal or black matte cabinetry — flat-front", "dark marble or black stone countertop and island", "integrated appliances behind dark panel fronts"],
        material_palette=["dark matte cabinetry in charcoal or black", "dark Nero Marquina or black stone countertop", "brushed bronze or gunmetal hardware"],
        lighting_behavior="Concealed warm under-cabinet strip + single bronze pendant over island; dramatic task lighting.",
        decor_language=["single dark ceramic vessel on island — empty", "open bronze shelf with 3 dark-toned ceramics only"],
        realism_constraints=["island at correct 90 cm working height", "cabinet panels at correct residential height"],
        room_specific_constraints=["single dark stone for counter and backsplash — no tile", "bronze hardware throughout — no mixing with other finishes"],
        visible_transition_logic="dark cabinetry and stone echo into dining area; bronze pendant palette continues over dining table",
        negative_rules=["no white or cream cabinetry", "no chrome handles", "no warm wood visible", "no under-lit glass shelving"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="dark_contemporary",
        room_type="bathroom",
        furniture_language=["floating dark stone or concrete vanity top with recessed basin", "dark stone or concrete freestanding tub", "frameless glass shower with dark stone surround"],
        material_palette=["book-matched dark marble or black stone floor and walls", "brushed bronze or gunmetal fixtures", "dark timber or concrete vanity"],
        lighting_behavior="Concealed warm perimeter slot at ceiling + single warm backlit mirror; near-dark ambience.",
        # Wave 5.5.27 Phase 3b — REPLACED vessel with mirror (bathroom
        # essential). User-locked wording : "above the existing vanity"
        # (drops "floating" — opening-simulation risk mitigation).
        decor_language=["single dark-framed mirror above the existing vanity", "folded dark linen towel on bronze wall bar"],
        realism_constraints=["vanity slab at correct 80–85 cm height", "stone walls with correct veining and joint lines"],
        room_specific_constraints=["all fixtures in brushed bronze or gunmetal — single finish only", "no light countertop surfaces — dark throughout"],
        visible_transition_logic="dark stone floor continues from dressing area; bronze fixtures echo through door hardware",
        negative_rules=["no white tiles", "no chrome", "no light stone", "no over-lit mirror wall"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="dark_contemporary",
        room_type="terrace",
        furniture_language=["deep outdoor sofa in dark charcoal outdoor fabric", "dark concrete or stone low table", "minimal steel or concrete pergola"],
        material_palette=["dark honed stone or brushed concrete paving", "dark charcoal outdoor upholstery", "brushed steel or dark concrete structure"],
        lighting_behavior="Concealed warm strips under pergola beam + low bronze floor lanterns; dramatic evening tone.",
        decor_language=["single large dark ceramic planter with sculptural plant", "dark steel fire pit as evening focal element"],
        realism_constraints=["outdoor sofa at correct scale for terrace", "paving at correct level with correct joint lines"],
        room_specific_constraints=["shade structure in dark material — steel or concrete, not timber", "single seating zone — no outdoor dining set"],
        visible_transition_logic="dark paving continues to pool deck; dark interior visible through glass doors as continuation",
        negative_rules=["no rattan", "no warm timber pergola", "no coloured cushions", "no string lights"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="dark_contemporary",
        room_type="facade",
        furniture_language=["dark render or black concrete facade", "steel or concrete cantilevered canopy at entrance", "pivot door in dark steel or timber"],
        material_palette=["dark charcoal render or black concrete finish", "dark steel window frames", "dark bronze or gunmetal door hardware"],
        lighting_behavior="Concealed ground uplights washing dark facade + single warm entrance flood; dramatic night presence.",
        decor_language=["facade as pure dark sculptural mass — no decoration", "single specimen tree in black crushed stone forecourt"],
        realism_constraints=["render texture visible — not CGI-smooth black", "window proportions architectural — not suburban"],
        room_specific_constraints=["single facade material — dark render or concrete only", "no visible entrance porch — canopy only"],
        visible_transition_logic="dark render continues to boundary wall; dark stone threshold echoes interior floor",
        negative_rules=["no warm sand render", "no timber cladding", "no white or light facade", "no suburban window proportions"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="dark_contemporary",
        room_type="dining_room",
        furniture_language=["dark marble or stone dining table on sculptural bronze base", "upholstered chairs in dark velvet or leather", "dark timber or bronze credenza"],
        material_palette=["smoked oak or dark stone floor", "dark charcoal plaster walls", "dark velvet or leather upholstery"],
        lighting_behavior="Single large sculptural pendant in bronze or dark metal over table; warm focused glow.",
        decor_language=["single sculptural dark ceramic centrepiece", "pair of dark candle columns flanking table"],
        realism_constraints=["pendant at correct height — 70–80 cm above table", "chairs at correct seat height"],
        room_specific_constraints=["all chair upholstery matching — dark tonal palette", "no light contrast table surface"],
        visible_transition_logic="dark plaster and smoked oak echo living room; bronze pendant palette continues through to kitchen",
        negative_rules=["no light table surface", "no crystal chandelier", "no patterned upholstery", "no bright centrepiece"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="dark_contemporary",
        room_type="balcony",
        furniture_language=["two dark steel or concrete armchairs", "small dark concrete side table", "single sculptural dark planter"],
        material_palette=["dark honed stone or brushed concrete balcony floor", "dark steel or glass balustrade", "dark outdoor upholstery"],
        lighting_behavior="Single recessed warm floor light + small bronze wall sconce; dramatic evening tone.",
        decor_language=["single dark ceramic pot with architectural plant — black pine or sculptural succulent", "no cushion — or single dark cover only"],
        realism_constraints=["chairs at correct scale for balcony", "balustrade at safety height"],
        room_specific_constraints=["dark material throughout — no warm timber accent", "single plant — not a collection"],
        visible_transition_logic="dark floor continues from interior; dark interior and warm glow visible through glass",
        negative_rules=["no warm rattan", "no coloured cushions", "no decorative lanterns", "no suburban balcony chair set"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="dark_contemporary",
        room_type="pool_area",
        furniture_language=["dark stone or concrete sun loungers or platforms", "minimal steel or concrete cantilevered shade", "single sculptural planter at pool edge"],
        material_palette=["dark honed stone or concrete pool deck", "dark pool liner — black or deep charcoal", "brushed steel or dark concrete pool coping"],
        lighting_behavior="Warm underwater lighting reflected against dark liner + concealed deck strip at coping level.",
        decor_language=["pool as dark mirror at night — primary visual", "single specimen architectural tree in dark crushed stone"],
        realism_constraints=["dark pool liner creates mirror effect — not just dark", "lounger platforms at correct rest height"],
        room_specific_constraints=["dark pool liner — mandatory", "no white or cream sun loungers"],
        visible_transition_logic="dark stone deck continues to terrace paving; dark facade visible as dramatic backdrop",
        negative_rules=["no light stone deck", "no white loungers", "no bright parasols", "no resort-blue water tone"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="dark_contemporary",
        room_type="garden",
        furniture_language=["single dark steel or concrete garden bench", "architectural specimen tree — black bamboo or olive", "dark crushed stone or gravel ground plane"],
        material_palette=["dark crushed stone or black gravel ground plane", "dark steel garden bench or plinth", "deep green or dark foliage planting only"],
        lighting_behavior="Single dramatic uplight on specimen tree + ground-level warm strips; garden as lit sculpture.",
        decor_language=["single architectural specimen as sole focal element", "dark ground plane as canvas for specimen"],
        realism_constraints=["ground plane at correct grade level", "specimen tree at correct planted scale"],
        room_specific_constraints=["dark ground surface only — no lawn or pale gravel", "single species specimen — not a planting mix"],
        visible_transition_logic="dark stone continues to terrace; dark facade visible at garden boundary",
        negative_rules=["no lawn", "no light gravel", "no mixed planting", "no colourful planting"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="dark_contemporary",
        room_type="entrance_hall",
        furniture_language=["dark stone or concrete console table — floating or slab-based", "large dark bronze-framed mirror", "single sculptural vessel in dark ceramic or stone"],
        material_palette=["large-format dark stone floor", "dark charcoal plaster walls", "brushed bronze or gunmetal hardware"],
        lighting_behavior="Single narrow ceiling slot over console + wall cove at ceiling; arrival through precision warm beam.",
        decor_language=["single sculptural dark vessel — empty", "no artwork — dark plaster wall as composition"],
        realism_constraints=["console at correct 80–85 cm height", "mirror height 150 cm+ for architectural proportion"],
        room_specific_constraints=["single object on console — enforced discipline", "no coats or storage visible at entry"],
        visible_transition_logic="dark stone floor and charcoal plaster flow unbroken into living room; bronze hardware echoes throughout",
        negative_rules=["no warm oak console", "no decorative objects cluster", "no coat rack", "no warm-toned entry"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="dark_contemporary",
        room_type="home_office",
        furniture_language=["large dark stone or lacquer desk — floating or on dark base", "high-back chair in dark leather", "floor-to-ceiling dark shelving with edited display"],
        material_palette=["smoked oak or dark stone floor", "dark charcoal plaster walls", "brushed bronze desk accessories"],
        lighting_behavior="Concealed warm bookshelf backlighting + single adjustable bronze task lamp on desk.",
        decor_language=["curated books with neutral or dark spines", "single dark ceramic or stone desk object"],
        realism_constraints=["desk at correct 72–75 cm working height", "shelving with correct structural depth — 30 cm minimum"],
        room_specific_constraints=["cable management complete — no visible wires", "shelving with breathing space — not overloaded"],
        visible_transition_logic="dark floor and plaster echo hallway and living room; bronze accessories match hardware throughout",
        negative_rules=["no light wood desk", "no white walls", "no cold LED task light", "no RGB accent lighting"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="dark_contemporary",
        room_type="driveway",
        furniture_language=["dark concrete or steel gate", "dark stone or concrete driveway with minimal edging", "single specimen tree in dark crushed stone forecourt"],
        material_palette=["dark honed stone or brushed concrete driveway", "dark steel or concrete gate pillars", "dark crushed stone or black gravel infill"],
        lighting_behavior="Single ground uplight on specimen tree + concealed warm strip at gate reveal; dramatic arrival.",
        decor_language=["single dark crushed stone forecourt — no planting borders", "architectural gate as only arrival element"],
        realism_constraints=["driveway at correct width — 3.5–4 m for penthouse scale", "gate pillar proportioned correctly for gate width"],
        room_specific_constraints=["single dark material for driveway — no mixing", "gate in dark steel only — no timber mix"],
        visible_transition_logic="dark stone driveway continues to entrance threshold; dark facade visible as dramatic backdrop from gate",
        negative_rules=["no pale gravel", "no warm render boundary", "no ornate gate", "no warm lanterns — cool precision only"],
    ),
]:
    register(_d)
