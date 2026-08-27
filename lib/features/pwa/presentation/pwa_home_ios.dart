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
import 'pwa_widgets.dart' show pwaAfterImage, pwaBeforeImage;

class PwaHomeIos extends ConsumerWidget {
  const PwaHomeIos({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.pwaL10n;
    final state = ref.watch(pwaControllerProvider);
    final controller = ref.read(pwaControllerProvider.notifier);

    // `visibleProjects` already guarantees what a Featured Vision needs — at
    // least one vision AND a project-owned cover — and is deduplicated, most
    // recent first. Reusing it means Home and Projects can never disagree
    // about what exists, and no new state or endpoint was required.
    final featured = state.visibleProjects.isEmpty
        ? null
        : state.visibleProjects.first;

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
            break; // no screen yet — the shell renders it inert
        }
      },
      child: PwaScreen(
        // The nav owns the bottom inset; the footer sits directly above it.
        bottom: false,
        footer: PwaPrimaryButton(
          key: const ValueKey('pwa-home-new-session'),
          label: l.newDesignSession,
          icon: Icons.add,
          onPressed: controller.newProject,
        ),
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
                    _FeaturedVision(
                      key: const ValueKey('pwa-home-hero'),
                      project: featured,
                      onOpen: featured == null
                          ? null
                          : () => controller.openProject(featured.projectId),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: PwaGap.lg)),
          ],
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
class _FeaturedVision extends StatelessWidget {
  const _FeaturedVision({super.key, required this.project, this.onOpen});

  /// The person's most recent finished project, or null for a first-time
  /// visitor.
  final PwaProjectSnapshot? project;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;

    // iOS: height * 0.45, clamped [260, 460]. Copied rather than re-derived —
    // the proportion is what makes the hero dominant without pushing the CTA
    // off a small phone.
    final height =
        (MediaQuery.sizeOf(context).height * 0.45).clamp(260.0, 460.0);

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
          : '${p.roomLabel} · ${p.atmosphereLabel}';
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
        if (onOpen == null)
          KeyedSubtree(
              key: const ValueKey('pwa-home-showcase'), child: hero)
        else
          Semantics(
            button: true,
            label: l.featuredVision,
            child: GestureDetector(
              key: const ValueKey('pwa-home-featured'),
              onTap: onOpen,
              behavior: HitTestBehavior.opaque,
              child: hero,
            ),
          ),
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
