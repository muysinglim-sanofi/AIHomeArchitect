"""
PR-B Execution Voice — wiring validation for resolve_design_ai_message.

Run:  PYTHONPATH=. python _pr_b_exec_voice_validation.py   (needs backend/.env)

Deterministic, offline (no OpenAI): monkeypatches the exec-voice function, the
designer voice and localize_reply, then drives resolve_design_ai_message
directly. Proves the safety contract of the (always-on) Execution Voice branch:

  • a sentence                        → the exec voice is returned
  • LLM error / None / empty          → pool fallback (voice attempted once)
  • timeout (>2s)                     → pool fallback (asyncio.wait_for hard cap)
  • advice turn (should_generate=False)→ voice NEVER called (only GENERATE turns)

The fallback in every failing case is exactly `localize_reply(fallback_msg)` —
the behavior that shipped before PR-B.
"""
import asyncio
import sys

import main
from prompt_engine.intent_classifier import (
    IntentClassification, ConversationIntent, SubIntent,
)

_calls = {"exec": 0}


async def _fake_localize(client, text, locale, enabled=True):
    return f"POOL::{text}"


def _make_fake_exec(behavior):
    async def fake_exec(client, **kw):
        _calls["exec"] += 1
        if behavior == "line":
            return "Sure — I'll rotate the sofa while keeping the room balanced."
        if behavior == "empty":
            return "   "
        if behavior == "raise":
            raise RuntimeError("simulated LLM error")
        if behavior == "timeout":
            await asyncio.sleep(2.5)  # > 2.0s hard cap → TimeoutError → fallback
            return "late"
        return None  # behavior == "none"
    return fake_exec


async def _run_case(name, *, behavior, should_generate, msg, expect_kind):
    main.generate_execution_voice = _make_fake_exec(behavior)
    main.localize_reply = _fake_localize
    main.designer_voice_enabled = lambda: False  # neutralize the advice LLM
    _calls["exec"] = 0

    intent = ConversationIntent.GENERATE if should_generate else ConversationIntent.CONVERSATION
    ic = IntentClassification(intent=intent, sub_intent=SubIntent.LOCAL_EDIT,
                              confidence=1.0, reasoning="test")
    out = await main.resolve_design_ai_message(
        object(), fallback_msg="FB", message=msg, intent_class=ic,
        should_generate=should_generate, room_type="living room",
        atmosphere_label="Warm Modern", has_vision=True, ui_locale="en",
        normalize_enabled=False, image_url="")

    if expect_kind == "exec":
        ok = out.startswith("Sure —") and _calls["exec"] == 1
    elif expect_kind == "fallback_called":
        ok = out == "POOL::FB" and _calls["exec"] == 1
    else:  # fallback_uncalled
        ok = out == "POOL::FB" and _calls["exec"] == 0
    print(f"  [{'OK ' if ok else 'FAIL'}] {name}: out={out!r} exec_calls={_calls['exec']}")
    return ok


async def _main() -> int:
    r = []
    r.append(await _run_case("sentence → execution voice returned",
        behavior="line", should_generate=True, msg="Rotate the sofa.", expect_kind="exec"))
    r.append(await _run_case("LLM error → fallback",
        behavior="raise", should_generate=True, msg="Rotate the sofa.", expect_kind="fallback_called"))
    r.append(await _run_case("None → fallback",
        behavior="none", should_generate=True, msg="Rotate the sofa.", expect_kind="fallback_called"))
    r.append(await _run_case("empty → fallback",
        behavior="empty", should_generate=True, msg="Rotate the sofa.", expect_kind="fallback_called"))
    r.append(await _run_case("timeout(2.5s) → fallback",
        behavior="timeout", should_generate=True, msg="Rotate the sofa.", expect_kind="fallback_called"))
    r.append(await _run_case("advice turn (should_generate=False) → voice NEVER called",
        behavior="line", should_generate=False, msg="Where should I put the TV?", expect_kind="fallback_uncalled"))
    fails = r.count(False)
    print(f"\n{'ALL GREEN' if not fails else str(fails) + ' FAILURE(S)'}  ({len(r) - fails}/{len(r)})")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(_main()))
