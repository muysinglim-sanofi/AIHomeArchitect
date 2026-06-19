/// AYDEN card system — AI action card (system action).
/// CHANTIER E #19 — aligned to the premium room-card language: warm-dark depth
/// (not flat black), gold mark, gold selected border + check (like RoomCard),
/// matching geometry and press. Still reads as an ACTION, never as content.
library;

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class AiActionCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final double radius;
  final bool selected;
  final bool locked;
  final VoidCallback? onTap;

  // Optional brand watermark (e.g. the gold Ayden compass). When set, a large
  // low-opacity logo + a soft gold radial glow render behind the content, for
  // a more premium, branded feel. Left null on generic action cards (Surprise
  // Me / Custom) so they keep the plain look.
  final String? watermarkAsset;

  // Optional full-bleed image that REPLACES the icon/title/subtitle layout —
  // the card becomes just this image (cover-filled), keeping the selection
  // border + check + lock overlay. Used for the pre-composed "Ayden Decide"
  // card art. Takes precedence over [watermarkAsset].
  final String? backgroundImageAsset;

  const AiActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.radius = 16,
    this.selected = false,
    this.locked = false,
    this.onTap,
    this.watermarkAsset,
    this.backgroundImageAsset,
  });

  @override
  State<AiActionCard> createState() => _AiActionCardState();
}

class _AiActionCardState extends State<AiActionCard> {
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
            // Warm-dark depth instead of flat black → sits as a premium peer of
            // the photo room cards rather than a disconnected black tile.
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1C1510), Color(0xFF0E0B09)],
            ),
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(
              color: widget.selected
                  ? AppColors.accent
                  : AppColors.accent.withValues(alpha: 0.22),
              width: widget.selected ? 3.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Full-bleed card art (replaces the icon/title/subtitle).
              if (widget.backgroundImageAsset != null)
                Positioned.fill(
                  child: Image.asset(
                    widget.backgroundImageAsset!,
                    fit: BoxFit.cover,
                    alignment: Alignment.centerLeft,
                  ),
                ),
              // ── Design B — soft gold glow behind content (depth).
              if (widget.backgroundImageAsset == null &&
                  widget.watermarkAsset != null)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(widget.radius),
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.15),
                        radius: 0.95,
                        colors: [
                          AppColors.accent.withValues(alpha: 0.18),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              if (widget.backgroundImageAsset == null)
                Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Brand mark as the icon (visible) when provided ; thin
                    // gold line-art doesn't read as a faint watermark, so the
                    // compass leads instead. Falls back to the sparkle.
                    if (widget.watermarkAsset != null && !widget.locked)
                      Image.asset(
                        widget.watermarkAsset!,
                        height: 46,
                        fit: BoxFit.contain,
                      )
                    else
                      Icon(
                        widget.locked
                            ? Icons.lock_outline
                            : Icons.auto_awesome,
                        size: 22,
                        color: widget.locked
                            ? Colors.white.withValues(alpha: 0.5)
                            : AppColors.accent,
                      ),
                    const SizedBox(height: 10),
                    Text(
                      widget.title.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        widget.subtitle,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 11,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Locked overlay for the full-bleed art (the gated content's lock
              // icon is hidden when an image replaces it).
              if (widget.backgroundImageAsset != null && widget.locked)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.5),
                    child: const Center(
                      child: Icon(Icons.lock_outline,
                          size: 24, color: Colors.white),
                    ),
                  ),
                ),
              // Selected check — same gold chip as RoomCard.
              if (widget.selected && !widget.locked)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.check, size: 16, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
