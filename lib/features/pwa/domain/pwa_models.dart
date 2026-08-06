/// Batch 2 — pure domain models for the mocked PWA signature experience.
///
/// No Flutter widgets, no dart:io, no backend/Supabase/RevenueCat types. These
/// describe a design conversation (messages) and a branched version tree
/// (visions) entirely in memory, so the prototype is deterministic and
/// pure-Dart testable.
library;

/// Who authored a conversation message.
enum PwaRole { ayden, user }

/// What a conversation message renders as.
enum PwaMessageKind {
  /// Plain text (Ayden explanation / advice, or a user line / system note).
  text,

  /// A rich Full-Reveal card bound to a [PwaMessage.visionId]. The FIRST Ayden
  /// message after generation is of this kind (Full Reveal in-conversation).
  reveal,

  /// A deterministic "generating…" placeholder shown while a mocked vision is
  /// produced; replaced by a [reveal] message on completion.
  loading,
}

/// How a vision was produced — drives titles and the version tree.
enum PwaActionType { signature, refine, switchAtmosphere }

/// The three mocked conversation intents.
enum PwaIntent { advice, refine, switchAtmosphere }

/// An Ayden atmosphere (selector item). [asset] is the selector thumbnail;
/// [visionAsset] is the mocked "result" image a switch produces.
class PwaAtmosphere {
  const PwaAtmosphere({
    required this.id,
    required this.name,
    required this.asset,
    required this.visionAsset,
    this.descriptor = '',
    this.isSignature = false,
  });

  final String id;
  final String name;
  final String asset;
  final String visionAsset;

  /// Short three-word mood descriptor rendered under the atmosphere card
  /// ("Warm · Timeless · Balanced"). Empty when unspecified.
  final String descriptor;

  final bool isSignature;
}

/// A single design vision in the branched version tree.
class PwaVision {
  const PwaVision({
    required this.versionId,
    required this.projectId,
    required this.visionNumber,
    required this.title,
    required this.atmosphereId,
    required this.actionType,
    required this.afterAsset,
    required this.order,
    this.parentVersionId,
    this.sourceMessageId,
    this.instruction = '',
    this.isCurrent = false,
    this.remotePersisted = false,
  });

  final String versionId;
  final String? parentVersionId;
  final String? sourceMessageId;
  final String projectId;
  final int visionNumber;
  final String title;
  final String atmosphereId;
  final PwaActionType actionType;
  final String instruction;

  /// Where the "after" image lives: a private Storage PATH for a real
  /// generation (`users/{uid}/projects/{id}/generated/{visionId}.jpg`), or a
  /// bundle asset (`assets/...`) in the offline mock. Never a signed URL — a URL
  /// expires, a path does not.
  final String afterAsset;

  /// Deterministic creation order (replaces a wall-clock timestamp so tests are
  /// stable). Higher = more recent.
  final int order;

  final bool isCurrent;

  /// True when the ROW for this vision was already written by the backend (a
  /// real generation) or read back from it. The durable save then skips it: the
  /// backend owns that row, and re-appending it locally would either duplicate
  /// it or collide on its idempotency key. Purely a persistence concern — the
  /// domain treats a remote and a local vision identically everywhere else.
  final bool remotePersisted;

  /// Human label for the creation reason (mobile "Created from…" line).
  String get reasonLabel => switch (actionType) {
    PwaActionType.signature => 'Ayden Signature',
    PwaActionType.switchAtmosphere => 'Atmosphere · $atmosphereId',
    PwaActionType.refine =>
      instruction.isEmpty ? 'Refinement' : 'Refine · $instruction',
  };

  PwaVision copyWith({bool? isCurrent}) => PwaVision(
    versionId: versionId,
    projectId: projectId,
    visionNumber: visionNumber,
    title: title,
    atmosphereId: atmosphereId,
    actionType: actionType,
    afterAsset: afterAsset,
    order: order,
    parentVersionId: parentVersionId,
    sourceMessageId: sourceMessageId,
    instruction: instruction,
    isCurrent: isCurrent ?? this.isCurrent,
    remotePersisted: remotePersisted,
  );
}

/// A conversation message. A [reveal]/[loading] message binds to a vision via
/// [visionId]; a [text] message carries [text] (and optional action [chips]).
class PwaMessage {
  const PwaMessage({
    required this.id,
    required this.role,
    required this.kind,
    this.text = '',
    this.visionId,
    this.chips = const <String>[],
    this.pendingRefine,
  });

  final String id;
  final PwaRole role;
  final PwaMessageKind kind;
  final String text;
  final String? visionId;
  final List<String> chips;

  /// When set, this Ayden advice message offers an "Apply this change" action
  /// that would create a refine child from the given instruction.
  final String? pendingRefine;
}

/// The mocked project (uploaded room → design session).
class PwaProject {
  const PwaProject({
    required this.projectId,
    required this.originalAsset,
    required this.title,
  });

  final String projectId;
  final String originalAsset;
  final String title;
}
