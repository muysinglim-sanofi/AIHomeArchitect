/// Web-only: register the bundled product typefaces before the first frame.
///
/// Imported ONLY by `main_pwa` (the web entrypoint), like `pwa_khmer_font.dart`
/// and `pwa_web_navigation.dart` — it pulls in `package:web` / `dart:js_interop`,
/// which the VM that runs `flutter test` does not have and which must never be
/// reached from the widget tree or the mobile entrypoint.
///
/// WHY THE FILES LIVE IN `web/` AND NOT `assets/`
///
/// `pubspec.yaml` is SHARED with the frozen mobile app. Declaring these fonts as
/// Flutter assets would ship ~300 KB into an iOS binary that neither needs them
/// nor is allowed to change. `web/` is copied into `build/web` and served as
/// static files; nothing in it is ever packaged into a mobile bundle. This is
/// the same reasoning — and the same mechanism — the Khmer font already uses.
///
/// WHY BUNDLED AND NOT FETCHED
///
/// `google_fonts` fetches from `fonts.gstatic.com` at runtime, and
/// `pwaDisableRemoteFonts()` deliberately forbids that. Three reasons it stays
/// forbidden: a paywall that blocks on a third-party CDN is a paywall that
/// breaks behind a firewall; a Cambodia-first product should not depend on a
/// round trip to Google for its first paint; and the flash of un-styled text
/// while a display face downloads is exactly the "not the same product" feeling
/// this whole alignment exists to remove.
///
/// VARIABLE FONTS
///
/// Both files carry a `wght` axis, so ONE file covers every weight the design
/// uses. Flutter maps `TextStyle.fontWeight` onto that axis for a registered
/// variable font, and `pwa_type.dart` additionally states the axis explicitly
/// via `fontVariations` so the weight is deterministic rather than inferred.
library;

import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import '../presentation/pwa_type.dart' show kPwaDisplayFamily, kPwaTextFamily;

/// Relative on purpose: the PWA is served from the origin root in staging but
/// must keep working under a sub-path, and an absolute `/fonts/...` would break
/// there. Same rule as the Khmer font.
const Map<String, String> _kFontFiles = {
  kPwaDisplayFamily: 'fonts/CormorantGaramond-Latin.ttf',
  kPwaTextFamily: 'fonts/Inter-Latin.ttf',
};

/// Load and register the product typefaces.
///
/// Returns the families that are actually available. NEVER throws and never
/// blocks the app: a missing or unreachable file degrades to the platform
/// default face — which is exactly what the PWA looked like before this phase —
/// rather than to a blank page. `pwa_type.dart` names the fallbacks that catch
/// it, so a failed load is ugly, not broken.
Future<Set<String>> loadPwaFonts() async {
  final loaded = <String>{};
  await Future.wait(_kFontFiles.entries.map((entry) async {
    if (await _register(entry.key, entry.value)) loaded.add(entry.key);
  }));
  return loaded;
}

Future<bool> _register(String family, String url) async {
  try {
    final response = await web.window.fetch(url.toJS).toDart;
    if (!response.ok) return false;

    final buffer = await response.arrayBuffer().toDart;
    final bytes = buffer.toDart.asUint8List();
    // A 404 page is a few hundred bytes of HTML and would register as a font
    // with no glyphs — worse than not registering at all, because the fallback
    // chain would never be consulted.
    if (bytes.lengthInBytes < 4096) return false;

    final loader = FontLoader(family)
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
    return true;
  } catch (_) {
    // Deliberately silent about the reason and deliberately non-fatal.
    return false;
  }
}
