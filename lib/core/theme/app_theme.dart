import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';

class AppTheme {
  // ── Wave 4 — Design-System Spine: editorial typography tokens ─────────────
  // Additive ONLY. These tokens are NOT wired into the global textTheme yet —
  // they have zero visual effect until a screen wave consumes them. The audit
  // identified "Inter-only headings" as the #1 premium gap; the editorial face
  // (a restrained luxury serif via the existing google_fonts mechanism — same
  // runtime path already used for Inter) is reserved for hero + atmosphere
  // identity, pairing with Inter body. Calm-premium calibration spirit kept
  // (light-leaning weight, tight tracking). Khmer glyph fallback preserved on
  // every token so bilingual rendering never breaks.

  /// Shared Khmer fallback chain — mirrors the body textTheme exactly.
  static const List<String> khmerFallback = [
    'Noto Sans Khmer',
    'Khmer OS',
    'sans-serif',
  ];

  /// Large editorial display — hero headlines (FTUE, Home, Cinematic).
  /// Replaces Inter `displayLarge/Medium` ONLY where a screen opts in.
  static TextStyle displayEditorial({
    double fontSize = 38,
    FontWeight fontWeight = FontWeight.w500,
    Color color = AppColors.textPrimary,
    double height = 1.08,
    double letterSpacing = -0.5,
  }) =>
      GoogleFonts.cormorantGaramond(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      ).copyWith(fontFamilyFallback: khmerFallback);

  /// Atmosphere identity — atmosphere name over imagery / on cards.
  /// One canonical type for the product's signature element (replaces the
  /// hard-coded 'Lato' fracture once cards migrate).
  static TextStyle atmosphereTitle({
    double fontSize = 20,
    FontWeight fontWeight = FontWeight.w600,
    Color color = AppColors.textPrimary,
    double height = 1.15,
    double letterSpacing = 0.0,
  }) =>
      GoogleFonts.cormorantGaramond(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      ).copyWith(fontFamilyFallback: khmerFallback);

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      displayLarge: GoogleFonts.inter(
        fontSize: 40,
        fontWeight: FontWeight.w300,
        color: AppColors.textPrimary,
        letterSpacing: -1,
      ),
      displayMedium: GoogleFonts.inter(
        fontSize: 32,
        fontWeight: FontWeight.w300,
        color: AppColors.textPrimary,
        letterSpacing: -0.5,
      ),
      headlineLarge: GoogleFonts.inter(
        fontSize: 26,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        letterSpacing: -0.3,
      ),
      headlineMedium: GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      headlineSmall: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.textTertiary,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        letterSpacing: 0.2,
      ),
    );

    // Apply Khmer font fallback to every text style so Khmer glyphs render
    // correctly alongside Inter (Latin). Noto Sans Khmer covers all Khmer
    // Unicode ranges; the system Khmer font is the final fallback.
    const khmerFallback = ['Noto Sans Khmer', 'Khmer OS', 'sans-serif'];
    TextStyle withKhmer(TextStyle? s) =>
        (s ?? const TextStyle()).copyWith(fontFamilyFallback: khmerFallback);
    final khmerTextTheme = textTheme.copyWith(
      displayLarge: withKhmer(textTheme.displayLarge),
      displayMedium: withKhmer(textTheme.displayMedium),
      headlineLarge: withKhmer(textTheme.headlineLarge),
      headlineMedium: withKhmer(textTheme.headlineMedium),
      headlineSmall: withKhmer(textTheme.headlineSmall),
      titleLarge: withKhmer(textTheme.titleLarge),
      titleMedium: withKhmer(textTheme.titleMedium),
      bodyLarge: withKhmer(textTheme.bodyLarge),
      bodyMedium: withKhmer(textTheme.bodyMedium),
      bodySmall: withKhmer(textTheme.bodySmall),
      labelLarge: withKhmer(textTheme.labelLarge),
    );

    return base.copyWith(
      colorScheme: const ColorScheme.light(
        primary: AppColors.textPrimary,
        secondary: AppColors.accent,
        surface: AppColors.surface,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.background,
      textTheme: khmerTextTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.textPrimary,
        unselectedItemColor: AppColors.textTertiary,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.textPrimary,
          foregroundColor: AppColors.surface,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
        hintStyle: GoogleFonts.inter(
          color: AppColors.textTertiary,
          fontSize: 14,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceVariant,
        selectedColor: AppColors.textPrimary,
        labelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
        secondaryLabelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.surface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
          side: BorderSide.none,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
