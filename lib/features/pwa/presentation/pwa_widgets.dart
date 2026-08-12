/// Batch 2 — shared premium widgets for the PWA prototype.
///
/// Reuses the existing theme tokens (AppColors/AppSpacing/AppTheme) and the
/// production RevealHero (embedded read-only — no production behaviour change).
/// Ivory surfaces, charcoal text, muted gold accents, editorial serif headings.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/media/ayden_image_source.dart';
import '../../../shared/widgets/reveal_hero.dart';
import '../domain/pwa_models.dart';
import 'pwa_brand.dart';
import 'pwa_stored_image.dart';
import 'pwa_theme.dart';
import '../l10n/pwa_l10n.dart';

const Color kPwaGold = AppColors.accent; // #C8A86A

// Batch 2.1 — offline editorial style (no google_fonts runtime fetch). Kept as
// `pwaSerif` for call-site compatibility; renders in the platform default
// family with restrained luxury tracking/weight.
TextStyle pwaSerif({
  required double fontSize,
  FontWeight fontWeight = FontWeight.w400,
  Color color = AppColors.textPrimary,
  double height = 1.15,
  double letterSpacing = -0.2,
}) => TextStyle(
  fontSize: fontSize,
  fontWeight: fontWeight,
  color: color,
  height: height,
  letterSpacing: letterSpacing,
);

// ── Brand header ─────────────────────────────────────────────────────────────

class PwaBrandHeader extends StatelessWidget {
  const PwaBrandHeader({super.key, this.trailing, this.compact = false});

  final Widget? trailing;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Official logo (compact dark badge) — no invented icon/text wordmark.
        PwaLogoBadge(size: compact ? 30 : 38),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

// ── Reveal image helpers ─────────────────────────────────────────────────────

Widget _imgFallback(BuildContext _, Object _, StackTrace? _) =>
    const ColoredBox(color: AppColors.surfaceVariant);

/// The "before": the user's own photo. In-memory bytes when the session has
/// them (the common case — upload, and hydration on open/boot), otherwise the
/// durable original resolved from Storage. Still an asset for a bundled
/// original, which [PwaStoredImage] handles without a round-trip.
/// What "Before" means for [vision].
///
/// Not the uploaded photo — the image this vision was made FROM. Reported
/// 2026-08-10: the Full Reveal of a second vision still showed the original
/// room, so the comparison answered a question nobody asked ("what did the
/// empty room look like?") instead of the one on screen ("what did this change
/// do?"). A first vision has no parent, and there the photo IS the before.
///
/// Falls back to the photo whenever the parent cannot be resolved: showing the
/// upload is merely less useful, showing nothing is broken.
String pwaBeforeReference(
  PwaVision vision,
  List<PwaVision> versions,
  PwaProject project,
) {
  final parentId = vision.parentVersionId;
  if (parentId != null && parentId.isNotEmpty) {
    for (final v in versions) {
      if (v.versionId == parentId && v.afterAsset.isNotEmpty) return v.afterAsset;
    }
  }
  return project.originalAsset;
}

/// The Before image itself. [source] is the freshly-picked photo held in memory
/// and is only the right answer for a vision with no parent — using it for a
/// child would put the empty room opposite a refinement of a furnished one.
Widget pwaBeforeImage(
  AydenImageSource? source,
  PwaProject project, {
  PwaVision? vision,
  List<PwaVision> versions = const [],
}) {
  final reference = vision == null
      ? project.originalAsset
      : pwaBeforeReference(vision, versions, project);
  final isOriginal = reference == project.originalAsset;
  if (source != null && isOriginal) {
    return Image.memory(source.bytes, fit: BoxFit.cover,
        errorBuilder: _imgFallback);
  }
  return PwaStoredImage(
    key: ValueKey('before-${project.projectId}-$reference'),
    reference: reference,
    placeholderColor: AppColors.surfaceVariant,
  );
}

/// The generated image of [vision]. Its reference is a private Storage path in
/// the real runtime, so it goes through [PwaStoredImage] — which signs it, and
/// which never substitutes a bundle asset when it cannot.
Widget pwaAfterImage(PwaVision vision) => PwaStoredImage(
  key: ValueKey('after-${vision.versionId}'),
  reference: vision.afterAsset,
  placeholderColor: AppColors.surfaceVariant,
);

/// The Full-Reveal card — Before/After of the current vision, tappable to a
/// full-screen view. Reuses the production RevealHero.
class PwaRevealCard extends StatelessWidget {
  const PwaRevealCard({
    super.key,
    required this.vision,
    required this.source,
    this.versions = const [],
    required this.project,
    this.aspectRatio = 4 / 3,
    this.onDark = false,
    this.showCaption = true,
  });

