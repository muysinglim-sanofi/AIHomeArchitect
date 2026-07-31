/// Batch 1.5C — non-web stub for the hero video boundary. Reports unsupported so
/// the hero goes straight to the final poster (used on VM/tests and mobile).
library;

import 'package:flutter/widgets.dart';

import 'pwa_hero_video.dart';

class _StubHeroVideo implements PwaHeroVideo {
  @override
  bool get isSupported => false;
  @override
  Widget buildView() => const SizedBox.shrink();
  @override
  void play() {}
  @override
  void pause() {}
  @override
  void dispose() {}
}

PwaHeroVideo createPwaHeroVideo({
  required String mp4,
  String? webm,
  required String poster,
  String objectPosition = 'center center',
  required VoidCallback onReady,
  required VoidCallback onEnded,
  required VoidCallback onError,
}) => _StubHeroVideo();
