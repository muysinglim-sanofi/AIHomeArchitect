/// Wave 5.17d — Paywall sheet (real RevenueCat purchase flow).
///
/// Surfaced on backend HTTP 402 (QUOTA_EXHAUSTED or FREE_TIER_RESTRICTED)
/// and on tap of any locked room/atmosphere card on the upload screen.
/// The sheet's job is to convert : Subscribe (Monthly or Annual) or
/// Restore a prior purchase.
///
/// Pricing (Decision D2)
///   Monthly  $7.99
///   Annual   $49.99   (best-value badge — D2)
/// The actual amounts come from RevenueCat offerings at runtime ; the
/// constants above are the dashboard intent. If RC returns different
/// prices, the prices on the cards follow RC (single source of truth).
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
        _errorMessage = 'Purchase failed: $e';
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = 'Restore failed: $e';
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

  /// Annual is the "best value" — D2. RC exposes the annual package via
  /// `PackageType.annual` ; monthly via `PackageType.monthly`. Order
  /// is annual-first so the highlighted card lands above.
  ({Package? annual, Package? monthly}) _splitPackages(Offering off) {
    Package? annual;
    Package? monthly;
    for (final p in off.availablePackages) {
      if (p.packageType == PackageType.annual) annual ??= p;
      if (p.packageType == PackageType.monthly) monthly ??= p;
    }
    return (annual: annual, monthly: monthly);
  }

  @override
  Widget build(BuildContext context) {
    if (offering == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text(
          'Subscription temporarily unavailable. Please try again later '
          'or restore a prior purchase below.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
          textAlign: TextAlign.center,
        ),
      );
    }

    final split = _splitPackages(offering!);
    final annual = split.annual;
    final monthly = split.monthly;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (annual != null) ...[
          _OfferCard(
            package: annual,
            highlighted: true,
            badgeLabel: 'Best value',
            enabled: !busy,
            onTap: () => onPurchase(annual),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (monthly != null)
          _OfferCard(
            package: monthly,
            highlighted: false,
            enabled: !busy,
            onTap: () => onPurchase(monthly),
          ),
      ],
    );
  }
}

class _OfferCard extends StatelessWidget {
  final Package package;
  final bool highlighted;
  final String? badgeLabel;
  final bool enabled;
  final VoidCallback onTap;

  const _OfferCard({
    required this.package,
    required this.highlighted,
    required this.enabled,
    required this.onTap,
    this.badgeLabel,
  });

  String get _title {
    switch (package.packageType) {
      case PackageType.annual:
        return 'Annual';
      case PackageType.monthly:
        return 'Monthly';
      default:
        return package.identifier;
    }
  }

  String get _price => package.storeProduct.priceString;

  String? get _sublabel {
    if (package.packageType == PackageType.annual) {
      // Approximate per-month text for context. Uses the dashboard
      // pricing from D2 (USD 49.99 / 12 ≈ 4.17). The real value lives
      // on the StoreProduct ; for V1 we keep a static caption since
      // RC's per-period breakdown isn't always populated cross-store.
      return 'billed yearly';
    }
    if (package.packageType == PackageType.monthly) {
      return 'billed monthly';
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
                    Row(
                      children: [
                        Text(
                          _title,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        if (badgeLabel != null) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              badgeLabel!,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppColors.surface,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ],
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
