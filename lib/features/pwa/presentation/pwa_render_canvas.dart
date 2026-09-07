/// THE CANVAS A RENDER IS SHOWN ON — iOS's, not the render's own outline.
///
/// Round 3 fixed the orientation: a portrait photo now comes back as a
/// portrait render (1024×1536) and is framed at its measured shape instead of
/// being cover-cropped into 3:2. The phone then reported the consequence: the
/// whole result card had become a narrow 2:3 strip — "a raw portrait photo
/// pasted into the chat" — because the frame WAS the image.
///
/// Frozen iOS never lets the image be the frame. Two surfaces, two rules,
/// both read from source:
///
/// CHAT RESULT — `_GeneratedImageCard` (chat_screen.dart ~4014 / ~4140)
/// ```dart
///   final h = (MediaQuery.sizeOf(context).height * 0.52).clamp(280.0, 560.0);
///   SizedBox(height: h, child: OverflowBox(... breakoutWidth ...,
///     child: _GeneratedImageCard(...)))          // OUTER: fixed height, column width
///   ...
///   RevealCanvas(
///     ambientImage: _provider,                    // blurred cover copy (σ 28)
///     focalAspectRatio: _aspectRatio,             // INNER: decoded width/height
///     bottomScrim: false,
///     child: CachedNetworkImage(fit: BoxFit.cover)) // cover INSIDE its own aspect = no crop
///   Positioned(top: 12, right: 12, child: <expand icon>)   // relative to the OUTER
/// ```
/// `RevealCanvas` itself (shared/widgets/reveal_canvas.dart): a dark base
/// (`AppColors.textPrimary`), the ambient image `BoxFit.cover` under a
/// σ-28 blur, a 0.42 darkening veil, then `Center(AspectRatio(focal, child))`.
///
/// FULL REVEAL — `before_after_screen.dart` ~596-760
/// ```dart
///   SizedBox(height: imageH, width: double.infinity,   // OUTER: fixed block
///     child: ClipRRect(borderRadius: 22,
///       child: Stack(fit: expand, children: [
///         ImageFiltered(blur σ 36, child: _RevealImage(after, fit: cover)), // matte
///         ShaderMask(vertical fade 0 → .30 → .70 → 1, dstIn,
///           child: RevealHero(afterImage: _RevealImage(url),   // default fit: CONTAIN
///                             beforeImage: _RevealImage(url), ...)),
/// ```
/// So iOS's outer surfaces are FIXED and its inner picture is CONTAINed,
/// centred, with a blurred continuation of itself filling what it does not
/// cover. That is what this file reproduces — the chat card through the
/// shared `RevealCanvas` verbatim, the reveal through the same three layers
/// the before/after screen stacks — with the inner aspect coming from the
/// measured decode (`pwa_render_aspect.dart`), never from a constant.
///
/// Not reintroduced: `AspectRatio(3 / 2)` + `BoxFit.cover` around the image.
/// The only `AspectRatio` here is the INNER one, at the image's own ratio, so
/// `cover` inside it cuts nothing.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/reveal_canvas.dart';
import 'pwa_stored_image.dart';

/// iOS's result-card height: `(screenH * 0.52).clamp(280, 560)` — shared by
/// its loading bubble and its generated card "so the shape doesn't jump
/// between generating and generated".
double pwaRenderCanvasHeight(Size screen) =>
    (screen.height * 0.52).clamp(280.0, 560.0).toDouble();

/// iOS's Full Reveal image block: `(screenH * 0.50).clamp(340, 500) - 34`.
double pwaRevealBlockHeight(double boxH) =>
    ((boxH * 0.50).clamp(340.0, 500.0) - 34.0).toDouble();

enum PwaCanvasStyle {
  /// `_GeneratedImageCard`: RevealCanvas, blur 28, darken 0.42, no scrim.
  chatCard,

  /// `before_after_screen`: blur 36, no darkening, vertical fade on the
  /// foreground.
  reveal,
}

/// A stored render on its iOS canvas.
///
/// [reference] is the render's durable path (or bundle asset); it is both the
/// ambient matte and — when [child] is null — the picture itself. [aspect] is
/// the INNER frame's ratio: the measured one, or the engine's landscape until
/// measured. [child] replaces the picture inside the inner frame (the Full
/// Reveal puts its before/after slider there).
class PwaRenderCanvas extends StatelessWidget {
  const PwaRenderCanvas({
    super.key,
    required this.reference,
    required this.aspect,
    this.style = PwaCanvasStyle.chatCard,
    this.child,
  });

  final String reference;
  final double aspect;
  final PwaCanvasStyle style;
  final Widget? child;

  @override
  Widget build(BuildContext context) => PwaStoredImage(
        key: ValueKey('canvas-$reference'),
        reference: reference,
        // The canvas's own ground, while the URL is being signed: iOS's dark
        // base, so the placeholder is the canvas and not a light hole.
        placeholderColor: AppColors.textPrimary,
        // FAIL-OPEN: while the URL is being signed (or if it cannot be) the
        // provider is null — the canvas then has no blurred matte, only its
        // dark ground, and the child (the picture's placeholder, or the
        // slider) is laid out exactly the same. A signature is never allowed
        // to take the compare gesture away.
        builder: (context, provider, image) => PwaCanvasSurface(
          ambient: provider,
          aspect: aspect,
          style: style,
          child: child ?? image,
        ),
      );

  /// The inner frame's rect inside a canvas of [outer] for a render of
  /// [aspect] — what `Center(AspectRatio(aspect))` produces. Exposed so the
  /// geometry is checkable without a widget tree.
  static Rect innerRect(Size outer, double aspect) {
    double w = outer.width;
    double h = w / aspect;
    if (h > outer.height) {
      h = outer.height;
      w = h * aspect;
    }
    return Rect.fromCenter(
      center: Offset(outer.width / 2, outer.height / 2),
      width: w,
      height: h,
    );
  }
}

/// The canvas layers, given an already-resolved provider. Split out so a
/// photo held in memory (the working card) can use the same surface.
class PwaCanvasSurface extends StatelessWidget {
  const PwaCanvasSurface({
    super.key,
    required this.ambient,
    required this.aspect,
    required this.child,
    this.style = PwaCanvasStyle.chatCard,
  });

  /// The image the matte is derived from; null = no matte yet, dark ground.
  final ImageProvider? ambient;
  final double aspect;
  final Widget child;
  final PwaCanvasStyle style;

  @override
  Widget build(BuildContext context) {
    final ambient = this.ambient;
    switch (style) {
      case PwaCanvasStyle.chatCard:
        // iOS's call, argument for argument. (`RevealCanvas` already treats a
        // null ambient as "dark ground only".)
        return RevealCanvas(
          ambientImage: ambient,
          focalAspectRatio: aspect,
          bottomScrim: false,
          child: child,
        );
      case PwaCanvasStyle.reveal:
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: AppColors.textPrimary),
              // "A BoxFit.cover copy of the AFTER image, heavily blurred" —
              // rasterised once, so the slider above it costs nothing here.
              if (ambient != null)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36),
                      child: Image(
                        image: ambient,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              // iOS's vertical fade: the foreground dissolves into the matte
              // over the top and bottom 30 % of the block.
              ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.30, 0.70, 1.0],
                  colors: [
                    Colors.transparent,
                    Colors.white,
                    Colors.white,
                    Colors.transparent,
                  ],
                ).createShader(rect),
                blendMode: BlendMode.dstIn,
                child: Center(
                  child: AspectRatio(aspectRatio: aspect, child: child),
                ),
              ),
            ],
          ),
        );
    }
  }
}
