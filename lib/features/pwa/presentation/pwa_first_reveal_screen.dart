/// The First Reveal — the one moment the whole product exists for.
///
/// Route: `/projects/{id}/reveal?vision={v}&mode=first`.
///
/// It is shown exactly once, right after the first Generate, when the project
/// and its vision are already durably saved. Its single job is to let the render
/// land: the image fills the screen, there is one thing to do, and nothing else
/// competes for attention — no details panel, no atmospheres, no navigation, no
/// conversation. Those all belong to the Full Reveal and the Architect.
///
/// It reuses [PwaRevealCard] → the production `RevealHero`, which is shared with
/// the frozen mobile app and used strictly read-only: this screen only composes
/// around it.
///
/// PHASE 5 — it is now on the PRODUCT CANVAS, not on black.
///
/// The black was inherited from a time when every screen after Create was dark.
/// It is a real choice for the Full Reveal, which is a cinema and keeps it. It
/// was the wrong one here: this is the first frame after a two-minute wait that
/// ended on cream, and dropping to black between the session and the
/// conversation made the result feel like it belonged to a different app. The
/// render is still the whole screen and there is still exactly one thing to do
/// — only the room around it changed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pwa_controller.dart';
import 'pwa_architect_screen.dart' show kPwaRenderAspect;
import 'pwa_brand.dart';
import 'pwa_theme.dart';
import 'pwa_type.dart';
import 'pwa_widgets.dart';
import '../l10n/pwa_l10n.dart';

class PwaFirstRevealScreen extends ConsumerWidget {
  const PwaFirstRevealScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pwaControllerProvider);
    final c = ref.read(pwaControllerProvider.notifier);
    final vision = state.previewedVision;
    // Nothing to unveil (a stale route) → hand over to the conversation rather
    // than dereferencing null.
    if (vision == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) c.continueToArchitect();
      });
      return const ColoredBox(color: pwaCanvas);
    }

    return Scaffold(
      key: const ValueKey('pwa-first-reveal'),
      backgroundColor: pwaCanvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final mobile = box.maxWidth < 700;
            // The render takes the room it can; the CTA keeps a reserved band so
            // it is always reachable without scrolling.
            final padH = mobile ? 10.0 : 28.0;

            // A COLUMN, not a Stack.
            //
            // The brand line used to be positioned OVER the render, which was
            // safe when the render sat on black: white text, dark ground,
            // guaranteed. On the canvas the render fills the frame and the
            // words land on whatever the person's room happens to be — light
            // walls, in the first case tried, and they disappeared. Overlaying
            // text on an image you did not choose is a contrast bet; the
            // canvas above the image is not.
            //
            // The readability gradient under the CTA went for the same reason
            // in reverse: it existed to lift a pill off a black photograph,
            // and there is no photograph under it any more.
            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      mobile ? 16 : 34, mobile ? 10 : 16, mobile ? 16 : 34, 12),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PwaLogoBadge(size: 30),
                      SizedBox(width: 10),
                      _BrandLine(),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(padH, 0, padH, 0),
                    // MEASURED, not estimated. The card derives its height from
                    // the aspect it is given, so an aspect computed from a
                    // guess at the header and CTA bands overflows by whatever
                    // the guess was wrong by — it was four pixels. Reading the
                    // real remaining box cannot be wrong by any.
                    // THE RENDER'S OWN SHAPE, centred, rather than the frame's.
                    //
                    // It used to fill the screen edge to edge, which on a
                    // phone means cover-cropping a 3:2 render into a 0.45
                    // portrait — most of the room gone, at the exact moment
                    // the room is the point. Filling the frame was the right
                    // call when the surround was black and the crop read as
                    // cinema; on the canvas it just reads as a mistake.
                    //
                    // Same shape the result screen uses, so the two frames of
                    // the same picture do not disagree about what it is.
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: kPwaRenderAspect,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                              mobile ? PwaGap.radius : 22),
                          child: PwaRevealCard(
                            vision: vision,
                            source: state.source,
                            versions: state.versions,
                            project: state.project,
                            aspectRatio: kPwaRenderAspect,
                            onDark: false,
                            showCaption: false,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(
                      top: 18, bottom: mobile ? 22 : 30),
                  child: _ContinueButton(
                    compact: mobile,
                    onTap: c.continueToArchitect,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BrandLine extends StatelessWidget {
  const _BrandLine();
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'AYDEN STUDIO',
        style: PwaType.caption(color: pwaInk)
            .copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: pwaTracking(2.4)),
      ),
      const SizedBox(height: 2),
      Text(context.pwaL10n.yourFirstVision, style: pwaEyebrow(fontSize: 9)),
    ],
  );
}

/// The only action on the screen.
class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.compact, required this.onTap});
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.pwaL10n.continueWithAyden,
      // The product's primary CTA: an INK pill, as everywhere else. Gold was
      // right when it had to carry against a black photograph; on the canvas
      // the ink pill is the same button the person pressed to get here.
      child: Material(
        color: pwaInk,
        borderRadius: BorderRadius.circular(PwaGap.radiusPill),
        child: InkWell(
          key: const ValueKey('pwa-first-reveal-continue'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(PwaGap.radiusPill),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 28 : 34,
              vertical: compact ? 15 : 17,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    context.pwaL10n.continueWithAyden,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PwaType.button(color: pwaSurface),
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.arrow_forward, size: 18, color: pwaSurface),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
