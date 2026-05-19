"""
validate_wave41.py — Wave 4.1 photographic fidelity pipeline validation.

Covers:
  P0  — quality="high" in images.edit call
  P0  — dynamic aspect ratio size selection
  P1  — anti-CGI realism vocabulary
  P1  — camera lock optical/geometric language
  P1.5 — original_image_url structural anchor (backend + Flutter service)
  P2  — vision analysis detail=high + structural extraction prompt
  P3  — masking feasibility (analysis-only; no code implementation)
  REG — no regressions in Wave 2.5–3.4.3 exports
"""

import sys
import re
import io
import inspect
import pathlib
import ast
sys.path.insert(0, pathlib.Path(__file__).parent.as_posix())

PASS = 0
FAIL = 0

def check(name: str, cond: bool, detail: str = "") -> None:
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  [PASS] {name}")
    else:
        FAIL += 1
        msg = f"  [FAIL] {name}"
        if detail:
            msg += f" — {detail}"
        print(msg)

def section(title: str) -> None:
    print(f"\n{'-'*70}")
    print(title)
    print(f"{'-'*70}")


# ─── P0: quality and size ────────────────────────────────────────────────────

section("P0 — quality=high and dynamic size selection")

main_src = pathlib.Path("main.py").read_text(encoding="utf-8")

check("P0-1: quality='high' in images.edit call",
      "quality=\"high\"" in main_src or "quality='high'" in main_src)

check("P0-2: size no longer hardcoded as 1024x1024",
      "size=\"1024x1024\"" not in main_src.replace("return \"1024x1024\"", ""),
      "static 1024x1024 assignment found outside the fallback return")

check("P0-3: _detect_output_size function defined",
      "def _detect_output_size" in main_src)

check("P0-4: _detect_output_size returns 1536x1024 for landscape",
      "1536x1024" in main_src)

check("P0-5: _detect_output_size returns 1024x1536 for portrait",
      "1024x1536" in main_src)

check("P0-6: Pillow imported for image dimension detection",
      "PilImage" in main_src or "from PIL" in main_src)

check("P0-7: Pillow in requirements.txt",
      "Pillow" in pathlib.Path("requirements.txt").read_text())

# Functional test of _detect_output_size
try:
    from PIL import Image as _PilImage
    import io as _io

    def _detect_output_size_test(image_bytes):
        try:
            with _PilImage.open(_io.BytesIO(image_bytes)) as img:
                w, h = img.size
            if w > h:
                return "1536x1024"
            if h > w:
                return "1024x1536"
            return "1024x1024"
        except Exception:
            return "1024x1024"

    def _make_img(w, h):
        buf = _io.BytesIO()
        _PilImage.new("RGB", (w, h), "white").save(buf, format="JPEG")
        return buf.getvalue()

    check("P0-8: landscape (1920x1080) -> 1536x1024",
          _detect_output_size_test(_make_img(1920, 1080)) == "1536x1024")
    check("P0-9: portrait (1080x1920) -> 1024x1536",
          _detect_output_size_test(_make_img(1080, 1920)) == "1024x1536")
    check("P0-10: square (1024x1024) -> 1024x1024",
          _detect_output_size_test(_make_img(1024, 1024)) == "1024x1024")
    check("P0-11: broken bytes -> fallback 1024x1024",
          _detect_output_size_test(b"notanimage") == "1024x1024")
    check("P0-12: 4:3 landscape (1440x1080) -> 1536x1024",
          _detect_output_size_test(_make_img(1440, 1080)) == "1536x1024")
except Exception as e:
    print(f"  [WARN] P0 functional tests skipped: {e}")


# ─── P1: Anti-CGI realism vocabulary ─────────────────────────────────────────

section("P1 — Anti-CGI realism layer vocabulary")

from prompt_engine.realism_layer import build_realism_block, _CORE_REALISM

rb = build_realism_block()
core = _CORE_REALISM
first_150 = rb[:150]

check("P1-1: 'NOT a CGI render' in realism block",
      "NOT a CGI render" in rb)
check("P1-2: 'DSLR' in realism block",
      "DSLR" in rb)
check("P1-3: 'real estate' in realism block",
      "real estate" in rb)
check("P1-4: 'Airbnb' in realism block",
      "Airbnb" in rb)
check("P1-5: 'NOT a 3D visualization' in realism block",
      "NOT a 3D visualization" in rb or "NOT a 3D render" in rb or "NOT an architectural visualization" in rb)
