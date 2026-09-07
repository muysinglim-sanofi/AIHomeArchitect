/// HOME, aligned to iOS. Phase 2.
///
/// The composition iOS uses, in iOS's order, with one deliberate divergence.
///
///     wordmark + calm actions
///     "Reimagine / your home."          displayEditorial 27
///     Featured Vision                   a real before/after, 45% of height
///     + New Design Session              sticky, above the nav
///     Home · Projects · Profile         the Phase 1 shell
///
/// THE DIVERGENCE, and why it is the point
/// ---------------------------------------
/// iOS fills its hero from `featuredShowcase` — a curated marketing list, the
/// same three rooms for everybody, forever. On the web that would be a worse
/// product: a returning customer would open Home and see a stranger's
/// apartment instead of the room they were working on last night.
///
/// So the hero prefers the person's OWN most recent finished project, and falls
/// back to the shared showcase only when there is nothing of theirs to show.
/// Same composition, same geometry, truthful content.
///
/// WHAT WAS REMOVED, and why that is a fix rather than a loss
/// ----------------------------------------------------------
/// The old Home had THREE competing blocks: a stock hero with two CTAs, a
/// "Continue designing" grid, and a second full-width "New project" panel. Two
/// of them said the same thing and the third duplicated Projects.
///
/// Now the Featured Vision IS the continuation — tapping it reopens that
/// project — and "See all" goes to Projects. One hero, one CTA, one nav.
/// That is also what makes the iOS vertical rhythm reachable on a phone:
/// headline, hero, CTA, nav, no scrolling required to reach the action.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/mock/mock_projects.dart' show featuredShowcase;
import '../../../shared/widgets/reveal_hero.dart';
import '../application/pwa_controller.dart';
import '../application/pwa_layout.dart';
import '../domain/pwa_models.dart' show PwaProject;
import '../domain/pwa_project.dart';
import '../l10n/pwa_l10n.dart';
import 'pwa_account_chip.dart';
import 'pwa_brand.dart';
import 'pwa_home_screen.dart' show kPwaGenericRoomLabel;
import 'pwa_language_switcher.dart';
import 'pwa_nav_shell.dart';
import 'pwa_primitives.dart';
import 'pwa_scaffold.dart';
import 'pwa_theme.dart';
import 'pwa_type.dart';
import 'pwa_widgets.dart' show pwaAfterImage, pwaBeforeImage, pwaRoomDisplayLabel;

