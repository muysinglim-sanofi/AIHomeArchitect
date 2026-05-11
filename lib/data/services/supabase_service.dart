import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseClient get _db => Supabase.instance.client;

  // ── Sessions ──────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchSessions() async {
    final res = await _db
        .from('sessions')
        .select()
        .order('updated_at', ascending: false);
    return List<Map<String, dynamic>>.from(res as List);
  }

  Future<Map<String, dynamic>> createSession({
    required String title,
    required String roomType,
    required String atmosphere,
    String? beforeImageUrl,
  }) async {
    final userId = _db.auth.currentUser!.id;
    final res = await _db
        .from('sessions')
        .insert({
          'user_id': userId,
          'title': title,
          'room_type': roomType,
          'atmosphere': atmosphere,
          'before_image_url': beforeImageUrl,
        })
        .select()
        .single();
    return Map<String, dynamic>.from(res as Map);
  }

  Future<void> updateSessionTitle(String sessionId, String title) async {
    await _db
        .from('sessions')
        .update({'title': title})
        .eq('id', sessionId);
  }

  Future<void> updateLatestPreview(String sessionId, String previewUrl) async {
    await _db
        .from('sessions')
        .update({'latest_preview': previewUrl})
        .eq('id', sessionId);
  }

  // ── Messages ──────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchMessages(String sessionId) async {
    final res = await _db
        .from('messages')
        .select()
        .eq('session_id', sessionId)
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(res as List);
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
    await _db.from('messages').insert({
      'session_id': sessionId,
      'role': role,
      'content': content,
      'message_type': messageType,
      'before_image_url': beforeImageUrl,
      'after_image_url': afterImageUrl,
      'style_label': styleLabel,
    });
  }

  // ── Storage ───────────────────────────────────────────────────────────────

  Future<String> uploadSourceImage({
    required String sessionId,
    required String filename,
    required Uint8List bytes,
  }) async {
    final userId = _db.auth.currentUser!.id;
    final path = '$userId/$sessionId/$filename';
    await _db.storage.from('uploads').uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
    );
    // uploads bucket is private — return a signed URL valid for 1 hour
    final signedUrl = await _db.storage
        .from('uploads')
        .createSignedUrl(path, 3600);
    return signedUrl;
  }
}
