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

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cards/card_catalog.dart';
import '../../cards/widgets/atmosphere_hero_card.dart';
import '../../../shared/widgets/reveal_hero.dart';
import '../application/pwa_controller.dart';
import '../domain/pwa_models.dart';
import '../l10n/pwa_l10n.dart';
import 'pwa_architect_screen.dart' show kPwaRenderAspect;
import 'pwa_architect_tokens.dart';
import 'pwa_stored_image.dart';
import 'pwa_widgets.dart' show pwaAfterImage, pwaBeforeImage;

/// iOS `before_after_screen.dart`: the hero takes half the screen, clamped, and
/// gives back exactly the height of the section header beneath it.
const double kPwaRevealHeroFactor = 0.50;
const double kPwaRevealHeroMin = 340;
const double kPwaRevealHeroMax = 500;
const double kPwaRevealSectionHeaderH = 34;

/// The floor the atmosphere section keeps for itself: header, a card, and the
/// action slot. The hero yields rather than pushing it off a short window.
const double kPwaRevealSectionMin = 190;

/// The blur that turns the letterbox into the render's own halo. iOS's sigma.
const double kPwaRevealMatteBlur = 36;

/// The band under the render holding the instruction line and the one action.
/// Reserved, so the picture is never laid out underneath them.
const double kPwaRevealFootH = 84;

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
                final contentW =
                    box.maxWidth < kPwaRevealMaxWidth
                        ? box.maxWidth
                        : kPwaRevealMaxWidth;

                // TWO CANDIDATES, and the bigger wins.
                //
                // iOS's 0.50-of-the-screen rule is a PHONE rule: there, the
                // column is narrow, so height is what limits the render. On a
                // desktop it is the opposite — the column is wide and the
                // 0.50 rule leaves a small picture adrift in a large blurred
                // halo, which is the opposite of "an even larger comparison
                // surface". So the hero also asks what height the render would
                // need to use the full column width, and takes whichever is
                // larger.
                final fromHeight =
                    (box.maxHeight * kPwaRevealHeroFactor).clamp(
                          kPwaRevealHeroMin,
                          kPwaRevealHeroMax,
                        ) -
                        kPwaRevealSectionHeaderH;
                final fromWidth = (contentW - 24) / kPwaRenderAspect +
                    kPwaRevealFootH +
                    24;

                // …bounded by what the atmospheres need. A floor in pixels for
                // a short window, and a share of the screen on a tall one, so
                // the cards never collapse to a strip on a large display.
                final sectionH = box.maxHeight * 0.28 < kPwaRevealSectionMin
                    ? kPwaRevealSectionMin
                    : box.maxHeight * 0.28;
                final heroH = (fromHeight > fromWidth ? fromHeight : fromWidth)
                    .clamp(
                      160.0,
                      (box.maxHeight - sectionH).clamp(160.0, double.infinity),
                    )
                    .toDouble();

                return Center(
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: kPwaRevealMaxWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: heroH,
                          child: _RevealHeroBlock(
                            state: state,
                            vision: vision,
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
                          ),
                        ),
                        _SectionHeader(context.pwaL10n.exploreOtherAtmospheres),
                        Expanded(
                          child: _AtmosphereCarousel(
                            state: state,
                            onSelect: _c.stageAtmosphere,
                          ),
                        ),
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
  });

  final PwaState state;
  final PwaVision vision;
  final VoidCallback onBack;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onRefine;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    final atmosphere = pwaAtmosphereNameOf(state, vision.atmosphereId);

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── The halo ────────────────────────────────────────────────────────
        // The render again, filling the block, blurred past recognition. It is
        // what turns the letterbox from dead walnut into the picture's own
        // extended colour. Isolated in a RepaintBoundary so the blur is
        // rasterised once and never recomputed while the divider is dragged.
        Positioned.fill(
          child: RepaintBoundary(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: kPwaRevealMatteBlur,
                sigmaY: kPwaRevealMatteBlur,
              ),
              child: PwaStoredImage(
                key: ValueKey('reveal-matte-${vision.versionId}'),
                reference: vision.afterAsset,
                placeholderColor: av7DarkBg,
              ),
            ),
          ),
        ),
        // A little ink over the halo: it is a backdrop, and the render in front
        // of it has to stay the brightest thing on the screen.
        const Positioned.fill(
          child: ColoredBox(color: Color(0x59181410)),
        ),

        // ── The render ──────────────────────────────────────────────────────
        Center(
          child: Padding(
            // The bottom inset is the hint + CTA block's own height. Without
            // it the render's lower edge and the instruction line share the
            // same six pixels, and the words sit ON the picture — the exact
            // contrast bet this screen avoids everywhere else.
            padding: const EdgeInsets.fromLTRB(12, 12, 12, kPwaRevealFootH),
            child: AspectRatio(
              // CONTAIN, at the shape the engine returns. The screen is called
              // Full Reveal; cropping it here would be the one place the name
              // is a lie.
              aspectRatio: kPwaRenderAspect,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: RevealHero(
                  key: ValueKey('full-reveal-${vision.versionId}'),
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
              ],
            ],
          ),
        ),

        // ── The one action, and the one line of instruction ────────────────
        //
        // iOS keeps a SINGLE in-hero CTA at the foot of the render. Here it is
        // "Refine with Ayden", and it is not decoration: `startRefineContext`
        // is a real capability that was reachable only from this screen — it
        // returns to the conversation carrying THIS vision, so the composer
        // opens already pointed at it. The details panel that used to hold it
        // is gone; the capability is not.
        Positioned(
          left: 0,
          right: 0,
          bottom: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IgnorePointer(
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
              const SizedBox(height: 8),
              Center(child: _HeroCta(label: l.refineWithAyden, onTap: onRefine)),
            ],
          ),
        ),
      ],
    );
  }
}

/// The single in-hero call to action. Glass, so it reads over a bright kitchen
/// and a dark bedroom alike — the label never sits bare on an image nobody
/// chose.
class _HeroCta extends StatelessWidget {
  const _HeroCta({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('pwa-reveal-refine'),
      color: const Color(0xFF181410).withValues(alpha: 0.66),
      shape: const StadiumBorder(
        side: BorderSide(color: Color(0x59D3B064)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.tune_rounded, size: 15, color: av7Gold),
              const SizedBox(width: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: av7Sans(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: av7OnDark,
                ),
              ),
            ],
          ),
        ),
      ),
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
    // What is APPLIED, not what is staged: the tick marks the direction the
    // render on screen was made in.
    final appliedId =
        state.currentVision?.atmosphereId ?? state.selectedAtmosphereId;

    return LayoutBuilder(
      builder: (context, c) {
        // iOS's proportions: the card's width follows the section's full
        // height, the card itself is a little shorter so the strip reads as
        // calm rather than packed.
        final cardW = (c.maxHeight * 1.35).clamp(150.0, screenW * 0.86);
        final cardH = c.maxHeight * 0.82;
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
      child: child,
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
