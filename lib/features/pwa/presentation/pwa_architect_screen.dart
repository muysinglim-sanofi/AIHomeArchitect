/// THE DESIGN SESSION, after the result. Phase 5.
///
/// What changed, and what deliberately did not
/// -------------------------------------------
/// Every line of control flow here is the one that was already here: which
/// message renders as what, that the FIRST vision leads with its image, that a
/// backend-sent `chips` list beats the local suggestions, that a red advisory
/// verdict has no override, that a quick action is identical to typing it. None
/// of that moved. What moved is the room it all sits in.
///
/// It used to sit in a photograph. A blurred Warm Modern living room filled the
/// window, a warm-ivory veil lay over it, and on desktop a sheet of translucent
/// glass floated on top carrying the conversation. It was a beautiful surface
/// and it was the wrong one: the person has just generated a picture of THEIR
/// room, and the app was showing them somebody else's behind it. Two rooms
/// competing, and the one that wins is not theirs.
///
/// So the backdrop is gone and the canvas is the product's own cream. The
/// render is the only photograph on the screen.
///
///     AYDEN STUDIO                header, ink on cream
///     ┌──────────────────────┐
///     │  the generated room  │    the payoff, first and largest
///     └──────────────────────┘
///     Vision 1 · Warm Modern      caption UNDER the image, not above it
///     [ View Full Reveal ] …      actions
///     Your Warm Modern direction  two short sentences
///     What would you like to change?
///     ( Make it warmer ) ( … )    suggestions
///     ── ask Ayden ─────────  ▸    the composer
///
/// IMAGE FIRST, COMMENTARY SECOND, ACTIONS THIRD is not a new rule here — the
/// first vision already led with its render. What Phase 5 fixed is that the
/// image was preceded by a title strip inside its own card, so the first thing
/// read after a two-minute wait was a label.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pwa_controller.dart';
import '../domain/pwa_models.dart';
import '../domain/pwa_project.dart';
import 'pwa_architect_tokens.dart';
import 'pwa_brand.dart';
import 'pwa_stored_image.dart';
import 'pwa_working_indicator.dart';
import '../l10n/pwa_l10n.dart';
import 'pwa_account_chip.dart';
import 'pwa_theme.dart';
import 'pwa_type.dart';
import 'pwa_language_switcher.dart';

// V7 responsive tiers (§4). Local to the Architect so the shared
// `pwaFormFactorForWidth` (used by the frozen entry screen) stays untouched.
bool _isMobileW(double w) => w < 768;

/// Maximum measure of the conversation column. Wide screens buy comfort, not a
/// wider line of text.
const double kPwaChatColumnMax = 880;

/// Maximum width of the desktop chat workspace surface that holds the header,
/// the thread and the composer together.
const double kPwaChatShellMax = 1080;

/// The glass is gone.
///
/// This file used to carry sixteen constants describing a translucent plate,
/// its blur, its two gradient stops, its border alpha and the ink to use on
/// each side of it — because the conversation floated on a photograph of a
/// living room. Phase 5 removed the photograph, and every one of those numbers
/// went with it. What is left is the product's own canvas, and the tokens for
/// that live in `pwa_theme.dart` where every other screen reads them.

/// The one rule in the composition: the product hairline, separating the
/// thread from the composer and the desktop project header from the thread.
class _V7GlassDivider extends StatelessWidget {
  const _V7GlassDivider();

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(
        color: pwaHairlineSoft,
        child: SizedBox(height: 1, width: double.infinity),
      );
}

/// Left gutter of the conversation grid — the width of the Ayden avatar plus its
/// gap. EVERY Ayden-side element starts here: bubbles, vision card, guidance and
/// quick actions, so the thread reads on one axis instead of three.
const double kPwaChatGutter = 42;

/// The render IS the payoff of Generate: it takes nearly the whole conversation
/// column. Capped in height so the actions, Ayden's reply and the composer still
/// belong to the same screen.
const double kPwaVisionMaxWidth = 820;
const double kPwaVisionMaxHeight = 560;

/// The shape the engine actually returns: 1536x1024. Stated once, so the result
/// screen shows the render rather than a crop of it.
const double kPwaRenderAspect = 3 / 2;

class PwaArchitectScreen extends ConsumerStatefulWidget {
  const PwaArchitectScreen({super.key});

  @override
  ConsumerState<PwaArchitectScreen> createState() => _PwaArchitectScreenState();
}

class _PwaArchitectScreenState extends ConsumerState<PwaArchitectScreen> {
  final _chatScroll = ScrollController();
  // Owned here so "Refine with Ayden" can hand the user a ready composer.
  final _composerFocus = FocusNode();
  final Map<String, GlobalKey> _visionKeys = {};
  String? _highlightVersionId;
  Timer? _highlightTimer;

  PwaController get _c => ref.read(pwaControllerProvider.notifier);

  GlobalKey _visionKey(String versionId) => _visionKeys.putIfAbsent(
    versionId,
    () => GlobalKey(debugLabel: versionId),
  );

