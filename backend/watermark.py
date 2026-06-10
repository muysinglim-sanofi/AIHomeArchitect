"""AYDEN Studio — server-side free-tier watermark (Sprint 1).

Applied to the actual image BEFORE the JPEG bytes are uploaded to Supabase
Storage, so the *stored and served* image carries the mark. This is
non-bypassable via the public URL: there is no clean copy anywhere for a
free-tier render.

Premium / admin users (decided by the server-authoritative
`quota.has_admin_role`) receive a CLEAN image — `apply_watermark` is simply
not called for them in main.py.

Design goals: premium, subtle, elegant, hard to crop out cleanly, without
destroying the "wow". Text-based ("AYDEN STUDIO") — no external asset needed:
  • a faint diagonal tiling across the whole frame (can't be cropped away), and
  • a single refined corner wordmark (brand presence, legible on light OR dark
    renders thanks to a soft shadow).
"""
from __future__ import annotations

import logging

from PIL import Image, ImageDraw, ImageFont

log = logging.getLogger("watermark")

WATERMARK_TEXT = "AYDEN STUDIO"

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
    """Return a watermarked **RGB** copy of `img`. Input may be any mode."""
    base = img.convert("RGBA")
    w, h = base.size
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
