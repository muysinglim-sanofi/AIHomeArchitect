/// THE NEW DESIGN SESSION — the wait, aligned to iOS. Phase 4.
///
/// What this replaces, and why it needed replacing
/// -----------------------------------------------
/// The old wait was already cream, already free of a fake percentage, and
/// already said only what it could know. It was not a "legacy dark loading
/// screen" and it was not dishonest. What it was, was DISCONNECTED: a gold
/// compass on an empty canvas, with the person's photo, their room, their
/// atmosphere and the words they had just typed all gone from the screen the
/// moment they pressed Generate. Two minutes of a form being processed.
///
/// So the change here is not a restyle of a loader. It is the difference
/// between "a server is working on your request" and "Ayden is reading YOUR
/// space" — and the way to say the second is to keep the space on screen.
///
///     NEW DESIGN SESSION            eyebrow, session identity
///     Living Room · Warm Modern     what was actually asked for
///     ┌───────────────────────┐
///     │   the person's photo  │     large, uncropped, ambient blur behind
///     │                       │
///     │  ● ○ ○                │     dots
///     │  Reading your space…  │     Ayden's voice, iOS's approved wording
///     │  ▁▁▁▁▁▁▁▁▁            │     indeterminate, never a percentage
///     └───────────────────────┘
///     "more natural light"          their own words, if they wrote any
///     This usually takes a couple of minutes.
///
/// THE PHOTO IS NOT CROPPED
/// ------------------------
/// iOS's `_LoadingBubble` fills its card with `BoxFit.cover`. On a phone
/// holding a 4:3 photo that is nearly free; on the web, where a desktop
/// browser's card is a different shape entirely, cover-cropping cuts away the
/// part of the room the person is asking to have redesigned. So the focal image
/// is CONTAINed and iOS's own ambient backdrop — blurred, muted toward ink —
/// fills the rest. That backdrop exists on iOS for exactly this purpose; it is
/// simply never visible there because the focal image covers it.
///
/// WHAT IS NOT CLAIMED
/// -------------------
/// No percentage, and no asymptotic bar either. iOS eases a progress line from
/// 0.04 to 0.96 over eighty seconds and never completes it — visually calm, but
/// it is invented progress: nothing in the pipeline reports any. A person who
/// watches it sit near the end for a minute learns that the bar is decorative.
/// This screen uses a travelling highlight, which says the one true thing —
/// still working — and never implies a distance covered.
///
/// The phrases are the mobile dictionary's own `genInitPhrases`, approved and
/// translated in all three languages, shown on iOS's widening cadence and
/// HELD on the last one for as long as the render actually takes. They are
/// experiential language, not telemetry, and no new production copy was
/// written for this screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/media/ayden_image_source.dart';
import '../../../shared/widgets/reveal_canvas.dart';
import '../application/pwa_controller.dart';
import '../l10n/pwa_l10n.dart';
import 'pwa_entry_screen.dart' show pwaRoomById;
import 'pwa_scaffold.dart';
import 'pwa_theme.dart';
import 'pwa_type.dart';

/// iOS `_LoadingBubble`: `height * 0.52`, clamped. Copied rather than
/// re-derived — it is the proportion that makes the photo the subject of the
/// screen without pushing the status text off a small phone.
const double kPwaSessionCanvasFactor = 0.52;
const double kPwaSessionCanvasMin = 280;
const double kPwaSessionCanvasMax = 560;

/// iOS `_advancePhases`: how long each beat is shown, in milliseconds. The
/// windows WIDEN, so the narrative slows as the wait goes on instead of
/// marching. The last entry is never used — that phrase is held.
///
/// Reproduced without iOS's ±14% jitter. On a phone the jitter keeps a
/// repeated wait from feeling mechanical; here it would only make the cadence
/// untestable, and the widening windows are already irregular.
const List<int> kPwaSessionDwellMs = [3200, 4000, 5200, 6600, 8200, 9000];

/// The beat being shown after [elapsed], given [count] phrases.
///
/// Monotonic and non-looping: it advances through the narrative once and then
/// STOPS on the last phrase, so a slow render keeps saying "finalizing your
/// vision" rather than starting again at "reading your space" — which would
/// tell the person the work had restarted, and it has not.
///
/// Pure, so the cadence is testable without pumping an animation.
int pwaSessionPhaseFor(Duration elapsed, int count) {
  if (count <= 1) return 0;
  var threshold = 0;
  for (var i = 0; i < count - 1; i++) {
    threshold += i < kPwaSessionDwellMs.length
        ? kPwaSessionDwellMs[i]
        : kPwaSessionDwellMs.last;
    if (elapsed.inMilliseconds < threshold) return i;
  }
  return count - 1;
}

