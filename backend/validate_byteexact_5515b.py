"""Wave 5.5.15b — Byte-exact prompt diff validator.

After wiring the new emotional_realism signal into composer.py +
composer_v2.py, this script regenerates the same 6 (atm × mode) cells
captured by `capture_baseline_5515b.py` and asserts:

  POST_PROMPT == BASELINE_PROMPT + emotional_realism_sentence + "\n"

If ANY other character differs, the test FAILS with a precise diff.
This catches the failure mode of Wave 5.5.14i where prompts were
assumed byte-identical but empirical bench proved otherwise.

Acceptance:
  - Each of the 6 cells: diff is EXACTLY the new sentence appended,
    plus one separator newline.
  - No other char changes anywhere in the prompt.
  - Chars delta matches len(sentence) + 1.

Run:
    cd backend
    BIMODAL_ENABLED=1 python validate_byteexact_5515b.py
"""

from __future__ import annotations
import hashlib
import json
import os
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from prompt_engine import compose_generation_prompt as v1_compose
from prompt_engine.atmosphere_dna import (
    build_dna_room_context_signal,  # Wave 5.5.18
    get_room_dna,                    # Wave 5.5.18
    label_to_atmosphere_id,
)
from prompt_engine.emotional_realism import build_emotional_realism_signal
# Wave 5.5.16 — renamed from safe_furnishing_intelligence.
from prompt_engine.geometry_attached_furnishing import build_furnishing_signal
from prompt_engine.structural_identity import (
    extract_from_description,
    render_clause,
    render_negative_anchors,
)


_BASELINE_PATH = _HERE / "baseline_5515b.json"
_IDENTITY_DESC = (
    "Living room with wide floor-to-ceiling window dominating the rear "
    "wall and an open kitchen visible on the left, with a glass partition."
)


def _build_prompt(atm: str, mode: str) -> str:
    identity = extract_from_description(_IDENTITY_DESC)
    return v1_compose(
        style_label=atm,
        room_type="living_room",
        room_description=_IDENTITY_DESC,
        user_instruction="",
        iteration=1,
        history=[],
        structural_identity=render_clause(identity, "V1", mode),
        structural_negative_anchors=render_negative_anchors(identity, mode),
        generation_mode=mode,
    )


def _char_diff(baseline: str, post: str) -> str:
    """Return a short diff description if strings differ."""
    if baseline == post:
        return "(identical)"
    # Find first divergence
    for i, (a, b) in enumerate(zip(baseline, post)):
        if a != b:
            ctx_pre = baseline[max(0, i - 30):i]
            ctx_post_a = baseline[i:i + 60]
            ctx_post_b = post[i:i + 60]
            return (
                f"first diff at index {i}: "
                f"before='...{ctx_pre}[{ctx_post_a}]...' "
                f"after ='...{ctx_pre}[{ctx_post_b}]...'"
            )
    return f"length differs: baseline={len(baseline)}, post={len(post)}"


