/// P0 (2026-07-10) — feature-gating = VÉRITÉ BACKEND (/me/status), plus l'entitlement
/// RevenueCat SDK.
///
/// Avant : premiumProvider = RevenuecatService.instance.isPremium (RC SDK). Un abo
/// Apple actif signalé par le SDK déverrouillait rooms/atmospheres MÊME sans accès
/// mesuré côté backend → un free avec abo sandbox actif voyait tout déverrouillé.
///
/// Maintenant : les features suivent la MÊME autorité que la génération. Unlocked
/// ⟺ access_source ∈ {admin, pass, promo} (accès réel/mesuré). 'restore_required'
/// (rôle premium sans pass mesuré) et 'free' → LOCKED (comme la génération : pas de
/// pass = pas d'accès premium ; l'user doit restaurer/synchroniser son achat).
///
/// Fail-closed : tant que /me/status n'est pas chargé → false (verrouillé). Le
/// meStatusProvider re-seed son dernier snapshot au cold start → pas de flicker
/// pour un vrai abonné (access_source='pass' immédiat).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'me_status_provider.dart';

/// True ⟺ l'user a un accès premium RÉEL côté backend (pass mesuré, promo, admin).
final premiumProvider = Provider<bool>((ref) {
  final status = ref.watch(meStatusProvider);
  if (status == null) return false; // pas encore chargé → verrouillé
  final src = status.accessSource;
  return src == 'admin' || src == 'pass' || src == 'promo';
});
