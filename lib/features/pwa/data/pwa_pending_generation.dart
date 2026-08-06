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
