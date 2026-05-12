import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseClient get _db => Supabase.instance.client;

  // ── Sessions ──────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchSessions() async {
    final userId = _db.auth.currentUser?.id;
    debugPrint('[DB] fetchSessions() — user_id: $userId');
    final res = await _db
        .from('sessions')
        .select()
        .order('updated_at', ascending: false);
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

  Future<void> insertMessage({
    required String sessionId,
    required String role,
    required String content,
    String messageType = 'text',
    String? beforeImageUrl,
    String? afterImageUrl,
    String? styleLabel,
  }) async {
    debugPrint('[DB] insertMessage() — session_id: $sessionId | role: $role | type: $messageType | content: "${content.substring(0, content.length.clamp(0, 40))}..."');
    await _db.from('messages').insert({
      'session_id': sessionId,
      'role': role,
      'content': content,
      'message_type': messageType,
      'before_image_url': beforeImageUrl,
      'after_image_url': afterImageUrl,
      'style_label': styleLabel,
    });
    debugPrint('[DB] insertMessage() — done');
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
