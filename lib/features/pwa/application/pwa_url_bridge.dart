/// Batch 3.4b — the injectable browser-history bridge (PWA-only).
///
/// A tiny seam over the browser History API so the durable URL can be read at
/// boot, pushed/replaced as the user navigates, and observed on Back/Forward —
/// without importing any web-only library into the widget tree (the web impl
/// lives in a file imported ONLY by `main_pwa`; tests + the offline VM use the
/// in-memory [FakePwaUrlBridge]). It never touches project data.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class PwaUrlBridge {
  /// The current browser URI (path + query).
  Uri current();

  /// Push a new durable route (a normal user navigation → a history entry).
  void push(String location);

  /// Replace the current route (boot normalization / fallback / correction —
  /// never adds a duplicate history entry).
  void replace(String location);

  /// Register the single Back/Forward (popstate) listener.
  void onPop(void Function(Uri) callback);

  void dispose();
}

/// In-memory bridge for tests + the non-web VM. Records the history stack and an
/// [ops] log so history tests can assert push/replace/back/forward deterministic-
/// ally with no real browser.
class FakePwaUrlBridge implements PwaUrlBridge {
  FakePwaUrlBridge([String initial = '/']) : _stack = [Uri.parse(initial)];

  final List<Uri> _stack;
  int _index = 0;
  void Function(Uri)? _cb;

  /// Ordered log of `push:<loc>` / `replace:<loc>` for assertions.
  final List<String> ops = [];

  @override
  Uri current() => _stack[_index];

  @override
  void push(String location) {
    ops.add('push:$location');
    if (_index < _stack.length - 1) {
      _stack.removeRange(_index + 1, _stack.length);
    }
    _stack.add(Uri.parse(location));
    _index = _stack.length - 1;
  }

  @override
  void replace(String location) {
    ops.add('replace:$location');
    _stack[_index] = Uri.parse(location);
  }

  @override
  void onPop(void Function(Uri) callback) => _cb = callback;

  @override
  void dispose() => _cb = null;

  // ── test helpers ──────────────────────────────────────────────────────────
  void back() {
    if (_index > 0) {
      _index--;
      _cb?.call(_stack[_index]);
    }
  }

  void forward() {
    if (_index < _stack.length - 1) {
      _index++;
      _cb?.call(_stack[_index]);
    }
  }

  int get historyLength => _stack.length;
}

/// App-wide bridge. `main_pwa` overrides it with the web (History API) bridge;
/// tests/mock keep the in-memory one.
final pwaUrlBridgeProvider = Provider<PwaUrlBridge>(
  (ref) => FakePwaUrlBridge(),
);
