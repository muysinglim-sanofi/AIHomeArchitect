import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart' show Share;
import 'package:speech_to_text/speech_to_text.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/providers/session_provider.dart';
import '../../data/mock/mock_projects.dart';
import '../../data/services/generation_service.dart';
import '../../data/services/supabase_service.dart';
import '../../data/models/message_model.dart';
import '../../data/models/project_model.dart';
import '../../shared/widgets/app_button.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

String _timeAgo(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'yesterday';
  return '${diff.inDays}d ago';
}

// ── Chat screen ───────────────────────────────────────────────────────────────

class ChatScreen extends ConsumerStatefulWidget {
  final String projectId;
  final String? initialRoomType;
  final String? initialStyle;
  final File? sourceImageFile;
  const ChatScreen({
    super.key,
    required this.projectId,
    this.initialRoomType,
    this.initialStyle,
    this.sourceImageFile,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> with SingleTickerProviderStateMixin {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isGenerating = false;
  bool _hasGenerated = false;

  late String _sessionTitle;
  bool _isEditingTitle = false;
  final _titleEditController = TextEditingController();
  final _titleFocusNode = FocusNode();

  File? _sourceImageFile;
  final _picker = ImagePicker();

  late String _currentRoomType;
  late String _currentStyle;

  late ProjectModel _project;
  late List<MessageModel> _messages;
  late int _iterationCount;

  late final SupabaseService _svc;
  // Messages queued while the Supabase session is still being created.
  final List<MessageModel> _pendingMessages = [];

  late final AnimationController _entryController;
  late final Animation<double> _fadeAnim;

  List<String> get _suggestions =>
      (_hasGenerated || _iterationCount > 0)
          ? postGenerationSuggestions
          : preGenerationSuggestions;

  // Flat list interleaving DateTime day-separators with MessageModels
  List<Object> get _listItems {
    final items = <Object>[];
    DateTime? lastDay;
    for (final msg in _messages) {
      final day = DateTime(msg.createdAt.year, msg.createdAt.month, msg.createdAt.day);
      if (lastDay == null ||
          day.year != lastDay.year ||
          day.month != lastDay.month ||
          day.day != lastDay.day) {
        items.add(day);
        lastDay = day;
      }
      items.add(msg);
    }
    return items;
  }

  @override
  void initState() {
    super.initState();
    _svc = ref.read(supabaseServiceProvider);

    if (widget.projectId == 'new') {
      final roomType = widget.initialRoomType ?? 'Living Room';
      final style = widget.initialStyle ?? 'Modern Minimalist';
      _project = ProjectModel(
        id: 'new',
        title: 'New Design Session',
        roomType: roomType,
        style: style,
        beforeImageUrl: null,
        afterImageUrl: null,
        status: ProjectStatus.inProgress,
        createdAt: DateTime.now(),
        lastUpdatedAt: DateTime.now(),
        messages: const [],
        iterationCount: 0,
      );
      _messages = [
        MessageModel(
          id: 'initial',
          content: 'I can see the space. Tell me what you want it to feel like — the mood, the materials, the lifestyle. The more specific you are, the closer I can get to the vision you have in mind.',
          isAi: true,
          createdAt: DateTime.now(),
        ),
      ];
      _iterationCount = 0;
      // Initialize before _initNewSession() reads them synchronously.
      _currentRoomType = roomType;
      _currentStyle = style;
      _sessionTitle = 'New Design Session';
      _sourceImageFile = widget.sourceImageFile;
      _initNewSession();
    } else {
      // Look up from provider state (populated from Supabase).
      // Falls back to a placeholder if the session hasn't loaded yet.
      final sessions = ref.read(sessionProvider);
      _project = sessions.firstWhere(
        (p) => p.id == widget.projectId,
        orElse: () => ProjectModel(
          id: widget.projectId,
          title: 'Design Session',
          roomType: widget.initialRoomType ?? '',
          style: widget.initialStyle ?? '',
          status: ProjectStatus.inProgress,
          createdAt: DateTime.now(),
          lastUpdatedAt: DateTime.now(),
          messages: const [],
          iterationCount: 0,
        ),
      );
      _messages = List.from(_project.messages);
      _iterationCount = _project.iterationCount;
      _currentRoomType = _project.roomType;
      _currentStyle = _project.style;
      _sessionTitle = _project.title;
      _loadMessages();
    }
    _titleFocusNode.addListener(() {
      if (!_titleFocusNode.hasFocus && _isEditingTitle) _applyTitleEdit();
    });

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _entryController, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _entryController.dispose();
    _titleEditController.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  // ── Supabase persistence ──────────────────────────────────────────────────

  /// Called once for new sessions. Creates the row in Supabase, persists the
  /// initial greeting, flushes any messages sent before the row was ready,
  /// then updates _project with the real UUID so subsequent writes work.
  Future<void> _initNewSession() async {
    debugPrint('[DB] _initNewSession() started — title: "$_sessionTitle" room: "$_currentRoomType" style: "$_currentStyle"');
    try {
      final realProject = await ref.read(sessionProvider.notifier).createSession(
        title: _sessionTitle,
        roomType: _currentRoomType,
        atmosphere: _currentStyle,
      );
      debugPrint('[DB] _initNewSession() session created — id: ${realProject.id}');

      // Upload source image (fire after session exists so we have the real ID for the path).
      String? beforeUrl;
      final imageFile = _sourceImageFile;
      if (imageFile != null) {
        debugPrint('[DB] _initNewSession() uploading source image…');
        try {
          final bytes = await imageFile.readAsBytes();
          final filename = 'source_${DateTime.now().millisecondsSinceEpoch}.jpg';
          beforeUrl = await _svc.uploadSourceImage(
            sessionId: realProject.id,
            filename: filename,
            bytes: bytes,
          );
          await _svc.updateBeforeImageUrl(realProject.id, beforeUrl);
          debugPrint('[DB] _initNewSession() source image uploaded — url: $beforeUrl');
        } catch (uploadErr) {
          debugPrint('[DB] _initNewSession() image upload failed (non-fatal): $uploadErr');
        }
      }

      // Persist the initial AI greeting.
      await _svc.insertMessage(
        sessionId: realProject.id,
        role: 'ai',
        content: _messages.first.content,
      );
      debugPrint('[DB] _initNewSession() initial greeting persisted');

      // Flush user messages that arrived before the session row existed.
      if (_pendingMessages.isNotEmpty) {
        debugPrint('[DB] _initNewSession() flushing ${_pendingMessages.length} pending messages');
        for (final msg in _pendingMessages) {
          await _svc.insertMessage(
            sessionId: realProject.id,
            role: msg.isAi ? 'ai' : 'user',
            content: msg.content,
            messageType: msg.type == MessageType.imageResult ? 'image_result' : 'text',
          );
        }
        _pendingMessages.clear();
      }

      if (mounted) {
        setState(() {
          _project = beforeUrl != null
              ? realProject.copyWith(beforeImageUrl: beforeUrl)
              : realProject;
        });
      }
      debugPrint('[DB] _initNewSession() complete — _project.id updated to ${realProject.id}');
    } catch (e, st) {
      debugPrint('[DB] _initNewSession() ERROR: $e');
      debugPrint('[DB] _initNewSession() STACK: $st');
    }
  }

  /// Fetches full message history from Supabase for an existing session.
  Future<void> _loadMessages() async {
    debugPrint('[DB] _loadMessages() started — session_id: ${_project.id}');
    try {
      final rows = await _svc.fetchMessages(_project.id);
      debugPrint('[DB] _loadMessages() — got ${rows.length} rows');
      if (!mounted || rows.isEmpty) return;
      final msgs = rows.map(_rowToMessage).toList();
      final imageCount = msgs.where((m) => m.type == MessageType.imageResult).length;
      setState(() {
        _messages = msgs;
        _iterationCount = imageCount;
        _hasGenerated = imageCount > 0;
      });
      _scrollToBottom();
    } catch (e, st) {
      debugPrint('[DB] _loadMessages() ERROR: $e');
      debugPrint('[DB] _loadMessages() STACK: $st');
    }
  }

  MessageModel _rowToMessage(Map<String, dynamic> row) {
    final typeStr = (row['message_type'] as String?) ?? 'text';
    final isImageResult = typeStr == 'image_result';
    return MessageModel(
      id: row['id'] as String,
      content: row['content'] as String,
      isAi: (row['role'] as String) == 'ai',
      type: isImageResult
          ? MessageType.imageResult
          : typeStr == 'system'
              ? MessageType.system
              : MessageType.text,
      result: isImageResult
          ? GeneratedResult(
              beforeImageUrl: (row['before_image_url'] as String?) ?? '',
              afterImageUrl: (row['after_image_url'] as String?) ?? '',
              styleLabel: (row['style_label'] as String?) ?? '',
              projectId: _project.id,
            )
          : null,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  void _applyTitleEdit() {
    final trimmed = _titleEditController.text.trim();
    setState(() {
      if (trimmed.isNotEmpty) _sessionTitle = trimmed;
      _isEditingTitle = false;
    });
    if (trimmed.isNotEmpty && _project.id != 'new') {
      ref.read(sessionProvider.notifier).updateTitle(_project.id, trimmed);
    }
  }

  void _send(String text) {
    if (text.trim().isEmpty) return;
    final msg = MessageModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: text.trim(),
      isAi: false,
      createdAt: DateTime.now(),
    );
    setState(() => _messages.add(msg));
    _inputController.clear();
    _scrollToBottom();

    if (_project.id != 'new') {
      _svc.insertMessage(sessionId: _project.id, role: 'user', content: msg.content);
    } else {
      _pendingMessages.add(msg);
    }
  }

  Future<void> _generate() async {
    if (_isGenerating) return;

    final beforeUrl = _project.beforeImageUrl;
    if (beforeUrl == null || beforeUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please upload a source photo first.'),
          backgroundColor: AppColors.accentDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
      _messages.add(MessageModel(
        id: 'loading_${DateTime.now().millisecondsSinceEpoch}',
        content: '',
        isAi: true,
        type: MessageType.loading,
        createdAt: DateTime.now(),
      ));
    });
    _scrollToBottom();

    final lastUserMsg = _messages
        .where((m) => !m.isAi && m.type == MessageType.text)
        .lastOrNull;
    final prompt = lastUserMsg?.content ?? '';
    final newCount = _iterationCount + 1;
    final styleLabel = '$_currentStyle · Vision $newCount';

    try {
      final result = await GenerationService().generate(
        sessionId: _project.id,
        prompt: prompt,
        beforeImageUrl: beforeUrl,
        styleLabel: styleLabel,
        roomType: _currentRoomType,
      );

      if (!mounted) return;

      final afterUrl = result['after_image_url'] as String;
      final aiText = result['ai_message'] as String;

      setState(() {
        _isGenerating = false;
        _hasGenerated = true;
        _iterationCount = newCount;
        _messages.removeWhere((m) => m.type == MessageType.loading);
        _messages.add(MessageModel(
          id: 'result_${DateTime.now().millisecondsSinceEpoch}',
          content: aiText,
          isAi: true,
          type: MessageType.imageResult,
          result: GeneratedResult(
            beforeImageUrl: beforeUrl,
            afterImageUrl: afterUrl,
            styleLabel: styleLabel,
            projectId: _project.id,
          ),
          createdAt: DateTime.now(),
        ));
      });
      _scrollToBottom();

      if (_project.id != 'new') {
        _svc.insertMessage(
          sessionId: _project.id,
          role: 'ai',
          content: aiText,
          messageType: 'image_result',
          beforeImageUrl: beforeUrl,
          afterImageUrl: afterUrl,
          styleLabel: styleLabel,
        );
        ref.read(sessionProvider.notifier).updateLatestPreview(_project.id, afterUrl);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _messages.removeWhere((m) => m.type == MessageType.loading);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Generation failed — please try again.'),
          backgroundColor: AppColors.accentDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _showSourcePhotoSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SourcePhotoSheet(
        project: _project,
        sourceFile: _sourceImageFile,
        initialRoomType: _currentRoomType,
        initialStyle: _currentStyle,
        onReplace: _replaceSourcePhoto,
        onDirectionChanged: (roomType, style) {
          setState(() {
            _currentRoomType = roomType;
            _currentStyle = style;
          });
        },
      ),
    );
  }

  Future<void> _replaceSourcePhoto() async {
    Navigator.of(context).pop();
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    final l10n = context.l10n;
    setState(() {
      _sourceImageFile = File(picked.path);
      _messages.add(MessageModel(
        id: 'sys_${DateTime.now().millisecondsSinceEpoch}',
        content: '${l10n.sourcePhotoUpdated} · $_currentRoomType',
        isAi: false,
        type: MessageType.system,
        createdAt: DateTime.now(),
      ));
    });
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final headerSubtitle = _iterationCount > 0
        ? '$_currentStyle · ${l10n.visionCount(_iterationCount)}'
        : '$_currentStyle · ${l10n.readyToCreate}';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: _isEditingTitle
            ? TextField(
                controller: _titleEditController,
                focusNode: _titleFocusNode,
                style: Theme.of(context).textTheme.titleMedium,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
                onSubmitted: (_) => _applyTitleEdit(),
                textInputAction: TextInputAction.done,
              )
            : GestureDetector(
                onTap: () {
                  _titleEditController.text = _sessionTitle;
                  setState(() => _isEditingTitle = true);
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _titleFocusNode.requestFocus(),
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            _sessionTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Icon(Icons.edit_outlined, size: 12, color: AppColors.textTertiary),
                      ],
                    ),
                    Text(
                      headerSubtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                    ),
                  ],
                ),
              ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _isGenerating
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary),
                    ),
                  )
                : AppButton(
                    label: l10n.generateButton,
                    fullWidth: false,
                    icon: Icons.auto_awesome,
                    variant: AppButtonVariant.accent,
                    onPressed: _generate,
                  ),
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(
          children: [
            _SourceContextStrip(
              project: _project,
              sourceFile: _sourceImageFile,
              currentRoomType: _currentRoomType,
              currentStyle: _currentStyle,
              onTap: _showSourcePhotoSheet,
            ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  AppSpacing.sm,
                  AppSpacing.pagePadding,
                  AppSpacing.sm,
                ),
                itemCount: _listItems.length,
                itemBuilder: (context, index) {
                  final item = _listItems[index];
                  if (item is DateTime) return _DaySeparator(date: item);
                  final msg = item as MessageModel;
                  return switch (msg.type) {
                    MessageType.loading => _LoadingBubble(key: ValueKey(msg.id)),
                    MessageType.imageResult => _ImageResultBubble(
                        key: ValueKey(msg.id),
                        message: msg,
                        index: index,
                      ),
                    MessageType.system => _SystemMessageBubble(
                        key: ValueKey(msg.id),
                        message: msg,
                      ),
                    MessageType.text => _TextBubble(
                        key: ValueKey(msg.id),
                        message: msg,
                        index: index,
                      ),
                  };
                },
              ),
            ),
            _SuggestionBar(
              suggestions: _suggestions,
              onTap: _send,
              enabled: !_isGenerating,
            ),
            _InputBar(
              controller: _inputController,
              onSend: _send,
              enabled: !_isGenerating,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Day separator ─────────────────────────────────────────────────────────────

class _DaySeparator extends StatelessWidget {
  final DateTime date;
  const _DaySeparator({required this.date});

  String _label(BuildContext context) {
    final l10n = context.l10n;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return l10n.today;
    if (diff == 1) return l10n.yesterday;
    return DateFormat('MMMM d').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: AppColors.border, thickness: 0.5)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _label(context),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                    letterSpacing: 0.4,
                  ),
            ),
          ),
          Expanded(child: Divider(color: AppColors.border, thickness: 0.5)),
        ],
      ),
    );
  }
}

