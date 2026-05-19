"""
Wave 4.2 validation suite — Structural Preservation Architecture.

Covers:
  Suite A — input_fidelity parameter in main.py
  Suite B — mask_generator.py module structure and constants
  Suite C — mask generation correctness (functional PIL test)
  Suite D — mask mode routing in main.py (FIRST_VISION/STYLE_REFINEMENT only)
  Suite E — mask import wiring in main.py
  Suite F — edit_intent EditMode enum completeness
  Suite G — integration: mask_generator import + execution round-trip
  Suite H — regression: Wave 4.1 checks still intact
"""

import ast
import inspect
import io
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

PASS = "\033[92mPASS\033[0m"
FAIL = "\033[91mFAIL\033[0m"

results = []


def check(label: str, condition: bool, detail: str = "") -> None:
    status = PASS if condition else FAIL
    suffix = f"  [{detail}]" if detail and not condition else ""
    print(f"  {status}  {label}{suffix}")
    results.append((label, condition))


# ── Suite A: input_fidelity in main.py ────────────────────────────────────────
print("\n=== Suite A: input_fidelity parameter ===")

with open("main.py", encoding="utf-8") as f:
    main_src = f.read()

check("A1  input_fidelity='high' present in main.py",
      'input_fidelity="high"' in main_src or "input_fidelity='high'" in main_src)
check("A2  input_fidelity appears in images.edit call block",
      "input_fidelity" in main_src and "images.edit" in main_src)
check("A3  quality='high' still present alongside input_fidelity",
      'quality="high"' in main_src or "quality='high'" in main_src)
check("A4  log line references input_fidelity=high",
      "input_fidelity=high" in main_src)


# ── Suite B: mask_generator.py module structure ───────────────────────────────
print("\n=== Suite B: mask_generator.py module structure ===")

mask_path = os.path.join("prompt_engine", "mask_generator.py")
check("B1  mask_generator.py exists",
      os.path.isfile(mask_path))

if os.path.isfile(mask_path):
    with open(mask_path, encoding="utf-8") as f:
        mask_src = f.read()

    check("B2  build_structural_mask function defined",
          "def build_structural_mask(" in mask_src)
    check("B3  _PERIMETER_FRACTION constant defined",
          "_PERIMETER_FRACTION" in mask_src)
    check("B4  _WINDOW_LUMINOSITY_THRESHOLD constant defined",
          "_WINDOW_LUMINOSITY_THRESHOLD" in mask_src)
    check("B5  _PERIMETER_ALPHA constant defined",
          "_PERIMETER_ALPHA" in mask_src)
    check("B6  _WINDOW_ALPHA constant defined",
          "_WINDOW_ALPHA" in mask_src)
    check("B7  ImageChops.lighter used for max-protection combine",
          "ImageChops.lighter" in mask_src)
    check("B8  MaxFilter used for window zone expansion",
          "MaxFilter" in mask_src)
    check("B9  GaussianBlur used for feathering",
          "GaussianBlur" in mask_src)
    check("B10 Returns None on failure (non-fatal fallback)",
          "return None" in mask_src)
    check("B11 Output format is RGBA PNG",
          '"RGBA"' in mask_src and '"PNG"' in mask_src)
    check("B12 Returns Optional[bytes]",
          "Optional[bytes]" in mask_src or "bytes | None" in mask_src)
else:
    for n in range(2, 13):
        check(f"B{n}  (mask_generator.py missing — skipped)", False)


# ── Suite C: mask generation correctness (functional) ────────────────────────
print("\n=== Suite C: mask generation correctness ===")

try:
    from PIL import Image
    _PIL_OK = True
except ImportError:
    _PIL_OK = False
    print("  [SKIP] PIL not available — skipping functional mask tests")

