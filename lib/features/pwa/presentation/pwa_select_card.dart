/// PWA-only selection card (Screen 2 fast path) — faithful to
/// REF-PWA-UPLOAD-FASTPATH-V3.png: a rounded image on top (gold border + check
/// when selected) with an EXTERNAL caption below (title + optional subtitle).
///
/// Shared by the ROOM and ATMOSPHERE rows so both levels have identical
/// dimensions and align perfectly. Deliberately does NOT reuse the iOS
/// RoomCard / AtmosphereHeroCard (which overlay a single-line ellipsized label
/// INSIDE the image — the exact truncation the reference rejects). Those iOS
/// widgets are left untouched.
library;

import 'package:flutter/material.dart';

import 'pwa_theme.dart';

/// Fixed card footprint — shared by ROOM and ATMOSPHERE so the two horizontal
/// rows share the same card width and height (perfect vertical alignment).
const double kPwaCardW = 158;
const double kPwaCardH = 156;

class PwaSelectCard extends StatefulWidget {
  const PwaSelectCard({
    super.key,
    required this.title,
    required this.asset,
    required this.selected,
    required this.onTap,
    this.subtitle = '',
    this.imageAlignment = Alignment.center,
  });

  final String title;
  final String subtitle;
  final String asset;
  final bool selected;
  final VoidCallback onTap;
  final Alignment imageAlignment;

  @override
  State<PwaSelectCard> createState() => _PwaSelectCardState();
}

class _PwaSelectCardState extends State<PwaSelectCard> {
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Rounded image + selected gold frame + check (same grammar for
            // every card, Ayden Decide / Ayden Signature included).
            AspectRatio(
              aspectRatio: 3 / 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.selected ? Colors.white : null,
                  borderRadius: BorderRadius.circular(14),
                  border: widget.selected
                      ? Border.all(color: pwaGold, width: 2.5)
                      : Border.all(color: pwaOnDark.withValues(alpha: 0.10)),
                ),
                child: Padding(
                  padding: EdgeInsets.all(widget.selected ? 2 : 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      widget.selected ? 11 : 14,
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          widget.asset,
                          fit: BoxFit.cover,
                          alignment: widget.imageAlignment,
                          errorBuilder: (_, _, _) =>
                              const ColoredBox(color: pwaCharcoalSoft),
                        ),
                        // Bottom scrim for depth (keeps images premium on dark).
                        const IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment(0, 0.4),
                                colors: [Color(0x66000000), Color(0x00000000)],
                              ),
                            ),
                          ),
                        ),
                        if (widget.selected)
                          const Positioned(top: 6, right: 6, child: _Check()),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // External caption — the label is NEVER ellipsized (FittedBox scales
            // it down on narrow widths instead of cutting it).
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.title,
                  maxLines: 1,
                  style: pwaSans(
                    fontSize: 14,
                    color: pwaOnDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            // Reserved subtitle row (fixed height) so every card is the same
            // total height whether or not it carries a subtitle.
            SizedBox(
              height: 15,
              width: double.infinity,
              child: widget.subtitle.isEmpty
                  ? null
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        widget.subtitle,
                        maxLines: 1,
                        style: pwaSans(
                          fontSize: 11.5,
                          color: pwaGold.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
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
      decoration: BoxDecoration(
        color: pwaGold,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(Icons.check, size: 14, color: Colors.white),
    );
  }
}
