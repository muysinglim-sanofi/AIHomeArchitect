import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/l10n/app_localizations.dart';
import '../../data/models/project_model.dart';

String _timeAgo(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'yesterday';
  return '${diff.inDays}d ago';
}

class ProjectCard extends StatelessWidget {
  final ProjectModel project;
  final VoidCallback? onTap;

  const ProjectCard({super.key, required this.project, this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final previewUrl = project.afterImageUrl ?? project.beforeImageUrl;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ImageArea(url: previewUrl, iterationCount: project.iterationCount),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // CHANTIER D #4 — title leads the hierarchy.
                  Text(
                    project.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // CHANTIER D #13 — room badge + atmosphere chip make each card
                  // scannable at a glance (vs the old identical-looking rows).
                  Row(
                    children: [
                      if (project.roomType.isNotEmpty)
                        Flexible(
                          child: _MetaChip(
                            icon: Icons.meeting_room_outlined,
                            label: project.roomType,
                          ),
                        ),
                      if (project.roomType.isNotEmpty &&
                          project.style.isNotEmpty)
                        const SizedBox(width: 6),
                      if (project.style.isNotEmpty)
                        Flexible(
                          child: _MetaChip(
                            icon: Icons.auto_awesome,
                            label: project.style,
                            accent: true,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${l10n.lastUpdated} ${_timeAgo(project.lastUpdatedAt)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 10,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// CHANTIER D #13 — compact meta chip. Neutral for the room, gold-accented for
/// the atmosphere, so the two read distinctly without crowding the card.
class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool accent;
  const _MetaChip({required this.icon, required this.label, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final color = accent ? AppColors.accent : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent
            ? AppColors.accent.withValues(alpha: 0.10)
            : AppColors.border.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(50),
        border: accent
            ? Border.all(color: AppColors.accent.withValues(alpha: 0.30))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageArea extends StatelessWidget {
  final String? url;
  final int iterationCount;
  const _ImageArea({this.url, required this.iterationCount});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Stack(
        fit: StackFit.expand,
        children: [
          url != null
              ? CachedNetworkImage(
                  imageUrl: url!,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(color: AppColors.shimmerBase),
                  errorWidget: (_, _, _) => Container(
                    color: AppColors.shimmerBase,
                    child: const Icon(Icons.broken_image_outlined, color: AppColors.textTertiary),
                  ),
                )
              : Container(
                  color: AppColors.shimmerBase,
                  child: const Center(
                    child: Icon(Icons.image_outlined, color: AppColors.textTertiary, size: 32),
                  ),
                ),
          if (iterationCount > 0)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.textPrimary.withAlpha(180),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome, size: 9, color: AppColors.surface),
                    const SizedBox(width: 3),
                    Text(
                      '$iterationCount ${iterationCount == 1 ? context.l10n.vision : context.l10n.visions}',
                      style: const TextStyle(
                        color: AppColors.surface,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
