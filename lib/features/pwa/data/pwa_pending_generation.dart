/// A generation the browser has ALREADY asked the backend for, remembered
/// across a reload.
///
/// The problem this solves: the staging backend answers a generation
/// SYNCHRONOUSLY — it holds the HTTP request open for the ~2 minutes the engine
/// takes and there is no job resource to poll. If the tab is refreshed in that
/// window the browser drops the response, and nothing in the page knows whether
/// an image was produced (and paid for) or not.
///
/// So the intent is written down BEFORE the call and cleared after it. On the
/// next boot a pending record means "replay this, with the SAME idempotency
/// key". The backend keys its replay on that value (`pwa_visions` carries
/// `unique (owner_user_id, idempotency_key)`), so:
///   • the first request succeeded  → the replay returns the existing vision,
///     no second image, no second cost;
///   • the first request never landed → the replay generates it for real.
///
/// What this deliberately does NOT claim: it cannot observe a request that is
/// still in flight server-side. Replaying while the original is mid-render can
/// still cost a second render, because there is no job row to look at. That
/// limit belongs to the backend's synchronous shape, and inventing a fake poll
/// here would only hide it.
///
/// A record therefore has TWO meanings, and they must not be confused. "The
/// answer is unknown" is what makes an automatic replay free and correct. "The
/// answer is known, and it was a failure" is not: the person has already been
/// told, and re-running it without being asked spends their money on a render
/// they did not request — once per reload, for as long as the failure lasts.
/// `failed` is what separates the two. A settled record is kept, because an
/// explicit Retry must reuse the same idempotency key; it is simply never
/// replayed on its own.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The durable description of one in-flight generation. Structured facts only —
/// enough to reissue the exact same request, and nothing else.
class PwaPendingGeneration {
  const PwaPendingGeneration({
    required this.projectId,
    required this.idempotencyKey,
    required this.actionType,
    required this.roomId,
    required this.roomLabel,
    required this.atmosphereId,
    required this.atmosphereLabel,
    required this.originalStoragePath,
    required this.visionNumber,
    this.parentVisionId = '',
    this.userInstruction = '',
    this.confirm = false,
    this.failed = false,
    this.startedAtMs = 0,
  });

  final String projectId;
  final String idempotencyKey;
  final String actionType;
  final String roomId;
  final String roomLabel;
  final String atmosphereId;
  final String atmosphereLabel;
  final String originalStoragePath;
  final int visionNumber;
  final String parentVisionId;
  final String userInstruction;

  /// The user read the advisor's objection and chose to continue. Persisted so
  /// a replay after a reload does not re-ask a question already answered.
  final bool confirm;

  /// This attempt came back with a definitive failure, and the person has seen
  /// it. Only an explicit Retry may run it again — never a boot.
  final bool failed;

  /// When the request left, epoch ms. 0 means "written before this field
  /// existed", which is the same thing as old.
  final int startedAtMs;

  /// How long a record can still describe something that might be running.
  ///
  /// This is not a comfort margin, it is the point past which replaying stops
  /// being free. `pwa_staging.claim_generation` releases a PROCESSING claim
  /// after fifteen minutes; up to then a replay is answered by the backend with
  /// the vision it already made, and beyond it the claim is re-taken and a
  /// second image is really rendered and really paid for. So the client stops
  /// replaying exactly where the backend stops protecting it.
  static const Duration replayWindow = Duration(minutes: 15);

  /// Could this still be a generation that is genuinely in flight?
  ///
  /// A record is written before the request and cleared after it, so a live one
  /// is at most a couple of minutes old. One from yesterday describes something
  /// that finished, failed or died long ago — replaying it on a page load buys
  /// a render nobody asked for. That is what happened on 2026-08-08: a record
  /// left by a failure the previous evening started a fresh paid render the
  /// moment the site was reopened.
  bool isReplayableAt(DateTime now) {
    if (failed || startedAtMs <= 0) return false;
    final age = now.millisecondsSinceEpoch - startedAtMs;
    return age >= 0 && age < replayWindow.inMilliseconds;
  }

  /// Same operation, now settled. Kept (not cleared) so Retry reuses the key.
  PwaPendingGeneration asFailed() => _copy(failed: true);

  /// Same operation, taken back up by a deliberate retry.
  PwaPendingGeneration asActive() => _copy(failed: false);

