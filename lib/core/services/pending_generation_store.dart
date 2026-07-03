import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/pending_generation.dart';

/// PR2b Slice 2 — durable store of INTENDED generations (recovery only).
///
/// ⚠️ TECHNICAL LAYER, NOT A SOURCE OF TRUTH. See the invariant on
/// [PendingGeneration]: the backend `generation_intents` table is the source of
/// truth; this store only records "I intended to POST this /generate" so Slice 3
/// can re-attach or re-launch after a kill/sleep/network-drop. If this store and
/// the backend ever disagree, THE BACKEND ALWAYS WINS (Slice 3 probes first).
///
/// Storage: one SharedPreferences key per session, `aih:pending:{sessionId}`.
/// A session has at most one in-flight generation at a time, so one row suffices.
///
/// All methods are NON-FATAL (mirrors SessionPersistenceService): failures are
/// logged via debugPrint and swallowed — a store hiccup must never break a
/// generation. New sessions (`sessionId == 'new'` / empty) are ignored (their id
/// isn't real yet — the R2 guard ensures we only ever save a real id).
class PendingGenerationStore {
  static const String _keyPrefix = 'aih:pending:';

  final SharedPreferences _prefs;

  const PendingGenerationStore(this._prefs);

  /// Preferred constructor — awaits the SharedPreferences singleton.
  static Future<PendingGenerationStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return PendingGenerationStore(prefs);
  }

  String _keyFor(String sessionId) => '$_keyPrefix$sessionId';

  bool _isReal(String sessionId) =>
      sessionId.isNotEmpty && sessionId != 'new';

  /// Record the INTENTION to generate for [p.sessionId]. Call BEFORE the network
  /// POST so a crash/kill mid-POST still leaves the intention recoverable.
  Future<void> save(PendingGeneration p) async {
    if (!_isReal(p.sessionId)) return;
    try {
      await _prefs.setString(_keyFor(p.sessionId), p.toJsonString());
    } catch (e) {
      debugPrint('[PendingStore] save failed for ${p.sessionId}: $e');
    }
  }

  /// Drop the intention for [sessionId]. Call on a DEFINITIVE terminal
  /// (success / structured failure) — NOT on a transport error (the backend may
  /// still have succeeded; Slice 3 resolves it via the backend probe).
  Future<void> clear(String sessionId) async {
    if (!_isReal(sessionId)) return;
    try {
      await _prefs.remove(_keyFor(sessionId));
    } catch (e) {
      debugPrint('[PendingStore] clear failed for $sessionId: $e');
    }
  }

  /// The pending intention for [sessionId], or null (none / malformed / stale
  /// schema). Used by Slice 3 to decide re-attach vs re-launch.
  Future<PendingGeneration?> load(String sessionId) async {
    if (!_isReal(sessionId)) return null;
    try {
      final raw = _prefs.getString(_keyFor(sessionId));
      if (raw == null) return null;
      return PendingGeneration.fromJsonString(raw);
    } catch (e) {
      debugPrint('[PendingStore] load failed for $sessionId: $e');
      return null;
    }
  }

  /// Every pending intention (Slice 3 sweeps these at app launch). Skips
  /// malformed / stale-schema entries. Never throws.
  Future<List<PendingGeneration>> loadAll() async {
    try {
      final keys = _prefs.getKeys().where((k) => k.startsWith(_keyPrefix));
      final out = <PendingGeneration>[];
      for (final k in keys) {
        final raw = _prefs.getString(k);
        if (raw == null) continue;
        final p = PendingGeneration.fromJsonString(raw);
        if (p != null) out.add(p);
      }
      return out;
    } catch (e) {
      debugPrint('[PendingStore] loadAll failed: $e');
      return const [];
    }
  }
}
