/// BUG 2 (anti-abus Sign out) — flag LOCAL PERSISTANT « marqueur post-sign-out non confirmé ».
///
/// Après un Sign out, un NOUVEL utilisateur anonyme est créé côté GoTrue (le backend n'est PAS
/// dans ce chemin : il ne peut pas distinguer cet anonyme d'un tout premier boot). Tant que son
/// marqueur `trial-consumed` (POST /identity/post-signout-guest, clé idempotente `trial:<uid>`)
/// n'est PAS confirmé, le frontend NE DOIT PAS le laisser générer — sinon un Free 3 serait
/// « offert » à chaque Sign out.
///
/// Ce flag (réutilise SharedPreferences — AUCUN nouveau service ni stockage) :
///   • est LEVÉ (true) par le flux Sign out AVANT le POST, et ABAISSÉ (false) uniquement sur un
///     succès confirmé ;
///   • gate TOUS les points d'entrée Generate via le choke-point unique
///     `ensureCanGenerateOrShowPaywall` (aucun backend Generate touché) ;
///   • est RETENTÉ ([resolve]) au boot et via le bouton Retry : anonyme + pending → re-POST du
///     marqueur ; utilisateur NON anonyme (lié / connecté) → flag périmé → nettoyé.
///
/// Contrairement à `accessProvider`, il NE S'ABONNE PAS à l'auth au constructeur : le flag est
/// piloté EXPLICITEMENT (sign-out / boot / Retry). Cela garde le constructeur SÛR même quand
/// Supabase n'est pas initialisé (tests widget du gate qui instancient le provider par défaut).
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/services/identity_service.dart';

/// Message UNIQUE affiché quand une génération est bloquée par un marqueur non confirmé.
/// Réutilisé par le gate (dialog) ET le bouton Generate primaire (bandeau inline).
const String kGuestSetupPendingMessage = 'Finishing guest setup. Please try again.';

class PostSignoutPendingNotifier extends StateNotifier<bool> {
  /// Production : `PostSignoutPendingNotifier()` — lit SharedPreferences au boot et,
  /// si pending, retente le marqueur via un `IdentityService` réel + la session Supabase.
  ///
  /// Les deux paramètres sont un SEAM DE TEST (aucun appelant de prod ne les passe) :
  /// [postMarker] observe le re-POST sans réseau (renvoie 2xx=true / échec=false) ;
  /// [isAnonymous] fournit l'état de session sans Supabase. Aucun ne change le chemin de prod.
  PostSignoutPendingNotifier({
    Future<bool> Function()? postMarker,
    bool? Function()? isAnonymous,
  })  : _postMarkerOverride = postMarker,
        _isAnonymousOverride = isAnonymous,
        super(false) {
    _init();
  }

  // Réutilise SharedPreferences (déjà utilisé par meStatus/access) — pas de nouveau stockage.
  static const String _kKey = 'post_signout_marker_pending';

  final Future<bool> Function()? _postMarkerOverride;
  final bool? Function()? _isAnonymousOverride;
  // `IdentityService` créé PARESSEUSEMENT et seulement en production, UNIQUEMENT au premier retry
  // réel (anon + pending). Jamais instancié en test (le seam est fourni) ni quand rien n'attend.
  IdentityService? _identityCached;

  /// Re-poste le marqueur : renvoie true sur 2xx, false sinon. Le vrai POST côté backend est
  /// idempotent (clé `trial:<uid>`), donc un retry est toujours sûr.
  Future<bool> _postMarker() {
    final override = _postMarkerOverride;
    if (override != null) return override();
    return (_identityCached ??= IdentityService()).postSignoutGuest();
  }

  /// État de session courant : true = invité anonyme, false = compte permanent, null = indéterminé
  /// (pas de session / Supabase non prêt). Exception-safe (jamais de throw au boot / en test).
  bool? _currentIsAnonymous() {
    if (_isAnonymousOverride != null) return _isAnonymousOverride();
    try {
      return Supabase.instance.client.auth.currentUser?.isAnonymous;
    } catch (_) {
      return null;
    }
  }

  Future<void> _init() async {
    bool cached = false;
    try {
      cached = (await SharedPreferences.getInstance()).getBool(_kKey) ?? false;
    } catch (_) {
      // SharedPreferences indisponible (tests widget) → traité comme « pas en attente ».
    }
    if (!mounted) return;
    if (cached) {
      state = true;
      await resolve(); // retry au boot (anon+pending → re-POST ; non-anon → périmé → nettoyé)
    }
  }

  /// Lève / abaisse le flag ET le persiste. La persistance est best-effort (une panne locale ne
  /// casse jamais l'appelant) ; l'état mémoire fait toujours foi pour la session courante.
  Future<void> setPending(bool value) async {
    if (mounted) state = value;
    try {
      await (await SharedPreferences.getInstance()).setBool(_kKey, value);
    } catch (_) {
      // non-fatal — le gate en mémoire reste correct pour cette session.
    }
  }

  /// Retry (boot / bouton Retry). Renvoie true si le pending est LEVÉ (marqueur confirmé OU flag
  /// périmé car l'utilisateur n'est plus un invité), false s'il RESTE en attente. Idempotent et
  /// sûr : ne throw jamais ; côté backend le marqueur est idempotent (clé `trial:<uid>`).
  Future<bool> resolve() async {
    if (!state) return true; // rien en attente
    final anon = _currentIsAnonymous();
    if (anon == false) {
      // Plus un invité (lié / connecté) → le marqueur ne s'applique plus → flag périmé, nettoyé.
      await setPending(false);
      return true;
    }
    if (anon == null) {
      // Session indéterminée (pas encore restaurée) → garder le flag, retry plus tard.
      return false;
    }
    // anon == true → re-poser le marqueur.
    bool ok = false;
    try {
      ok = await _postMarker();
    } catch (e) {
      debugPrint('[PostSignoutPending] resolve failed: ${e.runtimeType}');
      ok = false;
    }
    if (ok) {
      await setPending(false);
      return true;
    }
    return false;
  }
}

/// True tant qu'un marqueur post-sign-out reste à confirmer → le frontend gate Generate.
/// Watché au root ([App]) pour être chargé (et retenté) DÈS le boot, avant tout tap Generate.
final postSignoutPendingProvider =
    StateNotifierProvider<PostSignoutPendingNotifier, bool>(
  (ref) => PostSignoutPendingNotifier(),
);
