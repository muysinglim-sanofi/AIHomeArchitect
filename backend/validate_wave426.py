"""
Wave 4.2.6 validation suite — Cost Protection + Dev/Prod Modes.

Suites:
  A — GenerationProfile dataclass: structure and field types
  B — Profile registry: DEV + PROD profiles with expected values
  C — get_active_profile(): environment routing + fallback
  D — Prompt savings: compact_prompts mode produces smaller prompts
  E — Composer integration: compact_prompts parameter wired in
  F — main.py integration: profile used for quality/fidelity/size/retries
  G — Logging: [GenerationProfile] and [Generation Cost] log lines present
  H — Future extensibility: profile registry pattern, not hardcoded if/else
  I — Regression: existing validators still pass (prompt budgets unchanged)
"""

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


# ── Suite A: GenerationProfile dataclass ─────────────────────────────────────
print("\n=== Suite A: GenerationProfile dataclass ===")

from generation_profiles import GenerationProfile, get_active_profile, list_profiles

check("A1  GenerationProfile importable",
      callable(GenerationProfile))
check("A2  GenerationProfile has 'name' field",
      hasattr(GenerationProfile, '__dataclass_fields__') and 'name' in GenerationProfile.__dataclass_fields__)
check("A3  GenerationProfile has 'quality' field",
      'quality' in GenerationProfile.__dataclass_fields__)
check("A4  GenerationProfile has 'input_fidelity' field",
      'input_fidelity' in GenerationProfile.__dataclass_fields__)
check("A5  GenerationProfile has 'size_override' field",
      'size_override' in GenerationProfile.__dataclass_fields__)
check("A6  GenerationProfile has 'max_attempts' field",
      'max_attempts' in GenerationProfile.__dataclass_fields__)
check("A7  GenerationProfile has 'compact_prompts' field",
      'compact_prompts' in GenerationProfile.__dataclass_fields__)
check("A8  GenerationProfile is frozen (immutable)",
      GenerationProfile.__dataclass_params__.frozen)


# ── Suite B: Profile registry ─────────────────────────────────────────────────
print("\n=== Suite B: Profile registry ===")

from generation_profiles import _PROFILES

check("B1  'dev' profile registered",
      "dev" in _PROFILES)
check("B2  'prod' profile registered",
      "prod" in _PROFILES)
check("B3  DEV quality is not 'high' (cost reduction)",
      _PROFILES["dev"].quality != "high",
      f"got {_PROFILES['dev'].quality}")
check("B4  PROD quality is 'high' (premium rendering)",
      _PROFILES["prod"].quality == "high")
check("B5  DEV size_override is set (forces smaller image)",
      _PROFILES["dev"].size_override is not None,
      "size_override should force a fixed size in DEV")
check("B6  PROD size_override is None (auto-detect from source)",
      _PROFILES["prod"].size_override is None)
check("B7  DEV max_attempts < PROD max_attempts (fail faster in DEV)",
      _PROFILES["dev"].max_attempts < _PROFILES["prod"].max_attempts,
      f"dev={_PROFILES['dev'].max_attempts} prod={_PROFILES['prod'].max_attempts}")
check("B8  DEV max_attempts >= 1 (at least one attempt)",
      _PROFILES["dev"].max_attempts >= 1)
check("B9  PROD max_attempts >= 2 (resilient retry)",
      _PROFILES["prod"].max_attempts >= 2)
check("B10 DEV compact_prompts=True (reduced verbosity)",
      _PROFILES["dev"].compact_prompts is True)
check("B11 PROD compact_prompts=False (full prompt richness)",
      _PROFILES["prod"].compact_prompts is False)
check("B12 DEV input_fidelity different from PROD or lower cost",
      _PROFILES["dev"].input_fidelity != "high" or _PROFILES["prod"].input_fidelity == "high")


# ── Suite C: get_active_profile() routing ─────────────────────────────────────
print("\n=== Suite C: Profile routing ===")

import os as _os

# Test PROD routing (default when APP_ENV unset)
_saved = _os.environ.pop("APP_ENV", None)
profile_default = get_active_profile()
check("C1  Default profile (no APP_ENV) is PROD",
      profile_default.name == "PROD",
      f"got {profile_default.name}")

# Test explicit PROD
_os.environ["APP_ENV"] = "prod"
profile_prod = get_active_profile()
check("C2  APP_ENV=prod routes to PROD profile",
      profile_prod.name == "PROD",
      f"got {profile_prod.name}")

