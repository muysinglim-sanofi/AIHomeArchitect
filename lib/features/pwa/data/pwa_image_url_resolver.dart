/// Turns a private Storage PATH into a temporary URL the browser can render.
///
/// The path is what gets persisted; the URL is minted here, cached while it is
/// good, and re-minted when it expires. Persisting a signed URL instead would
/// quietly give every saved project an expiry date — the project would still be
/// in the library, and its cover would be a black card.
///
/// Bundle assets pass through untouched: the mock experience keeps rendering
/// `assets/...` with `Image.asset`, unchanged.
library;

import 'dart:async';

/// Mints a signed URL for [path], valid for [expiresIn] seconds.
typedef PwaSignedUrlSigner =
    Future<String> Function(String path, int expiresIn);

/// True when [reference] is a private Storage path rather than a bundle asset.
bool pwaIsStoragePath(String reference) =>
    reference.isNotEmpty && !reference.startsWith('assets/');

class PwaImageUrlResolver {
  PwaImageUrlResolver({
    required PwaSignedUrlSigner signer,
    this.ttl = const Duration(hours: 1),
    DateTime Function()? clock,
  }) : _sign = signer,
       _now = clock ?? DateTime.now;

  final PwaSignedUrlSigner _sign;
  final Duration ttl;
  final DateTime Function() _now;

  final Map<String, _Entry> _cache = {};
  final Map<String, Future<String>> _inFlight = {};

  /// Re-minted this early before expiry, so a URL never dies mid-render.
  static const Duration _refreshMargin = Duration(minutes: 5);

  /// The URL to render [reference] with. Bundle assets are returned as-is.
  Future<String> resolve(String reference) {
    if (!pwaIsStoragePath(reference)) return Future.value(reference);

    final cached = _cache[reference];
    if (cached != null &&
        _now().isBefore(cached.goodUntil.subtract(_refreshMargin))) {
      return Future.value(cached.url);
    }
    // Collapse concurrent misses: five widgets showing one cover must not mint
    // five URLs.
    final pending = _inFlight[reference];
    if (pending != null) return pending;

    final future = _mint(reference);
    _inFlight[reference] = future;
    return future;
  }

  Future<String> _mint(String reference) async {
    try {
      final url = await _sign(reference, ttl.inSeconds);
      _cache[reference] = _Entry(url, _now().add(ttl));
      return url;
    } finally {
      _inFlight.remove(reference);
    }
  }

  /// Drops a cached URL so the next resolve mints a fresh one. Called when an
  /// image fails to load: the usual cause is an expired signature, and the fix
  /// is a new URL from the same durable path — never a fixture.
  void invalidate(String reference) => _cache.remove(reference);

  void clear() {
    _cache.clear();
    _inFlight.clear();
  }
}

class _Entry {
  const _Entry(this.url, this.goodUntil);
  final String url;
  final DateTime goodUntil;
}