class PwaDesignSessionScreen extends ConsumerStatefulWidget {
  const PwaDesignSessionScreen({super.key});

  @override
  ConsumerState<PwaDesignSessionScreen> createState() =>
      _PwaDesignSessionScreenState();
}

class _PwaDesignSessionScreenState extends ConsumerState<PwaDesignSessionScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _warmed = false;

  @override
  void initState() {
    super.initState();
    // One breathing cycle, repeated. Indeterminate by construction, because
    // the backend reports no progress to be determinate about. Elapsed time
    // for the phrase cadence comes from this same ticker, so there is no
    // second timer to leak.
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_warmed) return;
    _warmed = true;
    // PRESERVED FROM THE OLD SCREEN, and now doubly earned. It warms the Before
    // photo during this already-awaited window so the Architect's first frame
    // paints the person's own photo instead of an After-only frame. This screen
    // now also renders that same `MemoryImage`, twice (focal + ambient), so the
    // decode is shared rather than repeated.
    final src = ref.read(pwaControllerProvider).source;
    if (src != null) {
      precacheImage(MemoryImage(src.bytes), context, onError: (_, _) {});
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// "Living Room · Warm Modern" — what was actually asked for, in the
  /// person's language. A delegated room reads as "Ayden Decide", which is
  /// what they chose, not a blank.
  String _context(PwaL10n l, PwaState state) {
    final room = state.selectedRoomId == null
        ? l.uplAiDecide
        : l.roomCardLabel(
            state.selectedRoomId!,
            pwaRoomById(state.selectedRoomId)?.label ?? '',
          );
    final id = state.selectedAtmosphereId ?? 'ayden_signature';
    final atmo = state.atmospheres
        .where((a) => a.id == id)
        .map((a) => a.name)
        .firstOrNull;
    return atmo == null ? room : '$room · $atmo';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    final state = ref.watch(pwaControllerProvider);
    final src = state.source;
    final brief = state.visionBrief.trim();

    // iOS's proportion, from the real viewport rather than from `100vh` — which
    // in Safari measures the window with the chrome collapsed and would make
    // this card taller than the space it has.
    final height = (MediaQuery.sizeOf(context).height * kPwaSessionCanvasFactor)
        .clamp(kPwaSessionCanvasMin, kPwaSessionCanvasMax);

    return PwaScreen(
      key: const ValueKey('pwa-design-session'),
      // Centred when the composition fits, scrollable when it does not.
      //
      // `Center` inside a scroll view does nothing vertically — the column is
      // min-sized, so it pins to the top and leaves a band of dead canvas under
      // it on a tall phone. Giving the scroll child a minimum height of the
      // viewport is what actually lets it centre, and it still scrolls the
      // moment a long brief or a large text scale makes it taller.
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            PwaGap.page,
            PwaGap.md,
            PwaGap.page,
            PwaGap.lg,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: c.maxHeight - PwaGap.md - PwaGap.lg,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // NO back, close or navigation of any kind while a generation
                    // is in flight. A second entry into Create is a second billable
                    // request, and the surest way not to offer one is not to draw
                    // it. The person is not trapped: the session leaves this screen
                    // on its own, and a refresh resumes through the pending record
                    // exactly as it did before this phase.
                    Text(
                      l.newDesignSession.toUpperCase(),
                      key: const ValueKey('pwa-session-eyebrow'),
                      style: pwaEyebrow(color: pwaMuted),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _context(l, state),
                      key: const ValueKey('pwa-session-context'),
                      style: PwaType.atmosphereTitle(fontSize: 22).copyWith(
                        fontWeight: FontWeight.w500,
                        height: 1.18,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: PwaGap.md),
                    SizedBox(
                      height: height,
                      width: double.infinity,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(PwaGap.radius),
                        child: _SessionCanvas(source: src, pulse: _ctrl),
                      ),
                    ),
                    if (brief.isNotEmpty) ...[
                      const SizedBox(height: PwaGap.md),
                      _BriefQuote(brief),
                    ],
                    const SizedBox(height: PwaGap.md),
                    SizedBox(
                      width: double.infinity,
                      child: Text(
                        l.usuallyACoupleOfMinutes,
                        key: const ValueKey('pwa-session-duration-note'),
                        textAlign: TextAlign.center,
                        style: PwaType.caption(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The photo, and Ayden's voice over it.
class _SessionCanvas extends StatelessWidget {
  const _SessionCanvas({required this.source, required this.pulse});

  final AydenImageSource? source;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    // ONE provider for both layers, so the bytes are decoded once and the
    // ambient blur is rasterised from the same entry the focal image uses.
    final provider = source == null ? null : MemoryImage(source!.bytes);

    return RevealCanvas(
      ambientImage: provider,
      // iOS `_LoadingBubble`'s own values.
      ambientBlur: 18,
      ambientDarken: 0.5,
      bottomScrim: true,
      bottomOverlay: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
        child: _SessionStatus(pulse: pulse),
      ),
      child: provider == null
          // There is no path to this screen without a photo — `generateFirstVision`
          // returns early when `source` is null — but a calm ink field is the
          // right answer if one ever appears, not a broken frame.
          ? const ColoredBox(color: pwaImageFrame)
          : Image(
              key: const ValueKey('pwa-session-photo'),
              image: provider,
              // CONTAIN, not cover: see the header note. The ambient backdrop
              // fills whatever the photo's own shape does not.
              fit: BoxFit.contain,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => const ColoredBox(color: pwaImageFrame),
            ),
    );
  }
}

/// Dots, the current phrase, and an indeterminate line.
class _SessionStatus extends StatelessWidget {
  const _SessionStatus({required this.pulse});

  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    // The approved mobile narrative — seven beats, already translated in
    // en/fr/km, and the source of the "Reading your space…" this screen opens
    // on. Forwarded rather than rewritten: a web-only phrase set would have
    // meant new production copy in three languages for a screen whose whole
    // point is that it speaks with the product's existing voice.
    final phrases = context.pwaL10n.genInitPhrases;

    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final elapsed = pulse is AnimationController
            ? ((pulse as AnimationController).lastElapsedDuration ??
                  Duration.zero)
            : Duration.zero;
        final index = pwaSessionPhaseFor(elapsed, phrases.length);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Dots(pulse: pulse),
            const SizedBox(height: 10),
            // Reserved height so the card never jitters as the phrase changes,
            // and the outgoing line vanishes rather than cross-fading into the
            // incoming one — two sentences briefly stacked is the artefact this
            // avoids. Both are iOS's choices.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 360),
              switchInCurve: Curves.easeOut,
              switchOutCurve: const Threshold(0),
              layoutBuilder: (cur, _) => cur ?? const SizedBox.shrink(),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: SizedBox(
                key: ValueKey('pwa-session-phase-$index'),
                height: 26,
                width: double.infinity,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    phrases[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PwaType.cardSubtitle(color: pwaSurface),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _IndeterminateLine(pulse: pulse),
          ],
        );
      },
    );
  }
}

/// iOS `_DotsIndicator` — three dots, one lit at a time, ~450ms apart.
/// Driven off the shared ticker rather than its own controller: same cadence,
/// one less thing to dispose.
class _Dots extends StatelessWidget {
  const _Dots({required this.pulse});

  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        // The ticker runs 2600ms; six steps across it is ~433ms each, which is
        // iOS's 450 to within a frame.
        final step = (pulse.value * 6).floor() % 3;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            3,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: i == step ? pwaGold : pwaSurface.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A travelling highlight, NOT a progress bar.
///
/// It says "still working", which is the only thing that is actually known.
/// iOS's asymptotic fill was deliberately not copied — see the header note.
class _IndeterminateLine extends StatelessWidget {
  const _IndeterminateLine({required this.pulse});

  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('pwa-session-progress'),
      width: 200,
      height: 2,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(1),
        child: ColoredBox(
          color: pwaGold.withValues(alpha: 0.22),
          child: AnimatedBuilder(
            animation: pulse,
            builder: (context, _) => Align(
              alignment: Alignment(-1 + 2 * pulse.value, 0),
              child: const FractionallySizedBox(
                widthFactor: 0.34,
                heightFactor: 1,
                child: ColoredBox(color: pwaGold),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The person's own words, given back to them while Ayden works.
///
/// Unlabelled on purpose. A heading would have meant new production copy in
/// three languages, and the quotation marks plus the position already say what
/// it is: the thing they wrote, a moment ago, on the screen before this one.
class _BriefQuote extends StatelessWidget {
  const _BriefQuote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('pwa-session-brief'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: pwaWell,
        borderRadius: BorderRadius.circular(PwaGap.radius),
        border: const Border(left: BorderSide(color: pwaGold, width: 2)),
      ),
      child: Text(
        '“$text”',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: PwaType.bodyMuted(
          color: pwaOnCanvas,
        ).copyWith(fontStyle: FontStyle.italic),
      ),
    );
  }
}
