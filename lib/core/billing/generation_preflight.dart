import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/me_status_provider.dart';
import '../providers/post_signout_pending_provider.dart';
import '../../data/services/status_service.dart';
import '../../features/paywall/paywall_sheet.dart';
import '../../features/premium/premium_center_sheet.dart';

/// RC-PR3b — destination du PREFLIGHT génératif, décidée PUREMENT depuis `MeStatus`
/// (testable sans widget ni réseau). Couvre le cas `proceed` ET les 3 destinations de deny.
enum GenerationPreflightDestination {
  /// L'utilisateur peut générer (`can_generate == true`) — admin/promo/free-avec-quota/pass-avec-solde.
  proceed,

  /// Free épuisé (ou `insufficient_credits`) → PaywallSheet d'abonnement (parcours existant).
  freePaywall,

  /// Abonné (weekly/annual) à 0 Space (`pass_exhausted`) → Premium Center « plan épuisé ».
  /// JAMAIS le paywall d'abonnement : l'utilisateur est déjà abonné.
  passExhausted,

  /// Accès premium probable mais pass mesuré introuvable (`restore_required` / `needsRestore`
  /// / `no_active_pass`) → surface Restore du Premium Center. On propose de RESTAURER/SYNCHRONISER,
  /// jamais de racheter un abonnement.
  restoreRequired,
}

/// Décision PURE (RC-PR3b). Ne dépend NI du SDK Apple NI de RevenueCat NI du réseau.
///  • `can_generate == true` → proceed (couvre admin/promo/free-avec-quota/pass-avec-solde :
///    ils ne voient JAMAIS de paywall ni d'état épuisé dans leur état normal).
///  • restore_required / needsRestore / gateReason == 'no_active_pass' → restoreRequired
///    (accès premium probable mais pass introuvable → proposer Restore, PAS un rachat).
///  • pass ET gateReason == 'pass_exhausted' → passExhausted (uniquement le vrai épuisement).
///  • sinon (free / insufficient_credits / cas ambigu) → freePaywall.
GenerationPreflightDestination generationPreflightDestinationFor(MeStatus status) {
  if (status.canGenerate) {
    return GenerationPreflightDestination.proceed;
  }
  if (status.accessSource == 'restore_required' ||
      status.needsRestore ||
      status.gateReason == 'no_active_pass') {
    return GenerationPreflightDestination.restoreRequired;
  }
  if (status.accessSource == 'pass' && status.gateReason == 'pass_exhausted') {
    return GenerationPreflightDestination.passExhausted;
  }
  return GenerationPreflightDestination.freePaywall;
}

/// Signature de la présentation d'une surface de DENY. Injectable en test
/// ([ensureCanGenerateOrShowPaywall] paramètre `presentDeny`) pour valider le ROUTAGE sans
/// monter les vraies sheets (le vrai `PaywallSheet` dépend de Supabase/RevenueCat). En
/// production, le défaut [_routeDeny] est utilisé — comportement inchangé.
typedef DenyPresenter = Future<void> Function(
  WidgetRef ref,
  BuildContext context,
  GenerationPreflightDestination dest,
);

