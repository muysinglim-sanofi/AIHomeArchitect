/// ABA and KHQR artwork, as supplied by ABA.
///
/// WHICH FILES, AND WHERE THEY COME FROM
/// -------------------------------------
/// Two SVGs handed over by ABA's merchant-review team on 2026-09-08, used byte
/// for byte (the pristine copies live in `docs/aba/official/`, the served
/// copies in `web/aba/` under space-free names):
///
///   * `aba_khqr_payment_option.svg` — ABA's 40×40 payment-option tile
///     (`ABA BANK.svg` as received), shown beside "ABA KHQR" in the Wallet.
///   * `abakhqr-we-accept.svg`       — the 72×20 "We accept" lockup (two tiles,
///     ABA and KHQR, no words), shown in the site footer.
///
/// They REPLACE the generated PNG stand-ins that were authorised for the first
/// preprod review only; those are gone from `web/aba/` and no longer referenced
/// anywhere in the UI. The provenance record of that episode stays at
/// `docs/aba/REJECTED_AI_GENERATED/README.md`.
///
/// WHY THEY ARE FETCHED BY URL AND NOT BUNDLED
/// -------------------------------------------
/// Same reason as before: artwork a bank supplies can be swapped by dropping a
/// file into `web/aba/`, without a rebuild and without compiling a third
/// party's marks into `main.dart.js`.
///
/// WHY flutter_svg, AND WHY THIS LOADER
/// ------------------------------------
/// `Image.network` cannot show an SVG on Flutter web (the codec rejects it —
/// measured, not assumed). flutter_svg draws both files exactly; the tile's
/// `<foreignObject>` blur layer is skipped with a debug-only note, and that
/// layer is invisible anyway (it sits under the opaque ABA fill). The stock
/// network loader has one trap: it hands a 404 body — or `flutter_test`'s
/// stub 400 — to the XML parser, and the resulting error escapes through the
/// picture cache as an uncaught async error. [PwaSvgUrlLoader] checks the
/// status and draws NOTHING on anything but a 200, which is the old
/// `errorBuilder` contract: a missing mark is absent, never a broken glyph.
///
/// WHAT IS NOT HERE
/// ---------------
/// No Visa, no Mastercard, no Alipay, no WeChat, no ABA Pay. This deployment
/// offers exactly one payment method and says so with exactly one mark. And
/// the artwork is never recoloured: no colour filter, no theme, no mapper.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/pwa_mark_loader.dart';
import '../l10n/pwa_l10n.dart';
import 'pwa_theme.dart';

export '../data/pwa_mark_loader.dart'
    show PwaMarkLoader, PwaSvgUrlLoader, pwaMarkLoaderProvider;

/// The official "We accept" lockup: ABA tile + KHQR tile, 72×20, no words.
const String kPwaAcceptMarkAsset = 'aba/abakhqr-we-accept.svg';

/// The official payment-option tile, 40×40.
const String kPwaAbaMethodMarkAsset = 'aba/aba_khqr_payment_option.svg';

/// The acceptance lockup, as ONE picture. [height] is the only knob — the
/// width follows the artwork's own 72:20.
class PwaAcceptMark extends ConsumerWidget {
  const PwaAcceptMark({super.key, this.height = 20});

  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SvgPicture(
        ref.watch(pwaMarkLoaderProvider)(kPwaAcceptMarkAsset),
        key: const ValueKey('pwa-accept-mark'),
        height: height,
        fit: BoxFit.contain,
        semanticsLabel: '${context.pwaL10n.acceptWeAccept} ABA KHQR',
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
}

/// The payment-option tile for the Wallet's method row.
class PwaAbaMethodMark extends ConsumerWidget {
  const PwaAbaMethodMark({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SvgPicture(
        ref.watch(pwaMarkLoaderProvider)(kPwaAbaMethodMarkAsset),
        key: const ValueKey('pwa-aba-method-mark'),
        width: size,
        height: size,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
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

/// The payment-option row above the Wallet's Buy button, in ABA's own format:
/// their tile, the method's name, and their one-line description.
///
/// INFORMATIONAL. It is not a button and carries no affordance suggesting it
/// is: no chevron, no radio, no "Change". ABA's reference shows a chevron
/// because on ABA's screen the row opens a chooser; here there is nothing to
/// choose, and a chevron that leads nowhere is a false promise. `Buy` remains
/// the one control that starts a payment.
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
                // ABA's own description line ("Scan to pay with any banking
                // app"), localised without additions.
                Text(
                  l.payMethodBody,
                  style: pwaSans(fontSize: 12.5, color: pwaMuted, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