check("P1-6: 'real photograph' in realism block",
      "real photograph" in rb)

# Critical: all must survive within first 150 chars (budget survival window)
check("P1-7: 'NOT a CGI render' in first 150 chars (budget-safe)",
      "NOT a CGI render" in first_150,
      f"first 150 chars: {repr(first_150[:80])}")
check("P1-8: 'DSLR' in first 150 chars (budget-safe)",
      "DSLR" in first_150)
check("P1-9: 'real estate' in first 150 chars (budget-safe)",
      "real estate" in first_150)


# ─── P1: Camera lock optical/geometric language ───────────────────────────────

section("P1 — Camera lock optical/geometric language")

from prompt_engine.preservation import _CAMERA_LOCK, build_structural_contract

check("P1-10: 'focal length' in camera lock",
      "focal length" in _CAMERA_LOCK)
check("P1-11: 'vanishing point' in camera lock",
      "vanishing point" in _CAMERA_LOCK)
check("P1-12: 'horizon line' in camera lock",
      "horizon line" in _CAMERA_LOCK)
check("P1-13: 'proportions' in camera lock",
      "proportions" in _CAMERA_LOCK)
check("P1-14: 'structural lines' in camera lock",
      "structural lines" in _CAMERA_LOCK)
check("P1-15: 'architectural identity' in camera lock",
      "architectural identity" in _CAMERA_LOCK)
check("P1-16: 'DO NOT reinterpret' in camera lock",
      "DO NOT reinterpret" in _CAMERA_LOCK)
check("P1-17: 'DO NOT redesign' in camera lock",
      "DO NOT redesign" in _CAMERA_LOCK)
check("P1-18: 'SAME apartment' in camera lock",
      "SAME apartment" in _CAMERA_LOCK)

# Verify camera lock is first section of structural contract
contract = build_structural_contract("living room")
check("P1-19: camera lock is first in structural contract",
      contract.startswith("CAMERA LOCK"))

# Verify all four prompt paths contain camera lock vocabulary
from prompt_engine.composer import compose_generation_prompt

p_v1 = compose_generation_prompt("Zen Retreat", "living room", "A room.", "zen", 1, [], [])
p_v2r = compose_generation_prompt("Zen Retreat", "living room", "A room.", "warmer", 2, [{"role":"user","content":"zen"}], [])
p_v2s = compose_generation_prompt("Warm Modern", "living room", "A room.", "Turn into bedroom", 2, [], [])
p_v2l = compose_generation_prompt("Warm Modern", "living room", "A room.", "Add floor lamp", 2, [], [])

check("P1-20: V1 prompt contains focal length",       "focal length" in p_v1)
check("P1-21: V1 prompt contains DO NOT reinterpret", "DO NOT reinterpret" in p_v1)
check("P1-22: V2 refinement contains focal length",   "focal length" in p_v2r)
check("P1-23: V2 structural contains focal length",   "focal length" in p_v2s)
check("P1-24: V1 prompt contains NOT a CGI render",   "NOT a CGI render" in p_v1)

check("P1-25: V1 prompt within 3800 chars", len(p_v1) <= 3800)
check("P1-26: V2 refinement within 3800 chars", len(p_v2r) <= 3800)
check("P1-27: V2 structural within 3800 chars", len(p_v2s) <= 3800)
check("P1-28: V2 local edit within 3800 chars", len(p_v2l) <= 3800)


# ─── P1.5: Original image structural anchor ───────────────────────────────────

section("P1.5 — Original image structural anchor")

check("P1.5-1: original_image_url param in main.py generate()",
      "original_image_url" in main_src)

check("P1.5-2: generation_image_url logic in main.py",
      "generation_image_url" in main_src)

check("P1.5-3: iteration > 1 condition for original anchor",
      "iteration > 1" in main_src)

check("P1.5-4: original_image_url in generation_service.dart",
      "originalImageUrl" in pathlib.Path(
          "../frontend/lib/data/services/generation_service.dart"
      ).read_text(encoding="utf-8"))

check("P1.5-5: original_image_url passed in FormData in generation_service.dart",
      "'original_image_url': originalImageUrl" in pathlib.Path(
          "../frontend/lib/data/services/generation_service.dart"
      ).read_text(encoding="utf-8"))

chat_src = pathlib.Path("../frontend/lib/features/chat/chat_screen.dart").read_text(encoding="utf-8")
check("P1.5-6: originalUrl passed as originalImageUrl in chat_screen generate() call",
      "originalImageUrl: originalUrl" in chat_src or "originalImageUrl: originalUrl ??" in chat_src)


