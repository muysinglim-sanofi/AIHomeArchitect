/// Wave 5.17d — Compile-time feature flags.
///
/// Re-enable / disable user-facing surfaces without deleting the
/// underlying infrastructure. Every flag has a fixed name and is read
/// directly (no provider, no env var) so dead-code is eliminated by
/// the Dart tree-shaker when the flag is `false`.
library;

class FeatureFlags {
  FeatureFlags._();

  /// Sign-in flows hidden from the user journey (Decision Wave 5.17d).
  ///
  /// When false :
  ///   - PaywallSheet shows the RevenueCat purchase flow directly (no
  ///     intermediate sign-in screen).
  ///   - Profile screen does not show the voluntary "Sign In" entry.
  ///   - Profile screen does not show the "Sign Out" button (with no
  ///     sign-in there is nothing to sign out of ; also closes the
  ///     quota-reset abuse path via UUID rotation).
  ///
  /// To re-enable in a future wave : flip to true. The SignInScreen,
  /// AuthService.signInWithApple / signInWithGoogle, and the backend
  /// JWKS verification all remain functional — they are only hidden
  /// from the UI.
  static const bool signInEnabled = false;

  /// RevenueCat graceful-degradation guard.
  ///
  /// When false (default) : a missing or misconfigured RevenueCat
  /// configuration is a HARD FAILURE at app start — the configure()
  /// call throws, surfacing the misconfiguration immediately in dev.
  /// This is the safe choice : a paywall that silently shows "no
  /// products" is worse than a noisy crash.
  ///
  /// When true : missing config logs a warning and the paywall falls
  /// back to "Restore Purchases" + "Maybe later" only. Use this only
  /// as a production hot-fix while a misconfiguration is being
  /// resolved on the RevenueCat dashboard — never as the default.
  static const bool revenuecatGracefulDegradation = true;

  /// Wave 5.17d.1 — Display ABA + ACLEDA payment chips in the paywall
  /// "Secure payments" row. OFF by default because RevenueCat does not
  /// process Cambodian banking rails directly ; showing those badges
  /// without an actual processor would violate App Store + Play policy
  /// (misleading payment claims). Re-enable only after a confirmed
  /// regional processor is wired AND store policy is reviewed.
  static const bool cambodianPaymentBadges = false;

  /// AYDEN Part A (A2) — cinematic before→after reveal on the result surface.
  ///
  /// When false (default) : the result reveal uses the existing `RevealHero`
  /// slider exactly as before — zero behaviour change.
  /// When true : the result surface swaps in the new `RevealWidget`
  /// (deterministic feathered sweep + shared ≤3% push, auto-play once → settle
  /// on AFTER, then manual scrub). Additive, isolated, fully reversible — flip
  /// to preview on device. No AI, no provider, no image-core/DNA impact.
  static const bool cinematicReveal = true;

  /// AYDEN card system preview — exposes a dev entry (Profile) + `/cards-preview`
  /// route to validate the redesigned Room/Atmosphere/AI card system on device.
  /// Isolated; does not alter the real upload/selection flow.
  static const bool cardsPreview = true;

  /// AYDEN new card system wired into the real New Design (upload Step 2/3).
  /// When true (default) : Step 2 = hero grid + More Spaces row, Step 3 =
  /// mini-hero atmosphere carousel (new RoomCard/AtmosphereHeroCard/AiActionCard).
  /// When false : the original `RoomTypeRow` / `AtmosphereCard` selectors —
  /// instant rollback. Display labels English (Option A); routing/free-tier
  /// values + paywall + `_start()` unchanged.
  static const bool newDesignCards = true;

  /// AYDEN premium paywall V2 — emotional lifestyle redesign (Cormorant
  /// headline, premium hero, simplified vertically-stacked plans with Annual
  /// pushed as Best Value, "How it works" mini-story, lighter density). When
  /// false : the original V1 paywall layout. Frontend/UI only — pricing,
  /// RevenueCat purchase/restore logic and `_start()` are unchanged.
  static const bool paywallV2 = true;

  /// AYDEN premium "Upload your space" picker — the image-source bottom sheet
  /// redesigned (serif title, Camera/Gallery cards, "Example photos" carousel
  /// of blank before-rooms to test instantly, privacy footer). When false : the
  /// original Camera/Gallery `ListTile` sheet. Frontend/UI only — selecting an
  /// example just sets the source image exactly like a normal pick.
  static const bool uploadPickerV2 = true;

  /// Voice dictation — "continuous" capture (Option A, best-effort on the
  /// native OS recognizers). When true : the mic keeps listening through
  /// pauses (large pauseFor + auto-restart when the engine self-stops),
  /// partials feed a temporary PREVIEW only, final segments accumulate in an
  /// internal buffer, and the committed transcript is written into the text
  /// field ONLY when the user taps stop (never auto-sent). When false : the
  /// legacy single-shot behaviour (partials written live, stop on first
  /// silence). Frontend/voice only — no /generate, backend or pipeline impact.
  /// Instant rollback : flip to false.
  static const bool voiceContinuous = true;

  /// Group 1 (2026-06-19) — generation lifecycle hardening:
  ///   • "ready" snackbar / OS notification is SUPPRESSED when the just-completed
  ///     session is the one the user is currently viewing (active-session aware,
  ///     instead of the old `!mounted`-only guard which misfired for a
  ///     re-opened instance of the same session);
  ///   • the loading progress bar RESUMES from the real generation elapsed time
  ///     (persisted startedAt) instead of restarting from 0 on every rebuild;
  ///   • the long-generation reassurance fires after 60s (was 45s).
  /// Frontend/UI only — no /generate, backend or pipeline change. Instant
  /// rollback: flip to false. V1 impact: NONE.
  static const bool genLifecycleV2 = true;

  /// B1 (2026-06-19) — stay in ONE session across a re-upload, but keep every
  /// lineage's versions in the ledger (do NOT purge on re-upload) so that acting
  /// on an OLDER vision (continue-from-vision, or an atmosphere switch from its
  /// full reveal) pins THAT vision's exact version AND restores its lineage's
  /// structural identity. Fixes the cross-lineage "wrong apartment" leak (the
  /// switch used the re-uploaded lineage's version+identity instead of the
  /// viewed vision's). Scoped to NON-latest visions so the normal switch keeps
  /// the cascade-free V1 anchor (Wave 5.21). When false: the legacy ledger purge
  /// runs (instant rollback). V1 first-vision path unchanged → V1 impact: NONE.
  static const bool reuploadKeepLineage = true;

  /// #8 (2026-06-19) — Ayden Decide (Let-AI-Decide) is available to FREE users
  /// (no premium lock); only the normal free generation quota applies. Mirrors
  /// the backend AYDEN_DECIDE_FREE env flag (free_tier.check_restrictions).
  /// Surprise Me stays premium. When false: the old premium lock + paywall on
  /// tap. Keep both sides in lockstep. UI gating only — backend enforces.
  static const bool aydenDecideFree = true;

  /// AYDEN SIGNATURE (2026-06-21) — the rebranded "Surprise Me": the AI analyzes
  /// the photo and picks the best-fit atmosphere (backend SURPRISE_VISION). When
  /// true: shown FIRST in the atmosphere selector, pre-selected by DEFAULT, and
  /// FREE (no premium lock) — it's a conversion funnel (taste a premium style via
  /// the AI, then pay to pick it explicitly). The explicit-atmosphere lock stays.
  /// Mirrors the backend AYDEN_SIGNATURE_FREE env flag — keep both in lockstep.
  /// When false: the old premium-locked "Surprise Me", default = Warm Modern.
  static const bool aydenSignatureFree = true;
}
