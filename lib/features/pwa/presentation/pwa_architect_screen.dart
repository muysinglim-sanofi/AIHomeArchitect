/// Batch 2 — Ayden Architect: the signature screen.
///
/// The Full Reveal is the first rich message in the conversation, with the
/// atmospheres directly under the image and the version chronology integrated.
/// Mobile = one vertical flow (reveal card + atmospheres + filmstrip + chat +
/// fixed composer). Desktop = reveal workspace (left) + conversation panel
/// (right). No backend, no real generation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../application/pwa_controller.dart';
import '../application/pwa_layout.dart';
import '../domain/pwa_models.dart';
import 'pwa_versions_sheet.dart';
import 'pwa_widgets.dart';

class PwaArchitectScreen extends ConsumerStatefulWidget {
  const PwaArchitectScreen({super.key});

  @override
  ConsumerState<PwaArchitectScreen> createState() => _PwaArchitectScreenState();
}

class _PwaArchitectScreenState extends ConsumerState<PwaArchitectScreen> {
  final _chatScroll = ScrollController();

  void _onChip(PwaMessage msg, String chip) {
    final c = ref.read(pwaControllerProvider.notifier);
    if (msg.pendingRefine != null && chip == 'Apply this change') {
      c.applyRefine(msg.pendingRefine!);
    } else {
      c.sendUserText(chip);
    }
  }

