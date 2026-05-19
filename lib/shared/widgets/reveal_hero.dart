import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/scrim.dart';
import 'app_pill.dart';

/// Wave 4 — Foundation: **RevealHero** — the single shared before/after
/// compare surface.
///
/// Replaces (in later migration PRs, NOT here) the three divergent copies:
/// FTUE `_RevealSlide`, Home `_HeroSlide`, Reveal `_CompareView`. Built to be
/// the long-term emotional core for Homepage, FTUE, the Reveal screen, the
/// Wave 4.4 cinematic viewer and future branching compares — so it is
/// deliberately screen-agnostic (no FTUE/Home/Reveal-specific logic).
///
/// Design intent: cinematic, immersive, architecture-first — not a technical
/// compare tool. Minimal chrome, shadowless, calm.
///
/// Fraction semantics (kept identical to all three existing implementations so
/// migration is 1:1): [fraction] is the portion of the width, from the LEFT,
/// that shows the BEFORE image. `afterImage` is the full-bleed base layer;
/// `beforeImage` is revealed clipped to the left `fraction * width`.
///
/// Image API is widget-based on purpose: callers pass already-built image
/// widgets (asset `Image`, `CachedNetworkImage`, `Hero`, etc.) sized to fill —
/// the component owns only the clip, divider, handle, labels, scrim, overlay
/// and the optional auto-sweep. This keeps it free of any image-source
/// assumption.
///
/// Graceful fallback: if [beforeImage] is null the widget renders the after
/// image alone — no divider, no handle, no gestures, no auto-sweep (matches
/// the wave-4.8.3 reveal null/empty behaviour).
enum RevealDragMode {
  /// Only the divider/handle strip is draggable; the rest of the surface lets
  /// a parent `PageView` / scrollable own the horizontal gesture. **Default —
  /// the gesture-safe choice** (resolves the audit's PageView ↔ drag trap).
  handle,

  /// The whole surface is draggable. Use only in contexts with no competing
  /// horizontal-swipe parent (e.g. a dedicated fullscreen reveal).
  surface,

  /// Not interactive — display + optional auto-sweep only.
  none,
}

enum RevealVariant { full, compact }

class RevealHero extends StatefulWidget {
  final Widget afterImage;
  final Widget? beforeImage;

  /// Portion of width (from left) initially showing BEFORE. 0.30 ⇒ 70% after
  /// visible (AI result is the dominant first impression).
  final double initialFraction;

  /// Subtle, interruptible auto reveal. Ignored if [beforeImage] is null.
  final bool autoSweep;
  final Duration autoSweepDelay;

  final RevealDragMode dragMode;
  final RevealVariant variant;

  /// If set, the surface is wrapped in an `AspectRatio`; otherwise it fills
  /// the parent's constraints (caller controls height).
  final double? aspectRatio;

  /// Clip radius. `null` ⇒ no clipping (caller decides) — keeps the component
  /// free of a screen-specific radius assumption.
  final BorderRadiusGeometry? borderRadius;

  final String? beforeLabel;
  final String? afterLabel;
  final bool showLabels;

  /// Optional editorial/atmosphere/CTA content pinned to the bottom.
  final Widget? overlay;

  /// Render an `AppScrim` behind [overlay] for legibility (default: on when an
  /// overlay is supplied).
  final bool overlayScrim;

  const RevealHero({
    super.key,
    required this.afterImage,
    this.beforeImage,
    this.initialFraction = 0.30,
    this.autoSweep = true,
    this.autoSweepDelay = const Duration(milliseconds: 800),
    this.dragMode = RevealDragMode.handle,
    this.variant = RevealVariant.full,
    this.aspectRatio,
    this.borderRadius,
    this.beforeLabel,
    this.afterLabel,
    this.showLabels = true,
    this.overlay,
    this.overlayScrim = true,
  });

  @override
  State<RevealHero> createState() => _RevealHeroState();
}