// ── Text bubble ───────────────────────────────────────────────────────────────

class _TextBubble extends StatefulWidget {
  final MessageModel message;
  final int index;
  const _TextBubble({super.key, required this.message, required this.index});

  @override
  State<_TextBubble> createState() => _TextBubbleState();
}

class _TextBubbleState extends State<_TextBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    final dx = widget.message.isAi ? -0.05 : 0.05;
    _slide = Tween<Offset>(begin: Offset(dx, 0.02), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    Future.delayed(Duration(milliseconds: 30 * widget.index.clamp(0, 8)), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAi = widget.message.isAi;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Align(
          alignment: isAi ? Alignment.centerLeft : Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isAi) ...[
                _AiAvatar(),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: isAi ? AppColors.surface : AppColors.textPrimary,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isAi ? 4 : 18),
                      bottomRight: Radius.circular(isAi ? 18 : 4),
                    ),
                    border: isAi ? Border.all(color: AppColors.border) : null,
                  ),
                  child: Text(
                    widget.message.content,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isAi ? AppColors.textPrimary : AppColors.surface,
                          height: 1.6,
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

// ── Loading bubble ────────────────────────────────────────────────────────────

const _thinkingPhrases = [
  'Analyzing your space…',
  'Exploring material palettes…',
  'Understanding the light flow…',
  'Refining the atmosphere…',
  'Composing the vision…',
];

class _LoadingBubble extends StatefulWidget {
  const _LoadingBubble({super.key});

  @override
  State<_LoadingBubble> createState() => _LoadingBubbleState();
}

class _LoadingBubbleState extends State<_LoadingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  int _phraseIndex = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300))..forward();
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _cyclePhrase();
  }

  void _cyclePhrase() async {
    while (mounted) {
      await Future.delayed(const Duration(milliseconds: 2200));
      if (mounted) {
        setState(() => _phraseIndex = (_phraseIndex + 1) % _thinkingPhrases.length);
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _AiAvatar(),
            const SizedBox(width: 8),
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                  bottomLeft: Radius.circular(4),
                ),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DotsIndicator(),
                  const SizedBox(height: 6),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 380),
                    child: Text(
                      _thinkingPhrases[_phraseIndex],
                      key: ValueKey(_phraseIndex),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DotsIndicator extends StatefulWidget {
  @override
  State<_DotsIndicator> createState() => _DotsIndicatorState();
}

class _DotsIndicatorState extends State<_DotsIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _active = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 450))..repeat();
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _active = (_active + 1) % 3);
        _ctrl.forward(from: 0);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) => _Dot(active: _active == i)),
    );
  }
}

