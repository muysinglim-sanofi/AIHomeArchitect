import 'package:flutter/widgets.dart';

/// In-place "magnifier" pinch-to-zoom (Option A).
///
/// Wraps [child] so a TWO-finger pinch zooms it in place, and the zoom
/// SNAPS BACK to 100% (animated) the moment the gesture ends — so a zoomed
/// image never lingers in a scrolling feed.
///
/// Pan is deliberately DISABLED so one-finger gestures fall through to the
/// parent untouched (chat list scroll, the before/after slider drag, tap and
/// long-press). Only the 2-pointer scale gesture is captured here.
class PinchZoom extends StatefulWidget {
  final Widget child;
  final double maxScale;

  const PinchZoom({super.key, required this.child, this.maxScale = 4.0});

  @override
  State<PinchZoom> createState() => _PinchZoomState();
}

class _PinchZoomState extends State<PinchZoom>
    with SingleTickerProviderStateMixin {
  final TransformationController _controller = TransformationController();
  // Created in initState (NOT a lazy `late` initializer): a lazy field would be
  // constructed on first access — and if the widget is disposed before any
  // pinch, that first access happens inside dispose(), where createTicker()
  // looks up the (now deactivated) TickerMode ancestor → crash.
  late final AnimationController _reset;
  Animation<Matrix4>? _resetAnim;

  @override
  void initState() {
    super.initState();
    _reset = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(_onResetTick);
  }

  void _onResetTick() {
    final anim = _resetAnim;
    if (anim != null) _controller.value = anim.value;
  }

  void _onInteractionStart(ScaleStartDetails _) {
    // A new pinch began before a previous snap-back finished — stop it so the
    // two don't fight over the controller.
    if (_reset.isAnimating) _reset.stop();
  }

  void _onInteractionEnd(ScaleEndDetails _) {
    if (_controller.value == Matrix4.identity()) return;
    _resetAnim = Matrix4Tween(
      begin: _controller.value,
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(parent: _reset, curve: Curves.easeOut));
    _reset.forward(from: 0);
  }

  @override
  void dispose() {
    _reset
      ..removeListener(_onResetTick)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _controller,
      panEnabled: false,
      scaleEnabled: true,
      minScale: 1.0,
      maxScale: widget.maxScale,
      onInteractionStart: _onInteractionStart,
      onInteractionEnd: _onInteractionEnd,
      child: widget.child,
    );
  }
}
