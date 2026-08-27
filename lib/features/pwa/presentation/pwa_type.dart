/// THE PWA type system, derived from iOS rather than approximated.
///
/// Every value below is read from `frontend/lib/core/theme/app_theme.dart` at
/// mobile HEAD `f3a6fa2`, which is the visual source of truth. Where a role has
/// no iOS counterpart the derivation is stated in a comment; nothing here is a
/// taste decision made on the web side.
///
/// The two families, and which is which
/// ------------------------------------
///   Cormorant Garamond  editorial display. iOS `AppTheme.displayEditorial()`
///                       and `AppTheme.atmosphereTitle()`. This is the face
///                       that makes the product read as an architecture studio
///                       rather than a dashboard, and its absence is most of
///                       why the PWA did not look like Ayden Studio.
///   Inter               everything functional. iOS `GoogleFonts.interTextTheme`.
///
/// Both are BUNDLED (`web/fonts/`, registered by `pwa_fonts.dart`). Runtime
/// fetching stays disabled — see that file for why.
///
/// Why roles instead of a `TextStyle` per call site
/// ------------------------------------------------
/// The screens that come after this phase should ask for `PwaType.screenTitle`,
/// not for "Inter 26 w600 -0.3". A role can be corrected once against the iOS
/// reference; a hundred literal sizes cannot. The old `pwaDisplay` / `pwaSans`
/// factories still exist for the screens not yet migrated — see
/// `pwa_theme.dart` — and now resolve to these same families.
library;

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

// ── the registered families ─────────────────────────────────────────────────

/// Must match the `FontLoader` family in `pwa_fonts.dart`.
const String kPwaDisplayFamily = 'CormorantGaramond';
const String kPwaTextFamily = 'Inter';

/// The bundled Khmer family, registered by `pwa_khmer_font.dart`.
const String kPwaKhmerFamilyName = 'NotoSansKhmer';

/// Every chain ends with Khmer.
///
/// CanvasKit does not use the browser's system fonts: a script with no loaded
/// font renders as tofu until Flutter fetches a Noto fallback over the network.
/// Putting the bundled family last means Khmer is correct on the FIRST frame,
/// offline. The system faces in between catch the case where a bundled Latin
/// face failed to load — degraded, not broken.
const List<String> kPwaTextFallback = [
  kPwaTextFamily,
  'Helvetica Neue',
  'Arial',
  'sans-serif',
  kPwaKhmerFamilyName,
];

const List<String> kPwaDisplayFallback = [
  kPwaDisplayFamily,
  'Georgia',
  'Times New Roman',
  'serif',
  kPwaKhmerFamilyName,
];

// ── the Khmer tracking rule, preserved from the previous system ─────────────

/// Whether the UI is currently rendering Khmer. Set once per frame by the app
/// root (see `pwa_theme.dart`, which owns the flag and its rationale).
///
/// Restated here because it is a TYPE concern: the eyebrow roles apply 2+ of
/// letter-spacing, which reads as luxury in Latin. Khmer is a cluster script —
/// a base consonant carries subscripts and vowel signs that must sit tight
/// against it — so the same tracking pushes one syllable apart into what looks
/// like several. Legibility, not taste.
double pwaTrackingFor(double base, {required bool khmer}) => khmer ? 0 : base;

/// The `wght` axis, stated rather than inferred.
///
/// Flutter does map `fontWeight` onto a variable font's `wght` axis, but only
/// once the font is registered — and if a load failed, `fontWeight` alone would
/// silently render the fallback at a synthesised weight. Naming the axis makes
/// the intent explicit and costs nothing when the font is absent.
List<FontVariation> pwaWeightAxis(FontWeight w) =>
    [FontVariation('wght', w.value.toDouble())];

TextStyle _display({
  required double fontSize,
  required FontWeight fontWeight,
  required double height,
  required double letterSpacing,
  Color color = AppColors.textPrimary,
}) =>
    TextStyle(
      fontFamily: kPwaDisplayFamily,
      fontFamilyFallback: kPwaDisplayFallback,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontVariations: pwaWeightAxis(fontWeight),
      height: height,
      letterSpacing: letterSpacing,
      color: color,
      decoration: TextDecoration.none,
    );

TextStyle _text({
  required double fontSize,
  required FontWeight fontWeight,
  double? height,
  double letterSpacing = 0,
  Color color = AppColors.textPrimary,
}) =>
    TextStyle(
      fontFamily: kPwaTextFamily,
      fontFamilyFallback: kPwaTextFallback,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontVariations: pwaWeightAxis(fontWeight),
      height: height,
      letterSpacing: letterSpacing,
      color: color,
      decoration: TextDecoration.none,
    );

/// The roles. Each carries the iOS style it was derived from.
abstract final class PwaType {
  // ── editorial display — Cormorant Garamond ───────────────────────────────

