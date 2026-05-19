abstract class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double xxxl = 64;

  static const double pagePadding = 24;
  static const double cardRadius = 16;
  static const double buttonRadius = 50;
  static const double chipRadius = 50;
  static const double inputRadius = 14;

  // ── Wave 4 — Design-System Spine: rationalized radius tokens ───────────────
  // Canonical, semantically-named radii for all future frontend waves.
  // Values intentionally ALIAS the existing constants so adopting these names
  // is a zero-visual-change refactor; the legacy names above are retained for
  // backward compatibility until screens migrate. (Any value *change* — e.g. a
  // less "pill" CTA — is a deliberate screen-wave decision, NOT this PR.)
  static const double radiusPill = buttonRadius;   // 50 — pills, chips, badges
  static const double radiusButton = buttonRadius; // 50 — CTAs (value unchanged)
  static const double radiusCard = cardRadius;     // 16 — cards
  static const double radiusInput = inputRadius;   // 14 — inputs
  static const double radiusHero = 24;             // large hero / cinematic surfaces
}
