/// Batch 2.1 — the PWA's own coherent, OFFLINE design language.
///
/// Deliberately does NOT use google_fonts (which fetches from fonts.gstatic.com
/// at runtime) so `AYDEN_ENV=mock` stays genuinely offline — no external font
/// request. The editorial hierarchy is built from weight / size / tracking on
/// the platform default family (no bundled serif is available to embed; adding
/// one would require a local .ttf, out of scope here). [pwaDisableRemoteFonts]
/// hard-disables any google_fonts runtime fetch defensively.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';

/// The bundled Khmer family, registered at boot by `pwa_khmer_font.dart`.
///
/// It is only ever a FALLBACK, never a primary family: Latin text keeps exactly
/// the typography it had, and only code points no other font covers reach it.
/// The name must match the `FontLoader` family used at registration.
const String kPwaKhmerFamily = 'NotoSansKhmer';

/// Every fallback chain in the PWA ends with Khmer.
///
/// CanvasKit does not use the browser's system fonts, so a script with no
/// loaded font renders as tofu until Flutter has fetched a Noto fallback over
/// the network. Putting the bundled family at the end of each chain means Khmer
/// is right on the FIRST frame and stays right offline — see
/// `web/fonts/README.md` for the measurement that motivated it.
const List<String> pwaTextFallback = [kPwaKhmerFamily];

/// A safe system-serif fallback stack for editorial headings.
///
/// Khmer is appended: without it, a Khmer heading would consult Georgia and
/// Times (neither of which has the script) and then fall through to the remote
/// Noto download this bundling exists to avoid.
const List<String> pwaSerifFallback = [
  'Georgia',
  'Times New Roman',
  'serif',
  kPwaKhmerFamily,
];

// ── Colour system ────────────────────────────────────────────────────────────
// Cinematic / design-authority states = deep black + charcoal; product states =
// warm ivory; muted metallic gold is the single signature accent.

const Color pwaBlack = Color(0xFF0B0B0C);
const Color pwaCharcoal = Color(0xFF161513);
const Color pwaCharcoalSoft = Color(0xFF201E1B);
const Color pwaIvory = AppColors.background; // #F9F6F1
const Color pwaSurface = AppColors.surface; // #FFFFFF
const Color pwaGold = AppColors.accent; // #C8A86A
const Color pwaGoldSoft = Color(0xFFE8D9C5);
const Color pwaInk = AppColors.textPrimary; // #1C1917
const Color pwaMuted = AppColors.textSecondary; // #78716C
const Color pwaFaint = AppColors.textTertiary; // #A8A29E
const Color pwaHairline = AppColors.border;
const Color pwaOnDark = Color(0xFFF4F1EC); // warm white on dark

// ── Spacing rhythm ───────────────────────────────────────────────────────────
abstract final class PwaGap {
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 40;
  static const double xxl = 64;
  static const double page = 24;
  static const double radius = 16;
  static const double radiusLg = 22;
  static const double maxContent = 1360;
}

// ── Typography (offline — no runtime font fetch) ─────────────────────────────

/// Editorial display for major statements. Uses the platform default family
/// with restrained luxury tracking/weight (no google_fonts → offline-safe).
TextStyle pwaDisplay({
  required double fontSize,
  FontWeight fontWeight = FontWeight.w300,
  Color color = pwaInk,
  double height = 1.1,
  double letterSpacing = -0.4,
}) => TextStyle(
  fontSize: fontSize,
  fontWeight: fontWeight,
  color: color,
  height: height,
  letterSpacing: letterSpacing,
  fontFamilyFallback: pwaSerifFallback,
  decoration: TextDecoration.none, // never underlined
);

/// Functional / control copy.
TextStyle pwaSans({
  required double fontSize,
  FontWeight fontWeight = FontWeight.w500,
  Color color = pwaInk,
  double height = 1.4,
  double letterSpacing = 0,
}) => TextStyle(
  fontSize: fontSize,
  fontWeight: fontWeight,
  color: color,
  height: height,
  letterSpacing: letterSpacing,
  fontFamilyFallback: pwaTextFallback,
  decoration: TextDecoration.none, // never underlined
);

/// Whether the UI is currently rendering Khmer.
///
/// Set once per frame by the app root. A mutable global is not how business
/// state is handled anywhere else in this codebase, and deliberately so — but
/// TRACKING is a rendering property of the script, the two eyebrow helpers are
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
double pwaTracking(double base) => pwaKhmerTypography ? 0 : base;

/// Small uppercase label (section eyebrows: "AYDEN DECIDE", "AYDEN SIGNATURE").
TextStyle pwaEyebrow({Color color = pwaGold, double fontSize = 11}) =>
    TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      color: color,
      letterSpacing: pwaTracking(2.4),
      fontFamilyFallback: pwaTextFallback,
      decoration: TextDecoration.none, // never underlined
    );

/// Hard-disable google_fonts runtime fetching so the offline mock never makes
/// an external font request. Idempotent; safe to call on every build.
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

/// The PWA's offline ThemeData (no google_fonts textTheme). Ivory scaffold,
/// ink/gold scheme, default font family (no external fetch).
ThemeData pwaTheme() {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    // THE Khmer fallback at THEME level, not only as an ambient
    // DefaultTextStyle.
    //
    // Material surfaces that render in an overlay — PopupMenuItem, dialogs,
    // snackbars, menus — install their OWN DefaultTextStyle from
    // `theme.textTheme`, which REPLACES the ambient one instead of merging with
    // it. Measured: with only the ambient fallback in place, the language menu
    // still painted ភាសាខ្មែរ as tofu while the page behind it was correct.
    // Applying the fallback to the text themes is what reaches those surfaces.
    textTheme: base.textTheme.apply(fontFamilyFallback: pwaTextFallback),
    primaryTextTheme:
        base.primaryTextTheme.apply(fontFamilyFallback: pwaTextFallback),
    colorScheme: const ColorScheme.light(
      primary: pwaInk,
      secondary: pwaGold,
      surface: pwaSurface,
    ),
    scaffoldBackgroundColor: pwaIvory,
    dividerTheme: const DividerThemeData(
      color: pwaHairline,
      thickness: 1,
      space: 1,
    ),
  );
}
