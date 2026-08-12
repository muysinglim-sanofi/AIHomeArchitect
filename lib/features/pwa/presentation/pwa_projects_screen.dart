/// Batch 2.3 — My Projects library (offline, mocked).
///
/// A premium design portfolio, not a file manager: a warm near-black canvas,
/// large current-vision imagery, restrained gold, editorial type. Lists the
/// seeded + user projects, resumes one exactly where it was left, and supports
/// search, sort, rename, duplicate, delete and New project — all client-side and
/// deterministic. Reuses the isolated V7 (`av7*`) design tokens so it sits in the
/// same world as the Architect. No backend / Supabase / auth / generation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pwa_controller.dart';
import '../domain/pwa_project.dart';
import 'pwa_architect_tokens.dart';
import 'pwa_brand.dart';
import 'pwa_entry_screen.dart' show pwaRoomById;
import 'pwa_widgets.dart';
import '../l10n/pwa_l10n.dart';
import 'pwa_account_chip.dart';
import 'pwa_language_switcher.dart';

class PwaProjectsScreen extends ConsumerWidget {
  const PwaProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pwaControllerProvider);
    final c = ref.read(pwaControllerProvider.notifier);
    final w = MediaQuery.sizeOf(context).width;
    final mobile = w < 700;
    final cols = w >= 1180
        ? 3
        : w >= 720
        ? 2
        : 1;
    final pad = mobile
        ? 16.0
        : w < 1100
        ? 24.0
        : 32.0;

    final query = state.librarySearch.trim();
    final results = state.visibleProjects;
    // Step 6A — a pre-Generate creation is NOT a project: no synthetic Draft card
    // in My Projects. The grid shows only usable generated projects (results).
    const PwaProjectSnapshot? draft = null;
    final showGlobalEmpty = results.isEmpty && query.isEmpty;
    final showSearchEmpty = query.isNotEmpty && results.isEmpty;

    return Material(
      key: const ValueKey('pwa-projects'),
      color: av7DarkBg,
      child: Column(
        children: [
          _ProjectsHeader(
            mobile: mobile,
            onBack: c.returnToStudio,
            onNew: c.newProject,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(pad, mobile ? 24 : 40, pad, 48),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ProjectsIntro(mobile: mobile),
                      SizedBox(height: mobile ? 22 : 30),
                      _SearchSortBar(
                        mobile: mobile,
                        query: state.librarySearch,
                        sort: state.librarySort,
                        onSearch: c.setLibrarySearch,
                        onSort: c.setLibrarySort,
                      ),
                      if (query.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _SearchContext(
                          count: results.length,
                          query: query,
                          onClear: () => c.setLibrarySearch(''),
                        ),
                        const SizedBox(height: 16),
                      ] else
                        SizedBox(height: mobile ? 20 : 28),
                      if (showGlobalEmpty)
                        _EmptyState(onCreate: c.newProject)
                      else if (showSearchEmpty)
                        _SearchEmptyState(onClear: () => c.setLibrarySearch(''))
                      else
                        _ProjectGrid(
                          draft: draft,
                          projects: results,
                          cols: cols,
                          gap: mobile ? 16 : 24,
                          mobile: mobile,
                          onOpen: c.openProject,
                          onContinueDraft: c.returnToStudio,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

class _ProjectsHeader extends StatelessWidget {
  const _ProjectsHeader({
    required this.mobile,
    required this.onBack,
    required this.onNew,
  });
  final bool mobile;
  final VoidCallback onBack;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('pwa-projects-header'),
      height: mobile ? 60 : 72,
      padding: EdgeInsets.symmetric(horizontal: mobile ? 16 : 32),
      decoration: const BoxDecoration(
        color: av7HeaderBlack,
        border: Border(bottom: BorderSide(color: Color(0x29D3B064))),
      ),
      child: Row(
        children: [
          _HeaderTextButton(
            icon: Icons.arrow_back_rounded,
            label: context.pwaL10n.backHome,
            showLabel: !mobile,
            onTap: onBack,
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'AYDEN STUDIO',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: av7Sans(
                    fontSize: mobile ? 15 : 20,
                    color: av7OnDark,
                    letterSpacing: mobile ? 2.6 : 6.0,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  context.pwaL10n.myProjectsCaps,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: av7Eyebrow(
                    fontSize: mobile ? 8.5 : 10,
                    letterSpacing: 4.0,
                  ),
                ),
              ],
            ),
          ),
          // The selector belongs in EVERY chrome bar, not only on Home: a
          // person who lands on a deep link, or who is mid-project, must be
          // able to change language without first navigating away.
          const PwaLanguageSwitcher(onDark: true, compact: true),
          const PwaAccountChip(onDark: true),
          const SizedBox(width: 10),
          _NewProjectButton(compact: mobile, onTap: onNew),
        ],
      ),
    );
  }
}

class _HeaderTextButton extends StatelessWidget {
  const _HeaderTextButton({
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: av7OnDark),
                  if (showLabel) ...[
                    const SizedBox(width: 12),
                    Text(
                      label,
                      style: av7Sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: av7OnDark,
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
  const _NewProjectButton({required this.compact, required this.onTap});
  final bool compact;
  final VoidCallback onTap;

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
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 18,
                vertical: compact ? 8 : 10,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_rounded, size: 18, color: av7DarkBg),
                  if (!compact) ...[
                    const SizedBox(width: 8),
                    Text(
                      context.pwaL10n.newProjectAction,
                      style: av7Sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: av7DarkBg,
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

// ── Intro ────────────────────────────────────────────────────────────────────

class _ProjectsIntro extends StatelessWidget {
  const _ProjectsIntro({required this.mobile});
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.pwaL10n.yourSpaces,
          style: av7Eyebrow(fontSize: 12, letterSpacing: 2.4),
        ),
        SizedBox(height: mobile ? 10 : 14),
        Text(
          context.pwaL10n.contineShapingHome,
          style: av7Sans(
            fontSize: mobile ? 27 : 38,
            fontWeight: FontWeight.w600,
            color: av7OnDark,
            height: 1.08,
            letterSpacing: -0.4,
          ),
        ),
        SizedBox(height: mobile ? 8 : 12),
        Text(
          context.pwaL10n.returnToProject,
          style: av7Sans(
            fontSize: mobile ? 14 : 16,
            color: av7OnDarkSoft,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

// ── Search + sort ────────────────────────────────────────────────────────────

class _SearchSortBar extends StatefulWidget {
  const _SearchSortBar({
    required this.mobile,
    required this.query,
    required this.sort,
    required this.onSearch,
    required this.onSort,
  });
  final bool mobile;
  final String query;
  final PwaProjectSort sort;
  final ValueChanged<String> onSearch;
  final ValueChanged<PwaProjectSort> onSort;

  @override
  State<_SearchSortBar> createState() => _SearchSortBarState();
}

class _SearchSortBarState extends State<_SearchSortBar> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.query,
  );

  @override
  void didUpdateWidget(covariant _SearchSortBar old) {
    super.didUpdateWidget(old);
    // Keep the field in step when the query is cleared externally (Clear search).
    if (widget.query != _controller.text) _controller.text = widget.query;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = _SearchField(
      controller: _controller,
      onChanged: widget.onSearch,
    );
    final sort = _SortControl(
      mobile: widget.mobile,
      sort: widget.sort,
      onSort: widget.onSort,
    );
    if (widget.mobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [search, const SizedBox(height: 12), sort],
      );
    }
    return Row(
      children: [
        Expanded(child: search),
        const SizedBox(width: 16),
        sort,
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const ValueKey('pwa-projects-search'),
      controller: controller,
      onChanged: onChanged,
      style: av7Sans(fontSize: 15, color: av7OnDark),
      cursorColor: av7Gold,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: const Color(0xFF1A1712),
        hintText: context.pwaL10n.searchProjects,
        hintStyle: av7Sans(fontSize: 15, color: av7MutedSoft),
        prefixIcon: const Icon(Icons.search_rounded, color: av7Muted, size: 20),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0x22D3B064)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0x22D3B064)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: av7Gold),
        ),
      ),
    );
  }
}

class _SortControl extends StatelessWidget {
  const _SortControl({
    required this.mobile,
    required this.sort,
    required this.onSort,
  });
  final bool mobile;
  final PwaProjectSort sort;
  final ValueChanged<PwaProjectSort> onSort;

  Future<void> _openSheet(BuildContext context) async {
    final picked = await showModalBottomSheet<PwaProjectSort>(
      context: context,
      backgroundColor: av7CardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          key: const ValueKey('pwa-sort-sheet'),
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: av7Muted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            for (final o in PwaProjectSort.values)
              ListTile(
                title: Text(
                  context.pwaL10n.sortLabel(o),
                  style: av7Sans(
                    fontSize: 16,
                    color: o == sort ? av7Gold : av7OnDark,
                    fontWeight: o == sort ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                trailing: o == sort
                    ? const Icon(Icons.check_rounded, color: av7Gold, size: 20)
                    : null,
                onTap: () => Navigator.of(ctx).pop(o),
              ),
          ],
        ),
      ),
    );
    if (picked != null) onSort(picked);
  }

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1712),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x22D3B064)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.swap_vert_rounded, size: 18, color: av7Muted),
          const SizedBox(width: 8),
          Text(
            context.pwaL10n.sortLabel(sort),
            style: av7Sans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: av7OnDark,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more_rounded, size: 18, color: av7Muted),
        ],
      ),
    );

    if (mobile) {
      return Semantics(
        button: true,
        label: context.pwaL10n.sortProjects,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('pwa-sort-button'),
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openSheet(context),
            child: pill,
          ),
        ),
      );
    }

    return PopupMenuButton<PwaProjectSort>(
      key: const ValueKey('pwa-sort-button'),
      tooltip: context.pwaL10n.sortProjects,
      color: av7CardDark,
      onSelected: onSort,
      itemBuilder: (ctx) => [
        for (final o in PwaProjectSort.values)
          PopupMenuItem<PwaProjectSort>(
            value: o,
            child: Text(
              context.pwaL10n.sortLabel(o),
              style: av7Sans(
                fontSize: 14,
                color: o == sort ? av7Gold : av7OnDark,
                fontWeight: o == sort ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
      ],
      child: pill,
    );
  }
}

// ── Grid ─────────────────────────────────────────────────────────────────────

class _ProjectGrid extends StatelessWidget {
  const _ProjectGrid({
    required this.draft,
    required this.projects,
    required this.cols,
    required this.gap,
    required this.mobile,
    required this.onOpen,
    required this.onContinueDraft,
  });
  final PwaProjectSnapshot? draft;
  final List<PwaProjectSnapshot> projects;
  final int cols;
  final double gap;
  final bool mobile;
  final ValueChanged<String> onOpen;
  final VoidCallback onContinueDraft;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cardW = cols == 1
            ? c.maxWidth
            : (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            if (draft != null)
              SizedBox(
                width: cardW,
                child: _DraftProjectCard(
                  draft: draft!,
                  mobile: mobile,
                  onContinue: onContinueDraft,
                ),
              ),
            for (final p in projects)
              SizedBox(
                width: cardW,
                child: _ProjectCard(
                  project: p,
                  mobile: mobile,
                  onOpen: () => onOpen(p.projectId),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ProjectCard extends ConsumerStatefulWidget {
  const _ProjectCard({
    required this.project,
    required this.mobile,
    required this.onOpen,
  });
  final PwaProjectSnapshot project;
  final bool mobile;
  final VoidCallback onOpen;

  @override
  ConsumerState<_ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends ConsumerState<_ProjectCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    final cover = p.coverVision;
    final lifted = _hover && !widget.mobile;

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(0, lifted ? -4 : 0, 0),
      decoration: BoxDecoration(
        color: av7CardDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: lifted ? av7Gold : const Color(0x1FD3B064),
          width: lifted ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Color(lifted ? 0x40000000 : 0x24000000),
            blurRadius: lifted ? 26 : 16,
            offset: Offset(0, lifted ? 12 : 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: ColoredBox(
                  color: av7Reveal,
                  child: cover == null
                      ? const SizedBox.shrink()
                      : pwaAfterImage(cover),
                ),
              ),
              // Open affordance on hover (desktop).
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: lifted ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.center,
                          colors: [Color(0xB3000000), Color(0x00000000)],
                        ),
                      ),
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            context.pwaL10n.openProject,
                            style: av7Sans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: av7OnDark,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Action menu — subtle by default on desktop, brightening on
              // hover/focus; always visible on mobile. No status badge: the
              // vision count and updated date already convey maturity.
              Positioned(
                top: 5,
                right: 5,
                child: _CardMenu(project: p, hovered: lifted),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: av7Sans(
                    fontSize: widget.mobile ? 19 : 21,
                    fontWeight: FontWeight.w600,
                    color: av7OnDark,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${p.roomLabel} · ${p.atmosphereLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: av7Sans(fontSize: 13, color: av7Gold),
                ),
                const SizedBox(height: 4),
                Text(
                  '${context.pwaL10n.visionCount(p.visionCount)} · '
                  '${context.pwaL10n.updatedLabelFor(p.updatedAt, p.updatedLabel)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: av7Sans(fontSize: 12.5, color: av7Muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        button: true,
        label: context.pwaL10n.openNamed(p.title),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('project-card-${p.projectId}'),
            borderRadius: BorderRadius.circular(20),
            onTap: widget.onOpen,
            child: card,
          ),
        ),
      ),
    );
  }
}

/// The only badge that survives (§5): shown ONLY on a draft card. Warm dark
/// translucent pill, muted gold text, no glow. Normal projects carry no badge.
class _DraftBadge extends StatelessWidget {
  const _DraftBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xB30D0C0A),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x2ED3B064)),
      ),
      child: Text(
        context.pwaL10n.draftBadge,
        style: av7Sans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: av7Gold,
          height: 1.0,
        ),
      ),
    );
  }
}

