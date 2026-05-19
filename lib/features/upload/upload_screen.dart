import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/layout/adaptive_layout.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/atmosphere_card.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> with SingleTickerProviderStateMixin {
  File? _image;
  String? _selectedRoom;
  String? _selectedStyle;
  final _picker = ImagePicker();

  late final AnimationController _entryController;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();
    _fadeAnim = CurvedAnimation(parent: _entryController, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked != null) setState(() => _image = File(picked.path));
  }

  void _showImagePicker() {
    final l10n = context.l10n;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(l10n.uploadYourSpace, style: Theme.of(sheetCtx).textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.md),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.surfaceVariant, shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt_outlined, size: 20),
                ),
                title: Text(l10n.takePhoto),
                subtitle: Text(l10n.takePhotoSub),
                onTap: () { Navigator.pop(sheetCtx); _pickImage(ImageSource.camera); },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.surfaceVariant, shape: BoxShape.circle),
                  child: const Icon(Icons.photo_library_outlined, size: 20),
                ),
                title: Text(l10n.chooseGallery),
                subtitle: Text(l10n.chooseGallerySub),
                onTap: () { Navigator.pop(sheetCtx); _pickImage(ImageSource.gallery); },
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canProceed => _image != null && _selectedRoom != null && _selectedStyle != null;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.uploadTitle),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => context.pop()),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  AppSpacing.pagePadding,
                  AppSpacing.pagePadding,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.uploadSubtitle,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.uploadHint,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _UploadZone(image: _image, onTap: _showImagePicker),
                    const SizedBox(height: AppSpacing.xl),
                    _SectionLabel(label: l10n.roomTypeLabel),
                    const SizedBox(height: AppSpacing.sm),
                    _GroupedRoomSelector(
                      selected: _selectedRoom,
                      onSelected: (v) => setState(() => _selectedRoom = v),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _SectionLabel(label: l10n.styleLabel),
                    const SizedBox(height: AppSpacing.sm),
                    _StyleGrid(
                      selected: _selectedStyle,
                      onSelected: (v) => setState(() => _selectedStyle = v),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.pagePadding,
                AppSpacing.md,
                AppSpacing.pagePadding,
                AppSpacing.md + MediaQuery.of(context).padding.bottom,
              ),
              decoration: const BoxDecoration(
                color: AppColors.background,
                border: Border(top: BorderSide(color: AppColors.borderLight)),
              ),
              child: AnimatedOpacity(
                opacity: _canProceed ? 1.0 : 0.45,
                duration: const Duration(milliseconds: 300),
                child: AppButton(
                  label: l10n.startDesign,
                  onPressed: _canProceed
                      ? () => context.pushReplacement(
                            '/chat/new?roomType=${Uri.encodeComponent(_selectedRoom!)}&style=${Uri.encodeComponent(_selectedStyle!)}',
                            extra: _image,
                          )
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(label, style: Theme.of(context).textTheme.titleMedium);
  }
}

class _UploadZone extends StatelessWidget {
  final File? image;
  final VoidCallback onTap;
  const _UploadZone({this.image, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: image == null ? AppColors.surfaceVariant : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(
            color: image != null ? AppColors.accent : AppColors.border,
            width: image != null ? 2 : 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: image == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(Icons.add_photo_alternate_outlined, size: 28, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 14),
                    Text(context.l10n.uploadPrompt, style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    Text(
                      'JPG · PNG · HEIC',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(image!, fit: BoxFit.cover),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: GestureDetector(
                        onTap: onTap,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: AppColors.surface,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.edit_outlined, size: 16, color: AppColors.textPrimary),
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

class _GroupedRoomSelector extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onSelected;
  const _GroupedRoomSelector({this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.interiorSection,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: AppColors.textTertiary,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: l10n.interiorRooms
              .map((r) => _Chip(label: r, selected: selected == r, onTap: () => onSelected(r)))
              .toList(),
        ),
        const SizedBox(height: 14),
        Text(
          l10n.exteriorSection,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: AppColors.textTertiary,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: l10n.exteriorRooms
              .map((r) => _Chip(label: r, selected: selected == r, onTap: () => onSelected(r)))
              .toList(),
        ),
      ],
    );
  }
}

class _StyleGrid extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onSelected;
  const _StyleGrid({this.selected, required this.onSelected});

  static const _customLabel = 'Describe Your Dream Space';

  @override
  Widget build(BuildContext context) {
    final atmospheres = AppLocalizations.atmospheres;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: AppAdaptive.uploadAtmosphereAspectRatio,
      ),
      itemCount: atmospheres.length + 1,
      itemBuilder: (context, index) {
        if (index < atmospheres.length) {
          final a = atmospheres[index];
          return AtmosphereCard(
            atmosphere: a,
            selected: selected == a.name,
            onTap: () => onSelected(a.name),
          );
        }
        return _CustomAtmosphereCard(
          selected: selected == _customLabel,
          onTap: () => onSelected(_customLabel),
        );
      },
    );
  }
}

class _CustomAtmosphereCard extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  const _CustomAtmosphereCard({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: selected ? AppColors.textPrimary : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(
            color: selected ? AppColors.textPrimary : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.edit_note_outlined,
              size: 32,
              color: selected ? AppColors.surface : AppColors.textSecondary,
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Describe Your\nDream Space',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected ? AppColors.surface : AppColors.textPrimary,
                    ),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Tell us in your own words',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: selected
                          ? AppColors.surface.withValues(alpha: 0.7)
                          : AppColors.textTertiary,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.textPrimary : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
          border: Border.all(
            color: selected ? AppColors.textPrimary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: selected ? AppColors.surface : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
        ),
      ),
    );
  }
}
