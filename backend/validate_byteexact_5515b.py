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
from prompt_engine.emotional_realism import build_emotional_realism_signal
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
        expected_sentence = build_emotional_realism_signal(mode)

        delta_chars = len(post_prompt) - len(baseline_prompt)

        # Wave 5.5.15d — preserve mode now returns "" (signal silenced).
        # The expected post-prompt is BYTE-IDENTICAL to baseline.
        if not expected_sentence:
            byte_exact_ok = (post_prompt == baseline_prompt)
            status_size = "OK" if byte_exact_ok else f"FAIL (delta {delta_chars:+d}, expected 0)"
            print(f"  {key:<32s}  [SILENCED]")
            print(f"    chars baseline={len(baseline_prompt)}, post={len(post_prompt)}, "
                  f"delta={delta_chars:+d}")
            print(f"    byte-identical to baseline: {status_size}")
            if not byte_exact_ok:
                print(f"    detailed diff: {_char_diff(baseline_prompt, post_prompt)}")
                fails.append(f"[{key}] silenced-mode delta != 0")
            print()
            continue

        # The signal is inserted into the prompt via composer's section
        # assembly. Sections are joined by "\n" (composer.py) or "\n\n"
        # (composer_v2.py). For V1 path (which is what we're testing here
        # via compose_generation_prompt), composer.py uses single "\n".
        # So the expected delta is "\n" + sentence appended somewhere in
        # the section order. We check by computing the difference set.
        expected_delta = len(expected_sentence) + 1  # +1 for separator newline

        size_ok = delta_chars == expected_delta
        sentence_in_post = expected_sentence in post_prompt
        sentence_not_in_baseline = expected_sentence not in baseline_prompt

        # Check that everything else is byte-identical. We do this by
        # removing the sentence + 1 newline from post and asserting the
        # remainder equals baseline.
        if sentence_in_post:
            # Find the sentence with its surrounding newline and remove
            stripped_post = post_prompt.replace("\n" + expected_sentence, "", 1)
            if stripped_post == baseline_prompt:
                byte_exact_ok = True
            else:
                byte_exact_ok = False
        else:
            byte_exact_ok = False

        status_size = "OK" if size_ok else f"FAIL (got {delta_chars}, expected {expected_delta})"
        status_present = "OK" if sentence_in_post else "FAIL (sentence missing)"
        status_clean_diff = "OK" if byte_exact_ok else "FAIL (other chars changed)"

        print(f"  {key:<32s}")
        print(f"    chars baseline={len(baseline_prompt)}, post={len(post_prompt)}, "
              f"delta={delta_chars:+d}")
        print(f"    sentence delta: {status_size}")
        print(f"    sentence in post: {status_present}")
        print(f"    sentence ABSENT in baseline: "
              f"{'OK' if sentence_not_in_baseline else 'FAIL (was already there)'}")
        print(f"    byte-exact diff (only the sentence): {status_clean_diff}")
        if not byte_exact_ok:
            print(f"    detailed diff: {_char_diff(baseline_prompt, post_prompt)}")
            fails.append(f"[{key}] byte-exact diff failed")
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
