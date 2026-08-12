/// The Home dashboard — the front door of Ayden Studio (`/`).
///
/// It follows the mobile mental model, widened for desktop:
///   1. a brand HERO that sells the promise (one photo → one vision) — not the
///      last project, so the page has an identity of its own;
///   2. CONTINUE DESIGNING — the projects, most recent first, one flat list;
///   3. a closing NEW PROJECT block.
///
/// There is deliberately no "featured + recent" split: it made the same project
/// appear twice and turned the dashboard into a second library. The exhaustive
/// library stays at `/projects`.
///
/// The cinematic plays INSIDE the hero band — there is no full-screen overlay
/// and no interstitial: opening or refreshing `/` shows the dashboard straight
/// away, with the transformation running in the hero.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pwa_controller.dart';
import '../application/pwa_intro_gate.dart';
import '../domain/pwa_models.dart';
import '../domain/pwa_project.dart';
import '../l10n/pwa_l10n.dart';
import 'hero/pwa_hero_sequence.dart';
import 'hero/pwa_hero_video.dart';
import 'pwa_architect_tokens.dart';
import 'pwa_brand.dart';
import 'pwa_language_switcher.dart';
import 'pwa_stored_image.dart';
import 'pwa_theme.dart';

/// A generic label the repository returns when no room was ever chosen. It
/// states nothing, so it is never shown.
///
/// NOT a presentation string, and therefore NOT translated: it is a SENTINEL
/// that is compared against STORED data (rows written before a room was
/// resolved carry exactly this text). Localising it would make every such
/// comparison fail in Khmer and French, and the placeholder would start being
/// displayed in precisely the two languages nobody looks at first. What a
/// person sees when the room is unknown is `PwaL10n.yourSpaceFallback`, which
/// IS translated.
const String kPwaGenericRoomLabel = 'Your space';

/// How many projects the dashboard offers before sending the user to the full
/// library. The dashboard is a starting point, not the archive.
const int kPwaHomeProjectCount = 6;

/// Whether arriving on `/` should play the full-screen cinematic.
///
/// Three conditions, no more: the platform can play video, motion is allowed,
/// and this tab has not seen the intro yet. Pure, so the rule is testable
/// without a browser — and so it can never accidentally gate a direct URL to
/// Create / Projects / Architect / Reveal, which do not mount this screen.
bool pwaShouldPlayIntro({
  required bool isWeb,
  required bool reduceMotion,
  required bool gateAllows,
}) => pwaHeroUseVideo(isWeb: isWeb, reduceMotion: reduceMotion) && gateAllows;

class PwaHomeScreen extends ConsumerStatefulWidget {
  const PwaHomeScreen({super.key});

  @override
  ConsumerState<PwaHomeScreen> createState() => _PwaHomeScreenState();
}

