import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/session_state.dart';

/// Wave 4.10g — Persistent Design Session Stabilization
///
/// `SessionPersistenceService` is the **local persistence layer** for
/// in-progress design sessions. It wraps `SharedPreferences` so the
/// ChatScreen can:
///
///   • `load(sessionId)` — hydrate the persisted `SessionState` on
///     session reopen / app restart, restoring the protocol tokens and
///     conversational continuity.
///   • `save(sessionId, state)` — write through after every state
///     mutation that matters (generation success, atmosphere swap,
///     iteration advance, etc.). Write-through is fast (SharedPreferences
///     is local; no network).
///   • `clear(sessionId)` — drop a snapshot (e.g. user explicitly resets
///     a session).
///   • `clearAll()` — nuclear option (developer-only / future "sign out").
///
/// ## Storage layout
///
///   key = `"aih:session:{sessionId}"`     →     value = JSON-encoded
///   `SessionState.toJsonString()`
///
/// One key per session id. No global state. No cross-session contamination
/// risk. New sessions (`projectId == 'new'`) do NOT touch persistence
/// (their id isn't real yet); persistence begins after the Supabase row is
/// created and the project id is finalised.
///
/// ## Why SharedPreferences (Phase 1)
///
/// Local-only, instant (no network), available on Android/iOS/web. Wave
/// 4.10g Phase 1 scope: get session continuity working end-to-end. Phase 3
/// (deferred, not in this commit) will optionally mirror to a Supabase
/// column for cross-device sync; the service is intentionally narrow
/// enough that swapping the backing store is a single-method change.
///
/// ## Concurrency model
///
/// All operations are async (SharedPreferences uses async write). Multiple
/// concurrent `save` calls are not synchronized in this service — last
/// write wins, which is the correct semantic for a single-user single-
/// device session. ChatScreen calls `save` from the UI thread post-state-
/// commit, so writes are naturally serialised.
///
/// ## Failure modes
///
/// All methods are non-fatal. Read failures (corrupt JSON, schema
/// mismatch, missing key) return `null`. Write failures are logged via
/// `debugPrint` but do not throw — the in-memory session continues to
/// function; the worst case is the next restart starts from empty.
class SessionPersistenceService {
  static const String _keyPrefix = 'aih:session:';

  final SharedPreferences _prefs;

  const SessionPersistenceService(this._prefs);

  /// Factory — preferred way to obtain an instance. Awaits the underlying
  /// SharedPreferences singleton.
  static Future<SessionPersistenceService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SessionPersistenceService(prefs);
  }

  String _keyFor(String sessionId) => '$_keyPrefix$sessionId';

  /// Returns the persisted state for [sessionId] or `null` if none exists,
  /// the snapshot is malformed, or the schema version is unrecognized.
  /// Never throws.
  Future<SessionState?> load(String sessionId) async {
    if (sessionId.isEmpty || sessionId == 'new') return null;
    try {
      final raw = _prefs.getString(_keyFor(sessionId));
      if (raw == null) return null;
      return SessionState.fromJsonString(raw);
    } catch (e) {
      debugPrint(
          '[SessionPersistenceService] load failed for $sessionId: $e');
      return null;
    }
  }

  /// Write-through save for [sessionId]. Non-fatal: errors are logged and
  /// swallowed (in-memory state continues to function regardless).
  Future<void> save(String sessionId, SessionState state) async {
    if (sessionId.isEmpty || sessionId == 'new') return;
    try {
      final raw = state.toJsonString();
      await _prefs.setString(_keyFor(sessionId), raw);
    } catch (e) {
      debugPrint(
          '[SessionPersistenceService] save failed for $sessionId: $e');
    }
  }

  /// Drop the snapshot for [sessionId]. Non-fatal.
  Future<void> clear(String sessionId) async {
    if (sessionId.isEmpty || sessionId == 'new') return;
    try {
      await _prefs.remove(_keyFor(sessionId));
    } catch (e) {
      debugPrint(
          '[SessionPersistenceService] clear failed for $sessionId: $e');
    }
  }

  /// Drop ALL session snapshots. Future "sign out" / "clear app data" hook.
  /// Non-fatal.
  Future<void> clearAll() async {
    try {
      final keys =
          _prefs.getKeys().where((k) => k.startsWith(_keyPrefix)).toList();
      for (final k in keys) {
        await _prefs.remove(k);
      }
    } catch (e) {
      debugPrint('[SessionPersistenceService] clearAll failed: $e');
    }
  }
}
