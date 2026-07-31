/// Batch 1.5C — web implementation of the hero video boundary: a real native
/// HTML `<video>` (muted, autoplay, playsinline, no controls, no loop) hosted in
/// Flutter via `HtmlElementView`. No Flutter dependency — uses `dart:ui_web` +
/// `package:web` (both available on web; never compiled on mobile/iOS).
library;

import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
// `web` ships with the Flutter web engine (transitive); we intentionally do NOT
// add it to pubspec (no dependency change for this batch).
// ignore: depend_on_referenced_packages
import 'package:web/web.dart' as web;

import 'pwa_hero_video.dart';

int _counter = 0;

class _WebHeroVideo implements PwaHeroVideo {
  _WebHeroVideo({
    required String mp4,
    String? webm,
    required String poster,
    required String objectPosition,
    required this.onReady,
    required this.onEnded,
    required this.onError,
  }) : _viewType = 'ayden-hero-video-${_counter++}' {
    _video = web.HTMLVideoElement()
      ..muted = true
      ..autoplay = true
      ..controls = false
      ..loop = false
      ..poster = poster
      ..preload = 'auto';
    _video.setAttribute('playsinline', 'true');
    _video.setAttribute('webkit-playsinline', 'true');
    _video.setAttribute('disablepictureinpicture', 'true');
    _video.setAttribute('disableremoteplayback', 'true');
    _video.style.setProperty('width', '100%');
    _video.style.setProperty('height', '100%');
    _video.style.setProperty('object-fit', 'cover');
    // Form-factor crop focal point (portrait mobile biases up toward the room).
    _video.style.setProperty('object-position', objectPosition);
    _video.style.setProperty('border', '0');

    if (webm != null) {
      _video.appendChild(
        web.HTMLSourceElement()
          ..src = webm
          ..type = 'video/webm',
      );
    }
    _video.appendChild(
      web.HTMLSourceElement()
        ..src = mp4
        ..type = 'video/mp4',
    );

    _readyJs = ((web.Event _) => onReady()).toJS;
    _endedJs = ((web.Event _) => onEnded()).toJS;
    _errorJs = ((web.Event _) => onError()).toJS;
    // Reveal only on a real "playing" event (a usable frame is on screen), not
    // merely when the element was created.
    _video.addEventListener('playing', _readyJs);
    _video.addEventListener('ended', _endedJs);
    _video.addEventListener('error', _errorJs);
    _video.addEventListener('stalled', _errorJs);

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int _) => _video,
    );
  }

  final String _viewType;
  late final web.HTMLVideoElement _video;
  final VoidCallback onReady;
  final VoidCallback onEnded;
  final VoidCallback onError;
  late final JSFunction _readyJs;
  late final JSFunction _endedJs;
  late final JSFunction _errorJs;
  bool _disposed = false;

  @override
  bool get isSupported => true;

  @override
  Widget buildView() => HtmlElementView(viewType: _viewType);

  @override
  void play() {
    if (_disposed) return;
    // Muted autoplay is permitted; ignore the returned promise. If it is
    // rejected the readiness timeout / error handler drives the fallback.
    _video.play();
  }

  @override
  void pause() {
    if (_disposed) return;
    _video.pause();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _video.removeEventListener('playing', _readyJs);
    _video.removeEventListener('ended', _endedJs);
    _video.removeEventListener('error', _errorJs);
    _video.removeEventListener('stalled', _errorJs);
    _video.pause();
    _video.removeAttribute('src');
    while (_video.firstChild != null) {
      _video.removeChild(_video.firstChild!);
    }
    _video.load(); // release the decoder
  }
}

PwaHeroVideo createPwaHeroVideo({
  required String mp4,
  String? webm,
  required String poster,
  String objectPosition = 'center center',
  required VoidCallback onReady,
  required VoidCallback onEnded,
  required VoidCallback onError,
}) => _WebHeroVideo(
  mp4: mp4,
  webm: webm,
  poster: poster,
  objectPosition: objectPosition,
  onReady: onReady,
  onEnded: onEnded,
  onError: onError,
);