def main() -> int:
    if not os.environ.get("BIMODAL_ENABLED"):
        print("ERROR: BIMODAL_ENABLED not set. Set it to enable the bimodal "
              "path that the emotional realism signal lives on.",
              file=sys.stderr)
        return 1

    if not _BASELINE_PATH.exists():
        print(f"ERROR: baseline not found at {_BASELINE_PATH}. "
              f"Run capture_baseline_5515b.py first.",
              file=sys.stderr)
        return 1

    baseline = json.loads(_BASELINE_PATH.read_text(encoding="utf-8"))

    print("Wave 5.5.15b — Byte-exact diff validation")
    print("=" * 78)
    print(f"Baseline cells: {len(baseline)}")
    print()

    fails: list[str] = []

    for key, entry in baseline.items():
        atm = entry["atmosphere"]
        mode = entry["mode"]
        baseline_prompt = entry["content"]

        post_prompt = _build_prompt(atm, mode)
        # Wave 5.5.15c — emotional realism is per-atmosphere; Wave 5.5.15g
        # adds per-room furnishing (living_room only). Wave 5.5.18 adds
        # dna_room_context (creative-only). Baseline cells all use
        # room_type="living_room" (see _build_prompt above).
        atmosphere_id = label_to_atmosphere_id(atm)
        sig_emotional = build_emotional_realism_signal(mode, atmosphere_id)
        sig_furnishing = build_furnishing_signal(mode, "living_room")
        sig_dna_ctx = build_dna_room_context_signal(
            get_room_dna(atmosphere_id, "living_room"), mode,
        )

        delta_chars = len(post_prompt) - len(baseline_prompt)

        # If ALL signals empty, expected = byte-identical baseline.
        if not sig_emotional and not sig_furnishing and not sig_dna_ctx:
            byte_exact_ok = (post_prompt == baseline_prompt)
            status_size = "OK" if byte_exact_ok else f"FAIL (delta {delta_chars:+d}, expected 0)"
            print(f"  {key:<32s}  [BOTH SIGNALS EMPTY]")
            print(f"    chars baseline={len(baseline_prompt)}, post={len(post_prompt)}, "
                  f"delta={delta_chars:+d}")
            print(f"    byte-identical to baseline: {status_size}")
            if not byte_exact_ok:
                print(f"    detailed diff: {_char_diff(baseline_prompt, post_prompt)}")
                fails.append(f"[{key}] silenced-mode delta != 0")
            print()
            continue

        # Expected delta = sum of (sentence + 1 newline) for each non-empty
        # signal that the composer inserted. Each signal is its own section
        # joined by "\n".
        expected_delta = 0
        if sig_emotional:
            expected_delta += len(sig_emotional) + 1
        if sig_furnishing:
            expected_delta += len(sig_furnishing) + 1
        if sig_dna_ctx:
            expected_delta += len(sig_dna_ctx) + 1

        size_ok = delta_chars == expected_delta

        # Each expected sentence must be present in post and absent in baseline.
        emo_ok = (not sig_emotional) or (
            sig_emotional in post_prompt
            and sig_emotional not in baseline_prompt
        )
        fur_ok = (not sig_furnishing) or (
            sig_furnishing in post_prompt
            and sig_furnishing not in baseline_prompt
        )
        dna_ctx_ok = (not sig_dna_ctx) or (
            sig_dna_ctx in post_prompt
            and sig_dna_ctx not in baseline_prompt
        )

        # Strip all signals + their separator newlines from post; remainder
        # must equal baseline.
        stripped_post = post_prompt
        if sig_emotional:
            stripped_post = stripped_post.replace("\n" + sig_emotional, "", 1)
        if sig_furnishing:
            stripped_post = stripped_post.replace("\n" + sig_furnishing, "", 1)
        if sig_dna_ctx:
            stripped_post = stripped_post.replace("\n" + sig_dna_ctx, "", 1)
        byte_exact_ok = (stripped_post == baseline_prompt)

        status_size = "OK" if size_ok else f"FAIL (got {delta_chars}, expected {expected_delta})"
        status_emo = "OK" if emo_ok else "FAIL"
        status_fur = "OK" if fur_ok else "FAIL"
        status_ctx = "OK" if dna_ctx_ok else "FAIL"
        status_clean_diff = "OK" if byte_exact_ok else "FAIL (other chars changed)"

        print(f"  {key:<32s}")
        print(f"    chars baseline={len(baseline_prompt)}, post={len(post_prompt)}, "
              f"delta={delta_chars:+d}")
        print(f"    emotional_realism  : {len(sig_emotional):3d} chars, present={status_emo}")
        print(f"    geometry_furnish   : {len(sig_furnishing):3d} chars, present={status_fur}")
        print(f"    dna_room_context   : {len(sig_dna_ctx):3d} chars, present={status_ctx}")
        print(f"    combined size delta: {status_size}")
        print(f"    byte-exact (only the signals differ): {status_clean_diff}")
        if not byte_exact_ok:
            print(f"    detailed diff: {_char_diff(baseline_prompt, post_prompt)}")
            fails.append(f"[{key}] byte-exact diff failed")
        if not size_ok or not emo_ok or not fur_ok or not dna_ctx_ok:
            fails.append(f"[{key}] signal presence or size mismatch")
        print()

    print("=" * 78)
    if fails:
        print(f"FAILURES: {len(fails)}")
        for f in fails:
            print(f"  ✗ {f}")
        return 1
    print(f"✓ All {len(baseline)} cells: prompt delta is EXACTLY the emotional realism sentence.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
