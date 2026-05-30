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
import '../../core/services/voice_service.dart';
import '../../shared/widgets/atmosphere_card.dart';
import '../../shared/widgets/room_type_card.dart';
import '../../shared/widgets/sticky_action_bar.dart';
import '../chat/widgets/chat_input_bar.dart' show MicButton;

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

  bool get _roomChosen => _selectedRoom != null || _aiDecideRoom;
  bool get _styleChosen => _selectedStyle != null || _surpriseStyle;
  bool get _canProceed => _image != null && _roomChosen && _styleChosen;

  String get _missingHint {
    if (_image == null) return 'Add a photo of your space to begin';
    if (!_roomChosen) return 'Choose a room — or let the AI decide';
    return 'Pick an atmosphere — or let the AI surprise you';
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
                    label: 'Generate Design ✨',
                    onPressed: _canProceed ? _start : null,
                  ),
                  secondary: Text(
                    _canProceed
                        ? 'AI will create your transformation'
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
            title: 'Upload your space',
            subtitle:
                'Upload a photo of the room, facade, garden or any space '
                'you want to redesign.',
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
                      'Your photos are private and secure',
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
            title: 'What type of space are we transforming?',
            subtitle: 'Choose the type of space you want to transform.',
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
            title: 'Choose your atmosphere',
            subtitle: 'Select the feeling and style that defines your space.',
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
            title: 'Describe your vision',
            titleTrailing: const _OptionalBadge(),
            subtitle: 'Brief the architect in your own words. '
                'You can speak or type.',
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
        'STEP $stepNumber OF 4',
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
        'Optional',
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

  static const _labels = [
    'Upload',
    'Room Type',
    'Atmosphere',
    'Your Vision',
  ];

  const _StepperSide({required this.currentStep, required this.onStep});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xl, 8,
          AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(_labels.length, (i) {
          final step = i + 1;
          final isCurrent = step == currentStep;
          final isPast = step < currentStep;
          final isLast = i == _labels.length - 1;
          return _StepperNode(
            stepNumber: step,
            label: _labels[i],
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

class _DescriptionField extends StatefulWidget {
  final TextEditingController controller;
  const _DescriptionField({required this.controller});

  @override
  State<_DescriptionField> createState() => _DescriptionFieldState();
}

class _DescriptionFieldState extends State<_DescriptionField>
    with SingleTickerProviderStateMixin {
  final VoiceService _voice = VoiceService();
  bool _voiceAvailable = false;
  bool _isListening = false;
  String _dictationPrefix = '';

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

    setState(() => _isListening = true);
    _pulseCtrl.repeat();
    await _voice.start(
      onPartial: _applyTranscript,
      onFinal: _applyTranscript,
      onStop: _handleStop,
      onError: (_) => _handleStop(),
    );
  }

  void _applyTranscript(String words) {
    if (!mounted) return;
    final combined = _dictationPrefix + words;
    widget.controller.text = combined;
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: combined.length),
    );
  }

  void _handleStop() {
    if (!mounted) return;
    _pulseCtrl.stop();
    _pulseCtrl.reset();
    setState(() => _isListening = false);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _voice.dispose();
    super.dispose();
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

    if (!_voiceAvailable) return field;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: field),
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

// ── Room-type — premium horizontal scroller (exact l10n strings kept) ────────

class _RoomScroller extends StatelessWidget {
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
          aiDecideSelected: aiDecideSelected,
          aiLabel: onAiDecide != null ? 'AI Decide' : null,
          aiSublabel:
              onAiDecide != null ? 'Let AI detect the space for me' : null,
          onAiDecide: onAiDecide,
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
            letterSpacing: 0.4,
          ),
    );
  }
}

// ── Atmosphere — shared AtmosphereCard V2 horizontal scroller + custom fold ──

class _AtmosphereScroller extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
            return SizedBox(
              width: 150,
              child: AtmosphereCard.surprise(
                label: 'Surprise Me',
                sublabel: 'Let the AI choose a fitting atmosphere',
                selected: surpriseSelected,
                onTap: onSurprise!,
              ),
            );
          }
          final atmosphereIndex = index - leading;
          if (atmosphereIndex < atmospheres.length) {
            final a = atmospheres[atmosphereIndex];
            return SizedBox(
              width: 150,
              child: AtmosphereCard(
                atmosphere: a,
                selected: selected == a.name,
                onTap: () => onSelected(a.name),
              ),
            );
          }
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

// ── Wave 5.16 — FTUE Simplification & V1 Focus ────────────────────────────────
// The _ModeChooser, _ModeCard and _RecommendedBadge widgets that previously
// powered Step 4 ("How should AI redesign your space?" — Preserve vs Reimagine)
// were removed in this wave. Rationale : V1 onboarding now always launches
// in preserve mode (backend default). The advanced creative flip survives
// in the chat Design Direction sheet (`_SheetModeToggle`) for refinement
// time, per the V1 positioning : preserve onboarding, creative refinement.
// Backend `generation_mode` contract untouched ; the FTUE simply omits the
// `mode` query param so the server-side default ("preserve") applies.