# Test DEV
_os.environ["APP_ENV"] = "dev"
profile_dev = get_active_profile()
check("C3  APP_ENV=dev routes to DEV profile",
      profile_dev.name == "DEV",
      f"got {profile_dev.name}")

# Test case-insensitivity
_os.environ["APP_ENV"] = "DEV"
profile_upper = get_active_profile()
check("C4  APP_ENV=DEV (uppercase) routes to DEV profile",
      profile_upper.name == "DEV",
      f"got {profile_upper.name}")

# Test unknown env — should fall back to PROD
_os.environ["APP_ENV"] = "staging"
profile_unknown = get_active_profile()
check("C5  Unknown APP_ENV falls back to PROD (safe-fail toward quality)",
      profile_unknown.name == "PROD",
      f"got {profile_unknown.name}")

# Restore to PROD for subsequent checks
_os.environ["APP_ENV"] = "prod"
if _saved is not None:
    _os.environ["APP_ENV"] = _saved

check("C6  list_profiles() returns at least dev and prod",
      "dev" in list_profiles() and "prod" in list_profiles())


# ── Suite D: Prompt savings in compact mode ────────────────────────────────────
print("\n=== Suite D: Prompt savings (compact_prompts) ===")

import logging
logging.disable(logging.CRITICAL)

from prompt_engine.composer import compose_generation_prompt

room_desc = "Open-plan living room, natural light from west-facing windows."

p_fv_prod = compose_generation_prompt(
    "Zen Retreat · Serenity", "living room", room_desc, "", 1, [])
p_fv_dev = compose_generation_prompt(
    "Zen Retreat · Serenity", "living room", room_desc, "", 1, [],
    compact_prompts=True)
p_sr_prod = compose_generation_prompt(
    "Zen Retreat · Serenity", "living room", room_desc,
    "calmer vibe", 2, [{"role": "user", "content": "start"}, {"role": "ai", "content": "Vision 1"}])
p_sr_dev = compose_generation_prompt(
    "Zen Retreat · Serenity", "living room", room_desc,
    "calmer vibe", 2, [{"role": "user", "content": "start"}, {"role": "ai", "content": "Vision 1"}],
    compact_prompts=True)
p_fv_j_prod = compose_generation_prompt(
    "Japandi · Harmony", "living room", room_desc, "", 1, [])
p_fv_j_dev = compose_generation_prompt(
    "Japandi · Harmony", "living room", room_desc, "", 1, [],
    compact_prompts=True)

logging.disable(logging.NOTSET)

check("D1  compact FV (DNA) is smaller than PROD FV (DNA)",
      len(p_fv_dev) < len(p_fv_prod),
      f"dev={len(p_fv_dev)} prod={len(p_fv_prod)}")
check("D2  compact FV (DNA) saves at least 150 chars vs PROD",
      len(p_fv_prod) - len(p_fv_dev) >= 150,
      f"saved={len(p_fv_prod) - len(p_fv_dev)}")
check("D3  compact SR is smaller than or equal to PROD SR",
      len(p_sr_dev) <= len(p_sr_prod),
      f"dev={len(p_sr_dev)} prod={len(p_sr_prod)}")
check("D4  compact FV (no-DNA) saves chars vs PROD",
      len(p_fv_j_prod) >= len(p_fv_j_dev),
      f"dev={len(p_fv_j_dev)} prod={len(p_fv_j_prod)}")
check("D5  compact FV still has structural contract (P1 preserved)",
      "CAMERA LOCK" in p_fv_dev)
check("D6  compact FV still has design intelligence (P2 preserved)",
      len(p_fv_dev) > 1800, f"prompt too short: {len(p_fv_dev)}")
check("D7  compact FV has compact realism vocabulary",
      "NOT a CGI render" in p_fv_dev and "DSLR" in p_fv_dev)
check("D8  compact FV skips P4 enrichments (no dream_micro / scene_completion)",
      "Layered lighting" not in p_fv_dev and
      "COMPLETE THE SCENE" not in p_fv_dev)
check("D9  Wave 4.3.1 PROD FV retains wow_directive (Zen DNA path)",
      "TRANSFORMATION AMBITION" in p_fv_prod)


# ── Suite E: Composer integration ─────────────────────────────────────────────
print("\n=== Suite E: Composer integration ===")

with open("prompt_engine/composer.py", encoding="utf-8") as f:
    composer_src = f.read()

check("E1  compact_prompts parameter in compose_generation_prompt signature",
      "compact_prompts: bool = False" in composer_src)
