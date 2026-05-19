import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_pill.dart';
import '../../shared/widgets/atmosphere_card.dart';
import '../../shared/widgets/room_type_card.dart';
import '../../shared/widgets/sticky_action_bar.dart';

// ── Wave 4.3 — New Design Session V2 ──────────────────────────────────────────
// Premium architectural-direction flow. Consumes the Wave 4 spine
// (AtmosphereCard V2 incl. .custom, StickyActionBar, AppPill, editorial type).
// In scope: atmosphere V2 + custom fold, premium room-type horizontal scroller
// (exact l10n room strings preserved — route/backend contract), calmer
// dropzone, sticky CTA with a clear premium disabled state, editorial
// hierarchy. NOT included (deferred to a future routing+chat wave, by
// decision): AI-Decide, Surprise-Me, free-text description — they cannot be
// wired honestly without route/chat_screen/backend changes. No backend /
// routing / session / generation changes; picker, validation, route contract
// and session creation preserved verbatim.

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen>
    with SingleTickerProviderStateMixin {
  File? _image;
  String? _selectedRoom;
  String? _selectedStyle;
  final _picker = ImagePicker();

  late final AnimationController _entryController;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();
    _fadeAnim = CurvedAnimation(parent: _entryController, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  // ── Picker (preserved verbatim — non-regression) ──────────────────────────
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
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(l10n.uploadYourSpace,
                  style: Theme.of(sheetCtx).textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.md),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                      color: AppColors.surfaceVariant,
                      shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt_outlined, size: 20),
                ),
                title: Text(l10n.takePhoto),
                subtitle: Text(l10n.takePhotoSub),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                      color: AppColors.surfaceVariant,
                      shape: BoxShape.circle),
                  child: const Icon(Icons.photo_library_outlined, size: 20),
                ),
                title: Text(l10n.chooseGallery),
                subtitle: Text(l10n.chooseGallerySub),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canProceed =>
      _image != null && _selectedRoom != null && _selectedStyle != null;

  // Calm, specific hint for the disabled state (premium, never a dead button).
  String get _missingHint {
    if (_image == null) return 'Add a photo of your space to begin';
    if (_selectedRoom == null) return 'Choose what you\'re transforming';
    return 'Pick an atmosphere direction';
  }

  void _start() {
    context.pushReplacement(
      '/chat/new?roomType=${Uri.encodeComponent(_selectedRoom!)}&style=${Uri.encodeComponent(_selectedStyle!)}',
      extra: _image,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.uploadTitle),
        leading: IconButton(
            icon: const Icon(Icons.close), onPressed: () => context.pop()),
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
                      style: AppTheme.displayEditorial(
                        fontSize: 26,
                        fontWeight: FontWeight.w500,
                        height: 1.15,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.uploadHint,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.5,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _UploadZone(image: _image, onTap: _showImagePicker),
                    const SizedBox(height: AppSpacing.xl),
                    _Eyebrow(label: l10n.roomTypeLabel),
                    const SizedBox(height: AppSpacing.md),
                    _RoomScroller(
                      selected: _selectedRoom,
                      onSelected: (v) => setState(() => _selectedRoom = v),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _Eyebrow(label: l10n.styleLabel),
                    const SizedBox(height: AppSpacing.md),
                    _AtmosphereScroller(
                      selected: _selectedStyle,
                      onSelected: (v) => setState(() => _selectedStyle = v),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ),
            StickyActionBar(
              primary: AppButton(
                label: l10n.startDesign,
                onPressed: _canProceed ? _start : null,
              ),
              secondary: _canProceed
                  ? null
                  : Text(
                      _missingHint,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// Quiet editorial section label (calmer than a titleMedium heading).
class _Eyebrow extends StatelessWidget {
  final String label;
  const _Eyebrow({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            fontSize: 11,
            color: AppColors.textTertiary,
          ),
    );
  }
}

// ── Upload zone — calmer premium empty/filled state ───────────────────────────

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
          borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
          border: Border.all(
            color: image != null ? AppColors.accent : AppColors.border,
            width: image != null ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: image == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_photo_alternate_outlined,
                        size: 30, color: AppColors.textTertiary),
                    const SizedBox(height: 12),
                    Text(
                      context.l10n.uploadPrompt,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'JPG · PNG · HEIC',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
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
                      child: AppPill(
                        text: 'Replace',
                        icon: Icons.edit_outlined,
                        dark: true,
                        onTap: onTap,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ── Room-type — premium horizontal scroller (exact l10n strings kept) ─────────

class _RoomScroller extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onSelected;
  const _RoomScroller({this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RoomGroupLabel(label: l10n.interiorSection),
        const SizedBox(height: 8),
        RoomTypeRow(
          rooms: l10n.interiorRooms,
          selected: selected,
          onSelected: onSelected,
        ),
        const SizedBox(height: 16),
        _RoomGroupLabel(label: l10n.exteriorSection),
        const SizedBox(height: 8),
        RoomTypeRow(
          rooms: l10n.exteriorRooms,
          selected: selected,
          onSelected: onSelected,
        ),
      ],
    );
  }
}

class _RoomGroupLabel extends StatelessWidget {
  final String label;
  const _RoomGroupLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
            color: AppColors.textTertiary,
          ),
    );
  }
}

// Wave 4.10h: the old `_RoomRow` / `_RoomChip` text pills were removed —
// the shared image-led `RoomTypeRow` / `RoomTypeCard` now drive room
// selection in BOTH upload and the chat re-upload sheet (one foundation,
// zero duplicated room-type UI logic). The `(rooms, selected, onSelected)`
// contract — and therefore routing / session / generation — is unchanged.

// ── Atmosphere — shared AtmosphereCard V2 horizontal scroller + custom fold ───

class _AtmosphereScroller extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onSelected;
  const _AtmosphereScroller({this.selected, required this.onSelected});

  // Exact value preserved — route/backend interpret this literal (chat custom
  // path). Do NOT change.
  static const _customLabel = 'Describe Your Dream Space';

  @override
  Widget build(BuildContext context) {
    final atmospheres = AppLocalizations.atmospheres;
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: atmospheres.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index < atmospheres.length) {
            final a = atmospheres[index];
            return SizedBox(
              width: 150,
              child: AtmosphereCard(
                atmosphere: a,
                selected: selected == a.name,
                onTap: () => onSelected(a.name),
              ),
            );
          }
          // Custom — folded into the shared shell (AtmosphereCard.custom).
          return SizedBox(
            width: 150,
            child: AtmosphereCard.custom(
              label: _customLabel,
              sublabel: 'Tell us in your own words',
              selected: selected == _customLabel,
              onTap: () => onSelected(_customLabel),
            ),
          );
        },
      ),
    );
  }
}
