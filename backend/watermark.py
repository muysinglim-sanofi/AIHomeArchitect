"""AYDEN Studio — server-side free-tier watermark (Sprint 1 · Sprint 2A brand).

Applied to the actual image BEFORE the JPEG bytes are uploaded to Supabase
Storage, so the *stored and served* image carries the mark. This is
non-bypassable via the public URL: there is no clean copy anywhere for a
free-tier render.

Premium / admin users (decided by the server-authoritative
`quota.has_admin_role`) receive a CLEAN image — `apply_watermark` is simply
not called for them in main.py.  ← that gating is UNCHANGED by Sprint 2A.

Sprint 2A (brand) : the watermark is now the compact AYDEN **compass mark** in
the bottom corner, low opacity — luxury branding, NOT anti-theft aggression.
The mark is `assets/branding/ayden_compass_gold.png` with a soft shadow so it
reads on light OR dark renders. If the asset is ever missing, we fall back to
the previous text wordmark so a free render is never left unmarked.
"""
from __future__ import annotations

import logging
import os

from PIL import Image, ImageDraw, ImageFont

log = logging.getLogger("watermark")

WATERMARK_TEXT = "AYDEN STUDIO"

# Compact compass mark (bottom corner). Opacity kept in the luxury 0.12-0.18
# band so it stays elegant / almost invisible but still recognisable.
_MARK_PATH = os.path.join(
    os.path.dirname(__file__), "assets", "branding", "ayden_compass_gold.png"
)
_MARK_OPACITY = 0.16
_mark_cache: "Image.Image | None" = None
_mark_loaded = False


def _load_mark() -> "Image.Image | None":
    """Load + cache the compass RGBA once. None if unavailable."""
    global _mark_cache, _mark_loaded
    if _mark_loaded:
        return _mark_cache
    _mark_loaded = True
    try:
        _mark_cache = Image.open(_MARK_PATH).convert("RGBA")
    except Exception as e:  # pragma: no cover - packaging slip
        log.warning("watermark mark asset unavailable (%s) — text fallback", e)
        _mark_cache = None
    return _mark_cache

# Try real TTFs first (crisp), fall back to Pillow's scalable default.
_FONT_CANDIDATES = (
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/Library/Fonts/Arial Bold.ttf",
    "C:/Windows/Fonts/arialbd.ttf",
    "C:/Windows/Fonts/arial.ttf",
)


def _load_font(size: int):
    for path in _FONT_CANDIDATES:
        try:
            return ImageFont.truetype(path, size)
        except Exception:
            continue
    try:
        # Pillow >= 10.1 returns a scalable (FreeType) default at this size.
        return ImageFont.load_default(size=size)
    except TypeError:  # very old Pillow — bitmap default, no size arg
        return ImageFont.load_default()


def _letterspace(text: str, gap: int = 1) -> str:
    """Premium letter-tracking, e.g. 'A Y D E N   S T U D I O'."""
    return (" " * gap).join(list(text))


def apply_watermark(img: "Image.Image") -> "Image.Image":
    """Return a watermarked **RGB** copy of `img`. Input may be any mode.

    Sprint 2A: the compact AYDEN compass mark in the bottom-right corner, low
    opacity, with a faint shadow for legibility. Falls back to the legacy text
    watermark if the asset is unavailable.
    """
    base = img.convert("RGBA")
    w, h = base.size

    mark = _load_mark()
    if mark is None:
        return _apply_text_watermark(base, w, h)

    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    # Compact, proportional to image width.
    target = max(56, w // 9)
    scale = target / max(mark.size)
    m = mark.resize(
        (max(1, int(mark.width * scale)), max(1, int(mark.height * scale))),
        resample=Image.Resampling.LANCZOS,
    )
    src_alpha = m.getchannel("A")
    m.putalpha(src_alpha.point(lambda a: int(a * _MARK_OPACITY)))

    margin = max(14, w // 60)
    px = w - m.width - margin
    py = h - m.height - margin

    # Faint dark shadow (1px offset) so the gold mark reads on light renders.
    shadow_alpha = src_alpha.point(lambda a: int(a * _MARK_OPACITY * 0.7))
    shadow = Image.new("RGBA", m.size, (0, 0, 0, 0))
    shadow.paste((8, 6, 6, 255), (0, 0, m.width, m.height), shadow_alpha)
    overlay.alpha_composite(shadow, (px + 1, py + 1))
    overlay.alpha_composite(m, (px, py))

    return Image.alpha_composite(base, overlay).convert("RGB")


def _apply_text_watermark(base: "Image.Image", w: int, h: int) -> "Image.Image":
    """Legacy text watermark — fallback when the compass asset is missing."""
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))

    # ── 1) Faint diagonal tiling — impossible to crop out completely ────────
    tile_font = _load_font(max(16, w // 40))
    tile_text = _letterspace(WATERMARK_TEXT, 1)
    # Oversized layer so a 30° rotation never leaves empty corners after crop.
    big = Image.new("RGBA", (int(w * 1.6), int(h * 1.6)), (0, 0, 0, 0))
    bd = ImageDraw.Draw(big)
    tb = bd.textbbox((0, 0), tile_text, font=tile_font)
    tw, th = tb[2] - tb[0], tb[3] - tb[1]
    step_x = tw + max(60, w // 8)
    step_y = th + max(80, h // 6)
    row = 0
    for y in range(0, big.height, step_y):
        shift = (step_x // 2) if (row % 2) else 0
        for x in range(-step_x, big.width, step_x):
            bd.text((x + shift, y), tile_text, font=tile_font,
                    fill=(255, 255, 255, 20))  # ~8% — subtle
        row += 1
    big = big.rotate(30, resample=Image.Resampling.BICUBIC, expand=False)
    left, top = (big.width - w) // 2, (big.height - h) // 2
    overlay = Image.alpha_composite(overlay, big.crop((left, top, left + w, top + h)))

    # ── 2) Corner wordmark (bottom-right), embossed for legibility ──────────
    corner_font = _load_font(max(15, w // 46))
    corner_text = _letterspace(WATERMARK_TEXT, 2)
    cd = ImageDraw.Draw(overlay)
    cb = cd.textbbox((0, 0), corner_text, font=corner_font)
    cw, ch = cb[2] - cb[0], cb[3] - cb[1]
    margin = max(14, w // 60)
    px = w - cw - margin - cb[0]
    py = h - ch - margin - cb[1]
    cd.text((px + 1, py + 1), corner_text, font=corner_font, fill=(0, 0, 0, 85))
    cd.text((px, py), corner_text, font=corner_font, fill=(255, 255, 255, 155))

    return Image.alpha_composite(base, overlay).convert("RGB")
