/// AYDEN Part A — Reveal engine (A2): the on-screen renderer.
///
/// Renders the before/after reveal against a [RevealController] (A1, the single
/// source of `progress`/`zoom`). Premium, sober, deterministic:
///   • horizontal feathered sweep via `ShaderMask` + `BlendMode.dstIn`
///     (alpha-only — never a visible colour band / glow / grade);
///   • a single shared `Transform.scale` push (≤ profile zoom) on the WHOLE
///     pile → both layers crop identically → geometry preserved;
///   • `ClipRect` contains the overscan;
///   • AUTO cinematic = no chrome; MANUAL = crisp edge + divider + handle.
///
/// Isolated: depends only on the pure reveal engine. Does NOT touch
/// `RevealHero`/`RevealCanvas`. Wired into a surface behind a feature flag.
library;

import 'package:flutter/material.dart';

import 'reveal_controller.dart';
import 'reveal_profile.dart';

/// Interaction model for the reveal surface (kept separate from RevealHero's
/// `RevealDragMode` to avoid any coupling).
enum RevealInteraction { none, handle, surface }

class RevealWidget extends StatefulWidget {
  final Widget afterImage;
  final Widget? beforeImage;

  /// Timeline to play. Defaults to the Part A cinematic reveal.
  final RevealProfile profile;

  /// Optional external controller (e.g. shared with a fullscreen view in A4).
  /// When null, the widget owns and disposes its own controller.
  final RevealController? controller;

  /// Auto-play the profile once when first shown.
  final bool autoPlay;

  final RevealInteraction interaction;

  final bool showLabels;
  final String? beforeLabel;
  final String? afterLabel;

  const RevealWidget({
    super.key,
    required this.afterImage,
    this.beforeImage,
    this.profile = RevealProfile.cinematic,
    this.controller,
    this.autoPlay = true,
    this.interaction = RevealInteraction.surface,
    this.showLabels = false,
    this.beforeLabel,
    this.afterLabel,
  });

  @override
  State<RevealWidget> createState() => _RevealWidgetState();
}

class _RevealWidgetState extends State<RevealWidget>
    with TickerProviderStateMixin {
  RevealController? _owned;
  late RevealController _controller;

  bool get _hasBefore => widget.beforeImage != null;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _owned = RevealController(vsync: this, profile: widget.profile);
      _controller = _owned!;
    }

    if (_hasBefore && widget.autoPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.play();
      });
    }
  }

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d, double width) {
    if (width <= 0) return;
    _controller.scrubTo(_controller.progress - d.delta.dx / width);
  }

  @override
  Widget build(BuildContext context) {
    // No before image ⇒ just the after, no reveal machinery (graceful, matches
    // RevealHero's null behaviour).
    if (!_hasBefore) return widget.afterImage;

    return ClipRect(
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final manual = _controller.mode == RevealMode.manual;
          final feather = manual ? 0.0 : widget.profile.feather;
          final progress = _controller.progress;

          return Transform.scale(
            scale: _controller.zoom,
            alignment: Alignment.center,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final revealLineX = (1.0 - progress).clamp(0.0, 1.0) * width;

                final layers = <Widget>[
                  // After — full-bleed base.
                  Positioned.fill(child: widget.afterImage),

                  // Before — feathered sweep (alpha-only mask).
                  Positioned.fill(
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (rect) =>
                          _sweepGradient(progress, feather).createShader(rect),
                      child: widget.beforeImage,
                    ),
                  ),
                ];

                // Chrome — manual mode only (auto cinematic stays clean).
                if (manual) {
                  // Clamp so the chrome stays fully on-screen at the edges —
                  // notably when the reveal settles on AFTER (line at x≈0) the
                  // handle parks visibly at the left as a "still draggable" cue.
                  final dividerX = (revealLineX - 0.5).clamp(0.0, width - 1);
                  final handleX =
                      (revealLineX - 17).clamp(0.0, (width - 34).clamp(0.0, width));
                  layers.add(Positioned(
                    left: dividerX,
                    top: 0,
                    bottom: 0,
                    width: 1,
                    child: const ColoredBox(
                      key: Key('reveal_divider'),
                      color: Color(0xE6FFFFFF),
                    ),
                  ));
                  layers.add(Positioned(
                    left: handleX,
                    top: 0,
                    bottom: 0,
                    width: 34,
                    child: const Center(child: _RevealHandle()),
                  ));
                }

                if (widget.showLabels && widget.beforeLabel != null) {
                  layers.add(Positioned(
                    top: 14,
                    left: 14,
                    child: _Label(widget.beforeLabel!),
                  ));
                }
                if (widget.showLabels && widget.afterLabel != null) {
                  layers.add(Positioned(
                    top: 14,
                    right: 14,
                    child: _Label(widget.afterLabel!),
                  ));
                }

                var stack = Stack(fit: StackFit.expand, children: layers);

                if (widget.interaction == RevealInteraction.surface) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (d) => _onDragUpdate(d, width),
                    onHorizontalDragEnd: (_) => _controller.releaseSnap(),
                    child: stack,
                  );
                }
                if (widget.interaction == RevealInteraction.handle) {
                  const hit = 44.0;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      stack,
                      Positioned(
                        left: (revealLineX - hit / 2)
                            .clamp(0.0, (width - hit).clamp(0.0, width)),
                        top: 0,
                        bottom: 0,
                        width: hit,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragUpdate: (d) => _onDragUpdate(d, width),
                          onHorizontalDragEnd: (_) => _controller.releaseSnap(),
                        ),
                      ),
                    ],
                  );
                }
                return stack;
              },
            ),
          );
        },
      ),
    );
  }

  /// Horizontal alpha gradient: BEFORE kept (opaque) on the left up to the
  /// reveal line, feathered to transparent over [feather] width, AFTER (the
  /// transparent region) on the right. Endpoints special-cased so progress 0/1
  /// are exactly full BEFORE / full AFTER; interior stops clamped & monotone.
  LinearGradient _sweepGradient(double progress, double feather) {
    const opaque = Color(0xFFFFFFFF);
    const clear = Color(0x00FFFFFF);
    final line = (1.0 - progress).clamp(0.0, 1.0);

    if (line <= 0.0) {
      return const LinearGradient(colors: [clear, clear]);
    }
    if (line >= 1.0) {
      return const LinearGradient(colors: [opaque, opaque]);
    }

    final half = feather / 2.0;
    var s1 = (line - half).clamp(0.0, 1.0);
    var s2 = (line + half).clamp(0.0, 1.0);
    if (s2 - s1 < 1e-4) s2 = (s1 + 1e-4).clamp(0.0, 1.0); // hard-edge safety

    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      stops: [0.0, s1, s2, 1.0],
      colors: const [opaque, opaque, clear, clear],
    );
  }
}

class _RevealHandle extends StatelessWidget {
  const _RevealHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('reveal_handle'),
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chevron_left, size: 13, color: Color(0xFF1C1C1C)),
          Icon(Icons.chevron_right, size: 13, color: Color(0xFF1C1C1C)),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
