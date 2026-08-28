/// PROJECTS, aligned to iOS. Phase 7.
///
/// iOS's `projects_history_screen.dart` is 111 lines and holds four things: a
/// title, a count, a grid of image-led cards, and one button. No search, no
/// sort, no introduction, no per-card metadata block. You find a project by
/// recognising the room.
///
///     Your designs                 title
///     4 redesigns                  count
///     ┌──────────┐ ┌──────────┐
///     │  the     │ │  the     │    the cover, full-bleed, scrim at the foot
///     │  render  │ │  render  │
///     │ Kitchen  │ │ Bedroom  │    room · atmosphere · updated, overlaid
///     └──────────┘ └──────────┘
///           + New Design Session
///
/// WHAT WAS REMOVED, AND WHY IT IS THE POINT
/// -----------------------------------------
/// The old screen had a header bar with its own back and New buttons, an
/// editorial introduction, a search field, a sort menu, a search-results
/// context line, a search-empty state, and cards carrying a title, a
/// room · atmosphere line and a "3 visions · updated today" line UNDER the
/// image. It read as a project database with pictures in it.
///
/// Search and sort are gone from the surface. That is the largest single
/// change and the most arguable one, so: the brief asks for a visual portfolio
/// and names "a dense project database" as the thing to avoid, and iOS — the
/// source of truth — offers neither control. `librarySearch` and `librarySort`
/// remain on the controller, untouched and still tested; the ordering they
/// produce is unchanged, because the screen simply reads `visibleProjects` as
/// it always did. Putting either control back is a few lines, and this note is
/// here so that stays true.
///
/// THE COVER IS NOT DECIDED HERE
/// -----------------------------
/// `visibleProjects` → `coverVision` → `pwaAfterImage`. The same three steps
/// Home takes, in the same order, from the same state. Home and Projects
/// cannot disagree about a project's latest vision because neither of them
/// works it out.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pwa_controller.dart';
import '../application/pwa_layout.dart';
import '../domain/pwa_project.dart';
import '../l10n/pwa_l10n.dart';
import 'pwa_home_screen.dart' show kPwaGenericRoomLabel;
import 'pwa_nav_shell.dart';
import 'pwa_primitives.dart';
import 'pwa_projects_screen.dart' show PwaProjectCardMenu;
import 'pwa_scaffold.dart';
import 'pwa_theme.dart';
import 'pwa_type.dart';
import 'pwa_widgets.dart' show pwaAfterImage, pwaRoomDisplayLabel;

/// iOS `projects_history_screen.dart`: two columns, `sm` apart, at 0.72.
///
/// The ratio is a portrait card holding a 3:2 render, so the cover IS cropped —
/// deliberately, and only here. A thumbnail grid earns its uniformity, and the
/// screens that exist to examine a render (the Result, the Full Reveal) both
/// show it whole. The crop keeps the middle of the room, which is what the eye
/// uses to recognise it.
const double kPwaProjectCardRatio = 0.72;
const double kPwaProjectGap = PwaGap.sm;

/// The web adds columns rather than metadata: the extra width shows more work.
int pwaProjectColumns(double width) {
  if (width >= 1180) return 4;
  if (width >= 860) return 3;
  return 2;
}

/// A restrained ceiling — a portfolio, not a wall of contact sheets. The value
/// is the product's own, shared with every other web surface via
/// `pwaMaxContentWidth`, so Projects widens exactly as far as Home does and no
/// further: on a 1920 monitor the grid stops, centred, instead of running to
/// both edges. Columns are counted from the CONSTRAINED width for the same
/// reason — the ceiling has to decide the layout, not merely clip it.
double pwaProjectsColumnWidth(double screenWidth) => math.min(
      screenWidth,
      pwaMaxContentWidth(pwaFormFactorForWidth(screenWidth)),
    );

class PwaProjectsIos extends ConsumerWidget {
  const PwaProjectsIos({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.pwaL10n;
    final state = ref.watch(pwaControllerProvider);
    final controller = ref.read(pwaControllerProvider.notifier);
    // THE canonical list: deduped, filtered to projects that really have a
    // vision and a cover, ordered by the controller. Read, never re-derived.
    final projects = state.visibleProjects;
    final columnWidth =
        pwaProjectsColumnWidth(MediaQuery.sizeOf(context).width);

    return PwaNavShell(
      key: const ValueKey('pwa-projects'),
      current: PwaNavDestination.projects,
      onSelect: (d) {
        switch (d) {
          case PwaNavDestination.home:
            controller.openHome();
          case PwaNavDestination.projects:
            break; // already here
          case PwaNavDestination.profile:
            break; // no screen yet — the shell renders it inert
        }
      },
      child: PwaScreen(
        // The nav owns the bottom inset.
        bottom: false,
        // One centred column. Without it the header sat against the left edge
        // of a 1440 window and the button ran the full width of the monitor.
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: columnWidth),
            child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    PwaGap.page, PwaGap.lg, PwaGap.page, PwaGap.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.historyTitle, style: PwaType.screenTitle()),
                    const SizedBox(height: 4),
                    Text(
                      '${projects.length} ${l.transformations}',
                      style: PwaType.bodyMuted(),
                    ),
                  ],
                ),
              ),
            ),
            if (projects.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(onCreate: controller.newProject),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: PwaGap.page),
                sliver: SliverGrid(
                  gridDelegate:
                      SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: pwaProjectColumns(columnWidth),
                    crossAxisSpacing: kPwaProjectGap,
                    mainAxisSpacing: kPwaProjectGap,
                    childAspectRatio: kPwaProjectCardRatio,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _ProjectCard(
                      project: projects[i],
                      // Opening a project is the controller's existing route
                      // into the session it already has. It starts nothing.
                      onTap: () =>
                          controller.openProject(projects[i].projectId),
                    ),
                    childCount: projects.length,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: PwaGap.xl)),
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: PwaGap.page),
                  child: PwaPrimaryButton(
                    key: const ValueKey('pwa-projects-new'),
                    label: l.newDesignSession,
                    icon: Icons.add,
                    onPressed: controller.newProject,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: PwaGap.xl)),
            ],
          ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One project, led by the work.
