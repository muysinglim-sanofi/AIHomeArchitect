import 'package:flutter/material.dart';

abstract class AppColors {
  // Backgrounds
  static const background = Color(0xFFF9F6F1);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceVariant = Color(0xFFF0ECE7);

  // Brand / Accent
  // Sprint 2A — canonical AYDEN gold (#C8A86A). Migrated from #C4A882 for one
  // consistent brand gold across the app. accentDark/Light kept (harmonious).
  static const accent = Color(0xFFC8A86A);
  static const accentDark = Color(0xFFA08060);
  static const accentLight = Color(0xFFE8D9C5);

  // Sprint 2A — AYDEN brand system tokens (branding surfaces: splash, loading).
  static const brandGold = Color(0xFFC8A86A);
  static const brandWarmBlack = Color(0xFF1E161E);
  static const brandIvory = Color(0xFFF4F1EC);

  // Text
  static const textPrimary = Color(0xFF1C1917);
  static const textSecondary = Color(0xFF78716C);
  static const textTertiary = Color(0xFFA8A29E);

  // Borders
  static const border = Color(0xFFE7E5E4);
  static const borderLight = Color(0xFFF5F3F1);

  // Status
  static const success = Color(0xFF4CAF50);
  static const error = Color(0xFFE53935);

  // Overlay
  static const overlay = Color(0x80000000);
  static const shimmerBase = Color(0xFFEDE8E3);
  static const shimmerHighlight = Color(0xFFF5F1EC);
}
