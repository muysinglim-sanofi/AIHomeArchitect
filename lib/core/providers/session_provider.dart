import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/message_model.dart';
import '../../data/models/project_model.dart';
import '../../data/services/supabase_service.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final supabaseServiceProvider = Provider<SupabaseService>((_) => SupabaseService());

final sessionProvider =
    StateNotifierProvider<SessionNotifier, List<ProjectModel>>(
  (ref) => SessionNotifier(ref.read(supabaseServiceProvider)),
);

// ── Notifier ──────────────────────────────────────────────────────────────────

class SessionNotifier extends StateNotifier<List<ProjectModel>> {
  final SupabaseService _svc;

  SessionNotifier(this._svc) : super([]) {
    _load();
  }

  // ── Load ───────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    debugPrint('[DB] SessionNotifier._load() started');
    try {
      final rows = await _svc.fetchSessions();
      debugPrint('[DB] SessionNotifier._load() — got ${rows.length} sessions');
      if (mounted) state = rows.map(_rowToProject).toList();
    } catch (e, st) {
      debugPrint('[DB] SessionNotifier._load() ERROR: $e');
      debugPrint('[DB] SessionNotifier._load() STACK: $st');
    }
  }

  Future<void> reload() => _load();

  // ── Session creation ──────────────────────────────────────────────────────

  /// Creates a real session in Supabase and prepends it to local state.
  /// Returns the new ProjectModel so chat_screen can hold a reference to its id.
  Future<ProjectModel> createSession({
    required String title,
    required String roomType,
    required String atmosphere,
    String? beforeImageUrl,
  }) async {
    final row = await _svc.createSession(
      title: title,
      roomType: roomType,
      atmosphere: atmosphere,
      beforeImageUrl: beforeImageUrl,
    );
    final project = _rowToProject(row);
    if (mounted) state = [project, ...state];
    return project;
  }

  // ── Mutations — same public signatures as before ──────────────────────────

  /// Existing callers (chat_screen title edit) unchanged.
  void updateTitle(String id, String title) {
    _applyToState(id, (p) => p.copyWith(title: title, lastUpdatedAt: DateTime.now()));
    _svc.updateSessionTitle(id, title); // fire-and-forget
  }

  void updateLatestPreview(String id, String previewUrl) {
    _applyToState(id, (p) => p.copyWith(afterImageUrl: previewUrl, lastUpdatedAt: DateTime.now()));
    _svc.updateLatestPreview(id, previewUrl); // fire-and-forget
  }

  void addMessageToSession(String sessionId, MessageModel message) {
    _applyToState(sessionId, (p) => p.copyWith(
      messages: [...p.messages, message],
      lastUpdatedAt: DateTime.now(),
      iterationCount: message.type == MessageType.imageResult
          ? p.iterationCount + 1
          : p.iterationCount,
    ));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _applyToState(String id, ProjectModel Function(ProjectModel) fn) {
    if (!mounted) return;
    state = [for (final p in state) if (p.id == id) fn(p) else p];
  }

  ProjectModel _rowToProject(Map<String, dynamic> row) {
    return ProjectModel(
      id: row['id'] as String,
      title: row['title'] as String,
      roomType: (row['room_type'] as String?) ?? '',
      style: (row['atmosphere'] as String?) ?? '',
      beforeImageUrl: row['before_image_url'] as String?,
      afterImageUrl: row['latest_preview'] as String?,
      status: (row['status'] as String?) == 'completed'
          ? ProjectStatus.completed
          : ProjectStatus.inProgress,
      createdAt: DateTime.parse(row['created_at'] as String),
      lastUpdatedAt: DateTime.parse(row['updated_at'] as String),
      messages: const [],   // loaded on-demand inside ChatScreen
      iterationCount: 0,    // derived from messages count when needed
    );
  }
}
