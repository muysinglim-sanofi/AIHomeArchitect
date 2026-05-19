// Lightweight adaptive layout utilities for AIHomeArchitect.
//
// Philosophy:
//   - No heavy responsive frameworks
//   - Precise, named thresholds with clear semantic meaning
//   - Subtle scaling — elegance first, density second
//   - OverflowBox remains a DEFENSIVE fallback; this is the PRIMARY solution

/// Three card density modes keyed to available card height.
enum AtmCardMode {
  /// h ≥ 160 — full premium layout: large icon, subtitle visible, 2-line name.
  full,

  /// 115 ≤ h < 160 — semi mode: medium icon, subtitle visible (1 line), 1-line name.
  semi,

  /// h < 115 — compact: small icon, name only, maximum image ratio.
  compact,
}

abstract final class AppAdaptive {
  // ── Atmosphere card ──────────────────────────────────────────────────────────

  /// Density mode based on the card's available [height].
  static AtmCardMode cardMode(double height) {
    if (height >= 160) return AtmCardMode.full;
    if (height >= 115) return AtmCardMode.semi;
    return AtmCardMode.compact;
  }

  /// Floating icon diameter — scales with card height.
  static double cardIconDiameter(double height) => switch (cardMode(height)) {
        AtmCardMode.full => 28.0,
        AtmCardMode.semi => 24.0,
        AtmCardMode.compact => 20.0,
      };

  /// Hero image fraction of total card height.
  static double cardImageRatio(double height) => switch (cardMode(height)) {
        AtmCardMode.full => 0.65,
        AtmCardMode.semi => 0.63,
        AtmCardMode.compact => 0.62,
      };

  /// Whether tagline text should be rendered.
  static bool cardShowsTagline(double height) => height >= 115;

  /// Max lines for the atmosphere name.
  static int cardNameMaxLines(double height) => height >= 175 ? 2 : 1;

  /// Max lines for the atmosphere tagline.
  static int cardTaglineMaxLines(double height) => height >= 175 ? 2 : 1;

  /// Font size for the atmosphere name.
  static double cardNameFontSize(double height) => switch (cardMode(height)) {
        AtmCardMode.full => 12.0,
        AtmCardMode.semi => 11.0,
        AtmCardMode.compact => 10.0,
      };

  /// Font size for the atmosphere tagline.
  static double cardTaglineFontSize(double height) => height >= 160 ? 10.0 : 9.5;

  /// Gap (px) between icon bottom edge and first text line.
  static double cardIconTextGap(double height) => height >= 140 ? 4.0 : 3.0;

  /// Gap (px) between name and tagline.
  static double cardNameTaglineGap(double height) => height >= 140 ? 2.0 : 1.0;

  // ── FTUE screen heights (keyed to device screen height) ──────────────────────
  //
  // Four tiers so every common device gets intentional values:
  //   ≥ 812  Pro / Max — generous layout, full hero, large strip
  //   ≥ 700  Standard (iPhone 14, 13, X…) — slightly reduced
  //   ≥ 600  Compact (iPhone 8, SE 2020, 2022 — 667 pt) — current small default
  //   < 600  Very small (iPhone SE 1st gen / 5s — 568 pt) — aggressive reduction

  /// Large hero image height for FTUE Screen 3.
  static double ftueHeroHeight(double screenH) {
    if (screenH >= 812) return 210.0;
    if (screenH >= 700) return 180.0;
    if (screenH >= 600) return 155.0;
    return 108.0;
  }

  /// Atmosphere card strip height for FTUE Screen 3.
  /// < 600: 90 px → compact mode (h < 115), tagline hidden.
  static double ftueCardStripHeight(double screenH) {
    if (screenH >= 812) return 140.0;
    if (screenH >= 700) return 125.0;
    if (screenH >= 600) return 112.0;
    return 90.0;
  }

  /// Card width in FTUE strip — narrower on small screens.
  static double ftueCardWidth(double screenH) {
    if (screenH >= 812) return 100.0;
    if (screenH >= 700) return 92.0;
    if (screenH >= 600) return 86.0;
    return 80.0;
  }

  /// Spacing between FTUE hero and card strip.
  static double ftueInnerSpacing(double screenH) {
    if (screenH >= 700) return 16.0;
    if (screenH >= 600) return 10.0;
    return 4.0;
  }

  /// Spacing between FTUE card strip and title text.
  static double ftueTitleSpacing(double screenH) {
    if (screenH >= 700) return 24.0;
    if (screenH >= 600) return 14.0;
    return 6.0;
  }

  // ── Reveal strip ─────────────────────────────────────────────────────────────
  //
  // The strip lives inside a fixed-height overlay below the before/after image.
  // Adapting to screen height preserves more image area on smaller devices.
  //   ≥ 812: 124 px — semi mode (tagline 1 line)
  //   ≥ 700: 118 px — semi mode
  //   ≥ 600: 115 px — semi mode (at exact threshold)
  //   < 600: 108 px — compact mode (tagline hidden, more image area)

  /// Atmosphere strip height in the before/after reveal screen.
  static double revealStripHeight(double screenH) {
    if (screenH >= 812) return 124.0;
    if (screenH >= 700) return 118.0;
    if (screenH >= 600) return 115.0;
    return 108.0;
  }

  /// Atmosphere card width in the reveal strip.
  static double revealCardWidth(double screenH) {
    if (screenH >= 812) return 90.0;
    if (screenH >= 700) return 86.0;
    if (screenH >= 600) return 82.0;
    return 76.0;
  }

  // ── Atmosphere grid aspect ratios ─────────────────────────────────────────────

  /// childAspectRatio for the 2-column atmosphere grid on the upload sheet.
  /// Gives ~200 px card height on a 375 px screen → full mode.
  static const double uploadAtmosphereAspectRatio = 0.82;

  /// childAspectRatio for the 3-column atmosphere grid in the design-direction modal.
  /// Gives ~145 px card height on a 375 px screen → semi mode (tagline visible, 1 line).
  static const double modalAtmosphereAspectRatio = 0.75;
}