class PwaHomeIos extends ConsumerWidget {
  const PwaHomeIos({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.pwaL10n;
    final state = ref.watch(pwaControllerProvider);
    final controller = ref.read(pwaControllerProvider.notifier);

    // TWO DATA SOURCES, never one. The hero is the curated Ayden showcase —
    // iOS fills its hero from `featuredShowcase` and nothing else — and the
    // person's own work is "Continue Designing", fed by `visibleProjects`
    // (deduplicated, most recent first, the same list Projects shows).
    //
    // The previous rule, `featured = visibleProjects.first`, is SUPERSEDED.
    // It is why the hero turned into whatever room had just been generated
    // when the person came back from a session: a new project sorts first,
    // so it displaced the approved Before/After. Opening a project, coming
    // back, signing in, hydrating a library, signing out — all of those may
    // reorder Continue Designing; none of them may touch the hero.
    final recent = state.visibleProjects.take(3).toList();
    final columnWidth = pwaHomeColumnWidth(MediaQuery.sizeOf(context).width);

    return PwaNavShell(
      key: const ValueKey('pwa-home'),
      current: PwaNavDestination.home,
      onSelect: (d) {
        switch (d) {
          case PwaNavDestination.home:
            break; // already here
          case PwaNavDestination.projects:
            controller.openLibrary();
          case PwaNavDestination.profile:
            controller.openProfile();
        }
      },
      child: PwaScreen(
        // The nav owns the bottom inset; the footer sits directly above it.
        bottom: false,
        // The footer is the scaffold's, so it sits OUTSIDE the column below
        // and has to be bounded on its own — otherwise the button runs the
        // full width of the monitor under a 900-wide composition.
        footer: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: columnWidth),
            child: PwaPrimaryButton(
              key: const ValueKey('pwa-home-new-session'),
              label: l.newDesignSession,
              icon: Icons.add,
              onPressed: controller.newProject,
            ),
          ),
        ),
        // Home ran to both edges of a monitor while Projects and Profile were
        // already bounded. A single composition — a headline, one picture, one
        // button — spread across 1920 stops being a composition; and the
        // ceiling is narrower than the Projects grid's for the same reason
        // Profile's is: a grid EARNS width by fitting more work into it, and
        // this screen has exactly one thing to show.
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: columnWidth),
            child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _HomeHeader()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    PwaGap.page, PwaGap.md, PwaGap.page, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.homeHeadline,
                      // Two lines on iOS ("Reimagine / your home."). The
                      // dictionary supplies the break; Khmer and French are
                      // longer and wrap on their own, so maxLines is 3 here
                      // where iOS can afford 2.
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: PwaType.homeHeadline(),
                    ),
                    const SizedBox(height: PwaGap.md),
                    const _FeaturedVision(
                      key: ValueKey('pwa-home-hero'),
                      // Always the showcase (see above). The project branch
                      // of `_FeaturedVision` is kept only so the widget's
                      // contract is unchanged; Home never feeds it one.
                      project: null,
                    ),
                  ],
                ),
              ),
            ),
            // Home showed ONE vision and offered no way to reach the rest, so
            // someone with two sessions saw half their work and no door to the
            // other half. This is not the old dashboard returning: it is a
            // short rail of the most recent sessions and a way through to
            // Projects, which owns the full library.
            if (recent.isNotEmpty)
              SliverToBoxAdapter(
                child: _RecentSessions(
                  key: const ValueKey('pwa-home-recent'),
                  projects: recent,
                  onOpen: controller.openProject,
                  onSeeAll: controller.openLibrary,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: PwaGap.lg)),
          ],
            ),
          ),
        ),
      ),
    );
  }
}

/// iOS's own numbers for this exact rail, read off `home_screen.dart`: a 168
/// wide by 214 tall card, separated by 10, inside the page padding so the next
/// card peeks past the edge. Not derived, not approximated — the same strip.
const double kPwaRecentCardW = 168;
const double kPwaRecentCardH = 214;

/// The most recent sessions after the hero — a rail, not a second Projects.
///
/// Every value on a card comes from the SAME canonical derivation Projects
/// uses: `visibleProjects` for existence and order, `coverVision` for the
/// picture, `pwaAfterImage` to resolve it, `pwaRoomDisplayLabel` for the room
/// in the reader's language, the denormalised atmosphere label, and
/// `updatedLabelFor` for recency. There is no second source of truth here, so
/// the two screens cannot drift.
class _RecentSessions extends StatelessWidget {
  const _RecentSessions({
    super.key,
    required this.projects,
    required this.onOpen,
    required this.onSeeAll,
  });

  final List<PwaProjectSnapshot> projects;
  final void Function(String projectId) onOpen;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: PwaGap.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: PwaGap.page),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  // iOS's own header for this rail, from the frozen shared
                  // dictionary and already approved in all three languages.
                  // It names the ACTION rather than the objects — "Continue
                  // Designing", not "Recent redesigns" — which is the whole
                  // reason the section is on Home at all.
                  l.continueDesigning,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PwaType.sectionTitle(),
                ),
              ),
              const SizedBox(width: PwaGap.sm),
              TextButton(
                key: const ValueKey('pwa-home-see-all'),
                onPressed: onSeeAll,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                // Gold, as on iOS: it is the one thing here that leaves.
                child: Text(
                  l.seeAll,
                  style: PwaType.body(color: pwaGold)
                      .copyWith(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: PwaGap.sm),
        SizedBox(
          height: kPwaRecentCardH,
          child: ListView.separated(
            key: const ValueKey('pwa-home-recent-rail'),
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: PwaGap.page),
            itemCount: projects.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => _RecentCard(
              project: projects[i],
              onTap: () => onOpen(projects[i].projectId),
            ),
          ),
        ),
      ],
    );
  }
}

