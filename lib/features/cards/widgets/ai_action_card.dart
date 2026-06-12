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

  const AiActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.radius = 16,
    this.selected = false,
    this.locked = false,
    this.onTap,
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
              width: widget.selected ? 2 : 1,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.locked ? Icons.lock_outline : Icons.auto_awesome,
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
              // Selected check — same gold chip as RoomCard.
              if (widget.selected && !widget.locked)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check, size: 14, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