// ── Card action menu (rename / duplicate / delete) ───────────────────────────

enum _CardAction { rename, duplicate, delete }

class _CardMenu extends ConsumerWidget {
  const _CardMenu({
    required this.project,
    this.hovered = false,
    this.renameOnly = false,
  });
  final PwaProjectSnapshot project;
  final bool hovered;

  /// A Draft has no meaningful Duplicate/Delete yet — show only Rename.
  final bool renameOnly;

  void _run(BuildContext context, WidgetRef ref, _CardAction action) {
    final c = ref.read(pwaControllerProvider.notifier);
    switch (action) {
      case _CardAction.rename:
        _renameDialog(context, ref);
      case _CardAction.duplicate:
        c.duplicateProject(project.projectId);
      case _CardAction.delete:
        _deleteDialog(context, ref);
    }
  }

  Future<void> _renameDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: project.title);
    final c = ref.read(pwaControllerProvider.notifier);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('pwa-rename-dialog'),
        backgroundColor: av7CardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          context.pwaL10n.renameProject,
          style: av7Sans(fontSize: 18, color: av7OnDark),
        ),
        content: TextField(
          key: const ValueKey('pwa-rename-field'),
          controller: controller,
          autofocus: true,
          style: av7Sans(fontSize: 15, color: av7OnDark),
          cursorColor: av7Gold,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF1A1712),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0x22D3B064)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: av7Gold),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              context.pwaL10n.cancel,
              style: av7Sans(fontSize: 14, color: av7Muted),
            ),
          ),
          TextButton(
            key: const ValueKey('pwa-rename-save'),
            onPressed: () {
              c.renameProject(project.projectId, controller.text);
              Navigator.of(ctx).pop();
            },
            child: Text(
              context.pwaL10n.save,
              style: av7Sans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: av7Gold,
              ),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _deleteDialog(BuildContext context, WidgetRef ref) async {
    final c = ref.read(pwaControllerProvider.notifier);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('pwa-delete-dialog'),
        backgroundColor: av7CardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          context.pwaL10n.deleteProjectTitle,
          style: av7Sans(fontSize: 18, color: av7OnDark),
        ),
        content: Text(
          context.pwaL10n.deleteProjectBody(project.title),
          style: av7Sans(fontSize: 14, color: av7OnDarkSoft, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              context.pwaL10n.cancel,
              style: av7Sans(fontSize: 14, color: av7Muted),
            ),
          ),
          TextButton(
            key: const ValueKey('pwa-delete-confirm'),
            onPressed: () {
              c.deleteProject(project.projectId);
              Navigator.of(ctx).pop();
            },
            child: Text(
              context.pwaL10n.delete,
              style: av7Sans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFE0857A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openMobileSheet(BuildContext context, WidgetRef ref) async {
    final picked = await showModalBottomSheet<_CardAction>(
      context: context,
      backgroundColor: av7CardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          key: const ValueKey('pwa-card-menu-sheet'),
          children: [
            const SizedBox(height: 10),
            Text(
              project.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: av7Sans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: av7OnDark,
              ),
            ),
            const SizedBox(height: 6),
            _sheetTile(ctx, Icons.edit_outlined, context.pwaL10n.rename, _CardAction.rename),
            if (!renameOnly) ...[
              _sheetTile(
                ctx,
                Icons.copy_all_outlined,
                context.pwaL10n.duplicate,
                _CardAction.duplicate,
              ),
              _sheetTile(
                ctx,
                Icons.delete_outline_rounded,
                context.pwaL10n.delete,
                _CardAction.delete,
                danger: true,
              ),
            ],
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (picked != null && context.mounted) _run(context, ref, picked);
  }

  Widget _sheetTile(
    BuildContext ctx,
    IconData icon,
    String label,
    _CardAction action, {
    bool danger = false,
  }) {
    final color = danger ? const Color(0xFFE0857A) : av7OnDark;
    return ListTile(
      leading: Icon(icon, color: color, size: 20),
      title: Text(label, style: av7Sans(fontSize: 15, color: color)),
      onTap: () => Navigator.of(ctx).pop(action),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mobile = MediaQuery.sizeOf(context).width < 700;
    // Small visible disc inside a 44×44 interaction target. Desktop: subtle by
    // default (0.60), full on hover/card-focus. Mobile: always fully visible.
    final opacity = mobile ? 1.0 : (hovered ? 1.0 : 0.60);
    final disc = Container(
      width: 33,
      height: 33,
      decoration: BoxDecoration(
        color: const Color(0x8C141210), // rgba(20,18,16,0.55)
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0x1FFFFDFC)),
      ),
      child: const Icon(Icons.more_vert_rounded, size: 17, color: av7OnDark),
    );
    final target = SizedBox(width: 44, height: 44, child: Center(child: disc));

    if (mobile) {
      return Semantics(
        button: true,
        label: context.pwaL10n.projectOptions,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('project-menu-${project.projectId}'),
            onTap: () => _openMobileSheet(context, ref),
            child: target,
          ),
        ),
      );
    }

    return AnimatedOpacity(
      opacity: opacity,
      duration: const Duration(milliseconds: 200),
      child: PopupMenuButton<_CardAction>(
        key: ValueKey('project-menu-${project.projectId}'),
        tooltip: context.pwaL10n.projectOptions,
        color: av7CardDark,
        padding: EdgeInsets.zero,
        onSelected: (a) => _run(context, ref, a),
        itemBuilder: (ctx) => [
          _menuItem(_CardAction.rename, Icons.edit_outlined, context.pwaL10n.rename),
          if (!renameOnly) ...[
            _menuItem(
              _CardAction.duplicate,
              Icons.copy_all_outlined,
              context.pwaL10n.duplicate,
            ),
            _menuItem(
              _CardAction.delete,
              Icons.delete_outline_rounded,
              context.pwaL10n.delete,
              danger: true,
            ),
          ],
        ],
        child: target,
      ),
    );
  }

  PopupMenuItem<_CardAction> _menuItem(
    _CardAction action,
    IconData icon,
    String label, {
    bool danger = false,
  }) {
    final color = danger ? const Color(0xFFE0857A) : av7OnDark;
    return PopupMenuItem<_CardAction>(
      value: action,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Text(label, style: av7Sans(fontSize: 14, color: color)),
        ],
      ),
    );
  }
}

