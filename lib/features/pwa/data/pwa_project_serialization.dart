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
    'room_id': s.roomId,
    'room_label': s.roomLabel,
    'selected_atmosphere_id': s.selectedAtmosphereId,
    'selected_atmosphere_label': s.atmosphereLabel,
    'original_image_path': s.originalImageAsset,
    'original_image_source': pwaImageSourceToDb(
      pwaImageSourceForPath(s.originalImageAsset),
    ),
    'current_vision_id': s.currentVisionId,
    'cover_vision_id': s.coverVisionId,
    'updated_label': s.updatedLabel,
    'client_created_order': s.createdOrder,
    'client_updated_order': s.updatedOrder,
    'schema_version': kPwaSchemaVersion,
  };

  final visions = <Map<String, dynamic>>[
    for (final v in s.visions)
      {
        'id': v.versionId,
        'project_id': s.projectId,
        'installation_id': installationId,
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
          'installation_id': installationId,
          'role': pwaRoleToDb(m.role),
          'message_type': pwaMessageKindToDb(m.kind),
          'text_content': m.text.isEmpty ? null : m.text,
          'referenced_vision_id': m.visionId,
          'confirmation_state': m.pendingRefine != null ? 'pending' : null,
          'client_order': i,
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

// ── records → snapshot ───────────────────────────────────────────────────────

PwaProjectSnapshot pwaSnapshotFromRecords({
  required Map<String, dynamic> project,
  required List<Map<String, dynamic>> visions,
  required List<Map<String, dynamic>> messages,
}) {
  _checkSchema(project);
  final projectId = _reqStr(project, 'id');
  final currentVisionId = _optStr(project, 'current_vision_id');

  final visionRows = [...visions]
    ..sort(
      (a, b) =>
          _reqInt(a, 'client_order').compareTo(_reqInt(b, 'client_order')),
    );
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
          order: _reqInt(r, 'client_order'),
          parentVersionId: _optStr(r, 'parent_vision_id'),
          sourceMessageId: _optStr(r, 'source_message_id'),
          instruction: _optStr(r, 'prompt_text') ?? '',
          isCurrent: id == currentVisionId,
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

  return PwaProjectSnapshot(
    projectId: projectId,
    title: _reqStr(project, 'title'),
    originalImageAsset: _reqStr(project, 'original_image_path'),
    roomId: _optStr(project, 'room_id'),
    roomLabel: _optStr(project, 'room_label') ?? '',
    selectedAtmosphereId: _optStr(project, 'selected_atmosphere_id'),
    atmosphereLabel: _optStr(project, 'selected_atmosphere_label') ?? '',
    visions: List<PwaVision>.unmodifiable(parsedVisions),
    messages: List<PwaMessage>.unmodifiable(parsedMessages),
    currentVisionId: currentVisionId,
    coverVisionId: _optStr(project, 'cover_vision_id'),
    createdOrder: _reqInt(project, 'client_created_order'),
    updatedOrder: _reqInt(project, 'client_updated_order'),
    updatedLabel: _optStr(project, 'updated_label') ?? 'Updated',
    status: pwaStatusFromDb(_reqStr(project, 'status')),
  );
}
