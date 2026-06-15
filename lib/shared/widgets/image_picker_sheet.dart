import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';

// CHANTIER C #1 — shared premium image-source picker (Camera / Gallery /
// Examples). Used by BOTH the New Design upload screen and the in-chat Replace
// Photo flow so the two surfaces offer the exact same premium UX. The widget +
// its sub-widgets were extracted verbatim from upload_screen.dart — no
// behavioural change, only made shareable.

/// Fire-and-forget convenience: shows the picker and pops it on selection,
/// then runs the matching callback. (New Design upload screen.)
void showAydenImagePicker(
  BuildContext context, {
  required VoidCallback onCamera,
  required VoidCallback onGallery,
  required void Function(String asset) onExample,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => ImagePickerSheet(
      onCamera: () {
        Navigator.pop(sheetCtx);
        onCamera();
      },
      onGallery: () {
        Navigator.pop(sheetCtx);
        onGallery();
      },
      onExample: (asset) {
        Navigator.pop(sheetCtx);
        onExample(asset);
      },
    ),
  );
}

const Color _pkCream = Color(0xFFF6F2EB);
const Color _pkCreamBorder = Color(0xFFEBE4D9);
const Color _pkMuted = Color(0xFF8C857B);
const Color _pkChampagne = Color(0xFFC2A172);
// Softer than _pkCream — used for the SECONDARY example section so it recedes
// (less contrast vs. the white sheet) while the Camera/Gallery cards stay
// visually dominant on _pkCream.
const Color _pkCreamSoft = Color(0xFFFAF8F4);

class _PickerExample {
  final String asset;
  final String label;
  final IconData icon;
  const _PickerExample(this.asset, this.label, this.icon);
}

class ImagePickerSheet extends StatefulWidget {
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final void Function(String asset) onExample;

  const ImagePickerSheet({
    super.key,
    required this.onCamera,
    required this.onGallery,
    required this.onExample,
  });

  @override
  State<ImagePickerSheet> createState() => ImagePickerSheetState();
}

class ImagePickerSheetState extends State<ImagePickerSheet> {
  final ScrollController _scroll = ScrollController();

  // Blank "before" rooms — replace these 3 files with the real shots you'll
  // provide (same paths). Selecting one uploads it instantly.
  static const _examples = <_PickerExample>[
    _PickerExample(
        'assets/examples/living_room.jpg', 'Living Room', Icons.weekend_outlined),
    _PickerExample(
        'assets/examples/kitchen.jpg', 'Kitchen', Icons.countertops_outlined),
    _PickerExample(
        'assets/examples/bedroom.jpg', 'Bedroom', Icons.bed_outlined),
  ];

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollRight() {
    if (!_scroll.hasClients) return;
    final target =
        (_scroll.offset + 150).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target,
        duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 28,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppColors.border.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                context.l10n.uploadYourSpace,
                textAlign: TextAlign.center,
                style: AppTheme.displayEditorial(
                    fontSize: 26, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 5),
              Text(
                context.l10n.uplPickerSubtitle,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: _pkMuted, fontSize: 13, height: 1.3),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _PickerSourceCard(
                      icon: Icons.camera_alt_outlined,
                      label: context.l10n.uplCamera,
                      onTap: widget.onCamera,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _PickerSourceCard(
                      icon: Icons.image_outlined,
                      label: context.l10n.uplGallery,
                      onTap: widget.onGallery,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
                decoration: BoxDecoration(
                  color: _pkCreamSoft,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: _pkCreamBorder.withValues(alpha: 0.6)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            color: _pkChampagne, size: 17),
                        const SizedBox(width: 7),
                        Text(
                          context.l10n.uplExamplePhotos,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.uplExampleHint,
                      style: const TextStyle(color: _pkMuted, fontSize: 11.5),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 96,
                      child: Stack(
                        children: [
                          ListView.separated(
                            controller: _scroll,
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            clipBehavior: Clip.none,
                            itemCount: _examples.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 10),
                            itemBuilder: (_, i) {
                              final ex = _examples[i];
                              final labels = [
                                context.l10n.livingRoom,
                                context.l10n.kitchen,
                                context.l10n.masterBedroom,
                              ];
                              return _ExamplePhotoCard(
                                example:
                                    _PickerExample(ex.asset, labels[i], ex.icon),
                                onTap: () => widget.onExample(ex.asset),
                              );
                            },
                          ),
                          Positioned(
                            right: -2,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: _CarouselArrow(onTap: _scrollRight),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const _PickerPrivacyFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerSourceCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PickerSourceCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: _pkCream,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _pkCreamBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _pkChampagne.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: _pkChampagne, size: 21),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExamplePhotoCard extends StatelessWidget {
  final _PickerExample example;
  final VoidCallback onTap;

  const _ExamplePhotoCard({required this.example, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 110,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                // #24/#1 — show the FULL example room, never crop it. The
                // photo is letterboxed on a neutral frame instead of being
                // cover-cropped to fill the thumbnail.
                child: ColoredBox(
                  color: const Color(0xFF0B0B0C),
                  child: Image.asset(
                    example.asset,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: _pkCreamBorder),
                  ),
                ),
              ),
              Container(
                color: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Icon(example.icon, size: 13, color: _pkMuted),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        example.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CarouselArrow extends StatelessWidget {
  final VoidCallback onTap;
  const _CarouselArrow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Deliberately understated (brief #5): soft translucent disc, no heavy
    // border, gentle chevron — a quiet "there's more" cue, not a web control.
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.82),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(Icons.chevron_right, size: 18, color: _pkMuted),
      ),
    );
  }
}

class _PickerPrivacyFooter extends StatelessWidget {
  const _PickerPrivacyFooter();

  @override
  Widget build(BuildContext context) {
    // Minimal single-line reassurance — present but unobtrusive.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.lock_outline, size: 13, color: _pkMuted),
        const SizedBox(width: 7),
        Text(
          context.l10n.uplPrivacy,
          style: const TextStyle(color: _pkMuted, fontSize: 11.5),
        ),
      ],
    );
  }
}
