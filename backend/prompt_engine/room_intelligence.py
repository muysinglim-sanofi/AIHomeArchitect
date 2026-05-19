"""
Room intelligence — per-room-type design priorities.

Each room type has different design logic. A bedroom transformation should
prioritise textile richness and calm lighting. A kitchen must address
practicality and circulation. A facade requires exterior-specific vocabulary.

This module produces a compact room-context block that is injected after
the style DNA, giving gpt-image-1 room-specific priorities that prevent
generic interior treatments being applied incorrectly.
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class RoomProfile:
    focal_points: list[str]         # what anchors the composition
    design_priorities: list[str]    # what matters most for this room type
    lighting_zones: list[str]       # key lighting layers
    scale_anchors: list[str]        # elements that establish correct proportion
    quality_markers: list[str]      # what makes this room feel premium


_ROOM_PROFILES: dict[str, RoomProfile] = {
    "living room": RoomProfile(
        focal_points=["feature wall or fireplace", "statement sofa arrangement", "art or architectural backdrop"],
        design_priorities=["conversation grouping logic", "clear circulation paths", "balance of soft and hard surfaces"],
        lighting_zones=["ambient ceiling layer", "accent art or wall wash", "table lamp intimacy layer"],
        scale_anchors=["sofa sized to room width", "coffee table at knee height", "rug defining the zone"],
        quality_markers=["layered textiles on sofa", "coffee table styling", "considered plant placement"],
    ),
    "bedroom": RoomProfile(
        focal_points=["bed headboard as architectural moment", "bedside symmetry", "window orientation"],
        design_priorities=["calm retreat atmosphere", "textile richness at multiple layers", "hotel-quality bed dressing"],
        lighting_zones=["concealed ceiling ambient", "bedside reading warmth", "accent on headboard wall"],
        scale_anchors=["bed sized correctly to wall", "bedside tables at correct height", "ceiling height felt through drapery"],
        quality_markers=["layered bed linen", "bedside lamp quality", "artwork above headboard", "drapery to floor"],
    ),
    "kitchen": RoomProfile(
        focal_points=["island or countertop run", "splashback feature material", "pendant lighting over island"],
        design_priorities=["visual cleanliness", "countertop material quality", "hardware consistency", "under-cabinet lighting"],
        lighting_zones=["recessed ambient ceiling", "under-cabinet task strip", "pendant over island"],
        scale_anchors=["cabinet height to ceiling proportion", "island sized to kitchen", "pendants at 750mm above counter"],
        quality_markers=["seamless stone countertop", "flush integrated appliances", "quality tap fitting", "clear countertops"],
    ),
    "bathroom": RoomProfile(
        focal_points=["freestanding bath or vanity feature wall", "mirror and lighting bar", "material statement"],
        design_priorities=["spa atmosphere", "indirect lighting priority", "material elegance at every surface"],
        lighting_zones=["indirect ceiling ambient", "mirror backlight or vertical flanking", "niche accent"],
        scale_anchors=["vanity sized to wall", "mirror proportioned to vanity", "tile format suited to room size"],
        quality_markers=["polished stone or large-format tile", "freestanding bath if space allows", "wall-mount fixtures", "towel warmth"],
    ),
    "dining room": RoomProfile(
        focal_points=["dining table as centrepiece", "chandelier directly above", "art wall behind host position"],
        design_priorities=["evening atmosphere", "table proportion to room", "lighting drama at table level"],
        lighting_zones=["statement pendant or chandelier over table", "accent on art wall", "sideboard display lighting"],
        scale_anchors=["table length two-thirds of room", "chandelier at 750mm above table surface", "chairs at 450mm seat height"],
        quality_markers=["table styling", "quality seating", "drapery to floor", "art at eye level when seated"],
    ),
    "home office": RoomProfile(
        focal_points=["desk as primary work surface", "bookshelf composition", "view or window as backdrop"],
        design_priorities=["natural light from the side (not behind screen)", "storage organisation", "material quality at desk level"],
        lighting_zones=["natural daylight dominant", "desk task lamp for evening", "shelf accent if present"],
        scale_anchors=["desk proportioned to wall", "chair at correct ergonomic height", "shelving to ceiling"],
        quality_markers=["clean desk surface", "organised shelving", "quality chair", "considered plant"],
    ),
    "house facade": RoomProfile(
        focal_points=["entrance door as arrival moment", "roof line and massing", "planting as framing device"],
        design_priorities=["first impression quality", "material coherence across facade", "lighting at entry", "planting scale"],
        lighting_zones=["entrance uplighting", "path or driveway wash", "feature tree or wall accent"],
        scale_anchors=["door height relative to facade", "window proportion to wall area", "planting scale relative to building"],
        quality_markers=["quality entrance door", "coherent material palette", "considered landscape edges", "evening lighting warmth"],
    ),
    "balcony": RoomProfile(
        focal_points=["view framing", "seating arrangement", "vertical planting or trellis"],
        design_priorities=["outdoor living usability", "plant presence", "weather-appropriate materials"],
        lighting_zones=["ambient string lights or lanterns", "planting accent", "entry threshold"],
        scale_anchors=["furniture scaled to balcony floor area", "railing as safety and visual edge"],
        quality_markers=["quality outdoor furniture", "planting density", "rug or outdoor surface treatment"],
    ),
    "terrace": RoomProfile(
        focal_points=["outdoor dining table", "lounge zone", "garden or landscape beyond"],
        design_priorities=["indoor-outdoor connection quality", "material durability with luxury feel", "landscape as design element"],
        lighting_zones=["overhead ambient", "table candle or lantern warmth", "path lighting"],
        scale_anchors=["furniture proportioned to terrace", "pergola or shade structure if present"],
        quality_markers=["stone or quality decking surface", "outdoor dining quality", "plant framing", "evening lanterns"],
    ),
}

_DEFAULT_PROFILE = RoomProfile(
    focal_points=["primary architectural feature"],
    design_priorities=["material quality", "spatial coherence", "lighting atmosphere"],
    lighting_zones=["ambient layer", "accent layer"],
    scale_anchors=["furniture proportioned to space"],
    quality_markers=["premium materials", "considered composition"],
)


def get_room_profile(room_type: str) -> RoomProfile:
    rt = room_type.lower()
    for key, profile in _ROOM_PROFILES.items():
        if key in rt:
            return profile
    return _DEFAULT_PROFILE


def build_room_context(room_type: str) -> str:
    """
    Generate a concise room-intelligence block for the prompt.
    Focuses on what makes this specific room type feel premium and correct.
    """
    if not room_type:
        return ""

    profile = get_room_profile(room_type)

    focal = ", ".join(profile.focal_points[:2])
    priorities = ", ".join(profile.design_priorities[:3])
    quality = ", ".join(profile.quality_markers[:3])

    return (
        f"ROOM INTELLIGENCE ({room_type}): "
        f"Focal composition: {focal}. "
        f"Design priorities: {priorities}. "
        f"Quality markers that must read clearly: {quality}."
    )
