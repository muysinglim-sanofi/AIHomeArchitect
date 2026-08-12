/// Web-only: register the bundled Khmer font before the first frame.
///
/// Imported ONLY by `main_pwa` (the web entrypoint), like
/// `pwa_web_navigation.dart` — it pulls in `package:web` / `dart:js_interop`,
/// which are unavailable to the VM that runs `flutter test` and must never be
/// reached from the widget tree or the mobile entrypoint.
///
/// WHY THIS EXISTS
///
/// The PWA renders with CanvasKit, which does not use the browser's system
/// fonts. When it meets a code point no loaded font covers, Flutter fetches a
/// Noto fallback from `fonts.gstatic.com` at runtime. That was measured working
/// — and measured being too late: the language menu painted ភាសាខ្មែរ as nine
/// tofu boxes, then painted correctly once the download landed. Every cold load
/// of a Cambodia-first product would show that flash, and a blocked or slow CDN
/// would make it permanent.
///
/// Registering the font here removes the round trip entirely: Khmer is correct
/// on the first frame, offline, with no third party involved.
///
/// The file lives in `web/fonts/` — served as a static asset, never packaged
/// into the mobile binary, `pubspec.yaml` untouched. See `web/fonts/README.md`.
library;

import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import '../presentation/pwa_theme.dart' show kPwaKhmerFamily;

/// Relative on purpose: the PWA is served from the origin root in staging but
/// must keep working under a sub-path, and an absolute `/fonts/...` would break
/// there.
const String _kKhmerFontUrl = 'fonts/NotoSansKhmer-Regular.ttf';

/// Loads the Khmer font and registers it under [kPwaKhmerFamily].
///
/// Returns true when the family is available. NEVER throws and never blocks the
/// app: if the file is missing or the fetch fails, the app still starts and
/// Flutter's own remote fallback remains as the second line of defence — a
/// degraded first paint is much better than a blank page.
Future<bool> loadPwaKhmerFont() async {
  try {
    final response = await web.window.fetch(_kKhmerFontUrl.toJS).toDart;
    if (!response.ok) return false;

    final buffer = await response.arrayBuffer().toDart;
    final bytes = buffer.toDart.asUint8List();
    if (bytes.lengthInBytes < 1024) return false; // a 404 page, not a font

    final loader = FontLoader(kPwaKhmerFamily)
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
    return true;
  } catch (_) {
    // Deliberately silent about the reason and deliberately non-fatal.
    return false;
  }
}
