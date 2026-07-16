import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/message_model.dart';
import '../../data/models/project_model.dart';
import '../../data/services/supabase_service.dart';
import '../services/pending_generation_store.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final supabaseServiceProvider = Provider<SupabaseService>((_) => SupabaseService());

final sessionProvider =
    StateNotifierProvider<SessionNotifier, List<ProjectModel>>(
  (ref) => SessionNotifier(ref.read(supabaseServiceProvider)),
);

// ── Notifier ──────────────────────────────────────────────────────────────────

class SessionNotifier extends StateNotifier<List<ProjectModel>> {
  final SupabaseService _svc;

  // Test seams (null in production). Let widget/unit tests drive auth events,
  // the current uid, and the fetch WITHOUT Supabase. Production reads the live
  // auth stream + uid + SupabaseService.fetchSessions.
  final Stream<AuthState>? _authStreamOverride;
  final String? Function()? _uidOverride;
  final Future<List<Map<String, dynamic>>> Function()? _fetchOverride;

  StreamSubscription<AuthState>? _authSub;
  // Monotonic guard against a user-change RACE: rows fetched for one user must
  // NEVER be applied after a sign-out / new user superseded that load.
  int _seq = 0;

  SessionNotifier(
    this._svc, {
    Stream<AuthState>? authStream,
    String? Function()? currentUid,
    Future<List<Map<String, dynamic>>> Function()? fetchSessions,
  })  : _authStreamOverride = authStream,
        _uidOverride = currentUid,
        _fetchOverride = fetchSessions,
        super([]) {
    // Account-scoped data must NOT survive a user change — mirror the
    // onAuthStateChange self-invalidation of meStatusProvider / accessProvider.
    // Guarded: Supabase may be uninitialised (unit/widget tests) → no listener,
    // matching the pre-change behaviour instead of crashing at construction.
    Stream<AuthState>? stream = _authStreamOverride;
    if (stream == null) {
      try {
        stream = Supabase.instance.client.auth.onAuthStateChange;
      } catch (_) {
        stream = null;
      }
    }
    _authSub = stream?.listen(_onAuthEvent);
    _load();
  }

  String? _currentUid() {
    if (_uidOverride != null) return _uidOverride();
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null; // Supabase not initialised (unit/widget tests)
    }
  }

  void _onAuthEvent(AuthState data) {
    if (data.event == AuthChangeEvent.signedOut) {
      _seq++; // invalidate any in-flight _load so the old user's rows can't land
      if (mounted) state = const [];
      return;
    }
    // New session (the fresh anon after Sign out, or boot) → reload for its uid.
    if (data.event == AuthChangeEvent.signedIn ||
        data.event == AuthChangeEvent.initialSession ||
        data.event == AuthChangeEvent.userUpdated) {
      _load();
    }
  }

  // ── Load ───────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    final int mySeq = ++_seq;
    final String? uidAtStart = _currentUid();
    debugPrint('[DB] SessionNotifier._load() started');
    try {
      final rows = await (_fetchOverride ?? _svc.fetchSessions)();
      // Race protection: drop the result if a sign-out / newer load / user swap
      // happened while the fetch was in flight — never show the old user's rows.
      if (!mounted || mySeq != _seq || _currentUid() != uidAtStart) {
        debugPrint('[DB] SessionNotifier._load() — stale result discarded');
        return;
      }
      debugPrint('[DB] SessionNotifier._load() — got ${rows.length} sessions');
      state = rows.map(_rowToProject).toList();
    } catch (e, st) {
      debugPrint('[DB] SessionNotifier._load() ERROR: $e');
      debugPrint('[DB] SessionNotifier._load() STACK: $st');
    }
  }

  Future<void> reload() => _load();

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

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

  /// CHANTIER D — remove a session optimistically, then delete it server-side.
  void deleteSession(String id) {
    if (mounted) state = [for (final p in state) if (p.id != id) p];
    _svc.deleteSession(id); // fire-and-forget (RLS-scoped to the current user)
    // PR2b #5 — the session no longer exists → drop any durable pending so the
    // recovery sweep never re-launches an OpenAI generation for a deleted session
    // (orphan cost + a message that can't persist, FK gone). Fire-and-forget.
    _clearPendingFor(id);
  }

  Future<void> _clearPendingFor(String id) async {
    try {
      final store = await PendingGenerationStore.create();
      await store.clear(id);
    } catch (e) {
      debugPrint('[PendingStore] clear-on-delete failed for $id (non-fatal): $e');
    }
  }

  void updateLatestPreview(String id, String previewUrl) {
    _applyToState(id, (p) => p.copyWith(afterImageUrl: previewUrl, lastUpdatedAt: DateTime.now()));
    _svc.updateLatestPreview(id, previewUrl); // fire-and-forget
  }

  // Wave 5.3.2 — in-memory propagation of the initial upload URL.
  //
  // createSession() writes the session row BEFORE the source image is
  // uploaded (chat_screen needs the row id to namespace the upload path),
  // so the row is inserted with before_image_url == null. chat_screen
  // then uploads and PATCHES the row via _svc.updateBeforeImageUrl().
  // That DB write was correctly persisting, but the in-memory ProjectModel
  // inside this notifier kept its initial null beforeImageUrl — so
  // before_after_screen._sessionOriginalUrl() returned null and the
  // hold-to-original overlay fell back to the per-step generation source
  // (which for V2+ is the previous render, not the user's upload).
  //
  // This mutator closes that gap. It is in-memory propagation ONLY — the
  // DB write is already performed by chat_screen via SupabaseService.
  // Do NOT double-write here.
  void updateBeforeImageUrl(String id, String url) {
    _applyToState(id, (p) => p.copyWith(beforeImageUrl: url, lastUpdatedAt: DateTime.now()));
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
