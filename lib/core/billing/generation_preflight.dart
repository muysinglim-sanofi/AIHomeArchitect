import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/me_status_provider.dart';
import '../../features/paywall/paywall_sheet.dart';

/// P0 bloc (b) — PREFLIGHT billing CENTRALISÉ pour TOUS les points d'entrée génératifs
/// (fresh upload, REUPLOAD, refine, switch, top-generate). Un seul choke-point → plus de
/// bypass silencieux (BUG 3 : le reupload est un FIRST_VISION qui ratait le preflight
/// `genIteration>1`).
///
/// Renvoie `true` si la génération peut continuer, `false` si le paywall a été montré
/// (l'appelant DOIT alors `return` sans créer de session/loading/pending/POST).
///
/// `fresh:true` (fresh upload / reupload = nouvelle V1) → refresh BORNÉ de /me/status avant
/// décision (la vérité backend peut avoir changé). `fresh:false` (refine in-session) → cache
/// seul (instantané, aucune latence). Cache-first : un deny DÉJÀ connu → paywall immédiat
/// SANS réseau. FAIL-OPEN si /me/status inconnu (st==null) → on laisse passer : le HOLD
/// atomique backend (billing_try_hold) reste le filet.
Future<bool> ensureCanGenerateOrShowPaywall(
  WidgetRef ref,
  BuildContext context, {
  required bool fresh,
  Duration refreshTimeout = const Duration(seconds: 3),
}) async {
  // 1. Cache-first — un deny DÉJÀ connu → paywall instantané, aucun aller-retour réseau.
  final cached = ref.read(meStatusProvider);
  if (cached != null && !cached.canGenerate) {
    await _showQuotaPaywall(context);
    return false;
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
    if (st != null && !st.canGenerate) {
      await _showQuotaPaywall(context);
      return false;
    }
  }
  return true; // fail-open si st==null (inconnu)
}

Future<void> _showQuotaPaywall(BuildContext context) async {
  await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PaywallSheet(trigger: PaywallTrigger.quota),
  );
}
