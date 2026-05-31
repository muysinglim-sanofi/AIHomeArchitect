"""
Generation profiles — centralized DEV/PROD configuration.

Wave 4.2.6: Cost Protection + Dev/Prod Modes.

Profile selection: read APP_ENV environment variable.
  APP_ENV=dev  → DEV profile  (cheap, fast, low-quality — safe for iteration)
  APP_ENV=prod → PROD profile (premium quality, full retries, full prompts)

Unset or unrecognised APP_ENV defaults to PROD (safe-fail toward quality).

Architecture notes:
- Add new profiles to _PROFILES without touching call sites.
- Profiles are frozen dataclasses — no accidental mutation.
- get_active_profile() is cheap to call per-request; it reads one env var.
- DO NOT scatter if/else APP_ENV checks outside this module.
"""

import logging
import os
from dataclasses import dataclass

log = logging.getLogger("aih")


@dataclass(frozen=True)
class GenerationProfile:
    """
    All per-mode parameters for a single generation call.

    Fields:
      name              — human-readable label used in log lines
      quality           — gpt-image-1 quality: "high" | "medium" | "low"
      input_fidelity    — "high" preserves source details; "low" is faster/cheaper;
                          None = omit the input_fidelity parameter from the API call entirely
      size_override     — None = auto-detect from source aspect ratio;
                          str  = force this exact output size ("1024x1024" etc.)
      max_attempts      — OpenAI retry attempts before raising GenerationError
      compact_prompts   — True = compact realism + skip P4 enrichments in composer
      use_mask          — False = skip the structural mask regardless of
                          ENABLE_STRUCTURAL_MASK (Wave 4.7.0 runtime isolation)
      vision_analysis_fv — False = skip GPT-4o-mini vision analysis for FIRST_VISION
                          (iteration == 1). Wave 4.6.1 already removed SOURCE_SPACE
                          from the FV prompt, so this has zero prompt impact for FV.

    Defaults on the last two fields preserve historical dev/prod behaviour exactly.
    """
    name: str
    quality: str
    input_fidelity: str | None
    size_override: str | None
    max_attempts: int
    compact_prompts: bool
    use_mask: bool = True
    vision_analysis_fv: bool = True
    # Wave 5.13n (2026-05-28) — hybrid per-atmosphere quality overrides.
    # Maps atmosphere_id -> quality string. Atmospheres NOT in this dict
    # use `quality` field above. Empty dict = no overrides, identical to
    # pre-5.13n behaviour. Use frozenset trick for hashability under frozen dataclass.
    quality_overrides: tuple[tuple[str, str], ...] = ()


# ── Profile registry ──────────────────────────────────────────────────────────
# Add future profiles here (STANDARD, FAST, LOW_COST, etc.) without
# touching main.py or the composer.

_PROFILES: dict[str, GenerationProfile] = {
    "dev": GenerationProfile(
        name="DEV",
        quality="low",
        input_fidelity="low",
        size_override="1024x1024",   # smallest supported size — fast + cheap
        max_attempts=1,              # fail fast; no retry budget burned
        compact_prompts=True,        # compact realism, skip dream/completeness
    ),
    "prod": GenerationProfile(
        name="PROD",
        quality="high",
        input_fidelity="high",
        size_override=None,          # aspect-ratio detection preserves proportions
        max_attempts=3,              # full resilience
        compact_prompts=False,       # full prompt richness
        use_mask=True,               # explicit — historical default
        vision_analysis_fv=True,     # explicit — historical default
    ),
    # ── Wave 4.7.0 Step 1 / 1B: Naked Baseline Isolation Test ─────────────────
    # Scientific runtime isolation. Tests whether the coherent 4.6.x prompt
    # architecture alone is sufficient WITHOUT the historical runtime "band-aids".
    # Activate with APP_ENV=mobile_mvp_baseline.
    #
    # Isolated OFF in this baseline (re-added one-per-step in future waves):
    #   quality          high  -> medium
    #   input_fidelity   high  -> OMITTED (no parameter sent)
    #   mask             on    -> off
    #   max_attempts     3     -> 1
    #   vision_analysis  on    -> off for FIRST_VISION
    #
    # Step 1B (aspect-ratio correction): forced size=1024x1024 was recomposing
    # landscape sources into a square frame (bay-window/width loss, geometry
    # normalization). size_override=None now routes through _detect_output_size()
    # — the same aspect-matched logic PROD uses (landscape -> 1536x1024,
    # portrait -> 1024x1536, square -> 1024x1024). Output aspect ratio is the
    # ONLY variable changed vs Step 1; this is NOT Step 2 (input_fidelity stays
    # omitted).
    #
    # KEPT identical: full 4.6.2 prompt architecture (compact_prompts=False),
    # SAME APARTMENT PHOTO-EDIT philosophy, openings_anchor, material-only DNA,
    # compact_realism, structural preservation wording. Prompt is NOT touched.
    "mobile_mvp_baseline": GenerationProfile(
        name="MOBILE_MVP_BASELINE",
        # Wave 5.13n hybrid quality (2026-05-28): MEDIUM by default,
        # LOW for atmospheres with strong natural texture identity
        # (validated visually per 16-photo bench: WM/Desert win in low,
        # SL/Japandi/Nordic/Nature/Tropical win in medium).
        # Wave 5.13b (2026-05-31): warm_modern override TEMPORARILY
        # REMOVED to test the daylight recalibration at medium quality.
        # The original 5.13n empirical "WM wins in low" was likely
        # correlated with the dark/orange/hotel mood that 5.13b is
        # rewriting away — low-quality picturial artifacts may have
        # been masking the over-warm tint. Re-bench Warm Modern at
        # both qualities after 5.13b stabilises and either re-add the
        # override or commit medium as the new permanent default.
        quality="medium",
        quality_overrides=(
            ("desert_luxe", "low"),
        ),
        # Wave 5.13n preserve override (in main.py call site): input_fidelity="high"
        # injected for preserve mode regardless of this default. Creative mode
        # (dormant V1) keeps profile.input_fidelity unchanged.
        input_fidelity=None,         # omitted entirely from the API call
        size_override=None,          # Step 1B: aspect-matched (was forced 1024x1024)
        max_attempts=1,
        compact_prompts=False,       # KEEP full 4.6.2 prompt architecture
        use_mask=False,
        vision_analysis_fv=False,
    ),
}

_DEFAULT_KEY = "prod"  # safe-fail direction: unknown env → premium quality


def get_active_profile() -> GenerationProfile:
    """
    Return the active GenerationProfile from APP_ENV.
    Logs the selected profile name + key parameters on every call (DEBUG level).
    Warns and falls back to PROD on unknown APP_ENV values.
    """
    env_key = os.environ.get("APP_ENV", _DEFAULT_KEY).lower().strip()
    profile = _PROFILES.get(env_key)
    if profile is None:
        log.warning(
            "[GenerationProfile] Unknown APP_ENV=%r — falling back to %r",
            env_key, _DEFAULT_KEY,
        )
        profile = _PROFILES[_DEFAULT_KEY]
    log.debug(
        "[GenerationProfile] active=%s  quality=%s  input_fidelity=%s  "
        "size_override=%s  max_attempts=%d  compact_prompts=%s  "
        "use_mask=%s  vision_analysis_fv=%s",
        profile.name, profile.quality, profile.input_fidelity or "omitted",
        profile.size_override or "auto", profile.max_attempts, profile.compact_prompts,
        profile.use_mask, profile.vision_analysis_fv,
    )
    return profile


def list_profiles() -> list[str]:
    """Return all registered profile keys (for introspection / health endpoints)."""
    return list(_PROFILES.keys())
