/// Wave 5.18 — Developer Validation Mode admin-flag fetcher.
///
/// Single-method HTTP service that calls `GET /me/access` and returns the
/// authenticated user's admin status. The Dio interceptor injects the
/// active Supabase JWT (anonymous OR signed-in) so the backend can resolve
/// the user via the existing `get_current_user` dependency.
///
/// Returns a TRI-STATE (true/false/null) — see [fetchIsAdmin]. Errors map to
/// `null` ("unknown"), NOT false, so the provider keeps the last known admin
/// state across transient failures instead of revoking access in the UI.
/// Backend bypass remains authoritative if the admin actually attempts a
/// privileged generation (Wave 5.17d `check_restrictions` honours the
/// `user_roles.admin` row directly via `has_admin_role`, independent of this
/// endpoint).
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccessService {
  late final Dio _dio;

  AccessService() {
    _dio = Dio(BaseOptions(
      baseUrl: dotenv.env['API_BASE_URL'] ?? 'http://localhost:8000',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
    ));

    // Mirror the JWT-injection interceptor used by GenerationService — the
    // token is read at request-time so a freshly-refreshed session carries
    // the new JWT, not a stale one.
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = Supabase
            .instance.client.auth.currentSession?.accessToken;
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  /// Fetch the admin status for the current user — TRI-STATE.
  ///
  ///   true  → backend confirmed the user IS admin
  ///   false → backend confirmed the user is NOT admin (explicit response)
  ///   null  → status UNKNOWN (no valid session yet, network error, 401 during
  ///           token rotation, 5xx, malformed body)
  ///
  /// The provider MUST treat `null` as "keep the last known state" and never as
  /// "not admin". Failing closed to false here was the root cause of admin
  /// access vanishing on a transient resume/token-refresh error (a fresh cold
  /// start re-fetched successfully and restored it).
  Future<bool?> fetchIsAdmin() async {
    // Skip the call entirely while there is no usable token (e.g. the brief
    // session-rotation window on app resume). Querying with no/expired token
    // would 401 and previously flipped admin off.
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) return null;
    try {
      final response = await _dio.get('/me/access');
      final data = response.data;
      if (data is Map<String, dynamic> && data.containsKey('is_admin')) {
        return data['is_admin'] == true;
      }
      return null; // malformed → unknown, do NOT fail closed
    } catch (e) {
      debugPrint('[AccessService] fetchIsAdmin unknown (keeping last state): $e');
      return null;
    }
  }
}
