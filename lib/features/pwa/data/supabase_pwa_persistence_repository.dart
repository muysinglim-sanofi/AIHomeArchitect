/// Phase D — the real staging persistence adapter (§7).
///
/// Implements the EXISTING [PwaPersistenceRepository] over the isolated staging
/// Supabase client, `schema('pwa_staging')`, native anonymous Auth, native
/// Storage and the deployed RPCs. No new interface, no id mapper, no sync engine.
///
/// [saveProject] is the single-seam, NON-destructive save: upsert project
/// metadata with revision control, insert only ABSENT visions/messages
/// (append-only; id == idempotency_key so a collision can only be the identical
/// row), then set current/cover after the children exist. No delete-and-reinsert.
library;

import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/media/ayden_image_source.dart';
import '../domain/pwa_models.dart';
import '../domain/pwa_project.dart';
import 'pwa_persistence_repository.dart';
import 'pwa_project_serialization.dart';
import 'pwa_repository_error.dart';
import 'pwa_staging_supabase_client.dart';

const String _kBucket = 'pwa-staging-images';
const Uuid _uuid = Uuid();

class SupabasePwaPersistenceRepository implements PwaPersistenceRepository {
  SupabasePwaPersistenceRepository(
    this._staging, {
    required this.installationId,
  });

  final PwaStagingSupabaseClient _staging;
  final String installationId;

  /// Last revision this client observed per project — the basis of the
  /// optimistic-concurrency check on metadata updates (§3.1).
  final Map<String, int> _revisions = {};

  SupabaseClient get _c => _staging.client;
  SupabaseQuerySchema get _db => _c.schema('pwa_staging');

  // ── identity / health ──────────────────────────────────────────────────────
  @override
  Future<PwaInstallationIdentity> ensureInstallation() async {
    try {
      // Ensure the anonymous session exists (stable auth.uid()). The client
      // installation id is a nullable provenance column stamped on project rows
      // at save time — no separate registration call is required.
      await _staging.ensureSession();
      return PwaInstallationIdentity(installationId);
    } catch (e) {
      _map(e, 'ensureInstallation');
    }
  }

  @override
  Future<void> healthCheck() async {
    try {
      await _staging.ensureSession();
      await _db.from('pwa_projects').select('id').limit(1);
    } catch (e) {
      _map(e, 'healthCheck');
    }
  }

  // ── reads ──────────────────────────────────────────────────────────────────
  @override
  Future<List<PwaProjectSnapshot>> loadLibrary() async {
    try {
      await _staging.ensureSession();
      final projects = await _db
          .from('pwa_projects')
          .select()
          .filter('deleted_at', 'is', null);
      if (projects.isEmpty) return const [];
      final visions = await _db.from('pwa_visions').select();
      final messages = await _db.from('pwa_messages').select();
      final vByP = _groupBy(visions, 'project_id');
      final mByP = _groupBy(messages, 'project_id');
      final out = <PwaProjectSnapshot>[];
      for (final p in projects) {
        final id = p['id'] as String;
        _revisions[id] = (p['revision'] as num).toInt();
        out.add(
          pwaSnapshotFromRecords(
            project: Map<String, dynamic>.from(p),
            visions: vByP[id] ?? const [],
            messages: mByP[id] ?? const [],
          ),
        );
      }
      return out;
    } catch (e) {
      _map(e, 'loadLibrary');
    }
  }

  @override
  Future<PwaProjectSnapshot?> loadProject(String projectId) async {
    try {
      await _staging.ensureSession();
      final p = await _db
          .from('pwa_projects')
          .select()
          .eq('id', projectId)
          .maybeSingle();
      if (p == null || p['deleted_at'] != null) return null;
      _revisions[projectId] = (p['revision'] as num).toInt();
      final v = await _db
          .from('pwa_visions')
          .select()
          .eq('project_id', projectId);
      final m = await _db
          .from('pwa_messages')
          .select()
          .eq('project_id', projectId);
      return pwaSnapshotFromRecords(
        project: Map<String, dynamic>.from(p),
        visions: v.map((e) => Map<String, dynamic>.from(e)).toList(),
        messages: m.map((e) => Map<String, dynamic>.from(e)).toList(),
      );
    } catch (e) {
      _map(e, 'loadProject');
    }
  }

