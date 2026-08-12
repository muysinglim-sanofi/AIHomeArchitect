/// Batch 3.0 — explicit mapping between the domain graph
/// ([PwaProjectSnapshot] / [PwaVision] / [PwaMessage]) and staging records
/// (§18 / §33). Strict: unknown enums and malformed/missing required fields
/// raise a controlled [PwaRepositoryError.serialization]; no silent field
/// dropping; [schema_version] is validated; immutable domain collections in,
/// immutable domain collections out.
///
/// Pure Dart — a record is a `Map<String, dynamic>` (a DB row shape), so the
/// whole layer round-trips offline with no backend. Timestamps are DB-side
/// metadata; the domain's ordering comes from the round-trippable client_order
/// integers, so mapping never needs a wall clock.
library;

import '../domain/pwa_models.dart';
import '../domain/pwa_project.dart';
import 'pwa_repository_error.dart';

/// Current record schema version. A row with a higher version is refused.
const int kPwaSchemaVersion = 1;

/// Sentinel stored in the NOT NULL `room_id` column for "Ayden Decide" (no
/// explicit room). The deployed schema forbids null room_id; this preserves the
/// null (auto-detect) semantics across a round-trip — mapped back to null on read.
const String kPwaAydenDecideRoom = '__ayden_decide__';

/// Default atmosphere id written when the snapshot's (nullable) atmosphere is
/// null, satisfying the NOT NULL `selected_atmosphere_id` column. Unlike the
/// room sentinel this is a REAL id (the app already treats null == this default),
/// so it needs no read-side remap.
const String kPwaDefaultAtmosphere = 'ayden_signature';

/// Where a persisted image lives (§11 / §20).
enum PwaImageSourceKind { bundle, stagingStorage }

String pwaImageSourceToDb(PwaImageSourceKind k) => switch (k) {
  PwaImageSourceKind.bundle => 'bundle',
  PwaImageSourceKind.stagingStorage => 'staging_storage',
};

PwaImageSourceKind pwaImageSourceFromDb(String? v) => switch (v) {
  'bundle' || null => PwaImageSourceKind.bundle,
  'staging_storage' => PwaImageSourceKind.stagingStorage,
  _ => throw PwaRepositoryError.serialization('Unknown image_source "$v".'),
};

/// A bundled asset path reads as `bundle`; anything else is staging storage.
PwaImageSourceKind pwaImageSourceForPath(String path) =>
    path.startsWith('assets/')
    ? PwaImageSourceKind.bundle
    : PwaImageSourceKind.stagingStorage;

// ── enum mapping ─────────────────────────────────────────────────────────────

String pwaActionToDb(PwaActionType a) => switch (a) {
  PwaActionType.signature => 'initial',
  PwaActionType.refine => 'refine',
  PwaActionType.switchAtmosphere => 'switch_atmosphere',
};

PwaActionType pwaActionFromDb(String v) => switch (v) {
  'initial' => PwaActionType.signature,
  'refine' => PwaActionType.refine,
  'switch_atmosphere' => PwaActionType.switchAtmosphere,
  _ => throw PwaRepositoryError.serialization('Unknown action_type "$v".'),
};

String pwaStatusToDb(PwaProjectStatus s) => switch (s) {
  PwaProjectStatus.draft => 'draft',
  PwaProjectStatus.active => 'active',
};

PwaProjectStatus pwaStatusFromDb(String v) => switch (v) {
  'draft' => PwaProjectStatus.draft,
  'active' => PwaProjectStatus.active,
  _ => throw PwaRepositoryError.serialization('Unknown status "$v".'),
};

String pwaRoleToDb(PwaRole r) => switch (r) {
  PwaRole.user => 'user',
  PwaRole.ayden => 'assistant',
};

PwaRole pwaRoleFromDb(String v) => switch (v) {
  'user' => PwaRole.user,
  'assistant' => PwaRole.ayden,
  'system' => PwaRole.ayden, // domain has no system role → treat as assistant
  _ => throw PwaRepositoryError.serialization('Unknown role "$v".'),
};

String pwaMessageKindToDb(PwaMessageKind k) => switch (k) {
  PwaMessageKind.text => 'text',
  PwaMessageKind.reveal => 'vision_result',
  PwaMessageKind.loading => 'generation_status',
};

PwaMessageKind pwaMessageKindFromDb(String v) => switch (v) {
  'text' || 'system_marker' => PwaMessageKind.text,
  'vision_result' => PwaMessageKind.reveal,
  'generation_status' => PwaMessageKind.loading,
  // Proposal messages are advice text carrying a pending action in the domain.
  'refine_proposal' || 'atmosphere_proposal' => PwaMessageKind.text,
  _ => throw PwaRepositoryError.serialization('Unknown message_type "$v".'),
};

