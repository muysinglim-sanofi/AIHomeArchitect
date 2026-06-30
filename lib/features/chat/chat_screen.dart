import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../../core/feature_flags.dart';
import '../cards/card_catalog.dart';
import '../cards/widgets/atmosphere_hero_card.dart';
import '../cards/widgets/room_card.dart';
import '../cards/widgets/ai_action_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../shared/widgets/image_picker_sheet.dart';
import 'package:intl/intl.dart';
import 'widgets/chat_input_bar.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/atmosphere_display.dart';
import '../../core/constants/free_tier.dart';
import '../../core/constants/room_type_images.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/models/atmosphere_style.dart';
import '../../core/providers/locale_provider.dart';
import '../../core/providers/me_status_provider.dart';
import '../../core/providers/pending_generations_provider.dart';
import '../../core/providers/active_session_provider.dart';
import '../../core/providers/premium_provider.dart';
import '../../core/providers/access_provider.dart';
import '../../core/providers/session_provider.dart';
import '../../core/services/local_notification_service.dart';
import '../../core/services/session_persistence_service.dart';
import '../../data/services/generation_service.dart';
import '../../data/services/supabase_service.dart';
import '../paywall/paywall_sheet.dart';
import '../../data/models/message_model.dart';
import '../../data/models/project_model.dart';
import '../../data/models/session_state.dart';
import '../../core/widgets/scrim.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_pill.dart';
import '../../shared/widgets/atmosphere_card.dart';
import '../../shared/widgets/pinch_zoom.dart';
import '../../shared/widgets/reveal_canvas.dart';
import '../../shared/widgets/room_type_card.dart';
import '../../shared/widgets/sticky_action_bar.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

String _timeAgo(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'yesterday';
  return '${diff.inDays}d ago';
}

/// #4-B — show the Ayden Signature (surprise) atmosphere with its brand label
/// instead of the internal "AI's choice" sentinel. Display ONLY — the stored /
/// routed VALUE (_currentStyle, style_label, the session title) stays
/// "AI's choice"; only what the user reads is rebranded. Works on a bare style
/// ("AI's choice") and on a composed title ("Master Bedroom — AI's choice").
/// Delegates to the shared single source of truth (atmosphere_display.dart) so
/// the chat screen and the project gallery can never desync.
String _brandSignature(String s) => brandSignature(s);

// ── Chat screen ───────────────────────────────────────────────────────────────

