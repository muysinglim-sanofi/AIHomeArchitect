/// Wave 5.17d — Paywall sheet (real RevenueCat purchase flow).
///
/// Surfaced on backend HTTP 402 (QUOTA_EXHAUSTED or FREE_TIER_RESTRICTED)
/// and on tap of any locked room/atmosphere card on the upload screen.
/// The sheet's job is to convert : Subscribe (Weekly Premium) or
/// Restore a prior purchase.
///
/// Pricing (Wave 5.17d alignment — supersedes earlier D2)
///   Weekly Premium  — price set in the RevenueCat dashboard
/// The displayed price comes from RevenueCat offerings at runtime ; RC
/// is the single source of truth. The placeholder card renders only in
/// degraded mode (RC not configured) ; in production the real package
/// price is shown via `_OfferCard`. The earlier D2 Monthly + Annual
/// decision is OBSOLETE.
///
/// Offerings shape (V1 target)
///   One weekly package per offering. `_selectWeeklyPackage` picks the
///   `PackageType.weekly` package ; if multiple packages exist, weekly
///   wins ; if no weekly is present, the first package is used as a
///   graceful fallback so the sheet doesn't go blank on a misconfigured
///   dashboard. V2 may introduce additional tiers — extend the selector
///   then, not before.
///
/// Subhead variants
///   QUOTA_EXHAUSTED        → "Your free architectural explorations are complete."
///   FREE_TIER_RESTRICTED   → "Premium unlocks every room and atmosphere."
///                            (and a hint based on `restrictedField`)
///
/// Sign-in routing (Wave 5.17c.1 reversal — Wave 5.17d Decision)
///   The sheet does NOT open SignInScreen. Sign-in is hidden in V1
///   (FeatureFlags.signInEnabled=false). Restore Purchases handles the
///   "I bought premium on another device" case without a sign-in flow,
///   via Apple/Google store account binding (Decision D8).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../data/services/revenuecat_service.dart';
import '../../shared/widgets/app_button.dart';

class PaywallSheet extends StatefulWidget {
  /// Discriminator for the subhead copy. 'quota' → "free explorations
  /// complete" ; 'free_tier' → "Premium unlocks every room/atmosphere".
  final PaywallTrigger trigger;
  /// When trigger == PaywallTrigger.freeTier, the specific field that
  /// was restricted ('room', 'atmosphere', 'delegated_choice', '').
  final String restrictedField;

  const PaywallSheet({
    super.key,
    this.trigger = PaywallTrigger.quota,
    this.restrictedField = '',
  });

  @override
  State<PaywallSheet> createState() => _PaywallSheetState();
}

enum PaywallTrigger {
  quota,    // QUOTA_EXHAUSTED — used all 2 free gens
  freeTier, // FREE_TIER_RESTRICTED — out-of-scope choice
  locked,   // user tapped a locked card directly
}

