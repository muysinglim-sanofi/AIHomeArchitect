/// ON-mode (2026-07-17) — RESTAURATION du Guest parqué EN ATTENTE / EN ÉCHEC.
///
/// CORRECTION PRODUIT OBLIGATOIRE : si un Guest est parqué (2e slot Keychain) mais que
/// `recoverSession` échoue (panne réseau / refresh token momentanément indisponible), on NE
/// crée JAMAIS un nouvel anonyme. On tient un état PERSISTANT « restauration en attente » qui :
///   • conserve le blob Guest parqué + le guest_id attendu (GuestParking ne nettoie que sur succès) ;
///   • BLOQUE toute génération/wallet (gate ensureCanGenerateOrShowPaywall) tant que le bon Guest
///     n'est pas restauré → aucun nouveau trial, aucun historique vide, aucune identité fantôme ;
///   • se retente au boot et via un bouton Retry ;
///   • n'est levé QUE sur restauration réussie.
/// Un nouvel anonyme n'est autorisé que s'il est PROUVÉ qu'AUCUN Guest parqué n'existe (storage
/// réellement vide/supprimé) — décision prise dans le flux sign-out, pas ici.
///
/// Mirroir de [postSignoutPendingProvider]. Ne s'abonne PAS à l'auth au constructeur (sûr en
/// tests widget). Inerte en mode OFF (jamais posé — aucun flux compte).
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/guest_parking.dart';
import '../../data/services/revenuecat_service.dart';

/// Message affiché quand une génération est bloquée par une restauration Guest en attente.
const String kGuestRestorePendingMessage =
    'Restoring your guest profile. Please try again.';

class GuestRestorePendingNotifier extends StateNotifier<bool> {
  /// Production : `GuestRestorePendingNotifier()`. Seams de TEST (aucun appelant de prod) :
  /// [restore] (observe recoverSession sans Supabase, renvoie le uid restauré ou null) ;
  /// [rebindRc] (RevenueCat sans SDK). Aucun ne change le chemin de prod.
  GuestRestorePendingNotifier({
    Future<String?> Function()? restore,
    Future<void> Function(String uid)? rebindRc,
  })  : _restoreOverride = restore,
        _rebindOverride = rebindRc,
        super(false) {
    _init();
  }

  static const String _kKey = 'guest_restore_pending';

  final Future<String?> Function()? _restoreOverride;
  final Future<void> Function(String uid)? _rebindOverride;

  Future<String?> _restore() =>
      (_restoreOverride ?? GuestParking.restore)();

  Future<void> _rebind(String uid) =>
      (_rebindOverride ?? RevenuecatService.instance.logIn)(uid);

  Future<void> _init() async {
    bool cached = false;
    try {
      cached = (await SharedPreferences.getInstance()).getBool(_kKey) ?? false;
    } catch (_) {/* storage indisponible (tests) → pas en attente */}
    if (!mounted) return;
    if (cached) {
      state = true;
      await resolve(); // retry au boot
    }
  }

  /// Lève/abaisse le flag ET le persiste (best-effort : l'état mémoire fait foi pour la session).
  Future<void> setPending(bool value) async {
    if (mounted) state = value;
    try {
      await (await SharedPreferences.getInstance()).setBool(_kKey, value);
    } catch (_) {/* non-fatal */}
  }

  /// Retry (boot / bouton Retry). Tente `GuestParking.restore` : succès → re-bind RC sur le
  /// Guest restauré + lève le flag (les providers meStatus/session se rafraîchissent seuls via
  /// l'event auth de recoverSession) ; échec → le flag RESTE levé (génération toujours bloquée).
  /// Renvoie true si restauré. Ne throw jamais.
  Future<bool> resolve() async {
    if (!state) return true;
    String? uid;
    try {
      uid = await _restore();
    } catch (e) {
      debugPrint('[GuestRestorePending] restore failed: ${e.runtimeType}');
      uid = null;
    }
    if (uid != null && uid.isNotEmpty) {
      try {
        await _rebind(uid);
      } catch (_) {/* best-effort : le RC re-bind ne bloque pas la levée */}
      await setPending(false);
      return true;
    }
    return false;
  }
}

/// True tant qu'un Guest parqué reste à restaurer → le frontend bloque la génération.
/// Watché au root ([App]) pour être chargé + retenté dès le boot, avant tout tap Generate.
final guestRestorePendingProvider =
    StateNotifierProvider<GuestRestorePendingNotifier, bool>(
  (ref) => GuestRestorePendingNotifier(),
);
