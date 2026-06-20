import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/locale_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/free_tier.dart';
import '../../core/constants/room_type_images.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/models/atmosphere_style.dart';
import '../../core/providers/premium_provider.dart';
import '../../core/providers/access_provider.dart';
import '../../core/providers/me_status_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/image_picker_sheet.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_pill.dart';
import '../../core/services/voice_service.dart';
import '../../shared/widgets/atmosphere_card.dart';
import '../../shared/widgets/room_type_card.dart';
import '../../shared/widgets/sticky_action_bar.dart';
import '../chat/widgets/chat_input_bar.dart' show MicButton;
import '../paywall/paywall_sheet.dart';
import '../../core/feature_flags.dart';
import '../cards/card_catalog.dart';
import '../cards/widgets/ai_action_card.dart';
import '../cards/widgets/atmosphere_hero_card.dart';
import '../cards/widgets/room_card.dart';

// ── Wave 5.8 → 5.16 — New Design Screen Redesign (4-step architectural journey)
// 5.8 reframed the upload flow as 5 explicit, persistent steps with a guided
// stepper roadmap. 5.16 — FTUE Simplification & V1 Focus — drops the
// "Redesign Options" step (Preserve vs Reimagine chooser) from FTUE for V1
// product clarity. The flow becomes:
//   1. Upload  →  2. Room Type  →  3. Atmosphere  →  4. Your Vision (optional)
// Generation always uses preserve mode at this entry point. The advanced
// creative-mode flip remains accessible later via the chat-screen Design
// Direction sheet (_SheetModeToggle), per the V1 product positioning :
// preserve onboarding, creative refinement-time.
// Premium editorial feeling preserved (calm, architect-like, not a settings
// form). Persistent left vertical stepper on tablet/desktop; compact
// horizontal top stepper on phones — scroll-driven highlight +
// click-to-scroll.
// Backend contract unchanged : room_type / style_label / generation_mode
// flow as before ; generation_mode now simply takes its server-side default
// ("preserve") since the FTUE no longer sends the param. AI Decide and
// Surprise Me remain real cards inside their respective selectors.

