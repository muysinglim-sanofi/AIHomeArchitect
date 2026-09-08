/// The RESULT of a payment — Ayden's card, shown after ABA's checkout.
///
/// ABA owns the checkout; Ayden owns the result. This card is what a person
/// sees once the server has a verdict, and only then:
///
///   * SUCCESS — behind `PwaPaymentState.granted`, which the server writes
///     after PayWay's Check Transaction said APPROVED and the Billing Engine
///     granted exactly once. Never before.
///   * FAILURE — behind the terminal `failed`, `cancelled` and `expired`
///     states. Never while PayWay may still legitimately say PENDING.
///
/// The figures on it are the server's. What was bought and for how much come
/// from the payment row itself; the new balance is READ from the entitlement
/// after it has been refreshed — never added up here from the pack that was
/// selected, which would be wrong the moment anything else touched the ledger.
///
/// No payment-provider branding of any kind: no ABA KHQR, no ABA PayWay. And
/// one action per card — `Continue` after a success, `Try again` after a
/// failure — because a verdict is not a place to browse.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../billing/pwa_entitlement_controller.dart';
import '../billing/pwa_payment.dart';
import '../l10n/pwa_l10n.dart';
import 'pwa_theme.dart';
import 'pwa_widgets.dart' show pwaSerif;

/// Colours of the result card — the Wallet's own near-black and gold, so the
/// card reads as the end of the same journey and not as a system dialog.
const Color kPwaResultSurface = Color(0xFF0E0C09);
const Color kPwaResultPanel = Color(0xFF15110D);
const Color kPwaResultLine = Color(0xFF2A241D);
const Color kPwaResultText = Color(0xFFF3ECE0);
const Color kPwaResultMuted = Color(0xFFC8B99B);
const Color kPwaResultDim = Color(0xFF8C857B);
const Color kPwaResultGold = Color(0xFFD6B25E);
const Color kPwaResultGoldLight = Color(0xFFE7CB82);
const Color kPwaResultRed = Color(0xFFE0574A);
const Color kPwaResultInk = Color(0xFF120E08);

/// Which card a terminal state gets.
enum PwaPaymentResultKind { success, failure }

/// The card for [state], or null when there is no verdict yet.
///
/// Only TERMINAL states map to a card. `awaitingPayment`, the two confirming
/// states, `unreachable` and `unavailable` are not verdicts: PayWay may still
/// say PENDING, and a failure shown then would be a lie the next poll retracts.
PwaPaymentResultKind? pwaPaymentResultKindFor(PwaPaymentState state) =>
    switch (state) {
      PwaPaymentState.granted => PwaPaymentResultKind.success,
      PwaPaymentState.failed ||
      PwaPaymentState.cancelled ||
      PwaPaymentState.expired =>
        PwaPaymentResultKind.failure,
      _ => null,
    };

/// Money is moving and the server is settling it: the surface is already
/// Ayden's near-black, so the verdict that follows does not flip the card.
bool pwaPaymentIsConfirming(PwaPaymentState state) =>
    state == PwaPaymentState.paidPendingVerification ||
    state == PwaPaymentState.verified;

/// The edge the modal frame wears for [kind]: a warm gold line for a success,
/// a red one for a failure. Subtle — a tint at the border, not a frame.
Color pwaPaymentResultBorder(PwaPaymentResultKind kind) => switch (kind) {
      PwaPaymentResultKind.success => kPwaResultGold.withValues(alpha: 0.45),
      PwaPaymentResultKind.failure => kPwaResultRed.withValues(alpha: 0.55),
    };

/// Ayden's verdict card. Renders nothing for a state that is not a verdict.
class PwaPaymentResultCard extends ConsumerStatefulWidget {
  const PwaPaymentResultCard({
    super.key,
    required this.payment,
    required this.onContinue,
    required this.onRetry,
  });

  final PwaPayment payment;
  final VoidCallback onContinue;
  final VoidCallback onRetry;

  @override
  ConsumerState<PwaPaymentResultCard> createState() =>
      _PwaPaymentResultCardState();
}

class _PwaPaymentResultCardState extends ConsumerState<PwaPaymentResultCard> {
  /// True once the entitlement has been re-read AFTER this card appeared —
  /// that is, after the grant. Until then the balance row shows a dash: the
  /// only number available would be the OLD balance, and a stale figure next
  /// to the words "New balance" is worse than none.
  bool _balanceFresh = false;

