/// THE FULL REVEAL — rebuilt against iOS. Phase 6.
///
/// Route: `/projects/{projectId}/reveal?vision={visionId}`.
///
/// What this replaced, and why it is a rebuild rather than a restyle
/// ------------------------------------------------------------------
/// The old screen was a reading surface with a picture on it. Above the fold
/// it had a header bar, a metadata strip ("Vision 1 • Warm Modern • Created
/// just now"), a VISION DETAILS panel carrying an eyebrow, a title, a reason
/// label, a paragraph from Ayden and two stacked action rows with subtitles —
/// and, somewhere in there, the transformation the person came to see.
///
/// Almost all of that was already said on the Result screen a tap earlier. The
/// Full Reveal is not where the product explains itself. It is where it shows.
///
/// So: the panel is gone, the metadata strip is gone, the header bar is gone,
/// and the render is the screen.
///
///     ┌─────────────────────────────┐
///     │ ←            Original│Vision│   the transformation, 3:2, uncropped,
///     │        the render           │   floating in its own blurred halo
///     │                             │
///     └─────────────────────────────┘
///     Explore other atmospheres
///     ▐ Soft Luxury ▌▐ Japandi ▌▐ …     immersive cards, horizontal
///     [ Soft Luxury selected · Create ] only once one is chosen
///
/// IT IS DARK, AND THAT IS PARITY
/// ------------------------------
/// Every other migrated screen moved to the cream canvas. This one does not,
/// because iOS's own Full Reveal does not: `before_after_screen.dart` paints a
/// warm walnut gradient (#3F3220 → #181410) and calls it "galleria, not
/// dashboard". A gallery dims the room to light the picture. The cream canvas
/// would be lighting the room instead.
///
/// THE MATTE
/// ---------
/// iOS's locked 5.15d decision, reproduced: the render is CONTAINed — zero
/// crop, the promise the screen's name makes — and the letterbox around it is
/// not dead space but a heavily blurred `cover` copy of the render itself. The
/// image extends into its own halo rather than sitting in a box.
///
/// WHAT IS NOT HERE, DELIBERATELY
/// ------------------------------
/// No hold-to-peek. iOS long-presses the render to flash the original upload;
/// `RevealHero` is shared with the frozen mobile app and exposes no way to
/// drive its divider from outside, so imitating that gesture would mean either
/// forking the widget or remounting it — a fragile copy of a native gesture,
/// which the brief explicitly prefers not to have. Dragging compares, the two
/// sides are labelled, and one short line says so.
library;


import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart' show Share;

import '../../cards/card_catalog.dart';
import '../../cards/widgets/atmosphere_hero_card.dart';
import '../../../shared/widgets/reveal_hero.dart';
import '../application/pwa_controller.dart';
import '../domain/pwa_models.dart';
import '../l10n/pwa_l10n.dart';
import 'pwa_architect_tokens.dart';
import 'pwa_render_aspect.dart';
import 'pwa_render_canvas.dart';
import 'pwa_widgets.dart' show pwaAfterImage, pwaBeforeImage;

/// iOS `before_after_screen.dart`: the hero takes half the screen, clamped, and
/// gives back exactly the height of the section header beneath it.
const double kPwaRevealHeroFactor = 0.50;
const double kPwaRevealHeroMin = 340;
const double kPwaRevealHeroMax = 500;
const double kPwaRevealSectionHeaderH = 34;