class _RevealHeroState extends State<RevealHero>
    with SingleTickerProviderStateMixin {
  late double _fraction;
  bool _userInteracted = false;

  AnimationController? _sweepCtrl;
  Animation<double>? _sweepAnim;

  bool get _hasBefore => widget.beforeImage != null;

  @override
  void initState() {
    super.initState();
    _fraction = widget.initialFraction.clamp(0.02, 0.98);

    if (_hasBefore && widget.autoSweep && widget.dragMode != RevealDragMode.none) {
      final start = _fraction;
      _sweepCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2800),
      );
      // Subtle, non-gimmicky: nudge open → reveal → settle slightly open.
      _sweepAnim = TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween(begin: start, end: 0.66)
              .chain(CurveTween(curve: Curves.easeInOutCubic)),
          weight: 50,
        ),
        TweenSequenceItem(tween: ConstantTween(0.66), weight: 12),
        TweenSequenceItem(
          tween: Tween(begin: 0.66, end: 0.42)
              .chain(CurveTween(curve: Curves.easeInOutCubic)),
          weight: 38,
        ),
      ]).animate(_sweepCtrl!);

      _sweepAnim!.addListener(() {
        if (!_userInteracted && mounted) {
          setState(() => _fraction = _sweepAnim!.value);
        }
      });

      Future.delayed(widget.autoSweepDelay, () {
        if (mounted && !_userInteracted) _sweepCtrl?.forward();
      });
    }
  }

  @override
  void dispose() {
    _sweepCtrl?.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails _) {
    _sweepCtrl?.stop();
    _userInteracted = true;
  }

  void _onDragUpdate(DragUpdateDetails d, double width) {
    if (width <= 0) return;
    setState(() {
      _fraction = (_fraction + d.delta.dx / width).clamp(0.02, 0.98);
    });
  }

  double get _handleSize =>
      widget.variant == RevealVariant.compact ? 30 : 38;

  @override
  Widget build(BuildContext context) {
    Widget content = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final divX = _fraction * width;

        final layers = <Widget>[
          // After — full-bleed base layer.
          Positioned.fill(child: widget.afterImage),
        ];

        if (_hasBefore) {
          // Before — revealed, clipped to the left divX pixels. OverflowBox
          // lets the image render at full width inside the clip.
          layers.add(Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: divX,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: width,
                maxWidth: width,
                child: widget.beforeImage!,
              ),
            ),
          ));

          // Subtle divider — a clean hairline, no shadow.
          layers.add(Positioned(
            left: divX - 1,
            top: 0,
            bottom: 0,
            width: 2,
            child: Container(color: Colors.white.withValues(alpha: 0.9)),
          ));

          // Handle — shadowless ring (spine baseline), not a lifted chip.
          layers.add(Positioned(
            left: divX - _handleSize / 2,
            top: 0,
            bottom: 0,
            width: _handleSize,
            child: Center(child: _RevealHandle(size: _handleSize)),
          ));
        }

        // Optional overlay + its scrim.
        if (widget.overlay != null) {
          if (widget.overlayScrim) {
            layers.add(const Positioned.fill(
              child: AppScrim(
                edge: ScrimEdge.bottom,
                opacity: 0.55,
                extent: 0.55,
              ),
            ));
          }
          layers.add(Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: widget.overlay!,
          ));
        }

        // Optional labels (shared AppPill — never local pills).
        if (widget.showLabels && widget.beforeLabel != null) {
          layers.add(Positioned(
            top: 14,
            left: 14,
            child: AppPill(text: widget.beforeLabel!),
          ));
        }
        if (widget.showLabels && widget.afterLabel != null) {
          layers.add(Positioned(
            top: 14,
            right: 14,
            child: AppPill(text: widget.afterLabel!, dark: true),
          ));
        }

        // ── Gesture ownership ─────────────────────────────────────────────
        // handle  → only a 44px strip on the divider is draggable; the rest
        //           of the surface ignores horizontal drags so a parent
        //           PageView / scrollable owns the swipe (no gesture trap).
        // surface → whole surface draggable (no competing parent only).
        // none    → display / auto-sweep only.
        if (_hasBefore && widget.dragMode == RevealDragMode.handle) {
          const hit = 44.0;
          layers.add(Positioned(
            left: (divX - hit / 2).clamp(0.0, (width - hit).clamp(0.0, width)),
            top: 0,
            bottom: 0,
            width: hit,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: _onDragStart,
              onHorizontalDragUpdate: (d) => _onDragUpdate(d, width),
            ),
          ));
        }

        final stack = Stack(fit: StackFit.expand, children: layers);

        if (_hasBefore && widget.dragMode == RevealDragMode.surface) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: (d) => _onDragUpdate(d, width),
            child: stack,
          );
        }
        return stack;
      },
    );

    if (widget.aspectRatio != null) {
      content = AspectRatio(aspectRatio: widget.aspectRatio!, child: content);
    }
    if (widget.borderRadius != null) {
      content = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: content,
      );
    }
    return content;
  }
}

class _RevealHandle extends StatelessWidget {
  final double size;
  const _RevealHandle({required this.size});

  @override
  Widget build(BuildContext context) {
    final icon = size <= 32 ? 12.0 : 14.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chevron_left, size: icon, color: AppColors.textPrimary),
          Icon(Icons.chevron_right, size: icon, color: AppColors.textPrimary),
        ],
      ),
    );
  }
}