class ChatScreen extends ConsumerStatefulWidget {
  final String projectId;
  final String? initialRoomType;
  final String? initialStyle;
  // Wave 4.8.5 — real conversational-intelligence intent (never fake
  // strings). When [initialAiDecide] the backend infers the room; when
  // [initialSurprise] the backend selects the atmosphere; [initialDescription]
  // is the user's free-text architectural direction → V1 prompt.
  final bool initialAiDecide;
  final bool initialSurprise;
  final String? initialDescription;
  // Wave 5.5.14b.2 — bimodal intent at session start. "preserve" (default,
  // today's behaviour) or "creative". User can flip per-generation later via
  // the source-photo sheet; this seeds the initial value for V1.
  final String initialMode;
  final File? sourceImageFile;
  // Phase A — entered via a "vision ready" notification deep-link. When the
  // target session no longer exists (deleted between completion and tap),
  // _loadMessages bounces cleanly to home instead of showing an empty chat.
  final bool fromNotification;
  const ChatScreen({
    super.key,
    required this.projectId,
    this.initialRoomType,
    this.initialStyle,
    this.initialAiDecide = false,
    this.initialSurprise = false,
    this.initialDescription,
    this.initialMode = 'preserve',
    this.sourceImageFile,
    this.fromNotification = false,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isGenerating = false;
  // #21 — monotonic generation guard. Bumped at each /generate start; the
  // in-flight call captures its value and every completion path bails if it no
  // longer matches (the gen was superseded — e.g. a foreground-resume
  // reconciliation adopted the DB result first). Prevents a late await from
  // appending a DUPLICATE vision after the timeline was already rebuilt.
  int _genSeq = 0;
  // #21 — single reconciliation poll timer (stored so it can be cancelled on
  // dispose and never stacked across resumes / transport retries).
  Timer? _reconcileTimer;
  // Wave 6.15 — perceived-latency: true while the V1 loading bubble is shown
  // EARLY (source image visible instantly) but the Supabase init chain
  // (createSession + source upload) is still running, before _generate fires.
  // Gates the composer like _isGenerating but does NOT block _generate's own
  // re-entrancy guard. Cleared the moment _generate starts (or on init failure).
  bool _v1Priming = false;
  bool get _busy => _isGenerating || _v1Priming;
  Timer? _longGenerationTimer;
  // Group 1 — app-scoped "visible session" controller (set on visible, cleared
  // on dispose/background) so completion handlers can suppress the "ready"
  // notify for the session the user is actually looking at.
  StateController<String?>? _activeSessionCtrl;
  bool _isChatting = false;
  bool _hasGenerated = false;
  bool _hasAutoGeneratedInitialVision = false;
  // ── Duplicate-generation guard (P0 billing fix 2026-06-25) ────────────────
  // ONE shared authorization for every _generate() entry point (auto / button /
  // switch / chat / future). A "logical generation" is identified by
  // session|source|iteration|attempt. The guard blocks (a) a concurrent fire
  // (_isGenerating) and (b) an accidental re-fire of an already-SUCCEEDED logical
  // generation (e.g. auto-gen + Generate button on the same source). An
  // INTENTIONAL regenerate bumps _genAttempt → new logical key → allowed. The
  // stable per-key clientRequestId lets the backend idempotency replay-cache
  // dedup a duplicate that still slips through. Failures never mark succeeded →
  // a retry of a failed generation is always allowed.
  // Mutable by design: an intentional "regenerate" bumps this so the logical key
  // changes and the guard ALLOWS the re-generation (not a duplicate).
  // ignore: prefer_final_fields
  int _genAttempt = 0;
  final Set<String> _succeededGenKeys = {};
  final Map<String, String> _requestIdForKey = {};
  List<String> _dynamicSuggestions = [];
  // Tracks the editing chain: starts null (use original upload), then
  // advances to each new generation so refinements build on the last output.
  String? _generationSourceUrl;

  // BUG A fix — one-shot branch pin: the version_id the user chose via
  // "Continue this vision". When set, the next /generate sends
  // source_mode=SPECIFIC_VERSION so the backend actually rebranches the source
  // (resolve_source ignores before_image_url). Cleared after that generation.
  String? _branchSourceVersionId;

  late String _sessionTitle;
  // CHANTIER C — once true, the user renamed the session manually, so the
  // room+atmosphere auto-naming backs off and never overrides their choice.
  bool _titleManuallySet = false;
  bool _isEditingTitle = false;
  final _titleEditController = TextEditingController();
  final _titleFocusNode = FocusNode();

  File? _sourceImageFile;
  // Set when the user replaces the source mid-session; consumed on the next
  // generation to start a FRESH lineage (re-upload + reset chain → FIRST_VISION).
  bool _sourceReplaced = false;
  final _picker = ImagePicker();

  late String _currentRoomType;
  late String _currentStyle;

  // Wave 4.8.5 — real semantic intent for the FIRST vision. Sent as flags to
  // /generate (let_ai_decide / surprise_me_flag); the description becomes the
  // V1 prompt → composer design-direction. Only meaningful at V1: once the
  // room is inferred / atmosphere chosen, later refinements steer normally.
  bool _letAiDecide = false;
  bool _surpriseMe = false;
  String? _pendingDescription;

  // Wave 5.5.14c — bimodal generation intent. "preserve" (default, today's
  // behaviour) | "creative" (Surprise Me / Create path). Per-generation
  // binding: each /generate POST sends the current value; state persisted
  // via SessionState so reopen restores last-used mode.
  String _generationMode = 'preserve';

  late ProjectModel _project;
  late List<MessageModel> _messages;
  late int _iterationCount;

  // Wave 4.7.2 — persisted architectural identity token (one-time capture at
  // V1, round-tripped on V2+ so structural_identity_clause stays present).
  String _structuralIdentity = '';
  // Wave 4.7.3 — client-persisted version ledger so the backend can resolve
  // LATEST / SPECIFIC_VERSION without server-side session state.
  String _versions = '';

  late final SupabaseService _svc;
  // Messages queued while the Supabase session is still being created.
  final List<MessageModel> _pendingMessages = [];

  // Wave 4.10g — local persistence layer for protocol round-trip tokens
  // and conversational continuity. Hydrated from SharedPreferences on
  // existing-session restore; written through after every state mutation
  // that matters (generation success, atmosphere swap, source change).
  // Lazy-initialised in initState (async); nullable until ready so we can
  // safely no-op if hydration races with a backend call.
  SessionPersistenceService? _persistence;

  late final AnimationController _entryController;
  late final Animation<double> _fadeAnim;

  List<String> get _suggestions {
    if (_dynamicSuggestions.isNotEmpty) return _dynamicSuggestions;
    // Localized static fallback (dynamic backend suggestions take priority above).
    final l10n = context.l10n;
    return (_hasGenerated || _iterationCount > 0)
        ? l10n.postGenerationSuggestions
        : l10n.preGenerationSuggestions;
  }

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
    // [ChatLife] — instance lifecycle trace. A spontaneous dispose+recreate of
    // this State (no user navigation) orphans an in-flight /generate into the
    // !mounted completion branch (DB written, in-memory card never built →
    // "image disappears until reopen"). hashCode identifies the instance so a
    // dispose can be paired with the initState that replaced it.
    debugPrint('[ChatLife] initState #$hashCode session=${widget.projectId}');
    // #21 — observe app lifecycle so a generation that finished while the app
    // was backgrounded gets reconciled from the DB on resume (the in-flight
    // HTTP future can silently never complete after the OS drops the socket).
    WidgetsBinding.instance.addObserver(this);
    _svc = ref.read(supabaseServiceProvider);

    // Wave 4.10g — kick off async persistence init. Hydration for existing
    // sessions happens here; new sessions get persistence only once their
    // real Supabase id exists (handled inside _initNewSession via
    // _persistSession() after the createSession returns).
    _initPersistence();

    // Wave 5.6c — clear any pending readyUnseen / errorUnseen flag for
    // this session. User opening the chat IS the acknowledgement that
    // the badge can be cleared. inFlight states are preserved (generation
    // still in progress, no acknowledgement yet).
    // Group 1 — hold the active-session controller (app-scoped, outlives this
    // widget) so dispose() can clear the "visible session" signal safely.
    _activeSessionCtrl = ref.read(activeSessionProvider.notifier);
    if (widget.projectId != 'new') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final notifier = ref.read(pendingGenerationsProvider.notifier);
        final state = ref.read(pendingGenerationsProvider)[widget.projectId];
        if (state == GenerationLifecycle.readyUnseen ||
            state == GenerationLifecycle.errorUnseen) {
          notifier.clear(widget.projectId);
        }
        // Group 1 — mark this session as the one the user is viewing, so a
        // completion fired on a now-disposed instance won't notify for it.
        _markSessionActive();
      });
    }

    if (widget.projectId == 'new') {
      _letAiDecide = widget.initialAiDecide;
      _surpriseMe = widget.initialSurprise;
      final desc = widget.initialDescription?.trim();
      _pendingDescription = (desc != null && desc.isNotEmpty) ? desc : null;
      // Wave 5.5.14b.2 — seed bimodal intent from upload-screen choice.
      _generationMode = widget.initialMode;

      // Real semantics, never fake strings:
      //  • AI Decide → no explicit room (backend infers via classify_room).
      //  • Surprise Me → a neutral, inert display/fallback label ("AI's
      //    choice"); the operative selection is surprise_me_flag, which the
      //    backend resolves to a real atmosphere and overrides internally.
      final roomType = _letAiDecide ? '' : (widget.initialRoomType ?? 'Living Room');
      final style = _surpriseMe
          ? "AI's choice"
          : (widget.initialStyle ?? 'Modern Minimalist');

      // #7 localization — context.l10n is illegal in initState (InheritedWidget
      // lookup), so build AppLocalizations from the Riverpod locale (ref.read is
      // legal here) to localize the V1 greeting (FR/KM regression fix).
      final greetL10n = AppLocalizations(Locale(ref.read(localeProvider).languageCode));
      final greeting = () {
        if (_letAiDecide && _surpriseMe) {
          return greetL10n.genReadyAiSurprise;
        }
        if (_surpriseMe) {
          return greetL10n.genReadySurprise;
        }
        if (_letAiDecide) {
          return greetL10n.genReadyAiDecide(style);
        }
        return greetL10n.genReadyDefault(style);
      }();

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
          content: greeting,
          isAi: true,
          createdAt: DateTime.now(),
        ),
        // Wave 6.15 — show the V1 loading bubble IMMEDIATELY (it renders the
        // local source file as backdrop), so the source image appears the
        // instant the chat opens — instead of waiting for createSession +
        // source upload to finish. _generate (after the upload) reuses this
        // bubble (it won't add a second one). content "1|<style>" = iteration 1.
        MessageModel(
          id: 'loading_v1_priming',
          content: '1|$style',
          isAi: true,
          type: MessageType.loading,
          createdAt: DateTime.now(),
        ),
      ];
      _v1Priming = true;
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
      _loadMessages(trigger: 'init');
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

  // Group 1 — mark/clear the "session the user is viewing". Guarded by the flag
  // so rollback is total. _activeSessionCtrl is app-scoped (outlives this
  // widget), so clearing it in dispose() is safe even after ref is gone.
  void _markSessionActive() {
    if (!FeatureFlags.genLifecycleV2) return;
    if (_project.id.isEmpty || _project.id == 'new') return;
    _activeSessionCtrl?.state = _project.id;
  }

  void _clearSessionActive() {
    if (!FeatureFlags.genLifecycleV2) return;
    final ctrl = _activeSessionCtrl;
    final id = _project.id;
    if (ctrl == null) return;
    // DEFER the write: Riverpod forbids modifying a provider during a widget
    // life-cycle (build/dispose) — doing it synchronously in dispose() threw and
    // aborted the rest of dispose (timers never cancelled → reconciliation poll
    // kept running on a disposed widget; activeSession never cleared → all
    // notifications stayed suppressed). The controller is app-scoped so the
    // deferred write is safe. Only clear if WE still own the signal (a newer
    // chat may already have claimed it).
    Future(() {
      if (ctrl.state == id) ctrl.state = null;
    });
  }

  @override
  void dispose() {
    // [ChatLife] — pairs with the initState log. `isGenerating=true` here is the
    // smoking gun: this instance is being torn down WHILE a generation it
    // launched is still in flight → that await will resolve in the !mounted
    // branch (orphaned). The hashCode matches the initState that created it.
    debugPrint('[ChatLife] dispose #$hashCode session=${_project.id} '
        'isGenerating=$_isGenerating');
    // Cancel timers FIRST so a throw later in dispose can never leave the
    // reconciliation poll running on a disposed widget.
    WidgetsBinding.instance.removeObserver(this);
    _longGenerationTimer?.cancel();
    _reconcileTimer?.cancel();
    _clearSessionActive();
    _inputController.dispose();
    _scrollController.dispose();
    _entryController.dispose();
    _titleEditController.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  // #21 — foreground reconciliation. While the app is backgrounded, Dart timers
  // are suspended and the in-flight /generate HTTP future can silently never
  // complete (the OS drops the socket). On resume we treat the DB as the source
  // of truth and reconcile, instead of trusting the local widget state.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Group 1 — keep the "visible session" signal in sync with foreground state:
    // backgrounding clears it (so a completion that lands while backgrounded DOES
    // notify); resuming re-marks this chat as visible.
    if (state == AppLifecycleState.resumed) {
      _markSessionActive();
    } else {
      _clearSessionActive();
    }
    if (state != AppLifecycleState.resumed) return;
    if (!mounted || _project.id == 'new') return;

    final pending = ref.read(pendingGenerationsProvider)[_project.id];
    // Returning to the chat acknowledges any ready/error badge for this session.
    if (pending == GenerationLifecycle.readyUnseen ||
        pending == GenerationLifecycle.errorUnseen) {
      ref.read(pendingGenerationsProvider.notifier).clear(_project.id);
    }

    // Only reconcile when something is actually pending — a live spinner or a
    // session still flagged in-flight/ready. Avoids a needless DB refetch (and
    // any flicker) on every ordinary app resume.
    final needsReconcile = _isGenerating ||
        pending == GenerationLifecycle.inFlight ||
        pending == GenerationLifecycle.readyUnseen;
    if (!needsReconcile) return;

    // Reuse the hardened poll: it loads the DB truth, clears the spinner only
    // when an image_result actually exists (no phantom clear if the gen is
    // genuinely still running), and fails gracefully after 90s.
    _startReconciliationPolling(sessionId: _project.id);
  }

  // ── Local persistence (Wave 4.10g) ────────────────────────────────────────
  //
  // Local snapshot of protocol round-trip tokens + conversational continuity.
  // Hydrates the in-memory state on existing-session reopen / app restart
  // so Wave 4.7.2 / 4.7.3 / 5.5.5 / 5.5.6 / 5.5.12 all see a consistent
  // V2+ environment instead of an empty token forcing backend re-capture.

  /// Initialise SharedPreferences and, for existing sessions, hydrate the
  /// in-memory state from the persisted snapshot. Non-fatal; failures
  /// degrade to an empty in-memory state (same behaviour as pre-Wave 4.10g).
  Future<void> _initPersistence() async {
    try {
      _persistence = await SessionPersistenceService.create();
    } catch (e) {
      debugPrint('[Persistence] init failed (non-fatal): $e');
      return;
    }
    final svc = _persistence;
    if (svc == null || !mounted) return;
    // Only hydrate existing sessions; new sessions persist forward only.
    if (widget.projectId == 'new') return;

    final snapshot = await svc.load(widget.projectId);
    if (snapshot == null || !mounted) return;

    // Apply only protocol/continuity tokens. UI state (messages, scroll)
    // is reconstructed independently from the message stream so we don't
    // double-source it. iteration_count guard: never go BACKWARDS — if
    // _loadMessages() already inferred a higher value from the message
    // stream, trust the inferred value (it is grounded in real images).
    setState(() {
      _structuralIdentity = snapshot.structuralIdentity;
      _versions = snapshot.versions;
      // generationSourceUrl: prefer snapshot if persisted, else keep whatever
      // _loadMessages inferred (typically the latest afterUrl in messages).
      if (snapshot.generationSourceUrl != null &&
          snapshot.generationSourceUrl!.isNotEmpty) {
        _generationSourceUrl = snapshot.generationSourceUrl;
      }
      // BUG A fix — restore a pending branch pin so "Continue this vision"
      // survives a reload that happens before the next generation.
      _branchSourceVersionId = snapshot.branchSourceVersionId;
      if (snapshot.iterationCount > _iterationCount) {
        _iterationCount = snapshot.iterationCount;
      }
      if (snapshot.currentRoomType.isNotEmpty) {
        _currentRoomType = snapshot.currentRoomType;
      }
      if (snapshot.currentStyle.isNotEmpty) {
        _currentStyle = snapshot.currentStyle;
      }
      _letAiDecide = snapshot.letAiDecide;
      _surpriseMe = snapshot.surpriseMe;
      if (snapshot.pendingDescription != null) {
        _pendingDescription = snapshot.pendingDescription;
      }
      _generationMode = snapshot.generationMode;
    });
    debugPrint(
      '[Persistence] hydrated ${widget.projectId} — '
      'iter=$_iterationCount, '
      'identityChars=${_structuralIdentity.length}, '
      'versionsChars=${_versions.length}, '
      'sourceUrl=${_generationSourceUrl != null ? "yes" : "no"}',
    );
  }

  /// Write-through save of the current in-memory state. Cheap (local) and
  /// non-fatal. Called after every state mutation that should survive
  /// restart: generation success, atmosphere swap, source change,
  /// iteration advance.
  void _persistSession() {
    final svc = _persistence;
    if (svc == null) return;
    final id = _project.id;
    if (id.isEmpty || id == 'new') return; // pre-Supabase: not persistable
    final state = SessionState(
      structuralIdentity: _structuralIdentity,
      versions: _versions,
      generationSourceUrl: _generationSourceUrl,
      branchSourceVersionId: _branchSourceVersionId,
      iterationCount: _iterationCount,
      currentRoomType: _currentRoomType,
      currentStyle: _currentStyle,
      letAiDecide: _letAiDecide,
      surpriseMe: _surpriseMe,
      pendingDescription: _pendingDescription,
      generationMode: _generationMode,
    );
    // Fire-and-forget; SharedPreferences.setString is locally fast.
    unawaited(svc.save(id, state));
  }

  // ── Supabase persistence ──────────────────────────────────────────────────

  /// Called once for new sessions. Creates the row in Supabase, persists the
  /// initial greeting, flushes any messages sent before the row was ready,
  /// then updates _project with the real UUID so subsequent writes work.
  // Wave 6.15 — downscale + JPEG-recompress the source before upload. ~2.2 MB
  // raw → ~0.6 MB, cutting ~3-4s off the Supabase upload (and the gen start).
  // q=85 + 1920px cap preserves all detail the model needs (output is
  // 1536x1024; high-fidelity anchors architecture, not fine grain). Native plugin
  // auto-applies EXIF rotation. Returns null on any failure → caller uses raw.
  Future<Uint8List?> _compressSource(String path) async {
    try {
      return await FlutterImageCompress.compressWithFile(
        path,
        quality: 85,
        minWidth: 1920,
        minHeight: 1920,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
    } catch (e) {
      debugPrint('[Compress] source compress failed (non-fatal): $e');
      return null;
    }
  }

  Future<void> _initNewSession() async {
    // Wave 6.15 — perceived-latency timing. Logs ms elapsed at each Supabase
    // step so we can see exactly where the click→source-image time goes
    // (typically the source upload). Read these in the Flutter console.
    final sw = Stopwatch()..start();
    debugPrint('[Timing] _initNewSession START (t=0)');
    debugPrint('[DB] _initNewSession() started — title: "$_sessionTitle" room: "$_currentRoomType" style: "$_currentStyle"');
    try {
      final realProject = await ref.read(sessionProvider.notifier).createSession(
        title: _sessionTitle,
        roomType: _currentRoomType,
        atmosphere: _currentStyle,
      );
      debugPrint('[Timing] createSession done @ ${sw.elapsedMilliseconds}ms');
      debugPrint('[DB] _initNewSession() session created — id: ${realProject.id}');

      // Upload source image (fire after session exists so we have the real ID for the path).
      String? beforeUrl;
      final imageFile = _sourceImageFile;
      if (imageFile != null) {
        debugPrint('[DB] _initNewSession() uploading source image…');
        try {
          // Wave 6.15 — compress the source before upload (2.2 MB raw → ~0.6 MB)
          // so the upload (and thus the generation start) is ~3-4s faster. Falls
          // back to the raw bytes if compression fails.
          final rawLen = await imageFile.length();
          final compressed = await _compressSource(imageFile.path);
          final bytes = compressed ?? await imageFile.readAsBytes();
          debugPrint(
              '[Compress] source ${(rawLen / 1024).round()} KB → ${(bytes.length / 1024).round()} KB @ ${sw.elapsedMilliseconds}ms');
          final filename = 'source_${DateTime.now().millisecondsSinceEpoch}.jpg';
          beforeUrl = await _svc.uploadSourceImage(
            sessionId: realProject.id,
            filename: filename,
            bytes: bytes,
          );
          await _svc.updateBeforeImageUrl(realProject.id, beforeUrl);
          // Wave 5.3.2 — propagate the upload URL into sessionProvider so the
          // reveal screen's _sessionOriginalUrl() lookup resolves to the real
          // initial upload (previously it stayed null until next session reload,
          // causing the hold-to-original overlay to fall back to the per-step
          // generation source — i.e. the latest render — on V2+ refinements).
          ref.read(sessionProvider.notifier)
              .updateBeforeImageUrl(realProject.id, beforeUrl);
          debugPrint('[Timing] uploadSourceImage (${(bytes.length / 1024).round()} KB) done @ ${sw.elapsedMilliseconds}ms');
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
      debugPrint('[Timing] insertMessage(greeting) done @ ${sw.elapsedMilliseconds}ms');
      debugPrint('[DB] _initNewSession() initial greeting persisted');

      // Flush user messages that arrived before the session row existed.
      if (_pendingMessages.isNotEmpty) {
        debugPrint('[DB] _initNewSession() flushing ${_pendingMessages.length} pending messages');
        for (final msg in _pendingMessages) {
          // #25 — a buffered branch event persists as a 'system' message that
          // carries its after_image_url (same encoding as the live path), so it
          // reconstructs as a branchEvent on reload instead of being downgraded
          // to plain text.
          final isBranch = msg.type == MessageType.branchEvent;
          await _svc.insertMessage(
            sessionId: realProject.id,
            role: (msg.isAi || isBranch) ? 'ai' : 'user',
            content: msg.content,
            messageType: isBranch
                ? 'system'
                : (msg.type == MessageType.imageResult ? 'image_result' : 'text'),
            afterImageUrl: isBranch ? msg.result?.afterImageUrl : null,
            styleLabel: isBranch ? msg.result?.styleLabel : null,
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

      // Wave 4.10g — Supabase id is finalised; capture the initial snapshot
      // so even a pre-V1 app restart preserves room/style/AI-Decide context.
      _persistSession();
      // Group 1 — the real id now exists; mark this freshly-created session as
      // the one on screen so its first generation never notifies itself.
      _markSessionActive();

      // Auto-generate Vision 1 once the session and image are confirmed ready.
      debugPrint('[Timing] init chain complete, triggering autogen @ ${sw.elapsedMilliseconds}ms (this is when the source image / loading bubble appears in the OLD flow)');
      debugPrint('[AutoGen] beforeImageUrl resolved — eligible: ${beforeUrl != null && mounted}');
      _triggerAutoGenerate();
    } catch (e, st) {
      debugPrint('[DB] _initNewSession() ERROR: $e');
      debugPrint('[DB] _initNewSession() STACK: $st');
      _abortV1Priming('init error: $e');
    }
  }

  // Wave 6.15 — the V1 loading bubble is shown EARLY (priming). If the init
  // chain fails before _generate runs (createSession/upload error → no
  // beforeImageUrl), that bubble would hang forever. Remove it + surface the
  // failure so the user can retry. No-op once _generate has taken over.
  void _abortV1Priming(String reason) {
    if (!_v1Priming) return; // _generate already owns the loading state
    debugPrint('[Wave 6.15] aborting V1 priming — $reason');
    if (!mounted) {
      _v1Priming = false;
      return;
    }
    setState(() {
      _v1Priming = false;
      _isGenerating = false;
      _messages.removeWhere((m) => m.type == MessageType.loading);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.genStartError),
        backgroundColor: AppColors.accentDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _triggerAutoGenerate() {
    if (_hasAutoGeneratedInitialVision) {
      debugPrint('[AutoGen] skipped — already triggered this session');
      return;
    }
    if (!mounted) {
      debugPrint('[AutoGen] skipped — widget not mounted');
      return;
    }
    if (_project.beforeImageUrl == null || _project.beforeImageUrl!.isEmpty) {
      debugPrint('[AutoGen] skipped — no beforeImageUrl');
      _abortV1Priming('no beforeImageUrl (source upload failed)');
      return;
    }
    debugPrint('[AutoGen] triggering Vision 1 auto-generation');
    _hasAutoGeneratedInitialVision = true;
    // Wave 4.8.5: the user's free-text architectural direction IS the V1
    // prompt → backend `prompt` → composer design-direction / refinement
    // authority (e.g. "turn the rear space into a bedroom"). It influences
    // generation honestly; falls back to the neutral first-vision prompt.
    _generate(
      overridePrompt: _pendingDescription ??
          'Generate the first architectural vision for this space.',
      trigger: 'auto',
    );
  }

  /// Generates a 32-char hex request ID for idempotency tracking.
  String _newRequestId() {
    final rand = Random.secure();
    return List.generate(16, (_) => rand.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  // Atmosphere switch INITIATED FROM a specific vision (reveal "Generate
  // <atmosphere>"). Re-binds the generation source + room to THAT vision before
  // generating, so a multi-upload session can't reuse an older vision's source
  // or room (fixes wrong-source + wrong-room atmosphere swaps). The reveal is
  // single-vision, so [vision] is exactly the render the user acted on.
  void _exploreDirectionFromVision(GeneratedResult vision, String style) {
    final target =
        resolveAtmosphereSwitchTarget(vision, fallbackRoom: _currentRoomType);
    // B1 — is the switched vision the LATEST imageResult? If so, keep today's
    // behavior (source_mode empty → Wave 5.21 cascade-free V1 anchor of the
    // CURRENT lineage). If it's an OLDER / cross-lineage vision (e.g. apartment
    // A after a re-upload of B), pin its EXACT version + restore its lineage
    // structural identity so the switch evolves from THAT vision's source +
    // identity instead of the re-uploaded lineage's (the cross-lineage leak).
    MessageModel? latest;
    for (final m in _messages.reversed) {
      if (m.type == MessageType.imageResult && m.result != null) {
        latest = m;
        break;
      }
    }
    final isLatest = latest?.result?.afterImageUrl == vision.afterImageUrl;
    setState(() {
      if (target.sourceUrl != null) _generationSourceUrl = target.sourceUrl;
      if (target.room != null) _currentRoomType = target.room!;
      _currentStyle = style;
      if (FeatureFlags.reuploadKeepLineage && !isLatest) {
        _branchSourceVersionId = _versionIdForUrl(vision.afterImageUrl);
        final token = _structuralTokenForUrl(vision.afterImageUrl);
        if (token != null && token.isNotEmpty) _structuralIdentity = token;
      }
    });
    _persistSession(); // Wave 4.10g — survive atmosphere swap
    _generate(overridePrompt: 'Redesign this space in the $style style.', trigger: 'switch');
  }

  // Wave 5.12 — type-discriminating reveal return contract. The reveal
  // can now pop with three distinct outcomes :
  //   GeneratedResult → "Continue this vision" : make THIS vision the
  //     active refinement baseline (even if older than the latest). The
  //     next refinement will evolve from this vision's afterUrl, not
  //     from the linear-latest. First emotional branching foundation —
  //     the backend still chains linearly (V4 follows V3 in iteration
  //     count) but the user-controlled refinement baseline is real.
  //   String         → "Explore another direction" (existing) : trigger
  //     a new generation in the selected atmosphere.
  //   null           → back navigation (existing) : no state change.
  // Wave 4.9.3 — resolve the DISPLAY label for the comparison SOURCE (left
  // side of the Full Reveal before/after) from the in-memory timeline, so the
  // reveal can show "Original | Warm Modern" / "Warm Modern | Japandi" instead
  // of generic "Before | AI Vision". Pure read of `_messages` + the session
  // upload — no persistence, recomputed each open (survives reload because the
  // timeline is rebuilt from the DB). Returns null when the source is unknown
  // (the screen then falls back to its default label).
  String? _sourceDisplayLabelFor(GeneratedResult vision) {
    final before = vision.beforeImageUrl;
    if (before.isEmpty) return null;
    // The immutable initial upload → "Original" (localized).
    final original = _project.beforeImageUrl;
    if (original != null && original.isNotEmpty && before == original) {
      return context.l10n.beforeLabel;
    }
    // Otherwise the source is a PREVIOUS vision in the timeline → its
    // atmosphere name (styleLabel minus the "· Vision N" suffix).
    for (final m in _messages) {
      final r = m.result;
      if (r != null && r.afterImageUrl.isNotEmpty && r.afterImageUrl == before) {
        final label = r.styleLabel.split('·').first.trim();
        return label.isNotEmpty ? label : null;
      }
    }
    return null;
  }

  Future<void> _openReveal(GeneratedResult result) async {
    // Enrich the nav payload with the source label (the model field is null
    // everywhere else; only the reveal needs it).
    final extra = GeneratedResult(
      beforeImageUrl: result.beforeImageUrl,
      afterImageUrl: result.afterImageUrl,
      styleLabel: result.styleLabel,
      projectId: result.projectId,
      roomType: result.roomType,
      sourceDisplayLabel: _sourceDisplayLabelFor(result),
    );
    final returned = await context.push<Object?>(
      '/result/${result.projectId}',
      extra: extra,
    );
    if (!mounted) return;
    if (returned is GeneratedResult) {
      await _continueFromVision(returned);
    } else if (returned is String) {
      // BUG FIX — bind the atmosphere switch to the vision that was opened
      // (`result`), not the stale session globals. The reveal is single-vision,
      // so `result` is exactly the render the user changed atmosphere on.
      _exploreDirectionFromVision(result, returned);
    }
    // else: null → back navigation, no change.
  }

  // Wave 5.12b — the sticky "active state" model is replaced by an
  // explicit branching narrative event in the conversation. When the
  // user taps "Continue this vision" on an older render :
  //   1. _generationSourceUrl is set to that vision's afterUrl (so the
  //      next refinement actually evolves from it — F5 source-sync)
  //   2. A branchEvent message is inserted into the chat AND persisted
  //      to Supabase, so the decision survives restart and reads as a
  //      first-class narrative beat in the timeline
  //   3. Future branching waves can derive a vision graph from the
  //      stored branchEvents without touching the backend schema —
  //      these events ARE the graph foundation.
  //
  // Wave 5.12b refinement (post-validation) — the branchEvent is ONLY
  // inserted when the user continues from an OLDER vision. If the
  // selected vision is the latest imageResult in the timeline, the
  // conversation is already naturally continuing from it ; inserting a
  // card would be redundant and would falsely suggest a branch where
  // none occurred. _generationSourceUrl is still updated in both cases
  // so the next refinement evolves from the selected source.
  // BUG A fix — look up the backend version_id for a given render URL inside
  // the round-tripped `_versions` ledger (JSON list of {version_id,
  // generated_image_url, ...}). Returns null if not found (older sessions).
  // Compare signed Supabase URLs by PATH only: the query string (token/expiry)
  // is re-issued and differs between when the evolution strip rendered a vision
  // and when the ledger entry was stored, so exact-string equality silently
  // failed → the pin fell back to LATEST → "continue from V1" landed on the
  // wrong lineage after a re-upload. The path identifies the storage object.
  static String _urlPath(String u) {
    final q = u.indexOf('?');
    return q >= 0 ? u.substring(0, q) : u;
  }

  String? _versionIdForUrl(String afterUrl) {
    if (_versions.isEmpty || afterUrl.isEmpty) return null;
    final wantPath = _urlPath(afterUrl);
    try {
      final list = jsonDecode(_versions);
      if (list is! List) return null;
      for (final v in list) {
        if (v is Map &&
            v['generated_image_url'] is String &&
            _urlPath(v['generated_image_url'] as String) == wantPath) {
          return v['version_id'] as String?;
        }
      }
    } catch (_) {/* malformed ledger → fall back to LATEST default */}
    return null;
  }

  // B1 — the structural-identity token a given render was generated WITH, looked
  // up in the round-tripped ledger (same path-match as _versionIdForUrl). Lets
  // continue-from-vision restore the CLICKED vision's lineage identity so the
  // pinned image and the structural identity stay in the same lineage (no
  // cross-lineage desync after a re-upload). Null if not found / no token.
  String? _structuralTokenForUrl(String afterUrl) {
    if (_versions.isEmpty || afterUrl.isEmpty) return null;
    final wantPath = _urlPath(afterUrl);
    try {
      final list = jsonDecode(_versions);
      if (list is! List) return null;
      for (final v in list) {
        if (v is Map &&
            v['generated_image_url'] is String &&
            _urlPath(v['generated_image_url'] as String) == wantPath) {
          final t = v['structural_identity_token'];
          return (t is String && t.isNotEmpty) ? t : null;
        }
      }
    } catch (_) {/* malformed ledger → no restore */}
    return null;
  }

  Future<void> _continueFromVision(GeneratedResult result) async {
    final afterUrl = result.afterImageUrl;
    if (afterUrl.isEmpty) return;

    // Determine whether the user selected the LATEST imageResult in the
    // chat timeline (natural continuation) or an OLDER one (real branch).
    MessageModel? latestImageResult;
    for (final m in _messages.reversed) {
      if (m.type == MessageType.imageResult && m.result != null) {
        latestImageResult = m;
        break;
      }
    }
    final isLatestVision =
        latestImageResult?.result?.afterImageUrl == afterUrl;

    // Wave 4.9.3 fix — suppress the branch card ONLY when the selection is
    // ALREADY the active source (truly redundant). The old rule suppressed it
    // whenever the LATEST vision was picked — but after the user had branched
    // to an older vision, returning to the latest IS a real change, and left
    // the stale older-branch card looking active (the reported bug). Now every
    // genuine source change drops a fresh card; the copy adapts (back-to-latest
    // vs earlier-direction). The source pin (below) was already correct in both
    // cases, so this is a visual-only fix. Compare by URL PATH (signed-token
    // query strings differ across reloads — same reason as _versionIdForUrl).
    final src = _generationSourceUrl;
    final alreadyActive =
        src != null && src.isNotEmpty && _urlPath(src) == _urlPath(afterUrl);

    final branchMessage = alreadyActive
        ? null
        : MessageModel(
            id: 'branch_${DateTime.now().millisecondsSinceEpoch}',
            content: isLatestVision
                ? "We're now evolving from your latest vision."
                : "We're now evolving from this earlier direction.",
            isAi: false,
            type: MessageType.branchEvent,
            result: GeneratedResult(
              beforeImageUrl: '',
              afterImageUrl: afterUrl,
              styleLabel: result.styleLabel,
              projectId: _project.id,
            ),
            createdAt: DateTime.now(),
          );

    setState(() {
      _generationSourceUrl = afterUrl;
      // P0 fix — continue the edit IN the clicked vision's atmosphere, not the
      // session's last/latest style. Editing V1 (Warm Modern) must stay Warm
      // Modern, never inherit the most recent switch (the reported "Vision 4 ·
      // Soft Luxury (FROM Vision 1)" bug). styleLabel is "<Atmosphere> · Vision N".
      final visionStyle = result.styleLabel.split('·').first.trim();
      if (visionStyle.isNotEmpty) _currentStyle = visionStyle;
      // BUG A fix — pin the chosen vision's version_id so the next /generate
      // sends source_mode=SPECIFIC_VERSION and the backend truly rebranches
      // (before_image_url alone is ignored by resolve_source). Null if the
      // url isn't in the ledger yet (pre-persistence sessions) → backend keeps
      // its LATEST default, i.e. the prior behaviour.
      _branchSourceVersionId = _versionIdForUrl(afterUrl);
      // B1 — restore the clicked vision's lineage structural identity so the
      // pinned image (its version) and the structural identity stay in the SAME
      // lineage. Prevents the cross-lineage desync after a re-upload (image=A
      // but identity=B → "different apartment"). No-op for a same-lineage
      // selection (token == current). Only meaningful with the ledger retained.
      if (FeatureFlags.reuploadKeepLineage) {
        final token = _structuralTokenForUrl(afterUrl);
        if (token != null && token.isNotEmpty) _structuralIdentity = token;
      }
      if (branchMessage != null) _messages.add(branchMessage);
    });
    _persistSession();

    if (branchMessage == null) return; // already-active selection : silent no-op

    _scrollToBottom();
    if (_project.id != 'new') {
      // #25 — persist within the schema's allowed values (role in user/ai,
      // message_type in text/image_result/system). A branch is encoded as a
      // 'system' message that CARRIES an after_image_url; _rowToMessage rebuilds
      // it as a branchEvent on reload (plain system messages have no after url).
      // await + log: the old fire-and-forget with role='system' /
      // message_type='branch_event' was SILENTLY REJECTED by the CHECK
      // constraints, so the card vanished on reload.
      try {
        await _svc.insertMessage(
          sessionId: _project.id,
          role: 'ai',
          content: branchMessage.content,
          messageType: 'system',
          afterImageUrl: afterUrl,
          styleLabel: result.styleLabel,
        );
      } catch (e) {
        debugPrint('[branch] persist failed: $e');
      }
    } else {
      _pendingMessages.add(branchMessage);
    }
  }

  // Wave 5.12b — F6 lineage cue. Walks the chat backward from a given
  // _listItems position : if the most recent event before this image is
  // a branchEvent (with no intervening imageResult), this vision was
  // directly branched from that earlier vision — return the source's
  // "Vision N" tag so the eyebrow can append "(FROM VISION N)".
  // Returns null for normal forward-chain refinements.
  String? _findBranchSourceVisionTag(int listItemIndex) {
    for (var i = listItemIndex - 1; i >= 0; i--) {
      final item = _listItems[i];
      if (item is! MessageModel) continue;
      if (item.type == MessageType.imageResult) return null;
      if (item.type == MessageType.branchEvent) {
        final label = item.result?.styleLabel ?? '';
        if (label.contains('·')) {
          final parts = label.split('·').map((s) => s.trim()).toList();
          if (parts.length == 2 && parts[1].isNotEmpty) return parts[1];
        }
        return label.isEmpty ? null : label;
      }
    }
    return null;
  }

  /// Fetches full message history from Supabase for an existing session.
  Future<void> _loadMessages({String trigger = 'unknown'}) async {
    debugPrint('[DB] _loadMessages() started — session_id: ${_project.id} '
        'trigger=$trigger');
    try {
      final rows = await _svc.fetchMessages(_project.id);
      debugPrint('[DB] _loadMessages() — got ${rows.length} rows');
      if (!mounted) return;
      // Phase A — a notification deep-link to a session that has no messages
      // means it was deleted between generation-complete and the tap. Bounce
      // cleanly to home rather than stranding the user on an empty chat.
      // (Scoped to fromNotification: a normally-opened empty session is left
      // alone — generated sessions always carry messages anyway.)
      if (rows.isEmpty) {
        if (widget.fromNotification) {
          context.go('/home');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.sessionUnavailable)),
          );
        }
        return;
      }
      final msgs = rows.map(_rowToMessage).toList();
      final imageCount = msgs.where((m) => m.type == MessageType.imageResult).length;

      // Wave 5.12b — walk the message stream backward and pick the FIRST
      // imageResult OR branchEvent as the refinement baseline. This
      // correctly handles the "user branched then closed the app before
      // refining" case : without this, the inferred source would always
      // be the linear-latest imageResult, silently undoing the user's
      // explicit branching decision on restore.
      String? lastGeneratedUrl;
      for (final m in msgs.reversed) {
        if (m.result == null) continue;
        if (m.type == MessageType.imageResult ||
            m.type == MessageType.branchEvent) {
          lastGeneratedUrl = m.result!.afterImageUrl;
          break;
        }
      }

      // Guard: the fetch above is async — if the widget was disposed during the
      // await (user navigated away while a reconciliation tick was in flight),
      // bail BEFORE touching ref (ref-after-dispose throws). The timer is also
      // cancelled in dispose, so this is belt-and-suspenders.
      if (!mounted) return;
      // #21b — a generation started on a now-disposed screen (user left the
      // chat mid-generation and came back) shows nothing here, because the DB
      // has no "loading" row. Detect the still-in-flight state from the
      // (app-alive) lifecycle provider and re-show the loading bubble so the
      // user sees the source + progress phrases again instead of a blank chat.
      final inFlightResume =
          ref.read(pendingGenerationsProvider)[_project.id] ==
              GenerationLifecycle.inFlight;

      setState(() {
        _messages = msgs;
        _iterationCount = imageCount;
        _hasGenerated = imageCount > 0;
        if (lastGeneratedUrl != null && lastGeneratedUrl.isNotEmpty) {
          _generationSourceUrl = lastGeneratedUrl;
        }
        if (inFlightResume) {
          _isGenerating = true;
          // Rebuilt in the SAME setState as the DB replace → no flicker. The
          // bubble renders the source via backdropUrl (beforeImageUrl) below.
          _messages.add(MessageModel(
            id: 'loading_resumed',
            content: '${imageCount + 1}|$_currentStyle',
            isAi: true,
            type: MessageType.loading,
            createdAt: DateTime.now(),
          ));
        }
      });
      // Reconcile from the DB until the result lands (the original await lives
      // in the disposed screen and won't update this instance). Idempotent —
      // the poll no-ops if one is already running. This is requirement (3):
      // opening a session that is still inFlight auto-starts reconciliation
      // with the correct baseline, so the orphaned result appears WITHOUT a
      // manual quit/reopen.
      if (inFlightResume) {
        debugPrint('[ChatLife] open inFlight session=${_project.id} '
            'trigger=$trigger → start reconcile');
        _startReconciliationPolling(sessionId: _project.id);
      }
      // #20 — keep session.latest_preview (the Projects card image) in sync
      // with the DB source of truth on every (re)load: reopen, reconciliation
      // poll AND foreground resume all flow through here. Guarded so we only
      // write when the URL actually changed (no redundant write, no rebuild
      // loop) — covers the case where the user left during generation and the
      // result was persisted server-side without the inline write-back.
      if (lastGeneratedUrl != null && lastGeneratedUrl.isNotEmpty) {
        final current = ref
            .read(sessionProvider)
            .where((p) => p.id == _project.id)
            .firstOrNull
            ?.afterImageUrl;
        if (current != lastGeneratedUrl) {
          ref
              .read(sessionProvider.notifier)
              .updateLatestPreview(_project.id, lastGeneratedUrl);
        }
      }
      // Wave 4.10g — capture the inferred state so a future restart skips
      // re-inferring from the message stream. Handles backfill for sessions
      // that pre-date the persistence layer.
      _persistSession();
      _scrollToBottom();
    } catch (e, st) {
      debugPrint('[DB] _loadMessages() ERROR: $e');
      debugPrint('[DB] _loadMessages() STACK: $st');
    }
  }

  MessageModel _rowToMessage(Map<String, dynamic> row) {
    final typeStr = (row['message_type'] as String?) ?? 'text';
    final isImageResult = typeStr == 'image_result';
    final afterUrl = (row['after_image_url'] as String?) ?? '';
    // Wave 5.12b — branchEvent rows carry the SOURCE vision's afterImageUrl +
    // styleLabel so the card can render the thumbnail + "Continuing from Vision
    // N" header. #25 — the schema's message_type CHECK only allows
    // text/image_result/system, so a branch is now persisted as a 'system'
    // message that CARRIES an after_image_url. Reconstruct it as a branchEvent
    // (plain system messages have none). Legacy 'branch_event' rows still honored.
    final isBranchEvent =
        typeStr == 'branch_event' || (typeStr == 'system' && afterUrl.isNotEmpty);
    final type = isImageResult
        ? MessageType.imageResult
        : isBranchEvent
            ? MessageType.branchEvent
            : typeStr == 'system'
                ? MessageType.system
                : MessageType.text;
    final result = (isImageResult || isBranchEvent)
        ? GeneratedResult(
            beforeImageUrl: (row['before_image_url'] as String?) ?? '',
            afterImageUrl: afterUrl,
            styleLabel: (row['style_label'] as String?) ?? '',
            projectId: _project.id,
          )
        : null;
    return MessageModel(
      id: row['id'] as String,
      content: row['content'] as String,
      isAi: (row['role'] as String) == 'ai',
      type: type,
      result: result,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  void _applyTitleEdit() {
    final trimmed = _titleEditController.text.trim();
    setState(() {
      if (trimmed.isNotEmpty) {
        _sessionTitle = trimmed;
        _titleManuallySet = true; // user's name wins — stop auto-naming
      }
      _isEditingTitle = false;
    });
    if (trimmed.isNotEmpty && _project.id != 'new') {
      ref.read(sessionProvider.notifier).updateTitle(_project.id, trimmed);
    }
  }

  // CHANTIER C — auto-name an un-renamed session from its room + latest
  // atmosphere ("Living Room — Warm Modern") so the Projects list is scannable
  // and premium instead of a wall of "New Design Session". Backs off the moment
  // the user renames manually.
  void _maybeAutoNameSession() {
    if (_titleManuallySet) return;
    final room = _currentRoomType.trim();
    final style = _currentStyle.split('·').first.trim(); // drop "· Vision N"
    if (room.isEmpty || style.isEmpty) return;
    final auto = '$room — $style';
    if (auto == _sessionTitle) return;
    setState(() => _sessionTitle = auto);
    if (_project.id != 'new') {
      ref.read(sessionProvider.notifier).updateTitle(_project.id, auto);
    }
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _busy || _isChatting) return;

    final userMsg = MessageModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: trimmed,
      isAi: false,
      createdAt: DateTime.now(),
    );
    final thinkingId = 'thinking_${DateTime.now().millisecondsSinceEpoch}';
    final thinkingMsg = MessageModel(
      id: thinkingId,
      content: '_thinking',
      isAi: true,
      type: MessageType.loading,
      createdAt: DateTime.now(),
    );

    setState(() {
      _messages.add(userMsg);
      _messages.add(thinkingMsg);
      _isChatting = true;
    });
    _inputController.clear();
    _scrollToBottom();

    if (_project.id != 'new') {
      _svc.insertMessage(sessionId: _project.id, role: 'user', content: trimmed);
    } else {
      _pendingMessages.add(userMsg);
    }

    final contextMessages = _messages.where((m) => m.type == MessageType.text).toList();
    final history = jsonEncode(
      contextMessages.map((m) => {'role': m.isAi ? 'ai' : 'user', 'content': m.content}).toList(),
    );

    try {
      final chatResult = await GenerationService().chat(
        sessionId: _project.id,
        message: trimmed,
        styleLabel: _currentStyle,
        roomType: _currentRoomType,
        iteration: _iterationCount + 1,
        history: history,
        uiLocale: ref.read(localeProvider).languageCode,
        // PR0 (Ayden Companion) — situational context from in-memory state.
        hasVision: _hasGenerated,
        generationInProgress: _busy,
        currentImageUrl: _generationSourceUrl ?? '',
        displayedVersionId: _branchSourceVersionId ?? '',
        originalImageUrl: _project.beforeImageUrl ?? '',
      );

      if (!mounted) return;

      final aiText = chatResult['ai_message'] as String;
      final shouldGenerate = chatResult['should_generate'] as bool? ?? false;
      final rawChips = chatResult['suggestions'] as List<dynamic>?;

      final aiMsg = MessageModel(
        id: 'chat_${DateTime.now().millisecondsSinceEpoch}',
        content: aiText,
        isAi: true,
        createdAt: DateTime.now(),
      );

      setState(() {
        _isChatting = false;
        _messages.removeWhere((m) => m.id == thinkingId);
        _messages.add(aiMsg);
        if (rawChips != null && rawChips.isNotEmpty) {
          _dynamicSuggestions = rawChips.cast<String>();
        }
      });
      _scrollToBottom();

      if (_project.id != 'new') {
        _svc.insertMessage(sessionId: _project.id, role: 'ai', content: aiText);
      } else {
        _pendingMessages.add(aiMsg);
      }

      if (shouldGenerate) {
        _generate(overridePrompt: trimmed, trigger: 'chat');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isChatting = false;
        _messages.removeWhere((m) => m.id == thinkingId);
      });
      if (_looksLikeDesignInstruction(trimmed)) {
        _generate(overridePrompt: trimmed, trigger: 'chat');
      } else {
        final errorMsg = MessageModel(
          id: 'chat_err_${DateTime.now().millisecondsSinceEpoch}',
          content: "I had trouble thinking through that, but you can still ask me for a design change.",
          isAi: true,
          createdAt: DateTime.now(),
        );
        setState(() => _messages.add(errorMsg));
        _scrollToBottom();
      }
    }
  }

  static bool _looksLikeDesignInstruction(String text) {
    final lower = text.toLowerCase().trimLeft();
    const verbs = [
      'add', 'change', 'make', 'replace', 'remove', 'redesign', 'create',
      'update', 'try', 'use', 'put', 'swap', 'move', 'show', 'give',
      'apply', 'modify', 'turn', 'render', 'generate', 'redo', 'adjust',
      // French
      'ajoute', 'fais', 'remplace', 'enlève', 'retire', 'crée',
      'montre', 'essaie', 'utilise', 'mets', 'pose',
    ];
    return verbs.any((v) => lower.startsWith(v));
  }

  Future<void> _generate({String? overridePrompt, String trigger = 'unknown'}) async {
    // ── Shared generation authorization guard (P0 duplicate-billing fix) ──────
    // EVERY entry point (auto / button / switch / chat / resume / any future)
    // routes through here. Reject (a) a concurrent fire and (b) an accidental
    // re-fire of an already-SUCCEEDED logical generation (session|source|
    // iteration|attempt). A re-upload or an intentional regenerate produces a
    // different key (new source, or _genAttempt++) → allowed. Failures never
    // mark a key succeeded → retry-after-failure stays possible.
    final int genIteration = _iterationCount + 1;
    final String genSource = _generationSourceUrl ?? _project.beforeImageUrl ?? '';
    // Deliberately NOT keyed on _project.id: it transitions 'new' → real Supabase
    // id during initial session creation, which would split ONE logical V1 into
    // two keys. _succeededGenKeys / _requestIdForKey are per-ChatScreen-instance
    // (already per-session), so source + iteration + attempt is a stable logical
    // identity across app restart / lifecycle / reconnect / foreground / rebuild —
    // the source URL is inherently stable for a given logical generation.
    final String genKey = '$genSource|$genIteration|$_genAttempt';
    final String srcHash =
        genSource.isEmpty ? 'none' : genSource.hashCode.toRadixString(16);
    if (_isGenerating) {
      debugPrint('[V1-GUARD] trigger=$trigger iteration=$genIteration '
          'source_hash=$srcHash decision=rejected reason=already_generating');
      return;
    }
    if (!_sourceReplaced && _succeededGenKeys.contains(genKey)) {
      debugPrint('[V1-GUARD] trigger=$trigger iteration=$genIteration '
          'source_hash=$srcHash decision=rejected reason=already_generated');
      return;
    }
    debugPrint('[V1-GUARD] trigger=$trigger iteration=$genIteration '
        'source_hash=$srcHash decision=accepted reason=new_generation');

    // Mid-session source change → re-upload + reset the chain BEFORE reading the
    // generation source, so this generation runs as a fresh FIRST_VISION on the
    // new photo (iteration == 1).
    if (_sourceReplaced) {
      // CHANTIER C — instant source preview. The loading bubble renders
      // _sourceImageFile from the LOCAL file, so showing it BEFORE the network
      // upload makes the user's new photo + the cinematic wait appear
      // immediately instead of after the Supabase round-trip (no perceived
      // freeze). The later loading-bubble add is guarded, so no duplicate.
      if (!_messages.any((m) => m.type == MessageType.loading)) {
        setState(() {
          _messages.add(MessageModel(
            id: 'loading_${DateTime.now().millisecondsSinceEpoch}',
            content: '1|$_currentStyle', // re-upload → fresh V1 (init phrases)
            isAi: true,
            type: MessageType.loading,
            createdAt: DateTime.now(),
          ));
        });
        _scrollToBottom();
      }
      final ok = await _applyReplacedSource();
      if (!ok) {
        if (!mounted) return;
        // Upload failed — drop the optimistic loading bubble we just showed.
        setState(() =>
            _messages.removeWhere((m) => m.type == MessageType.loading));
        if (overridePrompt == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.reuploadError),
              backgroundColor: AppColors.accentDark,
              behavior: SnackBarBehavior.floating,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
        return;
      }
    }
    if (!mounted) return;

    // originalUrl is the structural anchor only (keeps geometry stable on the
    // backend). It must NOT drive the reveal viewer.
    // generationSource is the EXACT image this step evolves from and is the
    // single source of truth for the before/after reveal pair:
    //   V1  -> _generationSourceUrl is null  -> generationSource == originalUrl
    //   V2+ -> _generationSourceUrl is set    -> generationSource == prev vision
    // This is branching-safe: restart/continue-from-version flows only need to
    // (re)assign _generationSourceUrl and the reveal follows automatically.
    final originalUrl = _project.beforeImageUrl;
    final generationSource = _generationSourceUrl ?? originalUrl;

    // Wave 5.12b — F5 diagnostic. Surfaces the exact source URL the
    // backend will receive as before_image_url, so any desync between
    // the user's branching intent and the real generation baseline
    // becomes visible in logs.
    debugPrint(
      '[Wave 5.12b] _generate '
      'using generationSource=$generationSource '
      '(_generationSourceUrl=$_generationSourceUrl, originalUrl=$originalUrl)',
    );

    if (generationSource == null || generationSource.isEmpty) {
      // Don't show snackbar for auto-generation (no user action triggered it).
      if (overridePrompt == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.chatPleaseUpload),
            backgroundColor: AppColors.accentDark,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
      return;
    }

    final newCount = _iterationCount + 1;
    final styleLabel = '$_currentStyle · Vision $newCount';

    // Collect recent text messages for conversational context.
    final contextMessages = _messages
        .where((m) => m.type == MessageType.text)
        .toList();
    final history = jsonEncode(
      contextMessages.map((m) => {'role': m.isAi ? 'ai' : 'user', 'content': m.content}).toList(),
    );

    // Wave 5.5.5 round-trip — for card-tap flows (overridePrompt provided by
    // _exploreDirection at V2+), the user intent text must persist in _messages
    // so FUTURE iterations find it during backend's backward atmosphere walk
    // (_previous_atmosphere_id_from_history). Critical constraints:
    //   1. Insert AFTER history is built so the CURRENT message doesn't appear
    //      in the history sent on this request (which would shadow the previous
    //      atmosphere and break switch detection — prev_id would equal current).
    //   2. Skip for V1 auto-gen (`_iterationCount == 0`). The V1 auto-gen prompt
    //      ("Generate the first architectural vision for this space." or any
    //      _pendingDescription) doesn't match any TransformationType regex →
    //      classifies as UNKNOWN → backend's `detect_history_customizations`
    //      treats UNKNOWN as customization (conservative policy) → at V2 the
    //      strategy becomes REBOOT_CUSTOMIZED instead of REBOOT_FRESH, keeping
    //      source_mode=LATEST and breaking the pure-switch contract.
    //      The V1 AI greeting "Your space is ready. Generating your first
    //      $style vision now." (line 173) already gives the backend regex
    //      _GREETING_ATMOS_RE everything it needs to identify V1's atmosphere.
    //   3. Skip when the typed-message flow (_send) already added a matching
    //      userMsg — `_send` inserts userMsg into _messages BEFORE calling
    //      `_generate`, so contextMessages already has it.
    // Wave 5.21e — track the user message we are about to insert so we can
    // clean it up if /generate fails with a structured backend error. Without
    // cleanup the orphan message persists into atmosphere history and the
    // next generation's _previous_atmosphere_id_from_history walk sees a
    // phantom switch (failed Japandi reported as prev even though Nature
    // was the last actually-rendered atmosphere). Tracking is per-call —
    // local variables only, no shared state.
    String? insertedUserMsgLocalId;
    Future<String?>? insertedUserMsgRowFuture;
    if (overridePrompt != null &&
        overridePrompt.isNotEmpty &&
        _iterationCount >= 1) {
      final lastTypedUser = contextMessages
          .where((m) => !m.isAi)
          .lastOrNull;
      if (lastTypedUser?.content != overridePrompt) {
        final userMsg = MessageModel(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          content: overridePrompt,
          isAi: false,
          createdAt: DateTime.now(),
        );
        insertedUserMsgLocalId = userMsg.id;
        setState(() {
          _messages.add(userMsg);
        });
        if (_project.id != 'new') {
          // Capture the Future so the catch block can await it (fire-and-
          // forget semantics preserved for the happy path).
          insertedUserMsgRowFuture = _svc.insertMessage(
            sessionId: _project.id,
            role: 'user',
            content: overridePrompt,
          );
        } else {
          _pendingMessages.add(userMsg);
        }
      }
    }

    setState(() {
      _isGenerating = true;
      _v1Priming = false; // generation now owns the loading state
      // Content encodes "<iteration>|<style>" so the loading bubble can pick
      // the right phrase set AND the subtle atmosphere-flavoured beat
      // (Wave 4.9.1b) without a separate state field. Parsed defensively.
      // Wave 6.15 — reuse the early V1 priming bubble if it's already shown
      // (don't stack a second loading bubble); otherwise add one (V2+ path).
      if (!_messages.any((m) => m.type == MessageType.loading)) {
        _messages.add(MessageModel(
          id: 'loading_${DateTime.now().millisecondsSinceEpoch}',
          content: '$newCount|$_currentStyle',
          isAi: true,
          type: MessageType.loading,
          createdAt: DateTime.now(),
        ));
      }
    });
    _scrollToBottom();

    final lastUserMsg = contextMessages.where((m) => !m.isAi).lastOrNull;
    final prompt = overridePrompt ?? lastUserMsg?.content ?? '';

    // Stable per-logical-generation id: the SAME logical key always maps to the
    // SAME request id, so an accidental re-fire that slips past the guard is
    // recognised by the backend idempotency replay-cache as the same request
    // (no second OpenAI billing). A fresh source / _genAttempt++ → fresh id.
    final clientRequestId =
        _requestIdForKey.putIfAbsent(genKey, () => _newRequestId());

    // 45s long-generation timer — injects a reassurance message without
    // disrupting the loading state. Cancelled on success or hard failure.
    _longGenerationTimer?.cancel();
    // Group 1 (addition #3) — the reassurance fires only after 60s (was 45s).
    _longGenerationTimer = Timer(
        Duration(seconds: FeatureFlags.genLifecycleV2 ? 60 : 45), () {
      if (!mounted || !_isGenerating) return;
      final reassurance = MessageModel(
        id: 'long_gen_${DateTime.now().millisecondsSinceEpoch}',
        content: context.l10n.genLongWait,
        isAi: true,
        createdAt: DateTime.now(),
      );
      setState(() => _messages.add(reassurance));
      _scrollToBottom();
      if (_project.id != 'new') {
        _svc.insertMessage(sessionId: _project.id, role: 'ai', content: reassurance.content);
        // Money-safety (2026-06-26) — a slow generation can have its long-lived
        // HTTP response silently dropped on mobile (no TCP error → Dio waits the
        // full receiveTimeout, ~10 min, showing an endless spinner) while the
        // backend has ALREADY finished and was billed. Start DB reconciliation
        // in PARALLEL now: the persisted result is adopted ~5s after it lands,
        // independent of the fragile HTTP response — so "stay on screen, never
        // see a result, give up and re-generate (double cost)" stops happening.
        // Reuses the hardened poll: idempotent (won't stack on an existing
        // poll), and _genSeq-deduped against the in-flight await, so whichever
        // delivers first wins with no duplicate vision. Slow (>60s) gens only.
        _startReconciliationPolling(sessionId: _project.id);
      }
    });

    // Wave 5.6c — capture the notifier reference BEFORE the await so that
    // even if the chat screen is disposed mid-generation we can still update
    // the global lifecycle state when the Future resolves. The notifier
    // itself is a long-lived ProviderScope singleton, so holding a reference
    // outlives the widget's dispose().
    final pendingNotifier = ref.read(pendingGenerationsProvider.notifier);
    // #20 — capture the session notifier BEFORE the await. After the widget is
    // disposed (user left during generation) `ref.read` is invalid, but this
    // StateNotifier is an app-scoped singleton, so the captured reference stays
    // usable to write the finished preview back even when !mounted.
    final sessionNotifier = ref.read(sessionProvider.notifier);
    final sessionIdForLifecycle = _project.id;

    // ── Wave 5.17b — Gen #2 sign-in gate REMOVED ──────────────────────────
    // Per the locked Option B funnel (2026-05-30) : Gen #1, #2, #3 are
    // ALL anonymous and free. Sign-in is offered only at the paywall
    // (Gen #4) and from the profile screen. The Wave 5.17a Gen #2 gate
    // is intentionally deleted here. Authentication continues to flow
    // through `AuthService` (still imported above for the paywall sign-in
    // flow + profile screen). Backend quota enforcement at /generate
    // returns HTTP 402 on Gen #4 attempts — caught below.

    pendingNotifier.markInFlight(sessionIdForLifecycle);
    // #21 — this generation's identity. Every completion path below bails if it
    // no longer matches (superseded by a foreground-resume reconciliation or a
    // user-restarted generation), so a late/duplicate await can't mutate state.
    final mySeq = ++_genSeq;

    try {
      // Wave 4.8.5: the AI-intent flags are only meaningful for the FIRST
      // vision (room inference / atmosphere selection happen once). Later
      // refinements steer normally, so they are not re-sent.
      final isFirstVision = newCount == 1;
      final result = await GenerationService().generate(
        sessionId: _project.id,
        prompt: prompt,
        beforeImageUrl: generationSource,      // editing chain for display/reveal
        styleLabel: styleLabel,
        roomType: _currentRoomType,
        // Wave 5.17d — canonical ids for the free-tier scope check.
        // Backend rejects non-premium calls when these don't map to
        // FREE_ROOMS / FREE_ATMOSPHERES (Living Room + Nordic/Soft Luxury).
        roomTypeId: RoomTypeImages.idForLabel(context.l10n, _currentRoomType) ?? '',
        atmosphereId: atmosphereIdFromLabel(styleLabel) ?? '',
        iteration: newCount,
        history: history,
        originalImageUrl: originalUrl ?? '',   // structural anchor — keeps geometry stable
        clientRequestId: clientRequestId,
        letAiDecide: _letAiDecide && isFirstVision,
        surpriseMe: _surpriseMe && isFirstVision,
        // Wave 4.7.2 / 4.7.3 — round-trip the persisted protocol fields so
        // structural_identity_clause and version ledger survive across V2+.
        structuralIdentity: _structuralIdentity,
        versions: _versions,
        // Wave 5.5.14c — per-generation bimodal intent. Default "preserve"
        // matches today's behaviour; backend no-ops unless BIMODAL_ENABLED=1.
        generationMode: _generationMode,
        // BUG A fix — when a branch pin is set ("Continue this vision"), tell
        // the backend to resolve the source from that exact version. Empty
        // otherwise → backend keeps its V2+ LATEST default (linear chain).
        sourceMode: _branchSourceVersionId != null ? 'SPECIFIC_VERSION' : '',
        sourceVersionId: _branchSourceVersionId ?? '',
        uiLocale: ref.read(localeProvider).languageCode,
        generationTrigger: trigger,
        generationAttempt: _genAttempt,
      );

      // Generation SUCCEEDED (await returned without throwing) → mark this
      // logical key done so an accidental re-fire of the SAME source+iteration
      // (e.g. auto-gen then Generate button) is rejected by the guard above.
      // Failures throw → this line is skipped → retry stays allowed.
      _succeededGenKeys.add(genKey);

      _longGenerationTimer?.cancel();
      _longGenerationTimer = null;
      if (!mounted) {
        // #20 — write the finished preview back even though the widget is gone,
        // so the Projects card reflects this vision WITHOUT needing a chat
        // reopen. Uses the pre-captured singleton notifier (ref is dead here).
        final afterUrl = result['after_image_url'] as String?;
        if (afterUrl != null && afterUrl.isNotEmpty) {
          sessionNotifier.updateLatestPreview(sessionIdForLifecycle, afterUrl);
        }
        // ledger_size=0 fix (2026-06-22) — a generation that completes while the
        // chat is unmounted (e.g. an auto-gen V1 finishing after the user moved
        // to the reveal) must STILL adopt + persist the protocol tokens. The
        // server is stateless and the DB doesn't store the ledger/identity, so
        // without this the version ledger AND structural_identity are lost → the
        // next generation sends an empty ledger (ledger_size=0) and no
        // architectural anchor. Safe off-screen: no setState/ref — direct field
        // writes + _persistSession() (which uses _persistence, not ref). The
        // snapshot is restored on the next open/reconcile, so the recovered
        // tokens reach the following /generate.
        final returnedVersions = result['versions'] as String?;
        final returnedIdentity = result['structural_identity'] as String?;
        final returnedRoom = (result['room_type'] as String?)?.trim() ?? '';
        if (returnedVersions != null && returnedVersions.isNotEmpty) {
          _versions = returnedVersions;
        }
        if (returnedIdentity != null && returnedIdentity.isNotEmpty) {
          _structuralIdentity = returnedIdentity;
        }
        if (returnedRoom.isNotEmpty && _currentRoomType.trim().isEmpty) {
          _currentRoomType = RoomTypeImages.enLabelForId(returnedRoom) ?? returnedRoom;
        }
        if (newCount > _iterationCount) {
          _iterationCount = newCount;
        }
        _persistSession();
        // Group 1 — suppress the "ready" badge/notification when the user is
        // currently viewing a (re-opened) instance of THIS session: its
        // reconciliation poll renders the result inline, so a cross-screen
        // snackbar/OS-notif would be wrong. Only notify when truly elsewhere.
        final viewingThisSession = FeatureFlags.genLifecycleV2 &&
            _activeSessionCtrl?.state == sessionIdForLifecycle;
        if (viewingThisSession) {
          pendingNotifier.clear(sessionIdForLifecycle);
        } else {
          // Wave 5.6c — user navigated away during the generation. Flag the
          // session as "result ready, not yet seen" so the home screen shows
          // a badge + snackbar via the pending generations provider.
          pendingNotifier.markReadyUnseen(sessionIdForLifecycle);
          // Phase A — fire an OS notification (no-op in foreground; the home
          // snackbar covers that). Deep-links back to this session on tap.
          LocalNotificationService.instance
              .notifyReady(sessionId: sessionIdForLifecycle);
        }
        return;
      }
      // #21 — superseded (a resume reconciliation already adopted the DB result,
      // or the user restarted): drop this completion so it can't append a
      // duplicate vision over the already-rebuilt timeline.
      if (mySeq != _genSeq) return;
      // Wave 5.6c — user is still on the chat screen at completion; clear
      // any pending state for this session (result will render inline).
      pendingNotifier.clear(sessionIdForLifecycle);

      // OS notification when the app is BACKGROUNDED but this chat is still
      // mounted (the user backgrounded the app mid-generation, so the completion
      // runs HERE — not in the !mounted/navigated-away branch). Without this the
      // "ready" OS notification never fired for the most common case: stay in the
      // chat, lock/leave the phone. No-op in the foreground via the service's own
      // resumed-guard (so the foreground-viewing case still shows nothing).
      if (FeatureFlags.genLifecycleV2 &&
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        pendingNotifier.markReadyUnseen(sessionIdForLifecycle);
        LocalNotificationService.instance
            .notifyReady(sessionId: sessionIdForLifecycle);
      }

      // A successful generation consumed quota — refresh the status snapshot so
      // the profile card's "free generations left" stays accurate.
      ref.read(meStatusProvider.notifier).refresh();

      final afterUrl = result['after_image_url'] as String;
      // Wave 5.13c perf #3 — fire-and-forget image precache. The
      // post-response ~6 s "blank shimmer" window was 100 % CDN download
      // + decode of the 1536×1024 result. Kicking precache off here, in
      // parallel with setState / persistSession / scroll, means the
      // bytes are already in the ImageCache when _GeneratedImageCard
      // mounts and asks for the same CachedNetworkImageProvider — the
      // card renders from cache on first frame instead of waiting on
      // the network. Logs let us measure the realized saving via the
      // existing [Wave 5.12d] "image card loaded in Xms" counter.
      if (afterUrl.isNotEmpty && mounted) {
        final preSw = Stopwatch()..start();
        debugPrint('[PerfPreload] precache start  url=${afterUrl.split('/').last.split('?').first}');
        precacheImage(CachedNetworkImageProvider(afterUrl), context).then((_) {
          debugPrint('[PerfPreload] precache done in ${preSw.elapsedMilliseconds}ms');
        }).catchError((e) {
          debugPrint('[PerfPreload] precache failed in ${preSw.elapsedMilliseconds}ms: $e');
        });
      }
      final aiText = result['ai_message'] as String;
      final rawChips = result['suggestions'] as List<dynamic>?;
      // Wave 4.7.2 / 4.7.3 — capture the backend's persisted protocol fields
      // for round-trip on the next /generate. Null-safe; preserve prior value
      // if backend omits / sends empty (older sessions, partial responses).
      final returnedIdentity = result['structural_identity'] as String?;
      final returnedVersions = result['versions'] as String?;
      // #8 — Ayden Decide exterior: the backend may have detected an exterior
      // room (e.g. "garden") and used its DNA. Fill our (empty) room so the
      // header shows it + the lineage continues with the right room. Only when
      // we had no room (delegated) → never overrides an explicit pick.
      final returnedRoom = (result['room_type'] as String?)?.trim() ?? '';

      setState(() {
        _isGenerating = false;
        _hasGenerated = true;
        _iterationCount = newCount;
        _generationSourceUrl = afterUrl;  // next refinement edits this output
        _branchSourceVersionId = null;    // BUG A fix — one-shot pin consumed
        if (returnedRoom.isNotEmpty && _currentRoomType.trim().isEmpty) {
          _currentRoomType = RoomTypeImages.enLabelForId(returnedRoom) ?? returnedRoom;
        }
        if (returnedIdentity != null && returnedIdentity.isNotEmpty) {
          _structuralIdentity = returnedIdentity;
        }
        if (returnedVersions != null && returnedVersions.isNotEmpty) {
          _versions = returnedVersions;
        }
        if (rawChips != null && rawChips.isNotEmpty) {
          _dynamicSuggestions = rawChips.cast<String>();
        }
        _messages.removeWhere((m) => m.type == MessageType.loading);
        _messages.add(MessageModel(
          id: 'result_${DateTime.now().millisecondsSinceEpoch}',
          content: aiText,
          isAi: true,
          type: MessageType.imageResult,
          result: GeneratedResult(
            // Reveal "before" = the exact source this step evolved from
            // (V1: original upload; V2+: previous vision). generationSource is
            // guaranteed non-empty by the guard above, so the slider can never
            // silently vanish for a vision that was actually generated.
            beforeImageUrl: generationSource,
            afterImageUrl: afterUrl,
            styleLabel: styleLabel,
            projectId: _project.id,
            // Bind the room to this vision so a later atmosphere switch on it
            // restores ITS room, not a stale session global (cross-vision leak).
            roomType: _currentRoomType,
          ),
          createdAt: DateTime.now(),
        ));
      });
      // Wave 4.10g — protocol tokens were just refreshed by the /generate
      // response. Persist NOW so the next app restart skips re-capture and
      // the V2+ lineage stays intact.
      _maybeAutoNameSession(); // CHANTIER C — name the session from room + atmo
      _persistSession();
      _scrollToBottom();

      // Reveal-chain observability: which images form this step's pair and
      // why (V1 evolves the original upload; V2+ evolves the previous vision).
      final revealMode =
          (generationSource == originalUrl) ? 'original' : 'previous_version';
      debugPrint('[Reveal] v$newCount pair — '
          'before_source=$revealMode '
          'reveal_before=$generationSource '
          'reveal_after=$afterUrl');

      if (_project.id != 'new') {
        // Wave 5.6 — backend now writes the AI image_result message to
        // Supabase before returning the HTTP response. Frontend only
        // inserts as a FALLBACK when the backend write failed (server-side
        // Supabase write error). The message_persisted flag in the
        // response tells us which path to take.
        final backendPersisted =
            (result['message_persisted'] as bool?) ?? false;
        if (!backendPersisted) {
          debugPrint('[Wave 5.6] backend message write failed — frontend fallback inserting');
          _svc.insertMessage(
            sessionId: _project.id,
            role: 'ai',
            content: aiText,
            messageType: 'image_result',
            beforeImageUrl: generationSource,
            afterImageUrl: afterUrl,
            styleLabel: styleLabel,
          );
        }
        ref.read(sessionProvider.notifier).updateLatestPreview(_project.id, afterUrl);
      }
    } on GenerationException catch (e) {
      // Backend exhausted all retries and returned a structured failure.
      // Only now do we surface the failure to the user.
      _longGenerationTimer?.cancel();
      _longGenerationTimer = null;

      // ── Wave 5.21e — Failed-generation history cleanup ────────────────
      // The user message we inserted before calling /generate must NOT
      // survive a structured backend failure. Otherwise the next
      // generation's _previous_atmosphere_id_from_history walk picks up
      // this orphan as the most-recent atmosphere transition — exactly
      // the Session-2 bug where a failed Japandi tap shadowed the
      // successful Nature retreat that followed. Cleanup runs on BOTH
      // GenerationException paths (paywall + regular failure), but NOT
      // on the transport-error catch below — there the backend may
      // still succeed (Wave 5.6 server-side persistence polling).
      if (insertedUserMsgLocalId != null) {
        setState(() {
          _messages.removeWhere((m) => m.id == insertedUserMsgLocalId);
        });
        if (insertedUserMsgRowFuture != null) {
          final rowId = await insertedUserMsgRowFuture;
          if (rowId != null) {
            await _svc.deleteMessage(rowId);
          }
        }
      }

      if (!mounted) {
        // Wave 5.6c — failure arrived after user navigated away.
        // Mark the session as "error, not yet seen" so home shows a badge.
        pendingNotifier.markErrorUnseen(sessionIdForLifecycle);
        // Phase A — OS notification for the failure (background only).
        LocalNotificationService.instance
            .notifyFailed(sessionId: sessionIdForLifecycle);
        return;
      }
      // #21 — superseded (resume reconciliation found the real result, or the
      // user restarted): don't surface this stale failure over a fresh timeline.
      if (mySeq != _genSeq) return;
      // Wave 5.6c — failure shown inline; clear pending state.
      pendingNotifier.clear(sessionIdForLifecycle);

      // ── Wave 5.17b/d — Paywall branch (HTTP 402) ───────────────────
      // Two distinct triggers map to the same paywall sheet, different
      // subhead copy :
      //   QUOTA_EXHAUSTED      → "Your free explorations are complete."
      //   FREE_TIER_RESTRICTED → "Premium unlocks every room/atmosphere."
      // The failure message is NOT persisted to messages — this is a
      // product gate, not an architect failure.
      if (e.quotaExhausted || e.freeTierRestricted) {
        setState(() {
          _isGenerating = false;
          _messages.removeWhere((m) => m.type == MessageType.loading);
        });
        // Quota state just changed — refresh the status snapshot (profile card).
        ref.read(meStatusProvider.notifier).refresh();
        await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => PaywallSheet(
            trigger: e.freeTierRestricted
                ? PaywallTrigger.freeTier
                : PaywallTrigger.quota,
            restrictedField: e.restrictedField,
          ),
        );
        return;
      }

      final failureMessage = e.userMessage;
      final errMsg = MessageModel(
        id: 'gen_err_${DateTime.now().millisecondsSinceEpoch}',
        content: failureMessage,
        isAi: true,
        createdAt: DateTime.now(),
      );
      setState(() {
        _isGenerating = false;
        _messages.removeWhere((m) => m.type == MessageType.loading);
        _messages.add(errMsg);
      });
      _scrollToBottom();

      if (_project.id != 'new') {
        // Wave 5.6b — backend now writes failure messages to Supabase
        // via the GenerationError handler (so disconnect-tolerant users
        // see the failure on reopen). Frontend only inserts as fallback
        // when the backend write failed.
        if (!e.messagePersisted) {
          debugPrint('[Wave 5.6b] backend failure-message write failed — frontend fallback inserting');
          _svc.insertMessage(sessionId: _project.id, role: 'ai', content: failureMessage);
        }
      }
    } catch (e) {
      // Transport error (timeout, network drop, etc.) — backend may still be
      // working. Keep loading state and poll for the result every 5s for 90s.
      _longGenerationTimer?.cancel();
      _longGenerationTimer = null;
      if (!mounted) {
        // Wave 5.6c — transport error after user left. Backend may still
        // complete (Wave 5.6 server-side persistence catches this), so we
        // optimistically flag readyUnseen — _loadMessages on reopen will
        // hydrate the actual result if it appeared. If the backend truly
        // failed too, the Wave 5.6b failure-message-persist will mean the
        // user still sees feedback (an error message instead of an image)
        // — either way, the session deserves a badge for re-attention.
        // Group 1 — but NOT when the user is viewing a re-opened instance of
        // this session: its in-flight reconciliation poll hydrates the result,
        // so no cross-screen "ready" notify.
        final viewingThisSession = FeatureFlags.genLifecycleV2 &&
            _activeSessionCtrl?.state == sessionIdForLifecycle;
        if (!viewingThisSession) {
          pendingNotifier.markReadyUnseen(sessionIdForLifecycle);
          // Phase A — optimistic "ready" OS notification (background only); the
          // tap re-opens the session where _loadMessages hydrates the result.
          LocalNotificationService.instance
              .notifyReady(sessionId: sessionIdForLifecycle);
        }
        return;
      }
      // #21 — superseded by a resume reconciliation / restart: stop here.
      if (mySeq != _genSeq) return;

      if (_project.id == 'new') {
        // No session to reconcile against — surface gracefully.
        setState(() {
          _isGenerating = false;
          _messages.removeWhere((m) => m.type == MessageType.loading);
          _messages.add(MessageModel(
            id: 'gen_err_${DateTime.now().millisecondsSinceEpoch}',
            content: context.l10n.genTransportInterrupted,
            isAi: true,
            createdAt: DateTime.now(),
          ));
        });
        _scrollToBottom();
        return;
      }

      // Poll for the result — backend may have succeeded after Dio gave up.
      _startReconciliationPolling(sessionId: _project.id);
    }
  }

  /// Polls `_loadMessages()` every 5s for up to 90s (18 attempts) until an
  /// image_result appears in the DB (the source of truth), then clears the
  /// spinner. Used by BOTH the transport-error fallback and the #21
  /// foreground-resume reconciliation.
  ///
  /// #21 — hardened: the timer is stored (cancelled on dispose, never stacked),
  /// and the "abandon" condition is keyed on `_genSeq` instead of the old
  /// `_isGenerating` check. The old check was dead-on-arrival: the transport
  /// path leaves `_isGenerating == true`, so the first tick bailed immediately
  /// and the poll never ran — a direct cause of the stuck spinner.
  void _startReconciliationPolling({required String sessionId}) {
    if (_reconcileTimer != null) return; // already polling — never stack
    const pollInterval = Duration(seconds: 5);
    const maxAttempts = 36; // 36 × 5s = 180s (matches the Dio gen timeout)
    final startSeq = _genSeq;
    int attempt = 0;

    // ── Disappearing-image fix — BASELINE ────────────────────────────────────
    // The old success test was `hasResult = any imageResult`. On V2/V3/V4 a
    // PRIOR vision is already an imageResult, so the very first poll tick
    // declared the in-flight generation "done", stopped the poll, dropped the
    // spinner and never rendered the real result (it landed in the orphaned
    // !mounted branch → DB only → "image disappears until reopen").
    //
    // Capture how many imageResults exist BEFORE the tracked generation lands.
    // In every reconcile entry point (transport-error fallback, inFlightResume
    // recovery, foreground resume) the new result is NOT yet in `_messages`, so
    // the current count IS the correct baseline. The poll then waits for a
    // count STRICTLY GREATER than this — a genuinely NEW vision.
    final baselineImageCount =
        _messages.where((m) => m.type == MessageType.imageResult).length;
    debugPrint('[Reconcile] start session=$sessionId '
        'baselineImageCount=$baselineImageCount startSeq=$startSeq');

    void stop(Timer t) {
      t.cancel();
      _reconcileTimer = null;
    }

    _reconcileTimer = Timer.periodic(pollInterval, (timer) async {
      attempt++;
      // Abandon if the screen is gone, the session changed, or a NEWER
      // generation superseded this one (user restarted).
      if (!mounted || _project.id != sessionId || _genSeq != startSeq) {
        stop(timer);
        return;
      }

      await _loadMessages(trigger: 'poll');
      if (!mounted || _genSeq != startSeq) {
        stop(timer);
        return;
      }

      // A NEW vision landed in the DB (count grew beyond the baseline) → adopt
      // it as truth, clear the spinner, and bump _genSeq so any still-in-flight
      // original await bails instead of appending a duplicate vision.
      // NEVER clear the spinner on a stale "any imageResult" — only on a real
      // increase, so the in-flight generation can't be declared done early.
      final currentImageCount =
          _messages.where((m) => m.type == MessageType.imageResult).length;
      final hasNewResult = currentImageCount > baselineImageCount;
      if (hasNewResult) {
        debugPrint('[Reconcile] NEW result session=$sessionId '
            'count=$currentImageCount > baseline=$baselineImageCount '
            'attempt=$attempt');
        stop(timer);
        _genSeq++;
        _longGenerationTimer?.cancel();
        _longGenerationTimer = null;
        // Result shown → drop the (possibly re-injected) loading bubble and
        // clear the lifecycle flag so it never re-injects or badges again.
        ref.read(pendingGenerationsProvider.notifier).clear(sessionId);
        setState(() {
          _isGenerating = false;
          _messages.removeWhere((m) => m.type == MessageType.loading);
        });
        return;
      }

      if (attempt >= maxAttempts) {
        stop(timer);
        _genSeq++;
        if (!mounted) return;
        // Give up → clear the lifecycle flag so the spinner can't re-inject.
        ref.read(pendingGenerationsProvider.notifier).clear(sessionId);
        final failMsg = context.l10n.genTookLonger;
        setState(() {
          _isGenerating = false;
          _messages.removeWhere((m) => m.type == MessageType.loading);
          _messages.add(MessageModel(
            id: 'gen_err_${DateTime.now().millisecondsSinceEpoch}',
            content: failMsg,
            isAi: true,
            createdAt: DateTime.now(),
          ));
        });
        _scrollToBottom();
        _svc.insertMessage(sessionId: sessionId, role: 'ai', content: failMsg);
      }
    });
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
        // Wave 4.6: the latest generated vision powers the "evolving this
        // vision" continuity header. Null (no vision yet) gracefully falls
        // back to the source photo. Read-only — no contract change.
        currentVisionUrl: _generationSourceUrl,
        // Wave 4.7: the session's prior visions, surfaced (read-only) from
        // the chat thread as the de-facto evolution history.
        visions: [
          for (final m in _messages)
            if (m.type == MessageType.imageResult && m.result != null)
              _VisionRef(
                afterUrl: m.result!.afterImageUrl,
                label: m.result!.styleLabel,
              ),
        ],
        // Wave 4.7: "continue from this vision" — lightweight in-session
        // re-source. Reassigns the 4.8.3 branch-safe _generationSourceUrl so
        // the NEXT existing generation flows from the chosen vision. No
        // pipeline / model / routing change; chat stays chronological.
        onContinueFromVision: (v) {
          Navigator.of(context).pop();
          setState(() {
            _generationSourceUrl = v.afterUrl;
            // B1 — same fix as _continueFromVision (the full-reveal pencil): pin
            // the chosen vision's exact version + restore its lineage structural
            // identity so the next edit (e.g. "add a TV") evolves from THIS
            // vision's source+identity, not the re-uploaded lineage's.
            if (FeatureFlags.reuploadKeepLineage) {
              _branchSourceVersionId = _versionIdForUrl(v.afterUrl);
              final token = _structuralTokenForUrl(v.afterUrl);
              if (token != null && token.isNotEmpty) _structuralIdentity = token;
            }
            _messages.add(MessageModel(
              id: 'sys_${DateTime.now().millisecondsSinceEpoch}',
              content: context.l10n.continuingFromVision,
              isAi: false,
              type: MessageType.system,
              createdAt: DateTime.now(),
            ));
          });
          // Wave 4.10g — branch source change must survive restart so the
          // next session reopen continues from the chosen vision.
          _persistSession();
          _scrollToBottom();
        },
        initialRoomType: _currentRoomType,
        initialStyle: _currentStyle,
        onReplace: _replaceSourcePhoto,
        onDirectionChanged: (roomType, style, aiDecide, surprise) {
          // CHANTIER A — Room lock. The room is settable ONLY before the first
          // vision exists; once the lineage has any generated vision the room is
          // IMMUTABLE (the Living Room → Home Office bug). Style stays freely
          // changeable.
          // #8b — EXCEPTION: a pending re-upload (_sourceReplaced) starts a fresh
          // V1 lineage (a NEW apartment), so the room — or Ayden Decide — may
          // legitimately change. Scoped to the re-upload case so the mid-lineage
          // lock still holds for a plain direction change.
          final hasVision = sessionHasVision(_messages);
          final canSetRoom = !hasVision || _sourceReplaced;
          setState(() {
            if (canSetRoom) {
              if (aiDecide) {
                // Delegate the room to the AI on the next (fresh) V1. Honored by
                // _generate via `_letAiDecide && isFirstVision` (re-upload resets
                // the iteration → isFirstVision true).
                _letAiDecide = true;
              } else {
                _letAiDecide = false;
                _currentRoomType = roomType;
              }
              // #2 — surprise = Ayden Signature (delegate the atmosphere). Only on
              // a fresh V1 / re-upload; honored by _generate via
              // `_surpriseMe && isFirstVision`.
              _surpriseMe = surprise;
              _currentStyle = surprise ? "AI's choice" : style;
            } else {
              // Mid-lineage: room + delegation locked; the atmosphere itself
              // stays freely changeable (explicit pick only, no surprise).
              _surpriseMe = false;
              _currentStyle = style;
            }
          });
          // Wave 4.10g — room/atmosphere selection survives restart.
          _persistSession();
          // AYDEN option B — "Generate Design" triggers a real generation
          // through the normal /generate path (quota consumed for free users,
          // exactly like any generation). Flag-gated with the new card system.
          if (FeatureFlags.newDesignCards) {
            _generate(trigger: 'button');
          }
        },
        // Wave 5.16b — initialMode + onModeChanged callsite dropped with
        // the sheet's MODE toggle. _generationMode still wired to the
        // backend on the next /generate call, just no longer mutated
        // from this surface.
      ),
    );
  }

  // Replace the source photo WITHOUT closing the sheet (the sheet stays open
  // so the user can still pick room + atmosphere). Returns the new file so the
  // sheet can update its own preview; the sheet only closes on quit or on
  // "Generate Design".
  Future<File?> _replaceSourcePhoto() async {
    // CHANTIER C #1 — same premium picker as New Design (Camera / Gallery /
    // Examples) via the SHARED ImagePickerSheet. Returns the picked file so the
    // Design Direction sheet refreshes its preview.
    final file = await showModalBottomSheet<File?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => ImagePickerSheet(
        onCamera: () async {
          final f = await _pickReplacementFile(ImageSource.camera);
          if (sheetCtx.mounted) Navigator.pop(sheetCtx, f);
        },
        onGallery: () async {
          final f = await _pickReplacementFile(ImageSource.gallery);
          if (sheetCtx.mounted) Navigator.pop(sheetCtx, f);
        },
        onExample: (asset) async {
          final f = await _exampleToFile(asset);
          if (sheetCtx.mounted) Navigator.pop(sheetCtx, f);
        },
      ),
    );
    if (file == null || !mounted) return null;
    setState(() {
      _sourceImageFile = file;
      _sourceReplaced = true; // next generation = fresh V1 from this photo
    });
    return file;
  }

  Future<File?> _pickReplacementFile(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    return picked == null ? null : File(picked.path);
  }

  // Example photo (bundled asset) → temp file, exactly like a Camera/Gallery
  // pick, so the re-upload flow stays identical downstream.
  Future<File?> _exampleToFile(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      final file = File(
        '${Directory.systemTemp.path}/ayden_example_'
        '${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      return file;
    } catch (e) {
      debugPrint('[Chat] example photo load failed: $e');
      return null;
    }
  }

  // Mid-session source change → re-upload the new photo, make it the new
  // structural anchor, and reset the vision chain so the NEXT generation is a
  // FIRST_VISION (iteration == 1). Old visions stay in the chat history. A
  // system message marks the new lineage. Returns false on upload failure.
  Future<bool> _applyReplacedSource() async {
    final file = _sourceImageFile;
    if (file == null) return false;
    try {
      // Wave 6.15 — compress the replaced source too (same as V1 upload).
      final compressed = await _compressSource(file.path);
      final bytes = compressed ?? await file.readAsBytes();
      final filename = 'source_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final newUrl = await _svc.uploadSourceImage(
        sessionId: _project.id,
        filename: filename,
        bytes: bytes,
      );
      await _svc.updateBeforeImageUrl(_project.id, newUrl);
      ref
          .read(sessionProvider.notifier)
          .updateBeforeImageUrl(_project.id, newUrl);
      if (!mounted) return false;
      setState(() {
        _project = _project.copyWith(beforeImageUrl: newUrl);
        _generationSourceUrl = null; // new root → generationSource == new anchor
        _iterationCount = 0; // → iteration == 1 → FIRST_VISION
        // New photo = new architecture → drop the old structural identity so the
        // re-upload's V1 (iteration==1, empty identity) re-analyses THIS photo.
        // Without this the backend reuses the original upload's identity and the
        // model destroys the new room's real openings (door/AC) on atmosphere
        // switches (where input_fidelity=low lets the identity text dominate).
        _structuralIdentity = '';
        // Option A (2026-06-16) — re-upload = clean NEW lineage. Purge the
        // version ledger + any branch pin. Without this, the old apartment's
        // visions stay clickable in chat history and `_versionIdForUrl` matched
        // an old-lineage URL by path → pinned the WRONG apartment's V1 image
        // (source_mode=SPECIFIC_VERSION) while structural_identity followed the
        // new root → image/identity desync → "completely different apartment"
        // on continue-from-vision. The ledger repopulates from this lineage's
        // first generation; a click on an old vision now resolves to the current
        // lineage (LATEST) instead of a stale cross-lineage pin.
        // B1 (2026-06-19) — when reuploadKeepLineage is ON we KEEP the ledger so
        // the prior lineage's versions stay resolvable; continue-from-vision now
        // pins the clicked version AND restores its lineage identity (no desync),
        // the proper fix this purge was a workaround for.
        if (!FeatureFlags.reuploadKeepLineage) {
          _versions = '';
        }
        _branchSourceVersionId = null;
        _sourceReplaced = false;
        _messages.add(MessageModel(
          id: 'sys_${DateTime.now().millisecondsSinceEpoch}',
          content: context.l10n.chatNewSourceMsg,
          isAi: false,
          type: MessageType.system,
          createdAt: DateTime.now(),
        ));
      });
      _persistSession();
      return true;
    } catch (e) {
      debugPrint('[NewSource] re-upload failed: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    // #8 — Ayden Decide header label. When the room was AI-delegated: show the
    // DETECTED room if we have one (e.g. an exterior "Garden" routed by
    // AYDEN_DECIDE_EXTERIOR), otherwise "Ayden Decide". Normal sessions
    // (explicit room) are unchanged → no prefix.
    final aiDecidePrefix = _letAiDecide
        ? (_currentRoomType.trim().isNotEmpty
            ? '${_currentRoomType.trim()} · '
            : '${l10n.uplAiDecide} · ')
        : '';
    final headerSubtitle = _iterationCount > 0
        ? '$aiDecidePrefix${_brandSignature(_currentStyle)} · ${l10n.visionCount(_iterationCount)}'
        : '$aiDecidePrefix${_brandSignature(_currentStyle)} · ${l10n.readyToCreate}';

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
                  // Seed the editor with the branded label the user sees (so they
                  // don't edit the raw "AI's choice" sentinel). Display-only.
                  _titleEditController.text = _brandSignature(_sessionTitle);
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
                            _brandSignature(_sessionTitle),
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
                      // Polish: match the title's overflow handling so a long
                      // "<style> · Vision N" ellipsizes cleanly instead of
                      // hard-clipping mid-glyph in the constrained AppBar.
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
            child: _busy
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
                    MessageType.loading => msg.content == '_thinking'
                        ? _ThinkingBubble(key: ValueKey(msg.id))
                        // Generation loading content is "<iteration>|<style>"
                        // (Wave 4.9.1b). Parsed defensively: a bare "<n>" or
                        // any malformed value still yields a valid bubble.
                        : _LoadingBubble(
                            key: ValueKey(msg.id),
                            iteration: int.tryParse(
                                    msg.content.split('|').first) ??
                                1,
                            atmosphere: msg.content.contains('|')
                                ? msg.content.split('|').last
                                : '',
                            // Wave 4.9: the image being transformed powers the
                            // cinematic wait (V2+ = latest vision, V1 = source
                            // photo). Read-only context; the 4.9.1b "<n>|<style>"
                            // content encoding is unchanged.
                            // B1 — the waiting backdrop must show the ACTUAL
                            // source being edited. The local file (_sourceImageFile)
                            // is the last upload (e.g. re-uploaded apartment B) and
                            // takes precedence in _backdrop(), so it wrongly showed
                            // B while continuing/switching from an older vision A.
                            // Only use the local file for V1 (no explicit source);
                            // for V2+/continue/switch fall back to backdropUrl
                            // (= _generationSourceUrl = the viewed vision).
                            sourceFile: (FeatureFlags.reuploadKeepLineage &&
                                    _generationSourceUrl != null)
                                ? null
                                : _sourceImageFile,
                            backdropUrl: _generationSourceUrl ??
                                _project.beforeImageUrl,
                            // Group 1 — real generation start (from the app-scoped
                            // provider) so the progress bar resumes instead of
                            // restarting from 0 after leaving/returning.
                            startedAt: FeatureFlags.genLifecycleV2
                                ? ref
                                    .read(pendingGenerationsProvider.notifier)
                                    .startedAt(_project.id)
                                : null,
                          ),
                    MessageType.branchEvent => _BranchEventCard(
                        key: ValueKey(msg.id),
                        message: msg,
                      ),
                    MessageType.imageResult => _ImageResultBubble(
                        key: ValueKey(msg.id),
                        message: msg,
                        index: index,
                        // Wave 5.12b — F6 lineage cue. Non-null when this
                        // vision was directly branched from an earlier
                        // vision via a branchEvent immediately preceding
                        // it (no intervening imageResult). Renders as
                        // "(FROM VISION N)" appended to the eyebrow.
                        sourceVisionTag: _findBranchSourceVisionTag(index),
                        onRevealTap: () => _openReveal(msg.result!),
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
              enabled: !_busy && !_isChatting,
            ),
            // Wave 5.12b — the sticky "CONTINUING • VISION X" context
            // line shipped in Wave 5.12 was removed : it competed with
            // the natural narrative model (users perceive the active
            // direction as the latest visible step in the conversation
            // story, not as a global persistent state). The branching
            // event card now lives INSIDE the timeline at the moment
            // the decision happened — see _BranchEventCard.
            ChatInputBar(
              controller: _inputController,
              onSend: _send,
              enabled: !_busy && !_isChatting,
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
    // Wave 5.11 — drop the flanking dividers. Centered text alone is a
    // calmer chronology cue ; the divider lines were the strongest
    // "chat-app block" rhythm in the stream.
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
      child: Center(
        child: Text(
          _label(context).toUpperCase(),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
        ),
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

class _TextBubbleState extends State<_TextBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    // Wave 5.11 — fade only. The horizontal slide + 30ms-per-index
    // stagger felt mechanical on long conversations ; a calm fade
    // reads as architectural narrative entering, not a messenger
    // bubble landing. The render-result bubble keeps its full
    // scale+slide+fade entry (emotional climax, separate widget).
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
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
      child: isAi ? _buildAiEditorial(context) : _buildUserBubble(context),
    );
  }

  // Wave 5.11 — AI prose becomes editorial architectural guidance, not a
  // messenger bubble. No avatar, no border, no fill, no asymmetric tail.
  // Wider reading column (85% of screen, vs 72% when constrained by the
  // old avatar + bubble), softer color (textSecondary), 1.55 line-height
  // for editorial breathing. Reads as a quiet caption around the render.
  Widget _buildAiEditorial(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        margin: const EdgeInsets.fromLTRB(2, 2, 0, 12),
        padding: EdgeInsets.zero,
        child: Text(
          widget.message.content,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                height: 1.55,
                fontSize: 14.5,
              ),
        ),
      ),
    );
  }

  // The user's voice keeps its weight — right-aligned dark bubble with
  // the asymmetric bottom-right tail. The user's intent is the anchor of
  // the conversation ; the AI prose softens around it.
  Widget _buildUserBubble(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: const BoxDecoration(
          color: AppColors.textPrimary,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(
          widget.message.content,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.surface,
                height: 1.6,
              ),
        ),
      ),
    );
  }
}

