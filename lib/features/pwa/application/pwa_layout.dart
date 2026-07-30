/// Batch 2 — centralized responsive decision for the PWA prototype.
///
/// One place owns the breakpoints so the hot screens don't scatter arbitrary
/// width checks. Pure + testable (no BuildContext).
library;

enum PwaFormFactor { mobile, tablet, desktop }

/// Map an available width to a form factor.
///   < 700  → mobile   (single vertical flow, bottom sheets, fixed composer)
///   < 1100 → tablet   (spacious vertical flow, touch-friendly)
///   ≥ 1100 → desktop  (reveal workspace + assistant panel)
PwaFormFactor pwaFormFactorForWidth(double width) {
  if (width < 700) return PwaFormFactor.mobile;
  if (width < 1100) return PwaFormFactor.tablet;
  return PwaFormFactor.desktop;
}

/// Desktop uses the two-pane (reveal + conversation) workspace; mobile/tablet
/// use the single vertical flow.
bool pwaIsTwoPane(PwaFormFactor f) => f == PwaFormFactor.desktop;

/// Restrained maximum content width so desktop never stretches mobile cards.
double pwaMaxContentWidth(PwaFormFactor f) => switch (f) {
      PwaFormFactor.mobile => double.infinity,
      PwaFormFactor.tablet => 720,
      PwaFormFactor.desktop => 1360,
    };