  @override
  void initState() {
    super.initState();
    // Arriving from the Full Reveal ("Back to conversation" / "Open in
    // conversation") carries the vision that was being explored: scroll its
    // message into view and mark it, so the return lands ON that render instead
    // of at the bottom of the thread.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final id = ref.read(pwaControllerProvider).previewVisionId;
      if (id != null) _revealVision(id);
    });
  }

  void _scrollChatToBottom() {
    if (!_chatScroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScroll.hasClients) return;
      _chatScroll.animateTo(
        _chatScroll.position.maxScrollExtent,
        duration: Av7Motion.component,
        curve: Av7Motion.curve,
      );
    });
  }

  /// §25/§34 — preview a vision, then scroll its rich chat card into view and
  /// briefly highlight it. Creates no version.
  Future<void> _revealVision(String versionId) async {
    _c.previewVision(versionId);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final ctx = _visionKeys[versionId]?.currentContext;
    if (ctx != null && ctx.mounted) {
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.18,
        duration: Av7Motion.component,
        curve: Av7Motion.curve,
      );
    }
    if (!mounted) return;
    _highlightTimer?.cancel();
    setState(() => _highlightVersionId = versionId);
    _highlightTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _highlightVersionId = null);
    });
  }

  void _onQuickAction(String action) => _c.sendUserText(action);

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _chatScroll.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(pwaControllerProvider.select((s) => s.messages.length), (_, _) {
      _scrollChatToBottom();
    });
    // Arriving with a refinement intent: put the caret where the user must type.
    ref.listen(pwaControllerProvider.select((s) => s.refineContextVisionId), (
      prev,
      next,
    ) {
      if (next != null && next != prev) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _composerFocus.requestFocus();
        });
      }
    });
    final state = ref.watch(pwaControllerProvider);

    return Scaffold(
      key: const ValueKey('pwa-design-session-result'),
      // The product canvas. It used to be transparent so a blurred photograph
      // could show through from below; that photograph is gone.
      backgroundColor: pwaCanvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            return _chat(context, state, c.maxWidth, c.maxHeight);
          },
        ),
      ),
    );
  }

  // ── One screen, one purpose: the conversation ───────────────────────────────

  /// Chat-first. The Full Reveal, the atmosphere rail and the vision navigator
  /// all live on `/reveal` now, so nothing here competes with the conversation.
  ///
  /// Desktop gets a real WORKSPACE: a bounded surface holding the project header,
  /// the scrolling thread and the composer, floating on the warm backdrop. The
  /// previous full-height column read as a gallery adrift in empty space.
  Widget _chat(BuildContext context, PwaState state, double w, double h) {
    final mobile = _isMobileW(w);
    final desktop = w >= 1200;
    // ONE measure: the shell is the column plus its gutters, so the internal
    // header, every message, the guidance and the composer share a single left
    // edge instead of three.
    const gutter = 40.0;
    final columnW = desktop
        ? (w.clamp(0.0, kPwaChatShellMax) - gutter * 2).clamp(
            0.0,
            kPwaChatColumnMax,
          )
        : w.clamp(0.0, kPwaChatColumnMax);

    // Keep a floor under the render on very short windows, but let it be big:
    // shrinking it to a third of the thread made the result look incidental.
    final visionMaxH = (h - 300).clamp(300.0, kPwaVisionMaxHeight);

    Widget feed() => ColoredBox(
      key: const ValueKey('av7-chat-feed'),
      color: Colors.transparent,
      child: ListView(
        controller: _chatScroll,
        // The conversation is short; keep every message laid out so
        // navigation / highlight never targets an unbuilt row.
        cacheExtent: 4000,
        padding: EdgeInsets.fromLTRB(
          desktop ? 0 : (mobile ? 12 : 20),
          16,
          desktop ? 0 : (mobile ? 12 : 20),
          // Breathing room: the last message is never under the composer.
          24,
        ),
        children: [
          ..._chatMessages(state, visionMaxH),
          SizedBox(height: MediaQuery.viewPaddingOf(context).bottom + 8),
        ],
      ),
    );

    // The composer and the refinement context it belongs to are one block.
    Widget composer() {
      final refine = state.refineContextVision;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (refine != null)
            Align(
              alignment: Alignment.centerLeft,
              child: _V7RefineContextBar(
                vision: refine,
                onCancel: _c.clearRefineContext,
              ),
            ),
          _V7Composer(
            enabled: !state.generating,
            focusNode: _composerFocus,
            onSend: _c.sendUserText,
          ),
        ],
      );
    }

    // ONE composition at every width now. The narrow and wide layouts used to
    // differ because one sat on a veil and the other on a sheet of glass; with
    // both on the canvas the only real difference left was a project header the
    // wide layout could afford, so it keeps it and nothing else forks.
    return Column(
      children: [
        _V7GlobalHeader(
          compact: mobile,
          onBack: _c.openHome,
          onProjects: _c.openLibrary,
        ),
        Expanded(
          child: Center(
            child: SizedBox(
              width: columnW,
              child: Column(
                children: [
                  if (desktop) ...[
                    _V7ConversationHeader(state: state),
                    const _V7GlassDivider(),
                  ],
                  Expanded(child: feed()),
                ],
              ),
            ),
          ),
        ),
        const _V7GlassDivider(),
        Center(
          child: SizedBox(width: columnW, child: composer()),
        ),
      ],
    );
  }

  // ── Shared chat chronology builder ──────────────────────────────────────────

  List<Widget> _chatMessages(PwaState state, double visionMaxH) {
    final out = <Widget>[];
    for (final m in state.messages) {
      out.addAll(_messageWidgets(state, m, visionMaxH));
    }
    return out;
  }

  List<Widget> _messageWidgets(
    PwaState state,
    PwaMessage m,
    double visionMaxH,
  ) {
    switch (m.kind) {
      case PwaMessageKind.loading:
        // The message says WHAT is running; the words for it live here, beside
        // the indicator, so there is one phase system and the controller carries
        // no copy.
        return [
          const _V7ChatGap(),
          _V7InlineGenerating(
            phases: pwaWorkingPhasesFor(
              m.workingKind,
              m.workingSubject,
              context.pwaL10n,
            ),
          ),
        ];
      case PwaMessageKind.text:
        if (m.role == PwaRole.user) {
          return [const _V7ChatGap(), _V7UserBubble(text: m.text)];
        }
        // Ayden text — advice, marker, or a refine offer (§21 confirm card).
        return [
          const _V7ChatGap(),
          _V7AydenBubble(text: m.text),
          if (m.pendingRefine != null) ...[
            const SizedBox(height: 10),
            _V7RefineConfirmCard(
              state: state,
              controller: _c,
              messageId: m.id,
              instruction: m.pendingRefine!,
              advisoryVerdict: m.advisoryVerdict,
            ),
          ] else if (m.chips.isNotEmpty) ...[
            const SizedBox(height: 8),
            _V7QuickActions(chips: m.chips, onTap: _onQuickAction),
          ],
        ];
      case PwaMessageKind.reveal:
        final vision = _visionFor(state, m.visionId);
        if (vision == null) return const [];
        final isCurrentReveal =
            vision.versionId == state.currentVision?.versionId;
        final card = _V7VisionCard(
          key: _visionKey(vision.versionId),
          vision: vision,
          atmosphereName: _atmoNameOf(state, vision.atmosphereId),
          highlighted: _highlightVersionId == vision.versionId,
          maxImageHeight: visionMaxH,
          onOpenReveal: () => _c.openReveal(vision.versionId),
          // A button label is not a design instruction. Sending "Refine
          // Vision 2" as the message made the parser read it as a change and
          // the engine act on it. Mobile has no such button: refining is what
          // the composer is for, so this focuses it on that vision.
          onRefine: () {
            _c.continueFromVision(vision.versionId);
            _composerFocus.requestFocus();
          },
          onTryAtmosphere: () => _c.openReveal(vision.versionId),
        );
        // Guidance: after a result nobody should wonder what to do next.
        final guidance = <Widget>[
          if (isCurrentReveal && !state.generating) ...[
            const SizedBox(height: 14),
            const _V7ChangePrompt(),
            const SizedBox(height: 10),
            _V7QuickActions(
              chips: _defaultQuickActions(context.pwaL10n),
              onTap: _onQuickAction,
            ),
          ],
        ];

        // The FIRST vision leads: the user has just generated an image, so the
        // image is what greets them — Ayden's commentary follows it. This is a
        // presentation order only; the stored chronology is untouched.
        if (vision.visionNumber == 1) {
          return [
            const _V7ChatGap(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // IMAGE, then COMMENTARY, then ACTIONS. The three pills used to
                // sit inside the card, between the render and Ayden's line, so
                // a person who had waited two minutes met a row of buttons
                // before they were told anything about what they were looking
                // at. Same widgets, same callbacks, read in the order the
                // moment actually has.
                _V7VisionCard(
                  key: _visionKey(vision.versionId),
                  vision: vision,
                  atmosphereName: _atmoNameOf(state, vision.atmosphereId),
                  highlighted: _highlightVersionId == vision.versionId,
                  maxImageHeight: visionMaxH,
                  showActions: false,
                  onOpenReveal: () => _c.openReveal(vision.versionId),
                  onRefine: () {
                    _c.continueFromVision(vision.versionId);
                    _composerFocus.requestFocus();
                  },
                  onTryAtmosphere: () => _c.openReveal(vision.versionId),
                ),
                if (m.text.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _V7AydenGroup(children: [_V7AydenSpeech(text: m.text)]),
                ],
                const SizedBox(height: 14),
                _VisionActions(
                  onOpenReveal: () => _c.openReveal(vision.versionId),
                  onRefine: () {
                    _c.continueFromVision(vision.versionId);
                    _composerFocus.requestFocus();
                  },
                  onTryAtmosphere: () => _c.openReveal(vision.versionId),
                ),
                ...guidance,
              ],
            ),
          ];
        }

        // Later visions stay strictly chronological: Ayden answers, then shows.
        return [
          const _V7ChatGap(),
          _V7AydenGroup(
            children: [
              if (m.text.isNotEmpty) ...[
                _V7AydenSpeech(text: m.text),
                const SizedBox(height: 10),
              ],
              card,
              ...guidance,
            ],
          ),
        ];
    }
  }

  PwaVision? _visionFor(PwaState state, String? id) {
    for (final v in state.versions) {
      if (v.versionId == id) return v;
    }
    return null;
  }
}

