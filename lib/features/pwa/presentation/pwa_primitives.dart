/// The shared visual grammar — small, faithful, and reusable.
///
/// Each primitive reproduces a piece of the iOS system exactly, with the source
/// named. The point is that the screens migrated after this phase do not each
/// invent their own approximation of a button or a selection tick: there is one
/// of each, it is right, and correcting it corrects everywhere.
///
/// Deliberately NOT here: anything screen-specific. No Home hero, no reveal
/// slider, no paywall row. Those belong to their own phases, and building them
/// now would be guessing at requirements that the screen work will actually
/// state.
library;

import 'package:flutter/material.dart';

import 'pwa_theme.dart';
import 'pwa_type.dart';

// ── buttons ─────────────────────────────────────────────────────────────────

/// The primary CTA. iOS `elevatedButtonTheme`: ink fill, white label, flat,
/// 32/16 padding, PILL radius.
///
/// The pill is the part that matters. The PWA drew some CTAs as pills and some
/// as 16-radius rectangles; iOS draws all of them as pills, and the
/// inconsistency was a large part of why the two did not feel alike.
class PwaPrimaryButton extends StatelessWidget {
  const PwaPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Full-width by default — the shape a mobile CTA takes on both platforms.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: pwaInk,
        foregroundColor: pwaSurface,
        disabledBackgroundColor: pwaWell,
        disabledForegroundColor: pwaFaint,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PwaGap.radiusPill),
        ),
        minimumSize: expand ? const Size.fromHeight(52) : null,
      ),
      child: _labelRow(label, icon, PwaType.button(color: pwaSurface)),
    );
    return button;
  }
}

/// The secondary CTA. iOS `outlinedButtonTheme`: 1.5px hairline, ink label.
class PwaSecondaryButton extends StatelessWidget {
  const PwaSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: pwaInk,
        side: const BorderSide(color: pwaHairline, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PwaGap.radiusPill),
        ),
        minimumSize: expand ? const Size.fromHeight(52) : null,
      ),
      child: _labelRow(label, icon, PwaType.button()),
    );
  }
}

Widget _labelRow(String label, IconData? icon, TextStyle style) {
  final text = Text(label, textAlign: TextAlign.center, style: style);
  if (icon == null) return text;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: style.color),
      const SizedBox(width: PwaGap.sm),
      Flexible(child: text),
    ],
  );
}

// ── labels ──────────────────────────────────────────────────────────────────

/// The uppercase eyebrow above a section — "CONTINUE DESIGNING",
/// "STEP 1 OF 4", "AYDEN SIGNATURE".
///
/// Tracking collapses to zero in Khmer; see [pwaEyebrow] for why that is a
/// legibility rule and not a stylistic one.
class PwaEyebrow extends StatelessWidget {
  const PwaEyebrow(this.text, {super.key, this.color = pwaGold});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: pwaEyebrow(color: color));
}

/// The numbered step marker of the creation flow — a filled pill, because iOS
/// treats a step as a badge rather than as a heading.
///
/// It takes the WHOLE label ("STEP 1 OF 4") rather than a number, so the
/// localisation layer owns the wording and word order. Khmer does not
/// necessarily put the numeral where English does.
class PwaStepPill extends StatelessWidget {
  const PwaStepPill(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: pwaGoldSoft,
          borderRadius: BorderRadius.circular(PwaGap.radiusPill),
        ),
        child: Text(label.toUpperCase(),
            style: pwaEyebrow(color: pwaInk, fontSize: 10)),
      );
}

/// A label over imagery — "Original", "Vision", an atmosphere name.
///
/// Two tones because a before/after needs to distinguish them at a glance and
/// iOS does exactly that: the source is light-on-dark, the result is the
/// inverse.
class PwaImageChip extends StatelessWidget {
  const PwaImageChip(this.label, {super.key, this.dark = false});

  final String label;

  /// True renders ink-on-white (the "Vision" side); false renders the
  /// translucent light chip used over a photograph.
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: dark ? pwaImageFrame : pwaSurface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(PwaGap.radiusPill),
        ),
        child: Text(label,
            style: PwaType.cardSubtitle(color: dark ? pwaOnDark : pwaInk)),
      );
}

// ── selection ───────────────────────────────────────────────────────────────

