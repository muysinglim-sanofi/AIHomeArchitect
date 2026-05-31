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
  static const bool revenuecatGracefulDegradation = false;

  /// Wave 5.17d.1 — Display ABA + ACLEDA payment chips in the paywall
  /// "Secure payments" row. OFF by default because RevenueCat does not
  /// process Cambodian banking rails directly ; showing those badges
  /// without an actual processor would violate App Store + Play policy
  /// (misleading payment claims). Re-enable only after a confirmed
  /// regional processor is wired AND store policy is reviewed.
  static const bool cambodianPaymentBadges = false;
}