// ── Empty / no-results ───────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('pwa-projects-empty'),
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
      decoration: BoxDecoration(
        color: av7CardDark,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x1FD3B064)),
      ),
      child: Column(
        children: [
          const PwaLogoBadge(size: 56),
          const SizedBox(height: 24),
          Text(
            context.pwaL10n.yourNextSpace,
            textAlign: TextAlign.center,
            style: av7Sans(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: av7OnDark,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            context.pwaL10n.uploadAndCreate,
            textAlign: TextAlign.center,
            style: av7Sans(fontSize: 15, color: av7OnDarkSoft, height: 1.45),
          ),
          const SizedBox(height: 28),
          _NewProjectButton(compact: false, onTap: onCreate),
        ],
      ),
    );
  }
}

/// §8 — search-specific empty state (NOT the global empty-library state): never
/// invites "Create a project" when the library merely has no match.
class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({required this.onClear});
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('pwa-projects-search-empty'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 56),
      decoration: BoxDecoration(
        color: av7CardDark,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x1FD3B064)),
      ),
      child: Column(
        children: [
          Text(
            context.pwaL10n.noMatchingProjects,
            textAlign: TextAlign.center,
            style: av7Sans(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: av7OnDark,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            context.pwaL10n.tryAnotherRoom,
            textAlign: TextAlign.center,
            style: av7Sans(fontSize: 15, color: av7OnDarkSoft, height: 1.45),
          ),
          const SizedBox(height: 22),
          _ClearSearchButton(onClear: onClear, filled: true),
        ],
      ),
    );
  }
}