// ── strict field readers ─────────────────────────────────────────────────────

String _reqStr(Map<String, dynamic> r, String k) {
  final v = r[k];
  if (v is! String || v.isEmpty) {
    throw PwaRepositoryError.serialization('Missing/invalid required "$k".');
  }
  return v;
}

String? _optStr(Map<String, dynamic> r, String k) {
  final v = r[k];
  if (v == null) return null;
  if (v is! String) {
    throw PwaRepositoryError.serialization('Invalid string "$k".');
  }
  return v;
}

int _reqInt(Map<String, dynamic> r, String k) {
  final v = r[k];
  if (v is int) return v;
  if (v is num) return v.toInt();
  throw PwaRepositoryError.serialization('Missing/invalid required int "$k".');
}

/// A human freshness label for [updatedAt], relative to [now].
///
/// The domain keeps display freshness as a PRE-RENDERED string so the library
/// sorts and renders deterministically in tests (see [PwaProjectSnapshot]). The
/// clock therefore lives here, at the record→domain seam, and is injectable.
///
/// This exists because the read side asked for an `updated_label` COLUMN that
/// the write side never produced and the schema never had — so every project
/// restored from staging rendered the bare word "Updated", with no date, no
/// matter how recently it had been touched.
String pwaRelativeUpdatedLabel(DateTime updatedAt, {DateTime? now}) {
  final ref = (now ?? DateTime.now()).toUtc();
  final then = updatedAt.toUtc();
  final delta = ref.difference(then);
  if (delta.isNegative || delta.inMinutes < 1) return 'Updated just now';
  if (delta.inMinutes < 60) {
    final m = delta.inMinutes;
    return 'Updated $m ${m == 1 ? "minute" : "minutes"} ago';
  }
  // Calendar days, not 24-hour buckets: something touched last night reads as
  // "Yesterday", which is what a person means by it.
  final days = DateTime.utc(
    ref.year,
    ref.month,
    ref.day,
  ).difference(DateTime.utc(then.year, then.month, then.day)).inDays;
  if (days == 0) return 'Updated today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  if (days < 14) return 'Last week';
  if (days < 31) return '${days ~/ 7} weeks ago';
  final months = days ~/ 30;
  return '$months ${months == 1 ? "month" : "months"} ago';
}