  final PwaVision vision;
  final AydenImageSource? source;

  /// The lineage, so "Before" can be resolved to this vision's parent.
  final List<PwaVision> versions;
  final PwaProject project;
  final double aspectRatio;

  /// When the card sits on a dark design surface (the Architect workspace / a
  /// dark reveal frame) the caption below the image switches to warm-white.
  final bool onDark;

  /// V7 — when false, the built-in "Vision N · title" caption row is omitted so
  /// the caller can render its own metadata strip (the Architect Full Reveal
  /// shows a "Vision N • atmosphere • Created just now" line instead).
  final bool showCaption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
          child: Stack(
            children: [
              RevealHero(
                key: ValueKey('reveal-${vision.versionId}'),
                afterImage: pwaAfterImage(vision),
                beforeImage: pwaBeforeImage(source, project,
                    vision: vision, versions: versions),
                initialFraction: 0.32,
                autoSweep: true,
                aspectRatio: aspectRatio,
                beforeLabel: context.pwaL10n.beforeLabel,
                afterLabel: context.pwaL10n.afterLabel,
                showLabels: true,
              ),
              // §9 — the full-screen affordance lives at the BOTTOM-right so it
              // never overlaps the top-corner Before / After labels, at any
              // divider position or width.
              Positioned(
                bottom: 10,
                right: 10,
                child: _FullscreenButton(
                  onTap: () => showPwaFullscreenReveal(
                    context,
                    vision: vision,
                    source: source,
                    project: project,
                    versions: versions,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showCaption) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              _VisionChip(label: context.pwaL10n.visionN(vision.visionNumber)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  vision.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: pwaSerif(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: onDark ? pwaOnDark : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _VisionChip extends StatelessWidget {
  const _VisionChip({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.textPrimary,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: AppColors.surface,
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
      ),
    ),
  );
}

class _FullscreenButton extends StatelessWidget {
  const _FullscreenButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: 0.45),
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: const Padding(
        padding: EdgeInsets.all(8),
        child: Icon(Icons.fullscreen, size: 20, color: Colors.white),
      ),
    ),
  );
}

Future<void> showPwaFullscreenReveal(
  BuildContext context, {
  required PwaVision vision,
  required AydenImageSource? source,
  required PwaProject project,
  List<PwaVision> versions = const [],
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    builder: (ctx) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      // §8 — Escape closes the full-screen reveal (keyboard accessible).
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(ctx).pop(),
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            children: [
              Center(
                child: RevealHero(
                  afterImage: pwaAfterImage(vision),
                  beforeImage: pwaBeforeImage(source, project,
                    vision: vision, versions: versions),
                  initialFraction: 0.32,
                  autoSweep: true,
                  beforeLabel: context.pwaL10n.beforeLabel,
                  afterLabel: context.pwaL10n.afterLabel,
                  showLabels: true,
                ),
              ),
              // Discreet version + atmosphere caption (§8).
              Positioned(
                left: 20,
                bottom: 20,
                child: SafeArea(
                  child: Text(
                    '${context.pwaL10n.visionN(vision.visionNumber)} · ${vision.title}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: SafeArea(
                  child: IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: () => Navigator.of(ctx).pop(),
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

// ── Atmosphere strip ─────────────────────────────────────────────────────────

class PwaAtmosphereStrip extends StatelessWidget {
  const PwaAtmosphereStrip({
    super.key,
    required this.atmospheres,
    required this.selectedId,
    required this.onSelected,
    this.enabled = true,
  });

  final List<PwaAtmosphere> atmospheres;
  final String? selectedId;
  final ValueChanged<String> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: atmospheres.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final a = atmospheres[i];
          final selected = a.id == selectedId;
          return _AtmosphereTile(
            atmosphere: a,
            selected: selected,
            onTap: enabled ? () => onSelected(a.id) : null,
          );
        },
      ),
    );
  }
}

class _AtmosphereTile extends StatelessWidget {
  const _AtmosphereTile({
    required this.atmosphere,
    required this.selected,
    required this.onTap,
  });
  final PwaAtmosphere atmosphere;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? kPwaGold
        : (atmosphere.isSignature
              ? kPwaGold.withValues(alpha: 0.5)
              : AppColors.border);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 92,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: selected ? 2 : 1),
                boxShadow: atmosphere.isSignature
                    ? [
                        BoxShadow(
                          color: kPwaGold.withValues(alpha: 0.18),
                          blurRadius: 10,
                        ),
                      ]
                    : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: AspectRatio(
                aspectRatio: 1.2,
                child: Image.asset(
                  atmosphere.asset,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: AppColors.surfaceVariant),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                if (atmosphere.isSignature)
                  const Padding(
                    padding: EdgeInsets.only(right: 3),
                    child: Icon(Icons.auto_awesome, size: 11, color: kPwaGold),
                  ),
                Expanded(
                  child: Text(
                    atmosphere.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Version filmstrip ────────────────────────────────────────────────────────

class PwaVersionFilmstrip extends StatelessWidget {
  const PwaVersionFilmstrip({
    super.key,
    required this.versions,
    required this.currentId,
    required this.onSelected,
    this.onViewAll,
  });

  final List<PwaVision> versions;
  final String? currentId;
  final ValueChanged<String> onSelected;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 74,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: versions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final v = versions[i];
                final selected = v.versionId == currentId;
                return GestureDetector(
                  onTap: () => onSelected(v.versionId),
                  child: Container(
                    width: 70,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected ? kPwaGold : AppColors.border,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        PwaStoredImage(
                          key: ValueKey('filmstrip-${v.versionId}'),
                          reference: v.afterAsset,
                          placeholderColor: AppColors.surfaceVariant,
                        ),
                        Positioned(
                          left: 3,
                          bottom: 3,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'V${v.visionNumber}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (onViewAll != null) ...[
            const SizedBox(width: 8),
            _ViewAllButton(count: versions.length, onTap: onViewAll!),
          ],
        ],
      ),
    );
  }
}

class _ViewAllButton extends StatelessWidget {
  const _ViewAllButton({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 62,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.grid_view_rounded,
            size: 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 3),
          Text(
            context.pwaL10n.allCount(count),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    ),
  );
}

// ── Chat: text bubble + chips + composer ─────────────────────────────────────

class PwaTextBubble extends StatelessWidget {
  const PwaTextBubble({super.key, required this.message});
  final PwaMessage message;

  @override
  Widget build(BuildContext context) {
    final isAyden = message.role == PwaRole.ayden;
    return Align(
      alignment: isAyden ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: isAyden ? AppColors.surface : AppColors.textPrimary,
          borderRadius: BorderRadius.circular(16),
          border: isAyden ? Border.all(color: AppColors.border) : null,
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: isAyden ? AppColors.textPrimary : AppColors.surface,
            fontSize: 14,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

class PwaLoadingBubble extends StatelessWidget {
  const PwaLoadingBubble({super.key, this.label});

  /// Null = "use the current language's default". Resolved in `build`, not in
  /// the constructor, so the bubble follows a language change while visible.
  final String? label;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: kPwaGold),
          ),
          const SizedBox(width: 10),
          Text(
            label ?? context.pwaL10n.creatingYourVision,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    ),
  );
}

class PwaChips extends StatelessWidget {
  const PwaChips({super.key, required this.chips, required this.onTap});
  final List<String> chips;
  final ValueChanged<String> onTap;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final c in chips)
        GestureDetector(
          onTap: () => onTap(c),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: kPwaGold.withValues(alpha: 0.55)),
            ),
            child: Text(
              c,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
    ],
  );
}

class PwaComposer extends StatefulWidget {
  const PwaComposer({super.key, required this.onSend, this.enabled = true});
  final ValueChanged<String> onSend;
  final bool enabled;
  @override
  State<PwaComposer> createState() => _PwaComposerState();
}

class _PwaComposerState extends State<PwaComposer> {
  final _ctrl = TextEditingController();

  void _send() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    widget.onSend(t);
    _ctrl.clear();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                enabled: widget.enabled,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: context.pwaL10n.askAydenAnything,
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: const BorderSide(color: kPwaGold, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: widget.enabled ? kPwaGold : AppColors.border,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.enabled ? _send : null,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(
                    Icons.arrow_upward,
                    size: 20,
                    color: Colors.white,
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
