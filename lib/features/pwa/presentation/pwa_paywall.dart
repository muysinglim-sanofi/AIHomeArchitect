/// The paywall. Renders a BILLING STATE — never a counter.
///
/// Every branch below comes from [PwaEntitlement], which is parsed from what the
/// server said. There is no `if (generationsUsed >= 1)` anywhere in this file,
/// and there cannot be: the browser is not told what a free generation costs,
/// and a second tab, a refund, a granted pass or a shared account would each
/// make a local count wrong in a different way.
///
/// The seven states it can be in are all real, including the two that are easy
/// to skip: we have not asked yet, and we asked and could not find out. Neither
/// shows a purchase.
///
/// Honesty about payment
/// ---------------------
/// Whether a purchase can be completed is a SERVER fact, read from
/// `payment.configured` on the entitlement, and this file renders whichever
/// answer it gets:
///
///   configured    the web-sellable products carry a Buy button that opens the
///                 KHQR payment sheet. The two subscription passes still do
///                 not: they carry app-store product ids, so they are marked
///                 mobile-only rather than presented as web merchandise (§10).
///   not           the "payments are not open yet" notice, and NO Buy button
///                 anywhere — an offer that cannot complete is worse than none.
///
/// The client never assumes either way. A browser build that believed ABA was
/// live while the backend had no merchant configuration would show a button
/// that dead-ends, and the whole point of putting the answer on the server is
/// that wiring a rail is a deployment, not a release.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/pwa_auth_controller.dart';
import '../auth/pwa_auth_service.dart';
import '../billing/pwa_entitlement.dart';
import '../billing/pwa_entitlement_controller.dart';
import '../l10n/pwa_l10n.dart';
import 'pwa_account_sheet.dart';
import 'pwa_payment_sheet.dart';
import 'pwa_theme.dart';
import 'pwa_widgets.dart' show pwaSerif;

/// Show the paywall for the state the BILLING ENGINE named.
///
/// [refusal] is the `billing_state` a 402 carried, when the paywall was opened
/// by a refusal rather than by a tap. It is applied to the entitlement before
/// the sheet builds, so the first frame already shows the right state.
Future<void> showPwaPaywall(
  BuildContext context,
  WidgetRef ref, {
  String refusal = '',
}) {
  if (refusal.isNotEmpty) {
    ref.read(pwaEntitlementProvider.notifier).applyRefusal(refusal);
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: pwaSurface,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const PwaPaywallSheet(),
  );
}

class PwaPaywallSheet extends ConsumerWidget {
  const PwaPaywallSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.pwaL10n;
    final e = ref.watch(pwaEntitlementProvider);
    final auth = ref.watch(pwaAuthProvider);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.92;

    final (title, body) = switch (e.state) {
      PwaBillingState.loading => (l.paywallTitle, l.paywallLoading),
      PwaBillingState.billingError => (l.paywallErrorTitle, l.paywallErrorBody),
      PwaBillingState.passActive => (l.paywallActiveTitle, l.paywallActiveBody),
      PwaBillingState.entitled => (l.paywallActiveTitle, l.paywallActiveBody),
      PwaBillingState.freeAvailable => (l.paywallTitle, l.freeVisionAvailable),
      PwaBillingState.passExhausted => (
          l.paywallPassExhaustedTitle,
          l.paywallPassExhaustedBody
        ),
      PwaBillingState.passRequired => (
          l.paywallPassRequiredTitle,
          l.paywallPassRequiredBody
        ),
      PwaBillingState.freeExhausted => (
          l.paywallFreeUsedTitle,
          l.paywallFreeUsedBody
        ),
    };

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: pwaHairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: PwaGap.lg),
                Text(title,
                    style: pwaSerif(fontSize: 26, fontWeight: FontWeight.w500)),
                const SizedBox(height: PwaGap.sm),
                Text(body,
                    style:
                        pwaSans(fontSize: 14, color: pwaMuted, height: 1.55)),

                if (e.state == PwaBillingState.loading) ...[
                  const SizedBox(height: PwaGap.xl),
                  const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: pwaGold),
                    ),
                  ),
                  const SizedBox(height: PwaGap.xl),
                ] else ...[
                  // A pass with spaces left is shown as a fact, not a pitch.
                  if (e.hasActivePass && e.passCredits > 0) ...[
                    const SizedBox(height: PwaGap.md),
                    _Badge(l.paywallSpaces(e.passCredits)),
                  ],

                  if (e.requiresPurchase) ...[
                    const SizedBox(height: PwaGap.lg),
                    _PaymentNotice(entitlement: e),
                    const SizedBox(height: PwaGap.md),
                    for (final p in e.productsForDisplay)
                      _ProductRow(
                        product: p,
                        // Buyable only when the SERVER says a rail is open AND
                        // the catalogue says this row belongs to the web.
                        purchasable: e.paymentConfigured && p.webEnabled,
                        onBuy: () async {
                          final granted =
                              await showPwaPaymentSheet(context, ref, p);
                          // A completed purchase closes the paywall behind the
                          // sheet: leaving someone on a purchase screen for
                          // something they have just bought reads as a bug.
                          if (granted && context.mounted) {
                            Navigator.of(context).maybePop();
                          }
                        },
                      ),
                    const SizedBox(height: PwaGap.md),
                    Text(l.paywallSecureNote,
                        style: pwaSans(fontSize: 12, color: pwaFaint)),
                  ],

                  const SizedBox(height: PwaGap.lg),

                  // §8: identity is offered HERE, at the moment it means
                  // something — not as a gate on Home or Create.
                  if (auth.stage != PwaAuthStage.identified)
                    _SecondaryButton(
                      label: l.accountTitle,
                      onPressed: () async {
                        final ok = await showPwaAccountSheet(context);
                        if (ok) {
                          // A different user has different entitlement. Re-read
                          // rather than assume the purchase followed them.
                          await ref
                              .read(pwaEntitlementProvider.notifier)
                              .onIdentityChanged();
                        }
                      },
                    )
                  else
                    _SecondaryButton(
                      label: l.paywallRestore,
                      onPressed: () => ref
                          .read(pwaEntitlementProvider.notifier)
                          .refresh(),
                    ),

                  const SizedBox(height: PwaGap.xs),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: Text(l.paywallClose,
                          style: pwaSans(fontSize: 13, color: pwaMuted)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Says plainly that no purchase can be completed here yet.
///
/// Shown whenever the provider is unconfigured, which is every deployment
/// today. It is the FIRST thing under the headline for a reason: a person who
/// cannot buy should learn that before they read prices.
class _PaymentNotice extends StatelessWidget {
  const _PaymentNotice({required this.entitlement});

  final PwaEntitlement entitlement;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    if (entitlement.paymentConfigured) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: pwaIvory,
        borderRadius: BorderRadius.circular(PwaGap.radius),
        border: Border.all(color: pwaHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.paywallUnavailableTitle,
              style: pwaSans(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(l.paywallUnavailableBody,
              style: pwaSans(fontSize: 13, color: pwaMuted, height: 1.5)),
        ],
      ),
    );
  }
}