/// Parse a DB timestamp, or null when absent/unreadable.
DateTime? pwaParseTimestamp(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

/// Chronological rank of a vision row.
///
/// `client_order` is a CLIENT sequence: it exists on rows this app wrote, and is
/// NULL on rows the BACKEND authored — the generation adapter inserts the vision
/// itself and has no client sequence to write. `vision_number` is then the
/// authority, and it is assigned by the same backend, so the two agree.
///
/// Reading it as required is what broke a refresh after a real generation: every
/// row came back without it, the whole library failed to deserialize, and the
/// app opened on an empty Home with three visions sitting safely in the database.
int _visionOrder(Map<String, dynamic> r) {
  final v = r['client_order'];
  if (v is num) return v.toInt();
  return _reqInt(r, 'vision_number');
}

void _checkSchema(Map<String, dynamic> r) {
  final v = r['schema_version'];
  final n = v is num ? v.toInt() : null;
  if (n == null) {
    throw PwaRepositoryError.serialization('Missing schema_version.');
  }
  if (n > kPwaSchemaVersion) {
    throw PwaRepositoryError.serialization(
      'Unsupported schema_version $n (max $kPwaSchemaVersion).',
    );
  }
}

// ── snapshot → records ───────────────────────────────────────────────────────

class PwaProjectRecords {
  const PwaProjectRecords({
    required this.project,
    required this.visions,
    required this.messages,
  });
  final Map<String, dynamic> project;
  final List<Map<String, dynamic>> visions;
  final List<Map<String, dynamic>> messages;
}

PwaProjectRecords pwaRecordsFromSnapshot(
  PwaProjectSnapshot s, {
  required String installationId,
}) {
  final project = <String, dynamic>{
    'id': s.projectId,
    'installation_id': installationId,
    'title': s.title,
    'status': pwaStatusToDb(s.status),
    // room_id is NOT NULL in the deployed schema; a null (Ayden Decide) room is
    // stored as the sentinel and restored to null on read.
    'room_id': s.roomId ?? kPwaAydenDecideRoom,
    'room_label': s.roomLabel,
    // selected_atmosphere_id is NOT NULL too; the domain field is nullable, so
    // default it (the app treats null == the signature default) — self-protecting.
    'selected_atmosphere_id': s.selectedAtmosphereId ?? kPwaDefaultAtmosphere,
    'selected_atmosphere_label': s.atmosphereLabel,
    'original_image_path': s.originalImageAsset,
    'original_image_source': pwaImageSourceToDb(
      pwaImageSourceForPath(s.originalImageAsset),
    ),
    'current_vision_id': s.currentVisionId,
    'cover_vision_id': s.coverVisionId,
    'client_created_order': s.createdOrder,
    'client_updated_order': s.updatedOrder,
    'schema_version': kPwaSchemaVersion,
  };

  final visions = <Map<String, dynamic>>[
    for (final v in s.visions)
      {
        'id': v.versionId,
        'project_id': s.projectId,
        'vision_number': v.visionNumber,
        'parent_vision_id': v.parentVersionId,
        'action_type': pwaActionToDb(v.actionType),
        'action_summary': v.title,
        'prompt_text': v.instruction.isEmpty ? null : v.instruction,
        'atmosphere_id': v.atmosphereId,
        'atmosphere_label': v.atmosphereId,
        'image_path': v.afterAsset,
        'image_source': pwaImageSourceToDb(pwaImageSourceForPath(v.afterAsset)),
        'source_message_id': v.sourceMessageId,
        'client_order': v.order,
        // idempotency_key = the entity's own stable UUID (retry-safe, unique per
        // owner). The same vision UUID is reused on retry — no derived id.
        'idempotency_key': v.versionId,
        'schema_version': kPwaSchemaVersion,
      },
  ];

  final messages = <Map<String, dynamic>>[
    for (var i = 0; i < s.messages.length; i++)
      () {
        final m = s.messages[i];
        return <String, dynamic>{
          'id': m.id,
          'project_id': s.projectId,
          'role': pwaRoleToDb(m.role),
          'message_type': pwaMessageKindToDb(m.kind),
          'text_content': m.text.isEmpty ? null : m.text,
          'referenced_vision_id': m.visionId,
          'confirmation_state': m.pendingRefine != null ? 'pending' : null,
          'client_order': i,
          // idempotency_key = the message's own stable UUID (retry-safe).
          'idempotency_key': m.id,
          'metadata_json': {
            if (m.chips.isNotEmpty) 'chips': m.chips,
            if (m.pendingRefine != null) 'pending_refine': m.pendingRefine,
          },
          'schema_version': kPwaSchemaVersion,
        };
      }(),
  ];

  return PwaProjectRecords(
    project: project,
    visions: visions,
    messages: messages,
  );
}

// ── idempotent append planner (§ Phase D, point 4) ───────────────────────────

/// Immutable columns compared to decide whether a colliding row is the SAME
/// operation (an idempotent retry) or a real divergence. Kept in sync with the
/// serialization above; excludes DB-managed columns (owner_user_id, timestamps).
const List<String> kPwaVisionImmutableKeys = [
  'id',
  'project_id',
  'idempotency_key',
  'vision_number',
  'parent_vision_id',
  'action_type',
  'atmosphere_id',
  'image_path',
  'source_message_id',
  'client_order',
];

const List<String> kPwaMessageImmutableKeys = [
  'id',
  'project_id',
  'idempotency_key',
  'role',
  'message_type',
  'referenced_vision_id',
  'text_content',
  'client_order',
];

/// Decide which append-only child rows are genuinely NEW and must be inserted —
/// WITHOUT ever updating an existing row (§ point 4). [existingRows] are the DB
/// rows already stored that match a local row by `id` OR `idempotency_key`.
///
/// - id absent + key absent → new (insert).
/// - id present → allowed ONLY if every immutable column is identical (an
///   idempotent retry → skipped, never re-inserted, never UPDATEd); otherwise
///   [PwaRepositoryError.conflict].
/// - key present under a DIFFERENT id → the idempotency key was reused by another
///   operation → [PwaRepositoryError.conflict].
List<Map<String, dynamic>> planIdempotentAppend({
  required List<Map<String, dynamic>> localRows,
  required List<Map<String, dynamic>> existingRows,
  required List<String> immutableKeys,
  required String op,
}) {
  final byId = <Object?, Map<String, dynamic>>{
    for (final e in existingRows) e['id']: e,
  };
  final byKey = <Object?, Map<String, dynamic>>{
    for (final e in existingRows) e['idempotency_key']: e,
  };
  final toInsert = <Map<String, dynamic>>[];
  for (final row in localRows) {
    final existById = byId[row['id']];
    final existByKey = byKey[row['idempotency_key']];
    if (existById == null && existByKey == null) {
      toInsert.add(row); // genuinely new
      continue;
    }
    if (existById != null) {
      // Same id already stored → allowed ONLY as the identical operation.
      _assertRowUnchanged(row, existById, immutableKeys, op);
      continue; // idempotent retry: no re-insert, no UPDATE
    }
    // idempotency_key present under a different id → reused by another op.
    throw PwaRepositoryError(
      PwaErrorKind.conflict,
      'Idempotency key for $op is already used by a different row.',
    );
  }
  return toInsert;
}

void _assertRowUnchanged(
  Map<String, dynamic> local,
  Map<String, dynamic> stored,
  List<String> immutableKeys,
  String op,
) {
  for (final k in immutableKeys) {
    if (!_scalarEquals(local[k], stored[k])) {
      throw PwaRepositoryError(
        PwaErrorKind.conflict,
        'Idempotency conflict on $op: "$k" differs for id ${local['id']}.',
      );
    }
  }
}

bool _scalarEquals(Object? a, Object? b) {
  if (a is num && b is num) return a.toDouble() == b.toDouble();
  return a == b;
}

// ── records → snapshot ───────────────────────────────────────────────────────

PwaProjectSnapshot pwaSnapshotFromRecords({
  required Map<String, dynamic> project,
  required List<Map<String, dynamic>> visions,
  required List<Map<String, dynamic>> messages,
  DateTime? now,
}) {
  _checkSchema(project);
  final projectId = _reqStr(project, 'id');
  final currentVisionId = _optStr(project, 'current_vision_id');

  final visionRows = [...visions]
    ..sort((a, b) => _visionOrder(a).compareTo(_visionOrder(b)));
  final parsedVisions = <PwaVision>[
    for (final r in visionRows)
      () {
        _checkSchema(r);
        final id = _reqStr(r, 'id');
        return PwaVision(
          versionId: id,
          projectId: _reqStr(r, 'project_id'),
          visionNumber: _reqInt(r, 'vision_number'),
          title: _optStr(r, 'action_summary') ?? '',
          atmosphereId: _reqStr(r, 'atmosphere_id'),
          actionType: pwaActionFromDb(_reqStr(r, 'action_type')),
          afterAsset: _reqStr(r, 'image_path'),
          order: _visionOrder(r),
          parentVersionId: _optStr(r, 'parent_vision_id'),
          sourceMessageId: _optStr(r, 'source_message_id'),
          instruction: _optStr(r, 'prompt_text') ?? '',
          isCurrent: id == currentVisionId,
          // It came FROM a record, so its row exists: a later save must not try
          // to append it again (the backend, not this client, wrote the row for
          // a real generation, and its idempotency_key is not the vision id).
          remotePersisted: true,
        );
      }(),
  ];

  final messageRows = [...messages]
    ..sort(
      (a, b) =>
          _reqInt(a, 'client_order').compareTo(_reqInt(b, 'client_order')),
    );
  final parsedMessages = <PwaMessage>[
    for (final r in messageRows)
      () {
        _checkSchema(r);
        final meta = r['metadata_json'];
        final metaMap = meta is Map ? meta : const {};
        final chips =
            (metaMap['chips'] as List?)?.cast<String>() ?? const <String>[];
        return PwaMessage(
          id: _reqStr(r, 'id'),
          role: pwaRoleFromDb(_reqStr(r, 'role')),
          kind: pwaMessageKindFromDb(_reqStr(r, 'message_type')),
          text: _optStr(r, 'text_content') ?? '',
          visionId: _optStr(r, 'referenced_vision_id'),
          chips: List<String>.unmodifiable(chips),
          pendingRefine: metaMap['pending_refine'] as String?,
        );
      }(),
  ];

  final updatedAt = pwaParseTimestamp(project['updated_at']);

  return PwaProjectSnapshot(
    projectId: projectId,
    title: _reqStr(project, 'title'),
    originalImageAsset: _reqStr(project, 'original_image_path'),
    // Map the Ayden-Decide sentinel back to null (no explicit room).
    roomId: () {
      final r = _optStr(project, 'room_id');
      return r == kPwaAydenDecideRoom ? null : r;
    }(),
    roomLabel: _optStr(project, 'room_label') ?? '',
    selectedAtmosphereId: _optStr(project, 'selected_atmosphere_id'),
    atmosphereLabel: _optStr(project, 'selected_atmosphere_label') ?? '',
    visions: List<PwaVision>.unmodifiable(parsedVisions),
    messages: List<PwaMessage>.unmodifiable(parsedMessages),
    currentVisionId: currentVisionId,
    coverVisionId: _optStr(project, 'cover_vision_id'),
    createdOrder: _reqInt(project, 'client_created_order'),
    updatedOrder: _reqInt(project, 'client_updated_order'),
    // `updated_at` is written by the DATABASE on every write, so it is the one
    // freshness value that is always true. The previous code read an
    // `updated_label` column that no writer produced and the schema never had,
    // so every restored project rendered the bare word "Updated".
    updatedAt: updatedAt,
    updatedLabel: updatedAt != null
        ? pwaRelativeUpdatedLabel(updatedAt, now: now)
        : (_optStr(project, 'updated_label') ?? 'Updated'),
    status: pwaStatusFromDb(_reqStr(project, 'status')),
  );
}