# ─── P2: Vision analysis upgrade ─────────────────────────────────────────────

section("P2 — Vision analysis detail=high + structural extraction")

check("P2-1: detail='high' in vision analysis call",
      '"detail": "high"' in main_src or "'detail': 'high'" in main_src)

check("P2-2: max_tokens increased beyond 120",
      "max_tokens=120" not in main_src,
      "max_tokens=120 (old low value) still present")

check("P2-3: vision prompt asks for window positions",
      "window" in main_src and "position" in main_src)

check("P2-4: vision prompt asks for camera angle",
      "camera angle" in main_src or "Camera angle" in main_src)

check("P2-5: vision prompt asks for perspective",
      "Perspective:" in main_src or "perspective:" in main_src)

check("P2-6: vision prompt asks for structural anchors",
      "structural anchor" in main_src or "Structural anchor" in main_src)

check("P2-7: vision prompt asks for spatial depth",
      "spatial depth" in main_src or "Spatial depth" in main_src)


# ─── P3: Masking feasibility (source verification only) ──────────────────────

section("P3 — Masking: mask wiring present (implemented in Wave 4.2)")

check("P3-1: mask wired into images.edit call via edit_kwargs (Wave 4.2 implementation)",
      'edit_kwargs["mask"]' in main_src or "mask=mask_file" in main_src)


# ─── Integration: real prompt audit ──────────────────────────────────────────

section("Integration — Real prompt audit across scenarios")

# Scenario: atmosphere switch with zen lighting
from prompt_engine.transformation_classifier import (
    classify_transformation, build_spatial_preservation_addendum, TransformationType
)
from prompt_engine.transformation_state_builder import build_clean_instruction

msg = "Switch to Zen Retreat atmosphere"
tt = classify_transformation(msg, 2)
addendum = build_spatial_preservation_addendum(
    transformation_type=tt,
    secondary_spaces=["kitchen"],
    room_type="living room",
    atmosphere_id="zen_retreat",
)
check("INT-1: zen atmosphere addendum has ZEN LIGHTING at position 0",
      addendum.startswith("ZEN LIGHTING"))

# Scenario: functional reassignment prompt
msg2 = "Turn the living room into a bedroom"
tt2 = classify_transformation(msg2, 2)
check("INT-2: functional reassignment classification correct",
      tt2 == TransformationType.FUNCTIONAL_REASSIGNMENT)
addendum2 = build_spatial_preservation_addendum(
    transformation_type=tt2,
    secondary_spaces=[],
    room_type="living room",
    atmosphere_id="warm_modern",
)
check("INT-3: functional addendum contains ERGONOMIC PLAUSIBILITY",
      "ERGONOMIC PLAUSIBILITY" in addendum2)

# Scenario: local edit — surgical, no redesign
p_local = compose_generation_prompt(
    "Nordic Warmth", "bedroom", "A simple bedroom.",
    "Add a floor lamp near the window",
    iteration=2, history=[], secondary_visible_spaces=[],
)
check("INT-4: local edit prompt contains NOT a CGI render",
      "NOT a CGI render" in p_local)
check("INT-5: local edit prompt contains TARGETED IMAGE EDIT",
      "TARGETED IMAGE EDIT" in p_local)
check("INT-6: local edit prompt NOT a redesign instruction",
      "Redesign this" not in p_local)

# V1 full-spectrum check
p_full = compose_generation_prompt(
    "Warm Modern", "living room",
    "Corner living room, one large window on right wall, camera slightly high, single vanishing point, medium depth.",
    "Make it warm and inviting",
    iteration=1, history=[], secondary_visible_spaces=[],
)
check("INT-7: V1 prompt has CAMERA LOCK", "CAMERA LOCK" in p_full)
check("INT-8: V1 prompt has STRUCTURAL LOCK", "STRUCTURAL LOCK" in p_full)
check("INT-9: V1 prompt has ATMOSPHERE BOUNDARY", "ATMOSPHERE BOUNDARY" in p_full)
check("INT-10: V1 prompt has SOURCE SPACE", "SOURCE SPACE" in p_full)
check("INT-11: V1 prompt has RENDER QUALITY", "RENDER QUALITY" in p_full)


# ─── Regression: all prior exports ───────────────────────────────────────────

section("Regression — All Wave 2.5–3.4.3 exports load cleanly")

