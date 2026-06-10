"""Temporary tool — slice the AYDEN cards composite into individual assets.

Run in two modes:
  python _slice.py overlay   -> draw the estimated grid over the composite for
                                visual calibration (no crops written)
  python _slice.py cut       -> crop each cell's PHOTO region (label band
                                excluded) into rooms/ and atmospheres/

Coordinates are screenshot-space (composite is 1536x1024). Tune GRID then cut.
"""
import sys
from PIL import Image, ImageDraw

SRC = "source/composite.png"  # relative to this folder
W, H = 1536, 1024

# --- ROOMS: 5 columns x 3 rows -------------------------------------------------
ROOM_X0, ROOM_W, ROOM_DX = 20, 286, 302          # left of col0, cell width, col pitch
ROOM_ROWS_Y = [(55, 282), (293, 500), (511, 723)]  # (top,bottom) per row (measured)
ROOM_LABEL_H = 52                                  # bottom band to EXCLUDE from photo

# row0: living kitchen master_bedroom bathroom dining_room
# row1: home_office terrace balcony entrance_hall pool_area
# row2: garden house_facade driveway  (cols 3,4 = AI cards -> skip)
ROOM_NAMES = [
    ["living_room", "kitchen", "master_bedroom", "bathroom", "dining_room"],
    ["home_office", "terrace", "balcony", "entrance_hall", "pool_area"],
    ["garden", "house_facade", "driveway", None, None],
]

# --- ATMOSPHERES: explicit x-spans (measured via dark-gap detection; cards
# have slightly unequal widths in the composite) + a fixed photo y-range that
# stays above the serif title band.
ATMO_Y0, ATMO_Y1 = 772, 902
ATMO_SPANS = [
    ("warm_modern", (24, 276)),
    ("nordic_warmth", (289, 525)),
    ("soft_luxury", (537, 768)),
    ("japandi_calm", (780, 991)),
    ("tropical_escape", (1004, 1207)),
]


def room_boxes():
    for r, row in enumerate(ROOM_NAMES):
        top, bot = ROOM_ROWS_Y[r]
        for c, name in enumerate(row):
            if name is None:
                continue
            x = ROOM_X0 + c * ROOM_DX
            yield name, (x, top, x + ROOM_W, bot), ROOM_LABEL_H


def atmo_boxes():
    for name, (x0, x1) in ATMO_SPANS:
        # label_h = 0: the photo y-range already excludes the title band.
        yield name, (x0, ATMO_Y0, x1, ATMO_Y1), 0


def overlay():
    im = Image.open(SRC).convert("RGB")
    d = ImageDraw.Draw(im)
    for name, (x0, y0, x1, y1), lh in list(room_boxes()) + list(atmo_boxes()):
        d.rectangle([x0, y0, x1, y1], outline=(255, 0, 0), width=2)
        # photo region (label band excluded) in cyan
        d.rectangle([x0, y0, x1, y1 - lh], outline=(0, 255, 255), width=1)
    im.save("source/_overlay.png")
    print("wrote source/_overlay.png")


def cut():
    import os
    im = Image.open(SRC).convert("RGB")
    os.makedirs("rooms", exist_ok=True)
    os.makedirs("atmospheres", exist_ok=True)
    for name, (x0, y0, x1, y1), lh in room_boxes():
        im.crop((x0, y0, x1, y1 - lh)).save(f"rooms/{name}.png")
    for name, (x0, y0, x1, y1), lh in atmo_boxes():
        im.crop((x0, y0, x1, y1 - lh)).save(f"atmospheres/{name}.png")
    print("cut done")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "overlay"
    {"overlay": overlay, "cut": cut}[mode]()
