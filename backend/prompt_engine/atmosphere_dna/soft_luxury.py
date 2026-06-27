from ._base import AtmosphereCoreDNA, RoomAdaptationDNA, register_core, register

register_core(AtmosphereCoreDNA(
    atmosphere_id="soft_luxury",
    philosophy="Refined hospitality luxury emphasizing softness, elegance, tactile richness, and timeless sophistication.",
    emotional_intent="Indulgent, serene, tactile, quietly opulent, feminine-refined, sensorially rich.",
    architectural_language="Curved forms and soft volumes, layered textured surfaces, and silk-to-stone material transitions in generous proportions.",
    material_palette=["fluted ivory plaster", "bouclé and cashmere textiles", "honed marble in cream or blush", "brushed champagne metal", "raw silk or velvet"],
    lighting_behavior="Warm diffused glow — concealed perimeter coves, silk lampshades, no exposed bulbs.",
    luxury_level="Rosewood / Aman / luxury suite",
    forbidden_elements=["Bling luxury", "crystal chandelier clichés", "fake palace aesthetics", "excessive gold", "hard-edge minimalism"],
    atmosphere_keywords=["soft luxury", "bouclé", "fluted plaster", "ivory", "tactile refinement"],
))

for _d in [
    RoomAdaptationDNA(
        atmosphere_id="soft_luxury",
        room_type="living_room",
        furniture_language=["warm bouclé in soft taupe — plush tactile richness", "honed marble or stone — champagne brass accents, premium surface warmth", "cashmere or velvet in warm champagne and soft taupe — layered textile softness"],
        # Wave 5.7e — anchored "fluted ivory plaster walls" → "fluted
        # ivory plaster finish on existing walls" (Wave 5.7 pattern, now
        # applied to living_room). Defense in depth against the fluted-
        # plaster signature creating new walls (bench 2026-05-26 showed
        # a new fluted wall built specifically to display SL signature +
        # anchor TV/console). Pairs with strengthened wall-preservation
        # negative_rule below. Core material_palette + atmosphere_keywords
        # intentionally left untouched (user-locked 2026-05-26).
        material_palette=["fluted ivory plaster finish on existing walls", "honed cream marble floor", "brushed champagne metal accents"],
        lighting_behavior="Concealed perimeter cove + silk shade floor lamps; warm evening tone, no ceiling spotlights.",
        # Wave 5.5.26 — "oversized ceramic vessel" → "floor-level ceramic
        # vessel". Original "oversized" implied wall-shelf placement competing
        # with TV for wall focal area. Floor-level anchors the vessel without
        # competing for wall space, preserving Soft Luxury hospitality identity.
        # Wave 5.5.27 — REPLACED cushions with seating-footprint rug. Cushions
        # were sofa-anchored redundant with rug. Rug is living essential, more
        # impactful for inhabitation realism. User-locked wording (drops
        # "silk-blend" and "blush" to reduce hotel-staging semantics).
        # Wave 6.14 (2026-06-09) — Emotional Styling Layer (SL Living). decor 2→6,
        # validated recipe (anchored-to-existing + conditional-omit art +
        # anchored-corner greenery + soft furnishings). SL voice: cashmere/velvet,
        # cream/blush, champagne. Structure / materials / fidelity / TV anchor
        # untouched. Gate: walls invented = 0 AND naturalness >= 4/5, else revert.
        decor_language=[
            "floor-length cashmere or silk-blend curtains in ivory or cream clearly framing each existing window, drawn open with the glass left fully clear — never covering, narrowing or blocking it, never on a glass partition",
            "floor-level ceramic vessel with dried pampas or lunaria",
            "soft wool-blend rug in soft taupe and warm champagne tones within the seating footprint",
            "layered cashmere and velvet cushions in cream, blush and soft taupe on the existing sofa — plush asymmetric placement, visible tactile weight",
            "a weighted velvet or cashmere throw in soft taupe casually draped over the existing sofa or chaise — softly folded, lived-in luxury",
            "a sculptural potted olive or fig anchored in the existing corner near the glazing — single statement vessel in cream ceramic or matte stone, never floating in the room",
            "a warm-toned abstract or textural artwork on the existing wall above the sofa or console — only if that wall is solid and free, else omit",
        ],
        realism_constraints=["sofa sized to room — not oversized for space", "marble floor with correct 3–5 mm grout lines"],
        # Wave 5.5.22 — added "a television" as a third focal-element option
        # so the model has explicit permission to place TV. Originally read
        # "fireplace or art wall" only (TV implicitly excluded).
        # Wave 5.5.25 fix #5 ROLLED BACK 2026-05-25 — preserve bench showed
        # wall added on right side. Dropping the symmetry mandate appears to
        # have removed structural discipline that was indirectly protecting
        # the architecture. Restored original wording.
        # Wave 5.5.36 — WM-parity rewrite + symmetry paradox resolution.
        # [0] standardized TV anchor pattern ("single clear focal wall — ...,
        # not multiple") — resolves the TV emission paradox observed in
        # bench 2026-05-25 where the original 3-option list without a cap
        # let the model default to classical fireplace-centric setups.
        # [1] "symmetry in furniture placement" → "balanced furniture
        # placement" — the "symmetry as implicit structural stabilizer"
        # insight (Wave 5.5.33 audit + Wave 5.5.25 rollback history):
        # dropping symmetry caused wall added (lost the discipline);
        # keeping symmetry caused wall added (model mirrored a wall to
        # match symmetry). "Balanced" preserves the structural discipline
        # function while removing the wall-mirroring interpretation pressure.
        # Wave 5.5.46 — TV baseline pattern (TV-first reorder in Wave
        # 5.5.43 wasn't enough for Soft Luxury — model still defaulted
        # to fireplace-centric).
        # Wave 5.5.48 — TV media console flex. Wave 5.5.46's "positioned
        # on a single clear focal wall" wording caused wall invention as
        # a side effect on Nature bench (model removed back window to
        # create a wall for the TV). New wording allows TV on existing
        # wall OR media console and explicitly forbids creating a new
        # wall. TV remains mandatory ("visible in living area").
        room_specific_constraints=["include a television as the living-room focal point, seating arranged toward it — clearly present on an existing wall or low media console, never a new wall or by converting glazing into a wall", "balanced furniture placement — not haphazard"],
        # Wave 5.5.36 — added "visible kitchen" continuity matching the WM
        # pattern. Previous wording mentioned dining + hallway but never
        # kitchen, contributing to "coin cuisine perdu" in bench 2026-05-25.
        # Wave 5.14c — dropped "plaster walls" plural noun (see Japandi
        # for rationale).
        visible_transition_logic="ivory plaster and marble floor flow continuously into adjacent rooms; brass accents echo through visible kitchen, dining or hallway if present",
        # Wave 5.5.22 — dropped "no visible TV above fireplace" negative rule.
        # It explicitly forbade the most natural TV placement (the wall focal),
        # making TV nearly impossible to introduce. Other negative rules
        # (no jewel tones, no gold leaf, no asymmetric gallery wall) retained.
        # Wave 5.5.49 — added defensive wall-preservation rule at slot [0].
        # Bench 2026-05-25 (round 4) showed Soft Luxury still created a
        # wall on the right side to mount TV, EVEN WITH the media console
        # flex wording in room_specific_constraints. The curved-form +
        # symmetry semantics of Soft Luxury appear to give the model
        # permission to invent walls. Explicit defensive rule at slot [0]
        # of AVOID line. Trade-off: "no asymmetric art gallery wall"
        # demoted to slot [3] (not emitted in AVOID); wall preservation
        # is more critical than gallery-wall avoidance.
        # Wave 5.7e — strengthened wall-preservation wording. Bench
        # 2026-05-26 showed SL invented a new fluted-plaster wall to
        # mount TV + console, DESPITE the Wave 5.5.49 defensive rule.
        # The fluted-plaster signature (repeated in core material_palette
        # and atmosphere_keywords) was winning the attention battle
        # against the standard "no new walls" rule. New wording makes
        # the architectural-hierarchy distinction explicit : decoration
        # only on photographed surfaces, no new architectural support
        # surfaces for furniture or TV anchoring, preserve open sides /
        # voids / window zones / circulation spaces exactly as
        # photographed. Slot [0] stays defensive (build_dna_block ships
        # [:3]).
        # Wave 5.12c — adopt the universal wall-preservation rule. The
        # bespoke Wave 5.7e wording was the most defensive but verbose
        # (~175 chars, custom for SL only). Universalising reduces
        # cognitive load, frees ~96 chars of budget for SL creative, and
        # keeps the same protective intent. SL's fluted-plaster identity
        # remains the hardest test of this rule — bench-validate post-ship.
        # Wave 5.14c — softened wall rule (see WM for rationale).
        negative_rules=["no jewel-tone colour pops", "no gold leaf or metallic wallpaper", "no asymmetric art gallery wall"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="soft_luxury",
        room_type="master_bedroom",
        # Wave 6.6 (2026-06-04) — master_bedroom anti-CGI emotional enrichment.
        # Reinforces textile realism (asymmetrical drape, slight imperfection)
        # and refined residential intimacy. Drops "above padded headboard
        # wall" architectural directive from lighting_behavior (wall risk).
        # Room-scoped, no living_room contamination.
        furniture_language=["a sculptural, generously upholstered headboard in warm cashmere or bouclé — greige or mushroom, the bed's dominant mass, clearly deeper than the pale walls", "matched nightstands in fluted ivory lacquer or honed marble with brushed champagne brass — refined and modern, never rustic or dark wood", "a fluted ivory lacquer chest of drawers or dresser with brushed champagne brass hardware — a calm secondary mass against an existing wall", "velvet or bouclé seating in champagne plus an upholstered foot-of-bed bench with slim brushed-brass legs"],
        material_palette=["honed marble or travertine floor", "fluted ivory plaster finish on existing walls", "honed marble or travertine tops, fluted ivory lacquer, brushed champagne brass, raw silk and velvet"],
        lighting_behavior="Soft warm daylight from windows + concealed warm cove + brushed brass bedside table lamps with silk shade producing soft ambient glow; refined residential intimacy.",
        # Wave 5.5.27 — REPLACED artwork with bedside rug. User-locked wording
        # drops "cashmere or champagne" hotel-staging semantics.
        # Wave 6.6 (2026-06-04) — extended from 2 to 4 items with secondary
        # emotional visible layer (sculptural ceramic vase + weighted velvet
        # throw at foot of bed). Anti-CGI : "naturally draped with slight
        # asymmetrical fall" replaces clean hotel-staging.
        # Wave 6.7 (2026-06-04) — A+B : assertive anti-staging vocab + 2
        # lived-in items. SL preserve previously rendered as designer/CGI
        # despite Wave 6.6 subtle anchors. Wave 6.7 amplifies anti-hotel
        # directives ("VISIBLY", "PROMINENTLY", "casually draped") + adds
        # concrete personal objects (book, framed photograph on dresser —
        # not above bed) to break the hotel-suite render.
        decor_language=[
            "floor-length cashmere or silk-blend curtains in ivory or cream clearly framing each existing window, drawn open with the glass left fully clear — never covering, narrowing or blocking it, never on a glass partition",
            "the bed is the focal mass — a coverlet or duvet in a clear mid-tone warm neutral (greige, mushroom or warm taupe), distinctly darker than the ivory sheets and the pale walls, a visible value step never near-white, with relaxed natural folds and layered mixed-texture pillows",
            "a large textured wool rug anchoring the bed in a warm neutral deeper than the floor — never pale-on-pale",
            "PROMINENTLY displayed sculptural ceramic vase in cream or champagne on the existing nightstand or dresser",
            "a substantial textured throw in deeper mushroom or taupe at the foot of the existing bed — warmth and contrast",
            "open book or magazine on the existing nightstand",
            "small framed photograph on the existing dresser",
        ],
        realism_constraints=["headboard at correct height — 120–140 cm above mattress", "velvet or cashmere bedding with visible slight imperfections in fabric drape — not hotel-stiff"],
        room_specific_constraints=["layer the bedding across warm neutrals — ivory through oat, greige and mushroom — for tonal hierarchy; the bed reads as the dominant mass, never blending into the walls", "dressing area separated if space allows"],
        visible_transition_logic="marble floor and ivory plaster continue into ensuite; silk soft furnishing palette echoes dressing room",
        negative_rules=["no strong or saturated colours — warm neutrals only, never black, blue, green or burgundy", "no mirrored furniture", "no printed pattern on bedding — woven texture welcome", "no LED strip headboard"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="soft_luxury",
        room_type="kitchen",
        # Wave 6.13b (2026-06-05) — kitchen enrichment (see WM block header).
        # SL target (col 3) : layered premium + refined indirect lighting + subtle
        # stone/marble styling + soft tonal textile + calm luxury. AVOID : gold
        # overload, glamour-Instagram, excessive symmetry — restraint encoded in
        # decor text (negative_rules[:3] only ships, so safety lives in the items).
        furniture_language=["fluted matte-lacquer perimeter cabinetry in warm oat, sand or greige with brushed champagne brass pulls — a clearly warm beige tone, never ivory, white or cream", "a statement island as the kitchen's focal hero mass — a waterfall top in warm honey-beige travertine with visible warm-brown veining and movement, distinctly warmer and deeper than the cabinetry — a clear warmth-and-value step, never white, cream or grey", "flush panel-front appliances in matching warm oat or sand, with a brushed-oak open shelf or niche as the timber accent"],
        material_palette=["fluted matte-lacquer cabinetry in warm oat, sand or greige — never ivory or white", "warm honey-beige travertine island with visible warm-brown veining; perimeter worktop in a warmer beige stone with soft veining, never stark white", "brushed warm champagne brass with brushed-oak accents and warm stone textures"],
        lighting_behavior="Warm concealed under-cabinet lighting grazing the stone + a refined brass pendant cluster over the existing island + a soft ceiling cove for layered ambient glow, with a warm golden daylight balance; calm warm brightness, no harsh spots, never over-bright and never a cool or white cast.",
        decor_language=[
            "a linen Roman shade in warm oat or sand, raised and open at the top — glass fully clear, never covering or blocking it; only where a window exists",
            "a stone mortar with a travertine or oak cutting board styled on the existing counter — tactile and premium",
            "a brushed-oak open shelf with 3-4 artisanal ceramics in warm stone and clay tones — asymmetric, tactile, never cluttered",
            "a linen runner or tea towel in oatmeal, mushroom or flax on the existing counter — a warm textile layer, never pale-on-pale",
            "a sculptural olive branch or lush greenery in a handmade stone or ceramic vessel — living and architectural, never a fussy floral",
            "a stack of 2-3 artisanal ceramic bowls in warm stone or clay tones beside the existing cooktop — curated and tactile",
            "a wooden tray with a few small amber glass bottles on the existing counter — natural texture",
        ],
        realism_constraints=["island at correct working height — 90 cm", "cabinet panels flush with appliances — no exposed appliance handles"],
        # Wave 6.13c (2026-06-05) — kitchen structure-preservation guard at [0] (see WM).
        # SL is the other documented wall-symmetry-leaning atmosphere. Ships [:2].
        room_specific_constraints=["arrange cabinetry and island without covering, narrowing or relocating any existing window, doorway or wall opening — keep photographed openings fully clear", "the island is the hero focal mass — a contrasting warm honey-beige stone, warmer and deeper than the cabinetry; all counters single slabs, no tile"],
        visible_transition_logic="warm stone and oak tones flow to the dining room furniture and table; materials and palette connect softly with the surrounding spaces",
        negative_rules=["no stark white or cool grey — warm neutrals only", "no glossy lacquer or over-polished high-glam look", "no dark cabinetry or black accents", "no industrial fixtures", "no cluttered open shelves", "no stainless steel appliances exposed"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="soft_luxury",
        room_type="bathroom",
        furniture_language=["floating vanity in fluted ivory lacquer with marble top", "freestanding sculptural stone soaking tub", "frameless glass shower with marble surround"],
        material_palette=["book-matched Calacatta or blush marble floor and walls", "ivory lacquer vanity", "brushed champagne brass fixtures"],
        lighting_behavior="Concealed perimeter cove at ceiling + soft warm backlit mirror; no harsh downlights.",
        # Wave 5.5.27 Phase 3b — REPLACED orchid (decorative accent) with
        # mirror (bathroom essential). Mirror is anchored to "existing
        # vanity" (user-locked wording — simpler than "floating vanity",
        # reduces designer-staging semantics + opening simulation risk).
        decor_language=["single warm brass-framed mirror above the existing vanity", "folded cashmere hand towels on brass wall bar"],
        realism_constraints=["freestanding tub with floor waste — no bath panel", "marble wall slabs correctly veined and matched"],
        room_specific_constraints=["single stone throughout — no mixing marble types", "all fixtures in brushed champagne — no chrome"],
        visible_transition_logic="marble floor and ivory vanity palette continue into dressing room; brass fixtures echo through hallway hardware",
        negative_rules=["no coloured grout", "no chrome fixtures", "no patterned tile", "no over-accessorised vanity top"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="soft_luxury",
        room_type="terrace",
        furniture_language=["deep curved outdoor sofa in ivory outdoor bouclé", "honed stone or concrete low table", "linen drape shade or pergola with fabric"],
        material_palette=["large-format honed limestone paving", "ivory outdoor upholstery", "brushed brass or stone accent"],
        lighting_behavior="Warm concealed pergola strip + soft floor lanterns; no functional overhead light.",
        decor_language=["anchored to the existing terrace floor, parapet, garde-corps and any existing shade structure — existing architecture and openings kept exactly; no new walls, no enclosure, no building roof, no floor or deck extension", "large matched ceramic planters with clipped olive or topiary, symmetrically placed, plus refined layered evergreen planting along the perimeter", "a honed stone or concrete low table styled with glass hurricane lanterns and a marble tray with a carafe and glasses", "plush layered ivory and champagne cushions and a soft throw on the sofa", "a refined tonal outdoor rug grounding the seating zone", "where the terrace is large enough, a stone or pale-timber dining table with upholstered or sculptural chairs — never rattan", "a soft linen drape on the pergola or shade structure and elegant lanterns along the floor edge"],
        realism_constraints=["outdoor sofa scaled to terrace area — not oversized", "shade structure at correct clearance height"],
        room_specific_constraints=["Create only the number of functional outdoor zones that naturally fit the available terrace size. Large terraces may include both a lounge and a dining area. Small terraces should prioritize a single well-composed seating area rather than overcrowding the space.", "cushion palette ivory or champagne only"],
        visible_transition_logic="limestone paving echoes interior marble or stone floor visible through glass; ivory upholstery palette echoes interior sofas",
        negative_rules=["no rattan outdoor furniture", "no brightly coloured cushions", "no string lights", "no plastic or resin furniture"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="soft_luxury",
        room_type="facade",
        furniture_language=["smooth render or limestone facade in ivory or cream", "arched or elegant window profiles", "solid oak or brushed brass entrance door"],
        material_palette=["smooth cream or ivory render finish", "natural limestone or travertine cladding strip", "brushed brass door hardware and lanterns"],
        lighting_behavior="Warm uplights at facade base + brushed brass lanterns flanking entrance; soft, not dramatic.",
        # Wave 6.26 (2026-06-06) — facade enrichment, architecture-safe (guard at [0]; see WM).
        decor_language=["keep the building exactly — never add, alter, narrow, extend, or restyle any wall, window, door, roof, cladding or structure; only ground-level planting, a doormat and warm light on the existing entrance", "clipped box or bay topiary flanking entrance", "flush letterbox and hardware in brushed brass", "a stone urn with seasonal flowers beside the existing entrance", "a natural stone doormat at the existing threshold"],
        realism_constraints=["window proportions tall — not wide suburban ratios", "entrance door at correct centred position"],
        room_specific_constraints=["single facade material — render or stone only, not mixed", "entrance canopy or porch if present in classical proportions"],
        visible_transition_logic="cream render flows into boundary wall finish; limestone threshold continues to driveway material",
        negative_rules=["no cold grey render", "no contemporary flat black framing", "no raw concrete", "no mixed material busy facade"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="soft_luxury",
        room_type="dining_room",
        # Wave 6.13 (2026-06-05) — dining_room enrichment (see WM block header).
        # SL target (col 2/3) : refined pendant + noble materials + minimalist
        # table styling + subtle artwork + soothing sophistication. SL has a strong
        # native signature (brass/marble) — enrich with restraint, not volume.
        furniture_language=["oval or round marble-top dining table on brass base", "upholstered dining chairs in ivory velvet", "marble-top sideboard with brass legs"],
        material_palette=["honed marble floor", "ivory plaster or linen-textured walls", "brushed brass lighting and hardware"],
        lighting_behavior="Single large sculptural brushed-brass pendant hung low over the existing table + soft indirect glow washing the ivory walls; warm dimmed evening sophistication, calm and refined.",
        decor_language=[
            "floor-length cashmere or silk-blend curtains in ivory or cream clearly framing each existing window, drawn open with the glass left fully clear — never covering, narrowing or blocking it, never on a glass partition",
            "PROMINENTLY displayed low sculptural floral centrepiece in cream ceramic — soft white blooms, editorial not busy",
            "refined brass column candle holders flanking the centrepiece on the existing table",
            "minimalist place settings on the existing chairs — ivory linen napkin and a single charger per setting, restrained and elegant",
            "single subtle framed artwork above the existing sideboard — tonal abstract or soft photograph in a slim frame, only if that wall is free, else omit",
            "two curated objects styled on the existing sideboard — a sculptural vase and a stacked art book in neutral tones",
            "single white orchid or sculptural stem in cream ceramic on the existing sideboard",
        ],
        realism_constraints=["pendant hung at correct 70–80 cm above table", "chair seat height correct for table — 45–47 cm"],
        room_specific_constraints=["table seats maximum 8 — not hotel-banquet scale", "chairs identical in fabric and form — no mixing"],
        visible_transition_logic="marble floor and ivory plaster echo living room; sideboard palette flows into kitchen visible beyond",
        negative_rules=["no crystal chandelier", "no patterned chair upholstery", "no dark dining table", "no china display cabinet"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="soft_luxury",
        room_type="balcony",
        furniture_language=["two upholstered armchairs in ivory outdoor fabric", "small marble or stone side table", "single sculptural planter"],
        material_palette=["honed limestone balcony floor", "ivory outdoor upholstery", "brushed brass or stone accents"],
        lighting_behavior="Single brass wall lantern; warm intimate tone — no overhead fixture.",
        # Wave 6.26 (2026-06-06) — balcony enrichment (anchoring guard at [0]; see WM).
        decor_language=["anchored to the existing balcony floor, railing and furniture — existing layout kept exactly; no added walls, new structures, roofs or extensions", "ivory outdoor cushions with subtle texture", "single white orchid or sculptural plant in white ceramic", "a marble tray with two cups on the existing side table", "a soft throw layered on the existing armchairs", "a brass lantern on the existing floor", "a soft outdoor rug in ivory grounding the seating on the existing floor"],
        realism_constraints=["chairs sized to balcony — not oversized", "balustrade glass or stone — no metal rail"],
        room_specific_constraints=["two chairs with side table — no dining set on balcony", "single plant accent only"],
        visible_transition_logic="limestone balcony floor echoes interior marble; ivory upholstery palette visible through glass doors",
        negative_rules=["no rattan", "no coloured cushions", "no outdoor dining set", "no decorative lantern overuse"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="soft_luxury",
        room_type="pool_area",
        furniture_language=["wide upholstered sun loungers in ivory outdoor linen", "linen canvas parasols on stone base", "low marble or stone side tables"],
        material_palette=["large-format honed limestone pool deck", "cream stone pool coping", "ivory outdoor upholstery"],
        lighting_behavior="Warm underwater lighting — soft blue-white + warm deck uplights at pool coping.",
        # Wave 6.25 (2026-06-06) — pool enrichment (anchoring guard at [0]; see WM).
        decor_language=["anchored to the existing deck, coping and furniture — existing pool and spatial layout kept exactly; no added walls, new structures, roofs, pergolas or architectural extensions", "symmetrical lounger pairs flanking pool", "refined layered evergreen planting filling the deck perimeter and any open or bare ground — clipped olive and bay, ornamental grasses and large matched ceramic planters, symmetrically massed for elegant landscaped depth", "rolled ivory towels and a marble tray with a carafe and glasses on the existing side table", "plush layered ivory cushions and a soft throw on the existing loungers", "elegant lanterns set along the existing pool coping"],
        realism_constraints=["loungers at correct residential scale — not resort-runway spacing", "pool coping at correct level above deck"],
        room_specific_constraints=["symmetrical layout — not scattered", "parasol at correct height — not too low", "no bare or unplanted ground around the deck — landscape it symmetrically with planting"],
        visible_transition_logic="limestone deck continues to terrace; cream render of house visible as backdrop",
        negative_rules=["no bright-coloured cushions", "no plastic furniture", "no mismatched towel colours"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="soft_luxury",
        room_type="garden",
        furniture_language=["a curved ivory outdoor sofa with a stone low table, plus a stone or pale-timber dining table with upholstered chairs where the garden is large enough — never rattan", "formal clipped hedging structure", "large planted urns flanking the axis"],
        material_palette=["honed limestone or gravel path", "clipped box or yew hedging", "painted iron or stone furniture"],
        lighting_behavior="Concealed ground uplights on hedging structure + warm path lighting; formal and restrained.",
        # Wave 6.26 (2026-06-06) — garden enrichment (anchoring guard at [0]; see WM balcony).
        decor_language=["anchored to the existing paving, beds and garden footprint — existing layout kept exactly; no added walls, new structures, roofs, pergolas or hardscape", "formal garden axis — clear sight line", "large planted urns in stone or lead finish", "a soft cushion and a folded throw on the existing garden bench", "warm uplighting grazing the existing hedging", "stone planters with topiary on the existing paving"],
        realism_constraints=["hedging at correct maintained height — not CGI-perfect", "gravel path at correct depth and boundary edge"],
        room_specific_constraints=["formal symmetry in layout — not naturalistic garden style", "single plant palette — box or yew hedging"],
        visible_transition_logic="garden path continues to terrace; house facade visible as formal backdrop beyond hedging",
        negative_rules=["no naturalistic planting chaos", "no mixed paving materials", "no colourful planting", "no plastic garden accessories"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="soft_luxury",
        room_type="entrance_hall",
        furniture_language=["marble console table with brushed brass legs", "full-height arched mirror in brass frame", "single statement sculptural vase"],
        material_palette=["book-matched marble or large-format stone floor", "ivory fluted plaster finish on existing walls", "brushed brass hardware"],
        lighting_behavior="Concealed ceiling cove + pair of warm wall sconces flanking mirror; arrival warmth.",
        # Wave 6.24 (2026-06-06) — entrance enrichment, surface/floor only (see WM note).
        decor_language=[
            "cashmere or silk-blend curtains in ivory or cream framing the existing window, drawn open with the glass clear — never covering or blocking it, never on a glass partition; only where a window exists",
            "single large floral arrangement in sculptural vessel",
            "single oversized framed artwork at end of hall",
            "a marble or lacquer tray with a small dish on the existing console",
            "a sculptural table lamp on the existing console — soft ambient glow",
            "a soft wool-blend runner in ivory along the floor",
        ],
        realism_constraints=["console at correct 80–85 cm height", "mirror height 150 cm minimum for proportion"],
        # Wave 6.23 (2026-06-06) — entrance opening-preservation guard at [0] (see WM).
        room_specific_constraints=["place the console, mirror and wall decor on an existing solid wall only — never cover, wall over, narrow or replace any existing opening, doorway or passage; if the only free wall is an opening, keep it open and place the console along a solid wall or omit it", "clear view to focal artwork from entrance door", "single console — not paired"],
        visible_transition_logic="marble floor and ivory plaster flow unbroken into living room; brass hardware echoes through all doors",
        negative_rules=["no coat rack visible", "no cluttered side table", "no crystal bowl or ornament collection", "no cold grey stone floor"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="soft_luxury",
        room_type="home_office",
        furniture_language=["large ivory lacquer or leather-wrapped desk", "upholstered chair in ivory cashmere or bouclé", "floor-to-ceiling bookshelf in ivory lacquer"],
        material_palette=["honed marble or oak parquet floor", "ivory plaster or linen-weave wall panelling", "brushed brass desk accessories"],
        lighting_behavior="Brushed brass adjustable desk lamp + concealed bookshelf uplighting; warm amber tone.",
        # Wave 6.14 (2026-06-06) — home_office enrichment (see WM block note).
        # Wave 6.16 (2026-06-06) — full pack (see WM home_office note).
        decor_language=[
            "floor-length cashmere or silk-blend curtains in ivory or cream clearly framing each existing window, drawn open with the glass left fully clear — never covering, narrowing or blocking it, never on a glass partition",
            "a single ivory bouclé lounge chair with a slim marble-topped side table in the open floor area — clear of any window or door, only if floor space allows, else omit",
            "a soft wool-blend rug in ivory spanning the desk and the seating zone",
            "a sculptural brass desk lamp, a closed leather portfolio and a fountain pen set on the existing desk — refined and in use",
            "a curated row of neutral-spined books with a marble bookend on the existing shelf",
            "a single subtle abstract artwork in a slim pale-gold frame on the existing wall — only if that wall is free, else omit",
            "a cream ceramic vessel of dried stems on the side table",
        ],
        realism_constraints=["desk at correct 72–75 cm working height", "bookshelf books at correct scale — not too sparse or too packed"],
        room_specific_constraints=["cable management complete — no visible wires", "single palette for all desk accessories — brass only"],
        visible_transition_logic="ivory palette and marble floor echo hallway and living room; brass accessories match door hardware throughout",
        negative_rules=["no cold grey office tone", "no exposed cables", "no ergonomic rubber chair", "no cluttered desk surface"],
    ),
    RoomAdaptationDNA(
        atmosphere_id="soft_luxury",
        room_type="driveway",
        furniture_language=["limestone or sandstone driveway with formal edging", "rendered gate pillars in cream or ivory", "wrought iron or brass estate gate"],
        material_palette=["honed limestone or fine gravel driveway", "cream smooth render gate pillars", "brushed brass or painted iron gate"],
        lighting_behavior="Warm brass lanterns on gate pillars + warm path uplights along drive edge.",
        # Wave 6.26 (2026-06-06) — driveway enrichment, architecture-safe (guard at [0]; see WM facade).
        decor_language=["keep the drive, gate, pillars and boundary exactly — never add, alter, widen or extend any wall, gate, pillar, structure or paving; only border planting, potted plants and warm light on existing surfaces", "clipped box topiary spheres flanking gate", "formal stone pillar capping in limestone", "matched stone urns with topiary at the existing gate", "warm brass lantern light on the existing pillars"],
        realism_constraints=["driveway at correct width for vehicle — minimum 3.5 m", "gate pillar height proportional to gate width"],
        room_specific_constraints=["single driveway material — no mixing paving types", "gate pillars in same render as house facade"],
        visible_transition_logic="limestone driveway continues to forecourt; cream render facade visible beyond gate",
        negative_rules=["no grey block paving", "no dark render finish", "no suburban gate proportions", "no ornate baroque ironwork"],
    ),
]:
    register(_d)
