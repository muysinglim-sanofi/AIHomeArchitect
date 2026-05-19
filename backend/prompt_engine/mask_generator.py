"""
Structural preservation mask for gpt-image-1 images.edit.

WAVE 4.4.0 — COMPLETE REWRITE. Root cause of Wave 4.2 RemoteProtocolError fixed.

DIAGNOSIS — Wave 4.2 failure root cause:
  The original build_structural_mask() iterated every pixel in a pure-Python loop
  (nested rows × columns, 1.57M iterations for a 1536×1024 image):
      compute cosine-falloff t for each pixel's distance from perimeter
      pixels[col, row] = int(_PERIMETER_ALPHA * t)

  For PROD images (1536×1024 = 1,572,864 pixels), this loop takes 2-5 seconds in
  CPython. Since main.py calls it synchronously from an async FastAPI route handler,
  it blocks the entire asyncio event loop — causing the client connection to drop
  before the OpenAI HTTP request even begins (RemoteProtocolError: server disconnected).

  Two fixes in Wave 4.4.0:
  1. Pixel loop replaced with PIL draw + GaussianBlur (C-implemented, ~50ms)
  2. Caller (main.py) uses asyncio.run_in_executor so mask generation never blocks
     the event loop even if a slow PIL operation is encountered.

MASK STRATEGY — three protection layers combined with max-protection:

  Layer 1 — Perimeter structural gradient:
    Outer 18% of image (shorter dimension) is protected (alpha up to _PERIMETER_ALPHA).
    Implementation: fill edge rectangles at _PERIMETER_ALPHA, then GaussianBlur
    creates the soft gradient inward. O(edge_perimeter) not O(w×h).
    Protects: walls, window frames near edges, structural columns near room boundaries.

  Layer 2 — Luminosity-based window detection:
    Pixels with luminosity >= _WINDOW_LUMINOSITY_THRESHOLD flagged as bright zones
    (daylight windows, skylights), expanded with MaxFilter, blurred to feather edge.
    Alpha ceiling: _WINDOW_ALPHA. Protects window position and proportion.

  Layer 3 — Edge-density structural detection (NEW — Wave 4.4.0):
    PIL FIND_EDGES detects strong structural lines (walls, glass partitions, door
    frames, opening boundaries). Expanded and blurred for a soft protection zone.
    Alpha ceiling: _EDGE_ALPHA=110 — moderate nudge, not absolute lock.
    Catches interior structural elements that perimeter and luminosity miss.

  Combine: ImageChops.lighter() takes maximum alpha at each pixel, so any layer
    that fires provides protection; no layer can reduce another layer's protection.

  File size guard: skip mask if PNG > _MAX_MASK_BYTES to stay within API limits.
  Maximum PNG compression (compress_level=9) applied before size check.

MASK CONVENTION (OpenAI images.edit API):
  alpha = 0   (transparent) → model edits this region freely
  alpha > 0   (opaque)      → model preserves this region
  Gradient alpha values create soft protection: geometry anchored, minor variation allowed.

RELATIONSHIP TO OTHER PRESERVATION LAYERS:
  This mask works alongside, not instead of:
  - input_fidelity="high" (PROD profile) — global image fidelity signal
  - SAME APARTMENT + spatial truth prompt (Wave 4.3.3) — semantic constraint
  - CAMERA LOCK + STRUCTURAL LOCK contract (preservation.py) — textual prohibitions
  The mask is the per-pixel geometric constraint; prompts + input_fidelity are
  the semantic and global constraints.
"""

from __future__ import annotations

import io
import logging
from typing import Optional

log = logging.getLogger(__name__)

try:
    from PIL import Image, ImageChops, ImageDraw, ImageFilter
    _PIL_AVAILABLE = True
except ImportError:
    _PIL_AVAILABLE = False
    log.warning("Pillow not available — mask generation disabled")


# ── Tuning constants ─────────────────────────────────────────────────────────

# Fraction of image shorter dimension treated as structural perimeter (0.0–0.5)
_PERIMETER_FRACTION = 0.18      # Wave 4.4.0: raised from 0.14 — stronger edge protection

# Alpha values: 0 = fully editable, 255 = fully protected
_PERIMETER_ALPHA = 225          # strong perimeter protection; raised from 210
_WINDOW_ALPHA    = 180          # luminosity-detected window protection; raised from 165
_EDGE_ALPHA      = 110          # structural edge lines — moderate nudge (NEW Wave 4.4.0)

# Luminosity threshold for window detection (0–255; 175 catches bright daylight)
_WINDOW_LUMINOSITY_THRESHOLD = 175

# MaxFilter radius for window expansion
_WINDOW_EXPANSION_RADIUS = 14   # pixels; raised from 12 — wider window protection zone
_WINDOW_BLUR_RADIUS      = 10   # Gaussian blur radius to feather window edges; raised from 8

# Edge detection layer parameters (NEW — Wave 4.4.0)
_EDGE_EXPANSION_RADIUS = 8      # pixels — expand structural edge zones
_EDGE_BLUR_RADIUS      = 14     # wide feather to create a soft protection region

