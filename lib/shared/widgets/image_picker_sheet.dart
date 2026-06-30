import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';

// CHANTIER UX — premium "Upload your space" bottom sheet. Two clear entry
// paths: (1) your own photo (Camera / Gallery), (2) "Try Ayden instantly" with
// an example room — promoted to a real second path (hero + small cards) instead
// of a secondary strip. Shared by BOTH the New Design upload screen and the
// in-chat Replace Photo flow, so the constructor (onCamera/onGallery/onExample)
// is UNCHANGED — only the presentation. No backend / generation change.

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

class _PickerExample {
  final String asset;
  final String label;
  final IconData icon;
  const _PickerExample(this.asset, this.label, this.icon);
}

class ImagePickerSheet extends StatelessWidget {
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final void Function(String asset) onExample;

  const ImagePickerSheet({
    super.key,
    required this.onCamera,
    required this.onGallery,
    required this.onExample,
  });

  // The Living Room is the recommended hero entry. The small row below is built
  // from the remaining example assets. To add a 3rd small card (e.g. Bathroom),
  // drop `assets/examples/bathroom.jpg` in and append it to `smalls` — the
  // `bathroom` label + Icons.bathtub_outlined already exist; the Row adapts.
  static const String _heroAsset = 'assets/examples/living_room.jpg';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final smalls = <_PickerExample>[
      _PickerExample(
          'assets/examples/kitchen.jpg', l.kitchen, Icons.countertops_outlined),
      _PickerExample(
          'assets/examples/bedroom.jpg', l.masterBedroom, Icons.bed_outlined),
    ];
    // ~70% of the screen: the wizard (Step 1) stays visible & dimmed behind.
    final sheetH =
        (MediaQuery.sizeOf(context).height * 0.70).clamp(460.0, 760.0);

    return Container(
      height: sheetH,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                l.uploadYourSpace,
                textAlign: TextAlign.center,
                style: AppTheme.displayEditorial(
                    fontSize: 25, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 5),
              Text(
                l.uplPickerSubtitle,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: _pkMuted, fontSize: 13, height: 1.3),
              ),
              const SizedBox(height: 16),
              // Scrollable middle — guarantees no overflow on small iPhones,
              // stays compact and premium on large screens.
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l.uplOwnSpace,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _UploadActionCard(
                              icon: Icons.camera_alt_outlined,
                              label: l.uplCamera,
                              onTap: onCamera,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _UploadActionCard(
                              icon: Icons.image_outlined,
                              label: l.uplGallery,
                              onTap: onGallery,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _OrDivider(label: l.uplOr),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Text('✨', style: TextStyle(fontSize: 15)),
                          const SizedBox(width: 7),
                          Text(
                            l.uplTryInstantly,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 11),
                      _ExampleHeroCard(
                        asset: _heroAsset,
                        label: l.livingRoom,
                        icon: Icons.weekend_outlined,
                        recommendedLabel: l.uplRecommended,
                        onTap: () => onExample(_heroAsset),
                      ),
                      const SizedBox(height: 11),
                      Row(
                        children: [
                          for (var i = 0; i < smalls.length; i++) ...[
                            if (i > 0) const SizedBox(width: 11),
                            Expanded(
                              child: _ExampleSmallCard(
                                example: smalls[i],
                                onTap: () => onExample(smalls[i].asset),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const _PickerPrivacyFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _UploadActionCard({
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
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 124,
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
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _pkChampagne.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: _pkChampagne, size: 22),
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

class _OrDivider extends StatelessWidget {
  final String label;
  const _OrDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: Container(height: 1, color: _pkCreamBorder),
    );
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: const TextStyle(
              color: _pkMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
        ),
        line,
      ],
    );
  }
}

/// Bottom gradient + bottom-left icon/label, shared by hero & small cards.
class _CardOverlay extends StatelessWidget {
  final String asset;
  final IconData icon;
  final String label;
  final double labelSize;
  final double iconSize;
  const _CardOverlay({
    required this.asset,
    required this.icon,
    required this.label,
    this.labelSize = 14,
    this.iconSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          asset,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const ColoredBox(color: _pkCreamBorder),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0x8C000000), Color(0x00000000)],
              stops: [0.0, 0.62],
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 11,
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: iconSize),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: labelSize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExampleHeroCard extends StatelessWidget {
  final String asset;
  final String label;
  final IconData icon;
  final String recommendedLabel;
  final VoidCallback onTap;

  const _ExampleHeroCard({
    required this.asset,
    required this.label,
    required this.icon,
    required this.recommendedLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AspectRatio(
          aspectRatio: 2.3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _CardOverlay(
                  asset: asset, icon: icon, label: label, labelSize: 16),
              Positioned(
                left: 12,
                top: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: _pkChampagne,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    recommendedLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExampleSmallCard extends StatelessWidget {
  final _PickerExample example;
  final VoidCallback onTap;
  const _ExampleSmallCard({required this.example, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: 1.35,
          child: _CardOverlay(
            asset: example.asset,
            icon: example.icon,
            label: example.label,
            labelSize: 12.5,
            iconSize: 13,
          ),
        ),
      ),
    );
  }
}

class _PickerPrivacyFooter extends StatelessWidget {
  const _PickerPrivacyFooter();

  @override
  Widget build(BuildContext context) {
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