class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({super.key});

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen>
    with SingleTickerProviderStateMixin {
  File? _image;
  String? _selectedRoom;
  String? _selectedStyle;
  // Wave 4.8.5 — AI Decide ⇄ explicit room are mutually exclusive; Surprise
  // Me ⇄ explicit atmosphere likewise. Carried as flags, never fake strings.
  bool _aiDecideRoom = false;
  bool _surpriseStyle = false;
  // Wave 5.16 — `_selectedMode` field removed. FTUE always launches in
  // preserve mode (backend default). The chat Design Direction sheet still
  // exposes the toggle for refinement-time creative flips.
  final _descController = TextEditingController();
  final _picker = ImagePicker();

  // Wave 5.8 — stepper plumbing. One GlobalKey per step section so we can
  // click-to-scroll (Scrollable.ensureVisible) and a scroll listener that
  // updates [_currentStep] based on which section's top has crossed the
  // viewport's reading line.
  // Wave 5.16 — stepKey count drops 5 → 4 (Redesign Options removed).
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _stepKeys = List.generate(4, (_) => GlobalKey());
  int _currentStep = 1;

  late final AnimationController _entryController;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();
    _fadeAnim = CurvedAnimation(parent: _entryController, curve: Curves.easeOut);
    _scrollController.addListener(_recomputeCurrentStep);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_recomputeCurrentStep);
    _scrollController.dispose();
    _descController.dispose();
    _entryController.dispose();
    super.dispose();
  }

  // Find the deepest step whose header has crossed the "reading line" near
  // the top of the viewport. Avoids fighting with very tall sections (a
  // long Atmosphere strip never makes Vision feel current unless the user
  // scrolls past its bottom).
  void _recomputeCurrentStep() {
    final scrollBox =
        _scrollController.position.context.notificationContext?.findRenderObject()
            as RenderBox?;
    if (scrollBox == null) return;
    final viewportTop = scrollBox.localToGlobal(Offset.zero).dy;
    // Reading line ~120 px below viewport top (roughly: just under the
    // sticky AppBar). Anything above this counts as "passed".
    final readingLine = viewportTop + 120;
    int newStep = 1;
    for (var i = 0; i < _stepKeys.length; i++) {
      final ctx = _stepKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final dy = box.localToGlobal(Offset.zero).dy;
      if (dy <= readingLine) {
        newStep = i + 1;
      } else {
        break;
      }
    }
    if (newStep != _currentStep) {
      setState(() => _currentStep = newStep);
    }
  }

  void _scrollToStep(int step) {
    final ctx = _stepKeys[step - 1].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
      alignment: 0.05, // small offset from viewport top
    );
  }

  // ── Picker (preserved verbatim — non-regression) ──────────────────────────
  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked != null) {
      setState(() {
        _image = File(picked.path);
        _applyDefaultsAfterUpload();
      });
    }
  }

  void _showImagePicker() {
    if (FeatureFlags.uploadPickerV2) {
      _showImagePickerV2();
    } else {
      _showImagePickerV1();
    }
  }

  // AYDEN premium picker — serif title + Camera/Gallery cards + "Example
  // photos" carousel (blank before-rooms to test instantly) + privacy footer.
  void _showImagePickerV2() {
    // CHANTIER C #1 — now the SHARED picker (same component as in-chat Replace
    // Photo). Behaviour unchanged: pop on pick, then Camera/Gallery/Example.
    showAydenImagePicker(
      context,
      onCamera: () => _pickImage(ImageSource.camera),
      onGallery: () => _pickImage(ImageSource.gallery),
      onExample: _useExamplePhoto,
    );
  }

  // Selecting an example = uploading it. The bundled asset is copied to a temp
  // file and assigned to `_image` exactly like a Camera/Gallery pick, so the
  // entire downstream flow (4 steps → generation) is unchanged.
  Future<void> _useExamplePhoto(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      final file = File(
        '${Directory.systemTemp.path}/ayden_example_'
        '${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      if (!mounted) return;
      setState(() {
        _image = file;
        _applyDefaultsAfterUpload();
      });
    } catch (e) {
      debugPrint('[Upload] example photo load failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.uplExampleLoadError)),
      );
    }
  }

  void _showImagePickerV1() {
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

  bool get _roomChosen => _selectedRoom != null || _aiDecideRoom;
  bool get _styleChosen => _selectedStyle != null || _surpriseStyle;
  bool get _canProceed => _image != null && _roomChosen && _styleChosen;

  // Wave — seed sensible defaults the moment a photo is uploaded so the user
  // can hit Generate immediately. Only seeds when nothing is chosen yet, so it
  // never overrides a deliberate pick (incl. a Replace-photo with prior choices).
  //   • Room  → Ayden Decide (free for everyone; renders great as-is).
  //   • Style → Warm Modern (first atmosphere, free tier, universal starter).
  // Called inside an existing setState by the callers.
  void _applyDefaultsAfterUpload() {
    if (_selectedRoom == null && !_aiDecideRoom) {
      // Default everyone to Ayden Decide: it's free (FeatureFlags.aydenDecideFree
      // + backend AYDEN_DECIDE_FREE) and renders great as-is — gpt-image-1 reads
      // the room from the source photo and the lean prompt keeps the atmosphere
      // native. The user can still pick an explicit room.
      _aiDecideRoom = true;
    }
    if (_selectedStyle == null && !_surpriseStyle) {
      final wm = AppLocalizations.atmospheres
          .firstWhere((a) => a.id == kDefaultAtmosphereId);
      _selectedStyle = wm.name;
    }
  }

  String get _missingHint {
    if (_image == null) return context.l10n.uplHintAddPhoto;
    if (!_roomChosen) return context.l10n.uplHintChooseRoom;
    return context.l10n.uplHintPickAtmosphere;
  }

  void _start() {
    final params = <String, String>{};
    if (_aiDecideRoom) {
      params['aiDecide'] = '1';
    } else {
      params['roomType'] = _selectedRoom!;
    }
    if (_surpriseStyle) {
      params['surprise'] = '1';
    } else {
      params['style'] = _selectedStyle!;
    }
    final desc = _descController.text.trim();
    if (desc.isNotEmpty) params['desc'] = desc;
    // Wave 5.16 — `mode` query param dropped from FTUE. Backend default
    // ("preserve") + ChatScreen.initialMode default ("preserve") both
    // pick it up implicitly. Chat-screen Design Direction sheet still
    // owns refinement-time creative flips.

    final uri = Uri(path: '/chat/new', queryParameters: params);
    context.pushReplacement(uri.toString(), extra: _image);
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Tablet/desktop layout: persistent vertical stepper sidebar +
            // scrollable content. Phones: horizontal top stepper + content.
            final isWide = constraints.maxWidth >= 720;
            return Column(
              children: [
                if (!isWide)
                  _StepperTop(
                    currentStep: _currentStep,
                    onStep: _scrollToStep,
                  ),
                Expanded(
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _StepperSide(
                              currentStep: _currentStep,
                              onStep: _scrollToStep,
                            ),
                            Expanded(child: _buildContent(isWide: true)),
                          ],
                        )
                      : _buildContent(isWide: false),
                ),
                StickyActionBar(
                  primary: AppButton(
                    label: '${context.l10n.uplGenerateDesign} ✨',
                    onPressed: _canProceed ? _start : null,
                  ),
                  secondary: Text(
                    _canProceed
                        ? context.l10n.uplWillCreate
                        : _missingHint,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent({required bool isWide}) {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.lg,
        AppSpacing.pagePadding,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── STEP 1 — Upload your space ────────────────────────────────────
          _StepSection(
            anchorKey: _stepKeys[0],
            stepNumber: 1,
            title: context.l10n.uploadYourSpace,
            subtitle: context.l10n.uplStep1Sub,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _UploadZone(image: _image, onTap: _showImagePicker),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 14,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      context.l10n.uplPrivacy,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),

          // ── STEP 2 — Room type ────────────────────────────────────────────
          _StepSection(
            anchorKey: _stepKeys[1],
            stepNumber: 2,
            title: context.l10n.uplStep2Title,
            subtitle: context.l10n.uplStep2Sub,
            child: _RoomScroller(
              selected: _selectedRoom,
              onSelected: (v) => setState(() {
                _selectedRoom = v;
                _aiDecideRoom = false;
              }),
              aiDecideSelected: _aiDecideRoom,
              onAiDecide: () => setState(() {
                _aiDecideRoom = !_aiDecideRoom;
                if (_aiDecideRoom) _selectedRoom = null;
              }),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),

          // ── STEP 3 — Atmosphere ───────────────────────────────────────────
          _StepSection(
            anchorKey: _stepKeys[2],
            stepNumber: 3,
            title: context.l10n.uplStep3Title,
            subtitle: context.l10n.uplStep3Sub,
            child: _AtmosphereScroller(
              selected: _selectedStyle,
              onSelected: (v) => setState(() {
                _selectedStyle = v;
                _surpriseStyle = false;
              }),
              surpriseSelected: _surpriseStyle,
              onSurprise: () => setState(() {
                _surpriseStyle = !_surpriseStyle;
                if (_surpriseStyle) _selectedStyle = null;
              }),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),

          // ── STEP 4 — Your vision (was STEP 5 pre-5.16) ────────────────────
          // Wave 5.16 — STEP 4 (Redesign Options / _ModeChooser) removed.
          // Describe your vision renumbered 5 → 4 ; uses _stepKeys[3]
          // (was _stepKeys[4]).
          _StepSection(
            anchorKey: _stepKeys[3],
            stepNumber: 4,
            title: context.l10n.uplStep4Title,
            titleTrailing: const _OptionalBadge(),
            subtitle: context.l10n.uplStep4Sub,
            child: _DescriptionField(controller: _descController),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

// ── Step section wrapper ─────────────────────────────────────────────────────
// Encapsulates the "STEP X OF 5" badge + title + subtitle + content with
// consistent spacing. The [anchorKey] lets the stepper scroll to this
// section and lets the scroll listener detect when it's the current step.

class _StepSection extends StatelessWidget {
  final GlobalKey anchorKey;
  final int stepNumber;
  final String title;
  final Widget? titleTrailing;
  final String subtitle;
  final Widget child;

  const _StepSection({
    required this.anchorKey,
    required this.stepNumber,
    required this.title,
    this.titleTrailing,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      key: anchorKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepBadge(stepNumber: stepNumber),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                title,
                style: AppTheme.displayEditorial(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  height: 1.18,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            if (titleTrailing != null) ...[
              const SizedBox(width: 10),
              titleTrailing!,
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
        ),
        const SizedBox(height: AppSpacing.lg),
        child,
      ],
    );
  }
}

// Small dark pill: "STEP N OF 4". (Wave 5.16 — 5 → 4 after Redesign Options drop.)
class _StepBadge extends StatelessWidget {
  final int stepNumber;
  const _StepBadge({required this.stepNumber});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.textPrimary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        context.l10n.uplStepBadge(stepNumber),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.surface,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
              fontSize: 10,
            ),
      ),
    );
  }
}

class _OptionalBadge extends StatelessWidget {
  const _OptionalBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        context.l10n.uplOptional,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
      ),
    );
  }
}

// ── Vertical stepper sidebar (tablet/desktop) ────────────────────────────────
// Persistent left-rail roadmap. Wave 5.16 — 4 numbered nodes (was 5 ;
// "Redesign Options" dropped). The current step glows with the accent
// colour ; completed steps look quietly resolved ; future steps are subdued.

class _StepperSide extends StatelessWidget {
  final int currentStep;
  final ValueChanged<int> onStep;

  const _StepperSide({required this.currentStep, required this.onStep});

  @override
  Widget build(BuildContext context) {
    final labels = [
      context.l10n.uplStepperUpload,
      context.l10n.uplStepperRoom,
      context.l10n.uplStepperAtmosphere,
      context.l10n.uplStepperVision,
    ];
    return Container(
      width: 132,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xl, 8,
          AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(labels.length, (i) {
          final step = i + 1;
          final isCurrent = step == currentStep;
          final isPast = step < currentStep;
          final isLast = i == labels.length - 1;
          return _StepperNode(
            stepNumber: step,
            label: labels[i],
            isCurrent: isCurrent,
            isPast: isPast,
            isLast: isLast,
            vertical: true,
            onTap: () => onStep(step),
          );
        }),
      ),
    );
  }
}