class _PwaHomeScreenState extends ConsumerState<PwaHomeScreen>
    with WidgetsBindingObserver {
  PwaHeroSequence? _seq;
  PwaHeroMedia _heroMedia = kHeroMediaDesktop;
  bool _seqStarted = false;

  PwaController get _c => ref.read(pwaControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    pwaHardenDebugPaints();
    pwaDisableRemoteFonts();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seqStarted) return;
    _seqStarted = true;
    final mq = MediaQuery.of(context);
    _heroMedia = pwaHeroMediaFor(mq.size.width < 700);
    final gate = ref.read(pwaIntroGateProvider);
    // Autoplays once per tab session; afterwards the hero simply rests on its
    // finished frame. Either way the page is interactive immediately.
    final autoplay = pwaShouldPlayIntro(
      isWeb: kIsWeb,
      reduceMotion: mq.disableAnimations,
      gateAllows: gate.shouldAutoplay(),
    );
    precacheImage(
      const AssetImage(kAydenLogoHero),
      context,
      onError: (_, _) {},
    );
    precacheImage(
      NetworkImage(autoplay ? _heroMedia.startPoster : _heroMedia.endPoster),
      context,
      onError: (_, _) {},
    );
    _seq = _buildSequence(useVideo: autoplay);
    if (autoplay) gate.markStarted();
  }

  PwaHeroSequence _buildSequence({required bool useVideo}) => PwaHeroSequence(
    useVideo: useVideo,
    createVideo: ({required onReady, required onEnded, required onError}) =>
        createPwaHeroVideo(
          mp4: _heroMedia.mp4,
          webm: _heroMedia.webm,
          poster: _heroMedia.startPoster,
          objectPosition: _heroMedia.videoObjectPosition,
          onReady: onReady,
          onEnded: onEnded,
          onError: onError,
        ),
  );

  /// "See how it works" — replay the transformation IN THE HERO. Repeatable,
  /// stays on Home, touches no project, never covers the page.
  void _replayIntro() {
    final useVideo = pwaHeroUseVideo(
      isWeb: kIsWeb,
      reduceMotion: MediaQuery.of(context).disableAnimations,
    );
    final old = _seq;
    setState(() => _seq = _buildSequence(useVideo: useVideo));
    old?.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _seq?.onVisible();
    } else {
      _seq?.onHidden();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _seq?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pwaControllerProvider);
    // Deduplicated by identity, most recent first — the same filtered library
    // the projects screen uses, so the two can never disagree.
    final seen = <String>{};
    final projects = [
      for (final p in state.visibleProjects)
        if (seen.add(p.projectId)) p,
    ].take(kPwaHomeProjectCount).toList();

    return Material(
      key: const ValueKey('pwa-home'),
      color: av7DarkBg,
      child: LayoutBuilder(
        builder: (context, c) {
          final mobile = c.maxWidth < 700;
          final pad = mobile ? 16.0 : 40.0;
          return Column(
            children: [
              _HomeBar(
                mobile: mobile,
                onProjects: _c.openLibrary,
                onNew: _c.newProject,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(pad, pad * 0.6, pad, 48),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AnimatedBuilder(
                            animation: _seq!,
                            builder: (context, _) => _HomeHero(
                              seq: _seq!,
                              media: _heroMedia,
                              mobile: mobile,
                              onNew: _c.newProject,
                              onHowItWorks: _replayIntro,
                            ),
                          ),
                          if (projects.isNotEmpty) ...[
                            SizedBox(height: mobile ? 32 : 46),
                            _ContinueDesigning(
                              projects: projects,
                              mobile: mobile,
                              columns: c.maxWidth >= 1000 ? 3 : 2,
                              onOpen: _c.openProject,
                              onViewAll: _c.openLibrary,
                            ),
                          ],
                          SizedBox(height: mobile ? 34 : 52),
                          _NewProjectBlock(
                            mobile: mobile,
                            firstProject: projects.isEmpty,
                            onNew: _c.newProject,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Top bar ──────────────────────────────────────────────────────────────────

class _HomeBar extends StatelessWidget {
  const _HomeBar({
    required this.mobile,
    required this.onProjects,
    required this.onNew,
  });
  final bool mobile;
  final VoidCallback onProjects;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('pwa-home-bar'),
      height: mobile ? 64 : 76,
      padding: EdgeInsets.symmetric(horizontal: mobile ? 16 : 36),
      decoration: const BoxDecoration(
        color: av7HeaderBlack,
        border: Border(bottom: BorderSide(color: Color(0x29D3B064))),
      ),
      child: Row(
        children: [
          const PwaLogoBadge(size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Ayden Studio',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: av7Sans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: av7OnDark,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const PwaLanguageSwitcher(onDark: true, compact: true),
          const SizedBox(width: 10),
          _BarAction(
            icon: Icons.grid_view_rounded,
            label: context.pwaL10n.myProjects,
            showLabel: !mobile,
            onTap: onProjects,
          ),
          const SizedBox(width: 10),
          _NewProjectButton(
            compact: mobile,
            onTap: onNew,
            buttonKey: const ValueKey('pwa-home-new-project'),
          ),
        ],
      ),
    );
  }
}

class _BarAction extends StatelessWidget {
  const _BarAction({
    required this.icon,
    required this.label,
    required this.showLabel,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: showLabel ? 10 : 8,
                vertical: 8,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 17, color: av7OnDarkSoft),
                  if (showLabel) ...[
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: av7Sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: av7OnDarkSoft,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewProjectButton extends StatelessWidget {
  const _NewProjectButton({
    required this.compact,
    required this.onTap,
    required this.buttonKey,
    this.large = false,
  });
  final bool compact;
  final VoidCallback onTap;
  final Key buttonKey;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.pwaL10n.newProjectAction,
      child: Tooltip(
        message: context.pwaL10n.newProjectAction,
        child: Material(
          color: av7Gold,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            key: buttonKey,
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: large ? 26 : (compact ? 10 : 18),
                vertical: large ? 15 : (compact ? 8 : 11),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_rounded,
                    size: large ? 20 : 18,
                    color: av7DarkBg,
                  ),
                  if (!compact || large) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        context.pwaL10n.newProjectAction,
                        // Text expansion: "Nouveau projet" and គម្រោង​ថ្មី are
                        // both wider than "New Project". Flexible + ellipsis
                        // keeps the pill from overflowing its row instead of
                        // shortening the meaning to fit the geometry.
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: av7Sans(
                          fontSize: large ? 15 : 13.5,
                          fontWeight: FontWeight.w700,
                          color: av7DarkBg,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Hero ─────────────────────────────────────────────────────────────────────

/// The brand hero: an empty room becoming a Warm Modern interior. It sells the
/// promise; it never shows a project, so the dashboard reads as a home page
/// rather than a second library.
class _HomeHero extends StatelessWidget {
  const _HomeHero({
    required this.seq,
    required this.media,
    required this.mobile,
    required this.onNew,
    required this.onHowItWorks,
  });
  final PwaHeroSequence seq;
  final PwaHeroMedia media;
  final bool mobile;
  final VoidCallback onNew;
  final VoidCallback onHowItWorks;

  @override
  Widget build(BuildContext context) {
    final videoSupported = seq.video?.isSupported ?? false;
    final showVideo = seq.phase == PwaHeroPhase.transform && videoSupported;
    // The poster is on screen from frame 0; the video only ever cross-fades in
    // over it, so the hero never blocks and never flashes.
    final posterUrl = seq.phase == PwaHeroPhase.promise
        ? media.endPoster
        : media.startPoster;

    return SizedBox(
      key: const ValueKey('pwa-home-hero'),
      height: mobile ? 340 : 460,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(mobile ? 16 : 22),
        child: ColoredBox(
          color: pwaCharcoal,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                posterUrl,
                fit: BoxFit.cover,
                alignment: media.posterAlignment,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const ColoredBox(color: pwaCharcoal),
              ),
              if (videoSupported)
                AnimatedOpacity(
                  opacity: showVideo ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: seq.video!.buildView(),
                ),
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomLeft,
                      end: Alignment(0.4, -0.2),
                      colors: [Color(0xE6000000), Color(0x00000000)],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: mobile ? 20 : 40,
                right: mobile ? 20 : 40,
                bottom: mobile ? 22 : 36,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: context.pwaL10n.heroLead,
                            style: pwaDisplay(
                              fontSize: mobile ? 30 : 46,
                              color: pwaOnDark,
                              height: 1.05,
                            ),
                          ),
                          TextSpan(
                            text: context.pwaL10n.heroAccent,
                            style: pwaDisplay(
                              fontSize: mobile ? 30 : 46,
                              color: pwaGold,
                              height: 1.05,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: mobile ? 10 : 14),
                    Text(
                      context.pwaL10n.heroSub,
                      style: pwaSans(
                        fontSize: mobile ? 13.5 : 15.5,
                        color: pwaOnDark.withValues(alpha: 0.82),
                        height: 1.45,
                      ),
                    ),
                    SizedBox(height: mobile ? 18 : 24),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _NewProjectButton(
                          compact: false,
                          onTap: onNew,
                          buttonKey: const ValueKey('pwa-hero-new-project'),
                        ),
                        _GhostCta(
                          label: context.pwaL10n.seeHowItWorks,
                          onTap: onHowItWorks,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GhostCta extends StatelessWidget {
  const _GhostCta({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          // Kept as the intro-replay control: same behaviour, clearer promise.
          key: const ValueKey('pwa-replay-intro'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: pwaGold.withValues(alpha: 0.7)),
            ),
            child: Text(
              label,
              maxLines: 1,
              style: pwaSans(
                fontSize: 13.5,
                color: pwaGoldSoft,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Continue designing ───────────────────────────────────────────────────────

class _ContinueDesigning extends StatelessWidget {
  const _ContinueDesigning({
    required this.projects,
    required this.mobile,
    required this.columns,
    required this.onOpen,
    required this.onViewAll,
  });
  final List<PwaProjectSnapshot> projects;
  final bool mobile;
  final int columns;
  final ValueChanged<String> onOpen;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('pwa-home-continue'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.pwaL10n.continueDesigningEyebrow,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: av7Eyebrow(fontSize: 11, letterSpacing: 2.2),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.pwaL10n.pickUpWhereYouLeftOff,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: av7Sans(
                      fontSize: mobile ? 17 : 21,
                      fontWeight: FontWeight.w600,
                      color: av7OnDark,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Semantics(
              button: true,
              label: context.pwaL10n.viewAllProjects,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  key: const ValueKey('pwa-home-view-all'),
                  onTap: onViewAll,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Text(
                      mobile
                          ? context.pwaL10n.filterAll
                          : context.pwaL10n.viewAllProjects,
                      maxLines: 1,
                      style: av7Sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: av7Gold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: mobile ? 14 : 18),
        if (mobile)
          // Same gesture as the app: a horizontal carousel.
          SizedBox(
            height: 232,
            child: ListView.separated(
              key: const ValueKey('pwa-home-carousel'),
              scrollDirection: Axis.horizontal,
              primary: false,
              physics: const ClampingScrollPhysics(),
              itemCount: projects.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => SizedBox(
                width: 250,
                child: _ProjectCard(
                  project: projects[i],
                  // In the carousel the row height is fixed, so the cover takes
                  // whatever the caption leaves — it can never overflow.
                  flexibleCover: true,
                  onTap: () => onOpen(projects[i].projectId),
                ),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, c) {
              const gap = 18.0;
              final w = (c.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final p in projects)
                    SizedBox(
                      width: w,
                      child: _ProjectCard(
                        project: p,
                        onTap: () => onOpen(p.projectId),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.onTap,
    this.flexibleCover = false,
  });
  final PwaProjectSnapshot project;
  final VoidCallback onTap;

  /// True inside a fixed-height row: the cover flexes instead of imposing an
  /// aspect the row cannot honour.
  final bool flexibleCover;

  @override
  Widget build(BuildContext context) {
    final cover = project.coverVision;
    final n = project.visions.length;
    final meta = <String>[
      if (project.atmosphereLabel.isNotEmpty) project.atmosphereLabel,
      context.pwaL10n.visionCount(n),
    ].join('  ·  ');

    return Semantics(
      button: true,
      label: context.pwaL10n.openNamed(project.title),
      child: Material(
        color: av7Reveal,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: flexibleCover ? MainAxisSize.max : MainAxisSize.min,
              children: [
                if (flexibleCover)
                  Expanded(child: _cover(cover))
                else
                  AspectRatio(aspectRatio: 16 / 10, child: _cover(cover)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        project.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: av7Sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: av7OnDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: av7Sans(fontSize: 12.5, color: av7OnDarkSoft),
                      ),
                      if (project.updatedLabel.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          // Rendered from the TIMESTAMP, not from the label
                          // baked in at deserialisation — that one is English
                          // whatever the reader's language is.
                          context.pwaL10n.updatedLabelFor(
                            project.updatedAt,
                            project.updatedLabel,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: av7Sans(fontSize: 11.5, color: av7MutedSoft),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The project cover — the generated image of its cover vision, resolved from
/// its durable Storage path. A calm placeholder when there is none, never a
/// stand-in photo of a different room.
Widget _cover(PwaVision? cover) => cover == null
    ? const ColoredBox(color: av7RevealRaised)
    : PwaStoredImage(
        key: ValueKey('cover-${cover.versionId}'),
        reference: cover.afterAsset,
        placeholderColor: av7RevealRaised,
      );

// ── Closing call to action ───────────────────────────────────────────────────

class _NewProjectBlock extends StatelessWidget {
  const _NewProjectBlock({
    required this.mobile,
    required this.firstProject,
    required this.onNew,
  });
  final bool mobile;

  /// True when the user owns nothing yet: the block becomes the empty state.
  final bool firstProject;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: firstProject
          ? const ValueKey('pwa-home-empty')
          : const ValueKey('pwa-home-new-block'),
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: mobile ? 30 : 40),
      decoration: BoxDecoration(
        color: av7Reveal,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: av7Gold.withValues(alpha: 0.20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            firstProject
                ? context.pwaL10n.createFirstVisionTitle
                : context.pwaL10n.readyToImagine,
            textAlign: TextAlign.center,
            style: av7Sans(
              fontSize: mobile ? 19 : 23,
              fontWeight: FontWeight.w600,
              color: av7OnDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            firstProject
                ? context.pwaL10n.onePhotoIsAll
                : context.pwaL10n.startANewProject,
            textAlign: TextAlign.center,
            style: av7Sans(fontSize: 14, color: av7OnDarkSoft, height: 1.45),
          ),
          SizedBox(height: mobile ? 20 : 24),
          _NewProjectButton(
            compact: false,
            large: true,
            onTap: onNew,
            buttonKey: const ValueKey('pwa-home-new-project-large'),
          ),
        ],
      ),
    );
  }
}
