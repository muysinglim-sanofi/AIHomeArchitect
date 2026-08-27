/// The viewport contract: safe areas, dynamic viewport, sticky CTAs.
///
/// Every one of these exists because iOS Safari does something a desktop
/// browser does not, and because an installed PWA does something Safari does
/// not. They are grouped here so later screens inherit correct behaviour
/// instead of each rediscovering it.
///
/// THE FOUR THAT ACTUALLY BITE
///
/// 1. `100vh` is a lie in Safari. It measures the viewport with the browser
///    chrome COLLAPSED, so a full-height column is taller than what you can see
///    and a bottom CTA sits under the toolbar until you scroll. Flutter reports
///    the honest number through `MediaQuery.sizeOf`, which is why nothing here
///    computes a height from `vh` — the fix is to never reach for it.
///
/// 2. The home indicator. On a notched iPhone the bottom 34 logical pixels are
///    the swipe area. A CTA drawn there is a CTA the user dismisses the app
///    trying to press. [PwaStickyFooter] adds that inset to its own padding
///    rather than leaving it to the screen.
///
/// 3. The Dynamic Island / status bar. In STANDALONE mode there is no browser
///    chrome above the page, so the top inset becomes the app's problem — the
///    same content that looked fine in a Safari tab collides with the clock
///    once installed. [PwaSafeArea] is the single answer.
///
/// 4. The keyboard. Safari resizes the VISUAL viewport, not the layout
///    viewport, so a fixed composer does not move on its own.
///    `MediaQuery.viewInsetsOf(context).bottom` is what actually reports it,
///    and [PwaStickyFooter] honours it so an input is never covered by the
///    keyboard that is editing it.
///
/// None of this is a web-only visual hack. The geometry it produces is the
/// geometry iOS already has; it just has to be asked for explicitly on the web.
library;

import 'package:flutter/material.dart';

import '../application/pwa_layout.dart';
import 'pwa_theme.dart';

/// A screen on the product canvas, inset from the device's unsafe edges.
///
/// Prefer this to a bare `Scaffold` + `SafeArea`: it centralises the canvas
/// colour and the inset policy, so a later screen cannot accidentally paint to
/// the very top of a notched display.
class PwaScreen extends StatelessWidget {
  const PwaScreen({
    super.key,
    required this.child,
    this.background = pwaCanvas,
    this.top = true,
    this.bottom = true,
    this.footer,
  });

  final Widget child;

  /// Defaults to the product canvas. A reveal surface may pass
  /// [pwaImageFrame]; nothing should pass a legacy dark token.
  final Color background;

  /// Whether to inset from the status bar / Dynamic Island. False for a
  /// full-bleed hero that deliberately runs under it — in which case the
  /// content inside must do its own insetting.
  final bool top;

  final bool bottom;

  /// A CTA pinned to the bottom, above the home indicator and above the
  /// keyboard. See [PwaStickyFooter].
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      // `false`: we handle the keyboard in the footer rather than letting the
      // Scaffold resize the whole body, which on Safari produces a visible
      // jump as the layout viewport lags the visual one.
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        top: top,
        // The footer owns the bottom inset when there is one; letting both
        // apply it would double the padding.
        bottom: bottom && footer == null,
        child: footer == null
            ? child
            : Column(
                children: [
                  Expanded(child: child),
                  PwaStickyFooter(child: footer!),
                ],
              ),
      ),
    );
  }
}

/// A bottom-pinned CTA that clears the home indicator AND the keyboard.
///
/// The two insets are deliberately NOT added together. When the keyboard is up
/// it already covers the home indicator, so adding both would float the CTA a
/// further 34px above the keyboard for no reason. `max` is the correct
/// combination, and getting it wrong is visible on every notched phone.
class PwaStickyFooter extends StatelessWidget {
  const PwaStickyFooter({
    super.key,
    required this.child,
    this.background = pwaCanvas,
    this.divider = true,
  });

  final Widget child;
  final Color background;

  /// A hairline above the footer, so a scrolling page passes UNDER it visibly
  /// rather than appearing to end there.
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final inset = media.viewInsets.bottom > 0
        ? media.viewInsets.bottom
        : media.viewPadding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: background,
        border: divider
            ? const Border(top: BorderSide(color: pwaHairline))
            : null,
      ),
      padding: EdgeInsets.fromLTRB(
          PwaGap.page, PwaGap.md, PwaGap.page, PwaGap.md + inset),
      child: child,
    );
  }
}

/// Horizontal page padding plus the restrained max width.
///
/// iOS is a phone and never needs this; the web does, and widening without a
/// ceiling is exactly how a premium product turns into a dashboard. The
/// breakpoints already live in `pwa_layout.dart` — this only applies them.
class PwaPageBody extends StatelessWidget {
  const PwaPageBody({
    super.key,
    required this.child,
    this.horizontal = PwaGap.page,
  });

  final Widget child;
  final double horizontal;

  @override
  Widget build(BuildContext context) {
    final form = pwaFormFactorForWidth(MediaQuery.sizeOf(context).width);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: pwaMaxContentWidth(form)),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontal),
          child: child,
        ),
      ),
    );
  }
}
