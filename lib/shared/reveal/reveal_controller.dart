/// AYDEN Part A — Reveal engine (A1/A4).
///
/// The Flutter *glue* around the pure [RevealTimeline]. It owns the auto-play
/// [AnimationController] and a second, short controller for the release-snap,
/// and exposes one source of truth — `progress` (0=BEFORE, 1=AFTER) and `zoom`
/// — that BOTH the auto timeline and the manual scrub write to. One system.
///
/// Haptics (A4): a discreet selection click when the auto reveal settles, and
/// a light impact when a release snaps. Centralised here so every surface
/// (in-card + fullscreen) gets the same feel.
library;

import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart';

import 'reveal_easing.dart';
import 'reveal_profile.dart';
import 'reveal_timeline.dart';

enum RevealMode { auto, manual }

class RevealController extends ChangeNotifier {
  RevealController({
    required TickerProvider vsync,
    RevealProfile profile = RevealProfile.cinematic,
    this.haptics = true,
  })  : _profile = profile,
        _progress = profile.keyframes.first.progress,
        _zoom = profile.zoomFrom {
    _anim = AnimationController(vsync: vsync, duration: profile.total)
      ..addListener(_onTick)
      ..addStatusListener(_onStatus);
    _snapCtrl = AnimationController(vsync: vsync)..addListener(_onSnapTick);
  }

  /// Fire light haptics on settle / snap (A4).
  final bool haptics;

  late final AnimationController _anim;
  late final AnimationController _snapCtrl;
  RevealProfile _profile;
  RevealMode _mode = RevealMode.auto;
  double _progress;
  double _zoom;
  bool _hasAutoPlayed = false;

  // Release-snap state.
  double _snapStart = 0;
  double _snapTarget = 0;
  RevealEasing _snapEasing = RevealEasing.easeOutCubic;

  RevealProfile get profile => _profile;
  RevealMode get mode => _mode;

  /// 0 = full BEFORE, 1 = full AFTER. The single source of truth.
  double get progress => _progress;

  /// Shared push-zoom (≥ 1.0), applied identically to both layers.
  double get zoom => _zoom;

  bool get isAnimating => _anim.isAnimating;

  /// Auto-play the profile once (idempotent — use [replay] to force).
  void play() {
    if (_hasAutoPlayed) return;
    _hasAutoPlayed = true;
    replay();
  }

  /// Force a fresh auto-play from the start.
  void replay() {
    _stopSnap();
    _mode = RevealMode.auto;
    _anim
      ..duration = _profile.total
      ..forward(from: 0);
  }

  /// Manual scrub — sets progress directly, cancels auto-play / snap. Zoom is
  /// left at its current value (the push settles and stays) so the first drag
  /// after the reveal doesn't pop the scale.
  void scrubTo(double value) {
    _stopSnap();
    _mode = RevealMode.manual;
    if (_anim.isAnimating) _anim.stop();
    _progress = value.clamp(0.0, 1.0).toDouble();
    notifyListeners();
  }

  /// On drag release, gently snap to the nearest attractor **if** within the
  /// profile's threshold — assistance, not a constraint (releases away from any
  /// attractor stay exactly put).
  void releaseSnap() {
    final snap = _profile.snap;
    if (snap == null) return;
    final target = snap.resolve(_progress);
    if (target == null || (_progress - target).abs() < 1e-4) return;
    _snapStart = _progress;
    _snapTarget = target;
    _snapEasing = snap.easing;
    _snapCtrl
      ..duration = snap.duration
      ..forward(from: 0);
    if (haptics) HapticFeedback.lightImpact();
  }

  void pause() {
    if (_anim.isAnimating) _anim.stop();
    _stopSnap();
  }

  /// Swap the active profile (e.g. fullscreen vs in-card). Resets play state.
  void setProfile(RevealProfile profile) {
    _stopSnap();
    _profile = profile;
    _hasAutoPlayed = false;
    _anim.duration = profile.total;
    _progress = profile.keyframes.first.progress;
    _zoom = profile.zoomFrom;
    notifyListeners();
  }

  void _onTick() {
    final elapsed = _profile.total * _anim.value;
    final frame = RevealTimeline.sample(_profile, elapsed);
    _progress = frame.progress;
    _zoom = frame.zoom;
    notifyListeners();
  }

  void _onStatus(AnimationStatus status) {
    // When the auto reveal finishes, surface the manual chrome (handle parks at
    // the left edge once AFTER is fully revealed) + a discreet settle haptic.
    if (status == AnimationStatus.completed && _mode == RevealMode.auto) {
      _mode = RevealMode.manual;
      if (haptics) HapticFeedback.selectionClick();
      notifyListeners();
    }
  }

  void _onSnapTick() {
    final e = _snapEasing.transform(_snapCtrl.value);
    _progress = _snapStart + (_snapTarget - _snapStart) * e;
    notifyListeners();
  }

  void _stopSnap() {
    if (_snapCtrl.isAnimating) _snapCtrl.stop();
  }

  @override
  void dispose() {
    _anim
      ..removeListener(_onTick)
      ..removeStatusListener(_onStatus)
      ..dispose();
    _snapCtrl
      ..removeListener(_onSnapTick)
      ..dispose();
    super.dispose();
  }
}
