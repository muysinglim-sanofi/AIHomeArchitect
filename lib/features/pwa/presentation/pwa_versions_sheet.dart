/// Batch 2 — near-full-screen mobile "all versions" bottom sheet.
///
/// Shows the chronological version list with thumbnail, title, atmosphere, the
/// creation reason and "Created from Vision X", plus the mocked actions (Open,
/// Compare, Continue from this version, Find in conversation, Set as current).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../application/pwa_controller.dart';
import '../domain/pwa_models.dart';
import 'pwa_stored_image.dart';
import 'pwa_widgets.dart';

Future<void> showPwaVersionsSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _PwaVersionsSheet(),
  );
}

class _PwaVersionsSheet extends ConsumerWidget {
  const _PwaVersionsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pwaControllerProvider);
    final controller = ref.read(pwaControllerProvider.notifier);
    final versions = state.versionsChronological;
    final height = MediaQuery.sizeOf(context).height * 0.9;

    String parentLabel(PwaVision v) {
      if (v.parentVersionId == null) return 'Original upload';
      final p = versions.where((x) => x.versionId == v.parentVersionId);
      return p.isEmpty ? 'Original upload' : 'Vision ${p.first.visionNumber}';
    }

    return SizedBox(
      height: height,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Your visions',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: pwaSerif(fontSize: 22, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${versions.length} total',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: versions.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final v = versions[i];
                return _VersionRow(
                  vision: v,
                  parentLabel: parentLabel(v),
                  isCurrent: v.versionId == state.currentVisionId,
                  onOpen: () {
                    controller.setCurrentVision(v.versionId);
                    Navigator.of(context).pop();
                  },
                  onCompare: () => showPwaFullscreenReveal(
                    context,
                    vision: v,
                    source: state.source,
                    project: state.project,
                  ),
                  onContinue: () {
                    controller.continueFromVision(v.versionId);
                    Navigator.of(context).pop();
                  },
                  onFind: () {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Jumped to Vision ${v.visionNumber} in the conversation',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  onSetCurrent: () {
                    controller.setCurrentVision(v.versionId);
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.vision,
    required this.parentLabel,
    required this.isCurrent,
    required this.onOpen,
    required this.onCompare,
    required this.onContinue,
    required this.onFind,
    required this.onSetCurrent,
  });

  final PwaVision vision;
  final String parentLabel;
  final bool isCurrent;
  final VoidCallback onOpen;
  final VoidCallback onCompare;
  final VoidCallback onContinue;
  final VoidCallback onFind;
  final VoidCallback onSetCurrent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(
          color: isCurrent ? kPwaGold : AppColors.border,
          width: isCurrent ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 68,
                  height: 68,
                  child: PwaStoredImage(
                    key: ValueKey('versions-${vision.versionId}'),
                    reference: vision.afterAsset,
                    placeholderColor: AppColors.surfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Vision ${vision.visionNumber}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: kPwaGold,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Current',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vision.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Created from $parentLabel · ${vision.reasonLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Action(label: 'Open', onTap: onOpen),
              _Action(label: 'Compare', onTap: onCompare),
              _Action(label: 'Continue', onTap: onContinue),
              _Action(label: 'Find in chat', onTap: onFind),
              _Action(label: 'Set current', onTap: onSetCurrent),
            ],
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
    ),
  );
}
