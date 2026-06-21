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

  /// Force the photo to COVER the card (fill edge-to-edge, cropping a little)
  /// instead of CONTAIN (which letterboxes with dark bands). Independent of
  /// [compact] so a large card can still fill its frame. The Full Reveal
  /// carousel sets this to drop the black frames around its cards.
  final bool fillPhoto;

  /// Optional type-size overrides. When null they fall back to the
  /// compact-aware defaults. The Full Reveal carousel uses these to keep the
  /// full-photo (contain) look while dialing the title/subtitle down so the
  /// name isn't oversized/truncated on its mid-size cards.
  final double? nameFontSize;
  final double? subtitleFontSize;
  final VoidCallback? onTap;

  const AtmosphereHeroCard({
    super.key,
    required this.name,
    required this.subtitle,
    required this.asset,
    this.selected = false,
    this.locked = false,
    this.compact = false,
    this.fillPhoto = false,
    this.nameFontSize,
    this.subtitleFontSize,
    this.onTap,
  });

  @override
  State<AtmosphereHeroCard> createState() => _AtmosphereHeroCardState();
}

class _AtmosphereHeroCardState extends State<AtmosphereHeroCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // Selected affordance scales with the card size: the small compact
    // thumbnails (Full Reveal / re-upload strips) get a lighter border + ring
    // + halo so the chrome never crowds the tiny image; the large carousel
    // card keeps the bold treatment.
    final bool c = widget.compact;
    final double selBorderW = c ? 2.5 : 3.5;
    final double selPad = c ? 1.5 : 2.5;
    final double selInnerRadius = 18 - selBorderW - selPad;
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
            // White ground shows as a crisp inner ring (via the padding below)
            // so the selected state contrasts on ANY photo, including warm
            // beige interiors where the muted gold border blended in.
            color: widget.selected ? Colors.white : null,
            borderRadius: BorderRadius.circular(18),
            border: widget.selected
                ? Border.all(color: AppColors.accent, width: selBorderW)
                : null,
          ),
          padding: widget.selected
              ? EdgeInsets.all(selPad)
              : EdgeInsets.zero,
          child: ClipRRect(
            borderRadius:
                BorderRadius.circular(widget.selected ? selInnerRadius : 18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Dark frame behind the contained photo so any letterbox band
                // reads as an intentional cinematic frame, never a "gap".
                const ColoredBox(color: Color(0xFF0B0B0C)),
                // Large = full photo (contain); compact / fillPhoto = cover.
                Image.asset(
                  widget.asset,
                  fit: (widget.compact || widget.fillPhoto)
                      ? BoxFit.cover
                      : BoxFit.contain,
                  // CHANTIER F #14 — normalize the cover crop toward the
                  // architectural focal point (upper-mid). Interior photos read
                  // best framed on the room/openings; the lower edge is covered
                  // by the title scrim anyway, so center-crop wasted the subject.
                  alignment: (widget.compact || widget.fillPhoto)
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
                      // Name is optional — Ayden Signature passes '' because its
                      // brand wordmark is baked into the image; only the subtitle
                      // shows. Skip the title (and its spacer) when blank.
                      if (widget.name.isNotEmpty) ...[
                        Text(
                          widget.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.atmosphereTitle(
                            fontSize: widget.nameFontSize ??
                                (widget.compact ? 15 : 22),
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
                        SizedBox(height: widget.compact ? 1 : 2),
                      ],
                      Text(
                        widget.subtitle,
                        maxLines: widget.compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.atmosphereTitle(
                          fontSize: widget.subtitleFontSize ??
                              (widget.compact ? 10.5 : 13),
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
                  Positioned(
                    top: c ? 7 : 10,
                    right: c ? 7 : 10,
                    child: _Check(compact: c),
                  ),
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
  final bool compact;
  const _Check({this.compact = false});

  @override
  Widget build(BuildContext context) {
    final double size = compact ? 22 : 30;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: compact ? 1.5 : 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(Icons.check, size: compact ? 13 : 17, color: Colors.white),
    );
  }
}