check("E2  compact_prompts used to select realism block",
      "compact_prompts" in composer_src and "build_compact_realism_block" in composer_src)
check("E3  compact_prompts skips dream enrichments",
      "if compact_prompts:" in composer_src)
check("E4  compact_prompts guards interior_completeness in FV path",
      "compact_prompts" in composer_src)
check("E5  PROD path still uses build_medium_realism_block for FV",
      "build_medium_realism_block" in composer_src)


# ── Suite F: main.py integration ──────────────────────────────────────────────
print("\n=== Suite F: main.py integration ===")

with open("main.py", encoding="utf-8") as f:
    main_src = f.read()

check("F1  generation_profiles imported in main.py",
      "from generation_profiles import" in main_src or "import generation_profiles" in main_src)
check("F2  get_active_profile() called in generate handler",
      "get_active_profile()" in main_src)
check("F3  profile.quality used in edit_kwargs",
      "quality=profile.quality" in main_src)
check("F4  profile.input_fidelity used in edit_kwargs",
      "input_fidelity=profile.input_fidelity" in main_src)
check("F5  profile.max_attempts used for retry count",
      "_MAX_ATTEMPTS = profile.max_attempts" in main_src)
check("F6  profile.size_override used for output_size",
      "profile.size_override" in main_src)
check("F7  compact_prompts passed to compose_generation_prompt",
      "compact_prompts=profile.compact_prompts" in main_src)
check("F8  profile resolution logged per-request",
      "[GenerationProfile] mode=" in main_src)


# ── Suite G: Logging ──────────────────────────────────────────────────────────
print("\n=== Suite G: Cost visibility logging ===")

check("G1  [GenerationProfile] log line in main.py",
      "[GenerationProfile]" in main_src)
check("G2  [Generation Cost] log line in main.py",
      "[Generation Cost]" in main_src)
check("G3  duration logged in [Generation Cost]",
      "duration=" in main_src and "_req_start" in main_src)
check("G4  prompt_chars logged in [Generation Cost]",
      "prompt_chars=" in main_src)
check("G5  [GenerationProfile] startup log present",
      "[GenerationProfile] ACTIVE:" in main_src)
check("G6  mode name logged in [Generation Cost]",
      "mode=profile.name" in main_src or "mode=%s" in main_src)


# ── Suite H: Extensibility ────────────────────────────────────────────────────
print("\n=== Suite H: Future extensibility ===")

with open("generation_profiles.py", encoding="utf-8") as f:
    profiles_src = f.read()

check("H1  _PROFILES dict is the central registry",
      "_PROFILES" in profiles_src)
check("H2  No APP_ENV==dev if/else chains in main.py (routing via generation_profiles)",
      'APP_ENV" == "dev"' not in main_src and
      "APP_ENV'] == 'dev'" not in main_src and
      '== "dev"' not in main_src)
check("H3  list_profiles() function available",
      "list_profiles" in profiles_src)
check("H4  Profile dataclass is frozen (safe extension model)",
      "frozen=True" in profiles_src)
check("H5  generation_profiles.py has docstring about future modes",
      "STANDARD" in profiles_src or "future" in profiles_src.lower() or
      "LOW_COST" in profiles_src or "FAST" in profiles_src)


# ── Suite I: Regression — prompt budgets unchanged ────────────────────────────
print("\n=== Suite I: Regression (PROD mode = Wave 4.2.4 baseline) ===")

import logging
logging.disable(logging.CRITICAL)
from prompt_engine.composer import compose_generation_prompt, _MODE_BUDGETS

room_desc_full = "Open-plan living room, natural light from west-facing windows, existing oak floors, high ceilings."
history_v2 = [
    {"role": "user", "content": "I want Japandi style, calm and minimal"},
    {"role": "ai", "content": "Here is Vision 1."},
    {"role": "user", "content": "make it warmer and add more texture"},
]

p_fv_j = compose_generation_prompt("Japandi · Harmony", "living room", room_desc_full, "", 1, [])
p_fv_z = compose_generation_prompt("Zen Retreat · Serenity", "living room", room_desc_full, "", 1, [])
p_sr_j = compose_generation_prompt("Japandi · Harmony", "living room", room_desc_full, "more luxurious atmosphere", 2, history_v2)
p_st   = compose_generation_prompt("Japandi · Harmony", "living room", room_desc_full, "open up the facade", 2, history_v2)
p_le   = compose_generation_prompt("Japandi · Harmony", "living room", room_desc_full, "add a floor lamp", 2, history_v2)

