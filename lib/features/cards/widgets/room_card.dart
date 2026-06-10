/// AYDEN card system — ROOM card (believable architecture).
/// Fills its parent (the grid cell sets the 3:2 ratio). Neutral photo +
/// bottom scrim + uppercase sans label (NO number). Press + selected states.
library;

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';

class RoomCard extends StatefulWidget {
  final String label;
  final String asset;
  final bool selected;
  final bool locked;
  final VoidCallback? onTap;

  const RoomCard({
    super.key,
    required this.label,
    required this.asset,
    this.selected = false,
    this.locked = false,
    this.onTap,
  });

  @override
  State<RoomCard> createState() => _RoomCardState();
}

class _RoomCardState extends State<RoomCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: widget.selected
                ? Border.all(color: AppColors.accent, width: 2)
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.selected ? 14 : 16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  widget.asset,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: Color(0xFF1A1A1C)),
                ),
                // Premium readability scrim — taller, refined protection for
                // a title anchored near the lower edge.
                const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment(0, 0.12),
                        colors: [Color(0xD6000000), Color(0x00000000)],
                      ),
                    ),
                  ),
                ),
                // Same serif design system as Atmospheres, but RESTRAINED:
                // Title Case, no italic, no subtitle → architectural/curated,
                // not the emotional editorial of the atmosphere cards.
                Positioned(
                  left: 18,
                  right: 16,
                  bottom: 8,
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.atmosphereTitle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                // Locked — dim + subtle lock (tap still opens the paywall).
                if (widget.locked) ...[
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(color: Color(0x66000000)),
                    ),
                  ),
                  const Positioned(top: 8, right: 8, child: _LockChip()),
                ],
                if (widget.selected && !widget.locked)
                  const Positioned(top: 8, right: 8, child: _Check()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LockChip extends StatelessWidget {
  const _LockChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.lock_outline, size: 13, color: Colors.white),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: const BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.check, size: 14, color: Colors.white),
    );
  }
}
