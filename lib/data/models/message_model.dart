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

  const GeneratedResult({
    required this.beforeImageUrl,
    required this.afterImageUrl,
    required this.styleLabel,
    required this.projectId,
  });
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