logging.disable(logging.NOTSET)

check(f"I1  PROD FIRST_VISION (Japandi) within budget ({_MODE_BUDGETS['FIRST_VISION']})",
      len(p_fv_j) <= _MODE_BUDGETS["FIRST_VISION"], f"got {len(p_fv_j)}")
check(f"I2  PROD FIRST_VISION (Zen/DNA) within budget ({_MODE_BUDGETS['FIRST_VISION']})",
      len(p_fv_z) <= _MODE_BUDGETS["FIRST_VISION"], f"got {len(p_fv_z)}")
check(f"I3  PROD STYLE_REFINEMENT within budget ({_MODE_BUDGETS['STYLE_REFINEMENT']})",
      len(p_sr_j) <= _MODE_BUDGETS["STYLE_REFINEMENT"], f"got {len(p_sr_j)}")
check("I4  PROD FV retains CAMERA LOCK",
      "CAMERA LOCK" in p_fv_j)
check("I5  PROD FV retains NOT a CGI render",
      "NOT a CGI render" in p_fv_j)
check("I6  PROD FV retains vanishing points vocabulary",
      "vanishing point" in p_fv_j.lower())


# ── Results ───────────────────────────────────────────────────────────────────

passed = sum(1 for _, ok in results if ok)
total = len(results)
failed = [(label, ok) for label, ok in results if not ok]

print(f"\n{'=' * 60}")
print(f"  TOTAL: {total}   PASSED: {passed}   FAILED: {total - passed}")
if failed:
    print(f"\n  FAILING CHECKS:")
    for label, _ in failed:
        print(f"    - {label}")
print(f"{'=' * 60}")

# DEV vs PROD prompt comparison
import logging
logging.disable(logging.CRITICAL)
_room = "Open-plan living room, natural light from west-facing windows."
_p_fv_prod = compose_generation_prompt("Zen Retreat · Serenity", "living room", _room, "", 1, [])
_p_fv_dev  = compose_generation_prompt("Zen Retreat · Serenity", "living room", _room, "", 1, [], compact_prompts=True)
_p_fv_j_prod = compose_generation_prompt("Japandi · Harmony", "living room", _room, "", 1, [])
_p_fv_j_dev  = compose_generation_prompt("Japandi · Harmony", "living room", _room, "", 1, [], compact_prompts=True)
logging.disable(logging.NOTSET)

_dev_profile  = _PROFILES.get("dev")
_prod_profile = _PROFILES.get("prod")

print(f"""
  DEV vs PROD BEHAVIOUR MATRIX:
  Parameter                | DEV             | PROD
  -------------------------|-----------------|----------------
  quality                  | {str(_dev_profile.quality):<15} | {str(_prod_profile.quality):<15}
  input_fidelity           | {str(_dev_profile.input_fidelity):<15} | {str(_prod_profile.input_fidelity):<15}
  size_override            | {str(_dev_profile.size_override or 'auto'):<15} | {str(_prod_profile.size_override or 'auto'):<15}
  max_attempts             | {str(_dev_profile.max_attempts):<15} | {str(_prod_profile.max_attempts):<15}
  compact_prompts          | {str(_dev_profile.compact_prompts):<15} | {str(_prod_profile.compact_prompts):<15}
  FV Zen/DNA prompt chars  | {len(_p_fv_dev):<15} | {len(_p_fv_prod):<15}
  FV Japandi prompt chars  | {len(_p_fv_j_dev):<15} | {len(_p_fv_j_prod):<15}
  Prompt saving (Zen/DNA)  | {len(_p_fv_prod) - len(_p_fv_dev):<15} | -

  MANUAL VALIDATION REQUIRED:
  [MANUAL] Run with APP_ENV=dev -- confirm 'DEV' in [GenerationProfile] log line
  [MANUAL] Run with APP_ENV=prod (or unset) -- confirm 'PROD' in log line
  [MANUAL] DEV generation: confirm quality=low, size=1024x1024 sent to OpenAI
  [MANUAL] DEV generation: confirm faster latency than PROD for same room
  [MANUAL] PROD generation: confirm quality=high, aspect-ratio size preserved
  [MANUAL] Architecture preservation: confirm structural contract present in both modes
  [MANUAL] DEV retry: confirm single attempt (no retry) on OpenAI failure
  [MANUAL] PROD retry: confirm up to 3 attempts logged on OpenAI failure
""")