/// The atmosphere strip's height — iOS's own arithmetic, made explicit.
///
/// Round 2 capped this at a flat 132 on the strength of a 5.15k CHANGELOG
/// comment ("Carousel strip height 120 → 105"). Reading the CODE instead: that
/// comment describes a wave whose formula is not in the file. What the shipped
/// `before_after_screen.dart` actually does is
///
/// ```dart
///   final imageH = (screenH * 0.50).clamp(340.0, 500.0) - sectionHeaderH;
///   …
///   Expanded(child: Padding(top: 12, bottom: 8 + safeBottom,
///       child: _buildControls(...)))     // header + Expanded(carousel) + 52
///   …
///   final cardW = (c.maxHeight * 1.35).clamp(170.0, screenW * 0.86);
///   final cardH = c.maxHeight * 0.82;
/// ```
///
/// which on a 390 × 844 phone gives a card of **335 × 269**, not 178 × 108 —
/// the web's were less than half the native ones, which is the "too narrow /
/// visually compressed" the phone review reported.
///
/// This reproduces iOS's CHAIN rather than a number copied out of it, so the
/// two agree at every viewport. It stays a fixed height (iOS's is an Expanded
/// inside a fixed budget, which comes to the same thing) because that is what
/// makes selection unable to move the rail.
double pwaRevealStripHeight(double boxH, double boxW) {
  // A WIDE window is not a phone, and iOS has no opinion about one. There the
  // web's own rule stands — the render earns the extra height, because a
  // desktop's limit is the column's WIDTH and a taller strip would only shrink
  // the picture. This is the value Round 2 measured for that case.
  if (boxW >= 700) return 132.0;

  const controlsPadV = 20.0; // iOS: Padding(top: 12, bottom: 8)
  const generateSlotH = 52.0; // iOS: the reserved CTA slot under the carousel
  final imageH = (boxH * kPwaRevealHeroFactor)
          .clamp(kPwaRevealHeroMin, kPwaRevealHeroMax) -
      kPwaRevealSectionHeaderH;
  final carousel =
      boxH - imageH - controlsPadV - kPwaRevealSectionHeaderH - generateSlotH;
  // Bounded at both ends: floored so a very short window still shows a card
  // rather than a sliver, and capped so the chain lands on iOS's measured
  // 335 x 220 rather than drifting past it on a tall phone.
  return carousel.clamp(150.0, 270.0);
}

/// The action slot's RESERVED height — the second half of the same fix.
///
/// The slot's own docstring already promised this ("Reserved rather than
/// animated, so choosing a card does not resize the strip above it") but it
/// rendered `SizedBox.shrink()` when idle and a two-line confirmation when a
/// card was tapped. That ~90dp swing came straight out of the `Expanded` above
/// it, so every selection resized every card in the rail. Fixed now, so the
/// geometry above it cannot move.
const double kPwaRevealSlotH = 104;  // measured: the pending bar needs
// 95 at the default text scale; the rest is headroom for FR/KM metrics.

/// The slot's own padding, counted into the hero's budget so the two agree.
const double kPwaRevealSlotPadV = 18;




/// The band under the render, reserved so the picture is never laid out
/// underneath the one line of text that sits there.
///
/// It was 84 because it used to hold TWO things: the instruction AND a full
/// "Refine with Ayden" pill. The pill is gone — that capability is the pencil
/// in the top-left chrome now, where iOS puts it — and the band was never
/// re-measured, so the render carried 84dp of reserved space for a 14dp line.
/// iOS reserves none at all: its image block is `imageH` tall, the render is
/// anchored to the top of it, and nothing is drawn beneath.
///
/// So this is the line's own height and nothing else, derived rather than
/// chosen: the text sits at `bottom: 12` and is `fontSize: 11` at Flutter's
/// default 1.2 leading (⌈13.2⌉ = 14), leaving 8 of clearance between it and
/// the render's lower edge.
const double kPwaRevealFootH = 12 + 14 + 8;

/// The floating chrome's own band at the top of the hero — Back, Edit, Replay
/// and Share sit at `top: 8` and are 40 tall, so the render starts below them.
///
/// It has to be RESERVED rather than overlapped: `RevealHero` prints the
/// Original / result labels along its own top edge, and with the render pulled
/// up under the buttons the two collided. iOS has the same four circles over
/// its image, but its image block is taller than the contained 3:2 render is
/// here, so the collision never arises there.
const double kPwaRevealChromeH = 8 + 40;

/// A restrained ceiling so a 27" monitor gets a bigger picture, not a poster.
const double kPwaRevealMaxWidth = 1080;