///
/// iOS `ProjectCard`: the cover full-bleed, a warm-dark scrim rising from the
/// foot, and the meta laid over it — room as the title, then the atmosphere,
/// then when it was last touched. The card carries no surface of its own
/// beyond a hairline; the picture is the card.
class _ProjectCard extends ConsumerWidget {
  const _ProjectCard({required this.project, required this.onTap});

  final PwaProjectSnapshot project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.pwaL10n;
    final cover = project.coverVision;

    // `kPwaGenericRoomLabel` is a STORED sentinel — rows written before a room
    // was resolved carry the literal English "Your space", deliberately never
    // localised so those comparisons keep working. Printing it would show an
    // untranslated English string to a Khmer reader, so the project's own
    // title stands in when the room is unknown.
    // ...and it is the room as the READER's language names it. The stored
    // value stays canonical English; `pwaRoomDisplayLabel` is display-only and
    // is the same resolver Home's caption uses, so the two cannot drift.
    final title = project.roomLabel == kPwaGenericRoomLabel
        ? project.title
        : pwaRoomDisplayLabel(l,
            roomId: project.roomId, roomLabel: project.roomLabel);

    return Semantics(
      button: true,
      label: l.openNamed(title),
      child: Material(
        color: pwaWell,
        borderRadius: BorderRadius.circular(PwaGap.radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('project-card-${project.projectId}'),
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
                        color: pwaFaint, size: 30),
                  ),
                ),

              // iOS's cinematic scrim. It is what lets the meta sit ON the
              // render at all: without it the words are a contrast bet against
              // a photograph nobody chose.
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment(0, -0.05),
                      colors: [Color(0xE60C0906), Color(0x000C0906)],
                    ),
                  ),
                ),
              ),

              if (project.visionCount > 0)
                Positioned(
                  top: 9,
                  left: 9,
                  child: _VisionsChip(l.visionCount(project.visionCount)),
                ),

              Positioned(
                top: 2,
                right: 2,
                // Rename, duplicate and delete — unchanged, and unchanged is
                // the point: this phase restyles a surface, and deleting
                // somebody's work is not a presentation decision.
                child: PwaProjectCardMenu(project: project, onDark: true),
              ),

              Positioned(
                left: 12,
                right: 40,
                bottom: 11,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PwaType.cardSubtitle(color: Colors.white)
                          .copyWith(
                              fontWeight: FontWeight.w600, letterSpacing: 0.1),
                    ),
                    if (project.atmosphereLabel.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        project.atmosphereLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PwaType.caption(
                          color: Colors.white.withValues(alpha: 0.78),
                        ),
                      ),
                    ],
                    const SizedBox(height: 3),
                    Text(
                      l.updatedLabelFor(project.updatedAt, project.updatedLabel),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PwaType.caption(
                        color: Colors.white.withValues(alpha: 0.55),
                      ).copyWith(fontSize: 10),
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

/// How many visions a project holds — the one number worth showing, because it
/// says how far the work has come rather than how it is stored.
class _VisionsChip extends StatelessWidget {
  const _VisionsChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(PwaGap.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 9, color: Colors.white),
            const SizedBox(width: 3),
            Text(
              label,
              style: PwaType.caption(color: Colors.white)
                  .copyWith(fontSize: 9, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
}

/// Nothing yet — said calmly, with the one thing worth doing.
///
/// No demo projects, no illustration panel, no feature tour. Someone who has
/// made nothing does not need a dashboard explaining what a dashboard is.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          PwaGap.page, PwaGap.xl, PwaGap.page, PwaGap.xxl),
      child: Column(
        key: const ValueKey('pwa-projects-empty'),
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.noProjects,
            textAlign: TextAlign.center,
            style: PwaType.sectionTitle(),
          ),
          const SizedBox(height: PwaGap.sm),
          Text(
            l.onePhotoIsAll,
            textAlign: TextAlign.center,
            style: PwaType.bodyMuted(),
          ),
          const SizedBox(height: PwaGap.lg),
          PwaPrimaryButton(
            key: const ValueKey('pwa-projects-empty-new'),
            label: l.newDesignSession,
            icon: Icons.add,
            onPressed: onCreate,
          ),
        ],
      ),
    );
  }
}