  @override
  void initState() {
    super.initState();
    if (pwaPaymentResultKindFor(widget.payment.state) ==
        PwaPaymentResultKind.success) {
      // Ask the Billing Engine what the account now holds. Concurrent
      // refreshes collapse, so this rides the one the controller already
      // triggered on GRANTED when that is still in flight.
      ref.read(pwaEntitlementProvider.notifier).refresh().then((_) {
        if (mounted) setState(() => _balanceFresh = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = pwaPaymentResultKindFor(widget.payment.state);
    if (kind == null) return const SizedBox.shrink();
    final l = context.pwaL10n;
    final success = kind == PwaPaymentResultKind.success;

    return Padding(
      key: ValueKey(
          success ? 'pwa-pay-result-success' : 'pwa-pay-result-failure'),
      padding: const EdgeInsets.fromLTRB(22, 30, 22, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Badge(kind: kind),
          const SizedBox(height: 18),
          Text(
            success ? l.payResultSuccessTitle : l.payResultFailedTitle,
            textAlign: TextAlign.center,
            style: pwaSerif(
                fontSize: 24, fontWeight: FontWeight.w500, color: kPwaResultText),
          ),
          const SizedBox(height: 8),
          Text(
            success
                ? l.payResultSuccessBody(widget.payment.credits)
                : l.payResultFailedBody,
            textAlign: TextAlign.center,
            style: pwaSans(fontSize: 14, color: kPwaResultMuted, height: 1.45),
          ),
          if (success) ...[
            const SizedBox(height: 24),
            _Summary(payment: widget.payment, balanceFresh: _balanceFresh),
            const SizedBox(height: 24),
            _GoldButton(
              key: const ValueKey('pwa-pay-result-continue'),
              label: l.payResultContinue,
              onPressed: widget.onContinue,
            ),
          ] else ...[
            const SizedBox(height: 14),
            Text(
              l.payResultFailedHint,
              textAlign: TextAlign.center,
              style: pwaSans(fontSize: 13, color: kPwaResultDim, height: 1.55),
            ),
            const SizedBox(height: 24),
            _OutlinedButton(
              key: const ValueKey('pwa-pay-result-retry'),
              label: l.payRetry,
              onPressed: widget.onRetry,
            ),
          ],
        ],
      ),
    );
  }
}

/// The outlined verdict glyph: a gold check, or a red cross.
class _Badge extends StatelessWidget {
  const _Badge({required this.kind});

  final PwaPaymentResultKind kind;

  @override
  Widget build(BuildContext context) {
    final success = kind == PwaPaymentResultKind.success;
    final tone = success ? kPwaResultGold : kPwaResultRed;
    return Center(
      child: Container(
        key: ValueKey(success
            ? 'pwa-pay-result-icon-success'
            : 'pwa-pay-result-icon-failure'),
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tone.withValues(alpha: 0.08),
          border: Border.all(color: tone, width: 1.6),
        ),
        child: Icon(
          success ? Icons.check_rounded : Icons.close_rounded,
          size: 30,
          color: tone,
        ),
      ),
    );
  }
}

/// "Purchase summary": what was bought, for how much, and what the account
/// now holds. Two rows, all three figures the server's.
class _Summary extends ConsumerWidget {
  const _Summary({required this.payment, required this.balanceFresh});

  final PwaPayment payment;
  final bool balanceFresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.pwaL10n;
    final e = ref.watch(pwaEntitlementProvider);
    final balance = balanceFresh && e.isKnown
        ? l.paywallSpaces(e.creditsAvailable)
        : '—';
    return Container(
      key: const ValueKey('pwa-pay-result-summary'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: kPwaResultPanel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kPwaResultLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.payResultSummaryTitle,
            style: pwaSans(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: kPwaResultDim,
                letterSpacing: 0.4),
          ),
          const SizedBox(height: 10),
          _SummaryRow(
            label: l.paywallSpaces(payment.credits),
            labelKey: const ValueKey('pwa-pay-result-pack'),
            value: payment.amountLabel,
            valueKey: const ValueKey('pwa-pay-result-amount'),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, thickness: 1, color: kPwaResultLine),
          ),
          _SummaryRow(
            label: l.payResultNewBalance,
            labelKey: const ValueKey('pwa-pay-result-balance-label'),
            value: balance,
            valueKey: const ValueKey('pwa-pay-result-balance'),
            emphasis: true,
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.labelKey,
    required this.value,
    required this.valueKey,
    this.emphasis = false,
  });

  final String label;
  final Key labelKey;
  final String value;
  final Key valueKey;
  final bool emphasis;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The label yields (and wraps) first; the figure is never clipped.
          Expanded(
            child: Text(label,
                key: labelKey,
                style: pwaSans(fontSize: 14, color: kPwaResultMuted)),
          ),
          const SizedBox(width: 12),
          Text(value,
              key: valueKey,
              textAlign: TextAlign.right,
              style: pwaSans(
                  fontSize: emphasis ? 15 : 14,
                  fontWeight: emphasis ? FontWeight.w700 : FontWeight.w600,
                  color: emphasis ? kPwaResultGoldLight : kPwaResultText)),
        ],
      );
}

/// The Wallet's gold pill, without the icons: one word, centred.
class _GoldButton extends StatelessWidget {
  const _GoldButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kPwaResultGoldLight, kPwaResultGold],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kPwaResultGoldLight.withValues(alpha: 0.55)),
          boxShadow: [
            BoxShadow(
              color: kPwaResultGold.withValues(alpha: 0.22),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: pwaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: kPwaResultInk,
                    letterSpacing: 0.2),
              ),
            ),
          ),
        ),
      );
}

/// The recovery action: ivory outline on the dark card, quieter than gold
/// because nothing has been won yet.
class _OutlinedButton extends StatelessWidget {
  const _OutlinedButton(
      {super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kPwaResultText.withValues(alpha: 0.35)),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: pwaSans(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: kPwaResultText,
                    letterSpacing: 0.2),
              ),
            ),
          ),
        ),
      );
}
