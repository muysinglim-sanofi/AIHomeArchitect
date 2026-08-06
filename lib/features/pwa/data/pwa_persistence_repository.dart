/// Batch 3.0 — the persistence abstraction (§14).
///
/// Presentation → Controller/Application → PwaPersistenceRepository → Adapter.
/// Widgets never touch Supabase/HTTP. Two adapters exist:
///   • [MockPwaPersistenceRepository] — offline, deterministic, round-trips the
///     serialization layer in memory (no network).
///   • [StagingPwaPersistenceRepository] — staging persistence, fail-closed,
///     never falls back to production or mock.
///
/// Every operation returns domain data or throws a [PwaRepositoryError].
library;

import 'dart:typed_data';

import '../domain/pwa_models.dart';
import '../domain/pwa_project.dart';

/// Staging tenancy identity (§5). An opaque, random, STAGING-ONLY installation
/// id. NOT authentication and NOT cross-device — it only scopes staging data.
class PwaInstallationIdentity {
  const PwaInstallationIdentity(this.installationId);
  final String installationId;
}

/// What [PwaPersistenceRepository.prepareGeneration] hands back: the durable
/// facts a generation needs, resolved by the layer that actually performed the
/// upload rather than re-derived (or re-read) by the caller.
///
/// [originalStoragePath] is the PRIVATE Storage path — the durable source of
/// truth. A signed URL is deliberately absent: minting one here would invite a
/// caller to persist it, and a persisted URL silently expires.
class PwaOriginalUpload {
  const PwaOriginalUpload({
    required this.projectId,
    required this.originalStoragePath,
    required this.originalMimeType,
    required this.originalExtension,
  });

  /// Derive the pair (mime, extension) from a canonical path, so a reused
  /// original and a fresh upload describe themselves identically.
  factory PwaOriginalUpload.forPath(
    String projectId,
    String path, {
    String? mimeType,
  }) {
    final dot = path.lastIndexOf('.');
    final ext = dot < 0 ? 'jpg' : path.substring(dot + 1).toLowerCase();
    return PwaOriginalUpload(
      projectId: projectId,
      originalStoragePath: path,
      originalMimeType: mimeType ?? pwaMimeForExtension(ext),
      originalExtension: ext,
    );
  }

  final String projectId;
  final String originalStoragePath;
  final String originalMimeType;
  final String originalExtension;
}

/// The MIME an image extension maps to (jpeg is the default, matching the
/// upload path's own default).
String pwaMimeForExtension(String extension) => switch (extension) {
  'png' => 'image/png',
  'webp' => 'image/webp',
  _ => 'image/jpeg',
};

abstract class PwaPersistenceRepository {
  /// Load (or lazily create) the staging tenancy identity for this browser.
  Future<PwaInstallationIdentity> ensureInstallation();

  /// Cheap reachability/permission probe. Throws a typed error when unavailable
  /// so hydration can render a non-destructive retry state (§15).
  Future<void> healthCheck();

  /// All non-deleted projects for this installation.
  Future<List<PwaProjectSnapshot>> loadLibrary();

  /// A single project's full graph, or null if unknown / soft-deleted.
  Future<PwaProjectSnapshot?> loadProject(String projectId);

  /// Idempotent upsert of a project's FULL graph, keyed by projectId (§16).
  ///
  /// [replaceOriginal] — Step 5: the session's original photo was REPLACED and
  /// its new bytes ([PwaProjectSnapshot.source]) must become the authoritative
  /// durable original even on an already-persisted project. When false the
  /// original is treated as immutable (the row's existing path is preserved).
  /// The caller sets this ONLY when the photo actually changed, so a Rename /
  /// Room / Atmosphere save never re-uploads.
  Future<void> saveProject(
    PwaProjectSnapshot project, {
    bool replaceOriginal = false,
  });

  /// Append-only vision write. Never overwrites an existing vision.
  Future<void> appendVision(String projectId, PwaVision vision);

  /// Append-only message write, preserving chronology.
  Future<void> appendMessage(String projectId, PwaMessage message);

  Future<void> updateCurrentVision(String projectId, String visionId);
  Future<void> updateCoverVision(String projectId, String visionId);

  Future<void> renameProject(String projectId, String title);

  /// Deep, fully-independent duplicate (§9-11). Returns the new project.
  Future<PwaProjectSnapshot> duplicateProject(String projectId);

  /// Soft delete — hidden from [loadLibrary], not physically purged (§16).
  Future<void> softDeleteProject(String projectId);

  /// Make [snapshot] GENERATABLE and report where its original now lives.
  ///
  /// Two things must be true before the backend can render anything: the
  /// project ROW must exist (the backend loads it and checks ownership), and
  /// the original photo must be a private Storage object under
  /// `users/{uid}/projects/{projectId}/original/{objectId}.{ext}` (the backend
  /// downloads it and rejects any path outside that namespace).
  ///
  /// Idempotent by design: an already-uploaded original is REUSED, so a retry
  /// of the same generation uploads nothing. [replaceOriginal] forces a fresh
  /// upload when the user actually replaced the photo.
  ///
  /// Returns the canonical durable path — never a signed URL.
  Future<PwaOriginalUpload> prepareGeneration(
    PwaProjectSnapshot snapshot, {
    bool replaceOriginal = false,
  });

  /// Mint a temporary URL the browser can render for the PRIVATE Storage object
  /// at [path], valid for [expiresInSeconds].
  ///
  /// Deliberately short-lived and never persisted: the path is the durable
  /// truth, this is only how a pixel reaches the screen.
  Future<String> signedImageUrl(String path, int expiresInSeconds);

  /// The original photo bytes for [snapshot], for rebuilding an in-memory
  /// [AydenImageSource] on hydration (the bytes are never stored on the row).
  /// Returns null for a bundle-asset original (no Storage object) so the caller
  /// falls back to the AssetBundle.
  Future<Uint8List?> loadOriginalBytes(PwaProjectSnapshot snapshot);
}
