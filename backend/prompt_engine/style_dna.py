"""
Style DNA — curated design vocabulary for each atmosphere.

Design principle: each style's identity lives as much in what it EXCLUDES
as in what it includes. The `avoid` list is the primary differentiation
mechanism — it prevents the convergence toward "generic warm beige luxury"
that happens when styles share too much vocabulary.

Cross-contamination prevention: `avoid` entries explicitly reference what
other styles contain, so the model understands the vocabulary belongs
elsewhere — e.g. "walnut (Warm Modern material, not Japandi)".

Matching is fuzzy: style_label from Flutter ("Warm Modern · Vision 2")
is scored against every key by word overlap.
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class StyleDNA:
    name: str
    materials: list[str]              # physical surfaces and finishes
    lighting: list[str]               # light quality, source, temperature
    mood: list[str]                   # atmospheric / emotional character
    furniture: list[str]              # furniture form and character
    architectural_elements: list[str] # walls, ceilings, floors, thresholds
    color_palette: list[str]          # specific color language
    composition: list[str]            # spatial and compositional guidance
    avoid: list[str]                  # explicit exclusions — critical for differentiation


_STYLES: dict[str, StyleDNA] = {

    # ── Tropical Escape ───────────────────────────────────────────────────────
    "Tropical Escape": StyleDNA(
        name="Tropical Escape",
        materials=["rattan", "bamboo", "natural teak", "lava stone", "woven grass cloth"],
        lighting=["dappled canopy light through greenery", "warm lantern glow", "open-air luminance", "deep cool shadow pockets"],
        mood=["lush living resort sanctuary", "humid tropical warmth", "barefoot luxury", "alive and sensory-rich with planting"],
        furniture=["low rattan loungers", "woven hanging chairs", "organic teak forms", "tropical daybeds"],
        architectural_elements=["deep roof overhangs", "open timber louvred screens", "indoor-outdoor threshold", "cascading greenery as wall element"],
        color_palette=["deep jungle green", "warm terracotta", "sand ivory", "tropical white", "bamboo gold"],
        composition=[
            "lush tropical greenery occupies at least one-third of the frame as architecture, not decoration",
            "layered depth — foreground plants, midground furniture, background space",
        ],
        avoid=[
            "Balinese carved stone or ceremonial objects (belongs to Bali Sanctuary)",
            "cold industrial steel or concrete dominance",
            "stark minimalism or intentional emptiness",
            "grey or cool Scandinavian palette",
            "polished marble or high-gloss luxury surfaces",
        ],
    ),

    # ── Tropical Modern ───────────────────────────────────────────────────────
    "Tropical Modern": StyleDNA(
        name="Tropical Modern",
        materials=["white concrete", "teak slat screens", "polished lava stone", "frosted glass", "natural linen"],
        lighting=["controlled tropical daylight", "precise recessed warm ambient", "architectural accent"],
        mood=["clean tropical architectural confidence", "resort precision", "contemporary ease without clutter"],
        furniture=["clean-lined teak", "linen upholstered low seating", "architectural side tables"],
        architectural_elements=["louvred timber screens", "cantilevered white volumes", "polished concrete floors", "clean minimal roof line"],
        color_palette=["clean white", "warm teak", "stone grey", "controlled tropical green accent", "matte black"],
        composition=[
            "tropical greenery as controlled architectural punctuation — precise, not dense",
            "strong horizontal planes and shadow lines define the composition",
        ],
        avoid=[
            "overly ornate carved Balinese details",
            "chaotic tropical overplanting or jungle density",
            "rustic imperfection or worn surfaces",
            "warm beige luxury (Warm Modern) aesthetic",
            "woven rattan as dominant material (too casual resort)",
        ],
    ),

    # ── Bali Sanctuary ────────────────────────────────────────────────────────
    "Bali Sanctuary": StyleDNA(
        name="Bali Sanctuary",
        materials=["volcanic andesite stone", "reclaimed teak", "alang-alang thatch", "raw concrete", "bronze"],
        lighting=["stone lanterns on ground plane", "deep tropical shadow play", "low warm candlelight pools", "filtered daylight through thatch ceiling"],
        mood=["sacred ceremonial arrival", "open-air Balinese luxury", "spiritual depth and ancient craft", "timeless handwork"],
        furniture=["carved teak day beds", "stone ceremonial benches", "low teak platforms", "handwoven ceremonial cushions"],
        architectural_elements=["carved stone feature wall with Hindu motif", "thatched pavilion roof", "water channel or reflecting pool", "Pandanus palm gateway"],
        color_palette=["volcanic grey", "deep reclaimed teak", "ceremonial gold", "tropical shadow green", "bone off-white"],
        composition=[
            "carved stone or water element as the centrepiece arrival moment that everything else frames",
            "strong vertical carved stone mass against long horizontal teak plane",
        ],
        avoid=[
            "modern minimalist coldness or glass curtain walls",
            "flat painted wall surfaces",
            "hotel-generic contemporary furniture",
            "rattan casual resort furniture (belongs to Tropical Escape)",
            "Scandinavian or Japanese minimalist influence",
        ],
    ),

    # ── Warm Modern ───────────────────────────────────────────────────────────
    "Warm Modern": StyleDNA(
        name="Warm Modern",
        materials=["American walnut", "white oak", "natural linen", "travertine", "brushed brass", "warm limewash plaster"],
        lighting=[
            "warm 2700K layered ambient with integrated LED coves in ceiling",
            "statement pendant over dining or seating",
            "table lamp warmth creating intimate pools",
            "natural warm morning light from generous windows",
        ],
        mood=["elevated everyday domesticity", "hospitality-quality warmth", "lived-in richness", "unhurried confident comfort"],
        furniture=["floating walnut joinery wall", "curved linen sofa with layered cushions", "low travertine coffee table", "statement upholstered armchair"],
        architectural_elements=["limewash plaster feature wall with visible texture", "integrated flush storage runs", "wide-plank oak floor", "warm timber ceiling detail or batten"],
        color_palette=["warm white", "ochre", "caramel brown", "deep walnut", "brushed brass accent", "stone greige"],
        composition=[
            "material richness layered at three depths — floor treatment, furniture upholstery, ceiling detail",
            "multiple light sources simultaneously visible — pendant, cove, table lamp",
            "curated objects and books on surfaces — this space is richly inhabited",
        ],
        avoid=[
            "pale ash or blonde Japandi timber (too minimal, belongs to Japandi)",
            "cold grey or blue Scandinavian palette",
            "raw unfinished surfaces or visible grain-only materials without finish",
            "floor cushions or Zen low-to-ground seating",
            "Buddhist emptiness or radical negative space",
            "sparse furniture — warmth comes from layered richness, not absence",
            "washi paper or shoji-inspired screens",
        ],
    ),

    # ── Warm Luxury Modern ────────────────────────────────────────────────────
    "Warm Luxury Modern": StyleDNA(
        name="Warm Luxury Modern",
        materials=["bookmatched Calacatta marble", "smoked or blackened walnut", "aged brass hardware", "mohair velvet", "full-grain leather", "lacquer"],
        lighting=["warm 2400K sculptural pendant as architectural statement", "recessed accent wash on bookmatched stone", "evening candlelight warmth"],
        mood=["effortless high-net-worth living", "architecture as personal jewellery", "material depth and sensory richness without ostentation"],
        furniture=["bespoke curved sofa forms in velvet or leather", "marble-topped coffee table", "single statement lounge chair", "brass-framed integrated shelving"],
        architectural_elements=["bookmatched stone feature panel floor-to-ceiling", "coffered or ribbed ceiling", "arched doorway or recess detail", "herringbone or parquet floor"],
        color_palette=["warm ivory", "deep cognac", "aged brass gold", "marble white with warm grey veining", "midnight smoked walnut"],
        composition=[
            "bookmatched stone or marble as the single compositional anchor that commands the room",
            "furniture arrangement oriented for evening conversation around a single focal point",
        ],
        avoid=[
            "mass-market furniture forms visible in any corner",
            "plastic-looking surfaces or uniform sheen",
            "over-lit clinical brightness",
            "generic hotel aesthetic or standardised luxury",
            "Japandi restraint or emptiness",
        ],
    ),

    # ── Hotel Luxury ──────────────────────────────────────────────────────────
    "Hotel Luxury": StyleDNA(
        name="Hotel Luxury",
        materials=["polished Calacatta marble", "satin brass fixtures", "deep-dyed wool carpet", "lacquered wall panels", "silk or heavy cotton drapery"],
        lighting=["warm arrival lighting 2400K maximum", "architectural uplighting on feature wall", "bedside reading warmth", "chandelier as centrepiece fixture"],
        mood=["five-star hospitality arrival experience", "time-suspended institutional luxury", "curated impersonal perfection", "private suite quality"],
        furniture=["deep upholstered headboard architectural in scale", "perfectly symmetrical bedside tables and lamps", "chaise lounge at foot of bed", "luggage bench"],
        architectural_elements=["coffered plaster ceiling", "tall skirting boards and crown moulding", "marble bathroom threshold visible in frame", "full-height drapery"],
        color_palette=["champagne white", "deep charcoal", "satin brass gold", "ivory marble", "midnight navy or deep taupe"],
        composition=[
            "perfect bilateral symmetry — the bed and its surround are a mirror-image composition",
            "every object in frame is deliberate, nothing casual or personal",
        ],
        avoid=[
            "casual residential informality or personal objects",
            "visible clutter of any kind",
            "rustic or raw materials (belongs to Nature Retreat or Desert Luxe)",
            "flat ceilings without architectural detail",
            "cosy Scandinavian or Japandi restraint",
        ],
    ),

    # ── Japandi Calm ─────────────────────────────────────────────────────────
    "Japandi Calm": StyleDNA(
        name="Japandi Calm",
        materials=["pale ash", "white oak", "handmade stoneware ceramic", "raw undyed linen", "matte iron", "washi paper"],
        lighting=[
            "single dominant source of raking natural sidelight from one window",
            "one concealed warm cove glow — no multiple fixture types",
            "washi paper pendant if overhead light is needed",
            "absolutely no recessed spotlights or multiple artificial light layers",
        ],
        mood=[
            "wabi-sabi — beauty found in imperfection and natural process",
            "purposeful restraint and the discipline of subtraction",
            "Buddhist ma — negative space is the design, not an absence of design",
            "dawn calm, slow breathing, still water quality",
        ],
        furniture=[
            "maximum three to four furniture pieces total in frame",
            "low-profile solid oak or ash forms close to floor",
            "absolutely no upholstered curved luxury forms",
        ],
        architectural_elements=["smooth warm plaster walls with no applied detail", "exposed pale timber structural beam if structurally present", "natural stone threshold or sill", "absolutely no wall art on multiple walls"],
        color_palette=["warm white", "pale ash blonde", "undyed linen greige", "soft charcoal", "stoneware natural grey-brown"],
        composition=[
            "radical restraint — at least 50 percent of each visible wall surface is completely bare",
            "a single handmade ceramic or natural object is the only decorative accent in the entire frame",
            "asymmetric composition referencing Japanese ma — the void is as important as the object",
        ],
        avoid=[
            "walnut or dark stained timber (Warm Modern material, fundamentally wrong for Japandi)",
            "brass or gold hardware or accents of any kind (too opulent)",
            "marble or polished stone surfaces (too luxurious)",
            "statement pendant chandeliers or multiple lighting fixtures",
            "maximalist material richness or layered luxury",
            "symmetrical Western interior arrangements",
            "more than four furniture pieces visible in frame",
            "decorative objects on multiple surfaces",
            "wall art on more than one wall",
            "travertine (Warm Modern material)",
            "velvet, leather, or cashmere upholstery",
        ],
    ),

    # ── Zen Retreat ───────────────────────────────────────────────────────────
    "Zen Retreat": StyleDNA(
        name="Zen Retreat",
        materials=["white plaster", "pale oak", "river-washed stone", "washi paper", "undyed linen", "dry sand"],
        lighting=["diffused even natural light — no single point source visible", "concealed minimal warm glow for evening", "absolutely no visible light fixtures in frame"],
        mood=["profound meditative stillness", "intentional emptiness as achievement", "monastery calm", "breath and space as luxury"],
        furniture=["floor cushions only — no raised furniture if possible", "single low timber platform if necessary", "nothing else"],
        architectural_elements=["smooth unadorned plaster walls — zero applied detail", "natural stone or sand element at floor level", "single window as the only light source", "flush minimal door"],
        color_palette=["pure warm white", "stone grey", "pale oak", "soft sage", "natural sand"],
        composition=[
            "extreme negative space — one deliberate object earns its place, everything else is absence",
            "the room itself is the composition — furniture is an intrusion, not an addition",
        ],
        avoid=[
            "any furniture accumulation — maximum two objects in entire frame",
            "decoration of any kind",
            "colour saturation or pattern",
            "multiple light sources or visible fixtures",
            "visual complexity or material richness",
            "Japandi warmth or wooden furniture richness (too comfortable for Zen Retreat)",
            "anything that interrupts the stillness",
        ],
    ),

    # ── Soft Luxury ───────────────────────────────────────────────────────────
    "Soft Luxury": StyleDNA(
        name="Soft Luxury",
        materials=["velvet", "Calacatta marble", "brushed gold", "cashmere throws", "glazed ceramic", "lacquered timber"],
        lighting=["warm 2200K — no cooler", "chandelier or sculptural pendant as centrepiece", "candle-adjacent softness with no visible source points", "absolutely no harsh downlights"],
        mood=["refined evening femininity", "cultivated opulence without aggression", "sensory textile richness", "intimate gathering warmth"],
        furniture=["gathered velvet drapery floor-to-ceiling", "sculptural curved sofa in velvet or silk", "marble-topped curved console", "single statement occasional chair in statement fabric"],
        architectural_elements=["curved plaster arch detail", "ribbed or fluted wall panelling", "high gloss lacquered surface somewhere", "parquet or herringbone floor"],
        color_palette=["champagne", "blush rose", "ivory", "soft warm gold", "deep taupe", "dusty mauve"],
        composition=[
            "curved forms dominate — right angles are rare",
            "layered textile softness at floor, seating, and window creates enveloping warmth",
        ],
        avoid=[
            "hard industrial edges or angular contemporary furniture",
            "cold material surfaces — concrete, steel, raw stone",
            "stark overhead lighting",
            "masculine austerity or architectural severity",
            "Japandi restraint or Zen emptiness",
            "walnut or dark wood dominance (too masculine)",
        ],
    ),

    # ── Nordic Warmth ─────────────────────────────────────────────────────────
    "Nordic Warmth": StyleDNA(
        name="Nordic Warmth",
        materials=["blonde birch", "undyed wool", "sheepskin", "matte chalky white", "raw pine", "hand-thrown ceramics"],
        lighting=["abundant northern natural light as dominant source", "warm candlelight clusters at table level", "hygge evening low glow", "paper pendant warmth"],
        mood=["Scandinavian hygge depth", "democratic honest warmth", "cosy without sentimentality", "still winter morning domestic peace"],
        furniture=["Shaker-inspired timber dining", "sheepskin draped armchair", "birch side table", "sofa layered with woollen throws"],
        architectural_elements=["exposed birch ceiling beam", "painted white plank or stone floor", "wide double-hung windows with deep sill", "candlelit windowsill"],
        color_palette=["pure white", "birch blonde", "warm grey", "dusty powder blue", "amber honey"],
        composition=[
            "candles as primary spatial anchors — clusters of three to seven candles in frame",
            "layered textile planes — throw on sofa, rug on floor, curtain at window — create depth",
        ],
        avoid=[
            "cold Bauhaus austerity or architectural severity",
            "dark tones or low-key moody lighting",
            "hard shiny or polished surfaces",
            "over-styling or excessive curation",
            "Japandi emptiness or Asian influence",
            "tropical or warm-climate materials",
        ],
    ),

    # ── Scandinavian Soft ─────────────────────────────────────────────────────
    "Scandinavian Soft": StyleDNA(
        name="Scandinavian Soft",
        materials=["pale birch", "natural linen", "organic cotton", "washed oak", "matte unglazed ceramics"],
        lighting=["soft even white daylight dominant", "gentle incandescent warmth for evening", "minimal shadow contrast"],
        mood=["gentle democratic simplicity", "functional beauty in everyday life", "clean calm without coldness"],
        furniture=["simple slender-legged timber forms", "loose linen slipcovers", "light and airy pieces that do not dominate the space"],
        architectural_elements=["painted white walls", "light oak or pine floor", "minimal architrave", "abundant glazing bringing sky inside"],
        color_palette=["soft white", "light birch", "dusty rose", "sage green", "sky grey"],
        composition=[
            "abundant breathing room — furniture is light and does not crowd the space",
            "light is the dominant design element — everything serves it",
        ],
        avoid=[
            "heavy dark furniture or dramatic contrast",
            "ornate detail or applied decoration",
            "maximalist layering",
            "busy textile pattern",
            "hygge cosy clutter (belongs to Nordic Warmth)",
            "walnut or dark wood",
        ],
    ),

    # ── Dark Contemporary ─────────────────────────────────────────────────────
    "Dark Contemporary": StyleDNA(
        name="Dark Contemporary",
        materials=["blackened brushed steel", "smoked oak", "raw architectural concrete", "tinted glass", "matte black hardware"],
        lighting=[
            "dramatic recessed architectural accent lighting only",
            "warm amber against darkness — no ambient fill light",
            "concealed uplight on concrete panel",
            "single warm beam as spotlight drama",
        ],
        mood=["bold architectural confidence", "sophisticated editorial precision", "night-time gallery residence", "controlled power"],
        furniture=["sharp geometric upholstered forms in dark fabric", "floating dark timber volumes", "architectural cantilever shelving", "low platform forms"],
        architectural_elements=["raw concrete panel or feature wall", "floating dark joinery mass", "black steel window frame as graphic element", "polished or honed concrete floor"],
        color_palette=["near-black", "warm charcoal", "smoked oak brown", "amber warm accent", "cold white as high contrast"],
        composition=[
            "darkness is the space — objects emerge from shadow rather than being placed against a wall",
            "single warm amber accent light as the compositional focus point",
        ],
        avoid=[
            "beige, cream, or warm neutral dominance (belongs to Warm Modern)",
            "decorative objects or styling items",
            "soft textiles in bulk (cushions, throws)",
            "traditional or classical furniture forms",
            "warm wood tones — smoked oak only, not walnut warmth",
            "any sense of domestic comfort or residential softness",
        ],
    ),

    # ── Dark Modern Luxury ────────────────────────────────────────────────────
    "Dark Modern Luxury": StyleDNA(
        name="Dark Modern Luxury",
        materials=["bookmatched dark Nero Portoro or similar black marble", "burnished bronze", "ebonised walnut", "aged full-grain leather", "deep velvet"],
        lighting=["museum-quality accent lighting on stone surface", "warm bronze ambient glow", "recessed drama with no ambient fill", "no visible light fixture bodies"],
        mood=["nocturnal luxury residence", "gallery-quality private space", "controlled extravagance", "deep material intelligence"],
        furniture=["low deep leather sofa", "ebonised walnut coffee table", "bronze accent table", "bespoke statement credenza in ebonised finish"],
        architectural_elements=["bookmatched black or dark marble wall floor-to-ceiling", "ribbed ebonised walnut panelling", "bronze threshold or inlay detail", "polished dark stone floor"],
        color_palette=["near-black obsidian", "ebonised dark walnut", "burnished bronze", "deep midnight blue velvet", "warm ivory as high contrast only"],
        composition=[
            "darkness is the primary material — objects are revealed by bronze light rather than displayed",
            "bronze light pools anchor the spatial composition in darkness",
        ],
        avoid=[
            "bright cheerful tones of any kind",
            "lightweight casual contemporary furniture",
            "natural unfinished materials",
            "Scandinavian lightness or Japandi restraint",
            "warm beige Warm Modern aesthetic",
            "polished chrome (use bronze only)",
        ],
    ),

    # ── Nature Retreat ────────────────────────────────────────────────────────
    "Nature Retreat": StyleDNA(
        name="Nature Retreat",
        materials=["raw timber slab", "river stone", "bark-textured plaster", "hemp rope", "living moss"],
        lighting=["green-filtered forest light through canopy", "organic candle warmth", "no artificial dominance — natural light rules", "dappled floor light patterns"],
        mood=["biophilic immersion — the boundary between inside and outside is dissolved", "forest floor calm", "nature as the architect, human as guest"],
        furniture=["live-edge timber dining or table", "organic stone bench", "low woven platform", "floor cushions in natural linen"],
        architectural_elements=["living green wall or ceiling greenery mass", "natural stone floor continuing from outside", "water rill or feature", "raw timber structural column or beam"],
        color_palette=["forest green", "bark brown", "river stone grey", "cream", "earthy ochre"],
        composition=[
            "greenery is the primary volume occupying frame — furniture is subordinate to the natural world",
            "vertical plant forms balance horizontal stone planes",
        ],
        avoid=[
            "polished artificial surfaces",
            "hard geometric precision",
            "synthetic materials of any kind",
            "clinical minimalism (belongs to Minimal Contemporary)",
            "urban luxury materials — marble, brass, velvet",
        ],
    ),

    # ── Desert Luxe ───────────────────────────────────────────────────────────
    "Desert Luxe": StyleDNA(
        name="Desert Luxe",
        materials=["adobe plaster", "hand-thrown terracotta", "sun-bleached linen", "hammered copper", "hand-knotted Moroccan or Persian wool"],
        lighting=["golden afternoon desert sunlight as primary source", "warm 2200K lanterns at low level", "deep shadow in niches and recesses", "fire or candle warmth for evening"],
        mood=["ancient artisanal luxury", "slow desert time and tactile material richness", "sun-dried warmth", "handcraft as the highest luxury"],
        furniture=["curved adobe bench or built-in seating", "low sheepskin-draped seating", "handwoven large ottoman", "copper-topped or hammered metal side table"],
        architectural_elements=["curved adobe wall niche with object or candle", "terracotta tile floor", "exposed raw timber lintel over opening", "arched doorway or low arch"],
        color_palette=["warm sand", "terracotta", "burnt sienna", "hammered copper orange", "cream", "desert sage green"],
        composition=[
            "curved forms echo desert erosion — no right angles in furniture or built form",
            "niches and recesses create depth and shadow — they are not just storage, they are architecture",
        ],
        avoid=[
            "sharp right-angle precision (wrong geometry for adobe)",
            "cold modern materials — concrete, steel, glass",
            "Scandinavian lightness or pale palette",
            "polished marble or metallic luxury",
            "tropical greenery or humid atmosphere",
        ],
    ),

    # ── Minimal Contemporary ─────────────────────────────────────────────────
    "Minimal Contemporary": StyleDNA(
        name="Minimal Contemporary",
        materials=["polished concrete", "matte white plaster", "clear tempered glass", "brushed stainless steel", "white oak"],
        lighting=["even diffuse natural light as primary source", "recessed flush ceiling slot lighting — fixtures invisible", "no visible fixture body of any kind"],
        mood=["precise intellectual clarity", "space itself as the luxury", "gallery residence quality", "non-decorative perfection"],
        furniture=["single sculptural sofa form", "handle-free flush joinery throughout", "one architectural coffee table — nothing else"],
        architectural_elements=["seamless plaster wall-to-ceiling junction — no cornice", "flush skirting or no skirting", "floor-to-ceiling glazing or large window", "polished concrete floor"],
        color_palette=["pure white", "light concrete grey", "natural white oak", "single black architectural accent", "glass transparency"],
        composition=[
            "extreme negative space — one perfect object per zone, all other space is intentional void",
            "architectural light slot as the only visible decoration",
        ],
        avoid=[
            "decorative objects of any kind",
            "visible storage or open shelving",
            "textile layering — cushions, throws, rugs",
            "warm coloured finishes",
            "furniture accumulation — one piece per zone maximum",
            "traditional or classical forms",
            "any hint of domestic comfort or warmth",
        ],
    ),
}

_DEFAULT_STYLE = StyleDNA(
    name="Contemporary Interior",
    materials=["natural timber", "linen", "stone", "warm plaster"],
    lighting=["layered warm ambient and natural light"],
    mood=["elevated, considered, spatially generous"],
    furniture=["well-proportioned contemporary pieces"],
    architectural_elements=["quality finishes throughout"],
    color_palette=["warm neutrals with deliberate accent"],
    composition=["balanced spatial composition"],
    avoid=["generic furniture", "flat uniform lighting"],
)


def get_style(style_label: str) -> StyleDNA:
    """
    Return the best-matching StyleDNA for a style_label string.
    style_label may include a vision suffix: "Warm Modern · Vision 2"
    Uses word-overlap scoring so partial matches resolve correctly.
    """
    clean = style_label.split("·")[0].strip().lower()
    words = set(clean.split())

    best_score = 0
    best_match = _DEFAULT_STYLE

    for key, dna in _STYLES.items():
        key_words = set(key.lower().split())
        score = len(words & key_words)
        if score > best_score:
            best_score = score
            best_match = dna

    return best_match
