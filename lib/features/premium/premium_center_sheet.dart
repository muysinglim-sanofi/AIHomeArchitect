/// Premium Center (Lot 1) — surface PARTAGÉE de consultation/gestion de l'abonnement,
/// ouvrable depuis la Home ET le Profil via [showPremiumCenter] (même composant, aucune
/// duplication). Pilotée par la vérité backend (`meStatusProvider` / `access_source` +
/// `plan_type`), elle N'ORCHESTRE aucun crédit et ne touche NI RC-PR3a NI RC-PR3b.
///
/// Lot 1 : états FREE (→ parcours d'achat existant, inchangé) / WEEKLY / ANNUAL / PROMO /
/// ADMIN / restore_required. PAS de bouton « Upgrade to Annual » (Lot 2, après confirmation
/// du subscription group App Store Connect). Le bouton « Manage Subscription » est ajouté au
/// Commit 3 (managementURL RevenueCat).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/providers/me_status_provider.dart';
import '../../data/services/revenuecat_service.dart';
import '../../data/services/status_service.dart';
import '../../shared/widgets/app_button.dart';
import '../paywall/paywall_sheet.dart';

/// Modes d'affichage du Premium Center, dérivés PUREMENT de `access_source`/`plan_type`.
enum PremiumCenterMode { purchase, weekly, annual, premiumGeneric, promo, admin, restoreRequired }

/// View-model PUR (testable sans widget/l10n) du Premium Center.
class PremiumCenterView {
  final PremiumCenterMode mode;
  final bool showRestore;

  /// Lot 1 : TOUJOURS false. Le bouton « Upgrade to Annual » est ajouté en Lot 2,
  /// uniquement après confirmation du subscription group App Store Connect.
  final bool showUpgrade;

  const PremiumCenterView(this.mode, {this.showRestore = false, this.showUpgrade = false});
}

/// Sélection d'état PURE — c'est le cœur testé du Lot 1.
PremiumCenterView premiumCenterViewFor(MeStatus s) {
  switch (s.accessSource) {
    case 'pass':
      final mode = s.isWeekly
          ? PremiumCenterMode.weekly
          : s.isAnnual
              ? PremiumCenterMode.annual
              : PremiumCenterMode.premiumGeneric;
      return PremiumCenterView(mode, showRestore: true);
    case 'promo':
      return const PremiumCenterView(PremiumCenterMode.promo);
    case 'admin':
      return const PremiumCenterView(PremiumCenterMode.admin);
    case 'restore_required':
      return const PremiumCenterView(PremiumCenterMode.restoreRequired, showRestore: true);
    default:
      // free / inconnu → parcours d'achat existant.
      return const PremiumCenterView(PremiumCenterMode.purchase);
  }
}

/// Point d'entrée UNIQUE, appelé à l'identique depuis Home et Profil.
Future<void> showPremiumCenter(BuildContext context, WidgetRef ref) async {
  final status = ref.read(meStatusProvider);
  final view = status == null
      ? const PremiumCenterView(PremiumCenterMode.purchase)
      : premiumCenterViewFor(status);

  if (view.mode == PremiumCenterMode.purchase) {
    // FREE / inconnu → le parcours d'achat EXISTANT (PaywallSheet), INCHANGÉ.
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PaywallSheet(trigger: PaywallTrigger.locked),
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PremiumCenterSheet(status: status!),
  );
}

class PremiumCenterSheet extends ConsumerStatefulWidget {
  final MeStatus status;
  const PremiumCenterSheet({super.key, required this.status});

  @override
  ConsumerState<PremiumCenterSheet> createState() => _PremiumCenterSheetState();
}

class _PremiumCenterSheetState extends ConsumerState<PremiumCenterSheet> {
  String? _formatDate(BuildContext context, String? iso) {
    if (iso == null || iso.isEmpty) return null;
    try {
      final dt = DateTime.parse(iso).toLocal();
      return MaterialLocalizations.of(context).formatShortDate(dt);
    } catch (_) {
      return null;
    }
  }