/// §19 — the four canned quick actions under the current vision.
///
/// They are TEXT, nothing more. Tapping one is identical to typing it: both go
/// through `sendUserText` to the canonical conversational turn, which decides
/// whether a line is an opinion ask or a change request. Nothing here routes.
/// An earlier version of this comment claimed the first chip was advice-only
/// and the rest were refines — believing that is how "What do you think?" ended
/// up buying an image.
/// A top-level const cannot read a dictionary, so the chips became a function
/// of one. They are UI-OWNED suggestions (the backend's own `suggestions` take
/// precedence whenever it sends any), which is exactly why they must be
/// translated: a Khmer speaker offered four English chips is being asked to
/// type in English.
List<String> _defaultQuickActions(PwaL10n l) => [
  l.chipWhatDoYouThink,
  l.chipWarmer,
  l.chipMoreLight,
  // Room-NEUTRAL. These four sit under EVERY result, and "Open the kitchen"
  // under a terrace or a bathroom was a suggestion a person could tap and pay
  // for. All four still travel the same road — `sendUserText` → the canonical
  // turn — so what a suggestion CAN do is unchanged; only whether it makes
  // sense to offer it.
  l.chipCalmer,
];

/// §20 — a leading gold glyph per quick-action chip (matches the reference).
IconData _chipIcon(String label) {
  final l = label.toLowerCase();
  if (l.contains('light')) return Icons.wb_sunny_outlined;
  if (l.contains('kitchen')) return Icons.countertops_outlined;
  if (l.contains('atmosphere')) return Icons.image_outlined;
  if (l.contains('think') || l.contains('?')) {
    return Icons.chat_bubble_outline_rounded;
  }
  return Icons.auto_awesome; // "Make it warmer" & default → sparkle
}

