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
}
