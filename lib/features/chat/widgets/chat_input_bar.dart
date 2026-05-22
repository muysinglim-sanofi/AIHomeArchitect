import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/voice_service.dart';

/// Wave 4.8 — Chat conversational input bar (extracted from the inline
/// `_InputBar` in `chat_screen.dart`).
///
/// Real native dictation now flows through the shared `VoiceService` so the
/// chat input and the upload description field share one implementation —
/// zero duplicated dictation logic. Behavioural contract is preserved for
/// the caller (`controller`, `onSend`, `enabled`); send/keyboard/scroll flow
/// is unchanged.
///
/// Premium voice UX:
///   • calm `mic_none_outlined` → `mic` swap when listening (no glowing orb),
///   • a single subtle accent ring pulse around the mic (Apple-restrained),
///   • partials are appended to whatever the user typed BEFORE pressing the
///     mic (we capture a prefix at session start) — so dictation never wipes
///     in-progress text, and the user can keep editing AFTER stopping,
///   • on `silence` / `done` the listening state exits cleanly — no stuck mic,
///   • on `permissionDenied` / `failed` the UI quietly exits listening (the
///     mic stays visible; users can retry — we never auto-prompt repeatedly).
class ChatInputBar extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSend;
  final bool enabled;
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.onSend,
    required this.enabled,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar>
    with SingleTickerProviderStateMixin {
  final VoiceService _voice = VoiceService();
  bool _voiceAvailable = false;
  bool _isListening = false;

  // Prefix captured at the moment the user pressed the mic, so partials are
  // appended cleanly rather than overwriting existing text.
  String _dictationPrefix = '';

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
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

  void _onTextChanged() => setState(() {});

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _voice.stop();
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    if (!_voiceAvailable || !mounted) return;
    _dictationPrefix = widget.controller.text;
    // Reserve a clean separator so appended words read naturally.
    final separator = (_dictationPrefix.isEmpty ||
            _dictationPrefix.endsWith(' ') ||
            _dictationPrefix.endsWith('\n'))
        ? ''
        : ' ';
    _dictationPrefix = _dictationPrefix + separator;

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
    widget.controller.removeListener(_onTextChanged);
    _pulseCtrl.dispose();
    _voice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasText = widget.controller.text.trim().isNotEmpty;
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.sm,
        AppSpacing.pagePadding,
        AppSpacing.sm + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller,
              enabled: widget.enabled,
              decoration: InputDecoration(
                hintText: _isListening
                    ? 'Listening…'
                    : widget.enabled
                        ? l10n.chatPlaceholder
                        : l10n.chatGeneratingHint,
                filled: true,
                fillColor: AppColors.background,
              ),
              onSubmitted: widget.enabled ? widget.onSend : null,
              textInputAction: TextInputAction.send,
              maxLines: null,
            ),
          ),
          const SizedBox(width: 8),
          if (_voiceAvailable) ...[
            MicButton(
              isListening: _isListening,
              enabled: widget.enabled,
              pulseScale: _pulseScale,
              pulseOpacity: _pulseOpacity,
              onTap: widget.enabled ? _toggleListening : null,
            ),
            const SizedBox(width: 8),
          ],
          AnimatedOpacity(
            opacity: widget.enabled && hasText ? 1.0 : 0.3,
            duration: const Duration(milliseconds: 200),
            child: GestureDetector(
              onTap: widget.enabled && hasText
                  ? () => widget.onSend(widget.controller.text)
                  : null,
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppColors.textPrimary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_upward_rounded,
                    color: AppColors.surface, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Calm, Apple-restrained mic affordance. Mic icon swap + a single subtle
/// accent ring pulse — no glowing orb, no gaming animation. Reused by the
/// upload description field too (same visual language across surfaces).
class MicButton extends StatelessWidget {
  final bool isListening;
  final bool enabled;
  final Animation<double> pulseScale;
  final Animation<double> pulseOpacity;
  final VoidCallback? onTap;
  const MicButton({
    super.key,
    required this.isListening,
    required this.enabled,
    required this.pulseScale,
    required this.pulseOpacity,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (isListening)
              AnimatedBuilder(
                animation: pulseScale,
                builder: (ctx, child) => Opacity(
                  opacity: pulseOpacity.value.clamp(0.0, 1.0),
                  child: Container(
                    width: 36 * pulseScale.value,
                    height: 36 * pulseScale.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: AppColors.accent, width: 1.5),
                    ),
                  ),
                ),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isListening
                    ? AppColors.accent.withValues(alpha: 0.12)
                    : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: AnimatedOpacity(
                opacity: enabled ? (isListening ? 1.0 : 0.55) : 0.2,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  isListening ? Icons.mic : Icons.mic_none_outlined,
                  size: 20,
                  color: isListening
                      ? AppColors.accent
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