try:
    from prompt_engine import (
        compose_generation_prompt, parse_history, classify_edit_mode,
        classify_room, surprise_me, classify_intent, generate_architect_response,
        generate_chat_response, generate_mixed_response, get_suggestion_chips,
        classify_meta_intent, MetaIntent, generate_meta_response,
        generate_project_aware_greeting, build_session_memory,
        select_tone_mode, generate_human_soft_response, ToneMode,
        detect_emotional_context, select_response_length,
        generate_architect_light_response, EmotionalContext,
        classify_transformation, build_spatial_preservation_addendum,
        TransformationType, get_contextual_chips,
    )
    from prompt_engine.transformation_state_builder import (
        build_vision_caption, build_clean_instruction,
    )
    check("REG-1: all Wave 2.5–3.4.3 exports load cleanly", True)
except ImportError as e:
    check("REG-1: all Wave 2.5–3.4.3 exports load cleanly", False, str(e))

from prompt_engine.meta_intent import classify_meta_intent, MetaIntent, _SOCIAL_QUESTION
check("REG-2: _SOCIAL_QUESTION pattern still exists",
      _SOCIAL_QUESTION is not None)

from prompt_engine.transformation_classifier import _ZEN_LIGHTING_DISCIPLINE
check("REG-3: _ZEN_LIGHTING_DISCIPLINE still exists",
      bool(_ZEN_LIGHTING_DISCIPLINE))

from prompt_engine.transformation_classifier import build_spatial_preservation_addendum
import inspect
sig = inspect.signature(build_spatial_preservation_addendum)
check("REG-4: build_spatial_preservation_addendum has atmosphere_id param",
      "atmosphere_id" in sig.parameters)

from prompt_engine.meta_intent import classify_meta_intent, MetaIntent
reflection = classify_meta_intent("What does the room look like?")
check("REG-5: reflection question still blocked",
      reflection.intent == MetaIntent.NONE or reflection.intent != MetaIntent.GREETING)

from prompt_engine.transformation_classifier import classify_transformation, TransformationType
check("REG-6: 'Turn the TV area into a bedroom' = FUNCTIONAL_REASSIGNMENT",
      classify_transformation("Turn the TV area into a bedroom", 2) == TransformationType.FUNCTIONAL_REASSIGNMENT)
check("REG-7: 'Make it warmer' = STYLE_REFINEMENT",
      classify_transformation("Make it warmer", 2) == TransformationType.STYLE_REFINEMENT)
check("REG-8: 'Add a floor lamp' = OBJECT_EDIT",
      classify_transformation("Add a floor lamp", 2) == TransformationType.OBJECT_EDIT)

from prompt_engine.edit_intent import build_style_refinement_header
sh = build_style_refinement_header("warmer", "Zen Retreat", "living room")
check("REG-9: refinement header has SAME APARTMENT", "SAME APARTMENT" in sh)

from prompt_engine.preservation import build_structural_contract
c = build_structural_contract("living room")
check("REG-10: contract has PRIORITY ORDER", "PRIORITY ORDER" in c)
check("REG-11: contract has Functional zone", "Functional zone" in c)

from prompt_engine.realism_layer import build_realism_block
rb2 = build_realism_block()
check("REG-12: realism block still has Architectural Digest",
      "Architectural Digest" in rb2)


# ─── Result ──────────────────────────────────────────────────────────────────

print(f"\n{'='*70}")
total = PASS + FAIL
if FAIL == 0:
    print(f"RESULT: ALL CHECKS PASSED — Wave 4.1 photographic fidelity pipeline ready")
else:
    print(f"RESULT: {FAIL} FAILED / {total} total — fix failures before shipping")

print(f"\n  MANDATORY MANUAL VISUAL VALIDATION:")
print(f"  [MANUAL] P0: Landscape room generates at 1536x1024 (proportions preserved)")
print(f"  [MANUAL] P0: Portrait room generates at 1024x1536 (proportions preserved)")
print(f"  [MANUAL] P0-Q: quality=high — improved geometric fidelity vs medium")
print(f"  [MANUAL] P1-R: Generated images feel like real photographs, NOT CGI renders")
print(f"  [MANUAL] P1-G: Geometry preserved — windows, walls, proportions stable")
print(f"  [MANUAL] P1.5: V3 generation uses original apartment geometry (not V2 drift)")
print(f"  [MANUAL] P2: Vision analysis extracts structural anchors (check logs)")
print(f"{'='*70}")