  // ── single-seam save (non-destructive) ──────────────────────────────────────
  @override
  Future<void> saveProject(
    PwaProjectSnapshot snapshot, {
    bool replaceOriginal = false,
  }) async {
    if (snapshot.title.trim().isEmpty) {
      throw const PwaRepositoryError.validation(
        'Project title must not be empty.',
      );
    }
    try {
      await _staging.ensureSession();
      final records = pwaRecordsFromSnapshot(
        snapshot,
        installationId: installationId,
      );
      final project = Map<String, dynamic>.from(records.project);
      final current = project.remove('current_vision_id');
      final cover = project.remove('cover_vision_id');

      final existing = await _db
          .from('pwa_projects')
          .select('revision')
          .eq('id', snapshot.projectId)
          .maybeSingle();

      if (existing == null) {
        // New: upload the original image once (if the session carries bytes),
        // then insert with current/cover null (set after children exist).
        if (snapshot.source != null) {
          project['original_image_path'] = await _uploadOriginal(
            snapshot.projectId,
            snapshot.source!,
          );
          project['original_image_source'] = 'staging_storage';
        }
        project['current_vision_id'] = null;
        project['cover_vision_id'] = null;
        await _db.from('pwa_projects').insert(project);
        _revisions[snapshot.projectId] = 1;
      } else {
        // Existing: metadata update under optimistic revision control. The
        // original image is immutable EXCEPT on an explicit Step-5 replacement:
        // then upload the new original FIRST (a fresh collision-free owned
        // object — the deployed policy has no per-project cap; the old object is
        // retained, there being no owner DELETE policy) and point the row at it
        // in the SAME update. Upload BEFORE the row write, so an upload failure
        // leaves the old durable path authoritative (§6).
        final rev =
            _revisions[snapshot.projectId] ??
            (existing['revision'] as num).toInt();
        final upd = Map<String, dynamic>.from(project)..['revision'] = rev + 1;
        if (replaceOriginal && snapshot.source != null) {
          upd['original_image_path'] = await _uploadOriginal(
            snapshot.projectId,
            snapshot.source!,
          );
          upd['original_image_source'] = 'staging_storage';
        } else {
          upd
            ..remove('original_image_path')
            ..remove('original_image_source');
        }
        final updated = await _db
            .from('pwa_projects')
            .update(upd)
            .eq('id', snapshot.projectId)
            .eq('revision', rev)
            .select('revision');
        if (updated.isEmpty) {
          throw const PwaRepositoryError.conflict(
            'Project changed elsewhere (revision mismatch). Reload and retry.',
          );
        }
        _revisions[snapshot.projectId] = rev + 1;
      }

      // Append-only children: insert only genuinely-new rows. A collision is
      // accepted ONLY as an identical retry (verified column-by-column); a real
      // divergence or a reused idempotency_key raises conflict. Never UPDATEs.
      await _appendChildren(
        'pwa_visions',
        records.visions,
        kPwaVisionImmutableKeys,
        'vision',
      );
      await _appendChildren(
        'pwa_messages',
        records.messages,
        kPwaMessageImmutableKeys,
        'message',
      );

      // current/cover after the referenced visions exist.
      await _db
          .from('pwa_projects')
          .update({'current_vision_id': current, 'cover_vision_id': cover})
          .eq('id', snapshot.projectId);
    } catch (e) {
      _map(e, 'saveProject');
    }
  }

  // ── granular ops (interface completeness; seam uses saveProject) ─────────────
  @override
  Future<void> appendVision(String projectId, PwaVision vision) async {
    try {
      await _staging.ensureSession();
      // Same verifying append as the seam — never a blind ignore-duplicates.
      await _appendChildren(
        'pwa_visions',
        [_visionRow(projectId, vision)],
        kPwaVisionImmutableKeys,
        'vision',
      );
      await updateCurrentVision(projectId, vision.versionId);
    } catch (e) {
      _map(e, 'appendVision');
    }
  }

  @override
  Future<void> appendMessage(String projectId, PwaMessage message) async {
    try {
      await _staging.ensureSession();
      final count = await _db
          .from('pwa_messages')
          .select('id')
          .eq('project_id', projectId);
      await _appendChildren(
        'pwa_messages',
        [_messageRow(projectId, message, count.length)],
        kPwaMessageImmutableKeys,
        'message',
      );
    } catch (e) {
      _map(e, 'appendMessage');
    }
  }

