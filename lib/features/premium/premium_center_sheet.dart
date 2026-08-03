/// Premium Center — surface PARTAGÉE de consultation/gestion de l'abonnement,
/// ouvrable depuis la Home ET le Profil via [showPremiumCenter] (même composant, aucune
/// duplication). Pilotée par la vérité backend (`meStatusProvider` / `access_source` +
/// `plan_type`), elle N'ORCHESTRE aucun crédit et ne touche NI RC-PR3a NI RC-PR3b.
///
/// Lot 1 : états FREE (→ parcours d'achat existant, inchangé) / WEEKLY / ANNUAL / PROMO /
/// ADMIN / restore_required + « Manage Subscription » (managementURL RevenueCat).
///
/// Lot 2 (2026-07-12) : **Upgrade Weekly → Annual**. Le CTA n'apparaît QUE pour
/// `plan_type == weekly` ET si le package Annual est résolu dans l'offering courant.
/// Preuve d'achat : le PRODUIT EXACT `com.aydenstudio.app.annual` (pas « premium actif »,
/// qu'un abonné Weekly possède déjà — cf. RevenuecatService.purchaseAnnual). Succès CONFIRMÉ :
/// `plan_type == annual` & `active_product_id == com.aydenstudio.app.annual` (PAS
/// `available_credits == 300`, fragile car available_credits = bucket pass + free résiduel).
/// Séquence après achat : `/purchases/sync` → `meStatusProvider.refresh()`. Aucun changement
/// backend (Weekly→Annual = 300, pas 318, géré par la projection wallet). Aucun pack de Spaces.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Package;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/providers/me_status_provider.dart';
import '../../data/services/revenuecat_service.dart';
import '../../data/services/status_service.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/legal_compliance_footer.dart';
import '../paywall/paywall_sheet.dart';

/// Product-id App Store du pass Annual (autorité = App Store Connect / backend
/// `active_product_id`). Sert UNIQUEMENT à confirmer que le pass actif est bien l'Annual.
const String kAnnualProductId = 'com.aydenstudio.app.annual';

/// Modes d'affichage du Premium Center, dérivés PUREMENT de `access_source`/`plan_type`.
enum PremiumCenterMode { purchase, weekly, annual, premiumGeneric, promo, admin, restoreRequired }

/// Issue de l'upgrade Weekly → Annual (orchestration testable).
///  • cancelled : rester Weekly, AUCUN /purchases/sync, aucun message agressif.
///  • failed    : rester Weekly, statut/solde inchangés, message honnête, CTA réactivé.
///  • confirmed : le pass actif backend est l'Annual EXACT (plan_type==annual & product-id).
///  • deferred  : achat OK mais backend pas (encore) à jour (ou sync/refresh en erreur)
///                → « achat réussi » + « Refresh plan », JAMAIS re-proposer d'acheter.
enum UpgradeResult { cancelled, failed, confirmed, deferred }

/// View-model PUR (testable sans widget/l10n) du Premium Center.
class PremiumCenterView {
  final PremiumCenterMode mode;
  final bool showRestore;

  /// « Manage Subscription » ÉLIGIBLE (abonnement store). Le bouton réel n'est rendu QUE si
  /// RevenueCat renvoie une managementURL non-null (masqué proprement sinon).
  final bool showManage;

  /// Lot 2 : ÉLIGIBILITÉ à l'upgrade (true UNIQUEMENT pour `plan_type == weekly`). Le CTA réel
  /// n'est rendu QUE si le package Annual est aussi résolu (voir [shouldRenderUpgrade]).
  final bool showUpgrade;

  const PremiumCenterView(this.mode,
      {this.showRestore = false, this.showManage = false, this.showUpgrade = false});
}

