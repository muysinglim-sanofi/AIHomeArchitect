import 'message_model.dart';

enum ProjectStatus { inProgress, completed, failed }

class ProjectModel {
  final String id;
  final String title;
  final String roomType;
  final String style;
  final String? beforeImageUrl;
  final String? afterImageUrl;
  final ProjectStatus status;
  final DateTime createdAt;
  final DateTime lastUpdatedAt;
  final List<MessageModel> messages;
  final int iterationCount;

  const ProjectModel({
    required this.id,
    required this.title,
    required this.roomType,
    required this.style,
    this.beforeImageUrl,
    this.afterImageUrl,
    required this.status,
    required this.createdAt,
    required this.lastUpdatedAt,
    required this.messages,
    required this.iterationCount,
  });

  ProjectModel copyWith({
    String? id,
    String? title,
    String? roomType,
    String? style,
    String? beforeImageUrl,
    String? afterImageUrl,
    ProjectStatus? status,
    DateTime? createdAt,
    DateTime? lastUpdatedAt,
    List<MessageModel>? messages,
    int? iterationCount,
  }) =>
      ProjectModel(
        id: id ?? this.id,
        title: title ?? this.title,
        roomType: roomType ?? this.roomType,
        style: style ?? this.style,
        beforeImageUrl: beforeImageUrl ?? this.beforeImageUrl,
        afterImageUrl: afterImageUrl ?? this.afterImageUrl,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
        lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
        messages: messages ?? this.messages,
        iterationCount: iterationCount ?? this.iterationCount,
      );
}