// ── Horizontal stepper (phones) ──────────────────────────────────────────────
// 4 numbered dots in a horizontal row connected by hairlines (Wave 5.16 —
// was 5). Labels are hidden to save vertical real estate ; current step glows.

class _StepperTop extends StatelessWidget {
  final int currentStep;
  final ValueChanged<int> onStep;

  const _StepperTop({required this.currentStep, required this.onStep});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        12,
        AppSpacing.pagePadding,
        12,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(
          bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: List.generate(4, (i) {
          final step = i + 1;
          final isCurrent = step == currentStep;
          final isPast = step < currentStep;
          final isLast = i == 3;
          return Expanded(
            child: _StepperNode(
              stepNumber: step,
              label: '',
              isCurrent: isCurrent,
              isPast: isPast,
              isLast: isLast,
              vertical: false,
              onTap: () => onStep(step),
            ),
          );
        }),
      ),
    );
  }
}

// Single stepper node — number circle + label, with connector to next node.
class _StepperNode extends StatelessWidget {
  final int stepNumber;
  final String label;
  final bool isCurrent;
  final bool isPast;
  final bool isLast;
  final bool vertical;
  final VoidCallback onTap;

  const _StepperNode({
    required this.stepNumber,
    required this.label,
    required this.isCurrent,
    required this.isPast,
    required this.isLast,
    required this.vertical,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color circleBg = isCurrent
        ? AppColors.textPrimary
        : isPast
            ? AppColors.textPrimary
            : AppColors.surface;
    final Color circleFg = (isCurrent || isPast)
        ? AppColors.surface
        : AppColors.textTertiary;
    final Color borderColor = isCurrent
        ? AppColors.textPrimary
        : isPast
            ? AppColors.textPrimary
            : AppColors.border;
    final connectorColor = isPast
        ? AppColors.textPrimary.withValues(alpha: 0.4)
        : AppColors.border;

    final circle = AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: circleBg,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: isCurrent ? 1.6 : 1),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: AppColors.textPrimary.withValues(alpha: 0.18),
                  blurRadius: 16,
                  spreadRadius: 0,
                ),
              ]
            : const [],
      ),
      alignment: Alignment.center,
      child: Text(
        '$stepNumber',
        style: TextStyle(
          color: circleFg,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );

    if (vertical) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                children: [
                  circle,
                  if (!isLast)
                    Container(
                      width: 1,
                      height: 36,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: connectorColor,
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 36 + 8.0),
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isCurrent
                              ? AppColors.textPrimary
                              : AppColors.textTertiary,
                          fontWeight:
                              isCurrent ? FontWeight.w600 : FontWeight.w500,
                          letterSpacing: 0.3,
                        ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Horizontal: circle inline with a connector running rightward.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          circle,
          if (!isLast)
            Expanded(
              child: Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: connectorColor,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Description field (preserved) ────────────────────────────────────────────
// Wave 4.8.7: calm free-text architectural direction with real voice
// dictation via the shared VoiceService + MicButton.

class _DescriptionField extends ConsumerStatefulWidget {
  final TextEditingController controller;
  const _DescriptionField({required this.controller});

  @override
  ConsumerState<_DescriptionField> createState() => _DescriptionFieldState();
}

class _DescriptionFieldState extends ConsumerState<_DescriptionField>
    with SingleTickerProviderStateMixin {
  final VoiceService _voice = VoiceService();
  bool _voiceAvailable = false;
  bool _isListening = false;
  String _dictationPrefix = '';
  // Continuous mode: live preview (not written to the controller until stop).
  String _preview = '';

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _pulseScale = Tween<double>(begin: 1.0, end: 1.85)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut));
    _pulseOpacity = Tween<double>(begin: 0.38, end: 0.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut));
    _initVoice();
  }

  Future<void> _initVoice() async {
    final ok = await _voice.initialize();
    if (mounted) setState(() => _voiceAvailable = ok);
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _voice.stop();
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    if (!_voiceAvailable || !mounted) return;
    final existing = widget.controller.text;
    final separator = (existing.isEmpty ||
            existing.endsWith(' ') ||
            existing.endsWith('\n'))
        ? ''
        : ' ';
    _dictationPrefix = existing + separator;

    final continuous = FeatureFlags.voiceContinuous;
    // Don't force/keep the keyboard open while dictating.
    if (continuous) FocusScope.of(context).unfocus();
    setState(() {
      _isListening = true;
      _preview = '';
    });
    _pulseCtrl.repeat();
    await _voice.start(
      continuous: continuous,
      onPartial: continuous ? _onPreview : _applyTranscript,
      onFinal: continuous ? _onCommit : _applyTranscript,
      onStop: _handleStop,
      onError: (_) => _handleStop(),
      // Phase 4 — dictate in the user's UI language (resolved/fallback inside).
      localeId: VoiceService.sttLocaleForLanguage(
          ref.read(localeProvider).languageCode),
    );
  }

  // Legacy live transcription (flag off).
  void _applyTranscript(String words) {
    if (!mounted) return;
    final combined = _dictationPrefix + words;
    widget.controller.text = combined;
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: combined.length),
    );
  }

  // Continuous: preview only — never touches the controller.
  void _onPreview(String content) {
    if (!mounted) return;
    setState(() => _preview = content);
  }

  // Continuous: commit the accumulated transcript once, at stop.
  void _onCommit(String full) {
    if (!mounted) return;
    final combined = _dictationPrefix + full;
    widget.controller.text = combined;
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: combined.length),
    );
  }

  void _handleStop() {
    if (!mounted) return;
    _pulseCtrl.stop();
    _pulseCtrl.reset();
    setState(() {
      _isListening = false;
      _preview = '';
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _voice.dispose();
    super.dispose();
  }

  // Read-only listening state (continuous mode) shown in place of the field:
  // "Listening… Tap to stop" + live preview. Committed only at stop.
  Widget _buildListeningPreview() {
    final text = (_dictationPrefix + _preview).trim();
    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(color: AppColors.accent, width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mic, size: 14, color: AppColors.accent),
              const SizedBox(width: 6),
              Text(
                context.l10n.voiceListening,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              text,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(height: 1.5, fontSize: 15),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: widget.controller,
      minLines: 3,
      maxLines: 5,
      textInputAction: TextInputAction.newline,
      style: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(height: 1.5, fontSize: 15),
      decoration: InputDecoration(
        hintText: _isListening
            ? 'Listening…'
            : 'More natural light, warm colors, cozy, minimalist, modern…',
        hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textTertiary,
              height: 1.5,
              fontSize: 14,
            ),
        filled: true,
        fillColor: AppColors.surfaceVariant,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
    );

    final content = (_isListening && FeatureFlags.voiceContinuous)
        ? _buildListeningPreview()
        : field;

    if (!_voiceAvailable) return content;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: content),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: MicButton(
            isListening: _isListening,
            enabled: true,
            pulseScale: _pulseScale,
            pulseOpacity: _pulseOpacity,
            onTap: _toggleListening,
          ),
        ),
      ],
    );
  }
}

