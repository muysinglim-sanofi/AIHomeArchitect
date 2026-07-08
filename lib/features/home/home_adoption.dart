/// Fix "adopt completed generations after session exit" — décision PURE (aucune
/// I/O) partagée par les deux chemins de l'accueil (_deriveRecentFromBackend au
/// lancement + _reconcilePending en poll). Prend le probe backend de
/// /v1/intents/latest (ou null) et la preview locale de la carte, décide quoi
/// faire. Testable isolément (mirror du pattern PendingRecoveryService.decide).
///
/// Contexte du bug : une génération qui se termine pendant que l'utilisateur est
/// HORS de la session laisse toute la donnée côté backend (image en storage,
/// message image_result persisté, intent SUCCEEDED avec result_ref) — mais la
/// carte d'accueil dérive `latest_preview` d'un write frontend qui n'a jamais eu
/// lieu (écran disposé → réponse abandonnée). La carte retombe alors sur la
/// source. L'adoption re-dérive la vérité depuis le backend → robuste après
/// sortie de session / kill app / pending supprimé / autre appareil / heures plus
/// tard.
library;

import '../../core/providers/pending_generations_provider.dart';
import '../../core/providers/session_provider.dart';

enum HomeAdoptionAction {
  /// SUCCEEDED + after_image_url présent ≠ preview locale → écrire la preview
  /// (DB + état mémoire) et marquer readyUnseen. [HomeAdoptionDecision.afterUrl]
  /// porte l'URL.
  adopt,

  /// Intent FAILED → surfacer un état d'erreur (badge "Failed").
  markError,

  /// Terminal sans image adoptable (SUCCEEDED sans URL, ou statut terminal autre)
  /// → nettoyer un éventuel spinner, mais ne JAMAIS écraser la preview existante.
  clearSpinner,

  /// Intent RUNNING → laisser/poser le spinner ; ne rien effacer.
  keepSpinner,

  /// Rien à faire : probe indisponible (null) ou image déjà adoptée (preview ==
  /// after_image_url) → aucune ré-écriture (idempotent).
  noop,
}

class HomeAdoptionDecision {
  final HomeAdoptionAction action;

  /// URL de l'image à adopter — non-null UNIQUEMENT quand action == adopt.
  final String? afterUrl;

  const HomeAdoptionDecision(this.action, [this.afterUrl]);
}

/// PURE. `probe` = la Map renvoyée par GenerationService.getLatestIntent
/// (/v1/intents/latest), ou null si la requête a échoué. `currentPreview` =
/// project.afterImageUrl local (colonne sessions.latest_preview).
HomeAdoptionDecision decideHomeAdoption({
  required Map<String, dynamic>? probe,
  required String? currentPreview,
}) {
  if (probe == null) {
    return const HomeAdoptionDecision(HomeAdoptionAction.noop);
  }
  final status = probe['status'] as String?;
  if (status == 'RUNNING') {
    return const HomeAdoptionDecision(HomeAdoptionAction.keepSpinner);
  }
  if (status == 'SUCCEEDED') {
    final after = (probe['after_image_url'] as String?) ?? '';
    // SUCCEEDED sans URL exploitable → ne pas écraser la preview (garde-fou
    // "SUCCEEDED sans after_image_url : ne pas écraser latest_preview").
    if (after.isEmpty) {
      return const HomeAdoptionDecision(HomeAdoptionAction.clearSpinner);
    }
    // Déjà adoptée → aucune ré-écriture (idempotent).
    if ((currentPreview ?? '') == after) {
      return const HomeAdoptionDecision(HomeAdoptionAction.noop);
    }
    return HomeAdoptionDecision(HomeAdoptionAction.adopt, after);
  }
  if (status == 'FAILED' || status == 'FAILED_TERMINAL') {
    return const HomeAdoptionDecision(HomeAdoptionAction.markError);
  }
  // Statut inconnu / null (mais probe non-null) → nettoyer un spinner éventuel,
  // sans toucher à la preview.
  return const HomeAdoptionDecision(HomeAdoptionAction.clearSpinner);
}

/// Applique une [HomeAdoptionDecision] sur les notifiers RÉELS (état mémoire + DB
/// via SessionNotifier.updateLatestPreview). SÉPARÉ de la décision pure pour être
/// testable SANS monter le widget ni faire de réseau — c'est la « couture »
/// recovery↔home que les anciens stress tests ne couvraient pas (méthodes privées
/// de widget = angle mort). [inFlightContext] = true depuis le poller de spinner
/// (_reconcilePending) : on nettoie/mute le spinner ; false au lancement
/// (_deriveRecentFromBackend) : on peut (re)poser un spinner RUNNING. [currentLifecycle]
/// = état lifecycle courant de la session (pour le garde keepSpinner).
void applyAdoptionToNotifiers({
  required SessionNotifier sessions,
  required PendingGenerationsNotifier pending,
  required String sessionId,
  required HomeAdoptionDecision decision,
  required bool inFlightContext,
  GenerationLifecycle? currentLifecycle,
}) {
  switch (decision.action) {
    case HomeAdoptionAction.adopt:
      // updateLatestPreview = mutation de l'état mémoire (_applyToState) + write DB
      // fire-and-forget → la carte se rafraîchit immédiatement, la preview persiste.
      sessions.updateLatestPreview(sessionId, decision.afterUrl!);
      pending.markReadyUnseen(sessionId); // badge "Ready" (résultat non encore vu)
      break;
    case HomeAdoptionAction.markError:
      if (inFlightContext) pending.markErrorUnseen(sessionId);
      break;
    case HomeAdoptionAction.clearSpinner:
      if (inFlightContext) pending.clear(sessionId);
      break;
    case HomeAdoptionAction.keepSpinner:
      // RUNNING : au lancement, (re)poser le spinner si absent ; en poll, ne rien
      // changer (il tourne déjà).
      if (!inFlightContext && currentLifecycle != GenerationLifecycle.inFlight) {
        pending.markInFlight(sessionId);
      }
      break;
    case HomeAdoptionAction.noop:
      break;
  }
}