/// A recent session at a glance: the render, the room, the direction, when.
class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.project, required this.onTap});

  final PwaProjectSnapshot project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    final cover = project.coverVision;
    // The stored sentinel is deliberately un-localised English; printing it
    // would put "Your space" at the top of a Khmer card. Projects makes the
    // same substitution, through the same resolver.
    final title = project.roomLabel == kPwaGenericRoomLabel
        ? project.title
        : pwaRoomDisplayLabel(l,
            roomId: project.roomId, roomLabel: project.roomLabel);
    final meta = [
      if (project.atmosphereLabel.isNotEmpty) project.atmosphereLabel,
      l.updatedLabelFor(project.updatedAt, project.updatedLabel),
    ].where((s) => s.isNotEmpty).join(' · ');

    return Semantics(
      button: true,
      label: l.openNamed(title),
      child: SizedBox(
        width: kPwaRecentCardW,
        child: Material(
          color: pwaWell,
          borderRadius: BorderRadius.circular(PwaGap.radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('pwa-home-recent-${project.projectId}'),
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (cover != null)
                  pwaAfterImage(cover)
                else
                  const ColoredBox(
                    color: pwaWell,
                    child: Center(
                      child: Icon(Icons.image_outlined,
                          color: pwaFaint, size: 24),
                    ),
                  ),
                // The foot carries the type, so it needs its own ground: a
                // render can be any brightness and white on a pale kitchen is
                // not readable.
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 72,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xCC000000)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // The Projects card's own type, to the letter, so a
                        // session looks like itself on both screens.
                        style: PwaType.cardSubtitle(color: Colors.white)
                            .copyWith(
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.1),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PwaType.caption(
                            color: Colors.white.withValues(alpha: 0.78),
                          ),
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

/// The calm top bar. Wordmark, language, identity — and nothing else.
///
/// iOS puts a Premium pill here. It is deliberately NOT reproduced: on iOS that
/// pill opens an Apple/RevenueCat subscription, and the web sells one-time ABA
/// credit packs through a different surface with different semantics. Copying
/// the badge would be copying the appearance of a feature the web does not
/// have — which is the opposite of the parity being asked for. The identity
/// chip already carries the state a web visitor actually has.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          PwaGap.page, PwaGap.sm, PwaGap.page, 0),
      child: Row(
        children: [
          const PwaLogoBadge(size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Ayden Studio',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PwaType.cardTitle(),
            ),
          ),
          const PwaLanguageSwitcher(compact: true),
          const PwaAccountChip(),
        ],
      ),
    );
  }
}

/// The hero: a real before/after, or the shared showcase when there is nothing
/// of the person's own to show yet.
/// How wide Home's single column may become.
///
/// The product's shared ceiling (`pwaMaxContentWidth`) first — so Home widens
/// exactly as far as the rest of the web app is allowed to — then narrower
/// still, because this screen is one picture and one sentence. 900 keeps the
/// Featured Vision near a natural landscape proportion at any desktop size; a
/// phone is unchanged and full-bleed.
double pwaHomeColumnWidth(double screenWidth) {
  final ceiling = pwaMaxContentWidth(pwaFormFactorForWidth(screenWidth));
  const composition = 900.0;
  final bounded = ceiling < screenWidth ? ceiling : screenWidth;
  return bounded < composition ? bounded : composition;
}

class _FeaturedVision extends StatelessWidget {
  const _FeaturedVision({super.key, required this.project});

  /// The person's most recent finished project, or null for a first-time
  /// visitor.
  final PwaProjectSnapshot? project;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;

    // iOS: height * 0.45, clamped [260, 460]. Copied rather than re-derived —
    // the proportion is what makes the hero dominant without pushing the CTA
    // off a small phone.
    //
    // That is a PHONE rule: it ties the picture to the height of the window,
    // which is right when width is the scarce dimension and wrong when it is
    // not. Bounded to a column on a desktop it produced a 3.4:1 letterbox —
    // the same mistake the Full Reveal made in Phase 6, and the same fix: away
    // from a phone the hero takes its height from its OWN width, so it stays a
    // landscape composition instead of a banner. Phone geometry is untouched.
    final size = MediaQuery.sizeOf(context);
    final form = pwaFormFactorForWidth(size.width);
    final height = form == PwaFormFactor.mobile
        ? (size.height * 0.45).clamp(260.0, 460.0)
        : (pwaHomeColumnWidth(size.width) / 1.6).clamp(320.0, 560.0);

