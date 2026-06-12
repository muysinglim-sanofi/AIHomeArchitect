/// AYDEN card system — ATMOSPHERE card (emotional projection).
/// Fills its parent (the carousel page sets the 16:10 size). Warm photo +
/// taller scrim + serif title + italic "Inspired by…" subtitle. Press +
/// selected states. Editorial register — deliberately unlike RoomCard.
library;

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';

class AtmosphereHeroCard extends StatefulWidget {
  final String name;
  final String subtitle;
  final String asset;
  final bool selected;
  final bool locked;

  /// Small thumbnail variant (atmosphere strips in Full Reveal / Reupload /
  /// FTUE): cover fit + tighter type & padding. Default false = the large
  /// mini-hero (contain, full photo) used by the upload carousel.
  final bool compact;
  final VoidCallback? onTap;

  const AtmosphereHeroCard({
    super.key,
    required this.name,
    required this.subtitle,
    required this.asset,
    this.selected = false,
    this.locked = false,
    this.compact = false,
    this.onTap,
  });

  @override
  State<AtmosphereHeroCard> createState() => _AtmosphereHeroCardState();
}

class _AtmosphereHeroCardState extends State<AtmosphereHeroCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: widget.selected
                ? Border.all(color: AppColors.accent, width: 2)
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.selected ? 16 : 18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Dark frame behind the contained photo so any letterbox band
                // reads as an intentional cinematic frame, never a "gap".
                const ColoredBox(color: Color(0xFF0B0B0C)),
                // Large = full photo (contain); compact thumbnail = cover.
                Image.asset(
                  widget.asset,
                  fit: widget.compact ? BoxFit.cover : BoxFit.contain,
                  // CHANTIER F #14 — normalize the compact crop toward the
                  // architectural focal point (upper-mid). Interior photos read
                  // best framed on the room/openings; the lower edge is covered
                  // by the title scrim anyway, so center-crop wasted the subject.
                  alignment: widget.compact
                      ? const Alignment(0, -0.18)
                      : Alignment.center,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: Color(0xFF1A1A1C)),
                ),
                const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment(0, 0.25),
                        colors: [Color(0xE6000000), Color(0x00000000)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: widget.compact ? 12 : 22,
                  right: widget.compact ? 10 : 20,
                  bottom: widget.compact ? 11 : 20,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.atmosphereTitle(
                          fontSize: widget.compact ? 15 : 22,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                          height: 1.1,
                        ),
                      ),
                      SizedBox(height: widget.compact ? 1 : 2),
                      Text(
                        widget.subtitle,
                        maxLines: widget.compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.atmosphereTitle(
                          fontSize: widget.compact ? 10.5 : 13,
                          fontWeight: FontWeight.w400,
                          color: Colors.white.withValues(alpha: 0.82),
                          height: 1.2,
                        ).copyWith(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
                if (widget.locked) ...[
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(color: Color(0x66000000)),
                    ),
                  ),
                  const Positioned(top: 12, right: 12, child: _LockChip()),
                ],
                if (widget.selected && !widget.locked)
                  const Positioned(top: 10, right: 10, child: _Check()),
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
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.lock_outline, size: 14, color: Colors.white),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: const BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.check, size: 15, color: Colors.white),
    );
  }
}
