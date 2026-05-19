import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/scrim.dart';

/// Wave 4 — Foundation: **RevealCanvas** — the shared immersive image surface.
///
/// The ambient emotional *environment* that wraps a focal surface (typically a
/// [RevealHero], but any image widget works). It exists so the reveal never
/// feels boxed / letterboxed / floating in a black void — the audit's
/// "emotional climax floats in emptiness" finding.
///
/// Clear responsibility split (kept deliberately):
///   • RevealCanvas → immersive framing, ambient backdrop, scrim
///     orchestration, safe overlay zones, fullscreen-ready composition.
///   • RevealHero (the [child]) → compare logic, divider, gestures, labels,
///     auto-sweep. RevealCanvas makes NO assumption that [child] is a
///     RevealHero — it is screen/feature-agnostic.
///
/// API shape (architecture decision): the focal content is a **Widget**
/// ([child]) so any surface composes; the ambient backdrop is an
/// **ImageProvider** ([ambientImage]) because a blurred cover backdrop needs
/// the raw image. Pass the SAME provider that the focal image uses so it is
/// decoded once (shared in the image cache) — no double decode.
///
/// Performance: the backdrop is a *static* [ImageFiltered] image inside a
/// [RepaintBoundary] — the blur is rasterised once and is NOT recomputed when
/// the focal child repaints (e.g. every RevealHero drag frame). No
/// [BackdropFilter] (per-frame, expensive). RevealCanvas is stateless (no
/// animation/state of its own — any breathe-beat sheet animation belongs to
/// the consuming screen, e.g. Wave 4.5).
class RevealCanvas extends StatelessWidget {
  /// Focal content — usually a `RevealHero`. Owns its own gestures.
  final Widget child;

  /// Image the ambient blurred backdrop is derived from (usually the same
  /// result image shown in [child]). Null ⇒ a calm solid-ink backdrop (a
  /// premium near-black, never a harsh "dead" void).
  final ImageProvider? ambientImage;

  /// If set, [child] is centred at this aspect ratio over the ambient
  /// backdrop (a landscape render in a portrait viewport now has cinematic
  /// depth instead of black bands). Null ⇒ [child] fills the canvas (most
  /// immersive — no backdrop gaps).
  final double? focalAspectRatio;

  /// Backdrop blur sigma. Subtle by default; clamped to avoid jank/abuse.
  final double ambientBlur;

  /// Mute toward ink (0–1) so focus stays on [child]; keeps the backdrop
  /// atmospheric, not a busy duplicate. No glow / gaming effects.
  final double ambientDarken;

  /// Top scrim (e.g. behind a transparent app bar / back control / title).
  final bool topScrim;

  /// Bottom scrim (behind [bottomOverlay] for legibility).
  final bool bottomScrim;

  /// Bottom-scrim strength. Defaults preserve the original wash (0.6 / 0.5).
  /// A consuming screen can soften it (lower opacity / tighter extent) so an
  /// already-dim render is not over-darkened, while controls still seat on a
  /// gradient. Top scrim is intentionally left fixed (it only backs a small
  /// title/back zone, never the focal mid-tones).
  final double bottomScrimOpacity;
  final double bottomScrimExtent;

  /// Safe overlay zones — editorial text, CTA, atmosphere, title. Positioned
  /// above their scrim; the caller owns the content and its own padding.
  final Widget? bottomOverlay;
  final Widget? topOverlay;

  const RevealCanvas({
    super.key,
    required this.child,
    this.ambientImage,
    this.focalAspectRatio,
    this.ambientBlur = 28,
    this.ambientDarken = 0.42,
    this.topScrim = false,
    this.bottomScrim = true,
    this.bottomScrimOpacity = 0.6,
    this.bottomScrimExtent = 0.5,
    this.bottomOverlay,
    this.topOverlay,
  });

  @override
  Widget build(BuildContext context) {
    final blur = ambientBlur.clamp(0.0, 40.0);
    final darken = ambientDarken.clamp(0.0, 1.0);

    final layers = <Widget>[
      // Base — brand ink. Even on image-load failure this reads as intentional
      // depth, never a harsh black void.
      const Positioned.fill(child: ColoredBox(color: AppColors.textPrimary)),
    ];

    // Ambient blurred backdrop (static → rasterised once, isolated).
    if (ambientImage != null) {
      layers.add(Positioned.fill(
        child: RepaintBoundary(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Image(
              image: ambientImage!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
      ));
      // Subtle ink mute so the focal image leads.
      layers.add(Positioned.fill(
        child: ColoredBox(
          color: AppColors.textPrimary.withValues(alpha: darken),
        ),
      ));
    }

    // Focal surface — fills, or centred at a fixed aspect over the backdrop.
    layers.add(
      focalAspectRatio != null
          ? Center(
              child: AspectRatio(
                aspectRatio: focalAspectRatio!,
                child: child,
              ),
            )
          : Positioned.fill(child: child),
    );

    // Scrims sit ABOVE the focal surface (legibility at the image edge) and
    // BELOW the overlays (overlay content rests on the scrim).
    if (topScrim) {
      layers.add(const Positioned.fill(
        child: AppScrim(edge: ScrimEdge.top, opacity: 0.45, extent: 0.22),
      ));
    }
    if (bottomScrim) {
      layers.add(Positioned.fill(
        child: AppScrim(
          edge: ScrimEdge.bottom,
          opacity: bottomScrimOpacity.clamp(0.0, 1.0),
          extent: bottomScrimExtent.clamp(0.0, 1.0),
        ),
      ));
    }

    if (topOverlay != null) {
      layers.add(Positioned(top: 0, left: 0, right: 0, child: topOverlay!));
    }
    if (bottomOverlay != null) {
      layers.add(
          Positioned(bottom: 0, left: 0, right: 0, child: bottomOverlay!));
    }

    return ClipRect(
      child: Stack(fit: StackFit.expand, children: layers),
    );
  }
}
