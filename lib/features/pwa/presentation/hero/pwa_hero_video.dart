/// Batch 1.5C — native web `<video>` boundary (no Flutter dependency).
///
/// Web builds get a real HTML `<video>` element via `HtmlElementView`
/// ([pwa_hero_video_web.dart]); everything else gets a stub that reports
/// unsupported so the hero falls straight to the final poster
/// ([pwa_hero_video_stub.dart]). Conditional import keeps `dart:ui_web` /
/// `package:web` out of mobile/iOS compilation entirely.
library;

import 'package:flutter/widgets.dart';

import 'pwa_hero_video_stub.dart'
    if (dart.library.js_interop) 'pwa_hero_video_web.dart'
    as impl;

// Same-origin runtime media (lives under web/media/hero, served at /media/hero;
// NOT a Flutter asset → stays out of the app-shell bundle).
const String kHeroMp4 = 'media/hero/ayden-cinematic-v1-desktop.mp4';
const String kHeroWebm = 'media/hero/ayden-cinematic-v1-desktop.webm';
const String kHeroStartPoster =
    'media/hero/ayden-cinematic-v1-start-desktop.webp';
const String kHeroEndPoster = 'media/hero/ayden-cinematic-v1-end-desktop.webp';

/// Responsive hero media contract. The video player is shared; only these
/// paths + crop values differ per form factor. When a dedicated 9:16 mobile
/// asset ships (ayden-cinematic-v1-mobile.{mp4,webm} +
/// ayden-cinematic-v1-{start,end}-mobile.webp), swap ONLY the mobile paths
/// below — no hero/player rewrite.
class PwaHeroMedia {
  const PwaHeroMedia({
    required this.mp4,
    required this.webm,
    required this.startPoster,
    required this.endPoster,
    required this.videoObjectPosition,
    required this.posterAlignment,
  });

  final String mp4;
  final String webm;
  final String startPoster;
  final String endPoster;

  /// CSS `object-position` for the native `<video>` (cover crop focal point).
  final String videoObjectPosition;

  /// Flutter [Alignment] for the poster `Image` cover crop (same focal point).
  final Alignment posterAlignment;
}

const PwaHeroMedia kHeroMediaDesktop = PwaHeroMedia(
  mp4: kHeroMp4,
  webm: kHeroWebm,
  startPoster: kHeroStartPoster,
  endPoster: kHeroEndPoster,
  videoObjectPosition: 'center center',
  posterAlignment: Alignment.center,
);

/// Mobile TEMPORARILY reuses the desktop media/posters (lightweight enough for
/// the prototype) with a portrait-friendly crop biased UP toward the
/// architectural focal (away from the floor), never exposing black/empty areas.
const PwaHeroMedia kHeroMediaMobile = PwaHeroMedia(
  mp4: kHeroMp4,
  webm: kHeroWebm,
  startPoster: kHeroStartPoster,
  endPoster: kHeroEndPoster,
  videoObjectPosition: 'center 35%',
  posterAlignment: Alignment(0, -0.3),
);

PwaHeroMedia pwaHeroMediaFor(bool isMobile) =>
    isMobile ? kHeroMediaMobile : kHeroMediaDesktop;

/// A muted, inline, non-looping native video the hero plays exactly once.
abstract class PwaHeroVideo {
  /// True only on web where a real `<video>` element was created.
  bool get isSupported;

  /// The widget that hosts the native video (or an empty box on the stub).
  Widget buildView();

  void play();
  void pause();
  void dispose();
}

/// Create the platform video. Callbacks fire on the corresponding media events;
/// on the stub they never fire (the hero uses its readiness timeout instead).
PwaHeroVideo createPwaHeroVideo({
  required String mp4,
  String? webm,
  required String poster,
  String objectPosition = 'center center',
  required VoidCallback onReady,
  required VoidCallback onEnded,
  required VoidCallback onError,
}) => impl.createPwaHeroVideo(
  mp4: mp4,
  webm: webm,
  poster: poster,
  objectPosition: objectPosition,
  onReady: onReady,
  onEnded: onEnded,
  onError: onError,
);