  /// Same operation, restamped as leaving now.
  PwaPendingGeneration startingAt(DateTime now) =>
      _copy(failed: false, startedAtMs: now.millisecondsSinceEpoch);

  PwaPendingGeneration _copy({required bool failed, int? startedAtMs}) =>
      PwaPendingGeneration(
    projectId: projectId,
    idempotencyKey: idempotencyKey,
    actionType: actionType,
    roomId: roomId,
    roomLabel: roomLabel,
    atmosphereId: atmosphereId,
    atmosphereLabel: atmosphereLabel,
    originalStoragePath: originalStoragePath,
    visionNumber: visionNumber,
    parentVisionId: parentVisionId,
    userInstruction: userInstruction,
    confirm: confirm,
    failed: failed,
    startedAtMs: startedAtMs ?? this.startedAtMs,
  );

  Map<String, dynamic> toJson() => {
    'project_id': projectId,
    'idempotency_key': idempotencyKey,
    'action_type': actionType,
    'room_id': roomId,
    'room_label': roomLabel,
    'atmosphere_id': atmosphereId,
    'atmosphere_label': atmosphereLabel,
    'original_image_path': originalStoragePath,
    'vision_number': visionNumber,
    'parent_vision_id': parentVisionId,
    'user_instruction': userInstruction,
    'confirm': confirm,
    'failed': failed,
    'started_at_ms': startedAtMs,
  };

  /// Null rather than throwing on anything malformed: a record we cannot read
  /// is a record we must not replay.
  static PwaPendingGeneration? tryParse(Object? raw) {
    if (raw is! Map) return null;
    String s(String k) => raw[k] is String ? raw[k] as String : '';
    if (s('project_id').isEmpty ||
        s('idempotency_key').isEmpty ||
        s('original_image_path').isEmpty) {
      return null;
    }
    return PwaPendingGeneration(
      projectId: s('project_id'),
      idempotencyKey: s('idempotency_key'),
      actionType: s('action_type').isEmpty ? 'initial' : s('action_type'),
      roomId: s('room_id'),
      roomLabel: s('room_label'),
      atmosphereId: s('atmosphere_id'),
      atmosphereLabel: s('atmosphere_label'),
      originalStoragePath: s('original_image_path'),
      visionNumber: (raw['vision_number'] as num?)?.toInt() ?? 1,
      parentVisionId: s('parent_vision_id'),
      userInstruction: s('user_instruction'),
      confirm: raw['confirm'] == true,
      failed: raw['failed'] == true,
      startedAtMs: (raw['started_at_ms'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Where a pending generation is remembered. One record at a time: the UI
/// refuses to start a second generation while one is running, so there can
/// never legitimately be two.
abstract class PwaPendingGenerationStore {
  Future<PwaPendingGeneration?> read();
  Future<void> write(PwaPendingGeneration pending);
  Future<void> clear();
}

/// Tests and the offline mock — nothing survives a reload there anyway.
class PwaMemoryPendingGenerationStore implements PwaPendingGenerationStore {
  PwaPendingGeneration? _value;

  /// Every write this store saw, in order. Lets a test prove the intent was
  /// recorded BEFORE the network call, not after it.
  final List<PwaPendingGeneration> writes = [];

  @override
  Future<PwaPendingGeneration?> read() async => _value;

  @override
  Future<void> write(PwaPendingGeneration pending) async {
    _value = pending;
    writes.add(pending);
  }

  @override
  Future<void> clear() async => _value = null;
}

/// The staging runtime: SharedPreferences, which is `localStorage` on web, so
/// the record outlives a refresh and a closed tab.
class PwaPrefsPendingGenerationStore implements PwaPendingGenerationStore {
  PwaPrefsPendingGenerationStore(this._prefs);

  static const String storageKey = 'pwa_pending_generation_v1';

  final SharedPreferences _prefs;

  @override
  Future<PwaPendingGeneration?> read() async {
    final raw = _prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return PwaPendingGeneration.tryParse(jsonDecode(raw));
    } catch (_) {
      // Unreadable → drop it rather than replay something we cannot describe.
      await _prefs.remove(storageKey);
      return null;
    }
  }

  @override
  Future<void> write(PwaPendingGeneration pending) =>
      _prefs.setString(storageKey, jsonEncode(pending.toJson()));

  @override
  Future<void> clear() => _prefs.remove(storageKey);
}
