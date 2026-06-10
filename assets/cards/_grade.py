"""Temporary tool — grade the sliced placeholder cards.

Reads pristine crops from source/raw/{rooms,atmospheres} and writes graded
versions into rooms/ and atmospheres/. Re-runnable (always reads raw), so
grading can be re-tuned without re-slicing.

Grades = global tone/colour only (Pillow). Placeholder-only; final separation
comes with hi-res originals shot to these light signatures.
"""
from PIL import Image, ImageEnhance


def wb(im, rmul, gmul, bmul):
    r, g, b = im.split()
    r = r.point(lambda v: min(255, int(v * rmul)))
    g = g.point(lambda v: min(255, int(v * gmul)))
    b = b.point(lambda v: min(255, int(v * bmul)))
    return Image.merge("RGB", (r, g, b))


def grade(im, bright=1.0, contrast=1.0, color=1.0, rmul=1.0, gmul=1.0, bmul=1.0):
    im = wb(im, rmul, gmul, bmul)
    im = ImageEnhance.Brightness(im).enhance(bright)
    im = ImageEnhance.Contrast(im).enhance(contrast)
    im = ImageEnhance.Color(im).enhance(color)
    return im


# Indoor rooms — neutral / architectural / realistic (kill any warm cast).
INDOOR = ["living_room", "kitchen", "master_bedroom", "bathroom",
          "dining_room", "home_office", "entrance_hall"]
INDOOR_G = dict(bright=1.02, contrast=1.04, color=0.97, rmul=0.98, bmul=1.03)

# Outdoor rooms — natural believable light, not over-cinematic (gentle lift).
OUTDOOR = ["terrace", "balcony", "pool_area", "garden", "house_facade",
           "driveway"]
OUTDOOR_G = dict(bright=1.06, contrast=1.03, color=1.04)

# Atmospheres — distinct light signatures.
ATMO_G = {
    "warm_modern":     dict(bright=1.02, contrast=1.04, color=1.10, rmul=1.09, bmul=0.90),
    "nordic_warmth":   dict(bright=1.06, contrast=1.00, color=1.00, rmul=0.95, bmul=1.11),
    "soft_luxury":     dict(bright=0.80, contrast=1.20, color=1.02, rmul=1.05, bmul=0.97),
    "japandi_calm":    dict(bright=1.07, contrast=0.90, color=0.88, rmul=1.02, bmul=0.99),
    "tropical_escape": dict(bright=1.09, contrast=1.06, color=1.16, rmul=1.03, bmul=1.00),
}


def run():
    for name in INDOOR:
        im = Image.open(f"source/raw/rooms/{name}.png").convert("RGB")
        grade(im, **INDOOR_G).save(f"rooms/{name}.png")
    for name in OUTDOOR:
        im = Image.open(f"source/raw/rooms/{name}.png").convert("RGB")
        grade(im, **OUTDOOR_G).save(f"rooms/{name}.png")
    for name, g in ATMO_G.items():
        im = Image.open(f"source/raw/atmospheres/{name}.png").convert("RGB")
        grade(im, **g).save(f"atmospheres/{name}.png")
    print("graded rooms(13) + atmospheres(5)")


def sheets():
    # atmosphere comparison sheet
    names = list(ATMO_G)
    ims = [Image.open(f"atmospheres/{n}.png").convert("RGB") for n in names]
    h = 150
    sc = [im.resize((int(im.width * h / im.height), h)) for im in ims]
    W = sum(i.width for i in sc) + (len(sc) + 1) * 8
    sheet = Image.new("RGB", (W, h), (10, 10, 10))
    x = 8
    for i in sc:
        sheet.paste(i, (x, 0)); x += i.width + 8
    sheet.save("source/_atmo_graded.png")

    rn = ["living_room", "kitchen", "bathroom", "terrace", "pool_area", "driveway"]
    ims = [Image.open(f"rooms/{n}.png").convert("RGB") for n in rn]
    sc = [im.resize((int(im.width * h / im.height), h)) for im in ims]
    W = sum(i.width for i in sc) + (len(sc) + 1) * 8
    sheet = Image.new("RGB", (W, h), (10, 10, 10))
    x = 8
    for i in sc:
        sheet.paste(i, (x, 0)); x += i.width + 8
    sheet.save("source/_rooms_graded.png")
    print("wrote check sheets")


if __name__ == "__main__":
    run()
    sheets()
