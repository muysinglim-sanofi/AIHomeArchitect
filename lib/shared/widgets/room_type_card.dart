import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/room_type_images.dart';
import '../../core/l10n/app_localizations.dart';
import 'tap_scale.dart';

/// Wave 4.10h — the canonical, shared room-type selection component.
///
/// Philosophy (deliberately NOT a copy of AtmosphereCard):
///   • AtmosphereCard = *mood* — expressive, larger, evocative title type.
///   • RoomTypeCard   = *space identity* — calmer, smaller, editorial,
///     architecture-magazine restraint. It answers "what kind of
///     architecture are we transforming", so it must read instantly and
///     never compete with the atmosphere strip.
///
/// One image-led card + one horizontal [RoomTypeRow] are reused verbatim by
/// BOTH the upload screen and the chat re-upload sheet, so there is zero
/// duplicated room-type UI logic (Task #4). The public contract is a drop-in
/// match for the old pill rows — `rooms` (localized labels), `selected`,
/// `onSelected(label)` — so routing / session / generation are untouched.
class RoomTypeCard extends StatelessWidget {
  /// Localized room label — also the selection value emitted by [onTap]
  /// (unchanged contract). The curated image is resolved from this via
  /// [RoomTypeImages] (stable, locale-correct).
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Wave 4.8.7 — when true, this card renders the "AI Decide" creative
  /// direction (subtle sparkle, calm ink surface, no curated image). It
  /// stays inside the SAME shell as a normal RoomTypeCard so the row reads
  /// as one editorial selection language, not a settings toggle.
  final bool aiDecide;
  final String? aiSublabel;

  /// Wave 5.17d — When true, the card renders dimmed with a small 🔒
  /// chip in the top-right corner. Purely visual ; the PARENT decides
  /// what onTap does (typically open the PaywallSheet).
  final bool locked;

  const RoomTypeCard({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.locked = false,
  })  : aiDecide = false,
        aiSublabel = null;

  /// Premium AI-direction card — restrained visual treatment, identical
  /// shell + selected language as a normal room card so it feels like one
  /// of the cards, not a settings option. Used as the FIRST entry of the
  /// room row to read as a creative direction.
  const RoomTypeCard.ai({
    super.key,
    required this.label,
    String? sublabel,
    required this.selected,
    required this.onTap,
    this.locked = false,
  })  : aiDecide = true,
        aiSublabel = sublabel;

  @override
  Widget build(BuildContext context) {
    final url =
        aiDecide ? null : RoomTypeImages.urlForLabel(context.l10n, label);

    return TapScale(
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, box) {
          // Adaptive: a touch smaller type on narrow cards (SE strip) so the
          // label never truncates awkwardly.
          final compact = box.maxWidth < 120;
          final labelSize = compact ? 12.0 : 13.0;

          final borderColor =
              selected ? AppColors.accent : AppColors.border;

          return Opacity(
            // Wave 5.17d — locked cards are muted (0.55) but legible.
            opacity: locked ? 0.55 : 1.0,
            child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
              border: Border.all(
                color: borderColor,
                width: selected ? 2 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (aiDecide) ...[
                  // AI direction — same shell, calm ink surface, subtle
                  // sparkle accent + editorial label/sublabel. Restrained:
                  // reads as a creative direction, NOT a settings option.
                  const ColoredBox(color: AppColors.textPrimary),
                  Padding(
                    padding: EdgeInsets.all(compact ? 8 : 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Icon(Icons.auto_awesome_outlined,
                            size: 18, color: AppColors.surface),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.surface,
                                fontWeight: FontWeight.w600,
                                fontSize: labelSize,
                                height: 1.15,
                                letterSpacing: 0.1,
                              ),
                            ),
                            if (aiSublabel != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                aiSublabel!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.surface
                                      .withValues(alpha: 0.68),
                                  fontSize:
                                      (labelSize - 2).clamp(9.0, 12.0),
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Image, or the calm typographic fallback (never broken).
                  if (url != null)
                    CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => const _RoomFallback(),
                      errorWidget: (_, _, _) =>
                          _RoomFallback(label: label, size: labelSize),
                    )
                  else
                    _RoomFallback(label: label, size: labelSize),

                  // A SINGLE calm legibility scrim (not "gradients everywhere")
                  // — only over the lower band, only where the label sits.
                  if (url != null)
                    const Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: 0.62,
                        widthFactor: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0x00000000),
                                Color(0x8A0E0E0E),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Label — bottom-left, restrained editorial caption.
                  Padding(
                    padding: EdgeInsets.fromLTRB(compact ? 8 : 10, 0,
                        compact ? 8 : 10, compact ? 8 : 10),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: url != null
                              ? AppColors.surface
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: labelSize,
                          height: 1.15,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ),
                ],

                // Selected — obvious but elegant: a small accent check chip
                // (no noisy full-card tint), paired with the 2px border.
                if (selected)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check,
                          size: 13, color: AppColors.surface),
                    ),
                  ),
                // Wave 5.17d — lock chip overlay. Sits in the same
                // top-right slot as `selected` ; both visible only matter
                // when a free-tier card is selected, which is allowed
                // (Living Room is both free and selectable). Stack ordering
                // puts the lock UNDER the check so the check stays visible.
                if (locked && !selected)
                  const Positioned(
                    top: 8,
                    right: 8,
                    child: _RoomLockChip(),
                  ),
              ],
            ),
          ),
          );
        },
      ),
    );
  }
}