# File size safety limit: skip mask if PNG exceeds this after max compression
# Prevents exceeding OpenAI API per-file size limits on very large source images
_MAX_MASK_BYTES = 3_500_000     # 3.5 MB


# ── Internal layer builders ───────────────────────────────────────────────────

def _build_perimeter_layer(w: int, h: int) -> "Image.Image":
    """
    Layer 1: Outer-edge structural protection.
    Uses PIL rectangle fill + GaussianBlur — O(perimeter) vs O(w×h) pixel loop.
    """
    edge_px = max(2, int(min(w, h) * _PERIMETER_FRACTION))
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    draw.rectangle([0,           0,            w - 1,        edge_px - 1      ], fill=_PERIMETER_ALPHA)  # top
    draw.rectangle([0,           h - edge_px,  w - 1,        h - 1            ], fill=_PERIMETER_ALPHA)  # bottom
    draw.rectangle([0,           edge_px,      edge_px - 1,  h - edge_px - 1  ], fill=_PERIMETER_ALPHA)  # left
    draw.rectangle([w - edge_px, edge_px,      w - 1,        h - edge_px - 1  ], fill=_PERIMETER_ALPHA)  # right
    blur_r = max(4, edge_px // 2)
    mask = mask.filter(ImageFilter.GaussianBlur(blur_r))
    return mask.point(lambda v: min(int(v), _PERIMETER_ALPHA))


def _build_luminosity_layer(gray: "Image.Image") -> "Image.Image":
    """
    Layer 2: Bright-zone (window/skylight) protection.
    High-luminosity pixels = daylight sources = likely window positions to preserve.
    """
    binary = gray.point(lambda v: 255 if v >= _WINDOW_LUMINOSITY_THRESHOLD else 0)
    expanded = binary.filter(ImageFilter.MaxFilter(_WINDOW_EXPANSION_RADIUS * 2 + 1))
    blurred = expanded.filter(ImageFilter.GaussianBlur(_WINDOW_BLUR_RADIUS))
    return blurred.point(lambda v: int(v * _WINDOW_ALPHA / 255))


def _build_edge_layer(gray: "Image.Image") -> "Image.Image":
    """
    Layer 3: Structural line protection via edge-density detection (NEW Wave 4.4.0).
    Catches interior structural elements — glass partitions, load-bearing walls,
    strong opening boundaries — that perimeter and luminosity layers miss.
    Alpha ceiling _EDGE_ALPHA=110: a directional nudge, not absolute geometric lock.
    """
    edges = gray.filter(ImageFilter.FIND_EDGES)
    expanded = edges.filter(ImageFilter.MaxFilter(_EDGE_EXPANSION_RADIUS * 2 + 1))
    blurred = expanded.filter(ImageFilter.GaussianBlur(_EDGE_BLUR_RADIUS))
    return blurred.point(lambda v: int(v * _EDGE_ALPHA / 255))


# ── Public API ────────────────────────────────────────────────────────────────

def build_structural_mask(image_bytes: bytes) -> Optional[bytes]:
    """
    Generate a three-layer structural preservation mask matching the source image size.

    Fast implementation: PIL draw + blur operations (C-level) instead of Python pixel loop.
    Designed to be called via asyncio.run_in_executor in an async context.

    Returns:
        RGBA PNG bytes (alpha channel encodes protection strength) or None on failure.
        None = "no mask" — caller proceeds without structural constraint.
    """
    if not _PIL_AVAILABLE:
        return None

    try:
        with Image.open(io.BytesIO(image_bytes)) as src:
            w, h = src.size
            gray = src.convert("L")

        # Three protection layers
        layer1 = _build_perimeter_layer(w, h)
        layer2 = _build_luminosity_layer(gray)
        layer3 = _build_edge_layer(gray)

        # Max-protection combine: each pixel gets the strongest protection from any layer
        combined = ImageChops.lighter(ImageChops.lighter(layer1, layer2), layer3)

        # Assemble RGBA output (RGB=black, alpha=protection map)
        output = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        output.putalpha(combined)

        # Maximum compression to minimize upload size
        buf = io.BytesIO()
        output.save(buf, format="PNG", compress_level=9)
        mask_out = buf.getvalue()

        # File size safeguard — skip mask if over API limit
        if len(mask_out) > _MAX_MASK_BYTES:
            log.warning(
                "  [Mask] size %d bytes exceeds %d byte limit — skipping mask",
                len(mask_out), _MAX_MASK_BYTES,
            )
            return None

        edge_px = max(2, int(min(w, h) * _PERIMETER_FRACTION))
        log.info(
            "  [Mask] generated %dx%d  %d bytes  perimeter_edge=%dpx  "
            "layers=perimeter+luminosity+edge",
            w, h, len(mask_out), edge_px,
        )
        return mask_out

    except Exception as exc:
        log.warning("  [Mask] generation failed (non-fatal): %s", exc)
        return None