/// P0 bloc (b) — PREFLIGHT billing CENTRALISÉ pour TOUS les points d'entrée génératifs
/// (fresh upload, REUPLOAD, refine, switch, top-generate). Un seul choke-point → plus de
/// bypass silencieux (BUG 3 : le reupload est un FIRST_VISION qui ratait le preflight
/// `genIteration>1`).
///
/// Renvoie `true` si la génération peut continuer, `false` si une surface a été montrée
/// (l'appelant DOIT alors `return` sans créer de session/loading/pending/POST). Comme
/// historiquement, on `await` la présentation de la surface avant de rendre `false` : le
/// bouton reste protégé pendant que la surface de deny est ouverte.
///
/// RC-PR3b — la destination du DENY est différenciée (voir [generationPreflightDestinationFor]) :
///   • free / insufficient_credits → PaywallSheet(quota) ;
///   • abonné à 0 Space (pass_exhausted) → Premium Center « plan épuisé » (JAMAIS le paywall) ;
///   • restore_required / no_active_pass → Premium Center (surface Restore).
///
/// `fresh:true` (fresh upload / reupload = nouvelle V1) → refresh BORNÉ de /me/status avant
/// décision. `fresh:false` (refine in-session) → cache seul (instantané). Cache-first : un deny
/// DÉJÀ connu → surface immédiate SANS réseau. FAIL-OPEN si /me/status inconnu (st==null) → on
/// laisse passer : le HOLD atomique backend (billing_try_hold) reste le filet.
///
/// `presentDeny` est un seam de TEST (défaut = [_routeDeny], la vraie présentation). N'est PAS
/// destiné à la production.
Future<bool> ensureCanGenerateOrShowPaywall(
  WidgetRef ref,
  BuildContext context, {
  required bool fresh,
  Duration refreshTimeout = const Duration(seconds: 3),
  DenyPresenter presentDeny = _routeDeny,
  GuestSetupPresenter presentGuestSetup = _presentGuestSetup,
}) async {
  // 0. Anti-abus (BUG 2) — un invité FRAÎCHEMENT créé par le Sign out, dont le marqueur
  //    trial-consumed n'est pas encore confirmé, NE DOIT PAS générer (sinon un Free 3 serait
  //    « offert » au sign-out). Le flag local persistant gate ICI TOUS les points d'entrée
  //    génératifs (le même choke-point que le paywall) ; la surface propose un Retry qui
  //    re-tente le marqueur. Priorité sur le paywall : un invité en attente ne voit rien d'autre.
  if (ref.read(postSignoutPendingProvider)) {
    await presentGuestSetup(ref, context);
    return false;
  }
  // 1. Cache-first — un deny DÉJÀ connu → surface adaptée immédiate, aucun aller-retour réseau.
  final cached = ref.read(meStatusProvider);
  if (cached != null) {
    final dest = generationPreflightDestinationFor(cached);
    if (dest != GenerationPreflightDestination.proceed) {
      await presentDeny(ref, context, dest);
      return false;
    }
    // cache = proceed → on continue (un fresh peut encore re-confirmer ci-dessous).
  }
  // 2. Nouvelle V1 (fresh) → confirmer la vérité backend (borné, fail-open).
  if (fresh) {
    try {
      await ref
          .read(meStatusProvider.notifier)
          .refresh()
          .timeout(refreshTimeout, onTimeout: () {});
    } catch (_) {/* fail-open : le HOLD atomique backend décide */}
    if (!context.mounted) return false;
    final st = ref.read(meStatusProvider);
    if (st != null) {
      final dest = generationPreflightDestinationFor(st);
      if (dest != GenerationPreflightDestination.proceed) {
        await presentDeny(ref, context, dest);
        return false;
      }
    }
  }
  return true; // fail-open si st==null (inconnu)
}

/// Ouvre la surface adaptée au deny et attend sa fermeture (sémantique historique).
/// `freePaywall` → paywall d'abonnement ; `passExhausted` / `restoreRequired` → Premium Center
/// (qui route lui-même l'abonné épuisé vs la surface Restore selon `access_source`).
/// N'est jamais appelé avec `proceed`.
Future<void> _routeDeny(
  WidgetRef ref,
  BuildContext context,
  GenerationPreflightDestination dest,
) async {
  switch (dest) {
    case GenerationPreflightDestination.proceed:
      return; // garde-fou : jamais atteint
    case GenerationPreflightDestination.freePaywall:
      await _showQuotaPaywall(context);
      return;
    case GenerationPreflightDestination.passExhausted:
    case GenerationPreflightDestination.restoreRequired:
      await showPremiumCenter(context, ref);
      return;
  }
}

Future<void> _showQuotaPaywall(BuildContext context) async {
  await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PaywallSheet(trigger: PaywallTrigger.quota),
  );
}

/// Présentation de la surface « configuration invité en cours » (BUG 2). Seam de TEST
/// (défaut [_presentGuestSetup]) : un test observe le BLOCAGE (la porte rend `false`) sans
/// monter le dialog. N'est PAS destiné à la production.
typedef GuestSetupPresenter = Future<void> Function(
  WidgetRef ref,
  BuildContext context,
);

/// Dialog transitoire : le marqueur post-sign-out n'est pas encore confirmé. Un seul bouton
/// Retry re-tente le marqueur ([PostSignoutPendingNotifier.resolve]) puis se ferme ; l'invité
/// re-tapera Generate (la porte re-évalue le flag). Aucune génération n'a lieu tant qu'il est levé.
Future<void> _presentGuestSetup(WidgetRef ref, BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (dctx) => AlertDialog(
      content: const Text(kGuestSetupPendingMessage),
      actions: [
        TextButton(
          onPressed: () async {
            await ref.read(postSignoutPendingProvider.notifier).resolve();
            if (dctx.mounted) Navigator.of(dctx).pop();
          },
          child: const Text('Retry'),
        ),
      ],
    ),
  );
}