// ── Upload zone ──────────────────────────────────────────────────────────────
// Calmer premium empty/filled state. AspectRatio 4:3, accent border when
// filled, "Replace" pill in the corner of the loaded image.

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
                    // #24 — show the FULL source room, never crop it out of
                    // view. Letterboxed on a neutral cinematic frame instead
                    // of cover-cropping a portrait/wide photo to 4:3.
                    const ColoredBox(color: Color(0xFF0B0B0C)),
                    Image.file(image!, fit: BoxFit.contain),
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

// ── Room-type — premium horizontal scroller (exact l10n strings kept) ────────

class _RoomScroller extends ConsumerWidget {
  final String? selected;
  final ValueChanged<String> onSelected;
  final bool aiDecideSelected;
  final VoidCallback? onAiDecide;
  const _RoomScroller({
    this.selected,
    required this.onSelected,
    this.aiDecideSelected = false,
    this.onAiDecide,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isPremium = ref.watch(premiumProvider);
    // Wave 5.18 — admin bypass added alongside premium bypass.
    final isAdmin = ref.watch(accessProvider);
    // Sprint 1B — an active promo grant (limited or unlimited) unlocks ALL
    // rooms/atmospheres too, exactly like the backend resolver's bypass_scope.
    final hasPromo = ref.watch(meStatusProvider)?.hasActivePromo ?? false;
    final entitled = isPremium || isAdmin || hasPromo;

    // Wave 5.17d — locked predicates. A room is locked when the user is NOT
    // entitled AND its canonical id is not in the free set. The "AI Decide"
    // tile is entitled-only — free users cannot delegate the choice (mirrors
    // the backend free_tier policy).
    bool roomLocked(String label) {
      if (entitled) return false;
      final id = RoomTypeImages.idForLabel(l10n, label);
      return id == null || !kFreeRoomIds.contains(id);
    }
    // #8 — Ayden Decide is free (no premium lock) when aydenDecideFree is on;
    // only the normal free quota applies (enforced backend-side). Flag off →
    // legacy premium lock.
    bool aiLocked() => FeatureFlags.aydenDecideFree ? false : !entitled;

    // Tap router : locked → paywall, else → original onSelected/onAiDecide.
    void onRoomTap(String label) {
      if (roomLocked(label)) {
        _openLockedPaywall(context, restrictedField: 'room');
        return;
      }
      onSelected(label);
    }
    VoidCallback? onAi = onAiDecide == null ? null : () {
      if (aiLocked()) {
        _openLockedPaywall(context, restrictedField: 'delegated_choice');
        return;
      }
      onAiDecide!();
    };

    // AYDEN new card system (flag-gated). Same selection value (localized
    // label), same locks/paywall — only the rendering changes.
    if (FeatureFlags.newDesignCards) {
      return _newRoomsLayout(context, l10n, onRoomTap, roomLocked, onAi,
          aiLocked());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RoomGroupLabel(label: l10n.interiorSection),
        const SizedBox(height: 8),
        RoomTypeRow(
          rooms: l10n.interiorRooms,
          selected: selected,
          onSelected: onRoomTap,
          aiDecideSelected: aiDecideSelected,
          aiLabel: onAi != null ? context.l10n.uplAiDecide : null,
          aiSublabel:
              onAi != null ? context.l10n.uplAiDecideSub : null,
          onAiDecide: onAi,
          isLocked: roomLocked,
          isAiLocked: aiLocked,
        ),
        const SizedBox(height: 16),
        _RoomGroupLabel(label: l10n.exteriorSection),
        const SizedBox(height: 8),
        RoomTypeRow(
          rooms: l10n.exteriorRooms,
          selected: selected,
          onSelected: onRoomTap,
          isLocked: roomLocked,
        ),
      ],
    );
  }