if _PIL_OK:
    from prompt_engine.mask_generator import build_structural_mask

    def _make_test_image(w: int, h: int) -> bytes:
        img = Image.new("RGB", (w, h), (128, 128, 128))
        # Add a bright patch simulating a window (top-right)
        for y in range(20, 80):
            for x in range(w - 80, w - 20):
                img.putpixel((x, y), (240, 240, 240))
        buf = io.BytesIO()
        img.save(buf, format="JPEG")
        return buf.getvalue()

    test_img_bytes = _make_test_image(640, 480)
    mask_result = build_structural_mask(test_img_bytes)

    check("C1  build_structural_mask returns bytes (not None)",
          mask_result is not None)

    if mask_result is not None:
        with Image.open(io.BytesIO(mask_result)) as mask_img:
            mode = mask_img.mode
            mw, mh = mask_img.size
            pixels = list(mask_img.getdata())

        check("C2  Output mode is RGBA",
              mode == "RGBA", f"got {mode}")
        check("C3  Mask dimensions match source image (640x480)",
              (mw, mh) == (640, 480), f"got {mw}x{mh}")

        # Alpha channel extraction
        alphas = [p[3] for p in pixels]
        center_idx = (480 // 2) * 640 + (640 // 2)
        center_alpha = pixels[center_idx][3]
        corner_alpha = pixels[0][3]

        check("C4  Center pixel has low alpha (fully editable interior)",
              center_alpha < 50, f"center_alpha={center_alpha}")
        check("C5  Top-left corner pixel has high alpha (perimeter protected)",
              corner_alpha > 100, f"corner_alpha={corner_alpha}")
        check("C6  Not all pixels have same alpha (gradient exists)",
              len(set(alphas)) > 10)
        check("C7  Max alpha does not exceed 255",
              max(alphas) <= 255)
        check("C8  Min alpha is 0 (interior is fully editable)",
              min(alphas) == 0)

        # Window zone: bright patch at top-right should have elevated alpha
        window_y, window_x = 50, 640 - 50
        window_idx = window_y * 640 + window_x
        window_alpha = pixels[window_idx][3]
        check("C9  Window zone pixel has elevated alpha (window detected or perimeter protected)",
              window_alpha > 50, f"window_alpha={window_alpha}")

    # Edge case: tiny image
    tiny_bytes = _make_test_image(100, 100)
    tiny_result = build_structural_mask(tiny_bytes)
    check("C10 Handles tiny 100x100 image without error",
          tiny_result is not None)

    # Edge case: corrupt bytes
    corrupt_result = build_structural_mask(b"not an image")
    check("C11 Returns None for corrupt input (non-fatal)",
          corrupt_result is None)

    # Edge case: empty bytes
    empty_result = build_structural_mask(b"")
    check("C12 Returns None for empty bytes (non-fatal)",
          empty_result is None)


# ── Suite D: mask mode routing in main.py ─────────────────────────────────────
print("\n=== Suite D: mask mode routing ===")

check("D1  FIRST_VISION in _MASK_MODES",
      "EditMode.FIRST_VISION" in main_src and "_MASK_MODES" in main_src)
check("D2  STYLE_REFINEMENT in _MASK_MODES",
      "EditMode.STYLE_REFINEMENT" in main_src and "_MASK_MODES" in main_src)
check("D3  Mask skipped for STRUCTURAL_TRANSFORMATION (comment or logic)",
      "STRUCTURAL_TRANSFORMATION" in main_src and "mask" in main_src.lower())
check("D4  Mask skipped for LOCAL_EDIT (comment or logic)",
      "LOCAL_EDIT" in main_src and "mask" in main_src.lower())
check("D5  mask_file=None default before conditional block",
      "mask_file = None" in main_src)
check("D6  mask injected via edit_kwargs when present",
      'edit_kwargs["mask"]' in main_src or "mask=mask_file" in main_src)
check("D7  mask_bytes=None default before conditional block",
      "mask_bytes = None" in main_src)
check("D8  build_structural_mask called with image_bytes",
      "build_structural_mask(image_bytes)" in main_src)

# ── Suite D2: feature flag ─────────────────────────────────────────────────────
print("\n=== Suite D2: feature flag ===")

check("D2-1  ENABLE_STRUCTURAL_MASK defined in main.py",
      "ENABLE_STRUCTURAL_MASK" in main_src)
check("D2-2  ENABLE_STRUCTURAL_MASK defaults to false (env-driven)",
      '"false"' in main_src and "ENABLE_STRUCTURAL_MASK" in main_src)
check("D2-3  Mask block guarded by ENABLE_STRUCTURAL_MASK flag",
      "ENABLE_STRUCTURAL_MASK and edit_mode in _MASK_MODES" in main_src or
      "ENABLE_STRUCTURAL_MASK" in main_src.split("_MASK_MODES")[0])
check("D2-4  Log line when mask is disabled",
      "ENABLE_STRUCTURAL_MASK=false" in main_src)
check("D2-5  mask=disabled log appears in call log line",
      'mask=%s' in main_src or '"no"' in main_src)


# ── Suite E: mask import wiring in main.py ────────────────────────────────────
print("\n=== Suite E: import wiring ===")

check("E1  from prompt_engine.mask_generator import build_structural_mask",
      "from prompt_engine.mask_generator import build_structural_mask" in main_src)
check("E2  mask_generator.py is in prompt_engine/ directory",
      os.path.isfile(os.path.join("prompt_engine", "mask_generator.py")))


# ── Suite F: EditMode enum completeness ───────────────────────────────────────
print("\n=== Suite F: EditMode enum ===")

from prompt_engine.edit_intent import EditMode

check("F1  EditMode.FIRST_VISION exists",
      hasattr(EditMode, "FIRST_VISION"))
check("F2  EditMode.STYLE_REFINEMENT exists",
      hasattr(EditMode, "STYLE_REFINEMENT"))
check("F3  EditMode.STRUCTURAL_TRANSFORMATION exists",
      hasattr(EditMode, "STRUCTURAL_TRANSFORMATION"))
check("F4  EditMode.LOCAL_EDIT exists",
      hasattr(EditMode, "LOCAL_EDIT"))


# ── Suite G: integration round-trip ───────────────────────────────────────────
print("\n=== Suite G: integration round-trip ===")

try:
    from prompt_engine.mask_generator import build_structural_mask as _bsm
    check("G1  build_structural_mask importable from prompt_engine.mask_generator", True)
except ImportError as e:
    check("G1  build_structural_mask importable from prompt_engine.mask_generator",
          False, str(e))

if _PIL_OK:
    landscape_bytes = _make_test_image(800, 500)
    portrait_bytes = _make_test_image(500, 800)
    square_bytes = _make_test_image(512, 512)

    lm = build_structural_mask(landscape_bytes)
    pm = build_structural_mask(portrait_bytes)
    sm = build_structural_mask(square_bytes)

    check("G2  Landscape image mask generated",
          lm is not None)
    check("G3  Portrait image mask generated",
          pm is not None)
    check("G4  Square image mask generated",
          sm is not None)

    if lm:
        with Image.open(io.BytesIO(lm)) as mi:
            check("G5  Landscape mask dimensions preserved (800x500)",
                  mi.size == (800, 500), f"got {mi.size}")
    if pm:
        with Image.open(io.BytesIO(pm)) as mi:
            check("G6  Portrait mask dimensions preserved (500x800)",
                  mi.size == (500, 800), f"got {mi.size}")


# ── Suite H: Wave 4.1 regression ──────────────────────────────────────────────
print("\n=== Suite H: Wave 4.1 regression ===")

check("H1  quality='high' still in images.edit call",
      'quality="high"' in main_src or "quality='high'" in main_src)
check("H2  _detect_output_size function defined",
      "_detect_output_size" in main_src)
check("H3  original_image_url Form parameter present",
      "original_image_url" in main_src)
check("H4  generation_image_url logic present (structural anchor)",
      "generation_image_url" in main_src)
check("H5  PilImage imported from PIL",
      "from PIL import Image as PilImage" in main_src)

from prompt_engine.realism_layer import build_realism_block
rb = build_realism_block()
check("H6  NOT a CGI render in first 150 chars of realism block",
      "NOT a CGI render" in rb[:150])
check("H7  DSLR in first 150 chars of realism block",
      "DSLR" in rb[:150])

from prompt_engine.preservation import build_structural_contract
CL = build_structural_contract("living room")
check("H8  CAMERA LOCK present",
      "CAMERA LOCK" in CL)
check("H9  vanishing point in camera lock",
      "vanishing point" in CL.lower())
check("H10 already exists physically in camera lock",
      "already exists physically" in CL.lower() or "real physical space" in CL.lower())

from prompt_engine.mask_generator import build_structural_mask as _bsm2
check("H11 build_structural_mask importable (Wave 4.2 addition)",
      True)

check("H12 input_fidelity wired into images.edit (Wave 4.2 addition)",
      'input_fidelity="high"' in main_src or "input_fidelity='high'" in main_src)
check("H13 edit_kwargs dict pattern used for safe mask injection",
      "edit_kwargs" in main_src)
check("H14 source image dimension logging present",
      "source image:" in main_src or "_src_w" in main_src)


# ── Summary ───────────────────────────────────────────────────────────────────
print()
print("=" * 60)
total = len(results)
passed = sum(1 for _, ok in results if ok)
failed = total - passed
print(f"  TOTAL: {total}   PASSED: {passed}   FAILED: {failed}")
if failed:
    print("\n  FAILING CHECKS:")
    for label, ok in results:
        if not ok:
            print(f"    - {label}")
print("=" * 60)
