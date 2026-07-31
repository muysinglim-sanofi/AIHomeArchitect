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

/// A safe system-serif fallback stack for editorial headings. No font file is
/// bundled (adding one needs approval), so this is best-effort: platforms that
/// expose these families render a true serif; on CanvasKit web it may fall back
/// to the embedded sans — a documented limitation, never an underline.
const List<String> pwaSerifFallback = ['Georgia', 'Times New Roman', 'serif'];

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
  decoration: TextDecoration.none, // never underlined
);

/// Small uppercase label (section eyebrows: "AYDEN DECIDE", "AYDEN SIGNATURE").
TextStyle pwaEyebrow({Color color = pwaGold, double fontSize = 11}) =>
    TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      color: color,
      letterSpacing: 2.4,
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