  // ── AYDEN new card system — hero grid + "More Spaces" row ──────────────────
  // Display labels = English (Option A). Selection VALUE = localized label via
  // RoomTypeImages.labelForId → routing / free-tier / paywall unchanged.
  Widget _newRoomsLayout(
    BuildContext context,
    AppLocalizations l10n,
    void Function(String) onRoomTap,
    bool Function(String) roomLocked,
    VoidCallback? onAi,
    bool aiLockedNow,
  ) {
    // VALUE routed to session/backend = canonical ENGLISH label (locale-stable;
    // backend DNA room lookup keys off English names). Display stays English
    // (r.label) per Option A. Localized labels must NEVER be the routed value —
    // they make the backend drop room DNA (room context / TV anchor).
    String value(String id) => RoomTypeImages.enLabelForId(id) ?? id;
    RoomCard card(RoomCardData r) {
      final v = value(r.id);
      return RoomCard(
        label: r.label,
        asset: r.asset,
        selected: selected == v,
        locked: roomLocked(v),
        onTap: () => onRoomTap(v),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final cols = MediaQuery.sizeOf(context).width >= 600 ? 3 : 2;
        final heroH = (c.maxWidth - (cols - 1) * 12) / cols * 5 / 6;
        final secH = heroH * 0.78;
        final secW = secH * 6 / 5;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GridView.count(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: cols,
              childAspectRatio: 6 / 5,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                // Ayden Decide leads the choices (first cell) — the default
                // pick. Full-bleed pre-composed card art (logo + tagline baked
                // into the image).
                if (onAi != null)
                  AiActionCard(
                    title: context.l10n.uplAiDecide,
                    subtitle: context.l10n.uplAiDecideSub,
                    selected: aiDecideSelected,
                    locked: aiLockedNow,
                    onTap: onAi,
                    backgroundImageAsset:
                        'assets/branding/ayden_decide_card.png',
                  ),
                for (final r in kHeroRooms) card(r),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  context.l10n.uplMoreSpaces,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward,
                    size: 15, color: AppColors.textTertiary),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: secH,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                clipBehavior: Clip.none,
                itemCount: kMoreRooms.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  return SizedBox(width: secW, child: card(kMoreRooms[i]));
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// Wave 5.17d — single entry point so the locked-tap path can never
// drift across the room + atmosphere scrollers. Returns true iff the
// purchase completed (we don't act on it here — the home rebuild on
// premiumProvider state change handles the visual refresh).
Future<void> _openLockedPaywall(
  BuildContext context, {
  required String restrictedField,
}) async {
  await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => PaywallSheet(
      trigger: PaywallTrigger.locked,
      restrictedField: restrictedField,
    ),
  );
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
            letterSpacing: 0.4,
          ),
    );
  }
}

