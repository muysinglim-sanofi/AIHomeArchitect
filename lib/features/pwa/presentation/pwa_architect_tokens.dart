/// Batch 2.2 — V7 Architect design tokens (isolated Design-Workspace palette).
///
/// The definitive palette sampled from `references/REF-PWA-ARCHITECT-FINAL-V7.png`.
/// Deliberately SEPARATE from the global `pwa*` / `AppColors` tokens: the frozen
/// cinematic hero, upload showroom and post-upload fast path keep their existing
/// muted gold (#C8A86A), while the Architect renders the reference's brighter
/// metallic gold (#D3B064) over warm charcoal / warm ivory. Offline only — no
/// google_fonts, no remote asset; the platform sans family carries the editorial
/// hierarchy through weight / size / tracking.
library;

import 'package:flutter/widgets.dart';
import 'pwa_theme.dart' show pwaTextFallback, pwaTracking;

// ── Warm charcoal design surfaces ────────────────────────────────────────────
const Color av7HeaderBlack = Color(0xFF080806); // global header bar
const Color av7DarkBg = Color(0xFF0D0C0A); // left design canvas / page
const Color av7Reveal = Color(0xFF15120E); // reveal frame inner bg (§8)
const Color av7RevealRaised = Color(0xFF38281B);
const Color av7MetaBg = Color(0xFF12100D); // reveal metadata strip (§9)
const Color av7PendingBg = Color(0xFF17140F); // atmosphere pending bar (§11)
const Color av7CardDark = Color(0xFF181612); // unselected atmosphere card

// ── Warm ivory conversation surfaces ─────────────────────────────────────────
const Color av7Canvas = Color(0xFFF7F3EE); // chat panel background
const Color av7Surface = Color(0xFFFFFDFC); // cards / Ayden bubbles
const Color av7Line = Color(0xFFE4DDD5); // warm hairline divider

// ── Text ─────────────────────────────────────────────────────────────────────
const Color av7Ink = Color(0xFF201B17);
const Color av7InkSecondary = Color(0xFF3B342E);
const Color av7Muted = Color(0xFF81786F);
const Color av7MutedSoft = Color(0xFFAAA198);
const Color av7OnDark = Color(0xFFFFFDFC); // primary text on dark
const Color av7OnDarkSoft = Color(0xD1FFFDFC); // ~82% white on dark
const Color av7UserText = Color(0xFFFFFDFC);

// ── Gold ─────────────────────────────────────────────────────────────────────
const Color av7Gold = Color(0xFFD3B064); // primary metallic gold
const Color av7GoldDeep = Color(0xFFA7823C);
const Color av7GoldWash = Color(0xFFF1E5C7); // soft gold wash (badges)
const Color av7UserBubble = Color(0xFF292622); // right-aligned user message

// ── Motion ───────────────────────────────────────────────────────────────────
abstract final class Av7Motion {
  static const Duration micro = Duration(milliseconds: 120);
  static const Duration component = Duration(milliseconds: 220);
  static const Duration page = Duration(milliseconds: 420);
  static const Curve curve = Curves.easeOutCubic;
}

// ── Type helpers (platform family; offline — no runtime font fetch) ───────────
//
// Every helper ends its fallback chain with the bundled Khmer family: CanvasKit
// has no system fonts to fall back on, so without it Khmer paints as tofu until
// a remote Noto download lands. See `web/fonts/README.md`.

/// Functional / conversational copy.
TextStyle av7Sans({
  required double fontSize,
  FontWeight fontWeight = FontWeight.w400,
  Color color = av7Ink,
  double height = 1.4,
  double letterSpacing = 0,
}) => TextStyle(
  fontSize: fontSize,
  fontWeight: fontWeight,
  color: color,
  height: height,
  letterSpacing: letterSpacing,
  fontFamilyFallback: pwaTextFallback,
  decoration: TextDecoration.none,
);

/// Uppercase gold eyebrow ("ATMOSPHERE", "AYDEN ARCHITECT", "DESIGN WORKSPACE").
TextStyle av7Eyebrow({
  Color color = av7Gold,
  double fontSize = 13,
  double letterSpacing = 2.1,
  FontWeight fontWeight = FontWeight.w600,
}) => TextStyle(
  fontSize: fontSize,
  fontWeight: fontWeight,
  color: color,
  // Khmer clusters must not be pulled apart — see `pwaTracking`.
  letterSpacing: pwaTracking(letterSpacing),
  fontFamilyFallback: pwaTextFallback,
  decoration: TextDecoration.none,
);
