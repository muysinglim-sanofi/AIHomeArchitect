/// ISSUE 14 (2026-08-25) — CONVERGENCE D'IDENTITÉ AVANT TOUTE LIAISON REVENUECAT.
///
/// L'INCIDENT RÉEL. Le 2026-08-16, une session anonyme Supabase créée en JUIN est
/// redevenue active sur l'appareil. L'app a configuré RevenueCat avec cet
/// `appUserID` périmé ; RevenueCat a suivi ; le renouvellement Weekly du 2026-08-23
/// a donc été crédité au mauvais compte. L'utilisateur payant s'est retrouvé en
/// « Free plan · 0 spaces », avec un paywall d'ACHAT — alors qu'il payait déjà.
///
/// L'INVARIANT VIOLÉ. Le boot liait RevenueCat à `auth.currentUser.id` **sans
/// jamais vérifier que cette identité était encore la bonne**. Une session
/// techniquement valide était traitée comme une identité légitime.
///
/// POURQUOI `configure()` EST DESTRUCTEUR. Ce n'est pas seulement `logIn` qui
/// déplace un abonnement : au démarrage, le SDK poste automatiquement le reçu
/// StoreKit présent sur l'appareil. Si ce reçu appartient déjà à un autre
/// `appUserID`, la politique « Transfer to new App User ID » de RevenueCat peut
/// transférer la propriété. La validation doit donc précéder **toute** liaison,
/// première configuration comprise — pas seulement les re-liaisons.
///
/// LA RÈGLE. Dans le doute, on ne lie pas. Une liaison non faite se rattrape au
/// boot suivant ; un abonnement transféré au mauvais compte demande une
/// réparation manuelle en base (c'est ce qui a été nécessaire ici).
///
/// Le backend fournit déjà le signal nécessaire : `/me/status` passe par
/// `require_active_identity`, qui répond **403 `identity_merged`** sur une identité
/// fermée. Aucun ajout d'API n'est requis.
library;

import 'package:flutter/foundation.dart';

/// Santé de l'identité Supabase courante, telle que le backend la rapporte.
enum IdentityHealth {
  /// `/me/status` a répondu 2xx : identité active, servie par le backend.
  canonical,

  /// `/me/status` a répondu 403 `identity_merged` : identité fermée par une fusion.
  merged,

  /// Indéterminée — réseau, 5xx, timeout, JWT absent. JAMAIS assimilée à « saine ».
  unknown,
}

/// Résultat d'une sonde `/me/status` : santé de l'identité + droit réellement
/// reconnu par le backend. Les deux sont nécessaires — la santé seule ne suffit
/// pas à décider (voir la règle 5 de [decideRcBinding]).
class IdentityProbe {
  const IdentityProbe(this.health, {this.backendEntitled = false});

  final IdentityHealth health;

  /// Vrai si le backend accorde un accès RÉEL (`access_source` ∈ {admin, pass,
  /// promo}). `restore_required` et `free` valent FAUX : dans les deux cas
  /// l'identité ne détient pas d'abonnement mesuré.
  final bool backendEntitled;

  static const unknown = IdentityProbe(IdentityHealth.unknown);
}

/// Décision portant sur la liaison RevenueCat.
enum RcBindAction {
  /// Les deux identités coïncident déjà et l'identité est saine — ne rien faire.
  noop,

  /// Identité Supabase vérifiée saine — lier RevenueCat dessus (configure ou logIn).
  bindToSupabase,

  /// Identité fermée : NE JAMAIS lier. L'utilisateur doit récupérer son compte.
  recoveryRequired,

  /// État indéterminé : conserver la liaison existante, ne rien transférer.
  holdSafe,
}

/// Traduit une sonde HTTP en verdict de santé. PURE et testable.
///
/// `networkError` couvre tout ce qui empêche d'obtenir une réponse (timeout, DNS,
/// socket). Un 5xx est également « inconnu » : le backend n'a pas pu se prononcer.
IdentityHealth healthFromProbe({
  int? httpStatus,
  String? errorCode,
  bool networkError = false,
}) {
  if (networkError || httpStatus == null) return IdentityHealth.unknown;
  if (httpStatus == 403 && errorCode == 'identity_merged') {
    return IdentityHealth.merged;
  }
  if (httpStatus >= 200 && httpStatus < 300) return IdentityHealth.canonical;
  // 401 (JWT expiré), 5xx, 503 identity_check_unavailable, tout le reste :
  // le backend n'affirme PAS que l'identité est saine → on ne lie pas.
  return IdentityHealth.unknown;
}

