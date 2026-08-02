/// Batch 2.3 — My Projects library domain (pure, offline, in-memory).
///
/// A [PwaProjectSnapshot] captures ONE complete design session — the uploaded
/// (or seeded) space, its Room / Atmosphere, the full immutable Vision tree and
/// the chronological conversation — so a project can be listed in the library
/// and RESUMED exactly where it was left. No Flutter widgets, no dart:io, no
/// backend / Supabase / RevenueCat types.
///
/// Determinism: like [PwaVision.order], ordering uses integer sequences
/// ([createdOrder] / [updatedOrder]) instead of a wall clock, and the display
/// freshness is a pre-rendered [updatedLabel] string — so the whole library
/// sorts and renders deterministically in tests.
library;

import '../../../core/media/ayden_image_source.dart';
import 'pwa_models.dart';

/// Lifecycle of a mocked project.
enum PwaProjectStatus {
  /// Uploaded / drafted but no vision generated yet (not yet in the library).
  draft,

  /// Has at least one vision — a real, listed project.
  active,
}

/// Client-side sort order for the library (deterministic).
enum PwaProjectSort { recentlyUpdated, newest, oldest, nameAsc }

extension PwaProjectSortLabel on PwaProjectSort {
  String get label => switch (this) {
    PwaProjectSort.recentlyUpdated => 'Recently updated',
    PwaProjectSort.newest => 'Newest',
    PwaProjectSort.oldest => 'Oldest',
    PwaProjectSort.nameAsc => 'Name A–Z',
  };
}

/// An immutable snapshot of a complete design session.
class PwaProjectSnapshot {
  const PwaProjectSnapshot({
    required this.projectId,
    required this.title,
    required this.originalImageAsset,
    required this.roomId,
    required this.roomLabel,
    required this.selectedAtmosphereId,
    required this.atmosphereLabel,
    required this.visions,
    required this.messages,
    required this.currentVisionId,
    required this.createdOrder,
    required this.updatedOrder,
    required this.updatedLabel,
    required this.status,
    this.source,
    this.coverVisionId,
  });

  final String projectId;
  final String title;

  /// The "before" asset (rendered when [source] bytes are absent — always the
  /// case for seeded projects and for anything reopened from the library).
  final String originalImageAsset;

  /// Fast-path Room choice (null = Ayden Decide) and its display label.
  final String? roomId;
  final String roomLabel;

  final String? selectedAtmosphereId;

  /// Display label for the current atmosphere (denormalised for the card).
  final String atmosphereLabel;

  final List<PwaVision> visions;
  final List<PwaMessage> messages;
  final String? currentVisionId;

  /// Deterministic ordering keys (higher = more recent). No wall clock.
  final int createdOrder;
  final int updatedOrder;

  /// Pre-rendered freshness label ("Updated today", "Yesterday", "3 days ago").
  final String updatedLabel;

  final PwaProjectStatus status;

  /// Original bytes for a real user upload; null for seeded / reopened projects
  /// (which render the "before" from [originalImageAsset]).
  final AydenImageSource? source;

  /// Cover thumbnail vision (defaults to the current vision).
  final String? coverVisionId;

  int get visionCount => visions.length;

  PwaVision? _byId(String? id) {
    if (id == null) return null;
    for (final v in visions) {
      if (v.versionId == id) return v;
    }
    return null;
  }

  /// The vision whose image represents the project on its card.
  PwaVision? get coverVision =>
      _byId(coverVisionId) ??
      _byId(currentVisionId) ??
      (visions.isEmpty ? null : visions.last);

  PwaProjectSnapshot copyWith({
    String? title,
    String? originalImageAsset,
    String? roomId,
    String? roomLabel,
    String? selectedAtmosphereId,
    String? atmosphereLabel,
    List<PwaVision>? visions,
    List<PwaMessage>? messages,
    String? currentVisionId,
    int? createdOrder,
    int? updatedOrder,
    String? updatedLabel,
    PwaProjectStatus? status,
    AydenImageSource? source,
    String? coverVisionId,
  }) => PwaProjectSnapshot(
    projectId: projectId,
    title: title ?? this.title,
    originalImageAsset: originalImageAsset ?? this.originalImageAsset,
    roomId: roomId ?? this.roomId,
    roomLabel: roomLabel ?? this.roomLabel,
    selectedAtmosphereId: selectedAtmosphereId ?? this.selectedAtmosphereId,
    atmosphereLabel: atmosphereLabel ?? this.atmosphereLabel,
    visions: visions ?? this.visions,
    messages: messages ?? this.messages,
    currentVisionId: currentVisionId ?? this.currentVisionId,
    createdOrder: createdOrder ?? this.createdOrder,
    updatedOrder: updatedOrder ?? this.updatedOrder,
    updatedLabel: updatedLabel ?? this.updatedLabel,
    status: status ?? this.status,
    source: source ?? this.source,
    coverVisionId: coverVisionId ?? this.coverVisionId,
  );

  /// Pure library ordering (deterministic — no wall clock).
  static List<PwaProjectSnapshot> sortedBy(
    List<PwaProjectSnapshot> items,
    PwaProjectSort order,
  ) {
    final list = [...items];
    switch (order) {
      case PwaProjectSort.recentlyUpdated:
        list.sort((a, b) => b.updatedOrder.compareTo(a.updatedOrder));
      case PwaProjectSort.newest:
        list.sort((a, b) => b.createdOrder.compareTo(a.createdOrder));
      case PwaProjectSort.oldest:
        list.sort((a, b) => a.createdOrder.compareTo(b.createdOrder));
      case PwaProjectSort.nameAsc:
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
    }
    return list;
  }

  /// Pure, case-insensitive search across title / room / atmosphere.
  static List<PwaProjectSnapshot> search(
    List<PwaProjectSnapshot> items,
    String query,
  ) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [...items];
    return [
      for (final p in items)
        if (p.title.toLowerCase().contains(q) ||
            p.roomLabel.toLowerCase().contains(q) ||
            p.atmosphereLabel.toLowerCase().contains(q))
          p,
    ];
  }
}
