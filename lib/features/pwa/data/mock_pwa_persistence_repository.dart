/// Batch 3.0 — offline persistence adapter.
///
/// Deterministic, no network. Stores each project as SERIALIZED records (the
/// same record shape a staging row would use) in memory, so every save/load
/// round-trips through [pwa_project_serialization] — proving the mapping
/// contract without a backend. Scoped to a single fixed installation id.
library;

import 'dart:typed_data';

import '../domain/pwa_models.dart';
import '../domain/pwa_project.dart';
import 'pwa_persistence_repository.dart';
import 'pwa_project_ops.dart';
import 'pwa_project_serialization.dart';
import 'pwa_repository_error.dart';

class MockPwaPersistenceRepository implements PwaPersistenceRepository {
  MockPwaPersistenceRepository({this.installationId = 'mock-installation'});

  final String installationId;

  final Map<String, PwaProjectRecords> _store = {};
  final Set<String> _deleted = {};
  int _seq = 0;
  int _order = 1000;

  int _nextOrder() => ++_order;

  PwaProjectRecords _require(String projectId) {
    final rec = _store[projectId];
    if (rec == null || _deleted.contains(projectId)) {
      throw PwaRepositoryError.notFound('Project "$projectId" not found.');
    }
    return rec;
  }

  @override
  Future<PwaInstallationIdentity> ensureInstallation() async =>
      PwaInstallationIdentity(installationId);

  @override
  Future<void> healthCheck() async {}

  @override
  Future<List<PwaProjectSnapshot>> loadLibrary() async => [
    for (final entry in _store.entries)
      if (!_deleted.contains(entry.key))
        pwaSnapshotFromRecords(
          project: entry.value.project,
          visions: entry.value.visions,
          messages: entry.value.messages,
        ),
  ];

  @override
  Future<PwaProjectSnapshot?> loadProject(String projectId) async {
    if (_deleted.contains(projectId)) return null;
    final rec = _store[projectId];
    if (rec == null) return null;
    return pwaSnapshotFromRecords(
      project: rec.project,
      visions: rec.visions,
      messages: rec.messages,
    );
  }

  @override
  Future<void> saveProject(
    PwaProjectSnapshot project, {
    bool replaceOriginal = false,
  }) async {
    // Offline mock: originals are bundle assets with no Storage object, so
    // [replaceOriginal] is a no-op here (loadOriginalBytes always returns null).
    if (project.title.trim().isEmpty) {
      throw PwaRepositoryError.validation('Project title must not be empty.');
    }
    _store[project.projectId] = pwaRecordsFromSnapshot(
      project,
      installationId: installationId,
    );
    _deleted.remove(project.projectId);
  }

  @override
  Future<void> appendVision(String projectId, PwaVision vision) async {
    final snap = pwaSnapshotFromRecords(
      project: _require(projectId).project,
      visions: _require(projectId).visions,
      messages: _require(projectId).messages,
    );
    if (snap.visions.any((v) => v.versionId == vision.versionId)) {
      // Idempotent: appending the same vision id is a no-op (retry safety).
      return;
    }
    await saveProject(
      snap.copyWith(
        visions: [...snap.visions, vision],
        currentVisionId: vision.versionId,
        coverVisionId: vision.versionId,
        updatedOrder: _nextOrder(),
      ),
    );
  }

  @override
  Future<void> appendMessage(String projectId, PwaMessage message) async {
    final rec = _require(projectId);
    final snap = pwaSnapshotFromRecords(
      project: rec.project,
      visions: rec.visions,
      messages: rec.messages,
    );
    if (snap.messages.any((m) => m.id == message.id)) return; // idempotent
    await saveProject(snap.copyWith(messages: [...snap.messages, message]));
  }

  @override
  Future<void> updateCurrentVision(String projectId, String visionId) async {
    final rec = _require(projectId);
    final snap = pwaSnapshotFromRecords(
      project: rec.project,
      visions: rec.visions,
      messages: rec.messages,
    );
    await saveProject(
      snap.copyWith(currentVisionId: visionId, updatedOrder: _nextOrder()),
    );
  }

  @override
  Future<void> updateCoverVision(String projectId, String visionId) async {
    final rec = _require(projectId);
    final snap = pwaSnapshotFromRecords(
      project: rec.project,
      visions: rec.visions,
      messages: rec.messages,
    );
    await saveProject(snap.copyWith(coverVisionId: visionId));
  }

  @override
  Future<void> renameProject(String projectId, String title) async {
    final t = title.trim();
    if (t.isEmpty) {
      throw PwaRepositoryError.validation('Project title must not be empty.');
    }
    final rec = _require(projectId);
    final snap = pwaSnapshotFromRecords(
      project: rec.project,
      visions: rec.visions,
      messages: rec.messages,
    );
    await saveProject(snap.copyWith(title: t, updatedOrder: _nextOrder()));
  }

  @override
  Future<PwaProjectSnapshot> duplicateProject(String projectId) async {
    final rec = _require(projectId);
    final src = pwaSnapshotFromRecords(
      project: rec.project,
      visions: rec.visions,
      messages: rec.messages,
    );
    final o = _nextOrder();
    final dup = pwaDeepDuplicate(
      src,
      newProjectId: 'copy-${++_seq}',
      newTitle: '${src.title} Copy',
      createdOrder: o,
      updatedOrder: o,
    );
    await saveProject(dup);
    return dup;
  }

  @override
  Future<void> softDeleteProject(String projectId) async {
    _require(projectId);
    _deleted.add(projectId);
  }

  // Offline: originals are bundle assets — no bytes to fetch.
  @override
  Future<Uint8List?> loadOriginalBytes(PwaProjectSnapshot snapshot) async =>
      null;

  /// Offline: there is no Storage and no backend, so there is nothing to
  /// prepare. Persists the row (so a Draft round-trips) and reports the bundle
  /// asset as the original — the mock generation service ignores it anyway.
  @override
  Future<PwaOriginalUpload> prepareGeneration(
    PwaProjectSnapshot snapshot, {
    bool replaceOriginal = false,
  }) async {
    await saveProject(snapshot);
    return PwaOriginalUpload.forPath(
      snapshot.projectId,
      snapshot.originalImageAsset,
    );
  }

  /// A bundle asset needs no signature; anything else would mean the offline
  /// adapter is being asked to reach a Storage it does not have.
  @override
  Future<String> signedImageUrl(String path, int expiresInSeconds) async {
    if (path.startsWith('assets/')) return path;
    throw PwaRepositoryError.configuration(
      'The offline adapter cannot sign a Storage path (got "$path").',
    );
  }
}