/// LE cœur de la correction. PURE, sans Supabase ni RevenueCat, donc testable
/// exhaustivement sur toute la matrice de scénarios.
///
/// LA RÈGLE 5 EST CELLE QUI AURAIT ÉVITÉ L'INCIDENT — et il faut comprendre
/// pourquoi les quatre premières n'auraient PAS suffi. Le 2026-08-16, l'identité
/// ressuscitée `eb78d687` était parfaitement « saine » du point de vue du backend :
/// `/me/status` répondait 200 avec `access_source=free`. Une règle du type
/// « identité saine + identifiants différents ⇒ lier » aurait donc lié RevenueCat
/// dessus et reproduit exactement le sinistre.
///
/// Le signal réellement discriminant n'est pas la santé de l'identité, c'est la
/// DIRECTION du transfert : lier ferait passer un abonnement ACTIF d'une identité
/// qui le détient vers une identité qui n'a rien. Ce mouvement-là n'est jamais
/// automatique — il exige un Restore explicite de l'utilisateur.
///
/// Ordre des règles, délibéré :
///   1. pas d'identité Supabase → rien à lier ;
///   2. identité FERMÉE → récupération, **même si les identifiants coïncident**
///      (une identité fusionnée reste fermée : le backend 403 tout) ;
///   3. identifiants déjà alignés → rien à faire ;
///   4. santé inconnue → on conserve l'existant (aucun transfert à l'aveugle) ;
///   5. RevenueCat détient un abonnement actif que la cible n'a PAS → récupération,
///      jamais de liaison automatique ;
///   6. sinon → on lie.
RcBindAction decideRcBinding({
  required String? supabaseUserId,
  required String? rcAppUserId,
  required IdentityHealth health,
  bool rcHasActiveEntitlement = false,
  bool backendSaysEntitled = false,
}) {
  final sb = (supabaseUserId ?? '').trim();
  if (sb.isEmpty) return RcBindAction.holdSafe;

  if (health == IdentityHealth.merged) return RcBindAction.recoveryRequired;

  final rc = (rcAppUserId ?? '').trim();
  if (rc.isNotEmpty && rc == sb) return RcBindAction.noop;

  if (health == IdentityHealth.unknown) return RcBindAction.holdSafe;

  // Règle 5 — la garde anti-sinistre. Lier déplacerait un abonnement payé.
  if (rcHasActiveEntitlement && !backendSaysEntitled) {
    return RcBindAction.recoveryRequired;
  }

  return RcBindAction.bindToSupabase;
}

/// Vrai si l'application doit présenter un état de RÉCUPÉRATION plutôt qu'un
/// paywall d'achat. Utilisé pour garantir qu'un abonné payant ne retombe jamais
/// silencieusement sur « Free plan · acheter ».
bool requiresIdentityRecovery(RcBindAction action) =>
    action == RcBindAction.recoveryRequired;

// ── Porteur d'état runtime ───────────────────────────────────────────────────
// Volontairement séparé de la logique ci-dessus, qui reste PURE et testable sans
// Flutter. Ce drapeau ne fait qu'empêcher l'UI de proposer un ACHAT quand Ayden
// sait que le compte est en récupération d'identité.

/// Drapeau global « récupération d'identité requise ». Faux par défaut : aucune
/// UI ne change tant que la convergence n'a pas explicitement constaté une
/// identité fermée.
final ValueNotifier<bool> identityRecoveryRequired = ValueNotifier<bool>(false);

/// Applique le verdict au drapeau global. Idempotent.
void applyIdentityVerdict(RcBindAction action) {
  final v = requiresIdentityRecovery(action);
  if (identityRecoveryRequired.value != v) {
    identityRecoveryRequired.value = v;
    debugPrint('[IDENTITY][RECOVERY] requiresRecovery=$v (action=$action)');
  }
}
