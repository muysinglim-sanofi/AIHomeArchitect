/// Sprint 1 — premium + quota status, and purchase reconciliation.
///
/// Two READ/RECONCILE calls against the (authoritative) backend:
///   • GET  /me/status      → premium state + remaining free generations (UI)
///   • POST /purchases/sync  → fallback when the RevenueCat webhook is delayed,
///                              reconciling user_roles from RevenueCat REST.
///
/// Both fail GRACEFULLY (null / false) so a status error never breaks the app.
/// The backend stays the single source of truth; the client only displays
/// what the backend reports and asks it to reconcile — it never grants itself
/// anything. Mirrors the JWT-injection Dio used by AccessService.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MeStatus {
  final bool isPremium;
  final bool isAdmin;
  final String role; // 'free' | 'premium' | 'admin'
  final int quotaUsed;
  final int quotaLimit;

  /// Null = unlimited (premium / admin).
  final int? remainingFreeGenerations;

  // ── Sprint 1B — promo (backend-authoritative; display only) ──
  final int promoGenerationsRemaining;
  final bool promoUnlimitedActive;
  final String? activePromoCampaign;

  /// admin | premium | promo_unlimited | promo_limited | free | blocked
  final String effectiveAccessState;
  final bool canGenerate;

  const MeStatus({
    required this.isPremium,
    required this.isAdmin,
    required this.role,
    required this.quotaUsed,
    required this.quotaLimit,
    required this.remainingFreeGenerations,
    this.promoGenerationsRemaining = 0,
    this.promoUnlimitedActive = false,
    this.activePromoCampaign,
    this.effectiveAccessState = 'free',
    this.canGenerate = true,
  });

  int get remaining =>
      remainingFreeGenerations ??
      (quotaLimit - quotaUsed).clamp(0, quotaLimit);

  /// True when a promo grant is currently active (and the user is not premium).
  bool get hasActivePromo =>
      !isPremium && (promoUnlimitedActive || promoGenerationsRemaining > 0);

  factory MeStatus.fromJson(Map<String, dynamic> j) => MeStatus(
        isPremium: j['is_premium'] == true,
        isAdmin: j['is_admin'] == true,
        role: (j['role'] as String?) ?? 'free',
        quotaUsed: (j['quota_used'] as num?)?.toInt() ?? 0,
        quotaLimit: (j['quota_limit'] as num?)?.toInt() ?? 0,
        remainingFreeGenerations:
            (j['remaining_free_generations'] as num?)?.toInt(),
        promoGenerationsRemaining:
            (j['promo_generations_remaining'] as num?)?.toInt() ?? 0,
        promoUnlimitedActive: j['promo_unlimited_active'] == true,
        activePromoCampaign: j['active_promo_campaign'] as String?,
        effectiveAccessState:
            (j['effective_access_state'] as String?) ?? 'free',
        canGenerate:
            j['can_generate'] == null ? true : j['can_generate'] == true,
      );
}

class StatusService {
  late final Dio _dio;

  StatusService() {
    _dio = Dio(BaseOptions(
      baseUrl: dotenv.env['API_BASE_URL'] ?? 'http://localhost:8000',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
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

  /// GET /me/status — returns null on ANY error (caller keeps its prior state).
  Future<MeStatus?> fetchStatus() async {
    try {
      final r = await _dio.get('/me/status');
      final data = r.data;
      if (data is Map<String, dynamic>) return MeStatus.fromJson(data);
      return null;
    } catch (e) {
      debugPrint('[StatusService] fetchStatus failed: $e');
      return null;
    }
  }

  /// POST /purchases/sync — reconcile backend entitlement from RevenueCat when
  /// the webhook is delayed/missed. Returns true iff the backend now sees
  /// premium. Never throws (safe to fire-and-forget).
  Future<bool> syncPurchases() async {
    try {
      final r = await _dio.post('/purchases/sync');
      final data = r.data;
      if (data is Map<String, dynamic>) return data['is_premium'] == true;
      return false;
    } catch (e) {
      debugPrint('[StatusService] syncPurchases failed: $e');
      return false;
    }
  }
}
