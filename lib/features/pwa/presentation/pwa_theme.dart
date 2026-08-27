/// The PWA's design language — now DERIVED FROM iOS rather than parallel to it.
///
/// Phase 1 of the iOS alignment. Three things changed and one deliberately did
/// not.
///
/// CHANGED — the canvas. [pwaCanvas] is the warm ivory iOS paints on, and the
/// theme's scaffold, surfaces and dividers follow it. The dark tokens below are
/// KEPT, not deleted: Home, Create, Projects and Full Reveal still paint with
/// them and will until their own migration phase. Deleting them would have
/// turned an incremental migration into a big-bang rewrite.
///
/// CHANGED — the typography. Cormorant Garamond and Inter are bundled in
/// `web/fonts/` and registered by `pwa_fonts.dart`; the roles live in
/// `pwa_type.dart`, each carrying the iOS style it was derived from. The old
/// [pwaDisplay] / [pwaSans] factories still work and now resolve to those same
/// families, so an unmigrated screen improves without being touched.
///
/// CHANGED — the geometry. Radii and spacing name the iOS values
/// (`AppSpacing`) instead of a parallel scale that was close without being it.
///
/// UNCHANGED — runtime font fetching stays OFF. [pwaDisableRemoteFonts] is not
/// a leftover: a paywall that blocks on `fonts.gstatic.com` is a paywall that
/// breaks behind a firewall, and a Cambodia-first product should not need a
/// round trip to Google for its first paint.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import 'pwa_type.dart';

/// The bundled Khmer family, registered at boot by `pwa_khmer_font.dart`.
/// Re-exported from [PwaType]'s definition so there is one spelling of it.
const String kPwaKhmerFamily = kPwaKhmerFamilyName;

/// Every fallback chain in the PWA ends with Khmer.
///
/// CanvasKit does not use the browser's system fonts, so a script with no
/// loaded font renders as tofu until Flutter has fetched a Noto fallback over
/// the network. Putting the bundled family at the end of each chain means Khmer
/// is right on the FIRST frame and stays right offline — see
/// `web/fonts/README.md` for the measurement that motivated it.
const List<String> pwaTextFallback = kPwaTextFallback;

/// The editorial fallback chain. Now headed by the bundled Cormorant Garamond;
/// the system serifs behind it catch a failed font load.
const List<String> pwaSerifFallback = kPwaDisplayFallback;

// ── Colour system ────────────────────────────────────────────────────────────
//
// These are ALIASES of the iOS palette, not a second one. `AppColors` is the
// shared file the mobile app itself uses, so a colour corrected there is
// corrected here — which is the whole reason this alignment turned out to be
// mostly a question of WHICH token a surface reaches for.

const Color pwaIvory = AppColors.background; // #F9F6F1
const Color pwaSurface = AppColors.surface; // #FFFFFF
const Color pwaSurfaceVariant = AppColors.surfaceVariant; // #F0ECE7
const Color pwaGold = AppColors.accent; // #C8A86A
const Color pwaGoldSoft = AppColors.accentLight; // #E8D9C5
const Color pwaInk = AppColors.textPrimary; // #1C1917
const Color pwaMuted = AppColors.textSecondary; // #78716C
const Color pwaFaint = AppColors.textTertiary; // #A8A29E
const Color pwaHairline = AppColors.border; // #E7E5E4
const Color pwaHairlineSoft = AppColors.borderLight; // #F5F3F1
const Color pwaOnDark = AppColors.brandIvory; // #F4F1EC — warm white on dark

// ── SEMANTIC surfaces — what later screens should reach for ──────────────────
//
// A screen asks for "the canvas", not "ivory". When a surface is wrong it gets
// corrected once, here, instead of in every widget that guessed.

/// The product canvas. iOS `AppColors.background`.
const Color pwaCanvas = pwaIvory;

/// Text and icons on [pwaCanvas].
const Color pwaOnCanvas = pwaInk;

/// A raised card or sheet on the canvas. iOS `AppColors.surface`.
const Color pwaCardSurface = pwaSurface;

/// A recessed well — chips, inactive fields. iOS `AppColors.surfaceVariant`.
const Color pwaWell = pwaSurfaceVariant;

/// The frame around an IMAGE, where iOS still goes dark so the photograph
/// carries the eye. A reveal surface, never chrome.
const Color pwaImageFrame = AppColors.brandWarmBlack; // #1E161E

// ── LEGACY dark tokens — kept deliberately, not endorsed ─────────────────────
//
// Home, Create, Projects and Full Reveal still paint with these and will until
// their own phase. They are NOT the application shell any more, and nothing new
// should reach for them: use [pwaCanvas] / [pwaCardSurface], or [pwaImageFrame]
// when the intent really is a dark frame around a photograph.
//
// They stay because an incremental migration has to compile at every step, and
// because the archive tag — not a big-bang delete — is the way back.

