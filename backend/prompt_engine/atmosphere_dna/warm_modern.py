from ._base import AtmosphereCoreDNA, RoomAdaptationDNA, register_core, register

# Wave 5.13b — Warm Modern daylight recalibration (2026-05-31).
# Diagnosis : Warm Modern was over-anchored on "boutique hotel" +
# "indirect warmth" + per-room "evening tone" cues. Result : the model
# generated dark, orange, hotel-at-night interiors on daytime uploads.
# Fix : keep warm + premium + residential identity, but rewrite the
# lighting layer to lead with natural daylight as the primary
# illumination and demote warm task lamps to "soft accent" so the room
# stays inviting without going dark or evening-moody.
register_core(AtmosphereCoreDNA(
    atmosphere_id="warm_modern",
    philosophy="Warm contemporary luxury rooted in emotional comfort, hospitality, softness, and believable urban premium living.",
    emotional_intent="Comforting, refined, welcoming, calm, premium, elegant but livable.",
    architectural_language="Organic forms softened by curves, warm-toned natural materials, and bright daylit residential-scale spaces.",
    material_palette=["European oak", "travertine", "warm sand plaster", "brushed brass", "warm linen"],
    lighting_behavior="Warm natural daylight as primary illumination; supplementary warm table lamps and sconces as soft accent — bright inviting residential warmth, not dark hotel mood.",
    # Wave 6.13g (2026-06-05) — de-orange Levier 1: white-balance cue in the
    # luxury_level (ships in every WM prompt's ATMOSPHERE [bracket]). Pins the
    # LIGHT to neutral daylight while keeping warmth in materials + mood.
    luxury_level="Bright premium urban residence / contemporary warm home photographed in natural daylight with a true neutral white balance — warm in materials and mood, not an orange or amber colour cast",
    forbidden_elements=["Cold minimalism", "sterile white interiors", "ultra glossy marble overload", "fake luxury gold", "overdecorated styling"],
    atmosphere_keywords=["warm contemporary", "boucle", "travertine", "oak", "daylit warmth"],
))

