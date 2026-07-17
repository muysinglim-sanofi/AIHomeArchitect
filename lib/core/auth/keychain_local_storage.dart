/// BUG 4 (2026-07-11) — Device-key, Approche 2.
///
/// Persiste la session Supabase (utilisateur ANONYME) dans le KEYCHAIN iOS via
/// `flutter_secure_storage`. Le Keychain SURVIT à la désinstallation/réinstallation de
/// l'app — contrairement à `SharedPreferences` (NSUserDefaults), qui est WIPÉ au reinstall.
///
/// Conséquence directe (répare BUG 4) : le `user_id` Supabase reste STABLE au reinstall →
///   • `free_remaining = 3 − consommé` conservé (fin du « reinstall redonne 3 gratuits ») ;
///   • le pass mesuré reste rattaché au MÊME user (répare la racine de BUG 3 : abo splitté
///     entre plusieurs anon au fil des reinstalls) ;
///   • l'`appUserID` RevenueCat (= `user.id`) reste stable → l'achat suit l'utilisateur.
///
/// Robustesse par plateforme :
///   • iOS : FORT. `first_unlock_this_device` = accessible après le 1er déverrouillage,
///     HORS backup/restore iCloud, tied-to-device ; `synchronizable:false` (décision D3 :
///     pas de sync iCloud Keychain). Les items Keychain persistent après suppression de l'app.
///   • Android : BEST-EFFORT (décision D2). `encryptedSharedPreferences` ; le Keystore ne
///     survit pas toujours au reinstall → dégradation propre (nouvel anon = comportement
///     actuel), jamais un crash.
///
/// Contrat FAIL-SAFE ABSOLU : toute erreur de secure storage est avalée et retombe sur
/// « pas de session » / no-op. Le boot ne casse JAMAIS ; au pire on retrouve le comportement
/// d'avant (un nouvel utilisateur anonyme).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class KeychainLocalStorage extends LocalStorage {
  KeychainLocalStorage();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false, // D3 — jamais de sync iCloud Keychain
    ),
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Clé unique de la session Supabase dans le Keychain (indépendante de l'URL — la
  /// migration lit l'ancienne clé SharedPreferences et écrit ici).
  static const String kSessionKey = 'sb_supabase_session';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async {
    try {
      final v = await _storage.read(key: kSessionKey);
      return v != null && v.isNotEmpty;
    } catch (e) {
      debugPrint('[Keychain] hasAccessToken failed (non-fatal): $e');
      return false;
    }
  }

  @override
  Future<String?> accessToken() async {
    try {
      return await _storage.read(key: kSessionKey);
    } catch (e) {
      debugPrint('[Keychain] accessToken read failed (non-fatal): $e');
      return null;
    }
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    try {
      await _storage.write(key: kSessionKey, value: persistSessionString);
    } catch (e) {
      debugPrint('[Keychain] persistSession failed (non-fatal): $e');
    }
  }

  @override
  Future<void> removePersistedSession() async {
    try {
      await _storage.delete(key: kSessionKey);
    } catch (e) {
      debugPrint('[Keychain] removePersistedSession failed (non-fatal): $e');
    }
  }

  // ── ON-mode (2026-07-17) — PARKING de la session GUEST ──────────────────────
  // 2e slot Keychain, DISTINCT de kSessionKey (que Supabase écrase à chaque event
  // auth). Même config secure (first_unlock_this_device, no iCloud). Stocke le blob
  // JSON complet de la session guest (access+refresh+user+expiry) pendant qu'un compte
  // est actif → restauré via recoverSession au sign-out. Fail-safe : toute erreur = no-op.
  // Inerte en mode OFF (jamais écrit, aucun sign-in/out compte).
  static const String kParkedGuestKey = 'sb_parked_guest_session';

  static Future<void> parkGuestSession(String sessionJson) async {
    try {
      await _storage.write(key: kParkedGuestKey, value: sessionJson);
    } catch (e) {
      debugPrint('[Keychain] parkGuestSession failed (non-fatal): $e');
    }
  }

  static Future<String?> readParkedGuestSession() async {
    try {
      return await _storage.read(key: kParkedGuestKey);
    } catch (e) {
      debugPrint('[Keychain] readParkedGuestSession failed (non-fatal): $e');
      return null;
    }
  }

  static Future<bool> hasParkedGuestSession() async {
    try {
      final v = await _storage.read(key: kParkedGuestKey);
      return v != null && v.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<void> clearParkedGuestSession() async {
    try {
      await _storage.delete(key: kParkedGuestKey);
    } catch (e) {
      debugPrint('[Keychain] clearParkedGuestSession failed (non-fatal): $e');
    }
  }

  /// La clé SharedPreferences EXACTE que `Supabase.initialize` utilisait par défaut
  /// (SharedPreferencesLocalStorage) : `sb-<sous-domaine>-auth-token`. PURE/testable —
  /// le succès de toute la migration dépend de la reproduire fidèlement.
  static String legacySessionKeyForUrl(String supabaseUrl) {
    final host = Uri.parse(supabaseUrl).host; // ex: abcdefgh.supabase.co
    if (host.isEmpty) return '';
    return 'sb-${host.split('.').first}-auth-token';
  }

  /// CONDITION 1 (D5) — MIGRATION legacy `SharedPreferences` → Keychain, au 1er lancement
  /// de ce build. Si le Keychain est vide MAIS l'ancien LocalStorage SharedPreferences
  /// contient une session, on la COPIE dans le Keychain AVANT que `Supabase.initialize` ne
  /// restaure la session. Sans ça, un utilisateur EXISTANT qui met à jour perdrait son
  /// `user_id` (un nouvel anon serait créé) au premier boot post-update.
  ///
  /// Utilisateurs ayant DÉJÀ réinstallé avant ce build (SharedPreferences déjà wipé) : rien
  /// à migrer → un nouvel anon (le « 1 reset unique » accepté, D5). Ensuite stable à vie.
  ///
  /// À APPELER dans `main()` AVANT `Supabase.initialize`. Fail-safe : toute erreur = no-op.
  static Future<void> migrateLegacySessionIfNeeded(String supabaseUrl) async {
    try {
      final existing = await _storage.read(key: kSessionKey);
      if (existing != null && existing.isNotEmpty) {
        debugPrint('[Keychain] session déjà en Keychain — pas de migration');
        return;
      }
      final legacyKey = legacySessionKeyForUrl(supabaseUrl);
      if (legacyKey.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(legacyKey);
      if (legacy != null && legacy.isNotEmpty) {
        await _storage.write(key: kSessionKey, value: legacy);
        debugPrint('[Keychain] MIGRÉ session legacy SharedPreferences → Keychain '
            '(key=$legacyKey)');
      } else {
        debugPrint('[Keychain] aucune session legacy à migrer '
            '(install neuf ou SharedPreferences déjà wipé) key=$legacyKey');
      }
    } catch (e) {
      debugPrint('[Keychain] migration legacy échouée (non-fatal): $e');
    }
  }
}
