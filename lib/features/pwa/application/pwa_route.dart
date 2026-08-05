/// Batch 3.4 — the PWA's durable, web-native route model (pure Dart).
///
/// The browser URL is the primary navigation authority (F5 reloads the same
/// durable page; Back/Forward work). A route carries ONLY durable navigation
/// identity — page, project id, optional selected vision id — never project
/// data (title/Room/Atmosphere/image/visions/messages), which always comes from
/// the persistence repository.
///
/// Route map:
///   /                                  → Home / Hero
///   /projects                          → My Projects
///   /projects/:id/draft                → Draft Fast Path
///   /projects/:id/architect            → Architect
///   /projects/:id/architect?vision=:v  → Architect with a selected vision
library;

import '../domain/pwa_project.dart';

enum PwaPage { home, projects, draft, architect }

class PwaRoute {
  const PwaRoute(this.page, {this.projectId, this.visionId});

  final PwaPage page;
  final String? projectId;
  final String? visionId;

  static const PwaRoute home = PwaRoute(PwaPage.home);
  static const PwaRoute projects = PwaRoute(PwaPage.projects);

  /// Parse a browser [uri] into a route. Unknown shapes fall back to the nearest
  /// safe page (unknown top-level → Home; malformed under /projects → Projects).
  static PwaRoute parse(Uri uri) {
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) return home;
    if (segs.first != 'projects') return home;
    if (segs.length == 1) return projects;
    final id = segs[1];
    if (id.isEmpty) return projects;
    if (segs.length >= 3) {
      switch (segs[2]) {
        case 'draft':
          return PwaRoute(PwaPage.draft, projectId: id);
        case 'architect':
          final v = uri.queryParameters['vision'];
          return PwaRoute(
            PwaPage.architect,
            projectId: id,
            visionId: (v != null && v.isNotEmpty) ? v : null,
          );
      }
    }
    return projects; // /projects/:id with no/unknown leaf → the library
  }

  /// The canonical URL string for this route.
  String get location {
    switch (page) {
      case PwaPage.home:
        return '/';
      case PwaPage.projects:
        return '/projects';
      case PwaPage.draft:
        return '/projects/$projectId/draft';
      case PwaPage.architect:
        final q = (visionId != null && visionId!.isNotEmpty)
            ? '?vision=$visionId'
            : '';
        return '/projects/$projectId/architect$q';
    }
  }

  /// Apply the §5 fallback + normalization rules against the durable library.
  /// [lookup] returns the snapshot for an id (null if unknown/deleted);
  /// [libraryEmpty] decides the unknown-project fallback (Projects vs Home).
  static PwaRoute normalize(
    PwaRoute route, {
    required PwaProjectSnapshot? Function(String id) lookup,
    required bool libraryEmpty,
  }) {
    switch (route.page) {
      case PwaPage.home:
        return home;
      case PwaPage.projects:
        return projects;
      case PwaPage.draft:
      case PwaPage.architect:
        final id = route.projectId;
        final p = id == null ? null : lookup(id);
        if (p == null) {
          // Unknown / deleted / inaccessible → never open another project.
          return libraryEmpty ? home : projects;
        }
        final hasVisions = p.visions.isNotEmpty;
        // Draft URL for a generated project → its Architect (and vice versa).
        if (route.page == PwaPage.draft && hasVisions) {
          return PwaRoute(PwaPage.architect, projectId: p.projectId);
        }
        if (route.page == PwaPage.architect && !hasVisions) {
          return PwaRoute(PwaPage.draft, projectId: p.projectId);
        }
        if (route.page == PwaPage.architect) {
          // Invalid vision query → keep the project, drop to current vision.
          final v = route.visionId;
          final valid = v != null && p.visions.any((x) => x.versionId == v);
          return PwaRoute(
            PwaPage.architect,
            projectId: p.projectId,
            visionId: valid ? v : null,
          );
        }
        return PwaRoute(PwaPage.draft, projectId: p.projectId);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PwaRoute &&
      other.page == page &&
      other.projectId == projectId &&
      other.visionId == visionId;

  @override
  int get hashCode => Object.hash(page, projectId, visionId);

  @override
  String toString() => 'PwaRoute($location)';
}