class _PaywallSheetState extends State<PaywallSheet> {
  Offering? _offering;
  bool _loading = true;
  bool _busy = false;       // true while a purchase / restore is in-flight
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    final offerings = await RevenuecatService.instance.loadOfferings();
    if (!mounted) return;
    setState(() {
      _offering = offerings?.current;
      _loading = false;
    });
  }

  Future<void> _onSubscribePressed(Package pkg) async {
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final activated = await RevenuecatService.instance.purchasePackage(pkg);
      if (!mounted) return;
      if (activated) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _busy = false;
          _errorMessage = 'Purchase did not complete. Please try again.';
        });
      }
    } on RevenuecatNotConfiguredException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = 'Purchases are not available in this test build yet.';
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
        // User cancelled — silent.
        setState(() => _busy = false);
        return;
      }
      setState(() {
        _busy = false;
        _errorMessage = e.message ?? 'Purchase failed.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = 'Purchase failed. Please try again.';
      });
    }
  }

  Future<void> _onRestorePressed() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final restored = await RevenuecatService.instance.restorePurchases();
      if (!mounted) return;
      if (restored) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _busy = false;
          _errorMessage = 'No prior purchases found on this device.';
        });
      }
    } on RevenuecatNotConfiguredException {
      // Degraded mode — RC SDK not configured. Show the canonical clean
      // message instead of the native "Singleton not initialised"
      // stacktrace bubbling up unwrapped.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = 'Purchases are not available in this test build yet.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = 'Restore failed. Please try again.';
      });
    }
  }

  // ── Copy helpers ─────────────────────────────────────────────────────

  String get _headline {
    switch (widget.trigger) {
      case PaywallTrigger.quota:
        return 'Your free architectural explorations are complete.';
      case PaywallTrigger.freeTier:
      case PaywallTrigger.locked:
        return 'Premium unlocks every room and atmosphere.';
    }
  }

  String get _subhead {
    switch (widget.trigger) {
      case PaywallTrigger.quota:
        return 'Unlock unlimited redesigns and continue working with '
            'your AI Architect.';
      case PaywallTrigger.locked:
        return 'Subscribe to transform any room with any of the seven '
            'atmospheres — and let your AI Architect guide every step.';
      case PaywallTrigger.freeTier:
        switch (widget.restrictedField) {
          case 'room':
            return 'The free tier transforms Living Rooms only. '
                'Subscribe to unlock every room.';
          case 'atmosphere':
            return 'The free tier offers Nordic Warmth and Soft Luxury. '
                'Subscribe to unlock every atmosphere.';
          case 'delegated_choice':
            return 'Let AI Decide and Surprise Me are part of premium. '
                'Subscribe to let your AI Architect drive every choice.';
          default:
            return 'Subscribe to unlock the full studio.';
        }
    }
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            Text(
              _headline,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _subhead,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),

            // ── Offerings ────────────────────────────────────────────────
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              _OfferingsBlock(
                offering: _offering,
                busy: _busy,
                onPurchase: _onSubscribePressed,
              ),

            if (_errorMessage != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _errorMessage!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.error,
                    ),
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: AppSpacing.md),

            // ── Restore Purchases (Decision D7 — paywall only) ──────────
            TextButton(
              onPressed: _busy ? null : _onRestorePressed,
              child: const Text('Restore Purchases'),
            ),

            // ── Dismiss ─────────────────────────────────────────────────
            AppButton(
              label: 'Maybe later',
              variant: AppButtonVariant.ghost,
              fullWidth: true,
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

// ── Offerings block ─────────────────────────────────────────────────────────

class _OfferingsBlock extends StatelessWidget {
  final Offering? offering;
  final bool busy;
  final Future<void> Function(Package) onPurchase;

  const _OfferingsBlock({
    required this.offering,
    required this.busy,
    required this.onPurchase,
  });

  /// V1 target : one weekly package. Picks `PackageType.weekly` when
  /// present ; otherwise falls back to the first available package so
  /// the sheet stays functional if the RC dashboard is mis-typed (e.g.
  /// a monthly product mis-tagged as weekly). Returns null when the
  /// offering has zero packages — caller renders the degraded
  /// placeholder.
  Package? _selectWeeklyPackage(Offering off) {
    if (off.availablePackages.isEmpty) return null;
    for (final p in off.availablePackages) {
      if (p.packageType == PackageType.weekly) return p;
    }
    return off.availablePackages.first;
  }

  @override
  Widget build(BuildContext context) {
    final weekly = offering == null ? null : _selectWeeklyPackage(offering!);

    if (weekly == null) {
      // Degraded mode — RC offerings unavailable OR empty. Render a
      // placeholder plan card so the paywall still reads as a purchase
      // surface (Subscribe is the intent ; Restore Purchases stays
      // secondary). The disabled Subscribe button signals the temporary
      // state without hiding the funnel structure. When Phase 4 wires
      // real offerings, this branch is dead and the real `_OfferCard`
      // renders below.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PlaceholderPlanCard(),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              'Subscriptions are temporarily unavailable in this build.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    // V1 — single weekly card (no "Best value" badge with only one
    // offer ; the highlighted accent border is sufficient).
    return _OfferCard(
      package: weekly,
      highlighted: true,
      enabled: !busy,
      onTap: () => onPurchase(weekly),
    );
  }
}

class _OfferCard extends StatelessWidget {
  final Package package;
  final bool highlighted;
  final bool enabled;
  final VoidCallback onTap;

  const _OfferCard({
    required this.package,
    required this.highlighted,
    required this.enabled,
    required this.onTap,
  });

  String get _title {
    switch (package.packageType) {
      case PackageType.weekly:
        return 'Weekly Premium';
      default:
        // Graceful fallback for a misconfigured RC dashboard where the
        // package isn't tagged as weekly. Renders the RC identifier so
        // the operator can spot the misconfiguration in the UI.
        return package.identifier;
    }
  }

  String get _price => package.storeProduct.priceString;

  String? get _sublabel {
    if (package.packageType == PackageType.weekly) {
      return 'billed weekly';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = highlighted ? AppColors.accent : AppColors.border;
    final borderWidth = highlighted ? 2.0 : 1.0;

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.55,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (_sublabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _sublabel!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textTertiary,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                _price,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Placeholder plan card (Wave 5.17d degraded paywall) ─────────────────────
//
// Shown when RC offerings are unavailable (graceful-degradation mode in dev,
// or RC dashboard config missing in early Phase 4). Mirrors the visual
// language of `_OfferCard` (accent border, large title) but the Subscribe
// action is DISABLED — the user can read the intended plan structure but
// cannot transact. Restore Purchases (the caller's secondary action)
// handles cross-device entitlement separately.
//
// V1 plan : Weekly Premium only. No "Best value" badge — that affordance
// requires a second offer to compare against. Price is shown as
// "Price available at launch" until RevenueCat is configured ; once Phase
// 4 wires real offerings, this branch is bypassed (`weekly != null`) and
// the live storefront price renders via `_OfferCard`.

class _PlaceholderPlanCard extends StatelessWidget {
  const _PlaceholderPlanCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(color: AppColors.accent, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Weekly Premium',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'billed weekly',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                    ),
                  ],
                ),
              ),
              Text(
                'Price available at launch',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: null, // disabled — temporarily unavailable
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.textPrimary,
                foregroundColor: AppColors.surface,
                disabledBackgroundColor: AppColors.border,
                disabledForegroundColor: AppColors.textTertiary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(
                'Subscribe — temporarily unavailable',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
