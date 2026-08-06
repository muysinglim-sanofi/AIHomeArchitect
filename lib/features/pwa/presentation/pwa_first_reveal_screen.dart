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
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pwa_controller.dart';
import 'pwa_architect_tokens.dart';
import 'pwa_brand.dart';
import 'pwa_widgets.dart';

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
      return const ColoredBox(color: av7DarkBg);
    }

    return Scaffold(
      key: const ValueKey('pwa-first-reveal'),
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final mobile = box.maxWidth < 700;
            // The render takes the room it can; the CTA keeps a reserved band so
            // it is always reachable without scrolling.
            const ctaBand = 104.0;
            final padH = mobile ? 10.0 : 28.0;
            final padTop = mobile ? 10.0 : 20.0;
            // Measure against what the padding actually leaves, or the card asks
            // for more height than its box and overflows.
            final revealH = (box.maxHeight - padTop - ctaBand).clamp(
              160.0,
              1200.0,
            );
            final revealW = (box.maxWidth - padH * 2).clamp(160.0, 4000.0);

            return Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(padH, padTop, padH, ctaBand),
                  child: Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(mobile ? 16 : 22),
                      child: PwaRevealCard(
                        vision: vision,
                        source: state.source,
                        project: state.project,
                        aspectRatio: revealW / revealH,
                        onDark: true,
                        showCaption: false,
                      ),
                    ),
                  ),
                ),
                // Discreet branding, top-left — it is still Ayden's moment.
                Positioned(
                  top: mobile ? 14 : 20,
                  left: mobile ? 16 : 34,
                  child: const IgnorePointer(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PwaLogoBadge(size: 30),
                        SizedBox(width: 10),
                        _BrandLine(),
                      ],
                    ),
                  ),
                ),
                // Readability gradient under the call to action.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: ctaBand + 60,
                  child: const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xF2000000), Color(0x00000000)],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: mobile ? 22 : 30,
                  child: Center(
                    child: _ContinueButton(
                      compact: mobile,
                      onTap: c.continueToArchitect,
                    ),
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
        style: av7Sans(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: av7OnDark,
          letterSpacing: 3,
        ),
      ),
      const SizedBox(height: 2),
      Text('YOUR FIRST VISION', style: av7Eyebrow(fontSize: 8.5)),
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
      label: 'Continue with Ayden',
      child: Material(
        color: av7Gold,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          key: const ValueKey('pwa-first-reveal-continue'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 24 : 34,
              vertical: compact ? 14 : 17,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    'Continue with Ayden',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: av7Sans(
                      fontSize: compact ? 14.5 : 16,
                      fontWeight: FontWeight.w700,
                      color: av7DarkBg,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.arrow_forward, size: 18, color: av7DarkBg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
