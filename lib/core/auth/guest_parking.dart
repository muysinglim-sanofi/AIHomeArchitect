/// ON-mode (2026-07-17) — PARK / RESTORE de la session GUEST autour d'une session compte.
///
/// Modèle (docs/GUEST_ACCOUNT_IDENTITY_SPEC.md) : le Guest local est PARQUÉ (2e slot Keychain)
/// quand un compte devient actif, puis RESTAURÉ exactement au sign-out — jamais un nouvel anon.
/// La restauration réinjecte le blob JSON de session via `auth.recoverSession` (rafraîchit le
/// refresh token → même user_id). Fail-safe : toute erreur = restauration ratée (l'appelant
/// retombe alors sur un anon frais), jamais un crash.
///
/// Inerte en mode OFF (FeatureFlags.accountSystemEnabled=false) : jamais appelé (aucun flux
/// compte). Les seams (currentSession/park/readParked/recover/clearParked) rendent la LOGIQUE
/// d'orchestration testable sans Supabase ni Keychain ; en prod, les défauts branchent le réel.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'keychain_local_storage.dart';

class GuestParking {
  GuestParking._();

  /// Park la session COURANTE (le Guest) dans le 2e slot Keychain, AVANT de basculer vers
  /// un compte. Renvoie le guest `user_id` parqué (pour re-binder RevenueCat au restore),
  /// ou null si aucune session active. Ne supprime PAS la session courante ici (le flux
  /// d'auth s'en charge) — on en fait seulement une COPIE durable.
  static Future<String?> parkCurrent({
    ({String json, String uid})? Function()? sessionData,
    Future<void> Function(String json)? park,
  }) async {
    final d = (sessionData ?? _liveSessionData)();
    if (d == null) return null;
    await (park ?? KeychainLocalStorage.parkGuestSession)(d.json);
    return d.uid;
  }

  /// True s'il existe un Guest parqué valide (→ ne JAMAIS minter un nouvel anon au sign-out
  /// tant qu'un parqué existe).
  static Future<bool> hasParked({Future<bool> Function()? has}) =>
      (has ?? KeychainLocalStorage.hasParkedGuestSession)();

  /// Restaure le Guest parqué au sign-out compte : recoverSession(blob) → renvoie le user_id
  /// restauré (ou null si aucun parqué / échec). Nettoie le slot UNIQUEMENT sur succès (un
  /// échec garde le blob pour un retry). L'appelant re-binde RevenueCat sur le user_id rendu.
  static Future<String?> restore({
    Future<String?> Function()? readParked,
    Future<String?> Function(String json)? recover,
    Future<void> Function()? clearParked,
  }) async {
    final json = await (readParked ?? KeychainLocalStorage.readParkedGuestSession)();
    if (json == null || json.isEmpty) return null;
    final uid = await (recover ?? _liveRecover)(json);
    if (uid != null && uid.isNotEmpty) {
      await (clearParked ?? KeychainLocalStorage.clearParkedGuestSession)();
      return uid;
    }
    return null;
  }

  // ── Défauts branchés sur le réel (non exécutés en test grâce aux seams) ──────
  static ({String json, String uid})? _liveSessionData() {
    final s = Supabase.instance.client.auth.currentSession;
    if (s == null) return null;
    return (json: jsonEncode(s.toJson()), uid: s.user.id);
  }

  static Future<String?> _liveRecover(String json) async {
    try {
      final res = await Supabase.instance.client.auth.recoverSession(json);
      return res.user?.id;
    } catch (e) {
      debugPrint('[GuestParking] recoverSession failed: ${e.runtimeType}');
      return null;
    }
  }
}