// ════════════════════════════════════════════════════════════════════════════
// LEFT DESIGN CANVAS (§7–§11)
// ════════════════════════════════════════════════════════════════════════════

String _atmoNameOf(PwaState state, String? id) {
  for (final a in state.atmospheres) {
    if (a.id == id) return a.name;
  }
  return 'Ayden Signature';
}

// ── Atmosphere (§10) ─────────────────────────────────────────────────────────

// ════════════════════════════════════════════════════════════════════════════
// GLOBAL HEADER (§5)
// ════════════════════════════════════════════════════════════════════════════

class _V7GlobalHeader extends StatelessWidget {
  const _V7GlobalHeader({
    required this.compact,
    required this.onBack,
    required this.onProjects,
  });
  final bool compact;
  final VoidCallback onBack;
  final VoidCallback onProjects;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('av7-global-header'),
      height: compact ? 60 : 72,
      padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 32),
      decoration: const BoxDecoration(
        color: pwaCanvas,
        border: Border(bottom: BorderSide(color: pwaHairlineSoft)),
      ),
      // Back, then the wordmark, then the actions — the same order Create
      // uses. They used to be back / language / account / projects all packed
      // against the left edge with the wordmark shoved into whatever was
      // left, which on a phone put "AYDEN STUDIO" hard against the right
      // margin and read as a mistake.
      child: Row(
        children: [
          _V7BackButton(compact: compact, onTap: onBack),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'AYDEN STUDIO',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PwaType.cardTitle().copyWith(
                    fontSize: compact ? 15 : 17,
                    letterSpacing: pwaTracking(compact ? 1.2 : 2.0),
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  context.pwaL10n.workspaceLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: pwaEyebrow(color: pwaMuted, fontSize: compact ? 9 : 10),
                ),
              ],
            ),
          ),
          // The selector belongs in EVERY chrome bar, not only on Home: a
          // person who lands on a deep link, or who is mid-project, must be
          // able to change language without first navigating away.
          _V7ProjectsButton(onTap: onProjects),
          const PwaLanguageSwitcher(compact: true),
          const PwaAccountChip(),
          // No vision navigator here: the chronology IS the navigation, and the
          // prev/next stepper lives on the Full Reveal.
        ],
      ),
    );
  }
}