// ── Atmosphere — shared AtmosphereCard V2 horizontal scroller + custom fold ──

class _AtmosphereScroller extends ConsumerWidget {
  final String? selected;
  final ValueChanged<String> onSelected;
  final bool surpriseSelected;
  final VoidCallback? onSurprise;
  const _AtmosphereScroller({
    this.selected,
    required this.onSelected,
    this.surpriseSelected = false,
    this.onSurprise,
  });

  static const _customLabel = 'Describe Your Dream Space';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPremium = ref.watch(premiumProvider);
    // Wave 5.18 — admin bypass for atmosphere/surprise/custom carousel.
    final isAdmin = ref.watch(accessProvider);
    // Sprint 1B — promo grants full atmosphere access too.
    final hasPromo = ref.watch(meStatusProvider)?.hasActivePromo ?? false;
    final entitled = isPremium || isAdmin || hasPromo;

    // AYDEN new card system (flag-gated). Same selection value (a.name),
    // same locks/paywall — only the rendering changes.
    if (FeatureFlags.newDesignCards) {
      return _newAtmosphereLayout(context, entitled);
    }

    final atmospheres = AppLocalizations.atmospheres;
    final hasSurprise = onSurprise != null;
    final leading = hasSurprise ? 1 : 0;
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: atmospheres.length + 1 + leading,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (hasSurprise && index == 0) {
            // Wave 5.17d — Surprise Me is delegated-choice, premium-only.
            // Wave 5.18 — admin bypass.
            final locked = !entitled;
            return SizedBox(
              width: 150,
              child: AtmosphereCard.surprise(
                label: context.l10n.uplSurpriseMe,
                sublabel: context.l10n.uplSurpriseSub,
                selected: surpriseSelected,
                locked: locked,
                onTap: locked
                    ? () => _openLockedPaywall(
                          context,
                          restrictedField: 'delegated_choice',
                        )
                    : onSurprise!,
              ),
            );
          }
          final atmosphereIndex = index - leading;
          if (atmosphereIndex < atmospheres.length) {
            final a = atmospheres[atmosphereIndex];
            // Wave 5.17d — non-free atmosphere is locked for non-premium.
            // Wave 5.18 — admin bypass.
            final locked = !entitled
                && !kFreeAtmosphereIds.contains(a.id);
            return SizedBox(
              width: 150,
              child: AtmosphereCard(
                atmosphere: a,
                selected: selected == a.name,
                locked: locked,
                onTap: locked
                    ? () => _openLockedPaywall(
                          context,
                          restrictedField: 'atmosphere',
                        )
                    : () => onSelected(a.name),
              ),
            );
          }
          // Custom tile = free-text direction, premium-only (out of free
          // scope by definition — the user is asking the AI to interpret).
          // Wave 5.18 — admin bypass.
          final customLocked = !entitled;
          return SizedBox(
            width: 150,
            child: AtmosphereCard.custom(
              label: _customLabel,
              sublabel: context.l10n.uplCustomSub,
              selected: selected == _customLabel,
              locked: customLocked,
              onTap: customLocked
                  ? () => _openLockedPaywall(
                        context,
                        restrictedField: 'atmosphere',
                      )
                  : () => onSelected(_customLabel),
            ),
          );
        },
      ),
    );
  }

  // ── AYDEN new card system — mini-hero atmosphere carousel ──────────────────
  // Iterates the canonical ordered list (AppLocalizations.atmospheres) for
  // identity/order/free-tier; pulls the new visuals (subtitle + asset) by id.
  // Selection VALUE = a.name → routing / free-tier / paywall unchanged.
  Widget _newAtmosphereLayout(BuildContext context, bool entitled) {
    final atmospheres = AppLocalizations.atmospheres;
    final hasSurprise = onSurprise != null;
    final notEntitled = !entitled;

    return LayoutBuilder(
      builder: (context, c) {
        final cardW = c.maxWidth * 0.80;
        final h = cardW / 1.2;

        final items = <Widget>[
          for (final a in atmospheres)
            AtmosphereHeroCard(
              name: a.name,
              subtitle: context.l10n.atmosphereSubtitle(a.id),
              asset: kAtmosphereCardById[a.id]?.asset ??
                  'assets/cards/atmospheres/${a.id}.png',
              selected: selected == a.name,
              locked: notEntitled && !kFreeAtmosphereIds.contains(a.id),
              onTap: notEntitled && !kFreeAtmosphereIds.contains(a.id)
                  ? () =>
                      _openLockedPaywall(context, restrictedField: 'atmosphere')
                  : () => onSelected(a.name),
            ),
          if (hasSurprise)
            AiActionCard(
              title: context.l10n.uplSurpriseMe,
              subtitle: context.l10n.uplSurpriseSub,
              radius: 18,
              locked: notEntitled,
              onTap: notEntitled
                  ? () => _openLockedPaywall(context,
                      restrictedField: 'delegated_choice')
                  : onSurprise!,
            ),
          AiActionCard(
            title: _customLabel,
            subtitle: context.l10n.uplCustomSub,
            radius: 18,
            locked: notEntitled,
            onTap: notEntitled
                ? () => _openLockedPaywall(context, restrictedField: 'atmosphere')
                : () => onSelected(_customLabel),
          ),
        ];

        return SizedBox(
          height: h,
          child: PageView.builder(
            controller: PageController(viewportFraction: 0.80),
            padEnds: false,
            itemCount: items.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: items[i],
            ),
          ),
        );
      },
    );
  }
}

// ── Wave 5.16 — FTUE Simplification & V1 Focus ────────────────────────────────
// The _ModeChooser, _ModeCard and _RecommendedBadge widgets that previously
// powered Step 4 ("How should AI redesign your space?" — Preserve vs Reimagine)
// were removed in this wave. Rationale : V1 onboarding now always launches
// in preserve mode (backend default). The advanced creative flip survives
// in the chat Design Direction sheet (`_SheetModeToggle`) for refinement
// time, per the V1 positioning : preserve onboarding, creative refinement.
// Backend `generation_mode` contract untouched ; the FTUE simply omits the
// `mode` query param so the server-side default ("preserve") applies.

