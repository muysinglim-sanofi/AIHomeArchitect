/// Batch 3.4 — the Hero cinematic play-once-per-tab gate (§7).
///
/// The intro plays automatically ONCE per browser tab session, never on F5 or
/// when returning Home, and can be replayed explicitly. The only thing stored is
/// a boolean marker in a session-scoped store — browser `sessionStorage` on web
/// (survives F5 within the tab, cleared on a new tab session), an in-memory map
/// in tests. No project data or routing state is ever stored here.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Injectable session-scoped key/value store. Only the intro marker lives here.
abstract class PwaSessionStore {
  String? read(String key);
  void write(String key, String value);
}

/// Default store — in-memory (tests + mock-without-override). Does NOT survive a
/// real page reload, so on web `main_pwa` overrides it with a sessionStorage
/// implementation that does.
class MemoryPwaSessionStore implements PwaSessionStore {
  final Map<String, String> _m = {};
  @override
  String? read(String key) => _m[key];
  @override
  void write(String key, String value) => _m[key] = value;
}

class PwaIntroGate {
  PwaIntroGate(this._store);
  final PwaSessionStore _store;

  static const String kMarkerKey = 'ayden_intro_started';

  /// True only on the first arrival in a new tab session (marker absent). F5
  /// after the marker is written returns false → no automatic replay.
  bool shouldAutoplay() => _store.read(kMarkerKey) == null;

  /// Mark the intro as started. MUST be called BEFORE playback begins so a
  /// mid-cinematic F5 (marker already present) does not restart it.
  void markStarted() => _store.write(kMarkerKey, '1');
}

/// App-wide singleton. `main_pwa` overrides the underlying store with the
/// sessionStorage-backed one on web; tests/mock keep the memory store.
final pwaIntroGateProvider = Provider<PwaIntroGate>(
  (ref) => PwaIntroGate(MemoryPwaSessionStore()),
);