class _V7BackButton extends StatelessWidget {
  const _V7BackButton({required this.compact, required this.onTap});
  final bool compact;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.pwaL10n.backHome,
      child: Tooltip(
        message: context.pwaL10n.backHome,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 6 : 8,
                vertical: 8,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.arrow_back_rounded,
                    size: 20,
                    color: pwaInk,
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 12),
                    Text(
                      context.pwaL10n.backHome,
                      style: PwaType.cardSubtitle(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Discreet access to the My Projects library from the workspace header (§4 —
/// does not overload the header: an icon-only control with a tooltip).
class _V7ProjectsButton extends StatelessWidget {
  const _V7ProjectsButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.pwaL10n.myProjects,
      child: Tooltip(
        message: context.pwaL10n.myProjects,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            key: const ValueKey('av7-projects-button'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.grid_view_rounded, size: 19, color: pwaInk),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// CHAT PANEL (§12–§24)
// ════════════════════════════════════════════════════════════════════════════

/// Warm-modern living-room hint behind the ivory chat surface.
///
/// Hotfix — the conversation panel used to read as a flat white block against
/// the dark, premium Full Reveal on the left. This lays a softened warm-modern
/// living room UNDER a warm-ivory veil so the panel gains editorial richness and
/// sits in the same warm world as the reveal, while staying light, luminous and
/// perfectly legible: the image is only perceived through a 0.76–0.88 cream haze
/// (a hair thinner mid-panel so it breathes), and every message / card / composer
/// surface stays on its own opaque fill on top. Reused by desktop + mobile so the
/// treatment is identical and maintainable. Falls back to flat ivory if the asset
/// is unavailable (offline test harness).

/// The workspace header: which project, which direction, which vision. It reads
/// only what the library snapshot already stores — nothing derived, nothing new.
class _V7ConversationHeader extends StatelessWidget {
  const _V7ConversationHeader({required this.state});
  final PwaState state;

  @override
  Widget build(BuildContext context) {
    PwaProjectSnapshot? snap;
    for (final p in state.library) {
      if (p.projectId == state.activeProjectId) snap = p;
    }
    final title =
        state.activeTitleOverride ?? snap?.title ?? state.project.title;
    final bits = <String>[
      if ((snap?.roomLabel ?? '').isNotEmpty) snap!.roomLabel,
      if ((snap?.atmosphereLabel ?? '').isNotEmpty) snap!.atmosphereLabel,
      if (state.currentVision != null)
        context.pwaL10n.visionN(state.currentVision!.visionNumber),
    ];
    return Container(
      key: const ValueKey('av7-conversation-header'),
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: av7GoldDeep.withValues(alpha: 0.22)),
        ),
      ),
      child: Row(
        children: [
          const PwaLogoBadge(size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Named first: the screen must announce a conversation, not
                // read as a gallery caption.
                Text(
                  context.pwaL10n.architectLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: pwaEyebrow(color: pwaMuted, fontSize: 10.5),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PwaType.subsectionTitle().copyWith(height: 1.2),
                ),
                if (bits.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    bits.join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PwaType.caption(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Chat messages ────────────────────────────────────────────────────────────

class _V7ChatGap extends StatelessWidget {
  const _V7ChatGap();
  @override
  Widget build(BuildContext context) => const SizedBox(height: 14);
}

class _V7Avatar extends StatelessWidget {
  const _V7Avatar();
  @override
  Widget build(BuildContext context) => const PwaLogoBadge(size: 32);
}

/// §16 — Ayden message: avatar + ivory bubble, left aligned.
/// One Ayden intervention: the avatar once, then everything he says or shows in
/// a single indented column. Grouping is what makes a render read as part of the
/// conversation instead of a picture that happens to sit above some text.
class _V7AydenGroup extends StatelessWidget {
  const _V7AydenGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _V7Avatar(),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ],
    );
  }
}

/// What Ayden says — the bubble alone, already inside a group.
class _V7AydenSpeech extends StatelessWidget {
  const _V7AydenSpeech({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: pwaSurface,
          border: Border.all(color: pwaHairline),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(PwaGap.radius),
            bottomLeft: Radius.circular(PwaGap.radius),
            bottomRight: Radius.circular(PwaGap.radius),
          ),
        ),
        child: Text(text, style: PwaType.body().copyWith(fontSize: 15)),
      ),
    );
  }
}

/// A standalone Ayden line — a group holding a single bubble.
class _V7AydenBubble extends StatelessWidget {
  const _V7AydenBubble({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) =>
      _V7AydenGroup(children: [_V7AydenSpeech(text: text)]);
}

/// §17 — user message: right-aligned dark bubble.
class _V7UserBubble extends StatelessWidget {
  const _V7UserBubble({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: pwaInk,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(PwaGap.radius),
                topRight: Radius.circular(PwaGap.radius),
                bottomLeft: Radius.circular(PwaGap.radius),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Text(
              text,
              style: PwaType.body(color: pwaSurface).copyWith(fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }
}

/// §23 — inline generation state (no full-screen route).
class _V7InlineGenerating extends StatelessWidget {
  const _V7InlineGenerating({this.phases = kPwaRefinePhases});

  /// What Ayden is doing, decided by the turn that started the work.
  final List<String> phases;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _V7Avatar(),
        const SizedBox(width: 10),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: av7Surface,
              border: Border.all(color: av7Line),
              borderRadius: BorderRadius.circular(16),
            ),
            // A render takes about two minutes. One frozen line for all of it
            // read as a hung page, so the state moves through qualitative
            // phases — none of which can end the generation. Only the backend's
            // answer removes this message from the conversation.
            //
            // The ink is the SAME one `_V7AydenBubble` uses. Passing "on dark"
            // here painted white text onto this near-white bubble, so the copy
            // and the ellipsis vanished and the bubble showed one gold dot.
            child: PwaWorkingIndicator(
              phases: phases,
              foreground: const Color(0xFF2B211C),
            ),
          ),
        ),
      ],
    );
  }
}

/// The vision result in the chronology: a large render plus the three actions
/// that belong to it. Everything deeper — Before/After, atmospheres, vision
/// navigation — happens on `/reveal`, so the card stays a card.
class _V7VisionCard extends StatelessWidget {
  const _V7VisionCard({
    super.key,
    required this.vision,
    required this.atmosphereName,
    required this.highlighted,
    required this.maxImageHeight,
    required this.onOpenReveal,
    required this.onRefine,
    required this.onTryAtmosphere,
    this.showActions = true,
  });
  final PwaVision vision;
  final String atmosphereName;
  final bool highlighted;

  /// False on the FIRST vision, where the actions are placed after Ayden's
  /// line so the reading order is image, then commentary, then actions.
  final bool showActions;

  /// Ceiling for the render, derived from the space the thread actually has.
  final double maxImageHeight;
  final VoidCallback onOpenReveal;
  final VoidCallback onRefine;
  final VoidCallback onTryAtmosphere;

  @override
  Widget build(BuildContext context) {
    // THE IMAGE IS THE FIRST THING. It used to sit under a title strip inside
    // the card, so after a two-minute wait the first thing read was a label --
    // "Vision 1 . Warm Modern" -- and the render came second. The caption now
    // sits UNDER the image, where a caption belongs.
    //
    // There is no card around it either. A border and a fill turned the payoff
    // into a row in a feed; on the canvas the render is simply the largest
    // thing on the screen, with its own corners.
    return Column(
      key: const ValueKey('pwa-result-vision'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The render itself opens the Full Reveal -- the obvious gesture -- and
        // an explicit expand control makes that possibility visible.
        // Align first: the parent Column stretches its children, which gives a
        // TIGHT width that a bare ConstrainedBox cannot shrink below.
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: kPwaVisionMaxWidth,
              maxHeight: maxImageHeight,
            ),
            child: AnimatedContainer(
              duration: Av7Motion.component,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(PwaGap.radius),
                border: Border.all(
                  // Only ever drawn while a returned-from-Reveal highlight is
                  // running; at rest the render carries no frame at all.
                  color: highlighted ? pwaGold : Colors.transparent,
                  width: 2,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: AspectRatio(
                // THE RENDER'S OWN SHAPE. The engine returns 1536x1024, and a
                // 16:9 frame was cover-cropping about a tenth off the top and
                // bottom of the one image the person waited for. That the Full
                // Reveal shows it uncropped is not a reason for the result
                // screen to crop it.
                aspectRatio: kPwaRenderAspect,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Semantics(
                      button: true,
                      label:
                          context.pwaL10n.openVisionInReveal(vision.visionNumber, atmosphereName),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: onOpenReveal,
                          child: PwaStoredImage(
                            key: ValueKey('vision-card-${vision.versionId}'),
                            reference: vision.afterAsset,
                            placeholderColor: pwaWell,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: _ExpandRevealButton(onTap: onOpenReveal),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          context.pwaL10n
              .visionNWithAtmosphere(vision.visionNumber, atmosphereName),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: PwaType.bodyMuted(),
        ),
        if (showActions) ...[
          const SizedBox(height: 12),
          _VisionActions(
            onOpenReveal: onOpenReveal,
            onRefine: onRefine,
            onTryAtmosphere: onTryAtmosphere,
          ),
        ],
      ],
    );
  }
}

/// What can be done with a vision: open it, refine it, or try another
/// direction. Its own widget because the FIRST result places it after Ayden's
/// line rather than directly under the render — image, commentary, actions.
class _VisionActions extends StatelessWidget {
  const _VisionActions({
    required this.onOpenReveal,
    required this.onRefine,
    required this.onTryAtmosphere,
  });

  final VoidCallback onOpenReveal;
  final VoidCallback onRefine;
  final VoidCallback onTryAtmosphere;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _VisionAction(
              icon: Icons.open_in_full_rounded,
              label: context.pwaL10n.viewFullReveal,
              primary: true,
              maxWidth: c.maxWidth,
              onTap: onOpenReveal,
            ),
            _VisionAction(
              icon: Icons.tune_rounded,
              label: context.pwaL10n.refineThis,
              maxWidth: c.maxWidth,
              onTap: onRefine,
            ),
            _VisionAction(
              icon: Icons.auto_awesome,
              label: context.pwaL10n.tryAnotherAtmosphere,
              maxWidth: c.maxWidth,
              onTap: onTryAtmosphere,
            ),
          ],
        ),
      );
}

/// One action attached to a vision card. The primary one is filled; the others
/// are outlined, so the card reads as a result with a clear next step rather
/// than a toolbar.
class _VisionAction extends StatelessWidget {
  const _VisionAction({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.maxWidth,
    this.primary = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// The width of the row these pills wrap inside — see the note on the
  /// constraint below.
  final double maxWidth;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    // The product's own two buttons: the primary is the ink pill, the others
    // are hairline pills. Gold is left to the accents it marks -- a selection,
    // a glyph -- rather than carrying a CTA.
    final fg = primary ? pwaSurface : pwaInk;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: primary ? pwaInk : pwaSurface,
        borderRadius: BorderRadius.circular(PwaGap.radiusPill),
        child: InkWell(
          borderRadius: BorderRadius.circular(PwaGap.radiusPill),
          onTap: onTap,
          child: Container(
            height: 40,
            // See _V7QuickActions: a Wrap gives loose constraints, so without
            // a ceiling a long French or Khmer label overflows instead of
            // ellipsizing.
            constraints: BoxConstraints(maxWidth: maxWidth),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PwaGap.radiusPill),
              border: primary ? null : Border.all(color: pwaHairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: primary ? pwaSurface : pwaGold),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PwaType.button(color: fg).copyWith(fontSize: 13.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The explicit "make this bigger" affordance on a vision. Same destination as
/// tapping the image and as "View full reveal" — one routing call, three doors.
class _ExpandRevealButton extends StatefulWidget {
  const _ExpandRevealButton({required this.onTap});
  final VoidCallback onTap;
  @override
  State<_ExpandRevealButton> createState() => _ExpandRevealButtonState();
}

class _ExpandRevealButtonState extends State<_ExpandRevealButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.pwaL10n.openFullReveal,
      child: Tooltip(
        message: context.pwaL10n.openFullReveal,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          cursor: SystemMouseCursors.click,
          child: Material(
            color: const Color(
              0xFF1E161E,
            ).withValues(alpha: _hover ? 0.92 : 0.82),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('av7-vision-expand'),
              onTap: widget.onTap,
              // A comfortable 40px touch target on every viewport.
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  Icons.open_in_full_rounded,
                  size: 21,
                  color: _hover ? pwaGold : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Refining Vision N" — the discreet context carried back from the Full Reveal.
/// It states what the next message is about; it sends nothing and can be
/// dropped without touching the vision.
class _V7RefineContextBar extends StatelessWidget {
  const _V7RefineContextBar({required this.vision, required this.onCancel});
  final PwaVision vision;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('av7-refine-context'),
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: av7GoldWash,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: av7GoldDeep.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.tune_rounded, size: 14, color: av7GoldDeep),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              context.pwaL10n.refiningVisionN(vision.visionNumber),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: av7Sans(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: av7GoldDeep,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Semantics(
            button: true,
            label: context.pwaL10n.cancelRefinement,
            child: Tooltip(
              message: context.pwaL10n.cancelRefinement,
              child: InkWell(
                key: const ValueKey('av7-refine-context-cancel'),
                customBorder: const CircleBorder(),
                onTap: onCancel,
                child: const SizedBox(
                  width: 28,
                  height: 28,
                  child: Icon(
                    Icons.close_rounded,
                    size: 15,
                    color: av7GoldDeep,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The single line that turns a result into a conversation.
class _V7ChangePrompt extends StatelessWidget {
  const _V7ChangePrompt();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 42),
    child: Text(
      context.pwaL10n.whatWouldYouLikeToChange,
      style: PwaType.cardTitle(),
    ),
  );
}

/// §20 — gold quick-action chips.
class _V7QuickActions extends StatelessWidget {
  const _V7QuickActions({required this.chips, required this.onTap});
  final List<String> chips;
  final ValueChanged<String> onTap;
  @override
  Widget build(BuildContext context) {
    // A Wrap hands each child LOOSE constraints, so a Row inside one sizes to
    // its natural width and a long label simply runs off the screen — there is
    // nothing for `Flexible` to shrink against. French does exactly that:
    // "Rends-le plus chaleureux" overflowed a 390px phone by 9px. The ceiling
    // has to come from the row the pills are laid out in, so it is measured
    // once and handed down.
    return LayoutBuilder(
      builder: (context, c) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final chip in chips)
            Material(
              color: pwaSurface,
              borderRadius: BorderRadius.circular(PwaGap.radiusPill),
              child: InkWell(
                borderRadius: BorderRadius.circular(PwaGap.radiusPill),
                onTap: () => onTap(chip),
                child: Container(
                  height: 38,
                  constraints: BoxConstraints(maxWidth: c.maxWidth),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(PwaGap.radiusPill),
                    border: Border.all(color: pwaHairline),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_chipIcon(chip), size: 14, color: pwaGold),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          chip,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              PwaType.cardSubtitle().copyWith(fontSize: 13.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// §21 — refine confirmation card rendered inline in the chronology.
class _V7RefineConfirmCard extends StatelessWidget {
  const _V7RefineConfirmCard({
    required this.state,
    required this.controller,
    required this.messageId,
    required this.instruction,
    this.advisoryVerdict,
  });
  final PwaState state;
  final PwaController controller;
  final String messageId;
  final String instruction;

  /// The advisor's verdict, when this card follows an objection.
  final String? advisoryVerdict;

  @override
  Widget build(BuildContext context) {
    final nextN = state.versionCount + 1;
    final busy = state.generating;
    // RED is a refusal, not a warning. Mobile's contract is explicit — "YELLOW →
    // [Try anyway] + [Edit request] ; RED → [Edit request] SEULEMENT (jamais
    // forçable, aucun confirm=true possible depuis une carte RED)" — and its
    // handler refuses one anyway (chat_screen.dart:1811). This card offered
    // "Create vision" on every verdict, which let a person pay for a render the
    // engine had already judged wrong. On red the override is not disabled, it
    // is absent: a greyed button still says "this is available to you".
    final isRed = advisoryVerdict == 'red';
    return Padding(
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: pwaWell,
          borderRadius: BorderRadius.circular(PwaGap.radius),
          border: Border.all(color: pwaGold.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.pwaL10n.applyThisChange,
              style: PwaType.cardTitle(),
            ),
            const SizedBox(height: 6),
            Text(
              // The user's own words, quoted back. Ayden's opinion on this
              // change belongs to the canonical advisor, which answers on the
              // backend — never to a template composed here.
              '“$instruction”',
              style: PwaType.bodyMuted().copyWith(fontStyle: FontStyle.italic),
            ),
            if (!isRed) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 14, color: pwaGold),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      context.pwaL10n.createsVisionUsesSpace(nextN),
                      style: PwaType.caption(),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => controller.dismissRefine(messageId),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: pwaInk,
                      side: const BorderSide(color: pwaHairline, width: 1.5),
                      shape: const StadiumBorder(),
                    ),
                    // On a refusal the only action left is to rephrase, so the
                    // button says that rather than "Cancel".
                    child: Text(isRed ? context.pwaL10n.editRequest : context.pwaL10n.cancel),
                  ),
                ),
                if (!isRed) ...[
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    // Consume the offer FIRST (strip pendingRefine) so the card
                    // collapses to plain advice and cannot be re-fired into a
                    // duplicate child, then create exactly one child vision.
                    onPressed: busy
                        ? null
                        : () {
                            controller.dismissRefine(messageId);
                            // The person read the objection and chose to go on:
                            // that is exactly what confirm carries. Without it
                            // the advisor simply objects again and the button
                            // does nothing — mobile sends refineConfirm:true
                            // here (chat_screen.dart:1813-1817).
                            controller.applyRefine(instruction, confirm: true);
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: pwaInk,
                      foregroundColor: pwaSurface,
                      shape: const StadiumBorder(),
                    ),
                    child: Text(busy ? context.pwaL10n.creating : context.pwaL10n.createVision),
                  ),
                ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// §24 — composer + disclaimer, on the V7 ivory palette (gold #D3B064 send
/// button + focused border). Deliberately its OWN widget so the frozen
/// fast-path `PwaComposer` (which uses the muted #C8A86A) is untouched.
class _V7Composer extends StatefulWidget {
  const _V7Composer({
    required this.enabled,
    required this.onSend,
    this.focusNode,
  });
  final bool enabled;
  final ValueChanged<String> onSend;

  /// Supplied by the screen when it needs to hand focus to the composer.
  final FocusNode? focusNode;
  @override
  State<_V7Composer> createState() => _V7ComposerState();
}

class _V7ComposerState extends State<_V7Composer> {
  final _controller = TextEditingController();
  FocusNode? _own;

  FocusNode get _focus => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void dispose() {
    _controller.dispose();
    _own?.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;
    widget.onSend(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const ValueKey('av7-integrated-composer'),
      // No fill of its own: the composer belongs to the glass plate, it is not
      // a band painted across the foot of the window.
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: 48,
                      maxHeight: 112,
                    ),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      enabled: widget.enabled,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      style: PwaType.body().copyWith(fontSize: 15),
                      cursorColor: pwaGold,
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        // The SAME field Step 4 uses: well, hairline, gold ring
                        // on focus. Continuing a session and briefing one
                        // should not feel like two different products.
                        fillColor: pwaWell,
                        hintText: context.pwaL10n.askAydenAnything,
                        hintStyle: PwaType.bodyMuted(color: pwaFaint)
                            .copyWith(fontSize: 15),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 15,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(PwaGap.radiusInput),
                          borderSide: const BorderSide(color: pwaHairline),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(PwaGap.radiusInput),
                          borderSide:
                              const BorderSide(color: pwaGold, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _V7SendButton(enabled: widget.enabled, onTap: _send),
              ],
            ),
            const SizedBox(height: 7),
            Text(context.pwaL10n.aydenDisclaimer, style: PwaType.caption()),
          ],
        ),
      ),
    );
  }
}

class _V7SendButton extends StatelessWidget {
  const _V7SendButton({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.pwaL10n.sendMessage,
      child: Material(
        color: enabled ? pwaInk : pwaWell,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              Icons.send_rounded,
              size: 20,
              color: enabled ? pwaSurface : pwaFaint,
            ),
          ),
        ),
      ),
    );
  }
}