// ── Lock chip (Wave 5.17d) ────────────────────────────────────────────────────

class _RoomLockChip extends StatelessWidget {
  const _RoomLockChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: AppColors.textPrimary.withValues(alpha: 0.78),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.lock_outline,
        size: 12,
        color: AppColors.surface,
      ),
    );
  }
}

/// Calm typographic fallback — same rounded shell language, never a broken
/// or empty box. Used as the network placeholder and the hard fallback.
class _RoomFallback extends StatelessWidget {
  final String? label;
  final double size;
  const _RoomFallback({this.label, this.size = 13});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceVariant,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.meeting_room_outlined,
                size: 20, color: AppColors.textTertiary),
            if (label != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  label!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: size,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shared horizontal room-type scroller — the single rhythm used by upload
/// AND the chat re-upload sheet (zero duplication). Drop-in replacement for
/// the old 42-px pill rows: same `(rooms, selected, onSelected)` contract.
class RoomTypeRow extends StatelessWidget {
  final List<String> rooms;
  final String? selected;
  final ValueChanged<String> onSelected;

  /// Wave 4.8.7 — optional leading AI-direction card. When both
  /// [onAiDecide] and [aiLabel] are provided the row prepends a calm
  /// AI card at index 0, visually unified with the other cards (same
  /// shell / sizing / scroll behaviour). When omitted the row renders
  /// exactly as before (chat re-upload sheet keeps its behaviour).
  final bool aiDecideSelected;
  final String? aiLabel;
  final String? aiSublabel;
  final VoidCallback? onAiDecide;

  /// Wave 5.17d — when non-null, returns true iff the given room label
  /// is OUT-OF-SCOPE for the free tier (lock chip + dimmed). Null →
  /// no card is locked (premium user or pre-monetization screens).
  final bool Function(String roomLabel)? isLocked;
  /// Wave 5.17d — when non-null, AI Decide tile is locked when this
  /// returns true. Independent of `isLocked` because AI Decide is
  /// always premium regardless of the selected room.
  final bool Function()? isAiLocked;

  /// Calm, modest footprint — deliberately smaller than the atmosphere
  /// strip so room selection never competes with mood selection.
  static const double rowHeight = 104;
  static const double _cardWidth = 130;

  const RoomTypeRow({
    super.key,
    required this.rooms,
    required this.selected,
    required this.onSelected,
    this.aiDecideSelected = false,
    this.aiLabel,
    this.aiSublabel,
    this.onAiDecide,
    this.isLocked,
    this.isAiLocked,
  });

  bool get _hasAi => onAiDecide != null && aiLabel != null;

  @override
  Widget build(BuildContext context) {
    final leading = _hasAi ? 1 : 0;
    return SizedBox(
      height: rowHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: EdgeInsets.zero,
        itemCount: rooms.length + leading,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          if (_hasAi && i == 0) {
            return SizedBox(
              width: _cardWidth,
              child: RoomTypeCard.ai(
                label: aiLabel!,
                sublabel: aiSublabel,
                selected: aiDecideSelected,
                onTap: onAiDecide!,
                locked: isAiLocked?.call() ?? false,
              ),
            );
          }
          final r = rooms[i - leading];
          return SizedBox(
            width: _cardWidth,
            child: RoomTypeCard(
              label: r,
              selected: selected == r,
              onTap: () => onSelected(r),
              locked: isLocked?.call(r) ?? false,
            ),
          );
        },
      ),
    );
  }
}