for _d in [
    RoomAdaptationDNA(
        atmosphere_id="warm_modern",
        room_type="living_room",
        furniture_language=["bouclé in oat or camel — warm curved tactile richness", "travertine — warm stone surface depth with brass or oak accent", "warm linen — oak-toned textural warmth"],
        # Wave 5.12c — anchored "warm sand plaster walls" → "warm sand
        # plaster finish on existing walls" (mirror of Wave 5.7e SL and
        # 5.7f Nature). Removes the plural-noun directive that competed
        # with the wall-preservation negative_rule and pushed the model
        # to materialize new walls to satisfy the atmosphere identity.
        material_palette=["wide-plank European oak floor", "warm sand plaster finish on existing walls", "travertine slab surfaces"],
        lighting_behavior="Warm natural daylight from windows + warm table lamps as soft accent; bright inviting residential warmth.",
        # Wave 5.5.21 fix A2 — dropped "oversized ceramic vessel on floating
        # oak shelf" from decor_language. This decor element was occupying
        # the wall focal area (shelf + vessel) and competing with TV
        # placement. Kept floor-length curtains (window-anchored, no
        # conflict with TV).
        # Wave 5.5.27 — APPEND rug essential (only 1 decor item so no
        # replacement needed). Rug anchored to seating footprint.
        # Wave 6.14 (2026-06-09) — Emotional Styling Layer PILOT (WM-Living only).
        # decor 2 → 6, same validated recipe as Dining 6.13 / Master Bedroom:
        # every item is portable + gravity-obeying + anchored to an EXISTING
        # surface; wall art uses CONDITIONAL OMIT; greenery uses anchored-corner.
        # NO floor-standing item that implies architecture (the 6.2a risk).
        # Closes the "large empty room" gap (bare walls / no greenery / bare
        # sofa) WITHOUT touching room_specific_constraints (TV anchor) or fidelity.
        # Gate: walls invented = 0 AND naturalness >= 4/5, else revert this line.
        decor_language=[
            "floor-length warm linen curtains in oat or camel clearly framing each existing window, drawn open with the glass left fully clear — never covering, narrowing or blocking it, never on a glass partition",
            "soft wool rug in oat or camel within the seating footprint",
            "layered warm linen and bouclé cushions in oat or camel on the existing sofa — natural asymmetric placement, visible fabric weight",
            "a relaxed warm linen or wool throw draped over the existing sofa or armchair — lived-in, not styled flat",
            "compact potted olive or trailing plant anchored in the existing corner near the glazing — single structured pot, never floating in the room",
            "warm-toned organic abstract artwork on the existing wall above the sofa or console — only if that wall is solid and free, else omit",
        ],
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
        # Wave 6.13e (2026-06-05) — close the glass→wall loophole for the TV.
        # Wave 5.5.49 stopped most "faux mur" TV mounts, but on glass-heavy
        # sources (sliding glass + black-framed glass partition) the model still
        # converted the partition into a solid wall to host the TV. Echo the
        # captured term "glass partition" so the ban binds to the seen feature.
        # Wave 6.16 (2026-06-10) — EMPHATIC focal-TV (same fix family as the
        # strong curtain phrasing): at fidelity=high the weak "television on an
        # existing wall…" was omitted (bare wall → model plays safe). Ported the
        # emphatic focal-TV phrasing from Japandi so the TV reliably renders,
        # keeping the never-new-wall / never-glass→wall guards.
        room_specific_constraints=["seating in conversation grouping", "include a television as the living-room focal point, in the primary seating's forward sightline, on an existing wall or low media console, never a new wall or by converting glazing into a wall"],
        visible_transition_logic="oak floor and warm plaster continue into adjacent rooms; brass accents echo through visible kitchen or hallway",
        negative_rules=["no cold grey palette", "no chrome hardware", "no matching 3-piece suite", "no floating furniture without visible support"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="warm_modern",
        room_type="master_bedroom",
        # Wave 6.6 (2026-06-04) — master_bedroom emotional enrichment.
        # Wave 6.7 (2026-06-04) — A+B vocab + lived-in items (6 items).
        # Wave 6.12 first attempt ROLLED BACK 2026-06-04 — micro-tuning
        # didn't deliver visible delta. User analysis : WM had NO signature
        # item (vs Japandi paper lantern, Nordic sheepskin, Tropical palm).
        # Wave 6.12 comprehensive 2026-06-04 — 4-direction polish per user :
        #   1. SIGNATURE ITEM : boucle/shearling bench at foot of bed
        #      (premium tactile, residential warmth marker)
        #   2. LIGHTING POLISH : concealed warm cove + matched amber lamps
        #      + golden ambient warmth descriptor
        #   3. MATERIAL REALISM : European oak with visible grain pattern,
        #      travertine with subtle natural vein
        #   4. SPATIAL COMPOSITION : matched nightstand pair flanking bed
        # → 6 → 7 items decor_language. NO conditional wall art (photo
        # droite target shows restrained, not dramatic above-bed).
        # Source taxonomy : Type A sources (clean bed wall) optimal ;
        # Type B sources (bed wall with openings) may render weaker WM
        # differentiation — accept as MVP baseline.
        furniture_language=["warm oat linen with visibly relaxed folds and natural fabric weight — layered tactile warmth", "European oak timber with visible natural grain — floating surface warmth at wall level", "European oak with visible grain and warm-toned timber — warm mirror surface quality"],
        material_palette=["European oak floor with visible natural grain", "warm sand plaster finish on existing walls", "travertine bedside surfaces with subtle natural vein"],
        # Wave 6.13f (2026-06-05) — de-orange: amber/golden intensifiers added in
        # 6.12 reverted toward natural daytime tone (user: WM too orange). Warmth
        # kept in materials + mood, not in the light's colour cast.
        lighting_behavior="Soft warm morning daylight from windows across the bedding + matched warm bedside table lamps with soft warm glow + concealed warm cove; bright inviting residential intimacy with natural daytime warmth, not dark hotel mood.",
        # Wave 5.5.27 — REPLACED artwork with bedside rug. Kept layered bedding.
        # Wave 6.6 (2026-06-04) — extended from 2 to 4 items.
        # Wave 6.7 (2026-06-04) — A+B vocab + lived-in items (6 items).
        # Wave 6.12 (2026-06-04) — NEW item 7 : signature boucle/shearling
        # bench at foot of bed. WM identity now has a visible signature
        # element (matches photo-droite target premium tactile bench).
        decor_language=[
            "floor-length warm linen curtains in oat or camel clearly framing each existing window, drawn open with the glass left fully clear — never covering, narrowing or blocking it, never on a glass partition",
            "VISIBLY relaxed warm linen and boucle bedding with clearly natural asymmetric folds and visible fabric weight — natural moment, not hotel turndown",
            "soft wool rug at the bedside in oat or camel",
            "PROMINENTLY displayed warm-toned ceramic vase on the existing nightstand or dresser",
            "matched warm-toned ceramic bedside lamps producing soft ambient glow",
            "open book or magazine on the existing nightstand",
            "small framed photograph on the existing dresser",
            "single boucle or shearling-upholstered bench at the foot of the existing bed",
        ],
        realism_constraints=["bed at correct height — not floating too high", "bedding draped with visible relaxed folds and natural weight — not hotel-stiff"],
        room_specific_constraints=["matched nightstand pair flanking the existing bed — same height with bedside lamps", "no TV directly facing bed unless wall-mounted flush"],
        visible_transition_logic="oak floor and warm plaster flow into visible ensuite; linen palette continues in towel accents",
        negative_rules=["no cold white bedding", "no mirrored furniture", "no heavy dark drapes", "no hotel-generic sets"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="warm_modern",
        room_type="kitchen",
        # Wave 6.13b (2026-06-05) — kitchen enrichment across 5 MVP atmospheres.
        # RESTRAINT is the brief (col 3 warns trop plantes / trop objets) : all
        # accents on EXISTING surfaces (island / shelf / windowsill / oven rail),
        # NO floor objects, NO wall art (cabinet walls + clutter risk). Scope =
        # kitchen blocks ONLY. WM target : indirect glow + handcrafted ceramic +
        # relaxed linen + warm daylight + soft material variation.
        # Wave 6.13h (2026-06-05) — door-preservation baked into the cabinetry
        # description itself (positive, constructive framing in ATMOSPHERE STYLE),
        # higher prominence than the ROOM CONTEXT guard. Bench: WM kitchen 3/4
        # door removed — uppers were spanning over the door to form a continuous
        # run. Keeps the look (upper+lower oak); only adds the stop-at-opening
        # layout rule. Kitchen furniture_language only — nothing else touched.
        furniture_language=["flat-front pale oak cabinetry, upper and lower, arranged only along uninterrupted wall runs — stopping cleanly at any existing door or window, never spanning across or covering an opening", "travertine slab island or countertop", "integrated appliances flush with cabinet faces"],
        material_palette=["pale oak cabinetry", "thick travertine countertop", "warm sand tile or plaster backsplash"],
        # Wave 6.13f (2026-06-05) — de-orange (see bedroom note): ambient→natural warmth.
        lighting_behavior="Bright warm residential daylight across the worksurfaces + subtle warm under-cabinet indirect glow grazing the splashback + soft natural warmth; inviting daytime residential brightness, handcrafted and lived-in.",
        decor_language=[
            "warm linen curtains in oat or camel framing the existing window, drawn open with the glass clear — never covering or blocking it, never on a glass partition; only where a window exists",
            "single oversized handcrafted ceramic pendant over the existing island — artisan-glazed, warm neutral tone",
            "open oak shelf styled with 3 handcrafted neutral ceramic pieces — curated, not crowded",
            "a relaxed natural linen tea towel draped over the existing oven rail — soft lived-in texture",
            "single handcrafted ceramic bowl holding a few lemons or fruit on the existing island — one vessel only",
            "a small potted herb on the existing windowsill — one only, restrained",
        ],
        # Wave 6.13i (2026-06-05) — structure preservation promoted into REALISM
        # (higher authority than ROOM CONTEXT). Bench: only 1/4 kept door+window;
        # 3/4 removed the door OR enlarged/moved the window. Closes the gap the
        # earlier guards missed: enlarge / extend-across-wall / remove.
        realism_constraints=["preserve every existing window, door and wall opening exactly as photographed — same wall, same size, same position; never enlarge, extend across the wall, narrow, relocate, remove, or cover them with cabinetry", "cabinet doors at correct residential height, not commercial scale"],
        # Wave 6.13c (2026-06-05) — kitchen structure-preservation guard at [0].
        # WM is a documented "wall-symmetry-leaning" atmosphere (structural_identity.py
        # ~L532) prone to relocating openings; kitchen amplifies it (cabinetry competes
        # for the window wall). Must be index [0] — build_dna_room_context ships only [:2].
        # "doorway" (not "door") avoids cabinet-door collision. Kitchen-scoped only.
        room_specific_constraints=["arrange cabinetry and island only around the existing openings — never cover, narrow, enlarge, extend across the wall, relocate, or remove any window, doorway or wall opening; keep every opening at its exact photographed size and position", "handle-free or brushed brass handles only", "no visible appliance clutter on countertop"],
        visible_transition_logic="oak cabinetry palette echoes dining furniture visible beyond; travertine floor or countertop continues",
        negative_rules=["no stainless steel excess", "no dark granite", "no chrome handles", "no open shelf clutter"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="warm_modern",
        room_type="bathroom",
        furniture_language=["floating double oak vanity", "freestanding stone soaking tub", "frameless glass shower screen"],
        material_palette=["travertine floor and wall surfaces", "floating oak vanity", "brushed brass fixtures"],
        lighting_behavior="Bright warm daylight from window or skylight + warm vanity sconce as soft accent; clean inviting daytime bathroom warmth.",
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
        lighting_behavior="Bright afternoon daylight under pergola shade + warm outdoor pendant as soft accent; inviting warm residential outdoor atmosphere.",
        decor_language=["anchored to the existing terrace floor, parapet, garde-corps and any existing shade structure — existing architecture and openings kept exactly; no new walls, no enclosure, no building roof, no floor or deck extension", "layered Mediterranean planting filling the perimeter and any bare ground — an olive tree in a large terracotta urn, flowering terracotta planters and ornamental grasses grouped for landscaped depth", "a low reclaimed-wood coffee table styled with hurricane candle lanterns, a stoneware bowl and a tray", "layered oat and camel linen cushions and a soft throw on the sofa", "a patterned natural-fibre outdoor rug grounding the lounge zone", "where the terrace is large enough, a teak dining table with woven or timber chairs, set with candle lanterns", "a soft linen drape on the pergola or shade structure and a cluster of lanterns along the floor edge"],
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
        lighting_behavior="Bright natural daylight on facade + warm entrance lanterns as soft accent; inviting warm residential exterior brightness.",
        # Wave 6.26 (2026-06-06) — facade enrichment, ARCHITECTURE-SAFE: ground/entrance
        # only, never touch the building. Reinforced guard at [0].
        decor_language=["keep the building exactly — never add, alter, narrow, extend, or restyle any wall, window, door, roof, cladding or structure; only ground-level planting, a doormat and warm light on the existing entrance", "single material discipline: render + timber + natural stone", "warm proportioned window rhythm", "a pair of potted olive trees or structured plants flanking the existing entrance", "a natural coir or stone doormat at the existing threshold"],
        realism_constraints=["window proportions match interior room heights", "render texture visible — not hyper-smooth CGI"],
        room_specific_constraints=["entrance door clearly legible as focal point", "no more than two cladding materials on facade"],
        visible_transition_logic="warm sand render tone flows to boundary walls; timber window frames echo interior oak palette",
        negative_rules=["no cold grey render", "no UPVC window frames", "no suburban builder aesthetic", "no excessive cladding mix"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="warm_modern",
        room_type="dining_room",
        # Wave 6.13 (2026-06-05) — dining_room enrichment across 5 MVP atmospheres.
        # Same validated pattern as Master Bedroom 6.6→6.12 : 2 → 6 decor items,
        # VISIBLY/PROMINENTLY vocab, lived-in layers. Safety patterns inherited :
        #   - floor-standing / corner plant ANCHORED to existing surface (floor-claim)
        #   - wall art uses CONDITIONAL OMIT on sideboard wall (Type B preservation)
        # WM target (col 2/3) : indirect warmth + artisan ceramic + natural textile
        # + organic wall art. WM stays the most "added" atmo (weakest native signature).
        furniture_language=["oval travertine-top table on brass base", "upholstered dining chairs in warm linen", "oak sideboard with concealed storage"],
        material_palette=["European oak floor", "warm plaster finish on existing walls", "travertine or warm stone table top"],
        # Wave 6.13f (2026-06-05) — de-orange (see bedroom note): golden→natural.
        lighting_behavior="Warm daylight from the existing window across the table + warm brass pendant glow as soft accent + gentle indirect ambient warmth washing the existing walls; bright inviting daytime dining warmth, natural and residential.",
        decor_language=[
            "floor-length warm linen curtains in oat or camel clearly framing each existing window, drawn open with the glass left fully clear — never covering, narrowing or blocking it, never on a glass partition",
            "PROMINENTLY displayed handcrafted ceramic centrepiece on the existing table — artisan-glazed with visible hand-thrown character, not mass-produced",
            "relaxed place settings on the existing table — natural linen napkins and warm stoneware plates, lived-in not formal",
            "warm-toned organic abstract artwork above the existing sideboard — only if that wall is free, else omit",
            "two curated ceramic objects styled on the existing sideboard — a vase and a low bowl, intentionally spaced",
            "compact potted olive or trailing plant on the existing sideboard",
        ],
        realism_constraints=["pendant hung at correct dining height — 70–80 cm above table surface", "chairs at correct seat height for table"],
        room_specific_constraints=["table sized for room — not oversized", "sideboard against wall, not floating in room"],
        visible_transition_logic="oak floor and warm plaster echo through to kitchen; linen chairs palette visible from living room",
        negative_rules=["no cold marble top", "no maximalist or banquet-formal tablescaping", "no mismatched chairs", "no chandelier"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="warm_modern",
        room_type="balcony",
        furniture_language=["compact rattan two-seat sofa", "small teak or stone side table", "single ceramic pot with structured plant"],
        material_palette=["composite or natural stone balcony floor", "warm linen cushion fabric", "glass or simple steel balustrade"],
        lighting_behavior="Open warm daylight + single warm sconce as soft accent; bright inviting residential balcony atmosphere.",
        # Wave 6.26 (2026-06-06) — balcony enrichment (anchoring guard at [0]).
        decor_language=["anchored to the existing balcony floor, railing and furniture — existing layout kept exactly; no added walls, new structures, roofs or extensions", "warm linen throw draped on sofa", "compact olive tree or trailing plant", "a small tray with two cups on the existing side table", "layered linen cushions on the existing sofa", "a lantern on the existing floor or table", "a soft outdoor rug in oat or camel grounding the seating on the existing floor"],
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
        lighting_behavior="Bright natural afternoon daylight on deck + warm underwater pool tone as soft accent; inviting warm outdoor residential brightness.",
        # Wave 6.25 (2026-06-06) — pool enrichment. Guard at [0] = user constraint:
        # everything anchored to existing surfaces/layout, no new architecture.
        decor_language=["anchored to the existing deck, coping and furniture — existing pool and spatial layout kept exactly; no added walls, new structures, roofs, pergolas or architectural extensions", "flush travertine coping at pool edge", "layered Mediterranean planting filling the deck perimeter and any open or bare ground — olive trees, ornamental grasses and lavender massed in clustered terracotta and stone planters for landscaped depth", "rolled towels and a stone tray with a carafe and two glasses on the existing side table", "layered linen cushions and a folded throw on the existing loungers", "a few lanterns set along the existing deck edge"],
        realism_constraints=["pool coping at correct height above deck", "loungers spaced at correct 60–80 cm clearance"],
        room_specific_constraints=["pool coping in single material — no mixing stone types", "deck furniture grouped in one zone — not scattered, while the surrounding ground is fully landscaped with planting"],
        visible_transition_logic="travertine deck material continues to terrace or garden; warm facade render visible as backdrop",
        negative_rules=["no plastic sun loungers", "no bright parasols", "no cold blue water overemphasis", "no bare or unplanted ground around the deck"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="warm_modern",
        room_type="garden",
        furniture_language=["oak or teak outdoor lounge sofa with warm cushions around a low table, plus an oak dining table and chairs where the garden is large enough", "stone or terracotta planters and urns", "specimen olive or tree as focal point"],
        material_palette=["natural limestone or sandstone paving", "warm-toned terracotta pots", "gravel infill between pavers"],
        lighting_behavior="Open natural daylight on planting + warm path lighting as soft accent; bright inviting warm garden atmosphere.",
        # Wave 6.26 (2026-06-06) — garden enrichment (anchoring guard at [0]; see WM balcony).
        decor_language=["anchored to the existing paving, beds and garden footprint — existing layout kept exactly; no added walls, new structures, roofs, pergolas or hardscape", "edited planting palette in warm greens and silvers", "clean paving-to-planting edge transition", "potted olive or herbs in terracotta on the existing paving", "soft cushions on the existing oak chairs", "warm lanterns along the existing path"],
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
        lighting_behavior="Bright daylight from windows or door glazing + warm wall sconce as soft accent; welcoming warm residential arrival.",
        # Wave 6.24 (2026-06-06) — entrance enrichment, SURFACE/FLOOR only (no new
        # wall items — keeps the 6.23 opening-preservation intent intact).
        decor_language=[
            "warm linen curtains in oat or camel framing the existing window, drawn open with the glass clear — never covering or blocking it, never on a glass partition; only where a window exists",
            "dried or fresh botanicals in ceramic vessel",
            "single warm-toned artwork above console",
            "a styled oak or brass tray with a small catch-all dish on the existing console",
            "a warm-toned table lamp on the existing console — soft welcome glow",
            "a natural wool or jute runner along the floor",
        ],
        realism_constraints=["console at correct height — 80–90 cm", "mirror sized proportionally to wall, not too small"],
        # Wave 6.23 (2026-06-06) — entrance opening-preservation guard at [0].
        # Bench: entrance hall walled the left passage to host the console/mirror
        # (passage was even mis-captured as a "window"). Guard the wall-hungry
        # entrance decor away from openings. entrance_hall only. Ships [:2].
        room_specific_constraints=["place the console, mirror and wall decor on an existing solid wall only — never cover, wall over, narrow or replace any existing opening, doorway or passage; if the only free wall is an opening, keep it open and place the console along a solid wall or omit it", "clear circulation path to adjacent rooms", "no visual clutter at entry — single focal console"],
        visible_transition_logic="travertine floor continues to living room; oak console echoes living room furniture palette",
        negative_rules=["no visible coat hooks from entry", "no cluttered surfaces", "no cold white tiles", "no mirror below console height"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="warm_modern",
        room_type="home_office",
        # Wave 6.17 (2026-06-06) — desk upsized (was rendering too small vs SL).
        # SL desk says "large" and renders right; mirror that keyword here.
        furniture_language=["large solid oak desk with a clean flat profile — generous full-width work surface", "linen upholstered chair on warm oak base", "floating oak shelves above desk"],
        material_palette=["European oak desk surface", "warm sand plaster finish on existing walls", "warm linen upholstery"],
        lighting_behavior="Bright warm daylight at desk + brushed brass task lamp as soft accent; clean inviting residential workspace warmth.",
        # Wave 6.14 (2026-06-06) — home_office enrichment, 5 MVP atmospheres.
        # Target: calm/inspiring/productive — authentic materials, greenery, rug,
        # personal touch. Decor anchored to EXISTING desk/shelf/wall/chair/floor;
        # wall art conditional-omit (no wall invention). home_office only.
        # Wave 6.16 (2026-06-06) — full pack: 2nd "reading" zone + generous rug +
        # lived-in desk to fill the empty floor. Floor furniture conditional-omit
        # + "clear of any window/door". Paired with WM home_office fidelity=high.
        decor_language=[
            "floor-length warm linen curtains in oat or camel clearly framing each existing window, drawn open with the glass left fully clear — never covering, narrowing or blocking it, never on a glass partition",
            "a compact bouclé reading armchair with a small round oak side table in the open floor area — clear of any window or door, only if floor space allows, else omit",
            "a generous wool-and-jute rug spanning the desk and the seating zone",
            "a warm task lamp, an open notebook, a pen and a low stack of books arranged on the existing desk — a workspace in genuine use",
            "a handcrafted ceramic vessel and trailing pothos styled on the existing floating shelf",
            "organic warm-toned abstract artwork on the existing wall above the desk — only if that wall is free, else omit",
            "a leafy potted plant softening the floor beside the seating zone",
            "a tall open oak bookcase against a free wall — books and a few curated objects — only if the room is large enough and it covers no window or door, else omit",
        ],
        realism_constraints=["desk at correct 72–75 cm working height", "chair at correct seat height relative to desk"],
        room_specific_constraints=["cable management — no visible cable tangle", "shelves with edited display — not overloaded"],
        visible_transition_logic="oak desk palette echoes hallway or living room flooring; warm plaster continuous",
        negative_rules=["no cold grey office aesthetic", "no aggressive ergonomic furniture styling", "no cable clutter", "no tech-showroom feel"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="warm_modern",
        room_type="driveway",
        furniture_language=["stone gate pillars in warm render", "clipped hedging or topiary flanking drive", "simple timber or warm steel gate"],
        material_palette=["natural limestone or sandstone driveway paving", "warm sand cement render for gate pillars and boundary", "warm bronze lanterns"],
        lighting_behavior="Open natural daylight on drive + warm bronze lanterns as soft accent; bright inviting warm residential approach.",
        # Wave 6.26 (2026-06-06) — driveway enrichment, ARCHITECTURE-SAFE (guard at [0]; see WM facade).
        decor_language=["keep the drive, gate, pillars and boundary exactly — never add, alter, widen or extend any wall, gate, pillar, structure or paving; only border planting, potted plants and warm light on existing surfaces", "single material consistency: render + stone + warm metal", "restrained specimen planting along boundary", "potted structured plants at the existing gate pillars", "warm bronze lanterns lit along the existing drive edge"],
        realism_constraints=["driveway width at least 3 m for single vehicle passage", "gate pillars at correct proportional height"],
        room_specific_constraints=["one consistent paving material for full drive", "boundary wall in same render as house facade"],
        visible_transition_logic="limestone paving echoes facade threshold; warm sand render of boundary walls matches house exterior",
        negative_rules=["no grey block paving", "no cold white rendered walls", "no suburban gatehouse aesthetic", "no ornate ironwork"],
    ),
]:
    register(_d)
