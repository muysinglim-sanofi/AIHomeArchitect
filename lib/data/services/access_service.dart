/// Wave 5.18 — Developer Validation Mode admin-flag fetcher.
///
/// Single-method HTTP service that calls `GET /me/access` and returns the
/// authenticated user's admin status. The Dio interceptor injects the
/// active Supabase JWT (anonymous OR signed-in) so the backend can resolve
/// the user via the existing `get_current_user` dependency.
///
/// Fail-closed for UI gating : any network/parse/auth error returns false,
/// degrading the UI to free-tier behaviour. Backend bypass remains
/// authoritative if the admin actually attempts a privileged generation
/// (Wave 5.17d `check_restrictions` honours the `user_roles.admin` row
/// directly via `has_admin_role`, independent of this endpoint).
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

  /// Fetch the admin status for the current user.
  ///
  /// Returns false on any error (network timeout, 401 expired token, 503
  /// backend misconfigured, malformed response). The provider that wraps
  /// this service interprets the false as "no admin privileges" — the UI
  /// renders the standard free/premium gating which is the safe default.
  Future<bool> fetchIsAdmin() async {
    try {
      final response = await _dio.get('/me/access');
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data['is_admin'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('[AccessService] fetchIsAdmin failed: $e');
      return false;
    }
  }
}
