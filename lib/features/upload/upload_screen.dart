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
  // Wave 4.8.5 — real conversational intent (carried as flags, never fake
  // strings). AI Decide ⇄ explicit room are mutually exclusive; Surprise Me
  // ⇄ explicit atmosphere likewise. Description is an optional free-text
  // architectural direction that flows to the backend prompt verbatim.
  bool _aiDecideRoom = false;
  bool _surpriseStyle = false;
  final _descController = TextEditingController();
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
    _descController.dispose();
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

  bool get _roomChosen => _selectedRoom != null || _aiDecideRoom;
  bool get _styleChosen => _selectedStyle != null || _surpriseStyle;
  bool get _canProceed => _image != null && _roomChosen && _styleChosen;

  // Calm, specific hint for the disabled state (premium, never a dead button).
  String get _missingHint {
    if (_image == null) return 'Add a photo of your space to begin';
    if (!_roomChosen) return 'Choose a room — or let the AI decide';
    return 'Pick an atmosphere — or let the AI surprise you';
  }

  void _start() {
    // Real semantics only — AI Decide / Surprise Me travel as typed flags,
    // never as fake "AI Decide"/"Surprise Me" room/style strings. The
    // optional free-text direction rides as `desc` → backend prompt.
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
                    // Wave 4.8.7 — AI Decide is now the FIRST card in the
                    // Interior row (`RoomTypeRow.aiDecide…`), not a separate
                    // settings-style bar. One editorial selection language.
                    _Eyebrow(label: l10n.roomTypeLabel),
                    const SizedBox(height: AppSpacing.md),
                    _RoomScroller(
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
                    const SizedBox(height: AppSpacing.xl),
                    // Wave 4.8.7 — Surprise Me is now the FIRST card in the
                    // atmosphere strip (`AtmosphereCard.surprise`), a creative
                    // direction, not a system toggle.
                    _Eyebrow(label: l10n.styleLabel),
                    const SizedBox(height: AppSpacing.md),
                    _AtmosphereScroller(
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
                    const SizedBox(height: AppSpacing.xxl),
                    // Wave 4.8.7 — description elevation. The architectural
                    // briefing is one of the most important creative surfaces
                    // in the app, so it leads with an editorial heading
                    // (display type), generous breathing, and a calmer hint —
                    // never a small eyebrow + form-like field.
                    Text(
                      'Describe your vision',
                      style: AppTheme.displayEditorial(
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                        height: 1.15,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Optional — brief the architect in your own words. '
                      'You can speak or type.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                            height: 1.4,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _DescriptionField(controller: _descController),
                    const SizedBox(height: AppSpacing.xl),
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

// Wave 4.8.7: `_AiChoiceBar` (the settings-style toggle row) was removed.
// AI Decide and Surprise Me are now real cards INSIDE the room / atmosphere
// selectors (`RoomTypeCard.ai` + `AtmosphereCard.surprise`) — one editorial
// selection language, no settings-style fragment. Backend semantics
// (`_aiDecideRoom` / `_surpriseStyle` → `let_ai_decide` / `surprise_me_flag`)
// are preserved verbatim from Wave 4.8.5.

// Calm free-text architectural direction — premium, not form-like. Multiline,
// keyboard-safe (lives inside the page SingleChildScrollView). Wave 4.8: real
// voice dictation via the shared `VoiceService` + the same `MicButton` the
// chat input bar uses → one voice language across the conversational system.
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
    // Append, never overwrite — preserve anything the user already typed.
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
      // Wave 4.8.7: more presence for the briefing surface (3-5 lines,
      // calmer 1.5 leading, slightly larger body) without becoming an
      // enterprise textarea.
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
            : 'e.g. “turn the rear space into a bedroom”, “keep the structure '
                'but modernize everything”, “add a warm tropical resort feeling”',
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

    // Row aligned to the bottom so the mic sits at the same baseline as the
    // last line of the multiline field — no layout jumps as lines wrap.
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
  // Wave 4.8.7 — AI Decide rides at position 0 of the INTERIOR row so the
  // creative direction lives inside the same selection language. Exterior
  // keeps its existing behaviour (no AI prefix).
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
              onAiDecide != null ? 'Infer the room from your photo' : null,
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
  // Wave 4.8.7 — Surprise Me rides at position 0 as a real `AtmosphereCard
  // .surprise` (creative direction, not a system toggle). When [onSurprise]
  // is null the strip renders exactly as before.
  final bool surpriseSelected;
  final VoidCallback? onSurprise;
  const _AtmosphereScroller({
    this.selected,
    required this.onSelected,
    this.surpriseSelected = false,
    this.onSurprise,
  });

  // Exact value preserved — route/backend interpret this literal (chat custom
  // path). Do NOT change.
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