  /// Restore honnête (miroir du profil) : autorité = backend /purchases/sync, terminal garanti.
  Future<void> _restore() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(
      content: Text(l10n.stRestoring),
      duration: const Duration(seconds: 2),
    ));
    final userId = Supabase.instance.client.auth.currentUser?.id;
    RestoreOutcome outcome = RestoreOutcome.failed;
    try {
      if (userId != null) {
        await RevenuecatService.instance.ensureConfigured(userId: userId);
      }
      await RevenuecatService.instance
          .restorePurchases()
          .timeout(const Duration(seconds: 15));
      final sync = await StatusService().syncPurchases().timeout(
            const Duration(seconds: 12),
            onTimeout: () => const <String, dynamic>{},
          );
      outcome = restoreOutcomeFromSync(sync);
    } catch (_) {
      outcome = RestoreOutcome.failed;
    }
    if (mounted) await ref.read(meStatusProvider.notifier).refresh();
    final String msg = switch (outcome) {
      RestoreOutcome.restored => l10n.stRestoreDone,
      RestoreOutcome.activeNoSpaces => l10n.stRestoreActiveNoSpaces,
      RestoreOutcome.noneFound => l10n.stRestoreNoneFound,
      RestoreOutcome.failed => l10n.stRestoreFailed,
    };
    try {
      messenger?.showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
    } catch (_) {/* messenger défunt */}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Live : reflète les changements (ex. après restore) ; fallback = snapshot d'ouverture.
    final MeStatus s = ref.watch(meStatusProvider) ?? widget.status;
    final view = premiumCenterViewFor(s);

    final (String title, String subtitle) = switch (view.mode) {
      PremiumCenterMode.weekly => (l10n.pcWeeklyPremium, _passSubtitle(context, s)),
      PremiumCenterMode.annual => (l10n.pcAnnualPremium, _passSubtitle(context, s)),
      PremiumCenterMode.premiumGeneric => (l10n.stPremiumActive, _passSubtitle(context, s)),
      PremiumCenterMode.promo => (l10n.pcPremiumAccess, l10n.pcPromotionActive),
      PremiumCenterMode.admin => (l10n.stAdminFullAccess, l10n.stUnlimited),
      PremiumCenterMode.restoreRequired => (l10n.stRestoreRequired, l10n.stRestoreRequiredSub),
      PremiumCenterMode.purchase => (l10n.stPremiumActive, ''),
    };

    final bool isPassMode = view.mode == PremiumCenterMode.weekly ||
        view.mode == PremiumCenterMode.annual ||
        view.mode == PremiumCenterMode.premiumGeneric;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.workspace_premium,
                color: AppColors.accent, size: 40),
            const SizedBox(height: AppSpacing.md),
            if (isPassMode)
              Text(
                l10n.pcCurrentPlan.toUpperCase(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                      letterSpacing: 1.0,
                    ),
              ),
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            // NOTE Lot 1 : PAS de « Upgrade to Annual » (Lot 2, après subscription group ASC).
            // NOTE Commit 3 : « Manage Subscription » (managementURL) s'insère ici.
            if (view.showRestore)
              AppButton(
                label: l10n.pwRestore,
                variant: AppButtonVariant.secondary,
                onPressed: _restore,
              ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: l10n.spClose,
              variant: AppButtonVariant.ghost,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ),
    );
  }

  String _passSubtitle(BuildContext context, MeStatus s) {
    final l10n = context.l10n;
    final String spaces = s.availableCredits <= 0
        ? l10n.stPassNoSpaces
        : l10n.stPassCreditsRemaining(s.availableCredits);
    final String? renews = _formatDate(context, s.passRenewsAt ?? s.passExpiresAt);
    return renews == null ? spaces : '$spaces · ${l10n.stPassRenews(renews)}';
  }
}
