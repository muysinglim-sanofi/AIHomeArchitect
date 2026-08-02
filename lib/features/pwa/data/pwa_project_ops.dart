/// Batch 3.0 — pure domain-graph operations shared by persistence adapters.
///
/// [pwaDeepDuplicate] produces a fully INDEPENDENT project graph: every
/// versionId and messageId is reallocated and every cross-reference (projectId,
/// parent lineage, sourceMessageId, message→vision, current/cover) is remapped,
/// with immutable collections. Mirrors the mock content-repository behaviour so
/// duplication is identical whether it happens in memory or over staging.
library;

import '../domain/pwa_models.dart';
import '../domain/pwa_project.dart';

PwaProjectSnapshot pwaDeepDuplicate(
  PwaProjectSnapshot src, {
  required String newProjectId,
  required String newTitle,
  required int createdOrder,
  required int updatedOrder,
  String updatedLabel = 'Updated just now',
}) {
  final vMap = <String, String>{
    for (var i = 0; i < src.visions.length; i++)
      src.visions[i].versionId: '$newProjectId-v${i + 1}',
  };
  final mMap = <String, String>{
    for (var i = 0; i < src.messages.length; i++)
      src.messages[i].id: '$newProjectId-m${i + 1}',
  };

  final visions = <PwaVision>[
    for (final v in src.visions)
      PwaVision(
        versionId: vMap[v.versionId]!,
        projectId: newProjectId,
        visionNumber: v.visionNumber,
        title: v.title,
        atmosphereId: v.atmosphereId,
        actionType: v.actionType,
        afterAsset: v.afterAsset,
        order: v.order,
        parentVersionId: v.parentVersionId == null
            ? null
            : vMap[v.parentVersionId],
        sourceMessageId: v.sourceMessageId == null
            ? null
            : mMap[v.sourceMessageId],
        instruction: v.instruction,
        isCurrent: v.isCurrent,
      ),
  ];

  final messages = <PwaMessage>[
    for (final m in src.messages)
      PwaMessage(
        id: mMap[m.id]!,
        role: m.role,
        kind: m.kind,
        text: m.text,
        visionId: m.visionId == null ? null : vMap[m.visionId],
        chips: List<String>.unmodifiable(m.chips),
        pendingRefine: m.pendingRefine,
      ),
  ];

  return PwaProjectSnapshot(
    projectId: newProjectId,
    title: newTitle,
    originalImageAsset: src.originalImageAsset,
    roomId: src.roomId,
    roomLabel: src.roomLabel,
    selectedAtmosphereId: src.selectedAtmosphereId,
    atmosphereLabel: src.atmosphereLabel,
    visions: List<PwaVision>.unmodifiable(visions),
    messages: List<PwaMessage>.unmodifiable(messages),
    currentVisionId: src.currentVisionId == null
        ? null
        : vMap[src.currentVisionId],
    coverVisionId: src.coverVisionId == null ? null : vMap[src.coverVisionId],
    createdOrder: createdOrder,
    updatedOrder: updatedOrder,
    updatedLabel: updatedLabel,
    status: src.status,
    source: src.source,
  );
}
