/// Batch 1.5C.1 — cinematic hero timeline (pure state machine, testable).
///
/// ZERO-WAIT: the empty-room poster is on screen from frame 0 and the native
/// video is created immediately (never after a black splash / logo timer). The
/// logo fades in OVER the room. We reveal the video on a real "playing" event,
/// not an arbitrary deadline.
///
///   intro (poster + logo, video loading) → transform (video plays once) →
///   promise (final poster + bottom-left copy + CTA, stays forever).
///
/// Never blocks the CTA and never shows a spinner: reduced-motion / no-video /
/// ready-timeout / error all resolve straight to promise.
///
/// REPLAY is scoped to the sequence INSTANCE — the cinematic plays once per
/// PwaHeroSequence. A fresh page load / browser reload / new tab creates a new
/// instance (new sequence → plays again). A resize or widget rebuild reuses the
/// SAME instance (no restart, no duplicate). There is NO process-wide static
/// flag, so a real reload always replays and responsive rebuilds stay stable.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'pwa_hero_video.dart';

enum PwaHeroPhase { intro, transform, promise }

typedef PwaHeroVideoFactory =
    PwaHeroVideo Function({
      required VoidCallback onReady,
      required VoidCallback onEnded,
      required VoidCallback onError,
    });

/// Whether the cinematic video should play. Deliberately width-INDEPENDENT:
/// the cinematic plays on every viewport (desktop / tablet / mobile) as long as
/// the platform is web and motion is allowed. Mobile no longer skips to the
/// static poster merely because the viewport is narrow.
bool pwaHeroUseVideo({required bool isWeb, required bool reduceMotion}) =>
    isWeb && !reduceMotion;

class PwaHeroSequence extends ChangeNotifier {
  PwaHeroSequence({
    required this.useVideo,
    required PwaHeroVideoFactory createVideo,
    this.readyTimeout = const Duration(milliseconds: 900),
  }) : _createVideo = createVideo {
    _start();
  }

  /// web AND motion-allowed AND platform-supported (see [pwaHeroUseVideo]).
  final bool useVideo;
  final PwaHeroVideoFactory _createVideo;
  final Duration readyTimeout;

  PwaHeroPhase _phase = PwaHeroPhase.intro;
  PwaHeroPhase get phase => _phase;

  PwaHeroVideo? _video;
  PwaHeroVideo? get video => _video;

  bool _ready = false;
  bool get videoReady => _ready;

  bool _finished = false;
  bool get finished => _finished;

  /// Promise reached without a video ever playing (debug only).
  bool fellBackToPoster = false;

  Timer? _readyTimer;

  void _emit(PwaHeroPhase p) {
    if (_phase == p) return;
    _phase = p;
    notifyListeners();
  }

  void _start() {
    if (!useVideo) {
      // Reduced-motion / non-web / unsupported → straight to the final state.
      fellBackToPoster = true;
      _finish(disposeVideo: false);
      return;
    }
    // Poster is painted by the widget from frame 0; create + start the video
    // immediately (no logo-timer gate). Logo is a fading overlay over the room.
    _video = _createVideo(
      onReady: _onReady,
      onEnded: _onEnded,
      onError: _onError,
    );
    _video!.play();
    // No spinner: if the video has not started playing in time, keep the poster
    // and reveal the final hero.
    _readyTimer = Timer(readyTimeout, () {
      if (!_ready && !_finished) {
        fellBackToPoster = true;
        _finish();
      }
    });
  }

  /// Fired on a real "playing" event (a usable frame is on screen).
  void _onReady() {
    if (_finished) return;
    _ready = true;
    _readyTimer?.cancel();
    _emit(PwaHeroPhase.transform);
  }

  void _onEnded() => _finish();

  void _onError() {
    fellBackToPoster = true;
    _finish();
  }

  /// User skip (tap / Enter / Space / Esc).
  void skip() => _finish();

  void _finish({bool disposeVideo = true}) {
    if (_finished) return;
    _finished = true;
    _readyTimer?.cancel();
    _video?.pause();
    _emit(PwaHeroPhase.promise);
    if (disposeVideo && _video != null) {
      final v = _video;
      _video = null;
      scheduleMicrotask(() => v?.dispose());
    }
  }

  void onHidden() {
    if (!_finished) _video?.pause();
  }

  void onVisible() {
    if (!_finished && _phase == PwaHeroPhase.transform) _video?.play();
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    _video?.dispose();
    super.dispose();
  }
}