/// Legacy dark canvas. Prefer [pwaCanvas], or [pwaImageFrame] for image frames.
const Color pwaBlack = Color(0xFF0B0B0C);

/// Legacy dark surface. Prefer [pwaCardSurface] or [pwaImageFrame].
const Color pwaCharcoal = Color(0xFF161513);

/// Legacy raised dark surface. Prefer [pwaWell] or [pwaImageFrame].
const Color pwaCharcoalSoft = Color(0xFF201E1B);

// ── Spacing + radii — the iOS values, named ──────────────────────────────────
//
// Previously a parallel scale (xs 6, sm 10, xl 40) that was close to iOS
// without being it. Now the iOS numbers via `AppSpacing`, so a margin measured
// on an iPhone matches the one a browser renders.
//
// The one that moves a VISIBLE thing: [PwaGap.radiusPill] is 50. iOS CTAs are
// pills. The PWA drew some as pills and some as 16-radius rectangles, which is
// a large part of why its buttons did not feel like the same product.
abstract final class PwaGap {
  static const double xs = AppSpacing.xs; // 4  (was 6)
  static const double sm = AppSpacing.sm; // 8  (was 10)
  static const double md = AppSpacing.md; // 16
  static const double lg = AppSpacing.lg; // 24
  static const double xl = AppSpacing.xl; // 32 (was 40)
  static const double xxl = AppSpacing.xxl; // 48 (was 64)
  static const double xxxl = AppSpacing.xxxl; // 64
  static const double page = AppSpacing.pagePadding; // 24

  /// Cards and image containers. iOS `radiusCard`.
  static const double radius = AppSpacing.cardRadius; // 16

  /// Large hero / cinematic surfaces. iOS `radiusHero`.
  static const double radiusLg = AppSpacing.radiusHero; // 24 (was 22)

  /// CTAs, chips, badges. iOS `radiusButton` — a PILL.
  static const double radiusPill = AppSpacing.radiusPill; // 50

  /// Text fields. iOS `inputRadius`.
  static const double radiusInput = AppSpacing.inputRadius; // 14

  static const double maxContent = 1360;
}

// ── Typography (offline — bundled families, no runtime fetch) ────────────────

/// Editorial display. Now genuinely Cormorant Garamond.
///
/// Kept as a factory so the screens that have not migrated yet gain the correct
/// face without being touched. New code should prefer the named roles in
/// [PwaType], which carry the iOS style each was derived from.
TextStyle pwaDisplay({
  required double fontSize,
  FontWeight fontWeight = FontWeight.w500,
  Color color = pwaInk,
  double height = 1.08,
  double letterSpacing = -0.5,
}) => TextStyle(
  fontFamily: kPwaDisplayFamily,
  fontFamilyFallback: pwaSerifFallback,
  fontSize: fontSize,
  fontWeight: fontWeight,
  fontVariations: pwaWeightAxis(fontWeight),
  color: color,
  height: height,
  letterSpacing: letterSpacing,
  decoration: TextDecoration.none, // never underlined
);

/// Functional / control copy. Now genuinely Inter.
TextStyle pwaSans({
  required double fontSize,
  FontWeight fontWeight = FontWeight.w500,
  Color color = pwaInk,
  double height = 1.4,
  double letterSpacing = 0,
}) => TextStyle(
  fontFamily: kPwaTextFamily,
  fontFamilyFallback: pwaTextFallback,
  fontSize: fontSize,
  fontWeight: fontWeight,
  fontVariations: pwaWeightAxis(fontWeight),
  color: color,
  height: height,
  letterSpacing: letterSpacing,
  decoration: TextDecoration.none, // never underlined
);

/// Whether the UI is currently rendering Khmer.
///
/// Set once per frame by the app root. A mutable global is not how business
/// state is handled anywhere else in this codebase, and deliberately so — but
/// TRACKING is a rendering property of the script, the eyebrow helpers are
/// plain functions with no BuildContext, and threading a context through every
/// call site to answer "is this Khmer" would be a much larger change for the
/// same result.
///
/// WHY IT MATTERS: the eyebrows apply 2.1-2.4 of letter-spacing, which reads as
/// luxury in Latin. Khmer is a cluster script — a base consonant carries
/// subscripts and vowel signs that must sit tight against it — so the same
/// tracking pushes a single syllable apart into what looks like several. It is
/// legibility, not taste: "បន្ទប់" spaced out stops reading as one word.
bool pwaKhmerTypography = false;

/// Letter-spacing that collapses to zero for Khmer.
double pwaTracking(double base) =>
    pwaTrackingFor(base, khmer: pwaKhmerTypography);

