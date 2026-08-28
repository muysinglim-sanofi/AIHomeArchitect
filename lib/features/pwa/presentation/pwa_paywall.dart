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
import 'pwa_primitives.dart';
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

class PwaPaywallSheet extends ConsumerStatefulWidget {
  const PwaPaywallSheet({super.key});

  @override
  ConsumerState<PwaPaywallSheet> createState() => _PwaPaywallSheetState();
}

class _PwaPaywallSheetState extends ConsumerState<PwaPaywallSheet> {
  /// The pack the person is about to buy. A SKU, never an amount: the price
  /// this screen shows is the catalogue's, and the price PayWay charges is
  /// resolved by the server from this sku alone.
  String? _sku;

  /// The pack a first look should land on. `popular` when the catalogue says
  /// so — the badge is a machine code from the products table, not a marketing
  /// word this file invented — otherwise the first row.
  PwaProduct? _defaultPack(List<PwaProduct> packs) {
    if (packs.isEmpty) return null;
    for (final p in packs) {
      if (p.badge == 'popular') return p;
    }
    return packs.first;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    final e = ref.watch(pwaEntitlementProvider);
    final auth = ref.watch(pwaAuthProvider);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.92;

    // ONLY what this platform can actually sell. The app-store passes are real
    // products in their own ecosystem and are not merchandise here: the row
    // that says "available in the mobile app" is an advertisement for a shop
    // the reader is not standing in. `webEnabled` is the SERVER's word for it
    // (`khqr_enabled AND NOT store_only`), so nothing here filters by sku.
    final packs = e.purchasableOnWeb;
    final selected = packs.isEmpty
        ? null
        : (packs.where((p) => p.sku == _sku).firstOrNull ?? _defaultPack(packs));

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
                  // A balance is shown as a fact, not a pitch — and it is the
                  // SAME number Profile shows. `creditsAvailable` is the
                  // server's `credits_available`, free bucket plus pass bucket;
                  // this used to render `passCredits` alone, so a person with
                  // both read one figure here and a larger one on Profile for
                  // the same account, from the same object.
                  if (e.hasActivePass && e.creditsAvailable > 0) ...[
                    const SizedBox(height: PwaGap.md),
                    _Badge(l.paywallSpaces(e.creditsAvailable)),
                  ],

                  if (e.requiresPurchase) ...[
                    const SizedBox(height: PwaGap.lg),
                    _PaymentNotice(entitlement: e),
                    if (packs.isNotEmpty) ...[
                      const SizedBox(height: PwaGap.md),
                      for (final p in packs)
                        _PackCard(
                          key: ValueKey('pwa-pack-${p.sku}'),
                          product: p,
                          selected: p.sku == selected?.sku,
                          // Choosing is free. Nothing is ordered, nothing is
                          // charged, and no request leaves the page until the
                          // one CTA below is pressed.
                          onTap: () => setState(() => _sku = p.sku),
                        ),
                      const SizedBox(height: PwaGap.md),
                      // ONE call to action, for the pack that is selected. The
                      // old screen put a Buy button on every row, which asked a
                      // person to compare three prices and three buttons at
                      // once; and its label was painted ink-on-ink, so all
                      // three read as empty black rectangles.
                      PwaPrimaryButton(
                        key: const ValueKey('pwa-paywall-continue'),
                        label: selected == null
                            ? l.payBuy
                            : '${l.payBuy} · ${selected.priceLabel}',
                        onPressed: (!e.paymentConfigured || selected == null)
                            ? null
                            : () async {
                                final granted = await showPwaPaymentSheet(
                                    context, ref, selected);
                                // A completed purchase closes the paywall
                                // behind the sheet: leaving someone on a
                                // purchase screen for something they have just
                                // bought reads as a bug.
                                if (granted && context.mounted) {
                                  Navigator.of(context).maybePop();
                                }
                              },
                      ),
                      const SizedBox(height: PwaGap.md),
                      Text(l.paywallSecureNote,
                          style: pwaSans(fontSize: 12, color: pwaFaint)),
                    ],
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

/// One pack, as a thing you can choose.
///
/// The old row was a read-only line with its own Buy button. This is a card:
/// the whole surface is the tap target, the selected one is stated in gold and
/// with a tick, and the price ladder reads top to bottom — badge, what you get,
/// what it costs, and (only when the catalogue says so) what it would otherwise
/// have cost.
///
/// The struck price and the percentage are DISPLAY, and they are kept visibly
/// subordinate to the payable one for that reason: `list_price_usd` lives in
/// `products.metadata`, the amount PayWay charges is resolved server-side from
/// `price_usd`, and this widget is not in that path.
class _PackCard extends StatelessWidget {
  const _PackCard({
    super.key,
    required this.product,
    required this.selected,
    required this.onTap,
  });

  final PwaProduct product;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: PwaGap.sm),
      child: Material(
        color: selected ? pwaGoldSoft.withValues(alpha: 0.35) : pwaSurface,
        borderRadius: BorderRadius.circular(PwaGap.radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PwaGap.radius),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PwaGap.radius),
              border: Border.all(
                color: selected ? pwaGold : pwaHairline,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                _SelectionDot(selected: selected),
                const SizedBox(width: PwaGap.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The marketing label, translated from a machine code.
                      if (product.badge.isNotEmpty) ...[
                        _BadgeChip(
                          label: l.productBadge(product.badge),
                          highlight: product.isDiscounted,
                        ),
                        const SizedBox(height: 6),
                      ],
                      Text(l.paywallSpaces(product.credits),
                          style: pwaSans(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      if (product.durationDays != null) ...[
                        const SizedBox(height: 2),
                        Text(l.paywallDays(product.durationDays!),
                            style: pwaSans(fontSize: 12, color: pwaFaint)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: PwaGap.md),
                if (product.priceLabel.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Above the real one and struck through, so the number a
                      // person acts on is the one they will be charged.
                      if (product.isDiscounted) ...[
                        Text(product.listPriceLabel,
                            style: pwaSans(fontSize: 12, color: pwaFaint)
                                .copyWith(
                                    decoration: TextDecoration.lineThrough)),
                        const SizedBox(height: 1),
                      ],
                      Text(product.priceLabel,
                          style: pwaSans(
                              fontSize: 18, fontWeight: FontWeight.w700)),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The selection mark — a gold ring, filled with a tick when chosen. Shape as
/// well as colour, so the choice survives a screenshot in greyscale and a
/// reader who does not see the gold.
class _SelectionDot extends StatelessWidget {
  const _SelectionDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? pwaGold : Colors.transparent,
          border: Border.all(
            color: selected ? pwaGold : pwaHairline,
            width: 1.5,
          ),
        ),
        child: selected
            ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
            : null,
      );
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