  @override
  Future<void> updateCurrentVision(String projectId, String visionId) =>
      _bumpProject(projectId, {
        'current_vision_id': visionId,
      }, 'updateCurrentVision');

  @override
  Future<void> updateCoverVision(String projectId, String visionId) =>
      _bumpProject(projectId, {
        'cover_vision_id': visionId,
      }, 'updateCoverVision');

  @override
  Future<void> renameProject(String projectId, String title) async {
    final t = title.trim();
    if (t.isEmpty) {
      throw const PwaRepositoryError.validation(
        'Project title must not be empty.',
      );
    }
    await _bumpProject(projectId, {'title': t}, 'renameProject');
  }

  @override
  Future<PwaProjectSnapshot> duplicateProject(String projectId) async {
    try {
      await _staging.ensureSession();
      final newId = await _db.rpc(
        'deep_duplicate_project',
        params: {'p_project_id': projectId, 'p_new_title': 'Copy'},
      );
      final snap = await loadProject(newId as String);
      if (snap == null) {
        throw const PwaRepositoryError.notFound(
          'Duplicated project not found.',
        );
      }
      return snap;
    } catch (e) {
      _map(e, 'duplicateProject');
    }
  }

  @override
  Future<void> softDeleteProject(String projectId) async {
    try {
      await _staging.ensureSession();
      await _db.rpc('soft_delete_project', params: {'p_project_id': projectId});
      _revisions.remove(projectId);
    } catch (e) {
      _map(e, 'softDeleteProject');
    }
  }

  @override
  Future<Uint8List?> loadOriginalBytes(PwaProjectSnapshot snapshot) async {
    // A bundle asset has no Storage object — caller loads from the AssetBundle.
    if (pwaImageSourceForPath(snapshot.originalImageAsset) ==
        PwaImageSourceKind.bundle) {
      return null;
    }
    try {
      await _staging.ensureSession();
      return await _c.storage
          .from(_kBucket)
          .download(snapshot.originalImageAsset);
    } catch (e) {
      _map(e, 'loadOriginalBytes');
    }
  }

  // ── helpers ─────────────────────────────────────────────────────────────────

  /// Insert only genuinely-new child rows (§ point 4). Reads the rows already
  /// stored that match a local `id` OR `idempotency_key`, plans the append with
  /// [planIdempotentAppend] (identical retry → skipped; divergence / reused key
  /// → conflict), then inserts the new rows. Never UPDATEs an existing row. On a
  /// concurrent insert (23505) it re-reads and re-plans: an identical retry
  /// passes idempotently, a real divergence surfaces as conflict.
  Future<void> _appendChildren(
    String table,
    List<Map<String, dynamic>> rows,
    List<String> immutableKeys,
    String op,
  ) async {
    if (rows.isEmpty) return;
    final toInsert = planIdempotentAppend(
      localRows: rows,
      existingRows: await _matchingRows(table, rows),
      immutableKeys: immutableKeys,
      op: op,
    );
    if (toInsert.isEmpty) return; // fully idempotent — nothing new
    try {
      await _db.from(table).insert(toInsert);
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
      // A row landed between our read and write. Re-plan against fresh state.
      final again = planIdempotentAppend(
        localRows: toInsert,
        existingRows: await _matchingRows(table, toInsert),
        immutableKeys: immutableKeys,
        op: op,
      );
      if (again.isNotEmpty) rethrow; // still new yet insert failed → real error
    }
  }