  void _scrollToBottom() {
    if (!_chatScroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScroll.hasClients) return;
      _chatScroll.animateTo(
        _chatScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _chatScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Auto-scroll the conversation as it grows.
    ref.listen(pwaControllerProvider.select((s) => s.messages.length), (_, _) {
      _scrollToBottom();
    });
    final state = ref.watch(pwaControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final ff = pwaFormFactorForWidth(c.maxWidth);
            return pwaIsTwoPane(ff)
                ? _desktop(context, state)
                : _mobile(context, state);
          },
        ),
      ),
    );
  }

  // ── Mobile / tablet — one vertical flow ─────────────────────────────────────

  Widget _mobile(BuildContext context, PwaState state) {
    final controller = ref.read(pwaControllerProvider.notifier);
    return Column(
      children: [
        _Header(
          versionCount: state.versionCount,
          onVersions: () => showPwaVersionsSheet(context, ref),
        ),
        Expanded(
          child: ListView(
            controller: _chatScroll,
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.pagePadding, 12, AppSpacing.pagePadding, 16),
            children: _conversation(context, state, inlineReveal: true),
          ),
        ),
        if (state.versions.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(AppSpacing.pagePadding, 8, AppSpacing.pagePadding, 8),
            decoration: const BoxDecoration(
              color: AppColors.background,
              border: Border(top: BorderSide(color: AppColors.borderLight)),
            ),
            child: PwaVersionFilmstrip(
              versions: state.versionsChronological,
              currentId: state.currentVisionId,
              onSelected: controller.setCurrentVision,
              onViewAll: () => showPwaVersionsSheet(context, ref),
            ),
          ),
        PwaComposer(
          enabled: !state.generating,
          onSend: controller.sendUserText,
        ),
      ],
    );
  }

  // ── Desktop — reveal workspace + conversation panel ─────────────────────────

  Widget _desktop(BuildContext context, PwaState state) {
    final controller = ref.read(pwaControllerProvider.notifier);
    final current = state.currentVision;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left — reveal workspace (dominant).
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PwaBrandHeader(),
                const SizedBox(height: 20),
                if (current != null) ...[
                  PwaRevealCard(
                    vision: current,
                    source: state.source,
                    project: state.project,
                    aspectRatio: 16 / 10,
                  ),
                  const SizedBox(height: 16),
                  Text('Atmospheres',
                      style: pwaSerif(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  PwaAtmosphereStrip(
                    atmospheres: state.atmospheres,
                    selectedId: state.selectedAtmosphereId,
                    onSelected: controller.selectAtmosphere,
                    enabled: !state.generating,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Text('Versions',
                          style: pwaSerif(fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Text('${state.versionCount}',
                          style: const TextStyle(
                              color: AppColors.textTertiary, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  PwaVersionFilmstrip(
                    versions: state.versionsChronological,
                    currentId: state.currentVisionId,
                    onSelected: controller.setCurrentVision,
                  ),
                ],
              ],
            ),
          ),
        ),
        // Right — conversation panel.
        Container(
          width: 440,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(left: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: _PanelTitle(),
              ),
              Expanded(
                child: ListView(
                  controller: _chatScroll,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: _conversation(context, state, inlineReveal: false),
                ),
              ),
              PwaComposer(
                enabled: !state.generating,
                onSend: controller.sendUserText,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Shared conversation builder ─────────────────────────────────────────────

  List<Widget> _conversation(BuildContext context, PwaState state,
      {required bool inlineReveal}) {
    final controller = ref.read(pwaControllerProvider.notifier);
    final out = <Widget>[];
    for (final m in state.messages) {
      switch (m.kind) {
        case PwaMessageKind.loading:
          out.add(const PwaLoadingBubble());
          break;
        case PwaMessageKind.text:
          out.add(PwaTextBubble(message: m));
          if (m.chips.isNotEmpty) {
            out.add(const SizedBox(height: 6));
            out.add(PwaChips(chips: m.chips, onTap: (chip) => _onChip(m, chip)));
            out.add(const SizedBox(height: 4));
          }
          break;
        case PwaMessageKind.reveal:
          final vision = _visionFor(state, m.visionId);
          if (vision == null) break;
          final isCurrent = vision.versionId == state.currentVisionId;
          if (inlineReveal) {
            out.add(const SizedBox(height: 6));
            out.add(PwaRevealCard(
              vision: vision,
              source: state.source,
              project: state.project,
            ));
            if (isCurrent) {
              out.add(const SizedBox(height: 12));
              out.add(PwaAtmosphereStrip(
                atmospheres: state.atmospheres,
                selectedId: state.selectedAtmosphereId,
                onSelected: controller.selectAtmosphere,
                enabled: !state.generating,
              ));
            }
            out.add(const SizedBox(height: 10));
            out.add(PwaTextBubble(message: m));
          } else {
            // Desktop — the big reveal lives in the workspace; the chat carries a
            // compact reference so the chronology stays intact.
            out.add(_VisionRefBubble(
              vision: vision,
              selected: isCurrent,
              onTap: () => controller.setCurrentVision(vision.versionId),
            ));
            out.add(PwaTextBubble(message: m));
          }
          if (m.chips.isNotEmpty) {
            out.add(const SizedBox(height: 6));
            out.add(PwaChips(chips: m.chips, onTap: (chip) => _onChip(m, chip)));
            out.add(const SizedBox(height: 4));
          }
          break;
      }
    }
    return out;
  }

  PwaVision? _visionFor(PwaState state, String? id) {
    for (final v in state.versions) {
      if (v.versionId == id) return v;
    }
    return null;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.versionCount, required this.onVersions});
  final int versionCount;
  final VoidCallback onVersions;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.pagePadding, 12, AppSpacing.pagePadding, 12),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: PwaBrandHeader(
        compact: true,
        trailing: GestureDetector(
          onTap: onVersions,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.layers_outlined, size: 15, color: AppColors.textSecondary),
              const SizedBox(width: 5),
              Text('$versionCount ${versionCount == 1 ? "vision" : "visions"}',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle();
  @override
  Widget build(BuildContext context) => Row(
        children: [
          const Icon(Icons.auto_awesome, size: 16, color: kPwaGold),
          const SizedBox(width: 8),
          Text('Ayden Architect',
              style: pwaSerif(fontSize: 17, fontWeight: FontWeight.w500)),
        ],
      );
}

class _VisionRefBubble extends StatelessWidget {
  const _VisionRefBubble(
      {required this.vision, required this.selected, required this.onTap});
  final PwaVision vision;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? kPwaGold : AppColors.border, width: selected ? 2 : 1),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: SizedBox(
                width: 54,
                height: 54,
                child: Image.asset(vision.afterAsset,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: AppColors.surfaceVariant)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Vision ${vision.visionNumber} · ${vision.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  const Text('Tap to view in workspace',
                      style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
