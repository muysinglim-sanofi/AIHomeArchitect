import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/room_type_images.dart';
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

/// CHANTIER D (premium pass) — full-bleed image card with a warm-dark scrim and
/// the meta OVERLAID (room as title · atmosphere · updated-ago), plus a "…" menu.
/// The cinematic scrim unifies the redesigns into one premium, consistent grid
/// (was: image on top + flat white text block below).
class ProjectCard extends StatelessWidget {
  final ProjectModel project;
  final VoidCallback? onTap;
  final VoidCallback? onMenu;

  const ProjectCard({super.key, required this.project, this.onTap, this.onMenu});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final previewUrl = project.afterImageUrl ?? project.beforeImageUrl;
    // Room leads the title (AFTER mock); fall back to the session title.
    // Display-only: localize the room VALUE via displayLabel (the stored
    // project.roomType stays canonical English — no data/routing change).
    final title = project.roomType.isNotEmpty
        ? RoomTypeImages.displayLabel(l10n, project.roomType)
        : project.title;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.shimmerBase,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Full-bleed preview ──
            if (previewUrl != null)
              CachedNetworkImage(
                imageUrl: previewUrl,
                fit: BoxFit.cover,
                placeholder: (_, _) => const ColoredBox(color: AppColors.shimmerBase),
                errorWidget: (_, _, _) => const ColoredBox(
                  color: AppColors.shimmerBase,
                  child: Icon(Icons.broken_image_outlined,
                      color: AppColors.textTertiary),
                ),
              )
            else
              const ColoredBox(
                color: AppColors.shimmerBase,
                child: Center(
                  child: Icon(Icons.image_outlined,
                      color: AppColors.textTertiary, size: 30),
                ),
              ),
            // ── Warm-dark cinematic scrim (premium readability + unifies the grid) ──
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
            // ── Visions count chip ──
            if (project.iterationCount > 0)
              Positioned(top: 9, left: 9, child: _VisionsChip(project.iterationCount)),
            // ── "…" menu ──
            if (onMenu != null)
              Positioned(
                bottom: 4,
                right: 2,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  onPressed: onMenu,
                  icon: Icon(Icons.more_horiz,
                      size: 20, color: Colors.white.withValues(alpha: 0.85)),
                ),
              ),
            // ── Overlaid meta ──
            Positioned(
              left: 12,
              right: onMenu != null ? 40 : 12,
              bottom: 11,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                  if (project.style.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      project.style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    '${l10n.lastUpdated} ${_timeAgo(project.lastUpdatedAt)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
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

class _VisionsChip extends StatelessWidget {
  final int count;
  const _VisionsChip(this.count);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome, size: 9, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            '$count ${count == 1 ? context.l10n.vision : context.l10n.visions}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
