/// Batch 2 — premium PWA upload entry. Sells without a sales page.
///
/// One photo → one click → Ayden creates the vision. No FTUE, no mandatory room
/// or atmosphere choice, no login, no pricing. Uses the bytes-first pipeline
/// (Batch 1B) — no network upload. Ayden Decide / Ayden Signature are shown as
/// subtle confidence indicators, not buttons.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/media/image_pipeline.dart';
import '../../../shared/widgets/reveal_hero.dart';
import '../application/pwa_controller.dart';
import '../application/pwa_layout.dart';
import 'pwa_widgets.dart';

class PwaUploadScreen extends ConsumerStatefulWidget {
  const PwaUploadScreen({super.key});

  @override
  ConsumerState<PwaUploadScreen> createState() => _PwaUploadScreenState();
}

class _PwaUploadScreenState extends ConsumerState<PwaUploadScreen> {
  final _picker = ImagePicker();

  Future<void> _pickFromGallery() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null) return;
    final img = await ImagePipeline.fromXFile(x);
    ref.read(pwaControllerProvider.notifier).setSource(img);
  }

  Future<void> _useExample() async {
    final img = await ImagePipeline.fromAsset('assets/examples/living_room.jpg');
    ref.read(pwaControllerProvider.notifier).setSource(img);
  }

  void _generate() => ref.read(pwaControllerProvider.notifier).generateFirstVision();

  void _customize() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Customize (room + atmosphere) — prototype-only. '
            'The fast default flow always stays one click.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pwaControllerProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final ff = pwaFormFactorForWidth(c.maxWidth);
            final wide = ff == PwaFormFactor.desktop;
            final content = Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: wide ? 40 : AppSpacing.pagePadding, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: pwaMaxContentWidth(ff)),
                child: wide
                    ? SingleChildScrollView(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: _leftColumn(state.hasSource)),
                            const SizedBox(width: 48),
                            const Expanded(child: _EvidencePanel()),
                          ],
                        ),
                      )
                    : SingleChildScrollView(child: _leftColumn(state.hasSource)),
              ),
            );
            return Center(child: content);
          },
        ),
      ),
    );
  }

  Widget _leftColumn(bool hasSource) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PwaBrandHeader(),
        const SizedBox(height: 28),
        Text('Upload your room.\nLet Ayden design the rest.',
            style: pwaSerif(fontSize: 30, fontWeight: FontWeight.w500, height: 1.12)),
        const SizedBox(height: 10),
        const Text(
          'One photo. One click. Your AI architect creates the first vision.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 15, height: 1.4),
        ),
        const SizedBox(height: 24),
        _UploadZone(
          onPick: _pickFromGallery,
          onExample: _useExample,
          onRemove: () => ref.read(pwaControllerProvider.notifier).removeSource(),
        ),
        const SizedBox(height: 18),
        if (hasSource) ...[
          const _ConfidenceRow(),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: _PrimaryButton(label: 'Generate my vision', onTap: _generate),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: _customize,
              child: const Text('Customize instead',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ),
          ),
        ],
        const SizedBox(height: 6),
        const Center(
          child: Text('First AI vision free',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
        ),
      ],
    );
  }
}

class _UploadZone extends ConsumerWidget {
  const _UploadZone(
      {required this.onPick, required this.onExample, required this.onRemove});
  final VoidCallback onPick;
  final VoidCallback onExample;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(pwaControllerProvider).source;
    if (source != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Container(
                color: const Color(0xFF0B0B0C),
                child: Image.memory(
                  source.bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: Color(0xFF0B0B0C)),
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Row(
                children: [
                  _MiniButton(icon: Icons.edit_outlined, label: 'Replace', onTap: onPick),
                  const SizedBox(width: 8),
                  _MiniButton(icon: Icons.close, label: 'Remove', onTap: onRemove),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return GestureDetector(
      onTap: onPick,
      child: DottedUploadBox(onExample: onExample),
    );
  }
}

class DottedUploadBox extends StatelessWidget {
  const DottedUploadBox({super.key, required this.onExample});
  final VoidCallback onExample;
  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_photo_alternate_outlined,
                size: 34, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            const Text('Upload a photo of your room',
                style: TextStyle(
                    color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            const Text('JPG · PNG · HEIC',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onExample,
              icon: const Icon(Icons.auto_awesome, size: 15, color: kPwaGold),
              label: const Text('Try an example'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: BorderSide(color: kPwaGold.withValues(alpha: 0.6)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfidenceRow extends StatelessWidget {
  const _ConfidenceRow();
  @override
  Widget build(BuildContext context) => Row(
        children: const [
          Expanded(
            child: _ConfidencePill(
              title: 'Ayden Decide',
              subtitle: 'Space identified automatically',
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: _ConfidencePill(
              title: 'Ayden Signature',
              subtitle: 'Creative direction selected',
            ),
          ),
        ],
      );
}

class _ConfidencePill extends StatelessWidget {
  const _ConfidencePill({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kPwaGold.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, size: 16, color: kPwaGold),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.textTertiary)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _EvidencePanel extends StatelessWidget {
  const _EvidencePanel();
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
          child: RevealHero(
            afterImage: Image.asset('assets/showcase/villa_after.jpg', fit: BoxFit.cover),
            beforeImage: Image.asset('assets/showcase/villa_before.jpg', fit: BoxFit.cover),
            aspectRatio: 4 / 3,
            initialFraction: 0.3,
            beforeLabel: 'Before',
            afterLabel: 'After',
          ),
        ),
        const SizedBox(height: 10),
        const Text('Real spaces, reimagined in seconds.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.textPrimary,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text('$label  ✨',
                  style: const TextStyle(
                      color: AppColors.surface,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      );
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 14, color: Colors.white),
              const SizedBox(width: 5),
              Text(label,
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ]),
          ),
        ),
      );
}