/// iOS's walnut body — the gallery wall the render hangs on.
const List<Color> kPwaRevealCanvas = [
  Color(0xFF3F3220),
  Color(0xFF2F2519),
  Color(0xFF221C14),
  Color(0xFF181410),
];

class PwaRevealScreen extends ConsumerStatefulWidget {
  const PwaRevealScreen({super.key});

  @override
  ConsumerState<PwaRevealScreen> createState() => _PwaRevealScreenState();
}

class _PwaRevealScreenState extends ConsumerState<PwaRevealScreen> {
  PwaController get _c => ref.read(pwaControllerProvider.notifier);

  /// How many times Replay has been pressed. It is only ever part of the
  /// reveal's widget key — see `_RevealHeroBlock.replayToken`.
  int _replayToken = 0;

  /// Share, the way iOS shares.
  ///
  /// `before_after_screen.dart` shares TEXT, not the render:
  /// `Share.share('Check out my AI home redesign — $_title!')`. That is the
  /// same package and the same shape here, so nothing is invented and nothing
  /// is promised that the platform cannot do: `share_plus` uses the browser's
  /// own `navigator.share` where it exists.
  ///
  /// A private render is deliberately NOT attached. Its URL is a signed,
  /// expiring Storage link scoped to one account — putting it into a share
  /// sheet would hand a third party a credential with a lifetime.
  Future<void> _share(PwaVision vision) async {
    final l = context.pwaL10n;
    final state = ref.read(pwaControllerProvider);
    final title = pwaAtmosphereNameOf(state, vision.atmosphereId);
    try {
      await Share.share(l.shareVisionText(title));
    } catch (_) {
      // Every browser that cannot share says so by throwing. Saying nothing
      // would be worse than saying "not here".
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.shareUnavailable)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pwaControllerProvider);
    final vision = state.previewedVision;
    // A Reveal without a vision cannot exist (the route model normalizes it
    // away). Fall back to the conversation rather than dereferencing null.
    if (vision == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _c.backToConversation();
      });
      return const ColoredBox(color: av7DarkBg);
    }

    return Scaffold(
      key: const ValueKey('pwa-full-reveal'),
      backgroundColor: av7DarkBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The gallery wall, full-bleed and behind everything — including the
          // space under the render, so the picture floats on one continuous
          // surface instead of ending at a seam.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.30, 0.65, 1.0],
                  colors: kPwaRevealCanvas,
                ),
              ),
            ),
          ),
          SafeArea(
            // The action slot carries the bottom inset itself, so the section
            // can run to the edge of the glass.
            bottom: false,
            child: LayoutBuilder(
              builder: (context, box) {

                // THE HEIGHT BUDGET.
                //
                // Everything below the hero is a FIXED quantity — the section
                // header, the atmosphere strip and the reserved action slot —
                // which is what makes the rail stable: nothing the person does
                // can resize it, because nothing under it changes size.
                final stripH = pwaRevealStripHeight(box.maxHeight, box.maxWidth);
                final belowH = kPwaRevealSectionHeaderH +
                    stripH +
                    kPwaRevealSlotH +
                    kPwaRevealSlotPadV;

                // EXACTLY WHAT THE RENDER NEEDS — nothing reserved beyond it.
                //
                // This used to take the LARGER of two candidates: iOS's
                // `(screenH * 0.50).clamp(340, 500) - sectionHeaderH`, and the
                // height the render needs at the full column width. On a phone
                // iOS's rule won (366 against 302) and the render could not
                // use the difference: iOS fills its image block, the web
                // CONTAINs a 3:2 render at zero crop, so the surplus became
                // dead space between the picture and the instruction line —
                // the ~84dp gap the phone review reported. Reserving less in
                // the foot alone would have made it WORSE (26 → 76), because
                // the surplus is the hero's, not the foot's.
                //
                // So the hero is the render's own requirement — its 3:2 height
                // at the column width, plus the line beneath it and the frame
                // around it — and iOS's 0.50 rule stays where it still governs
                // something real: `pwaRevealStripHeight`, which derives the
                // atmosphere rail from it.
                //
                // And "the render's own requirement" means the render's OWN
                // shape. A portrait photo comes back as a portrait render
                // (1024×1536); framing it at 3:2 cover-cropped it to landscape,
                // which the phone review read as the engine having widened the
                // room. The aspect is measured off the decode (see
                // `pwa_render_aspect.dart`); a portrait render is height-bound,
                // so it takes what the rail and the slot leave, as iOS's
                // fixed-height block CONTAINs it.
                final renderAspect = pwaAspectOf(
                  ref.watch(pwaRenderAspectsProvider),
                  vision.afterAsset,
                  fallbackKey: kPwaSourceAspectKey,
                );
                // The hero is iOS's IMAGE BLOCK — a fixed, full-width surface
                // (`(screenH * 0.50).clamp(340, 500) - 34`) — plus the chrome
                // band and the instruction line, bounded by what the rail and
                // the slot leave. The render's orientation no longer sizes the
                // block: it sizes the INNER frame, centred on the block over a
                // blurred continuation of itself (`pwa_render_canvas.dart`).
                //
                // A WIDE window is not a phone, and iOS has no opinion about
                // one; there the block also grows to the render's own height
                // at the column width (Round 2: "a wide window gets a BIGGER
                // comparison"), still bounded by what is available.
                final contentW = box.maxWidth < kPwaRevealMaxWidth
                    ? box.maxWidth
                    : kPwaRevealMaxWidth;
                final heroH = pwaRevealHeroHeight(
                  blockH: math.max(
                    pwaRevealBlockHeight(box.maxHeight),
                    (contentW - 24) / renderAspect,
                  ),
                  available: box.maxHeight - belowH,
                  chromeH: kPwaRevealChromeH,
                  footH: kPwaRevealFootH,
                );

                return Center(
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: kPwaRevealMaxWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // TOP-ANCHORED, at iOS's own height — not Expanded.
                        //
                        // iOS anchors the render "to the very top" of the
                        // safe area and lets the walnut continue beneath it
                        // (`before_after_screen.dart`, Wave 5.13d.8). Letting
                        // the hero expand instead centred the render and
                        // exposed the gradient's LIGHTEST stop (#3F3220) as a
                        // wide band above it — which is the flat taupe block
                        // the phone review saw. The colours were already iOS's;
                        // what differed was how much of the light end showed.
                        //
                        // The slack now falls BELOW the render, where iOS puts
                        // it and where the gradient is already deep — "a calm
                        // transition zone", not a hole, because the strip and
                        // the slot are pinned to the bottom by the Spacer.
                        SizedBox(
                          height: heroH,
                          child: _RevealHeroBlock(
                            state: state,
                            vision: vision,
                            aspect: renderAspect,
                            onBack: () => _c.backToConversation(
                              focusVisionId: vision.versionId,
                            ),
                            onPrev: _c.previewPrevious,
                            onNext: _c.previewNext,
                            // Untouched semantics: it records which vision the
                            // next message is about and hands the person back
                            // to the conversation. It generates nothing.
                            onRefine: () =>
                                _c.startRefineContext(vision.versionId),
                            // Presentation only: remount the reveal so its
                            // auto-sweep runs again. No request, no version,
                            // no Space.
                            onReplay: () =>
                                setState(() => _replayToken++),
                            onShare: () => _share(vision),
                            replayToken: _replayToken,
                          ),
                        ),
                        // The strip block sits CENTRED in what is left between
                        // the render and the reserved slot — iOS centres its
                        // own carousel in the same leftover (`Align(center)`
                        // inside an Expanded). Pinning it to the bottom left
                        // the void reading as a hole above it rather than as
                        // the calm transition zone iOS describes.
                        const Spacer(),
                        _SectionHeader(context.pwaL10n.exploreOtherAtmospheres),
                        // Fixed, not Expanded. The strip used to take whatever
                        // was left over, which made a card ~310dp wide on a
                        // phone — most of the screen for one of five
                        // directions — and made every card resize whenever the
                        // slot below grew.
                        SizedBox(
                          height: stripH,
                          child: _AtmosphereCarousel(
                            state: state,
                            onSelect: _c.stageAtmosphere,
                          ),
                        ),
                        const Spacer(),
                        _ActionSlot(state: state, controller: _c),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The atmosphere name for an id, or the signature default.
String pwaAtmosphereNameOf(PwaState state, String? id) {
  for (final a in state.atmospheres) {
    if (a.id == id) return a.name;
  }
  return 'Ayden Signature';
}

// ════════════════════════════════════════════════════════════════════════════
// THE TRANSFORMATION
// ════════════════════════════════════════════════════════════════════════════

class _RevealHeroBlock extends StatelessWidget {
  const _RevealHeroBlock({
    required this.state,
    required this.vision,
    required this.onBack,
    required this.onPrev,
    required this.onNext,
    required this.onRefine,
    required this.onReplay,
    required this.onShare,
    required this.replayToken,
    required this.aspect,
  });

  final PwaState state;
  final PwaVision vision;

  /// The render's measured `width / height` (3:2 until it is known).
  final double aspect;
  final VoidCallback onBack;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onRefine;
  final VoidCallback onReplay;
  final VoidCallback onShare;

  /// Bumped by Replay. Part of the reveal's key, and nothing else.
  final int replayToken;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    final atmosphere = pwaAtmosphereNameOf(state, vision.atmosphereId);

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── The block, and the render inside it ─────────────────────────────
        //
        // Round 2 removed a full-screen ambient halo here, citing iOS's 5.13b
        // ("Dropped: RevealCanvas ambient blur backdrop"). That reading stopped
        // one wave early. iOS 5.15d then made the reveal a CONTAIN and wrote,
        // in `before_after_screen.dart:502`: "the letterbox is no longer dead
        // walnut — a blurred BoxFit.cover copy of the AFTER image fills the
        // surface so the BoxFit.contain foreground floats on its own extended
        // colour". That is inside the rounded block (22), not across the
        // screen: the walnut gradient stays around it, the matte lives in it.
        //
        // The block is iOS's fixed image block; the render is CONTAINed in it
        // at its measured ratio. A portrait render is portrait artwork on a
        // canvas, a landscape one the same canvas with the matte above and
        // below. Nothing is cropped. Nothing is 3:2 by decree.
        Padding(
          // The bottom inset is the hint's own height. Without it the block's
          // lower edge and the instruction line share the same six pixels.
          padding: const EdgeInsets.fromLTRB(
              12, kPwaRevealChromeH, 12, kPwaRevealFootH),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: PwaRenderCanvas(
              key: ValueKey('full-reveal-canvas-${vision.versionId}'),
              reference: vision.afterAsset,
              aspect: aspect,
              style: PwaCanvasStyle.reveal,
              child: RevealHero(
                  // The replay token is part of the KEY on purpose. The shared
                  // `RevealHero` is a FROZEN widget and exposes no controller
                  // (iOS drives its own `RevealController.replay()` instead),
                  // so replaying the presentation here means remounting it —
                  // which restarts the auto-sweep from the beginning. It
                  // renders the same two images, asks the engine for nothing,
                  // creates no version and spends no Space.
                  key: ValueKey('full-reveal-${vision.versionId}-$replayToken'),
                  afterImage: pwaAfterImage(vision),
                  beforeImage: pwaBeforeImage(
                    state.source,
                    state.project,
                    vision: vision,
                    versions: state.versions,
                  ),
                  initialFraction: 0.30,
                  autoSweep: true,
                  // SURFACE, not handle. Everywhere else in this product the
                  // handle owns the drag so it cannot fight a scrolling page —
                  // and this is the one screen that does not scroll, which is
                  // exactly the condition the shared widget documents for
                  // giving the whole surface to the gesture.
                  dragMode: RevealDragMode.surface,
                  beforeLabel: l.beforeLabel,
                  afterLabel: atmosphere,
                  showLabels: true,
                ),
              ),
            ),
          ),

        // ── Chrome, kept to the corners ─────────────────────────────────────
        Positioned(
          top: 8,
          left: 8,
          right: 8,
          child: Row(
            key: const ValueKey('pwa-reveal-header'),
            children: [
              _GlassButton(
                key: const ValueKey('pwa-back-to-conversation'),
                icon: Icons.arrow_back_rounded,
                tooltip: l.backToConversation,
                onTap: onBack,
              ),
              const SizedBox(width: 8),
              // EDIT — iOS's own pencil, in iOS's own slot (top-left, right of
              // Back: "Wave 4.9.3 — 'Refine in chat' pencil… Top-LEFT, right
              // of Back"). It is the same capability the foot pill used to
              // carry: `startRefineContext` records which vision the next
              // message is about and hands the person back to the
              // conversation. It generates nothing.
              _GlassButton(
                key: const ValueKey('pwa-reveal-edit'),
                icon: Icons.edit_outlined,
                tooltip: l.refineWithAyden,
                onTap: onRefine,
              ),
              const Spacer(),
              // Only when there is more than one vision to step between. A
              // navigator that can never move is chrome for its own sake.
              if (state.versionCount > 1) ...[
                _GlassButton(
                  icon: Icons.chevron_left_rounded,
                  tooltip: l.previousVision,
                  onTap: state.hasPreviousVision ? onPrev : null,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    l.visionOfTotal(
                      state.previewedIndex + 1,
                      state.versionCount,
                    ),
                    style: av7Sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: av7OnDark,
                    ),
                  ),
                ),
                _GlassButton(
                  icon: Icons.chevron_right_rounded,
                  tooltip: l.nextVision,
                  onTap: state.hasNextVision ? onNext : null,
                ),
                const SizedBox(width: 8),
              ],
              // REPLAY — iOS's `Icons.replay` at `right: 52`, which
              // "re-triggers the cinematic reveal in place so the user never
              // has to leave and re-enter Full Reveal". Presentation only.
              _GlassButton(
                key: const ValueKey('pwa-reveal-replay'),
                icon: Icons.replay_rounded,
                tooltip: l.replayReveal,
                onTap: onReplay,
              ),
              const SizedBox(width: 8),
              // SHARE — iOS's share circle at `right: 12`. It shares TEXT, not
              // the render: `Share.share('Check out my AI home redesign — …')`.
              // The web equivalent is the same call through the same package,
              // which uses `navigator.share` where the browser has it.
              _GlassButton(
                key: const ValueKey('pwa-reveal-share'),
                icon: Icons.ios_share_rounded,
                tooltip: l.shareVision,
                onTap: onShare,
              ),
            ],
          ),
        ),

        // ── The one line of instruction ────────────────────────────────────
        //
        // The foot used to carry a full "Refine with Ayden" pill as well. iOS
        // has no such pill: the same capability is the PENCIL in the top-left
        // chrome, and the foot of its hero carries nothing. Keeping both put
        // one action in two places and pushed the atmosphere section down.
        //
        // The instruction stays. iOS does not draw it — `dragToReveal` is in
        // the shared dictionary but unused by `before_after_screen.dart` — and
        // the web keeps it because a surface-drag compare with no handle is
        // discoverable on a phone and much less so with a mouse.
        Positioned(
          left: 0,
          right: 0,
          bottom: 12,
          child: IgnorePointer(
            child: Text(
              l.shared.dragToReveal,
              textAlign: TextAlign.center,
              style: av7Sans(
                fontSize: 11,
                color: av7OnDark.withValues(alpha: 0.62),
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
/// A control that reads on any render: dark glass, never a bare glyph over an
/// unpredictable photograph.
class _GlassButton extends StatelessWidget {
  const _GlassButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return Semantics(
      button: true,
      enabled: on,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: const Color(0xFF181410).withValues(alpha: on ? 0.62 : 0.30),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                icon,
                size: 20,
                color: av7OnDark.withValues(alpha: on ? 1 : 0.35),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// EXPLORE OTHER ATMOSPHERES
// ════════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: kPwaRevealSectionHeaderH,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: av7Sans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: av7OnDark,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      );
}

/// The alternatives, as pictures rather than swatches.
///
/// Uses iOS's own `AtmosphereHeroCard` in its `fillPhoto` form — the same
/// widget Create's Step 3 shows — so an atmosphere looks the same wherever the
/// product offers it.
class _AtmosphereCarousel extends StatelessWidget {
  const _AtmosphereCarousel({required this.state, required this.onSelect});

  final PwaState state;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    final screenW = MediaQuery.sizeOf(context).width;
    // TWO concepts, one tick. While nothing is staged the tick marks the
    // direction the render on screen was made in (the CURRENT vision's
    // atmosphere). The moment the person taps a card, that card is the
    // PENDING choice and the tick moves to it — the same state the bar
    // beneath the rail reads ("Soft Luxury selected") and the same state
    // Create Vision will generate. Cancel clears the pending choice and the
    // tick returns to the current atmosphere. iOS's rail is driven by its
    // `_selectedAtmosphere` alone (`selected: _selectedAtmosphere == a.name`);
    // the web additionally shows the applied one at rest.
    //
    // Reported from the phone (Round 3): the tick stayed on Warm Modern while
    // the bar said "Soft Luxury selected" — this read `currentVision` only.
    final appliedId = state.pendingAtmosphereId ??
        state.currentVision?.atmosphereId ??
        state.selectedAtmosphereId;

    return LayoutBuilder(
      builder: (context, c) {
        // iOS's proportions: the card's width follows the strip's height, the
        // card itself is a little shorter so the strip reads as calm rather
        // than packed. The strip is CAPPED (`kPwaAtmoStripH`) rather than
        // taking all the room the Expanded offers — that cap is what keeps a
        // card browsable-sized instead of screen-sized, and what makes the
        // geometry identical in every selection state.
        // The parent hands down `pwaRevealStripHeight`; taking it from the
        // constraint rather than recomputing keeps this honest if a caller
        // ever gives it less. The 170 floor and the 0.86-of-screen ceiling are
        // iOS's OWN clamps — the web had lowered the floor to 150, which on a
        // narrow phone made the card smaller than the native one is allowed to
        // be.
        final strip = c.maxHeight;
        final cardW = (strip * 1.35).clamp(170.0, screenW * 0.86);
        final cardH = strip * 0.82;
        return Align(
          child: SizedBox(
            height: cardH,
            child: ListView.separated(
              key: const ValueKey('pwa-reveal-atmospheres'),
              scrollDirection: Axis.horizontal,
              primary: false,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: state.atmospheres.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final a = state.atmospheres[i];
                final selected = a.id == appliedId;
                final signature = a.id == 'ayden_signature';
                return SizedBox(
                  width: cardW,
                  child: AtmosphereHeroCard(
                    key: ValueKey('pwa-reveal-atmo-${a.id}'),
                    // The Signature wordmark is baked into its art, exactly as
                    // on Create — the card names itself.
                    name: signature ? '' : a.name,
                    subtitle: signature
                        ? l.selectedByAyden
                        : l.atmosphereSubtitle(a.id),
                    asset: signature
                        ? kPwaSignatureRevealAsset
                        : (kAtmosphereCardById[a.id]?.asset ??
                            'assets/cards/atmospheres/${a.id}.png'),
                    selected: selected,
                    // iOS's exact call for THIS rail, restored: the large mode
                    // with two size overrides. Round 2 switched to `compact`
                    // because the card had been shrunk to 178dp, where the
                    // large mode's 22/20/20 padding does not fit. With the card
                    // back at its native ~335 the large mode is right again —
                    // and it is what the phone actually draws.
                    fillPhoto: true,
                    nameFontSize: 16,
                    subtitleFontSize: 11,
                    // Staging only. Which atmospheres a person may pick, when a
                    // switch is allowed and what it costs are all decided
                    // elsewhere and are untouched by this screen: the tap
                    // records a choice and the slot below asks for
                    // confirmation, exactly as before.
                    onTap: state.generating ? null : () => onSelect(a.id),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// The pre-composed AYDEN SIGNATURE art — not in the atmosphere card
/// catalogue, because Signature is a delegation rather than an atmosphere.
const String kPwaSignatureRevealAsset = 'assets/atmospheres/ayden_signature.jpg';

// ════════════════════════════════════════════════════════════════════════════
// THE ACTION SLOT
// ════════════════════════════════════════════════════════════════════════════

/// One reserved band under the carousel, and only ever one thing in it: the
/// confirmation for a staged atmosphere, or the adopt/discard pair when a
/// previous vision is being previewed. Reserved rather than animated, so
/// choosing a card does not resize the strip above it.
class _ActionSlot extends StatelessWidget {
  const _ActionSlot({required this.state, required this.controller});

  final PwaState state;
  final PwaController controller;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    final Widget child;
    if (state.pendingAtmosphereId != null) {
      child = PwaRevealPendingBar(state: state, controller: controller);
    } else if (state.isPreviewingOther) {
      child = PwaRevealPreviewActions(state: state, controller: controller);
    } else {
      child = const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 10 + inset),
      child: SizedBox(height: kPwaRevealSlotH, child: child),
    );
  }
}

/// A staged atmosphere, awaiting the person's word.
///
/// EVERY semantic here is the one that was here before: staging creates
/// nothing, Cancel drops it, and only the confirm button spends anything. The
/// copy states the cost before it is paid.
class PwaRevealPendingBar extends StatelessWidget {
  const PwaRevealPendingBar({
    super.key,
    required this.state,
    required this.controller,
  });

  final PwaState state;
  final PwaController controller;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    final atmo = state.atmospheres.firstWhere(
      (a) => a.id == state.pendingAtmosphereId,
      orElse: () => state.atmospheres.first,
    );
    final busy = state.generating;

    // Two lines, not one. "Ayden Signature sélectionnée · Crée la Vision 2 ·
    // Utilise 1 Space" beside two buttons left the sentence about eighty
    // pixels wide on a phone, and the cost — the one thing that must be read
    // before it is paid — ellipsised away to "· ...".
    return Column(
      key: const ValueKey('pwa-reveal-pending'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.atmosphereSelected(atmo.name),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: av7Sans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: av7OnDark,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          // Each of these already carries its own leading "·" — they were
          // written to be chained. Joining them with another one produced
          // "· Crée la Vision 2 · · Utilise 1 Space".
          '${l.createsVisionN(state.versionCount + 1)} ${l.usesOneSpace}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: av7Sans(fontSize: 12, color: av7OnDarkSoft),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: busy ? null : controller.cancelPendingAtmosphere,
              style: TextButton.styleFrom(foregroundColor: av7OnDarkSoft),
              child: Text(l.cancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const ValueKey('pwa-reveal-create'),
              onPressed: busy ? null : controller.applyAtmosphere,
              style: FilledButton.styleFrom(
                backgroundColor: av7Gold,
                foregroundColor: av7Ink,
                shape: const StadiumBorder(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
              ),
              child: Text(busy ? l.creating : l.createVision),
            ),
          ],
        ),
      ],
    );
  }
}

/// Previewing a vision that is not the current one: adopt it, or leave it be.
/// Untouched semantics — `setCurrentVision` is the only thing that changes
/// which vision the session is working from.
class PwaRevealPreviewActions extends StatelessWidget {
  const PwaRevealPreviewActions({
    super.key,
    required this.state,
    required this.controller,
  });

  final PwaState state;
  final PwaController controller;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    final v = state.previewedVision!;
    return Row(
      key: const ValueKey('pwa-reveal-preview-actions'),
      children: [
        Expanded(
          child: Text(
            l.previewingVisionN(v.visionNumber),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: av7Sans(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: av7OnDarkSoft,
            ),
          ),
        ),
        FilledButton(
          onPressed: () => controller.setCurrentVision(v.versionId),
          style: FilledButton.styleFrom(
            backgroundColor: av7Gold,
            foregroundColor: av7Ink,
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: Text(l.setAsCurrent),
        ),
      ],
    );
  }
}
