enum MessageType { text, imageResult, loading, system }

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
