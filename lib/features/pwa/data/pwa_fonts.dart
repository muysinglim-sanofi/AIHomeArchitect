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

import '../presentation/pwa_type.dart'
    show
        kPwaDisplayFamily,
        kPwaPaywallDisplayFamily,
        kPwaPaywallScriptFamily,
        kPwaTextFamily;

/// Relative on purpose: the PWA is served from the origin root in staging but
/// must keep working under a sub-path, and an absolute `/fonts/...` would break
/// there. Same rule as the Khmer font.
const Map<String, String> _kFontFiles = {
  kPwaDisplayFamily: 'fonts/CormorantGaramond-Latin.ttf',
  kPwaTextFamily: 'fonts/Inter-Latin.ttf',
};

/// The two faces the PAYWALL headline is set in, and nowhere else.
///
/// iOS composes that headline in Playfair Display with a Great Vibes accent
/// word (`paywall_sheet.dart`), and those are the only two places either face
/// appears in the product. Both are SIL OFL 1.1 — see `web/fonts/README.md`
/// and the `OFL-*.txt` beside the files — so bundling and serving them is
/// exactly what the licence is for.
///
/// LOADED SEPARATELY, AND NOT AWAITED. The product faces are awaited before the
/// first paint because a face that arrives late causes a visible reflow on
/// CanvasKit. These two are ~750 KB and belong to ONE surface that is never the
/// first screen, so making every visitor wait for them would be paying a boot
/// cost for a screen most of them never open. They are started at boot and land
/// long before anyone can reach the paywall; if they somehow have not, the
/// headline draws in the fallback chain and re-lays out when they do.
const Map<String, String> _kPaywallFontFiles = {
  kPwaPaywallDisplayFamily: 'fonts/PlayfairDisplay-Latin.ttf',
  kPwaPaywallScriptFamily: 'fonts/GreatVibes-Regular.ttf',
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

/// The paywall's two faces. Same mechanism, same guarantees, not awaited.
Future<Set<String>> loadPwaPaywallFonts() async {
  final loaded = <String>{};
  await Future.wait(_kPaywallFontFiles.entries.map((entry) async {
    if (await _register(entry.key, entry.value)) loaded.add(entry.key);
  }));
  return loaded;
}

/// The family names `google_fonts` asks for, and why they are registered here.
///
/// The PWA reuses several FROZEN iOS widgets verbatim — the atmosphere card is
/// the one a reader notices — and those state their type through
/// `AppTheme.atmosphereTitle`, i.e. `GoogleFonts.cormorantGaramond(...)`.
///
/// MEASURED, not inferred (`google_fonts` 6.3.3, `google_fonts_base.dart:114`):
///
/// ```dart
/// return textStyle.copyWith(
///   fontFamily: familyWithVariant.toString(),   // "CormorantGaramond_500"
///   fontFamilyFallback: <String>[fontFamily],   // ["CormorantGaramond"]
/// );
/// ```
///
/// The primary name is per-VARIANT and is only ever registered by the runtime
/// fetch — which `pwaDisableRemoteFonts()` forbids, on purpose. That leaves the
/// fallback, which names the family this file already registers… except
/// `AppTheme.atmosphereTitle` ends with `.copyWith(fontFamilyFallback:
/// khmerFallback)`, and `copyWith` REPLACES the list. So the one name that
/// would have resolved was overwritten by the Khmer chain, and the card
/// resolved to `sans-serif`: the right size, the right weight, the wrong face.
///
/// On iOS none of this shows, because there the fetch succeeds and registers
/// the per-variant name. This is a WEB-ONLY consequence of a web-only rule.
///
/// Registering the same bytes under those names fixes every reused iOS widget
/// at once, and touches no frozen file. The files are variable, so one file
/// covers every weight; the alias only has to make the NAME resolve.
const List<String> _kVariantSuffixes = [
  'regular', 'italic',
  '300', '300italic',
  '500', '500italic',
  '600', '600italic',
  '700', '700italic',
];

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

    // The product name first: everything the PWA writes itself asks for this.
    final names = <String>[
      family,
      for (final v in _kVariantSuffixes) '${family}_$v',
    ];
    for (final name in names) {
      final loader = FontLoader(name)
        ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
    return true;
  } catch (_) {
    // Deliberately silent about the reason and deliberately non-fatal.
    return false;
  }
}