/// §7 — compact result-context row between search controls and the grid.
class _SearchContext extends StatelessWidget {
  const _SearchContext({
    required this.count,
    required this.query,
    required this.onClear,
  });
  final int count;
  final String query;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final prefix = count == 0
        ? context.pwaL10n.noProjectsFoundFor
        : count == 1
        ? context.pwaL10n.oneProjectFoundFor
        : context.pwaL10n.nProjectsFoundFor(count);
    return Row(
      key: const ValueKey('pwa-search-context'),
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: prefix),
                TextSpan(
                  text: '“$query”',
                  style: av7Sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: av7Gold,
                  ),
                ),
              ],
              style: av7Sans(fontSize: 13, color: av7OnDarkSoft),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        _ClearSearchButton(onClear: onClear),
      ],
    );
  }
}

class _ClearSearchButton extends StatelessWidget {
  const _ClearSearchButton({required this.onClear, this.filled = false});
  final VoidCallback onClear;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.pwaL10n.clearSearch,
      child: Material(
        color: filled ? const Color(0x1FD3B064) : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          key: const ValueKey('pwa-clear-search'),
          onTap: onClear,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: filled ? 18 : 10),
            child: Text(
              context.pwaL10n.clearSearch,
              style: av7Sans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: av7Gold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Draft card (§4) — active session with a photo but no vision yet ──────────

class _DraftProjectCard extends StatefulWidget {
  const _DraftProjectCard({
    required this.draft,
    required this.mobile,
    required this.onContinue,
  });
  final PwaProjectSnapshot draft;
  final bool mobile;
  final VoidCallback onContinue;

  @override
  State<_DraftProjectCard> createState() => _DraftProjectCardState();
}

class _DraftProjectCardState extends State<_DraftProjectCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final lifted = _hover && !widget.mobile;
    // Display only — the draft's routed room id is untouched.
    final card0 = pwaRoomById(d.roomId);
    final roomLabel = card0 == null
        ? context.pwaL10n.uplAiDecide
        : context.pwaL10n.roomCardLabel(card0.id, card0.label);
    final bytes = d.source?.bytes;

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(0, lifted ? -4 : 0, 0),
      decoration: BoxDecoration(
        color: av7CardDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: lifted ? av7Gold : const Color(0x1FD3B064),
          width: lifted ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: ColoredBox(
                  color: av7Reveal,
                  child: bytes == null
                      ? const Center(
                          child: Icon(
                            Icons.add_photo_alternate_outlined,
                            color: av7Muted,
                            size: 34,
                          ),
                        )
                      : Image.memory(
                          bytes,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const ColoredBox(color: av7Reveal),
                        ),
                ),
              ),
              const Positioned(top: 12, left: 12, child: _DraftBadge()),
              // Rename is reachable on the Draft via the SAME card menu (rename
              // only — Duplicate/Delete are meaningless before the first Vision).
              Positioned(
                top: 5,
                right: 5,
                child: _CardMenu(
                  project: widget.draft,
                  hovered: lifted,
                  renameOnly: true,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.title, // "Untitled Space"
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: av7Sans(
                    fontSize: widget.mobile ? 19 : 21,
                    fontWeight: FontWeight.w600,
                    color: av7OnDark,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$roomLabel · ${d.atmosphereLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: av7Sans(fontSize: 13, color: av7Gold),
                ),
                const SizedBox(height: 4),
                Text(
                  context.pwaL10n.draftContinueSetup,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: av7Sans(fontSize: 12.5, color: av7Muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        button: true,
        label: context.pwaL10n.continueSetup,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('pwa-draft-card'),
            borderRadius: BorderRadius.circular(20),
            onTap: widget.onContinue,
            child: card,
          ),
        ),
      ),
    );
  }
}