/// The selected-state tick iOS puts on a chosen room or atmosphere card:
/// a filled gold disc with a white check.
///
/// A single widget because "selected" must look identical everywhere. The
/// previous PWA drew this three different ways.
class PwaSelectionTick extends StatelessWidget {
  const PwaSelectionTick({super.key, this.selected = true, this.size = 28});

  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!selected) return SizedBox(width: size, height: size);
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: pwaGold, shape: BoxShape.circle),
      child: Icon(Icons.check_rounded, size: size * 0.62, color: pwaSurface),
    );
  }
}

/// The frame around a selectable card. iOS marks selection with a gold border
/// and leaves the unselected state to a hairline — not a shadow, not a scale.
class PwaSelectableCard extends StatelessWidget {
  const PwaSelectableCard({
    super.key,
    required this.child,
    required this.selected,
    this.onTap,
    this.radius = PwaGap.radius,
  });

  final Widget child;
  final bool selected;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: selected ? pwaGold : pwaHairline,
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      );
}

// ── surfaces ────────────────────────────────────────────────────────────────

/// A content card on the canvas. iOS `radiusCard` (16), white, hairline border,
/// no shadow — the restraint is the point.
class PwaCard extends StatelessWidget {
  const PwaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(PwaGap.md),
    this.color = pwaCardSurface,
    this.radius = PwaGap.radius,
    this.border = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final double radius;
  final bool border;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
          border: border ? Border.all(color: pwaHairline) : null,
        ),
        child: child,
      );
}

/// An image in the product's geometry: card radius, clipped, on a dark frame
/// so a photograph with light edges still reads as a contained object.
///
/// Named `PwaFramedImage`, not `PwaImageFrame`, so it cannot be misread as the
/// [pwaImageFrame] COLOUR it paints with.
class PwaFramedImage extends StatelessWidget {
  const PwaFramedImage({
    super.key,
    required this.child,
    this.radius = PwaGap.radius,
    this.aspectRatio,
  });

  final Widget child;
  final double radius;
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    final framed = Container(
      decoration: BoxDecoration(
        color: pwaImageFrame,
        borderRadius: BorderRadius.circular(radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
    return aspectRatio == null
        ? framed
        : AspectRatio(aspectRatio: aspectRatio!, child: framed);
  }
}

/// The hairline iOS uses between rows. Thin, warm, and never a hard grey.
class PwaDivider extends StatelessWidget {
  const PwaDivider({super.key, this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        thickness: 1,
        color: pwaHairline,
        indent: indent,
        endIndent: indent,
      );
}

// ── header ──────────────────────────────────────────────────────────────────

/// A screen header: optional back affordance, a title, optional trailing
/// actions. Sits on the canvas, not on a coloured app bar — iOS has no
/// Material app bar anywhere in this product.
class PwaScreenHeader extends StatelessWidget {
  const PwaScreenHeader({
    super.key,
    this.title,
    this.eyebrow,
    this.onBack,
    this.actions = const [],
  });

  final String? title;
  final String? eyebrow;
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
            PwaGap.page, PwaGap.md, PwaGap.page, PwaGap.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (onBack != null) ...[
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, color: pwaInk),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
              const SizedBox(width: PwaGap.sm),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (eyebrow != null) ...[
                    PwaEyebrow(eyebrow!),
                    const SizedBox(height: 4),
                  ],
                  if (title != null)
                    Text(title!, style: PwaType.screenTitle()),
                ],
              ),
            ),
            ...actions,
          ],
        ),
      );
}

// ── bottom sheet ────────────────────────────────────────────────────────────

/// The grabber every bottom sheet in the product wears.
class PwaSheetGrabber extends StatelessWidget {
  const PwaSheetGrabber({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(top: PwaGap.sm),
          decoration: BoxDecoration(
            color: pwaHairline,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

/// The shape and colour every modal sheet uses, in one place so a later screen
/// cannot invent a different corner radius.
const ShapeBorder pwaSheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(PwaGap.radiusLg)),
);

/// Open a sheet in the product's geometry.
Future<T?> showPwaSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      backgroundColor: pwaCardSurface,
      barrierColor: pwaImageFrame.withValues(alpha: 0.6),
      shape: pwaSheetShape,
      builder: builder,
    );