class _Dot extends StatelessWidget {
  final bool active;
  const _Dot({required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 7,
      height: 7,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: active ? AppColors.accent : AppColors.border,
        shape: BoxShape.circle,
      ),
    );
  }
}

// ── Image result bubble ───────────────────────────────────────────────────────

class _ImageResultBubble extends StatefulWidget {
  final MessageModel message;
  final int index;
  const _ImageResultBubble({super.key, required this.message, required this.index});

  @override
  State<_ImageResultBubble> createState() => _ImageResultBubbleState();
}

class _ImageResultBubbleState extends State<_ImageResultBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _scale = Tween<double>(begin: 0.95, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.message.result!;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _AiAvatar(),
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    constraints:
                        BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(18),
                        topRight: Radius.circular(18),
                        bottomRight: Radius.circular(18),
                        bottomLeft: Radius.circular(4),
                      ),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      widget.message.content,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 36, bottom: 10),
              child: ScaleTransition(
                scale: _scale,
                child: _GeneratedImageCard(
                  result: result,
                  createdAt: widget.message.createdAt,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GeneratedImageCard extends StatelessWidget {
  final GeneratedResult result;
  final DateTime createdAt;
  const _GeneratedImageCard({required this.result, required this.createdAt});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image with style badge
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: CachedNetworkImage(
                  imageUrl: result.afterImageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(color: AppColors.shimmerBase),
                  errorWidget: (_, _, _) => Container(color: AppColors.shimmerBase),
                ),
              ),
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.textPrimary.withAlpha(200),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Text(
                    result.styleLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.surface,
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                  ),
                ),
              ),
            ],
          ),
          // Actions + timestamp
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _CardAction(
                  icon: Icons.compare,
                  label: l10n.viewBeforeAfter,
                  primary: true,
                  onTap: () => context.push('/result/${result.projectId}', extra: result),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _CardAction(
                        icon: Icons.bookmark_outline,
                        label: l10n.saveDesign,
                        onTap: () => _showSnack(context, 'Saved to your transformations.'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _CardAction(
                        icon: Icons.ios_share,
                        label: l10n.shareDesign,
                        onTap: () => Share.share(
                          'Check out my AI home transformation — ${result.styleLabel}!',
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _CardAction(
                        icon: Icons.refresh,
                        label: l10n.tryAnother,
                        onTap: () => _showSnack(context, 'Generating another variation...'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${l10n.visionCreated} ${_timeAgo(createdAt)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 10,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.textPrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  const _CardAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: primary ? 16 : 10,
          vertical: primary ? 12 : 10,
        ),
        decoration: BoxDecoration(
          color: primary ? AppColors.textPrimary : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: primary ? AppColors.surface : AppColors.textSecondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: primary ? AppColors.surface : AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class _AiAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(color: AppColors.textPrimary, shape: BoxShape.circle),
      child: const Icon(Icons.architecture, color: AppColors.background, size: 14),
    );
  }
}

class _SuggestionBar extends StatelessWidget {
  final List<String> suggestions;
  final ValueChanged<String> onTap;
  final bool enabled;
  const _SuggestionBar({required this.suggestions, required this.onTap, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: Container(
        key: ValueKey(suggestions.first),
        height: 48,
        color: AppColors.background,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding, vertical: 6),
          itemCount: suggestions.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) => GestureDetector(
            onTap: enabled ? () => onTap(suggestions[index]) : null,
            child: AnimatedOpacity(
              opacity: enabled ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  suggestions[index],
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InputBar extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSend;
  final bool enabled;
  const _InputBar({required this.controller, required this.onSend, required this.enabled});

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> with SingleTickerProviderStateMixin {
  final _speech = SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;

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
    _initSpeech();
  }

  void _onTextChanged() => setState(() {});

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onError: (_) => _stop(),
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') _stop();
      },
    );
    if (mounted) setState(() {});
  }

  Future<void> _toggleListening() async {
    _isListening ? _stop() : await _startListening();
  }

  Future<void> _startListening() async {
    if (!_speechAvailable || !mounted) return;
    setState(() => _isListening = true);
    _pulseCtrl.repeat();
    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        widget.controller.text = result.recognizedWords;
        widget.controller.selection = TextSelection.fromPosition(
          TextPosition(offset: widget.controller.text.length),
        );
      },
      listenOptions: SpeechListenOptions(partialResults: true, cancelOnError: true),
    );
  }

  void _stop() {
    _speech.stop();
    _pulseCtrl.stop();
    _pulseCtrl.reset();
    if (mounted) setState(() => _isListening = false);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _pulseCtrl.dispose();
    _speech.cancel();
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
                    : widget.enabled ? l10n.chatPlaceholder : l10n.chatGeneratingHint,
                filled: true,
                fillColor: AppColors.background,
              ),
              onSubmitted: widget.enabled ? widget.onSend : null,
              textInputAction: TextInputAction.send,
              maxLines: null,
            ),
          ),
          const SizedBox(width: 8),
          if (_speechAvailable) ...[
            _MicButton(
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
              onTap: widget.enabled && hasText ? () => widget.onSend(widget.controller.text) : null,
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppColors.textPrimary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_upward_rounded, color: AppColors.surface, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  final bool isListening;
  final bool enabled;
  final Animation<double> pulseScale;
  final Animation<double> pulseOpacity;
  final VoidCallback? onTap;
  const _MicButton({
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
                      border: Border.all(color: AppColors.accent, width: 1.5),
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
                  color: isListening ? AppColors.accent : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Source context strip ──────────────────────────────────────────────────────

class _SourceContextStrip extends StatelessWidget {
  final ProjectModel project;
  final File? sourceFile;
  final String currentRoomType;
  final String currentStyle;
  final VoidCallback onTap;
  const _SourceContextStrip({
    required this.project,
    this.sourceFile,
    required this.currentRoomType,
    required this.currentStyle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pagePadding,
          vertical: 10,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: sourceFile != null
                  ? Image.file(sourceFile!, width: 34, height: 34, fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium)
                  : project.beforeImageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: project.beforeImageUrl!,
                          width: 34,
                          height: 34,
                          fit: BoxFit.cover,
                          placeholder: (_, _) =>
                              Container(width: 34, height: 34, color: AppColors.shimmerBase),
                          errorWidget: (_, _, _) =>
                              Container(width: 34, height: 34, color: AppColors.shimmerBase),
                        )
                      : Container(width: 34, height: 34, color: AppColors.shimmerBase),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.sourcePhoto,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 10,
                        ),
                  ),
                  Text(
                    '$currentRoomType · $currentStyle',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.swap_horiz_outlined, size: 16, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

// ── Source photo / design direction sheet ─────────────────────────────────────

class _SourcePhotoSheet extends StatefulWidget {
  final ProjectModel project;
  final File? sourceFile;
  final String initialRoomType;
  final String initialStyle;
  final VoidCallback onReplace;
  final void Function(String roomType, String style) onDirectionChanged;

  const _SourcePhotoSheet({
    required this.project,
    this.sourceFile,
    required this.initialRoomType,
    required this.initialStyle,
    required this.onReplace,
    required this.onDirectionChanged,
  });

  @override
  State<_SourcePhotoSheet> createState() => _SourcePhotoSheetState();
}

class _SourcePhotoSheetState extends State<_SourcePhotoSheet> {
  late String _selectedRoomType;
  late String _selectedStyle;

  static const _roomTypes = [
    'Living Room', 'Bedroom', 'Kitchen', 'Terrace',
    'Villa Exterior', 'Home Office', 'Pool Area', 'Dining Room',
  ];

  static const _styles = [
    'Tropical Escape', 'Warm Modern', 'Zen Retreat', 'Bali Sanctuary',
    'Japandi Calm', 'Soft Luxury', 'Nordic Warmth', 'Dark Contemporary',
    'Nature Retreat', 'Desert Luxe',
  ];

  @override
  void initState() {
    super.initState();
    _selectedRoomType = widget.initialRoomType;
    _selectedStyle = widget.initialStyle;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        20,
        AppSpacing.pagePadding,
        AppSpacing.xl + safeBottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Design Direction',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 3),
          Text(
            'Currently: $_selectedRoomType · $_selectedStyle',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: 16),
          // Compact photo row
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: widget.sourceFile != null
                      ? Image.file(widget.sourceFile!, fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium)
                      : widget.project.beforeImageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: widget.project.beforeImageUrl!,
                              fit: BoxFit.cover,
                              placeholder: (_, _) => Container(color: AppColors.shimmerBase),
                              errorWidget: (_, _, _) => Container(color: AppColors.shimmerBase),
                            )
                          : Container(color: AppColors.shimmerBase),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.sourcePhoto,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 10,
                        ),
                  ),
                  GestureDetector(
                    onTap: widget.onReplace,
                    child: Text(
                      l10n.replacePhoto,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 22),
          // Space type
          Text(
            'SPACE TYPE',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                  letterSpacing: 0.8,
                ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _roomTypes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final rt = _roomTypes[i];
                final selected = rt == _selectedRoomType;
                return GestureDetector(
                  onTap: () => setState(() => _selectedRoomType = rt),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.textPrimary : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(
                        color: selected ? AppColors.textPrimary : AppColors.border,
                      ),
                    ),
                    child: Text(
                      rt,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: selected ? AppColors.surface : AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 22),
          // Atmosphere
          Text(
            'ATMOSPHERE',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                  letterSpacing: 0.8,
                ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _styles.map((s) {
              final selected = s == _selectedStyle;
              return GestureDetector(
                onTap: () => setState(() => _selectedStyle = s),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.textPrimary : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(
                      color: selected ? AppColors.textPrimary : AppColors.border,
                    ),
                  ),
                  child: Text(
                    s,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: selected ? AppColors.surface : AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                widget.onDirectionChanged(_selectedRoomType, _selectedStyle);
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.textPrimary,
                foregroundColor: AppColors.surface,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text(
                'Apply Direction',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.surface),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── System message bubble ─────────────────────────────────────────────────────

class _SystemMessageBubble extends StatelessWidget {
  final MessageModel message;
  const _SystemMessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: AppColors.border, thickness: 0.5)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              message.content,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ),
          Expanded(child: Divider(color: AppColors.border, thickness: 0.5)),
        ],
      ),
    );
  }
}