/// One catalogue row, with a Buy button only when there is genuinely something
/// to press it for.
class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    this.purchasable = false,
    this.onBuy,
  });

  final PwaProduct product;

  /// True when this deployment can complete a purchase of THIS row.
  final bool purchasable;
  final Future<void> Function()? onBuy;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    return Container(
      margin: const EdgeInsets.only(bottom: PwaGap.sm),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PwaGap.radius),
        border: Border.all(color: pwaHairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The marketing label, translated from a machine code. Absent
                // for the app-store rows, which carry no badge.
                if (product.badge.isNotEmpty) ...[
                  _BadgeChip(label: l.productBadge(product.badge),
                      highlight: product.isDiscounted),
                  const SizedBox(height: 6),
                ],
                Text(l.paywallSpaces(product.credits),
                    style: pwaSans(fontSize: 15, fontWeight: FontWeight.w600)),
                if (product.durationDays != null) ...[
                  const SizedBox(height: 2),
                  Text(l.paywallDays(product.durationDays!),
                      style: pwaSans(fontSize: 12, color: pwaFaint)),
                ],
                // The catalogue row exists to be sold in an app store. Saying so
                // beats implying a web checkout that will never appear.
                if (product.storeOnly) ...[
                  const SizedBox(height: 4),
                  Text(l.paywallStoreOnly,
                      style: pwaSans(fontSize: 12, color: pwaMuted)),
                ],
              ],
            ),
          ),
          const SizedBox(width: PwaGap.md),
          if (product.priceLabel.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // The crossed-out reference price. Rendered ABOVE the real one
                // and struck through, so the number a person acts on is the
                // one they will actually be charged. It comes from a separate
                // field precisely so it can never be mistaken for the price.
                if (product.isDiscounted) ...[
                  Text(product.listPriceLabel,
                      style: pwaSans(
                        fontSize: 12,
                        color: pwaFaint,
                      ).copyWith(decoration: TextDecoration.lineThrough)),
                  const SizedBox(height: 1),
                ],
                Text(product.priceLabel,
                    style: pwaSans(fontSize: 16, fontWeight: FontWeight.w600)),
                if (product.isDiscounted) ...[
                  const SizedBox(height: 2),
                  Text(l.paywallDiscount(product.discountPercent),
                      style: pwaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: pwaGold)),
                ],
              ],
            ),
          if (purchasable && onBuy != null) ...[
            const SizedBox(width: PwaGap.sm),
            FilledButton(
              onPressed: onBuy,
              style: FilledButton.styleFrom(
                backgroundColor: pwaInk,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(PwaGap.radius),
                ),
              ),
              child: Text(l.payBuy,
                  style: pwaSans(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
    );
  }
}

/// The marketing label on a product row — a translated word, never a code.
class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.label, this.highlight = false});

  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: highlight ? pwaGoldSoft : pwaIvory,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: highlight ? pwaGold : pwaHairline),
      ),
      child: Text(label,
          style: pwaSans(
              fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: pwaGoldSoft.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label,
              style: pwaSans(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      );
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: pwaInk,
          side: const BorderSide(color: pwaInk),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PwaGap.radius),
          ),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: pwaSans(fontSize: 15, fontWeight: FontWeight.w600)),
      );
}
