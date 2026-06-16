"""SWITCH_REDESIGN_PILOT smoke — REAL active path (composer_v2), runtime.

Run BEFORE the change to capture baselines, then AFTER to compare:
  - V1 prompt hash MUST be byte-identical (flag on/off) — strict V1 freeze.
  - Switch prompt flag-OFF MUST equal baseline (no regression).
  - Switch prompt flag-ON MUST inject hero + redesign directive (pilot fires).
Tests through composer_v2.compose_generation_prompt (the ACTIVE module), with a
history that resolves to REBOOT_FRESH → composer.py FIRST_VISION (Path D).
"""
import hashlib
import os


def _hash(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()[:16]


def _v1_prompt():
    from prompt_engine.composer_v2 import compose_generation_prompt
    from prompt_engine.edit_intent import EditMode
    return compose_generation_prompt(
        style_label="Warm Modern", room_type="Living Room",
        room_description="a living room with a sofa on the left, a window on the right",
        user_instruction="", iteration=1, history=[],
        edit_mode=EditMode.FIRST_VISION,
    )


def _switch_prompt():
    # iteration=2 + a prev-atmosphere history → REBOOT_FRESH switch (Warm Modern → Japandi).
    from prompt_engine.composer_v2 import compose_generation_prompt
    from prompt_engine.edit_intent import EditMode
    return compose_generation_prompt(
        style_label="Japandi Calm", room_type="Living Room",
        room_description="a living room with a sofa on the left, a window on the right",
        user_instruction="Redesign this space in the Japandi Calm style.",
        iteration=2,
        history=[{"role": "user", "content": "Redesign this space in the Warm Modern style."}],
        edit_mode=EditMode.STYLE_REFINEMENT,
    )


def main():
    # V1 with flag OFF and ON — must be identical (V1 never reads the pilot).
    os.environ["SWITCH_REDESIGN_PILOT"] = "0"
    v1_off = _v1_prompt()
    sw_off = _switch_prompt()
    os.environ["SWITCH_REDESIGN_PILOT"] = "1"
    v1_on = _v1_prompt()
    sw_on = _switch_prompt()

    print(f"V1   flag=0  hash={_hash(v1_off)}  chars={len(v1_off)}")
    print(f"V1   flag=1  hash={_hash(v1_on)}  chars={len(v1_on)}")
    print(f"SW   flag=0  hash={_hash(sw_off)}  chars={len(sw_off)}")
    print(f"SW   flag=1  hash={_hash(sw_on)}  chars={len(sw_on)}")
    print(f"CHECK V1 flag on==off (freeze): {v1_on == v1_off}")
    print(f"CHECK SW flag-on has HERO     : {'HERO FURNISHING' in sw_on}")
    print(f"CHECK SW flag-on has REDESIGN : {'REPLACE' in sw_on.upper()}")
    print(f"CHECK SW flag-off no HERO     : {'HERO FURNISHING' not in sw_off}")


if __name__ == "__main__":
    main()
