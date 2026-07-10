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

  // ── RC-PR2b — wallet/pass snapshot (AFFICHAGE seul ; enforcement = RC-PR3) ──
  /// Crédits du pass actif (weekly/annual). 0 si pas de pass / bucket free vide.
  final int availableCredits;
  final String? activePassId;

  /// Expiration du pass actif (ISO-8601), ou null.
  final String? passExpiresAt;
  final bool hasActivePass;

  /// Source de vérité de la CAPACITÉ de génération (même autorité que le backend
  /// reserve_decision) : 'admin' | 'pass' | 'promo' | 'restore_required' | 'free'.
  /// 'restore_required' = rôle premium (abo actif RC) SANS pass mesuré → l'user doit
  /// restaurer/synchroniser son achat ; JAMAIS "Premium active".
  final String accessSource;

  /// Raison du gate quand la génération est bloquée : '' | bypass | pass_exhausted
  /// | no_active_pass | insufficient_credits.
  final String gateReason;

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
    this.availableCredits = 0,
    this.activePassId,
    this.passExpiresAt,
    this.hasActivePass = false,
    this.accessSource = 'free',
    this.gateReason = '',
  });

  /// True quand l'app a un rôle premium (abo actif) mais AUCUN pass mesuré côté
  /// backend → il faut restaurer/synchroniser l'achat pour obtenir le pass.
  bool get needsRestore => accessSource == 'restore_required';

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
        availableCredits: (j['available_credits'] as num?)?.toInt() ?? 0,
        activePassId: j['active_pass_id'] as String?,
        passExpiresAt: j['pass_expires_at'] as String?,
        hasActivePass: j['has_active_pass'] == true,
        accessSource: (j['access_source'] as String?) ?? 'free',
        gateReason: (j['gate_reason'] as String?) ?? '',
      );

  /// Exact mirror of [fromJson] — lets meStatusProvider cache the last
  /// confirmed entitled snapshot and re-seed it on cold start (fromJson(toJson)
  /// round-trips). Keys match the backend /me/status payload.
  Map<String, dynamic> toJson() => {
        'is_premium': isPremium,
        'is_admin': isAdmin,
        'role': role,
        'quota_used': quotaUsed,
        'quota_limit': quotaLimit,
        'remaining_free_generations': remainingFreeGenerations,
        'promo_generations_remaining': promoGenerationsRemaining,
        'promo_unlimited_active': promoUnlimitedActive,
        'active_promo_campaign': activePromoCampaign,
        'effective_access_state': effectiveAccessState,
        'can_generate': canGenerate,
        'available_credits': availableCredits,
        'active_pass_id': activePassId,
        'pass_expires_at': passExpiresAt,
        'has_active_pass': hasActivePass,
        'access_source': accessSource,
        'gate_reason': gateReason,
      };
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
