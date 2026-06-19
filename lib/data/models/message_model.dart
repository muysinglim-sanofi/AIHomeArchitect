// Wave 5.12b — branchEvent : a narrative event inserted into the chat
// timeline when the user taps "Continue this vision" on an older render.
// Persisted in the messages table with message_type='branch_event' (role
// 'system'). Carries a [GeneratedResult] pointing at the SOURCE vision
// (thumbnail + styleLabel) so the card can render without re-resolving
// the source from elsewhere. Distinct from [system] (calm italic centre
// line) and [imageResult] (the generated render). Future branching
// waves will derive a vision graph from these events without touching
// the backend schema.
enum MessageType { text, imageResult, loading, system, branchEvent }

class GeneratedResult {
  final String beforeImageUrl;
  final String afterImageUrl;
  final String styleLabel;
  final String projectId;

  // The room this vision was generated for. Lets an atmosphere switch on this
  // vision restore ITS room instead of a stale session-level global — the root
  // cause of the cross-vision room leak when several uploads share one chat
  // session. Nullable so legacy results (loaded from DB without a room) simply
  // fall back to the current room.
  final String? roomType;

  // Wave 4.9.3 — display label for the COMPARISON SOURCE (the left side of the
  // Full Reveal before/after), e.g. "Original", an atmosphere name ("Warm
  // Modern"), or — in future — "Vision #2" / "Branch A". Deliberately a
  // type-agnostic DISPLAY string (not a style/vision id) so it stays
  // future-proof for version branching / source selection. Computed at
  // navigation time from the in-memory timeline (chat_screen._openReveal), NOT
  // persisted — the timeline is rebuilt from the DB on reload, so it survives.
  // Null everywhere except the Full Reveal nav extra → the screen falls back.
  final String? sourceDisplayLabel;

  const GeneratedResult({
    required this.beforeImageUrl,
    required this.afterImageUrl,
    required this.styleLabel,
    required this.projectId,
    this.roomType,
    this.sourceDisplayLabel,
  });
}

/// The (source image, room) an atmosphere switch should evolve from when the
/// user changes atmosphere on a SPECIFIC vision. Binds to that vision's own
/// afterImageUrl + roomType so a multi-upload session can never leak an older
/// vision's source/room into the switch.
class AtmosphereSwitchTarget {
  final String? sourceUrl;
  final String? room;
  const AtmosphereSwitchTarget({this.sourceUrl, this.room});
}

/// Resolve the source + room an atmosphere switch must use, bound to [vision].
/// Uses the vision's own afterImageUrl (the render the switch evolves from) and
/// its own roomType; only falls back to [fallbackRoom] when the vision carries
/// no room (e.g. a legacy DB-loaded result). Pure → unit-testable.
AtmosphereSwitchTarget resolveAtmosphereSwitchTarget(
  GeneratedResult vision, {
  String? fallbackRoom,
}) {
  final src = vision.afterImageUrl.isNotEmpty ? vision.afterImageUrl : null;
  final r = vision.roomType;
  final room = (r != null && r.isNotEmpty) ? r : fallbackRoom;
  return AtmosphereSwitchTarget(sourceUrl: src, room: room);
}

class MessageModel {
  final String id;
  final String content;
  final bool isAi;
  final MessageType type;
  final GeneratedResult? result;
  final DateTime createdAt;

  const MessageModel({
    required this.id,
    required this.content,
    required this.isAi,
    this.type = MessageType.text,
    this.result,
    required this.createdAt,
  });
}

/// CHANTIER A — room lock. True once the session has produced at least one
/// generated vision. After this the room is IMMUTABLE for the lineage: an
/// atmosphere switch — or a re-upload (which keeps the prior visions in the
/// chat) — must never change it. Pure → unit-testable.
bool sessionHasVision(Iterable<MessageModel> messages) =>
    messages.any((m) => m.type == MessageType.imageResult);
