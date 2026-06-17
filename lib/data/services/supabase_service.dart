import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseClient get _db => Supabase.instance.client;

  // ── Sessions ──────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchSessions() async {
    final userId = _db.auth.currentUser?.id;
    debugPrint('[DB] fetchSessions() — user_id: $userId');
    // Startup perf — cap the unbounded session load (was fetching ALL rows;
    // a heavy-testing account reached ~627, slowing every cold start). The 50
    // most-recent cover the home "Continue" strip; older sessions can be
    // paginated later if a full history view needs them.
    final res = await _db
        .from('sessions')
        .select()
        .order('updated_at', ascending: false)
        .limit(50);
    final rows = List<Map<String, dynamic>>.from(res as List);
    debugPrint('[DB] fetchSessions() — returned ${rows.length} rows');
    return rows;
  }

  Future<Map<String, dynamic>> createSession({
    required String title,
    required String roomType,
    required String atmosphere,
    String? beforeImageUrl,
  }) async {
    final userId = _db.auth.currentUser?.id;
    debugPrint('[DB] createSession() — user_id: $userId | title: "$title" | room: "$roomType" | atm: "$atmosphere"');
    if (userId == null) throw StateError('[DB] createSession() aborted: currentUser is null (not authenticated)');

    final payload = {
      'user_id': userId,
      'title': title,
      'room_type': roomType,
      'atmosphere': atmosphere,
      'before_image_url': beforeImageUrl,
    };
    debugPrint('[DB] createSession() insert payload: $payload');

    final res = await _db.from('sessions').insert(payload).select().single();
    final row = Map<String, dynamic>.from(res as Map);
    debugPrint('[DB] createSession() — created id: ${row['id']}');
    return row;
  }

  Future<void> updateSessionTitle(String sessionId, String title) async {
    debugPrint('[DB] updateSessionTitle() — id: $sessionId | title: "$title"');
    await _db.from('sessions').update({'title': title}).eq('id', sessionId);
    debugPrint('[DB] updateSessionTitle() — done');
  }

  /// CHANTIER D — delete a design session. RLS scopes the delete to the current
  /// user's own rows, so this can only ever remove the caller's sessions.
  Future<void> deleteSession(String sessionId) async {
    debugPrint('[DB] deleteSession() — id: $sessionId');
    await _db.from('sessions').delete().eq('id', sessionId);
    debugPrint('[DB] deleteSession() — done');
  }

  Future<void> updateLatestPreview(String sessionId, String previewUrl) async {
    debugPrint('[DB] updateLatestPreview() — id: $sessionId');
    await _db.from('sessions').update({'latest_preview': previewUrl}).eq('id', sessionId);
    debugPrint('[DB] updateLatestPreview() — done');
  }

  Future<void> updateBeforeImageUrl(String sessionId, String url) async {
    debugPrint('[DB] updateBeforeImageUrl() — id: $sessionId');
    await _db.from('sessions').update({'before_image_url': url}).eq('id', sessionId);
    debugPrint('[DB] updateBeforeImageUrl() — done');
  }

  // ── Messages ──────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchMessages(String sessionId) async {
    debugPrint('[DB] fetchMessages() — session_id: $sessionId');
    final res = await _db
        .from('messages')
        .select()
        .eq('session_id', sessionId)
        .order('created_at', ascending: true);
    final rows = List<Map<String, dynamic>>.from(res as List);
    debugPrint('[DB] fetchMessages() — returned ${rows.length} rows');
    return rows;
  }

  /// Insert a chat message row and return its Supabase `id`.
  ///
  /// Wave 5.21e — return type widened from `Future<void>` to
  /// `Future<String?>` so the caller can keep a handle on the row for
  /// targeted cleanup (e.g. removing a user message whose subsequent
  /// `/generate` call failed, preventing it from polluting the
  /// atmosphere-history walk). Callers that ignore the return value
  /// (fire-and-forget) keep working unchanged.
  ///
  /// Returns the new row's `id` on success, or `null` if the insert
  /// completed but Supabase did not return a row payload (best-effort
  /// — never raises a different error than before).
  Future<String?> insertMessage({
    required String sessionId,
    required String role,
    required String content,
    String messageType = 'text',
    String? beforeImageUrl,
    String? afterImageUrl,
    String? styleLabel,
  }) async {
    debugPrint('[DB] insertMessage() — session_id: $sessionId | role: $role | type: $messageType | content: "${content.substring(0, content.length.clamp(0, 40))}..."');
    final inserted = await _db.from('messages').insert({
      'session_id': sessionId,
      'role': role,
      'content': content,
      'message_type': messageType,
      'before_image_url': beforeImageUrl,
      'after_image_url': afterImageUrl,
      'style_label': styleLabel,
    }).select('id').maybeSingle();
    final rowId = inserted?['id'] as String?;
    debugPrint('[DB] insertMessage() — done (id=$rowId)');
    return rowId;
  }

  /// Wave 5.21e — delete a previously inserted message by row id.
  /// Used by the chat screen to clean up a user message whose
  /// `/generate` call failed, preventing that orphan message from
  /// polluting `_previous_atmosphere_id_from_history` on subsequent
  /// generations. Best-effort: errors are swallowed (the local
  /// `_messages` removal already happened).
  Future<void> deleteMessage(String rowId) async {
    debugPrint('[DB] deleteMessage() — row_id: $rowId');
    try {
      await _db.from('messages').delete().eq('id', rowId);
      debugPrint('[DB] deleteMessage() — done');
    } catch (e) {
      debugPrint('[DB] deleteMessage() — failed (best-effort): $e');
    }
  }

  // ── Storage ───────────────────────────────────────────────────────────────

  Future<String> uploadSourceImage({
    required String sessionId,
    required String filename,
    required Uint8List bytes,
  }) async {
    final userId = _db.auth.currentUser!.id;
    final path = '$userId/$sessionId/$filename';
    debugPrint('[DB] uploadSourceImage() — path: $path | bytes: ${bytes.length}');
    await _db.storage.from('uploads').uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
    );
    final signedUrl = await _db.storage.from('uploads').createSignedUrl(path, 31536000);
    debugPrint('[DB] uploadSourceImage() — signed URL: $signedUrl');
    return signedUrl;
  }
}
