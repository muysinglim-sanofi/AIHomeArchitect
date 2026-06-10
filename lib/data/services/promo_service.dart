/// Sprint 1B — promo / influencer / admin codes (frontend client).
///
/// Thin client over the backend-authoritative endpoints. The frontend NEVER
/// decides access — it only sends the code / admin request and renders the
/// backend's result. Admin endpoints are gated server-side by is_admin_role;
/// hiding the admin UI is a convenience, not security.
///
///   POST  /promo/redeem
///   POST  /admin/promo-codes
///   GET   /admin/promo-codes
///   PATCH /admin/promo-codes/{id}
///
/// Mirrors the JWT-injection Dio used by StatusService.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of a redeem attempt. `errorCode` is the backend's machine code so the
/// UI can localise (invalid_code | expired_code | inactive_code |
/// already_redeemed | max_redemptions_reached | rate_limited | network).
class PromoRedeemResult {
  final bool ok;
  final String? errorCode;
  final String? type; // 'limited_generations' | 'unlimited'
  final bool unlimited;
  final int? generationLimit;
  final String? campaign;

  const PromoRedeemResult({
    required this.ok,
    this.errorCode,
    this.type,
    this.unlimited = false,
    this.generationLimit,
    this.campaign,
  });
}

class PromoCode {
  final String id;
  final String code;
  final String type;
  final int? generationLimit;
  final int? maxRedemptions;
  final int redeemedCount;
  final String? expiresAt;
  final bool active;
  final String? campaign;
  final String? note;

  const PromoCode({
    required this.id,
    required this.code,
    required this.type,
    required this.generationLimit,
    required this.maxRedemptions,
    required this.redeemedCount,
    required this.expiresAt,
    required this.active,
    required this.campaign,
    required this.note,
  });

  bool get isUnlimited => type == 'unlimited';

  /// Redemptions left (null = uncapped).
  int? get redemptionsRemaining =>
      maxRedemptions == null ? null : (maxRedemptions! - redeemedCount);

  factory PromoCode.fromJson(Map<String, dynamic> j) => PromoCode(
        id: (j['id'] ?? '').toString(),
        code: (j['code'] ?? '').toString(),
        type: (j['type'] ?? '').toString(),
        generationLimit: (j['generation_limit'] as num?)?.toInt(),
        maxRedemptions: (j['max_redemptions'] as num?)?.toInt(),
        redeemedCount: (j['redeemed_count'] as num?)?.toInt() ?? 0,
        expiresAt: j['expires_at'] as String?,
        active: j['active'] == true,
        campaign: j['campaign'] as String?,
        note: j['note'] as String?,
      );
}

class PromoService {
  late final Dio _dio;

  PromoService() {
    _dio = Dio(BaseOptions(
      baseUrl: dotenv.env['API_BASE_URL'] ?? 'http://localhost:8000',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      // Accept 4xx so we can read the backend error_code instead of throwing.
      validateStatus: (s) => s != null && s < 500,
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token =
            Supabase.instance.client.auth.currentSession?.accessToken;
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  String? _errorCodeOf(Response? r) {
    final data = r?.data;
    if (data is Map && data['detail'] is Map) {
      return (data['detail'] as Map)['error_code'] as String?;
    }
    return null;
  }

  /// POST /promo/redeem — never throws; returns a typed result.
  Future<PromoRedeemResult> redeem(String code) async {
    try {
      final r = await _dio.post('/promo/redeem', data: {'code': code});
      final data = r.data;
      if (r.statusCode == 200 && data is Map && data['ok'] == true) {
        return PromoRedeemResult(
          ok: true,
          type: data['type'] as String?,
          unlimited: data['unlimited'] == true,
          generationLimit: (data['generation_limit'] as num?)?.toInt(),
          campaign: data['campaign'] as String?,
        );
      }
      return PromoRedeemResult(
        ok: false,
        errorCode: _errorCodeOf(r) ?? 'invalid_code',
      );
    } catch (e) {
      debugPrint('[PromoService] redeem failed: $e');
      return const PromoRedeemResult(ok: false, errorCode: 'network');
    }
  }

  // ── Admin ──────────────────────────────────────────────────────────────────

  /// POST /admin/promo-codes. Returns the created code or null on failure.
  /// `errorOut` (if provided) receives the backend error_code.
  Future<PromoCode?> adminCreate({
    required String type, // 'limited_generations' | 'unlimited'
    String? code,
    int? generationLimit,
    int? maxRedemptions,
    String? expiresAt, // ISO-8601 or null
    String? campaign,
    String? note,
    void Function(String code)? errorOut,
  }) async {
    try {
      final body = <String, dynamic>{'type': type};
      final c = code?.trim();
      if (c != null && c.isNotEmpty) body['code'] = c;
      if (type == 'limited_generations') {
        body['generation_limit'] = generationLimit;
      }
      if (maxRedemptions != null) body['max_redemptions'] = maxRedemptions;
      if (expiresAt != null) body['expires_at'] = expiresAt;
      final camp = campaign?.trim();
      if (camp != null && camp.isNotEmpty) body['campaign'] = camp;
      final nt = note?.trim();
      if (nt != null && nt.isNotEmpty) body['note'] = nt;
      final r = await _dio.post('/admin/promo-codes', data: body);
      if (r.statusCode == 200 && r.data is Map) {
        return PromoCode.fromJson(Map<String, dynamic>.from(r.data as Map));
      }
      errorOut?.call(_errorCodeOf(r) ?? 'create_failed');
      return null;
    } catch (e) {
      debugPrint('[PromoService] adminCreate failed: $e');
      errorOut?.call('network');
      return null;
    }
  }

  /// GET /admin/promo-codes.
  Future<List<PromoCode>> adminList() async {
    try {
      final r = await _dio.get('/admin/promo-codes');
      final codes = (r.data is Map) ? (r.data as Map)['codes'] : null;
      if (codes is List) {
        return codes
            .whereType<Map>()
            .map((m) => PromoCode.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }
      return const [];
    } catch (e) {
      debugPrint('[PromoService] adminList failed: $e');
      return const [];
    }
  }

  /// PATCH /admin/promo-codes/{id} — enable/disable.
  Future<bool> adminSetActive(String id, bool active) async {
    try {
      final r = await _dio.patch('/admin/promo-codes/$id',
          data: {'active': active});
      return r.statusCode == 200;
    } catch (e) {
      debugPrint('[PromoService] adminSetActive failed: $e');
      return false;
    }
  }
}