    final p = project;
    final Widget after;
    final Widget? before;
    final String title;
    final String afterLabel;
    final String caption;

    if (p != null) {
      final vision = p.coverVision!;
      // The same descriptor shape the controller builds from a snapshot
      // (`_descriptor`). `pwaBeforeImage` needs the lineage root to decide
      // whether "before" is the uploaded photo or an earlier vision.
      final descriptor = PwaProject(
        projectId: p.projectId,
        originalAsset: p.originalImageAsset,
        title: p.title,
      );
      after = pwaAfterImage(vision);
      before = pwaBeforeImage(p.source, descriptor,
          vision: vision, versions: p.visions);
      title = p.title;
      afterLabel = p.atmosphereLabel;
      // `kPwaGenericRoomLabel` is a STORED sentinel, not copy — rows written
      // before a room was resolved carry the literal English "Your space", and
      // it is deliberately never localised so those comparisons keep working.
      // Printing it in a caption would leak an untranslated sentinel at a
      // Khmer reader, so the room is simply omitted when it is unknown and the
      // caption falls back to the atmosphere alone.
      caption = p.roomLabel == kPwaGenericRoomLabel
          ? p.atmosphereLabel
          : '${pwaRoomDisplayLabel(l, roomId: p.roomId, roomLabel: p.roomLabel)}'
              ' · ${p.atmosphereLabel}';
    } else {
      // The SAME curated list iOS's hero uses — genuine before/after pairs with
      // real room and style labels, not two unrelated photographs.
      final showcase = featuredShowcase.first;
      after = Image.asset(showcase.afterImageUrl!, fit: BoxFit.cover);
      before = Image.asset(showcase.beforeImageUrl!, fit: BoxFit.cover);
      title = showcase.title;
      afterLabel = showcase.style;
      caption = '${showcase.roomType} · ${showcase.style}';
    }

    final hero = ClipRRect(
      borderRadius: BorderRadius.circular(PwaGap.radiusLg), // 24, as iOS
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: RevealHero(
          key: ValueKey('home-hero-${p?.projectId ?? 'showcase'}'),
          afterImage: after,
          beforeImage: before,
          initialFraction: 0.30,
          autoSweep: true,
          // THE Safari fix, and it is iOS's own choice: only the handle strip
          // takes the drag. A full-surface drag would fight the page scroll on
          // a touch screen, and the compare would win — leaving the page stuck.
          dragMode: RevealDragMode.handle,
          beforeLabel: l.beforeLabel,
          afterLabel: afterLabel,
          overlay: _HeroOverlay(label: l.featuredVision, title: title),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tapping the hero returns to that project — which is what makes a
        // separate "Continue designing" grid unnecessary.
        // The curated hero is not a door into anyone's project; the person's
        // own work opens from Continue Designing below.
        KeyedSubtree(key: const ValueKey('pwa-home-showcase'), child: hero),
        const SizedBox(height: PwaGap.sm),
        Text(caption, style: PwaType.bodyMuted()),
      ],
    );
  }
}

/// The editorial caption over the hero scrim — eyebrow, then the room's name.
/// iOS `_HeroOverlay`: bodySmall at 65% white, then atmosphereTitle 19/w600.
class _HeroOverlay extends StatelessWidget {
  const _HeroOverlay({required this.label, required this.title});

  final String label;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 36, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: PwaType.caption(
              color: AppColors.surface.withValues(alpha: 0.65),
            ).copyWith(letterSpacing: 0.3),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PwaType.atmosphereTitle(
              fontSize: 19,
              color: AppColors.surface,
            ).copyWith(height: 1.1),
          ),
        ],
      ),
    );
  }
}
