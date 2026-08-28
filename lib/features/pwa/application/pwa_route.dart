/// Batch 3.4 — the PWA's durable, web-native route model (pure Dart).
///
/// The browser URL is the primary navigation authority (F5 reloads the same
/// durable page; Back/Forward work). A route carries ONLY durable navigation
/// identity — page, project id, optional selected vision id — never project
/// data (title/Room/Atmosphere/image/visions/messages), which always comes from
/// the persistence repository.
///
/// Route map:
///   /                                  → Home dashboard
///   /create                            → New project (local, pre-Generate)
///   /projects                          → My Projects
///   /projects/:id/draft                → Draft Fast Path
///   /projects/:id/architect            → Architect (the conversation)
///   /projects/:id/architect?vision=:v  → Architect with a selected vision
///   /projects/:id/reveal?vision=:v     → Full Reveal for that vision
///   …&mode=first                       → the one-off First Reveal after Generate
library;

import '../domain/pwa_project.dart';

enum PwaPage { home, create, projects, profile, draft, architect, reveal }

class PwaRoute {
  const PwaRoute(
    this.page, {
    this.projectId,
    this.visionId,
    this.firstLook = false,
  });

  final PwaPage page;
  final String? projectId;
  final String? visionId;

  /// Reveal only — the immersive one-off shown right after the first Generate.
  /// It is a presentation mode of the same vision, never a second entity.
  final bool firstLook;

  static const PwaRoute home = PwaRoute(PwaPage.home);
  static const PwaRoute create = PwaRoute(PwaPage.create);
  static const PwaRoute projects = PwaRoute(PwaPage.projects);
  static const PwaRoute profile = PwaRoute(PwaPage.profile);

  /// Parse a browser [uri] into a route. Unknown shapes fall back to the nearest
  /// safe page (unknown top-level → Home; malformed under /projects → Projects).
  static PwaRoute parse(Uri uri) {
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) return home;
    if (segs.first == 'create') return create;
    if (segs.first == 'profile') return profile;
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
        case 'reveal':
          final v = uri.queryParameters['vision'];
          return PwaRoute(
            PwaPage.reveal,
            projectId: id,
            visionId: (v != null && v.isNotEmpty) ? v : null,
            firstLook: uri.queryParameters['mode'] == 'first',
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
      case PwaPage.create:
        return '/create';
      case PwaPage.projects:
        return '/projects';
      case PwaPage.profile:
        return '/profile';
      case PwaPage.draft:
        return '/projects/$projectId/draft';
      case PwaPage.architect:
        final q = (visionId != null && visionId!.isNotEmpty)
            ? '?vision=$visionId'
            : '';
        return '/projects/$projectId/architect$q';
      case PwaPage.reveal:
        final q = (visionId != null && visionId!.isNotEmpty)
            ? '?vision=$visionId${firstLook ? '&mode=first' : ''}'
            : '';
        return '/projects/$projectId/reveal$q';
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
      case PwaPage.create:
        // A creation session is purely local — it is always a valid destination
        // and never depends on the durable library.
        return create;
      case PwaPage.projects:
        return projects;
      case PwaPage.profile:
        // Profile depends on nothing durable — no project, no vision — so it
        // is always a valid destination, exactly like Create.
        return profile;
      case PwaPage.draft:
      case PwaPage.architect:
      case PwaPage.reveal:
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
        if (route.page == PwaPage.reveal) {
          // A Reveal is only meaningful for a vision that exists IN THIS
          // project. An absent / unknown / foreign vision NEVER silently
          // resolves to a different one — it falls back to the conversation.
          final v = route.visionId;
          final valid =
              hasVisions && v != null && p.visions.any((x) => x.versionId == v);
          if (!valid) {
            return hasVisions
                ? PwaRoute(PwaPage.architect, projectId: p.projectId)
                : PwaRoute(PwaPage.draft, projectId: p.projectId);
          }
          return PwaRoute(
            PwaPage.reveal,
            projectId: p.projectId,
            visionId: v,
            firstLook: route.firstLook,
          );
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
      other.visionId == visionId &&
      other.firstLook == firstLook;

  @override
  int get hashCode => Object.hash(page, projectId, visionId, firstLook);

  @override
  String toString() => 'PwaRoute($location)';
}
