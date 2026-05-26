"""
Dream scene completion layer — Wave 4.2.3.

Ensures generated spaces feel complete, premium, and lived-in.

Two functions:

  build_scene_completion(room_type, atmosphere_id) → str
    ~280–380 char directive combining element checklist + atmosphere
    quality note + dream factor. Used in FIRST_VISION in place of
    build_room_context() when no room DNA is registered.

  build_dream_addendum(atmosphere_id) → str
    ~90–130 char compact aspiration note for STYLE_REFINEMENT.
    Guides the model toward atmosphere-specific richness on an
    existing scene without redesigning it.
"""

# ── Room element checklists ───────────────────────────────────────────────────

_ROOM_ELEMENTS: dict[str, str] = {
    "living room": (
        "sofa grouping, coffee table, area rug, floor or table lamps, "
        "curtains or blinds, TV wall or art focal point, decorative objects, plants"
    ),
    "bedroom": (
        "bed with layered linen and pillows, bedside tables with lamps, "
        "floor-length curtains, soft rug, art above headboard"
    ),
    "kitchen": (
        "countertop styling, pendant lights, quality tap fitting, "
        "integrated appliances, herbs or small plant"
    ),
    "bathroom": (
        "layered towels, bath mat, mirror with flanking light, "
        "plant or greenery, toiletries tastefully arranged"
    ),
    "dining room": (
        "dining table set with placemats, chairs, chandelier or pendant "
        "directly above, sideboard or feature art wall"
    ),
    "home office": (
        "desk lamp, organised shelving, framed art or pinboard, "
        "considered plant, quality ergonomic chair"
    ),
    "balcony": (
        "outdoor seating with cushions, side table, potted plants, "
        "string lights or lantern, outdoor rug"
    ),
    "terrace": (
        "outdoor dining or lounge furniture, layered planting as framing, "
        "lanterns or candles, quality hard-landscaping underfoot"
    ),
    "house facade": (
        "quality entrance door, coherent planting along facade, "
        "path and entry lighting, defined driveway edge"
    ),
    "exterior": (
        "quality entrance, coherent planting, architectural path lighting"
    ),
}

# ── Atmosphere quality descriptors ────────────────────────────────────────────

# Each entry defines what "richness" means for this atmosphere.
# Zen explicitly includes "not dark" because AI defaults to cave-like darkness.
# Japandi includes "never sparse" because AI defaults to empty minimalism.
_ATMOSPHERE_QUALITY: dict[str, str] = {
    "soft_luxury":        "plush, premium, effortlessly elegant — every surface tactile and warm",
    "japandi_calm":       "warm and complete — deeply considered calm, never sparse or cold",
    "tropical_escape":    "lush indoor-outdoor — layered greenery, open, air-filled",
    "warm_modern":        "grounded warmth — architecturally resolved, rich without being heavy",
    "nordic_warmth":      "cosy and layered — hygge warmth, candlelit textiles, not sterile",
    "nature_retreat":     "biophilic calm — raw organic materials, nature brought fully inside",
    "desert_luxe":        "sun-drenched luxury — tactile warmth, terracotta richness, artisan craft",
}

_DEFAULT_QUALITY = "premium, warm, emotionally desirable — lived-in and aspirational"

# Wave 4.7.1 R2 (coherence): dropped "Every zone inhabited" — spatial-completion
# semantics that echoed the removed INTERIOR COMPLETENESS authority on the non-DNA
# path only. Richness is now material/surface/atmosphere, never spatial completion.
_DREAM_FACTOR = (
    "Every surface considered, materially rich and tactile. "
    "Premium and emotionally desirable — warm, lived-in, aspirational."
)

_COMPACT_DREAM = "Warm, lived-in, aspirational."

# Ultra-compact dream micro-layer injected on DNA paths (50-120 chars).
# Used even when room DNA is registered — DNA covers materials/furniture/lighting
# but does not assert the overall luxurious livability of the composition.
_DREAM_MICRO = (
    "Layered lighting, complete furnishing composition, emotionally warm atmosphere."
)


# ── Internal helpers ──────────────────────────────────────────────────────────

def _room_elements(room_type: str) -> str:
    rt = room_type.lower()
    for key, elements in _ROOM_ELEMENTS.items():
        if key in rt:
            return elements
    return ""


# ── Public API ────────────────────────────────────────────────────────────────

def build_scene_completion(room_type: str, atmosphere_id: str) -> str:
    """
    Scene completion directive for FIRST_VISION when no room DNA is
    registered. ~120-170 chars.

    Wave 4.6.0: removed element checklist ("COMPLETE THE SCENE: include sofa
    grouping, coffee table..."). That instruction explicitly overrode uploaded
    furniture composition — contra photo-first philosophy. Replaced with quality
    note only: atmosphere richness standard + dream factor aspiration.
    """
    quality = _ATMOSPHERE_QUALITY.get(atmosphere_id, _DEFAULT_QUALITY)
    return f"QUALITY: {quality}. {_DREAM_FACTOR}"


def build_dream_micro_layer() -> str:
    """
    Ultra-compact dream richness micro-layer (78 chars).
    Added to DNA paths in FIRST_VISION and STYLE_REFINEMENT where the DNA
    block covers materials and furniture but does not assert warm livability.
    Wave 4.2.4.
    """
    return _DREAM_MICRO


def build_dream_addendum(atmosphere_id: str) -> str:
    """
    Compact aspiration note for STYLE_REFINEMENT paths. ~90-130 chars.
    Enriches an existing scene toward the atmosphere quality ideal
    without triggering redesign.
    """
    quality = _ATMOSPHERE_QUALITY.get(atmosphere_id, _DEFAULT_QUALITY)
    return f"DREAM QUALITY: {quality}. {_COMPACT_DREAM}"


# Wave 4.6.2 — Natural Decoration Enrichment.
# ROOT CAUSE: Wave 4.6.1 successfully removed composition authority but some outputs
# became under-decorated (missing TV, minimal accessory layering, sparse hospitality).
# FIX: light natural enrichment signal that allows secondary decor without recomposing.
# STRICT RULE: secondary to architecture. Enriches existing space, never recomposes it.
# No sofa grouping, no furniture arrangement, no composition directives.
#
# Wave 5.4b — trimmed 217 → 132 chars. Removed the example list ("plants,
# floor lamp, cushions, textiles, hospitality accessories, TV if appropriate")
# because the atmosphere DNA already specifies appropriate decor per
# atmosphere (e.g. Bali says "single large stone or clay vessel with tropical
# foliage", Japandi says "single branch in handmade ceramic vase"). Listing
# generic examples here was either redundant with DNA or pushed the model
# toward generic hospitality clichés instead of atmosphere-specific decor.
# KEPT verbatim: the directive frame and the "enrich, do not recompose" rule.
_NATURAL_ENRICHMENT = (
    "NATURAL ENRICHMENT — Enrich the photographed space with light natural "
    "layering. Secondary to architecture — enrich, do not recompose."
)


def build_natural_enrichment() -> str:
    """
    Wave 4.6.2 — Natural decoration richness. ~132 chars (post Wave 5.4b trim).
    Addresses under-decoration observed after Wave 4.6.1 removed composition authority.
    Allows secondary accessory layering without reintroducing composition directives.
    Used in FIRST_VISION Path D at P4 — drops before P3 realism if budget is tight.
    """
    return _NATURAL_ENRICHMENT