  /// Rows in [table] whose `id` OR `idempotency_key` matches any of [rows].
  Future<List<Map<String, dynamic>>> _matchingRows(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    final ids = rows.map((r) => r['id']).whereType<String>().toSet();
    final keys = rows
        .map((r) => r['idempotency_key'])
        .whereType<String>()
        .toSet();
    final res = await _db
        .from(table)
        .select()
        .or('id.in.(${ids.join(',')}),idempotency_key.in.(${keys.join(',')})');
    return res.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> _bumpProject(
    String projectId,
    Map<String, dynamic> patch,
    String op,
  ) async {
    try {
      await _staging.ensureSession();
      final existing = await _db
          .from('pwa_projects')
          .select('revision')
          .eq('id', projectId)
          .maybeSingle();
      if (existing == null) {
        throw PwaRepositoryError.notFound('Project "$projectId" not found.');
      }
      final rev =
          _revisions[projectId] ?? (existing['revision'] as num).toInt();
      final updated = await _db
          .from('pwa_projects')
          .update({...patch, 'revision': rev + 1})
          .eq('id', projectId)
          .eq('revision', rev)
          .select('revision');
      if (updated.isEmpty) {
        throw const PwaRepositoryError.conflict(
          'Project changed elsewhere (revision mismatch).',
        );
      }
      _revisions[projectId] = rev + 1;
    } catch (e) {
      _map(e, op);
    }
  }

  Future<String> _uploadOriginal(String projectId, AydenImageSource src) async {
    final uid = _c.auth.currentUser!.id;
    final ext = _extFor(src);
    final objectId = _uuid.v4();
    final path = 'users/$uid/projects/$projectId/original/$objectId.$ext';
    await _c.storage
        .from(_kBucket)
        .uploadBinary(
          path,
          src.bytes,
          fileOptions: FileOptions(
            contentType: src.mimeType ?? 'image/jpeg',
            upsert: false,
          ),
        );
    return path;
  }

  String _extFor(AydenImageSource src) {
    final mime = (src.mimeType ?? '').toLowerCase();
    if (mime.contains('png')) return 'png';
    if (mime.contains('webp')) return 'webp';
    return 'jpg';
  }

  Map<String, dynamic> _visionRow(String projectId, PwaVision v) => {
    'id': v.versionId,
    'project_id': projectId,
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
    'idempotency_key': v.versionId,
    'schema_version': kPwaSchemaVersion,
  };

  Map<String, dynamic> _messageRow(String projectId, PwaMessage m, int order) =>
      {
        'id': m.id,
        'project_id': projectId,
        'role': pwaRoleToDb(m.role),
        'message_type': pwaMessageKindToDb(m.kind),
        'text_content': m.text.isEmpty ? null : m.text,
        'referenced_vision_id': m.visionId,
        'confirmation_state': m.pendingRefine != null ? 'pending' : null,
        'client_order': order,
        'idempotency_key': m.id,
        'metadata_json': {
          if (m.chips.isNotEmpty) 'chips': m.chips,
          if (m.pendingRefine != null) 'pending_refine': m.pendingRefine,
        },
        'schema_version': kPwaSchemaVersion,
      };

  Map<String, List<Map<String, dynamic>>> _groupBy(
    List<Map<String, dynamic>> rows,
    String key,
  ) {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      (out[r[key] as String] ??= []).add(Map<String, dynamic>.from(r));
    }
    return out;
  }

  Never _map(Object e, String op) {
    if (e is PwaRepositoryError) throw e;
    if (e is PostgrestException) {
      final code = e.code ?? '';
      if (code == '23505') {
        throw PwaRepositoryError(
          PwaErrorKind.conflict,
          'Duplicate in $op.',
          cause: e,
        );
      }
      if (code == '23503') {
        throw PwaRepositoryError(
          PwaErrorKind.validation,
          'Reference violation in $op.',
          cause: e,
        );
      }
      if (code == '42501' || code.startsWith('PGRST3')) {
        throw PwaRepositoryError(
          PwaErrorKind.unauthorized,
          'Not authorized ($op).',
          cause: e,
        );
      }
      if (code == 'PGRST204') {
        throw PwaRepositoryError(
          PwaErrorKind.serialization,
          'Unknown column ($op).',
          cause: e,
        );
      }
      throw PwaRepositoryError(
        PwaErrorKind.network,
        'Query failed ($op).',
        cause: e,
      );
    }
    if (e is StorageException) {
      throw PwaRepositoryError(
        PwaErrorKind.storage,
        'Storage failed ($op).',
        cause: e,
      );
    }
    if (e is AuthException) {
      throw PwaRepositoryError(
        PwaErrorKind.unauthorized,
        'Auth failed ($op).',
        cause: e,
      );
    }
    throw PwaRepositoryError(PwaErrorKind.unknown, '$op failed.', cause: e);
  }
}
