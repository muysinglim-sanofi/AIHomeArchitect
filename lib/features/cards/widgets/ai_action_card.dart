/// AYDEN card system — AI action card (system action).
/// Black, minimal, ✦ — NO glow. Fills its parent (matches the neighbour card's
/// geometry). Reads as a system action, never as content.
library;

import 'package:flutter/material.dart';

class AiActionCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final double radius;
  final bool locked;
  final VoidCallback? onTap;

  const AiActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.radius = 16,
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
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0E0E10),
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.locked ? Icons.lock_outline : Icons.auto_awesome,
                    size: 22,
                    color: Colors.white
                        .withValues(alpha: widget.locked ? 0.5 : 0.92)),
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
        ),
      ),
    );
  }
}