  /// iOS `AppTheme.displayEditorial()` — 38 / w500 / -0.5 / 1.08.
  /// Hero statements: the Home headline, the FTUE, cinematic surfaces.
  static TextStyle displayHero({
    double fontSize = 38,
    Color color = AppColors.textPrimary,
  }) =>
      _display(
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          height: 1.08,
          letterSpacing: -0.5,
          color: color);

  /// iOS Home, verbatim — `displayEditorial(27, w500, height 1.12, -0.4)`.
  ///
  /// Deliberately NOT `displayHero` at a smaller size: the Home headline runs
  /// to two lines, and iOS loosens the leading (1.12 vs 1.08) and the tracking
  /// (-0.4 vs -0.5) for exactly that reason. Reusing the hero role would have
  /// set two lines too tight.
  static TextStyle homeHeadline({Color color = AppColors.textPrimary}) =>
      _display(
          fontSize: 27,
          fontWeight: FontWeight.w500,
          height: 1.12,
          letterSpacing: -0.4,
          color: color);

  /// iOS `AppTheme.atmosphereTitle()` — 20 / w600 / 0 / 1.15.
  /// The product's signature element: an atmosphere name over imagery.
  static TextStyle atmosphereTitle({
    double fontSize = 20,
    Color color = AppColors.textPrimary,
  }) =>
      _display(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          height: 1.15,
          letterSpacing: 0,
          color: color);

  // ── functional — Inter ───────────────────────────────────────────────────

  /// iOS `displayLarge` — 40 / w300 / -1.
  static TextStyle displayLarge({Color color = AppColors.textPrimary}) =>
      _text(fontSize: 40, fontWeight: FontWeight.w300, letterSpacing: -1, color: color);

  /// iOS `displayMedium` — 32 / w300 / -0.5.
  static TextStyle displayMedium({Color color = AppColors.textPrimary}) =>
      _text(fontSize: 32, fontWeight: FontWeight.w300, letterSpacing: -0.5, color: color);

  /// iOS `headlineLarge` — 26 / w600 / -0.3. The title of a screen.
  static TextStyle screenTitle({Color color = AppColors.textPrimary}) =>
      _text(fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: color);

  /// iOS `headlineMedium` — 22 / w600. The title of a section within a screen.
  static TextStyle sectionTitle({Color color = AppColors.textPrimary}) =>
      _text(fontSize: 22, fontWeight: FontWeight.w600, color: color);

  /// iOS `headlineSmall` — 18 / w500.
  static TextStyle subsectionTitle({Color color = AppColors.textPrimary}) =>
      _text(fontSize: 18, fontWeight: FontWeight.w500, color: color);

  /// iOS `titleLarge` — 16 / w600. A card's own title.
  static TextStyle cardTitle({Color color = AppColors.textPrimary}) =>
      _text(fontSize: 16, fontWeight: FontWeight.w600, color: color);

  /// iOS `titleMedium` — 15 / w500.
  static TextStyle cardSubtitle({Color color = AppColors.textPrimary}) =>
      _text(fontSize: 15, fontWeight: FontWeight.w500, color: color);

  /// iOS `bodyLarge` — 16 / w400 / textPrimary.
  static TextStyle body({Color color = AppColors.textPrimary}) =>
      _text(fontSize: 16, fontWeight: FontWeight.w400, height: 1.5, color: color);

  /// iOS `bodyMedium` — 14 / w400 / textSecondary. The default supporting line.
  static TextStyle bodyMuted({Color color = AppColors.textSecondary}) =>
      _text(fontSize: 14, fontWeight: FontWeight.w400, height: 1.5, color: color);

  /// iOS `bodySmall` — 12 / w400 / textTertiary.
  static TextStyle caption({Color color = AppColors.textTertiary}) =>
      _text(fontSize: 12, fontWeight: FontWeight.w400, height: 1.4, color: color);

  /// iOS `labelLarge` — 15 / w600 / +0.2. The label inside a CTA.
  static TextStyle button({Color color = AppColors.textPrimary}) =>
      _text(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.2, color: color);

  /// The bottom-navigation label.
  ///
  /// iOS does not set one explicitly — `BottomNavigationBar` derives it from
  /// the theme — so this states Flutter's own effective size (12) in the
  /// product's family rather than leaving it to a Material default that would
  /// silently be a different face.
  static TextStyle navigationLabel({Color color = AppColors.textPrimary}) =>
      _text(fontSize: 12, fontWeight: FontWeight.w500, color: color);

  /// The small uppercase eyebrow above a section — "STEP 1 OF 4",
  /// "CONTINUE DESIGNING", "AYDEN SIGNATURE".
  ///
  /// Tracking collapses to zero for Khmer; pass `khmer: true` from a call site
  /// that knows the locale, or use `pwaEyebrow()` in `pwa_theme.dart` which
  /// reads the ambient flag.
  static TextStyle eyebrow({
    Color color = AppColors.accent,
    double fontSize = 11,
    bool khmer = false,
  }) =>
      _text(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: pwaTrackingFor(2.4, khmer: khmer),
        color: color,
      );
}