/// Small uppercase label (section eyebrows: "AYDEN DECIDE", "STEP 1 OF 4").
TextStyle pwaEyebrow({Color color = pwaGold, double fontSize = 11}) =>
    PwaType.eyebrow(
        color: color, fontSize: fontSize, khmer: pwaKhmerTypography);

/// Hard-disable google_fonts runtime fetching so nothing ever makes an external
/// font request. Idempotent; safe to call on every build.
///
/// This is load-bearing, not defensive tidiness. The product typefaces are
/// bundled precisely so no surface — least of all the paywall — depends on a
/// third-party CDN being reachable.
void pwaDisableRemoteFonts() {
  GoogleFonts.config.allowRuntimeFetching = false;
}

/// Defensively force every Flutter debug-paint overlay OFF. The yellow lines the
/// PO saw look like `debugPaintBaselinesEnabled`; none is set in source, but this
/// guarantees no code path (or leaked test binding) can enable baseline/size/
/// pointer/repaint painting in the PWA. Idempotent; no effect in release.
void pwaHardenDebugPaints() {
  debugPaintBaselinesEnabled = false;
  debugPaintSizeEnabled = false;
  debugPaintPointersEnabled = false;
  debugPaintLayerBordersEnabled = false;
  debugRepaintRainbowEnabled = false;
  debugProfilePaintsEnabled = false;
}

/// The PWA's ThemeData — the iOS light system, offline.
///
/// Every value below is the one `AppTheme.light` uses on iOS. Where iOS states
/// a style through `GoogleFonts.inter(...)` this states the same numbers
/// through the bundled family instead, so the two render alike without the
/// runtime fetch.
ThemeData pwaTheme() {
  final base = ThemeData.light(useMaterial3: true);

  // THE Khmer fallback at THEME level, not only as an ambient DefaultTextStyle.
  //
  // Material surfaces that render in an overlay — PopupMenuItem, dialogs,
  // snackbars, menus — install their OWN DefaultTextStyle from
  // `theme.textTheme`, which REPLACES the ambient one instead of merging with
  // it. Measured: with only the ambient fallback in place, the language menu
  // still painted ភាសាខ្មែរ as tofu while the page behind it was correct.
  final textTheme = base.textTheme
      .apply(fontFamily: kPwaTextFamily, fontFamilyFallback: pwaTextFallback)
      .copyWith(
        displayLarge: PwaType.displayLarge(),
        displayMedium: PwaType.displayMedium(),
        headlineLarge: PwaType.screenTitle(),
        headlineMedium: PwaType.sectionTitle(),
        headlineSmall: PwaType.subsectionTitle(),
        titleLarge: PwaType.cardTitle(),
        titleMedium: PwaType.cardSubtitle(),
        bodyLarge: PwaType.body(),
        bodyMedium: PwaType.bodyMuted(),
        bodySmall: PwaType.caption(),
        labelLarge: PwaType.button(),
      );

  return base.copyWith(
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    colorScheme: const ColorScheme.light(
      primary: pwaInk,
      secondary: pwaGold,
      surface: pwaCardSurface,
    ),
    scaffoldBackgroundColor: pwaCanvas,
    dividerTheme: const DividerThemeData(
      color: pwaHairline,
      thickness: 1,
      space: 1,
    ),
    // iOS `bottomNavigationBarTheme` — white, hairline-topped, flat.
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: pwaCardSurface,
      selectedItemColor: pwaInk,
      unselectedItemColor: pwaFaint,
      selectedLabelStyle: PwaType.navigationLabel(),
      unselectedLabelStyle: PwaType.navigationLabel(color: pwaFaint),
      elevation: 0,
      type: BottomNavigationBarType.fixed,
    ),
    // iOS `elevatedButtonTheme` — ink pill, white label, flat.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: pwaInk,
        foregroundColor: pwaSurface,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PwaGap.radiusPill),
        ),
        textStyle: PwaType.button(),
      ),
    ),
    // iOS `outlinedButtonTheme` — 1.5px hairline, ink label.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: pwaInk,
        side: const BorderSide(color: pwaHairline, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PwaGap.radiusPill),
        ),
        textStyle: PwaType.button(),
      ),
    ),
    // iOS `inputDecorationTheme` — filled white, gold focus ring.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: pwaCardSurface,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PwaGap.radiusInput),
        borderSide: const BorderSide(color: pwaHairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PwaGap.radiusInput),
        borderSide: const BorderSide(color: pwaHairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PwaGap.radiusInput),
        borderSide: const BorderSide(color: pwaGold, width: 1.5),
      ),
      hintStyle: PwaType.bodyMuted(color: pwaFaint),
    ),
  );
}
