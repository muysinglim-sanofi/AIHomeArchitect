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


_SID = "OPENINGS: sliding glass door on the left; picture window center; open passage back-right."


def _switch_prompt(target="Japandi Calm", prev="Warm Modern", structural_identity=""):
    # iteration=2 + a prev-atmosphere history → REBOOT_FRESH switch.
    from prompt_engine.composer_v2 import compose_generation_prompt
    from prompt_engine.edit_intent import EditMode
    return compose_generation_prompt(
        style_label=target, room_type="Living Room",
        room_description="a living room with a sofa on the left, a window on the right",
        user_instruction=f"Redesign this space in the {target} style.",
        iteration=2,
        history=[{"role": "user", "content": f"Redesign this space in the {prev} style."}],
        edit_mode=EditMode.STYLE_REFINEMENT,
        structural_identity=structural_identity,
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
    print(f"CHECK V1 freeze (flag on==off, hash==89d61af887d9757c): "
          f"{v1_on == v1_off and _hash(v1_off) == '89d61af887d9757c'}")
    print(f"CHECK SW flag-off baseline (hash==05f0d51dcdddd0c5): "
          f"{_hash(sw_off) == '05f0d51dcdddd0c5'}")
    print(f"CHECK SW flag-on has HERO+REDESIGN: "
          f"{'HERO FURNISHING' in sw_on and 'REPLACE' in sw_on.upper()}")

    # ── A — structural enumeration (openings text-guard) on switch ────────────
    os.environ["SWITCH_REDESIGN_PILOT"] = "1"
    swA_on = _switch_prompt(target="Japandi Calm", prev="Warm Modern", structural_identity=_SID)
    os.environ["SWITCH_REDESIGN_PILOT"] = "0"
    swA_off = _switch_prompt(target="Japandi Calm", prev="Warm Modern", structural_identity=_SID)
    print(f"CHECK A enumeration KEPT on switch (flag on): {'sliding glass door' in swA_on}")
    print(f"CHECK A enumeration DROPPED flag-off (Japandi high-fid trust-pixels): "
          f"{'sliding glass door' not in swA_off}")

    # ── B — WM vs SL hero re-contrast (distinct) ──────────────────────────────
    os.environ["SWITCH_REDESIGN_PILOT"] = "1"
    sw_wm = _switch_prompt(target="Warm Modern", prev="Japandi Calm")
    sw_sl = _switch_prompt(target="Soft Luxury", prev="Japandi Calm")
    print(f"CHECK B WM hero new wording (MODULAR): {'MODULAR' in sw_wm}")
    print(f"CHECK B SL hero new wording (CURVED/tufting): "
          f"{'CURVED' in sw_sl or 'tufting' in sw_sl}")
    print(f"CHECK B WM hero != SL hero (distinct): "
          f"{('MODULAR' in sw_wm) and ('MODULAR' not in sw_sl)}")


if __name__ == "__main__":
    main()