/// Sélection d'état PURE — cœur testé du Premium Center.
PremiumCenterView premiumCenterViewFor(MeStatus s) {
  switch (s.accessSource) {
    case 'pass':
      if (s.isWeekly) {
        // Weekly → propose l'upgrade Annual (Lot 2).
        return const PremiumCenterView(PremiumCenterMode.weekly,
            showRestore: true, showManage: true, showUpgrade: true);
      }
      final mode = s.isAnnual ? PremiumCenterMode.annual : PremiumCenterMode.premiumGeneric;
      // Annual / premium générique → PAS d'upgrade.
      return PremiumCenterView(mode, showRestore: true, showManage: true);
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

/// Le CTA Upgrade n'est rendu QUE si l'état l'autorise ET le package Annual est disponible
/// (miroir de « Manage » : éligible mais rendu seulement si dispo). Pure → testable.
bool shouldRenderUpgrade(PremiumCenterView v, {required bool annualAvailable}) =>
    v.showUpgrade && annualAvailable;

/// Succès CONFIRMÉ de l'upgrade : le pass actif backend est l'Annual EXACT **ET** sa capacité
/// (300 Spaces) est projetée dans le wallet. On exige `available_credits >= 300` (PAS `== 300`) :
/// available_credits = bucket pass + bucket free (≥ 0) → un reliquat free peut donner 305, on
/// l'accepte ; mais on ne confirme JAMAIS un Annual à 0 / 18 / 299 (Spaces pas encore projetés
/// → « deferred » + Refresh plan). Le plancher 300 = capacité Annual garantie/auditée côté backend
/// (products.credits_granted = 300, Weekly ignoré par la projection wallet).
bool upgradeConfirmed(MeStatus? s) =>
    s != null &&
    s.isAnnual &&
    s.activeProductId == kAnnualProductId &&
    s.availableCredits >= 300;

/// Dépendances externes de l'upgrade (RevenueCat / backend / provider), INJECTABLES pour les
/// widget-tests (défaut = réelles). Découple la logique du SDK et du réseau.
class UpgradeDeps {
  /// Le package Annual est-il résolu dans l'offering courant ? (→ rend/masque le CTA)
  final Future<bool> Function() loadAnnualAvailable;

  /// Achat de l'Annual, CLASSIFIÉ par le produit exact (activated/cancelled/failed).
  final Future<PurchaseAttempt> Function() purchase;

  /// `/purchases/sync` puis `meStatusProvider.refresh()`.
  final Future<void> Function() syncAndRefresh;

  const UpgradeDeps({
    required this.loadAnnualAvailable,
    required this.purchase,
    required this.syncAndRefresh,
  });
}

/// Orchestrateur PUR de l'upgrade Weekly → Annual (Lot 2). Testable sans widget ni SDK :
/// les effets de bord sont injectés. Séquence : achat → (si activé) sync+refresh → confirmer
/// via [upgradeConfirmed] (pass actif = Annual exact).
Future<UpgradeResult> runAnnualUpgrade({
  required Future<PurchaseAttempt> Function() purchase,
  required Future<void> Function() syncAndRefresh,
  required MeStatus? Function() readStatus,
}) async {
  final attempt = await purchase();
  if (attempt == PurchaseAttempt.cancelled) return UpgradeResult.cancelled; // pas de sync
  if (attempt == PurchaseAttempt.failed) return UpgradeResult.failed; // statut inchangé
  try {
    await syncAndRefresh();
  } catch (_) {
    return UpgradeResult.deferred; // achat réussi mais MAJ backend non confirmée
  }
  return upgradeConfirmed(readStatus()) ? UpgradeResult.confirmed : UpgradeResult.deferred;
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

  /// Test-only : injecte les dépendances d'upgrade (défaut = réelles RevenueCat/backend).
  final UpgradeDeps? deps;

  const PremiumCenterSheet({super.key, required this.status, this.deps});

  @override
  ConsumerState<PremiumCenterSheet> createState() => _PremiumCenterSheetState();
}

class _PremiumCenterSheetState extends ConsumerState<PremiumCenterSheet> {
  String? _mgmtUrl; // managementURL RevenueCat (null = pas de bouton Manage)
  Package? _annualPkg; // résolu par les dépendances RÉELLES uniquement
  bool _annualAvailable = false; // package Annual disponible → CTA rendu
  bool _busy = false; // ré-entrance (dialog + achat) — pas de spinner
  bool _upgrading = false; // spinner + CTA désactivé (achat/sync uniquement)
  bool _deferredSync = false; // achat OK mais backend pas à jour → « Refresh plan »
  late final UpgradeDeps _deps;

  @override
  void initState() {
    super.initState();
    _deps = widget.deps ?? _buildRealDeps();
    final view = premiumCenterViewFor(widget.status);
    // Charge la managementURL uniquement pour un abonnement store éligible.
    if (view.showManage) {
      RevenuecatService.instance.managementUrl().then((url) {
        if (mounted) setState(() => _mgmtUrl = url);
      });
    }
    // Lot 2 — résout la disponibilité du package Annual seulement si l'upgrade est éligible.
    if (view.showUpgrade) {
      _deps.loadAnnualAvailable().then((available) {
        if (mounted) setState(() => _annualAvailable = available);
      });
    }
  }

  /// Dépendances RÉELLES (production) : RevenueCat + backend + provider.
  UpgradeDeps _buildRealDeps() => UpgradeDeps(
        loadAnnualAvailable: () async {
          _annualPkg = await RevenuecatService.instance.annualPackage();
          return _annualPkg != null;
        },
        purchase: () async {
          final p = _annualPkg;
          if (p == null) return PurchaseAttempt.failed;
          return RevenuecatService.instance.purchaseAnnual(p);
        },
        syncAndRefresh: _syncAndRefresh,
      );

  Future<void> _openManage() async {
    final url = _mgmtUrl;
    if (url == null || url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {/* best-effort : ne bloque jamais */}
  }

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

  // ── Lot 2 : Upgrade Weekly → Annual ─────────────────────────────────────────

  /// Confirmation honnête AVANT l'achat (remplacement du solde Weekly + proration éligible,
  /// jamais de promesse de remboursement précis).
  Future<bool> _confirmUpgrade() async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.pcUpgradeConfirmTitle),
        content: Text(l10n.pcUpgradeConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.pcUpgradeConfirmNo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.pcUpgradeConfirmYes),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _syncAndRefresh() async {
    await StatusService().syncPurchases().timeout(
          const Duration(seconds: 12),
          onTimeout: () => const <String, dynamic>{},
        );
    await ref.read(meStatusProvider.notifier).refresh();
  }

  Future<void> _upgrade() async {
    // `_busy` = garde de RÉ-ENTRANCE (couvre dialog + achat) → un 2ᵉ tap est ignoré : pas de
    // 2ᵉ dialog ni de 2ᵉ achat. Distinct du spinner (`_upgrading`) : pendant le dialog on ne
    // veut AUCUN indicateur infini (sinon le rendu ne se stabilise jamais).
    if (_busy) return;
    if (!_annualAvailable) return; // package indisponible → ne jamais acheter à l'aveugle
    _busy = true;
    try {
      final confirmed = await _confirmUpgrade();
      if (!mounted || !confirmed) return; // « Not now » → rien (garde relâchée par finally)
      setState(() {
        _upgrading = true; // spinner + CTA désactivé UNIQUEMENT pendant l'achat/sync
        _deferredSync = false;
      });
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(SnackBar(
        content: Text(context.l10n.pcUpgradeActivating),
        duration: const Duration(seconds: 2),
      ));

      final result = await runAnnualUpgrade(
        purchase: _deps.purchase,
        syncAndRefresh: _deps.syncAndRefresh,
        readStatus: () => ref.read(meStatusProvider),
      );

      if (!mounted) return;
      setState(() {
        _upgrading = false;
        _deferredSync = result == UpgradeResult.deferred;
      });

      final l10n = context.l10n;
      final String? msg = switch (result) {
        UpgradeResult.confirmed => l10n.pcUpgradeDone,
        UpgradeResult.failed => l10n.pcUpgradeFailed,
        UpgradeResult.cancelled => null, // aucun message agressif
        UpgradeResult.deferred => null, // géré par la carte « Refresh plan » inline
      };
      if (msg != null) {
        try {
          messenger?.hideCurrentSnackBar(); // remplace « Activating… » (pas de file d'attente)
          messenger?.showSnackBar(
              SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
        } catch (_) {/* messenger défunt */}
      }
    } finally {
      _busy = false;
    }
  }

  /// Sync différé : relance UNIQUEMENT sync + refresh (jamais un nouvel achat).
  Future<void> _refreshPlan() async {
    if (_upgrading) return;
    setState(() => _upgrading = true);
    try {
      await _deps.syncAndRefresh();
    } catch (_) {/* best-effort */}
    if (!mounted) return;
    setState(() {
      _upgrading = false;
      _deferredSync = !upgradeConfirmed(ref.read(meStatusProvider));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Live : reflète les changements (ex. après restore/upgrade) ; fallback = snapshot d'ouverture.
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
      // Scrollable so the card never clips/overflows on short screens (e.g.
      // iPhone SE) once the App Store legal footer is appended under the
      // upgrade CTA — visually identical on tall screens where it already fits.
      child: SingleChildScrollView(child: Container(
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
            // Lot 2 — Upgrade Weekly → Annual. Priorité : si sync différé, la carte « Refresh
            // plan » remplace le CTA ; sinon le CTA n'est rendu que si le package Annual existe.
            if (_deferredSync) ...[
              _deferredCard(context, l10n),
              const SizedBox(height: AppSpacing.sm),
            ] else if (shouldRenderUpgrade(view, annualAvailable: _annualAvailable)) ...[
              _upgradeCard(context, l10n),
              const SizedBox(height: AppSpacing.sm),
            ],
            // Manage Subscription — rendu UNIQUEMENT si RevenueCat fournit une managementURL
            // (masqué proprement sinon : promo, sandbox, non configuré).
            if (view.showManage && _mgmtUrl != null && _mgmtUrl!.isNotEmpty) ...[
              AppButton(
                label: l10n.pcManageSubscription,
                variant: AppButtonVariant.primary,
                onPressed: _openManage,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
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
      )),
    );
  }

  /// Carte « UPGRADE YOUR PLAN » (Annual Premium · 300 Spaces · Best value + CTA).
  Widget _upgradeCard(BuildContext context, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.pcUpgradeTitle.toUpperCase(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.accent,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.pcAnnualPremium,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            '${l10n.pcUpgradeSpaces} · ${l10n.pcUpgradeBestValue}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: l10n.pcUpgradeCta,
            variant: AppButtonVariant.primary,
            loading: _upgrading, // spinner + CTA désactivé pendant l'achat/sync
            onPressed: _upgrade,
          ),
          // App Store compliance (Apple 3.1.2) — the Weekly→Annual upgrade is a
          // purchase, so the legal links + auto-renew disclosure sit right under
          // its CTA. Same shared widget as the paywall (themed palette).
          const SizedBox(height: AppSpacing.sm),
          const LegalComplianceFooter(
            disclosureColor: AppColors.textSecondary,
            linkColor: AppColors.accent,
            underlineColor: AppColors.accent,
          ),
        ],
      ),
    );
  }

  /// Carte « sync différé » : achat réussi mais backend pas encore à jour → Refresh plan
  /// (relance sync+refresh seulement, jamais un nouvel achat).
  Widget _deferredCard(BuildContext context, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.pcUpgradeDeferred,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: l10n.pcUpgradeRefreshPlan,
            variant: AppButtonVariant.primary,
            loading: _upgrading,
            onPressed: _refreshPlan,
          ),
        ],
      ),
    );
  }

  String _passSubtitle(BuildContext context, MeStatus s) {
    final l10n = context.l10n;
    final bool noSpaces = s.availableCredits <= 0;
    final String? renews = _formatDate(context, s.passRenewsAt ?? s.passExpiresAt);
    // Épuisé SANS date connue → message autonome (jamais un « No Spaces remaining » orphelin).
    if (noSpaces && renews == null) return l10n.pcPassActiveNoSpacesNoDate;
    final String spaces = noSpaces
        ? l10n.pcPassNoSpaces // clé DÉDIÉE Premium Center (pas stPassNoSpaces, partagée/Profil)
        : l10n.stPassCreditsRemaining(s.availableCredits);
    return renews == null ? spaces : '$spaces · ${l10n.stPassRenews(renews)}';
  }
}
