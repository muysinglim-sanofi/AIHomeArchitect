// Wave 5.12b — branchEvent : a narrative event inserted into the chat
// timeline when the user taps "Continue this vision" on an older render.
// Persisted in the messages table with message_type='branch_event' (role
// 'system'). Carries a [GeneratedResult] pointing at the SOURCE vision
// (thumbnail + styleLabel) so the card can render without re-resolving
// the source from elsewhere. Distinct from [system] (calm italic centre
// line) and [imageResult] (the generated render). Future branching
// waves will derive a vision graph from these events without touching
// the backend schema.
enum MessageType {
  text,
  imageResult,
  loading,
  system,
  branchEvent,
  advisory,
  refineReport
}

/// Refine V2 (8b-3) — données d'une carte advisory (YELLOW/RED de l'Advisor).
/// Porte le message d'origine pour relancer /refine avec confirm=true (Try anyway)
/// de façon DÉTERMINISTE, sans repasser par le classifieur /chat.
class AdvisoryInfo {
  final String verdict; // 'yellow' | 'red'
  final String originalMessage; // le message user d'origine → relance confirm=true
  final String roomType;
  const AdvisoryInfo({
    required this.verdict,
    required this.originalMessage,
    this.roomType = '',
  });
}

/// Refine V2 (8b-4b) — données d'une carte « Still missing » (verify INCOMPLETE).
/// [report] = texte Applied ✓ / Still missing □ construit par le backend (P3).
/// [missingRaws] = les instructions EXACTES (champ `raw`) des seuls changements NON
/// appliqués (dédupliquées, ordre préservé) → [Retry] les rejoue de façon CIBLÉE sur
/// l'image incomplète (confirm=true, pas de re-advisory).
/// [afterUrl] + [sourceVersionId] = l'ANCRE de la vision incomplète EXACTE. Sans elle,
/// un Retry cliqué sur une vieille carte s'appliquerait à la vision courante (« bonne
/// modif, mauvaise vision »). [afterUrl] est comparé au tip actif pour n'autoriser le
/// Retry que si cette vision est toujours la source active.
/// N'existe QUE sur `verification == incomplete`. [Keep] masque les boutons.
class RefineReportInfo {
  final String report;
  final List<String> missingRaws;
  final String afterUrl; // ancre : l'image incomplète exacte (= tip au moment T)
  final String sourceVersionId; // ancre secondaire (version du résultat incomplet)
  const RefineReportInfo({
    required this.report,
    required this.missingRaws,
    required this.afterUrl,
    this.sourceVersionId = '',
  });
}

/// 8b-4b — un [Retry] n'est autorisé QUE si la carte est ancrée à l'image
/// actuellement active (le tip de la lignée). Empêche d'appliquer les changements
/// manquants d'une vision ANCIENNE sur une vision plus récente — le seul risque
/// capable d'appliquer une modif correcte sur la mauvaise vision. Pur → testable.
bool refineRetryAllowed(RefineReportInfo info, String? activeSourceUrl) {
  if (info.missingRaws.isEmpty) return false;
  if (info.afterUrl.isEmpty) return false;
  return info.afterUrl == activeSourceUrl;
}

/// 8b-4b — dédup en préservant l'ordre (comparaison trimée, insensible à la casse)
/// pour ne jamais renvoyer deux fois la même instruction au parser refine, et pour
/// écarter les entrées vides. Pur → testable.
List<String> dedupePreservingOrder(Iterable<String> items) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in items) {
    final s = raw.trim();
    if (s.isEmpty) continue;
    if (seen.add(s.toLowerCase())) out.add(s);
  }
  return out;
}

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
  final AdvisoryInfo? advisory; // non-null quand type == MessageType.advisory
  final RefineReportInfo? refineReport; // non-null quand type == refineReport
  final DateTime createdAt;

  const MessageModel({
    required this.id,
    required this.content,
    required this.isAi,
    this.type = MessageType.text,
    this.result,
    this.advisory,
    this.refineReport,
    required this.createdAt,
  });
}

/// CHANTIER A — room lock. True once the session has produced at least one
/// generated vision. After this the room is IMMUTABLE for the lineage: an
/// atmosphere switch — or a re-upload (which keeps the prior visions in the
/// chat) — must never change it. Pure → unit-testable.
bool sessionHasVision(Iterable<MessageModel> messages) =>
    messages.any((m) => m.type == MessageType.imageResult);
