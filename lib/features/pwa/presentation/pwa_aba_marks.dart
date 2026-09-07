/// ABA and KHQR artwork, as supplied.
///
/// WHERE THESE LIVE AND WHY THEY ARE NOT FLUTTER ASSETS
/// ----------------------------------------------------
/// `web/aba/*.png`, fetched same-origin by relative URL rather than declared in
/// `pubspec.yaml`. That is deliberate: when ABA supplies replacement artwork it
/// can be dropped into `web/` and deployed without a rebuild, and without the
/// bank's marks being compiled into the bundle. Swapping the files swaps the
/// UI; no Dart changes, no redesign.
///
/// PROVENANCE
/// ----------
/// These two files were reviewed and explicitly authorised by the product owner
/// for the preprod ABA review. The provenance record is kept at
/// `docs/aba/REJECTED_AI_GENERATED/README.md` and should be read again before
/// any production use.
///
/// WHAT IS NOT HERE
/// ---------------
/// No Visa, no Mastercard, no Alipay, no WeChat, no ABA Pay. This deployment
/// offers exactly one payment method and says so with exactly one mark.
library;

import 'package:flutter/material.dart';

import '../l10n/pwa_l10n.dart';
import 'pwa_theme.dart';

/// The horizontal "We accept · ABA · KHQR" lockup. 2172x724, artwork filling
/// the canvas (measured opaque bounds 1994x617 — 3.23:1 of actual mark, so
/// there is no padding to reclaim and the rendered height drives the width).
const String kPwaAcceptMarkAsset = 'aba/we_accept_aba_khqr.png';

/// The compact square ABA/KHQR tile. 1254x1254.
const String kPwaAbaMethodMarkAsset = 'aba/aba_khqr_logo.png';

/// The acceptance lockup, as ONE image.
///
/// Not "We accept" text beside a pill: the supplied artwork already contains
/// the words and both marks, and splitting it would mean re-typesetting a third
/// party's lockup. [height] is the only knob — the width follows the artwork's
/// own proportions.
///
/// It renders nothing at all if the file is missing. An acceptance mark that
/// has become a broken-image glyph is worse than an absent one.
class PwaAcceptMark extends StatelessWidget {
  const PwaAcceptMark({super.key, this.height = 26});

  final double height;

  @override
  Widget build(BuildContext context) => Semantics(
    label: context.pwaL10n.acceptWeAccept,
    child: Image.network(
      kPwaAcceptMarkAsset,
      key: const ValueKey('pwa-accept-mark'),
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    ),
  );
}

/// The compact ABA KHQR tile for the Wallet's payment-method row.
class PwaAbaMethodMark extends StatelessWidget {
  const PwaAbaMethodMark({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) => Image.network(
    kPwaAbaMethodMarkAsset,
    key: const ValueKey('pwa-aba-method-mark'),
    width: size,
    height: size,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
    errorBuilder: (_, _, _) => SizedBox(width: size, height: size),
  );
}

/// Which ground a mark is sitting on.
///
/// Only the surrounding TYPE changes with the ground — the artwork is the
/// artwork, and is never recoloured.
enum PwaMarkTone {
  light,
  dark;

  Color get label =>
      this == PwaMarkTone.dark ? const Color(0xFFF3ECE0) : pwaInk;
  Color get quiet =>
      this == PwaMarkTone.dark ? const Color(0xFF8C857B) : pwaMuted;
  Color get line =>
      this == PwaMarkTone.dark ? const Color(0xFF2A241D) : pwaHairline;
}

/// The payment-method row above the Wallet's Buy button.
///
/// It answers the one question a Cambodian payer asks before tapping: what will
/// I pay with, and will my bank app work.
///
/// INFORMATIONAL. It is not a button and carries no affordance suggesting it
/// is: no chevron, no radio, no "Change". On the Wallet's dark sheet it is the
/// one white card, which is enough to read as the selected method.
class PwaAbaMethodRow extends StatelessWidget {
  const PwaAbaMethodRow({super.key, this.tone = PwaMarkTone.light});

  final PwaMarkTone tone;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    final onDark = tone == PwaMarkTone.dark;
    return Container(
      key: const ValueKey('pwa-aba-method-row'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        // On the Wallet's near-black sheet the row sits on white, exactly as
        // the approved flow shows it: the payment method is the one thing on
        // that screen that should read as a card rather than as more dark
        // chrome.
        color: onDark ? Colors.white : null,
        border: onDark ? null : Border.all(color: tone.line),
        borderRadius: BorderRadius.circular(PwaGap.radius),
      ),
      child: Row(
        children: [
          const PwaAbaMethodMark(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Never translated — it is the name printed on the thing the
                // person is about to pay with.
                Text(
                  'ABA KHQR',
                  style: pwaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: pwaInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l.payMethodBody,
                  style: pwaSans(fontSize: 12.5, color: pwaMuted, height: 1.35),
                ),
              ],
            ),
          ),
          // NO CHEVRON, and this is the correction rather than an omission.
          // A trailing chevron promises a destination — another page, a chooser
          // — and tapping this row led nowhere, because there is nothing to
          // choose: ABA KHQR is the only method this deployment offers. The row
          // states which method will be used; `Buy` remains the one control
          // that starts a payment.
        ],
      ),
    );
  }
}
