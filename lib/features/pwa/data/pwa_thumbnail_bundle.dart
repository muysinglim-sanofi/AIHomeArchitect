/// Web-only: serve the Create flow's SELECTION cards as small derivatives.
///
/// Imported ONLY by `main_pwa` (the web entrypoint), like `pwa_fonts.dart` —
/// it pulls in `package:web` / `dart:js_interop`, which the VM that runs
/// `flutter test` does not have.
///
/// THE MEASUREMENT THAT MOTIVATED IT
///
/// Step 2 and Step 3 draw their cards at about 165 × 137 dp. The art behind
/// them is production photography, and every file is a lossless PNG:
///
/// ```
///   assets/cards/rooms/*.png            2.4 – 2.9 MB each  (13 files)
///   assets/cards/atmospheres/*.png      2.2 – 3.0 MB each  ( 6 files)
///   assets/branding/ayden_decide_card   2.1 MB
///   assets/atmospheres/ayden_signature  2.2 MB
///   ────────────────────────────────────────────────────
///   49.5 MB, to fill a grid of thumbnails.
/// ```
///
/// That is the whole of the "cards appear black and the images arrive much
/// later" report: nothing is stuck, 2.5 MB is simply a long time to spend on a
/// 330 px picture. No spinner and no prefetch fixes a number that size — the
/// bytes have to be smaller. Re-encoded at 640 px wide as WebP q82 the same
/// 22 files are **0.90 MB in total (1.8%)**, and 640 is still 2× the largest
/// place any of them is drawn, so nothing is upscaled on a retina phone.
///
/// WHY IT IS AN ASSET-BUNDLE OVERRIDE
///
/// The cards are FROZEN iOS widgets (`RoomCard`, `AiActionCard`,
/// `AtmosphereHeroCard`) and they call `Image.asset(...)` with the canonical
/// asset path. Neither the widgets nor the paths may change. But `Image.asset`
/// resolves through `DefaultAssetBundle.of(context)`, so wrapping the web app
/// in a bundle that answers those particular keys differently redirects the
/// load without a single frozen line moving — and without `pubspec.yaml`,
/// which is shared with the mobile app and would have shipped the derivatives
/// into an iOS binary that neither needs them nor is allowed to change.
///
/// FAIL-OPEN, ALWAYS. A missing or unreachable derivative falls straight back
/// to the real asset. The worst case is exactly what the build did before.
library;

import 'dart:js_interop';
import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

/// The asset families that are only ever drawn as small selection cards.
///
/// Deliberately NOT a blanket rule over `assets/`: a render, a showcase image
/// or the paywall's hero is displayed large, and swapping those for a 640 px
/// derivative would be a quality regression rather than an optimisation.
const List<String> _kThumbnailPrefixes = [
  'assets/cards/rooms/',
  'assets/cards/atmospheres/',
];

/// Two single files that belong to the same grids.
const Map<String, String> _kThumbnailFiles = {
  'assets/atmospheres/ayden_signature.jpg':
      'thumbs/atmospheres__ayden_signature.webp',
  'assets/branding/ayden_decide_card.png':
      'thumbs/branding__ayden_decide_card.webp',
};

/// `assets/cards/rooms/kitchen.png` → `thumbs/cards__rooms__kitchen.webp`.
String? pwaThumbnailFor(String assetKey) {
  final direct = _kThumbnailFiles[assetKey];
  if (direct != null) return direct;
  for (final prefix in _kThumbnailPrefixes) {
    if (!assetKey.startsWith(prefix)) continue;
    final rel = assetKey.substring('assets/'.length);
    final stem = rel.substring(0, rel.lastIndexOf('.'));
    return 'thumbs/${stem.replaceAll('/', '__')}.webp';
  }
  return null;
}

class PwaThumbnailBundle extends CachingAssetBundle {
  PwaThumbnailBundle(this._inner);

  final AssetBundle _inner;

  /// One in-flight fetch per key, and a negative cache: a derivative that is
  /// not there must not be re-requested once per card per rebuild.
  final Set<String> _missing = <String>{};

  @override
  Future<ByteData> load(String key) async {
    final thumb = pwaThumbnailFor(key);
    if (thumb != null && !_missing.contains(thumb)) {
      try {
        final response = await web.window.fetch(thumb.toJS).toDart;
        if (response.ok) {
          final buffer = await response.arrayBuffer().toDart;
          final bytes = buffer.toDart.asUint8List();
          // A 404 page is a few hundred bytes of HTML and would decode as
          // nothing at all — worse than falling back, because the fallback
          // would never be consulted.
          if (bytes.lengthInBytes > 512) {
            return ByteData.sublistView(bytes);
          }
        }
        _missing.add(thumb);
      } catch (_) {
        _missing.add(thumb);
      }
    }
    return _inner.load(key);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) =>
      _inner.loadString(key, cache: cache);
}