// ── Loading bubble ────────────────────────────────────────────────────────────

// Wave 4.9.1b — Perceived-latency UX. The ordered loading narrative (initial +
// refinement phrases + the slot-3 atmosphere-flavoured beat) now lives in l10n
// (AppLocalizations.genInitPhrases / genRefinePhrases / genFlavor) so it
// localizes; the scheduler below consumes the localized sequence.

class _LoadingBubble extends StatefulWidget {
  final int iteration;
  final String atmosphere;
  // Wave 4.9: the image being transformed (cinematic wait presence).
  final File? sourceFile;
  final String? backdropUrl;
  // Group 1 — when the underlying generation started (app-scoped, survives a
  // widget recreate). Lets the progress bar RESUME at the real elapsed fraction
  // instead of restarting from 0 each time the bubble is (re)built. Null → 0.
  final DateTime? startedAt;
  const _LoadingBubble({
    super.key,
    this.iteration = 1,
    this.atmosphere = '',
    this.sourceFile,
    this.backdropUrl,
    this.startedAt,
  });

  @override
  State<_LoadingBubble> createState() => _LoadingBubbleState();
}

class _LoadingBubbleState extends State<_LoadingBubble> with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;
  // Long asymptotic progress: eases toward (not to) ~0.96 over ~80s and never
  // completes — completion only "happens" when the real result replaces this
  // bubble. It therefore never hard-stalls at a fixed value (Wave 4.9.1b /
  // 4.9.1a Task 6: no frozen "did it crash?" feeling).
  late final AnimationController _progressCtrl;
  late final Animation<double> _progress;
  // Subtle continuous breathing on the progress fill so the bar reads as
  // "alive" even while growth is slow. Calm, low-amplitude (Task 4).
  late final AnimationController _breathCtrl;

  late final List<String> _sequence;
  int _phraseIndex = 0;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300))..forward();
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _progressCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 80));
    // Group 1 — resume the bar at the real elapsed fraction (so leaving and
    // returning, which rebuilds this bubble, no longer restarts progress at 0).
    final started = widget.startedAt;
    final elapsedMs = started != null
        ? DateTime.now().difference(started).inMilliseconds
        : 0;
    _progressCtrl.forward(from: (elapsedMs / 80000).clamp(0.0, 0.99));
    _progress = Tween<double>(begin: 0.04, end: 0.96)
        .animate(CurvedAnimation(parent: _progressCtrl, curve: Curves.easeOut));

    _breathCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1700))..repeat(reverse: true);
    // NOTE: the localized phrase sequence is built in didChangeDependencies —
    // NOT here. context.l10n → Localizations.of → dependOnInheritedWidgetOf…
    // is illegal in initState (throws → red ErrorWidget covering the loader).
  }

  bool _seqReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seqReady) return; // build the one-shot narrative exactly once
    _seqReady = true;
    // Slot 3 becomes the atmosphere-flavoured beat when the atmosphere is
    // recognised.
    final l10n = context.l10n;
    final base =
        widget.iteration > 1 ? l10n.genRefinePhrases : l10n.genInitPhrases;
    final seq = List<String>.from(base);
    final flavor = l10n.genFlavor(widget.atmosphere);
    if (flavor != null && seq.length > 3) seq[3] = flavor;
    _sequence = seq;
    _advancePhases();
  }

  // Monotonic, non-looping scheduler. Dwell windows widen as generation
  // progresses and carry a small deterministic-ish jitter so the cadence
  // never feels robotic (Task 2). The final phase is never advanced past —
  // it holds until this bubble is removed (success/failure). No modulo, no
  // wrap, no repetition (Task 3).
  void _advancePhases() async {
    // Base dwell per phase (ms); last entry is irrelevant (held).
    const dwell = [3200, 4000, 5200, 6600, 8200, 9000];
    final rnd = Random(widget.iteration * 7919 + _sequence.length);
    for (var i = 0; i < _sequence.length - 1; i++) {
      final jitter = 1.0 + (rnd.nextDouble() - 0.5) * 0.28; // ±14%
      await Future.delayed(
          Duration(milliseconds: (dwell[i] * jitter).round()));
      if (!mounted) return;
      setState(() => _phraseIndex = i + 1);
    }
    // Final phase reached — intentionally do nothing further (held).
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _progressCtrl.dispose();
    _breathCtrl.dispose();
    super.dispose();
  }

  // Backdrop = the image being transformed (cinematic wait presence).
  Widget? _backdrop() {
    if (widget.sourceFile != null) {
      return Image.file(widget.sourceFile!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          filterQuality: FilterQuality.medium);
    }
    final u = widget.backdropUrl;
    if (u != null && u.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: u,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder: (_, _) => const ColoredBox(color: AppColors.textPrimary),
        errorWidget: (_, _, _) =>
            const ColoredBox(color: AppColors.textPrimary),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final h =
        (MediaQuery.sizeOf(context).height * 0.52).clamp(280.0, 560.0);
    final img = _backdrop();
    return FadeTransition(
      opacity: _fade,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
          child: SizedBox(
            height: h,
            width: double.infinity,
            child: RevealCanvas(
              ambientImage: widget.sourceFile != null
                  ? FileImage(widget.sourceFile!)
                  : (widget.backdropUrl != null &&
                          widget.backdropUrl!.isNotEmpty)
                      ? CachedNetworkImageProvider(widget.backdropUrl!)
                      : null,
              ambientBlur: 18,
              ambientDarken: 0.5,
              bottomScrim: true,
              bottomOverlay: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DotsIndicator(),
                    const SizedBox(height: 10),
                    // Fixed transition — outgoing vanishes immediately and
                    // only the incoming fades in (no stacked double-text);
                    // reserved height prevents layout jitter (Wave 4.9 §4).
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 360),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: const Threshold(0),
                      layoutBuilder: (cur, _) =>
                          cur ?? const SizedBox.shrink(),
                      transitionBuilder: (child, anim) =>
                          FadeTransition(opacity: anim, child: child),
                      child: SizedBox(
                        key: ValueKey(_phraseIndex),
                        height: 24,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _sequence[_phraseIndex],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: AppColors.surface,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    AnimatedBuilder(
                      animation: Listenable.merge([_progress, _breathCtrl]),
                      builder: (_, _) {
                        final breath = 150 + (90 * _breathCtrl.value).round();
                        return SizedBox(
                          width: 200,
                          height: 2,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(1),
                            child: Stack(
                              children: [
                                // Sprint 2A — brand-gold progress line (visual
                                // only; timing / asymptote / phrases untouched).
                                Container(
                                    color: AppColors.accent
                                        .withValues(alpha: 0.22)),
                                FractionallySizedBox(
                                  widthFactor: _progress.value,
                                  child: Container(
                                      color: AppColors.accent
                                          .withAlpha(breath)),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              child: img ?? const ColoredBox(color: AppColors.textPrimary),
            ),
          ),
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

// ── Thinking bubble (chat-only loading state) ─────────────────────────────────

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble({super.key});

  @override
  Widget build(BuildContext context) {
    // Wave 5.11 — match the new editorial AI voice : no avatar, no bubble
    // chrome, just the pulsing dots quietly left-aligned. Reads as
    // "waiting for the next architectural sentence", not a messenger
    // typing indicator.
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 0, 14),
        child: _DotsIndicator(),
      ),
    );
  }
}

// ── Image result bubble ───────────────────────────────────────────────────────

class _ImageResultBubble extends StatefulWidget {
  final MessageModel message;
  final int index;
  // Wave 5.12b — F6 lineage cue. Non-null = this vision was branched
  // from an earlier one via a branchEvent immediately before it ; the
  // eyebrow appends "(FROM <tag>)" so the lineage reads inline.
  final String? sourceVisionTag;
  final VoidCallback onRevealTap;
  const _ImageResultBubble({
    super.key,
    required this.message,
    required this.index,
    this.sourceVisionTag,
    required this.onRevealTap,
  });

  @override
  State<_ImageResultBubble> createState() => _ImageResultBubbleState();
}

class _ImageResultBubbleState extends State<_ImageResultBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;

  // Wave 5.9 — narration capped at 2 lines so the render stays high in the
  // viewport. Tap the narration to expand the full prose. Lossless : the
  // backend message remains the source of truth.
  bool _narrationExpanded = false;

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

  // Wave 5.9 — establishes the future vision-timeline mental model.
  // The backend label is "Style · Vision N"; we surface it as "VISION N ·
  // STYLE" so the version reads first — a step toward the architectural
  // evolution timeline. Typography-first, no badge chrome.
  String _eyebrowLabel(String styleLabel) {
    if (styleLabel.contains('·')) {
      final parts = styleLabel.split('·').map((s) => s.trim()).toList();
      if (parts.length == 2 && parts.every((p) => p.isNotEmpty)) {
        return '${parts[1]} · ${parts[0]}';
      }
    }
    return styleLabel;
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.message.result!;
    final narration = widget.message.content;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Editorial eyebrow ─────────────────────────────────────────
            // Wave 5.11 — leading "•" bullet acts as a subtle timeline node.
            // Wave 5.12b — when this vision was branched from an earlier
            // one, append "(FROM VISION N)" inline so the lineage reads
            // at-a-glance without a separate widget.
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
              child: Text(
                '•  ${_eyebrowLabel(result.styleLabel).toUpperCase()}'
                '${widget.sourceVisionTag != null ? '  (FROM ${widget.sourceVisionTag!.toUpperCase()})' : ''}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                      fontSize: 10,
                    ),
              ),
            ),
            // ── The render (image-as-interface, Wave 5.13d.2) ─────────────
            // Restores the RevealCanvas ambient-backdrop pattern : the
            // image displays at its NATIVE 3:2 ratio centred vertically
            // inside a 0.52-of-screen-height portrait card. The card's
            // empty space above/below the focal image is filled with a
            // BLURRED + DARKENED ambient version of the image itself,
            // which reads as a cinematic atmospheric fade rather than
            // dead space. Zero crop on the focal — full architectural
            // composition preserved. 12dp inset breakout keeps the
            // premium framing visible. Card height matches the
            // _LoadingBubble formula (screen_h * 0.52, clamped 280-560)
            // so the shape doesn't jump between generating and
            // generated. Tap anywhere opens the fullscreen reveal.
            LayoutBuilder(
              builder: (ctx, constraints) {
                // Wave 5.13d.4 — full-screen-width breakout. The parent
                // ListView has horizontal AppSpacing.pagePadding on each
                // side ; extending the OverflowBox by 2 × pagePadding
                // makes the card reach the actual screen edges, matching
                // the reveal screen's edge-to-edge image (galleria, not
                // chat bubble). The eyebrow + narration above/below stay
                // at their small inset for caption-style legibility.
                final breakoutWidth =
                    constraints.maxWidth + AppSpacing.pagePadding * 2;
                final h = (MediaQuery.sizeOf(context).height * 0.52)
                    .clamp(280.0, 560.0);
                return SizedBox(
                  height: h,
                  child: OverflowBox(
                    alignment: Alignment.center,
                    minWidth: breakoutWidth,
                    maxWidth: breakoutWidth,
                    minHeight: h,
                    maxHeight: h,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                            spreadRadius: -4,
                          ),
                        ],
                      ),
                      child: ScaleTransition(
                        scale: _scale,
                        child: _GeneratedImageCard(
                          result: result,
                          onRevealTap: widget.onRevealTap,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            // ── Narration BELOW image (Wave 5.13d.3 image-first refinement) ──
            // Narration moved from above to below the image so the
            // sequence the user reads is : minimal eyebrow → render →
            // (optional) supporting prose. The image is the first
            // emotional object, the text becomes secondary support that
            // the user can engage with after observing the render.
            // 2-line cap with tap-to-expand preserved : full AI message
            // remains accessible on demand. Lossless ; perception only.
            if (narration.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(
                      () => _narrationExpanded = !_narrationExpanded),
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    alignment: Alignment.topLeft,
                    child: Text(
                      narration,
                      maxLines: _narrationExpanded ? null : 2,
                      overflow: _narrationExpanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.5,
                          ),
                    ),
                  ),
                ),
              ),
            // Wave 5.13 — action row removed. The image itself is now
            // the primary interaction (tap = reveal). Share migrated
            // entirely to the fullscreen reveal screen where exploration
            // + share emotionally belong together.
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
              child: Text(
                '${context.l10n.visionCreated} '
                '${_timeAgo(widget.message.createdAt)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GeneratedImageCard extends StatefulWidget {
  final GeneratedResult result;
  final VoidCallback onRevealTap;
  const _GeneratedImageCard({
    required this.result,
    required this.onRevealTap,
  });

  @override
  State<_GeneratedImageCard> createState() => _GeneratedImageCardState();
}

class _GeneratedImageCardState extends State<_GeneratedImageCard> {
  // Wave 5.13d.2 — restored the shared provider pattern : one
  // CachedNetworkImageProvider drives the focal image, the ambient
  // backdrop, AND the intrinsic-ratio probe. Single decode (RevealCanvas
  // guidance from Wave 4.10b) so a landscape render is no longer cropped
  // to the card's portrait box — it centres at its true ratio over the
  // ambient blur. The [Wave 5.12d] diagnostic timing log piggybacks on
  // the same listener.
  late final ImageProvider _provider =
      CachedNetworkImageProvider(widget.result.afterImageUrl);
  double? _aspectRatio;
  ImageStream? _sizeStream;
  ImageStreamListener? _sizeListener;

  @override
  void initState() {
    super.initState();
    final stopwatch = Stopwatch()..start();
    _sizeListener = ImageStreamListener((info, _) {
      stopwatch.stop();
      debugPrint(
        '[Wave 5.12d] image card loaded in ${stopwatch.elapsedMilliseconds}ms '
        '(${info.image.width}x${info.image.height}, url=${widget.result.afterImageUrl.split('?').first.split('/').last})',
      );
      if (mounted) {
        setState(
            () => _aspectRatio = info.image.width / info.image.height);
      }
      _sizeStream?.removeListener(_sizeListener!);
    });
    _sizeStream = _provider.resolve(ImageConfiguration.empty);
    _sizeStream!.addListener(_sizeListener!);
  }

  @override
  void dispose() {
    if (_sizeListener != null) _sizeStream?.removeListener(_sizeListener!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final onRevealTap = widget.onRevealTap;
    // Wave 5.13d.2 — RevealCanvas restored. Image centres at its native
    // 3:2 ratio over an ambient blurred backdrop of itself. Full
    // architectural composition visible (zero crop), atmospheric depth
    // around it reads cinematic without being sci-fi (it's the image's
    // own light/colour blurred — feels architectural, not synthetic).
    // GestureDetector wraps the whole surface : tap anywhere opens
    // reveal. The top-right open_in_full affordance is preserved.
    return GestureDetector(
      onTap: onRevealTap,
      // Wave 5.13d.4 — rounded card border dropped. The card now extends
      // edge-to-edge with the screen ; a rounded clip would just create
      // little corner notches at the screen edges. Plain ClipRect keeps
      // the focal/ambient layers contained while preserving the
      // full-bleed magazine look.
      child: ClipRect(
        child: Stack(
            fit: StackFit.expand,
            children: [
              RevealCanvas(
                ambientImage: _provider,
                focalAspectRatio: _aspectRatio,
                bottomScrim: false,
                // Pinch (2 fingers) zooms the render in place and snaps back on
                // release. Pan disabled so 1-finger drag still scrolls the chat
                // and a single tap still opens the reveal (GestureDetector above).
                child: PinchZoom(
                  child: CachedNetworkImage(
                    imageUrl: result.afterImageUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    placeholder: (_, _) => const _ShimmerPlaceholder(),
                    errorWidget: (_, _, _) =>
                        const ColoredBox(color: AppColors.shimmerBase),
                  ),
                ),
              ),
              // Subtle interactivity affordance — top-right corner,
              // ignores its own pointer so taps go through to the
              // GestureDetector above.
              Positioned(
                top: 12,
                right: 12,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.32),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.open_in_full,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────
// Wave 5.11 — _AiAvatar removed entirely. The AI voice is now editorial
// (caption-style around the render), not a messenger participant. The
// thinking indicator dropped its avatar too ; both states stay consistent.

// ── Branch event card — Option C (Wave 5.12b) ────────────────────────────────
// Full-width stacked narrative card inserted into the chat timeline when
// the user taps "Continue this vision" on an older render. Reads as an
// architectural design decision, not a system alert.
//
// Visual : editorial header (CONTINUING FROM VISION N + timestamp) + body
// row (source thumbnail + style label + human explanation). Subtle 1px
// stroke at low alpha + soft tinted background ≠ pill / badge / system
// banner. Persists in Supabase as message_type='branch_event' (role
// 'system') so the decision survives session restart and reads as a
// first-class chronological beat in the conversation story.
class _BranchEventCard extends StatelessWidget {
  final MessageModel message;
  const _BranchEventCard({super.key, required this.message});

  // Backend label format is "Style · Vision N" ; extract the version number
  // for the editorial header and the bare style for the inline label.
  ({String visionTag, String styleName}) _splitLabel(String styleLabel) {
    if (styleLabel.contains('·')) {
      final parts = styleLabel.split('·').map((s) => s.trim()).toList();
      if (parts.length == 2 && parts.every((p) => p.isNotEmpty)) {
        return (visionTag: parts[1], styleName: parts[0]);
      }
    }
    return (visionTag: '', styleName: styleLabel);
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final result = message.result;
    final styleLabel = result?.styleLabel ?? '';
    final split = _splitLabel(styleLabel);
    final headerSuffix = split.visionTag.isEmpty
        ? 'EARLIER VISION'
        : split.visionTag.toUpperCase();
    final accent = AppColors.accent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
          border: Border.all(
            color: accent.withValues(alpha: 0.28),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Editorial header row : "CONTINUING FROM <VISION TAG>" + time.
            Row(
              children: [
                Expanded(
                  child: Text(
                    'CONTINUING FROM $headerSuffix',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          fontSize: 10,
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatTime(message.createdAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 10,
                        letterSpacing: 0.4,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Body row : source thumbnail + style label + human narration.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: result == null || result.afterImageUrl.isEmpty
                        ? const ColoredBox(color: AppColors.shimmerBase)
                        : CachedNetworkImage(
                            imageUrl: result.afterImageUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, _) =>
                                const ColoredBox(color: AppColors.shimmerBase),
                            errorWidget: (_, _, _) =>
                                const ColoredBox(color: AppColors.shimmerBase),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (split.styleName.isNotEmpty)
                        Text(
                          split.styleName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            height: 1.2,
                            letterSpacing: -0.1,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      if (split.styleName.isNotEmpty)
                        const SizedBox(height: 4),
                      Text(
                        message.content,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.4,
                              fontSize: 12.5,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
              // Wave 5.11 — chips lose their border entirely and adopt a
              // 4% alpha ink fill. Reads as "architectural suggestion",
              // not "button" : typography-first, calmer, more inline with
              // the editorial conversation flow.
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.textPrimary.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  suggestions[index],
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                        fontSize: 11,
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

// Wave 4.8: `_InputBar` / `_MicButton` were extracted to
// `features/chat/widgets/chat_input_bar.dart` (the canonical chat input bar),
// and now consume the shared `VoiceService` for dictation. Behaviour is
// preserved verbatim (controller / onSend / enabled contract); the upload
// description field uses the same `MicButton` + `VoiceService` for one
// consistent voice language across the conversational system.

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
                    // Routed value is canonical English; localize for display.
                    '${RoomTypeImages.displayLabel(l10n, currentRoomType)}'
                    ' · ${_brandSignature(currentStyle)}',
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

class _SourcePhotoSheet extends ConsumerStatefulWidget {
  final ProjectModel project;
  final File? sourceFile;
  // Wave 4.6: latest generated vision (continuity header). Null => fall back
  // to the source photo. Read-only context — not part of any contract.
  final String? currentVisionUrl;
  // Wave 4.7: the session's prior visions (chronological) + a "continue from
  // this vision" callback. Read-only history surfaced from the chat thread;
  // no model/contract change.
  final List<_VisionRef> visions;
  final void Function(_VisionRef) onContinueFromVision;
  final String initialRoomType;
  final String initialStyle;
  final Future<File?> Function() onReplace;
  // #8b — aiDecide carries the "Ayden Decide" choice (delegate the room) out of
  // the sheet so the next generation can set let_ai_decide.
  final void Function(
          String roomType, String style, bool aiDecide, bool surprise)
      onDirectionChanged;
  // Wave 5.16b — bimodal toggle removed (preserve-only UI in V1).
  // `initialMode` + `onModeChanged` params dropped ; parent no longer
  // needs to seed the sheet or react to a flip.

  const _SourcePhotoSheet({
    required this.project,
    this.sourceFile,
    this.currentVisionUrl,
    this.visions = const [],
    required this.onContinueFromVision,
    required this.initialRoomType,
    required this.initialStyle,
    required this.onReplace,
    required this.onDirectionChanged,
  });

  @override
  ConsumerState<_SourcePhotoSheet> createState() => _SourcePhotoSheetState();
}

class _SourcePhotoSheetState extends ConsumerState<_SourcePhotoSheet> {
  late String _selectedRoomType;
  late String _selectedStyle;
  // #8b — "Ayden Decide" (delegate the room to the AI) chosen in this sheet.
  bool _aiDecide = false;
  // #2 — "Ayden Signature" (delegate the ATMOSPHERE to the AI = surprise) chosen
  // in this sheet. Mirrors the upload-screen signature card.
  bool _signatureSelected = false;
  // Wave 5.16b — `_selectedMode` field removed with the MODE toggle.

  // Local source preview — lets "Replace photo" update the sheet in place
  // without closing it.
  File? _sourceFile;

  @override
  void initState() {
    super.initState();
    _selectedRoomType = widget.initialRoomType;
    _selectedStyle = widget.initialStyle;
    // Pre-select the signature card if the current direction already delegates
    // the atmosphere (surprise label convention, mirrors ChatScreen initState).
    _signatureSelected = widget.initialStyle == "AI's choice";
    _sourceFile = widget.sourceFile;
  }

  Future<void> _onReplaceTap() async {
    final file = await widget.onReplace();
    if (file != null && mounted) setState(() => _sourceFile = file);
  }

  void _apply() {
    // chat consumes (roomType, style, aiDecide, surprise) then the sheet pops.
    widget.onDirectionChanged(
        _selectedRoomType, _selectedStyle, _aiDecide, _signatureSelected);
    Navigator.of(context).pop();
  }

  // #8b — Ayden Decide free unlock (mirror of upload screen + aydenDecideFree).
  bool _aiLockedSheet() {
    if (FeatureFlags.aydenDecideFree) return false;
    final isPremium = ref.read(premiumProvider);
    final isAdmin = ref.read(accessProvider);
    final hasPromo = ref.read(meStatusProvider)?.hasActivePromo ?? false;
    return !(isPremium || isAdmin || hasPromo);
  }

  void _onAiDecideTap() {
    if (_aiLockedSheet()) {
      _openSheetPaywall('delegated_choice');
      return;
    }
    setState(() => _aiDecide = !_aiDecide);
  }

  // #2 — Ayden Signature free unlock (mirror of upload screen + aydenSignatureFree).
  bool _signatureLockedSheet() {
    if (FeatureFlags.aydenSignatureFree) return false;
    final isPremium = ref.read(premiumProvider);
    final isAdmin = ref.read(accessProvider);
    final hasPromo = ref.read(meStatusProvider)?.hasActivePromo ?? false;
    return !(isPremium || isAdmin || hasPromo);
  }

  void _onSignatureTap() {
    if (_signatureLockedSheet()) {
      _openSheetPaywall('delegated_choice');
      return;
    }
    // Signature toggles like Ayden Decide. While it's on, any explicit style is
    // visually masked (see the atmosphere card `selected` predicate), so the two
    // are mutually exclusive — tapping it again turns delegation back off.
    setState(() => _signatureSelected = !_signatureSelected);
  }

  // Wave 5.17d — lock policy for the re-upload / direction sheet. Mirrors
  // the upload-screen rules so room + atmosphere restrictions are uniform
  // across every selection surface in the app. Premium users bypass all
  // locks (predicates return false).
  bool _roomLocked(String label) {
    // Wave 5.18 — admin bypass added alongside premium bypass.
    // Sprint 1B — promo grant unlocks all rooms too (matches backend bypass).
    final isPremium = ref.read(premiumProvider);
    final isAdmin = ref.read(accessProvider);
    final hasPromo = ref.read(meStatusProvider)?.hasActivePromo ?? false;
    if (isPremium || isAdmin || hasPromo) return false;
    final id = RoomTypeImages.idForLabel(context.l10n, label);
    return id == null || !kFreeRoomIds.contains(id);
  }

  void _onRoomTap(String label) {
    if (_roomLocked(label)) {
      _openSheetPaywall('room');
      return;
    }
    setState(() {
      _selectedRoomType = label;
      _aiDecide = false; // explicit room → not AI-delegated
    });
  }

  Future<void> _openSheetPaywall(String restrictedField) async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PaywallSheet(
        trigger: PaywallTrigger.locked,
        restrictedField: restrictedField,
      ),
    );
  }

  // ── AYDEN new card system (reupload sheet) — hero grid + "More Spaces" ─────
  // Selection VALUE = canonical ENGLISH label (locale-stable; the backend DNA
  // room lookup keys off English names — routing a localized label drops the
  // room DNA block). Same locks/paywall (_roomLocked / _onRoomTap). No AI
  // Decide here. Display labels English (Option A).
  Widget _newRoomsLayoutSheet(BuildContext context) {
    String value(String id) => RoomTypeImages.enLabelForId(id) ?? id;
    RoomCard card(RoomCardData r) {
      final v = value(r.id);
      return RoomCard(
        label: r.label,
        asset: r.asset,
        // Ayden Decide and an explicit room are mutually exclusive: while AI
        // Decide is on, no room card reads as selected (mirrors the upload screen).
        selected: _selectedRoomType == v && !_aiDecide,
        locked: _roomLocked(v),
        onTap: () => _onRoomTap(v),
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
                // #8b — Ayden Decide leads the choices here too (same card art
                // as the upload screen). Tapping it delegates the room to the AI.
                AiActionCard(
                  title: context.l10n.uplAiDecide,
                  subtitle: context.l10n.uplAiDecideSub,
                  selected: _aiDecide,
                  locked: _aiLockedSheet(),
                  onTap: _onAiDecideTap,
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
                itemBuilder: (context, i) =>
                    SizedBox(width: secW, child: card(kMoreRooms[i])),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final screenH = MediaQuery.sizeOf(context).height;

    // A tall sheet (not a full new screen) — the chat stays visible behind the
    // rounded top so it reads as "continuing the conversation", not a reset.
    return SizedBox(
      height: screenH * 0.9,
      child: Column(
        children: [
          const SizedBox(height: 10),
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
          const SizedBox(height: 14),

          // ── Continuity header — the CURRENT vision, image-first ───────────
          // Communicates "I'm evolving THIS space", never a blank reset.
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pagePadding),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
              child: SizedBox(
                height: 168,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _SheetVisionImage(
                      visionUrl: widget.currentVisionUrl,
                      sourceFile: _sourceFile,
                      beforeUrl: widget.project.beforeImageUrl,
                    ),
                    const Positioned.fill(
                      child: AppScrim(
                        edge: ScrimEdge.bottom,
                        opacity: 0.58,
                        extent: 0.6,
                      ),
                    ),
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 14,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppPill(text: context.l10n.chatEvolvingVision),
                          const SizedBox(height: 6),
                          Text(
                            '$_selectedRoomType · $_selectedStyle',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppColors.surface
                                      .withValues(alpha: 0.85),
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Scrollable direction controls ─────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding, 0, AppSpacing.pagePadding, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Source reference + calm Replace affordance.
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        // #24 — larger, UNCROPPED source preview (was a tiny
                        // 40×40 cover chip that cut the room). Full room shown,
                        // letterboxed on a neutral frame.
                        child: SizedBox(
                          width: 76,
                          height: 57,
                          child: ColoredBox(
                            color: const Color(0xFF0B0B0C),
                            child: _sourceFile != null
                                ? Image.file(_sourceFile!,
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.medium)
                                : widget.project.beforeImageUrl != null
                                    ? CachedNetworkImage(
                                        imageUrl:
                                            widget.project.beforeImageUrl!,
                                        fit: BoxFit.contain,
                                        placeholder: (_, _) => Container(
                                            color: AppColors.shimmerBase),
                                        errorWidget: (_, _, _) => Container(
                                            color: AppColors.shimmerBase),
                                      )
                                    : Container(color: AppColors.shimmerBase),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        l10n.sourcePhoto,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textTertiary,
                              fontSize: 11,
                            ),
                      ),
                      const Spacer(),
                      AppPill(
                        text: l10n.replacePhoto,
                        icon: Icons.image_outlined,
                        onTap: _onReplaceTap,
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // ── Design evolution — the project's visions, image-led ───
                  // Calm progression (V1 → … → latest), not a technical
                  // version tree. Tapping a vision continues from it.
                  if (widget.visions.isNotEmpty) ...[
                    _SheetEyebrow(label: context.l10n.chatDesignEvolution),
                    const SizedBox(height: 10),
                    _EvolutionStrip(
                      visions: widget.visions,
                      currentUrl: widget.currentVisionUrl,
                      onContinue: widget.onContinueFromVision,
                    ),
                    const SizedBox(height: 22),
                  ],

                  // Space type — Wave-4.3 room language (shared l10n rooms).
                  // Wave 5.17d — lock predicates mirror the upload-screen
                  // policy so the sheet's selection rules are identical :
                  // non-premium users see Living Room tappable, every
                  // other room dimmed with a 🔒 chip ; locked tap opens
                  // the paywall sheet (PaywallTrigger.locked).
                  _SheetEyebrow(label: context.l10n.chatSpaceType),
                  const SizedBox(height: 10),
                  if (FeatureFlags.newDesignCards)
                    _newRoomsLayoutSheet(context)
                  else ...[
                    _SheetRoomLabel(label: l10n.interiorSection),
                    const SizedBox(height: 8),
                    RoomTypeRow(
                      rooms: l10n.interiorRooms,
                      selected: _selectedRoomType,
                      onSelected: _onRoomTap,
                      isLocked: _roomLocked,
                    ),
                    const SizedBox(height: 14),
                    _SheetRoomLabel(label: l10n.exteriorSection),
                    const SizedBox(height: 8),
                    RoomTypeRow(
                      rooms: l10n.exteriorRooms,
                      selected: _selectedRoomType,
                      onSelected: _onRoomTap,
                      isLocked: _roomLocked,
                    ),
                  ],
                  const SizedBox(height: 22),

                  // Atmosphere — shared AtmosphereCard V2 horizontal strip.
                  _SheetEyebrow(label: context.l10n.chatAtmosphere),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 190,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      padding: EdgeInsets.zero,
                      itemCount: AppLocalizations.atmospheres.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, i) {
                        // #2 — Ayden Signature card first (mirror upload screen):
                        // delegates the atmosphere to the AI (surprise).
                        if (i == 0) {
                          final sigLocked = _signatureLockedSheet();
                          return SizedBox(
                            width: 150,
                            child: AtmosphereHeroCard(
                              compact: true,
                              name: '',
                              subtitle: 'AI analyzes your space and selects '
                                  'the atmosphere that fits it best.',
                              asset: 'assets/atmospheres/ayden_signature.jpg',
                              selected: _signatureSelected,
                              locked: sigLocked,
                              onTap: sigLocked
                                  ? () => _openSheetPaywall('delegated_choice')
                                  : _onSignatureTap,
                            ),
                          );
                        }
                        final a = AppLocalizations.atmospheres[i - 1];
                        // Wave 5.17d — atmosphere lock + paywall-on-tap
                        // mirroring upload-screen and full-reveal carousel.
                        // Wave 5.18 — admin bypass added.
                        final isPremium = ref.watch(premiumProvider);
                        final isAdmin = ref.watch(accessProvider);
                        final hasPromo =
                            ref.watch(meStatusProvider)?.hasActivePromo ?? false;
                        final locked = !isPremium && !isAdmin && !hasPromo
                            && !kFreeAtmosphereIds.contains(a.id);
                        final onTap = locked
                            ? () => _openSheetPaywall('atmosphere')
                            : () => setState(() {
                                  _selectedStyle = a.name;
                                  _signatureSelected = false;
                                });
                        return SizedBox(
                          width: 150,
                          child: FeatureFlags.newDesignCards
                              ? AtmosphereHeroCard(
                                  compact: true,
                                  name: a.name,
                                  subtitle: context.l10n.atmosphereSubtitle(a.id),
                                  asset: kAtmosphereCardById[a.id]?.asset ??
                                      'assets/cards/atmospheres/${a.id}.png',
                                  selected: a.name == _selectedStyle && !_signatureSelected,
                                  locked: locked,
                                  onTap: onTap,
                                )
                              : AtmosphereCard(
                                  atmosphere: a,
                                  selected: a.name == _selectedStyle && !_signatureSelected,
                                  locked: locked,
                                  onTap: onTap,
                                ),
                        );
                      },
                    ),
                  ),
                  // Wave 5.16b — MODE eyebrow + Preserve/Create toggle
                  // removed from the Design Direction sheet. V1 product
                  // positioning : preserve onboarding AND preserve
                  // refinement (no creative UI exposed). Backend still
                  // accepts generation_mode ; _ChatScreenState's
                  // _generationMode now stays at its default
                  // ("preserve") forever from the UI side. Session
                  // restore of legacy "creative" values stays
                  // coherent — it's just no longer flippable.
                ],
              ),
            ),
          ),

          // ── Sticky CTA — always reachable; sheet-toned ────────────────────
          StickyActionBar(
            background: AppColors.surface,
            primary: AppButton(
              label: FeatureFlags.newDesignCards
                  ? context.l10n.uplGenerateDesign
                  : context.l10n.chatApplyDirection,
              icon: FeatureFlags.newDesignCards ? Icons.auto_awesome : null,
              onPressed: _apply,
            ),
          ),
        ],
      ),
    );
  }
}

// Resolves the continuity header image: current vision → source file →
// original → calm shimmer. Image-first, BoxFit.cover.
// Wave 4.7 — a single prior vision (read-only history element).
class _VisionRef {
  final String afterUrl;
  final String label;
  const _VisionRef({required this.afterUrl, required this.label});
}

// Image-led evolution strip — calm progression V1 → … → latest. Not a
// technical version tree. Tapping a vision continues the project from it.
class _EvolutionStrip extends StatelessWidget {
  final List<_VisionRef> visions;
  final String? currentUrl;
  final void Function(_VisionRef) onContinue;
  const _EvolutionStrip({
    required this.visions,
    required this.currentUrl,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    // Wave 4.10b (#7): the strip was 104 while the content (72 image + 5 +
    // 'Vision N' + label) summed to ~107 → a few-px overflow that worsened
    // with text scaling. Raise to 122 and let the caption block flex, so it
    // fits with margin across SE/standard/Max and larger font scales while
    // keeping the image-led hierarchy.
    return SizedBox(
      height: 122,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: EdgeInsets.zero,
        itemCount: visions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final v = visions[i];
          final isCurrent = currentUrl != null && v.afterUrl == currentUrl;
          return GestureDetector(
            onTap: () => onContinue(v),
            child: SizedBox(
              width: 124,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusCard),
                        child: SizedBox(
                          width: 124,
                          height: 72,
                          child: CachedNetworkImage(
                            imageUrl: v.afterUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => const ColoredBox(
                                color: AppColors.shimmerBase),
                            errorWidget: (_, _, _) => const ColoredBox(
                                color: AppColors.shimmerBase),
                          ),
                        ),
                      ),
                      if (isCurrent)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusCard),
                              border: Border.all(
                                  color: AppColors.accent, width: 2),
                            ),
                          ),
                        ),
                      if (isCurrent)
                        Positioned(
                          top: 6,
                          left: 6,
                          child:
                              AppPill(text: context.l10n.chatCurrent, dark: true),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Text(
                          'Vision ${i + 1}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          v.label,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: AppColors.textTertiary,
                                fontSize: 10,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SheetVisionImage extends StatelessWidget {
  final String? visionUrl;
  final File? sourceFile;
  final String? beforeUrl;
  const _SheetVisionImage({
    this.visionUrl,
    this.sourceFile,
    this.beforeUrl,
  });

  @override
  Widget build(BuildContext context) {
    if (visionUrl != null && visionUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: visionUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder: (_, _) => const ColoredBox(color: AppColors.shimmerBase),
        errorWidget: (_, _, _) =>
            const ColoredBox(color: AppColors.shimmerBase),
      );
    }
    if (sourceFile != null) {
      return Image.file(sourceFile!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          filterQuality: FilterQuality.medium);
    }
    if (beforeUrl != null && beforeUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: beforeUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder: (_, _) => const ColoredBox(color: AppColors.shimmerBase),
        errorWidget: (_, _, _) =>
            const ColoredBox(color: AppColors.shimmerBase),
      );
    }
    return const ColoredBox(color: AppColors.shimmerBase);
  }
}

class _SheetEyebrow extends StatelessWidget {
  final String label;
  const _SheetEyebrow({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w600,
            fontSize: 11,
            letterSpacing: 1.2,
          ),
    );
  }
}

class _SheetRoomLabel extends StatelessWidget {
  final String label;
  const _SheetRoomLabel({required this.label});

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

// ── Wave 5.16b — Bimodal toggle removed ──────────────────────────────────────
// _SheetModeToggle + _SheetModeSegment widgets dropped together with the
// MODE eyebrow in the Design Direction sheet. V1 product positioning :
// preserve onboarding AND preserve refinement, no creative UI exposed.
// _generationMode state survives in _ChatScreenState and ships to the
// backend on every /generate (always "preserve" from the UI side, may be
// "creative" if restored from a legacy session). Orphaned l10n keys
// (modePreserve / modePreserveSub / modeCreate / modeCreateSub) dropped
// from app_localizations.dart + translations/{en,km}.dart in this wave.

// Wave 4.10h: `_SheetRoomRow` (text pills) removed — the chat re-upload
// sheet now uses the SAME shared `RoomTypeRow` as the upload screen (one
// foundation, zero duplicated room-type UI logic). `_SheetRoomLabel` /
// `_SheetEyebrow` grouping is preserved; the `(rooms, selected, onSelected)`
// contract — and routing / session / generation — is unchanged.

// ── System message bubble ─────────────────────────────────────────────────────

class _SystemMessageBubble extends StatelessWidget {
  final MessageModel message;
  const _SystemMessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    // Wave 5.11 — drop the flanking dividers (same rationale as
    // _DaySeparator). A quiet italic line of supporting copy reads
    // as architectural narration, not a chat-app system event.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Text(
          message.content,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
        ),
      ),
    );
  }
}

// ── Animated shimmer placeholder (Wave 5.12d) ────────────────────────────────
// Soft linear sweep across the surface during image download + decode. Reads
// as "actively loading" instead of "frozen blank". Calm timing (1.4s cycle),
// no scale or motion-noise, just a subtle diagonal highlight passing across.
// Used in place of the flat ColoredBox(shimmerBase) for the generated-image
// card placeholder ; error states stay static so they don't false-signal a
// loading animation when the image actually failed.
class _ShimmerPlaceholder extends StatefulWidget {
  const _ShimmerPlaceholder();

  @override
  State<_ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<_ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        // Sweep travels from -1.0 → 2.0 of the gradient axis so the
        // highlight enters from the left edge and exits past the right.
        final t = _ctrl.value;
        final shift = -1.0 + 3.0 * t;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(shift - 0.25, -0.4),
              end: Alignment(shift + 0.25, 0.4),
              colors: const [
                AppColors.shimmerBase,
                AppColors.shimmerHighlight,
                AppColors.shimmerBase,
              ],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}
