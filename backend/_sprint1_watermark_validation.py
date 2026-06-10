"""Sprint 1 — watermark validation (no OpenAI / no server needed).

Loads a real interior render, applies the free-tier watermark exactly as the
/generate pipeline does (PIL Image in → watermarked RGB out), re-encodes to the
same JPEG q=85, and proves:
  1. the function runs and preserves dimensions + RGB mode,
  2. the watermarked JPEG bytes DIFFER from the clean JPEG bytes (pixels changed
     → a free image is never identical to the clean/premium image),
  3. saves a visual sample to backend/watermark_sample.jpg for eyeball review.
"""
import io
import sys

from PIL import Image

from watermark import apply_watermark

SRC = "../frontend/assets/showcase/villa_after.jpg"
OUT = "watermark_sample.jpg"


def _jpeg(img: Image.Image) -> bytes:
    b = io.BytesIO()
    img.convert("RGB").save(b, format="JPEG", quality=85, optimize=True, progressive=True)
    return b.getvalue()


def main() -> int:
    src = Image.open(SRC)
    w, h = src.size
    print(f"[src] {SRC} {w}x{h} mode={src.mode}")

    clean_bytes = _jpeg(src)                      # premium/admin path (no watermark)
    wm_img = apply_watermark(src)                 # free path
    wm_bytes = _jpeg(wm_img)

    # Save visual proof
    with open(OUT, "wb") as f:
        f.write(wm_bytes)

    checks = []
    checks.append(("dimensions preserved", wm_img.size == (w, h)))
    checks.append(("output is RGB", wm_img.mode == "RGB"))
    checks.append(("watermarked != clean (bytes differ)", wm_bytes != clean_bytes))
    checks.append(("watermarked is a valid JPEG", _reopen_ok(wm_bytes)))
    # sanity: watermark shouldn't bloat the file absurdly
    ratio = len(wm_bytes) / max(len(clean_bytes), 1)
    checks.append(("file size sane (<2x clean)", ratio < 2.0))

    print(f"[clean] {len(clean_bytes)} bytes   [watermarked] {len(wm_bytes)} bytes   ratio={ratio:.2f}x")
    ok = True
    for name, passed in checks:
        print(f"  [{'PASS' if passed else 'FAIL'}] {name}")
        ok = ok and passed
    print(f"\nVisual sample written -> backend/{OUT}")
    print("RESULT:", "ALL PASS" if ok else "FAILURES")
    return 0 if ok else 1


def _reopen_ok(b: bytes) -> bool:
    try:
        Image.open(io.BytesIO(b)).verify()
        return True
    except Exception:
        return False


if __name__ == "__main__":
    sys.exit(main())
