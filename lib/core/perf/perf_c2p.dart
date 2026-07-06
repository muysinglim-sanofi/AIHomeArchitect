import 'package:flutter/foundation.dart';

/// PR0 (2026-07-06) — Click-to-pixel telemetry.
///
/// OBSERVABILITY ONLY. This module changes NO UX, network, cache, polling,
/// thumbnail, or generation behaviour — it only records monotonic durations and
/// emits one `[PerfC2P]` log line per generation, so the real tap → first
/// visible frame can be measured (the backend `total_ms` is server-side only).
///
/// Keyed by `request_id` (the SAME id the client sends to /generate and the
/// backend echoes back + logs in `[PERF SUMMARY]`), so a Flutter line and a
/// backend line can be correlated. Durations use a monotonic [Stopwatch], never
/// wall-clock. The first-visible-frame is recorded EXACTLY ONCE per request_id.
class PerfC2P {
  PerfC2P._();
  static final PerfC2P instance = PerfC2P._();

  /// Bounds memory: advisory/error/aborted generations never reach the
  /// first-frame mark, so their entries would otherwise linger. Oldest out.
  static const int _maxTracked = 8;
  final Map<String, _C2PRequest> _reqs = {};

  /// @visibleForTesting — every real [PerfC2P] emission (one per first-frame that
  /// actually logged), so tests OBSERVE the output instead of parsing debugPrint.
  @visibleForTesting
  final List<Map<String, Object?>> emittedForTest = [];

  /// @visibleForTesting — the singleton persists across tests; reset between them.
  @visibleForTesting
  void resetForTest() {
    _reqs.clear();
    emittedForTest.clear();
  }

  /// Pure — parse a `Server-Timing` header into the server "app" duration (ms).
  ///
  /// Accepts e.g. `app;dur=16`, `app;dur=16.4`, `cache;dur=1, app;dur=16`.
  /// Absent / empty / malformed → null (NEVER throws). Prefers the `app`
  /// metric; falls back to the first `dur=` found.
  static double? parseServerTimingMs(String? header) {
    if (header == null) return null;
    final h = header.trim();
    if (h.isEmpty) return null;
    final durRe =
        RegExp(r'dur\s*=\s*([0-9]+(?:\.[0-9]+)?)', caseSensitive: false);
    for (final part in h.split(',')) {
      if (part.toLowerCase().contains('app')) {
        final m = durRe.firstMatch(part);
        if (m != null) return double.tryParse(m.group(1)!);
      }
    }
    final m = durRe.firstMatch(h);
    return m == null ? null : double.tryParse(m.group(1)!);
  }

  /// Tap → start the monotonic clock for [requestId]. No-op on empty id.
  void beginRequest(String requestId,
      {String genType = 'unknown', int iteration = 0}) {
    if (requestId.isEmpty) return;
    if (_reqs.length >= _maxTracked && !_reqs.containsKey(requestId)) {
      _reqs.remove(_reqs.keys.first);
    }
    _reqs[requestId] = _C2PRequest(genType: genType, iteration: iteration);
  }

  /// Just before the HTTP POST leaves the client.
  void markHttpStart(String requestId) {
    _reqs[requestId]?.clickToHttpStartMs ??=
        _reqs[requestId]?.sw.elapsedMilliseconds;
  }

  /// Backend response received. [serverAppMs] comes from the `Server-Timing`
  /// header (null if absent/malformed — never blocks).
  void markResponse(String requestId, {double? serverAppMs}) {
    final r = _reqs[requestId];
    if (r == null) return;
    r.responseMs ??= r.sw.elapsedMilliseconds;
    r.serverAppMs = serverAppMs;
  }

  /// The image bytes are decoded (not yet necessarily painted).
  void markImageLoaded(String requestId) {
    _reqs[requestId]?.imageLoadedMs ??= _reqs[requestId]?.sw.elapsedMilliseconds;
  }

  /// First VISIBLE frame (call from an `addPostFrameCallback`). Guarded to run
  /// EXACTLY ONCE per request_id: emits `[PerfC2P]` and frees the entry.
  /// Returns true iff this call performed the logging. Safe on unknown ids
  /// (returns false, never throws) so a disposed widget can't crash.
  bool markFirstVisibleFrame(String requestId) {
    final r = _reqs[requestId];
    if (r == null || r.firstFrameLogged) return false;
    r.firstFrameLogged = true;
    _emit(requestId, r, r.sw.elapsedMilliseconds);
    _reqs.remove(requestId);
    return true;
  }

  /// Drop a request that will never reach first-frame (advisory / error / abort).
  void discard(String requestId) => _reqs.remove(requestId);

  @visibleForTesting
  bool isTracking(String requestId) => _reqs.containsKey(requestId);

  void _emit(String id, _C2PRequest r, int firstFrameMs) {
    final clickToHttp = r.clickToHttpStartMs;
    final resp = r.responseMs;
    final loaded = r.imageLoadedMs;
    final clientHttp =
        (resp != null && clickToHttp != null) ? resp - clickToHttp : null;
    final respToLoaded = (loaded != null && resp != null) ? loaded - resp : null;
    final loadedToFrame = (loaded != null) ? firstFrameMs - loaded : null;
    // preview == full TODAY. Kept as two distinct fields so the future
    // progressive-image PR can measure the low-res preview separately WITHOUT
    // re-touching PR0's wiring.
    final clickToPreview = firstFrameMs;
    final clickToFull = firstFrameMs;
    // Test observer — the real emission, keyed like the log line.
    emittedForTest.add({
      'request_id': id,
      'generation_type': r.genType,
      'iteration': r.iteration,
      'server_app_ms': r.serverAppMs,
      'click_to_full_pixel_ms': clickToFull,
    });
    String v(int? x) => x == null ? 'n/a' : '$x';
    debugPrint(
      '[PerfC2P] request_id=$id  generation_type=${r.genType}  '
      'iteration=${r.iteration}  '
      'click_to_http_start_ms=${v(clickToHttp)}  '
      'client_http_ms=${v(clientHttp)}  '
      'server_app_ms=${r.serverAppMs == null ? "unknown" : r.serverAppMs!.toStringAsFixed(0)}  '
      'response_to_image_loaded_ms=${v(respToLoaded)}  '
      'image_loaded_to_first_frame_ms=${v(loadedToFrame)}  '
      'click_to_preview_pixel_ms=$clickToPreview  '
      'click_to_full_pixel_ms=$clickToFull',
    );
  }
}

class _C2PRequest {
  _C2PRequest({required this.genType, required this.iteration});
  final String genType;
  final int iteration;
  final Stopwatch sw = Stopwatch()..start();
  int? clickToHttpStartMs;
  int? responseMs;
  int? imageLoadedMs;
  double? serverAppMs;
  bool firstFrameLogged = false;
}
