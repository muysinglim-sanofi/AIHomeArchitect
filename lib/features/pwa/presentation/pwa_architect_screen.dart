/// Batch 2.2 V7 — the definitive Ayden Architect design workspace.
///
/// Reference: `references/REF-PWA-ARCHITECT-FINAL-V7.png`. Three principal areas
/// only: a compact global Studio header; a dominant Full Reveal + full-width
/// Atmosphere selector (left); and a real chronological Ayden Architect chat
/// (right) that IS the version history. There is NO separate Versions column /
/// filmstrip / sheet — every generated vision lives inline in the chat, and the
/// "Vision N of M" + prev/next controls PREVIEW existing visions (no version
/// created). Fully offline & mocked — no backend, no debit.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pwa_controller.dart';
import '../domain/pwa_models.dart';
import '../domain/pwa_project.dart';
import 'pwa_architect_tokens.dart';
import 'pwa_brand.dart';
import 'pwa_stored_image.dart';

// V7 responsive tiers (§4). Local to the Architect so the shared
// `pwaFormFactorForWidth` (used by the frozen entry screen) stays untouched.
bool _isMobileW(double w) => w < 768;

/// Maximum measure of the conversation column. Wide screens buy comfort, not a
/// wider line of text.
const double kPwaChatColumnMax = 880;

/// Maximum width of the desktop chat workspace surface that holds the header,
/// the thread and the composer together.
const double kPwaChatShellMax = 1080;

/// The desktop conversation plate: LIGHT warm glass — white-ivory, barely
/// there. The room behind is the surface; the plate only warms and diffuses it.
const Color kPwaGlassTop = Color(0xFFFFFBF7);
const Color kPwaGlassBottom = Color(0xFFF6E8D8);

/// The warm dark accent used on the NARROW-window layout, where the chat sits
/// straight on the cream veil and the pills / composer bring their own contrast.
/// Kept separate from the plate so lightening desktop cannot touch mobile.
const Color kPwaWarmAccent = Color(0xFF211711);

/// The desktop plate, in numbers. These are the whole fix: at 0.44 the plate
/// was still a milky rectangle whatever the blur was set to, because opacity —
/// not blur — is what hides a room. At 0.18/0.10 the sofa reads through the
/// middle of the glass. Do not raise them to "improve contrast": legibility
/// belongs to the bubbles, the Vision card and the input field, each of which
/// carries its own surface.
const double kPwaDesktopBackdropBlur = 4.5;
const double kPwaDesktopBackdropVeilAlpha = 0.07;

const double kPwaDesktopGlassBlur = 18.0;
const double kPwaDesktopGlassTopAlpha = 0.18;
const double kPwaDesktopGlassBottomAlpha = 0.10;
const double kPwaDesktopGlassBorderAlpha = 0.34;

/// How much the room behind the NARROW-window layout is softened. Desktop has
/// its own blur above; this one is mobile's and must not follow it.
const double kPwaBackdropBlur = 6;

/// Gold used for the plate edge, the divider and the pill outlines.
const Color kPwaGlassEdge = Color(0xFFD7B968);

/// What Ayden says stays cream — the bubbles carry the legibility.
const Color kPwaWarmBubble = Color(0xFFFFF7EC);

/// Ink on the warm dark accents of the narrow-window layout.
const Color kPwaOnGlass = Color(0xFFF3E9DC);
const Color kPwaOnGlassSoft = Color(0xB3F3E9DC);

/// Ink on the light desktop plate.
const Color kPwaOnPlate = av7Ink;
const Color kPwaOnPlateSoft = Color(0xC2201B17);

/// A hairline on glass: white, barely there. A gold or dark rule reads as a
/// drawn border and gives the plate back the "panel" look this pass removed.
class _V7GlassDivider extends StatelessWidget {
  const _V7GlassDivider();

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: Colors.white.withValues(alpha: 0.22));
}

/// The Warm Modern room, full-bleed, painted FIRST so the glass above it has
/// something to refract. It is the bottom layer of the desktop Stack — nothing
/// between it and the plate is allowed to paint a fill.
class _DesktopWarmModernBackground extends StatelessWidget {
  const _DesktopWarmModernBackground();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      key: const ValueKey('av7-warm-modern-backdrop'),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The scale hides the transparent fringe a blur leaves at the edges.
          Transform.scale(
            scale: 1.04,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: kPwaDesktopBackdropBlur,
                sigmaY: kPwaDesktopBackdropBlur,
              ),
              child: Image.asset(
                _kV7ChatBackdrop,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, _, _) => const ColoredBox(color: av7DarkBg),
              ),
            ),
          ),
          ColoredBox(
            color: const Color(
              0xFF160F0B,
            ).withValues(alpha: kPwaDesktopBackdropVeilAlpha),
          ),
        ],
      ),
    );
  }
}

/// The desktop conversation plate — ONE layer of light glass, and nothing else.
///
/// This replaces the old brown panel outright rather than tinting it: a single
/// leftover opaque fill anywhere between the photo and here cancels the whole
/// effect, so the composition is deliberately flat — shadow, clip, backdrop
/// filter, one translucent gradient, a transparent [Material] for the ink.
class _DesktopLightGlassChatShell extends StatelessWidget {
  const _DesktopLightGlassChatShell({required this.child});

  final Widget child;

  static const BorderRadius _radius = BorderRadius.all(Radius.circular(24));

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('av7-glass-chat-shell'),
      decoration: BoxDecoration(
        borderRadius: _radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 36,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: _radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: kPwaDesktopGlassBlur,
            sigmaY: kPwaDesktopGlassBlur,
          ),
          blendMode: BlendMode.srcOver,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: _radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  kPwaGlassTop.withValues(alpha: kPwaDesktopGlassTopAlpha),
                  kPwaGlassBottom.withValues(
                    alpha: kPwaDesktopGlassBottomAlpha,
                  ),
                ],
              ),
              border: Border.all(
                color: Colors.white.withValues(
                  alpha: kPwaDesktopGlassBorderAlpha,
                ),
                width: 1,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: _V7OnLightGlass(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Marks the subtree that paints on the light desktop plate. The feed, the
/// guidance, the pills and the composer are shared verbatim with the narrow
/// window, so the surface tells them which ink to use instead of every private
/// builder carrying a `light:` argument down the tree.
class _V7OnLightGlass extends InheritedWidget {
  const _V7OnLightGlass({required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_V7OnLightGlass>() != null;

  @override
  bool updateShouldNotify(_V7OnLightGlass oldWidget) => false;
}

/// Left gutter of the conversation grid — the width of the Ayden avatar plus its
/// gap. EVERY Ayden-side element starts here: bubbles, vision card, guidance and
/// quick actions, so the thread reads on one axis instead of three.
const double kPwaChatGutter = 42;

/// The render IS the payoff of Generate: it takes nearly the whole conversation
/// column. Capped in height so the actions, Ayden's reply and the composer still
/// belong to the same screen.
const double kPwaVisionMaxWidth = 820;
const double kPwaVisionMaxHeight = 470;

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
      // Transparent: the Warm Modern photo is the bottom layer, and no surface
      // between it and the glass is allowed to paint over it.
      backgroundColor: Colors.transparent,
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

    if (!desktop) {
      // Mobile / tablet keep the single flowing column that already works.
      return Column(
        children: [
          _V7GlobalHeader(
            compact: mobile,
            onBack: _c.openHome,
            onProjects: _c.openLibrary,
          ),
          Expanded(
            child: _V7ChatBackdrop(
              child: Center(
                child: SizedBox(width: columnW, child: feed()),
              ),
            ),
          ),
          Center(
            child: SizedBox(width: columnW, child: composer()),
          ),
        ],
      );
    }

    // The mandatory hierarchy: the room is painted into the SAME Stack, BELOW
    // the plate, so the BackdropFilter has real pixels to sample. Nothing in
    // between carries a fill.
    return Stack(
      fit: StackFit.expand,
      children: [
        const _DesktopWarmModernBackground(),
        Column(
          children: [
            _V7GlobalHeader(
              compact: false,
              onBack: _c.openHome,
              onProjects: _c.openLibrary,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: kPwaChatShellMax,
                    ),
                    child: _DesktopLightGlassChatShell(
                      child: Center(
                        child: SizedBox(
                          width: columnW,
                          child: Column(
                            children: [
                              _V7ConversationHeader(state: state),
                              const _V7GlassDivider(),
                              Expanded(child: feed()),
                              const _V7GlassDivider(),
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: composer(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
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
        return const [_V7ChatGap(), _V7InlineGenerating()];
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
          onRefine: () =>
              _c.sendUserText('Refine Vision ${vision.visionNumber}'),
          onTryAtmosphere: () => _c.openReveal(vision.versionId),
        );
        // Guidance: after a result nobody should wonder what to do next.
        final guidance = <Widget>[
          if (isCurrentReveal && !state.generating) ...[
            const SizedBox(height: 14),
            const _V7ChangePrompt(),
            const SizedBox(height: 10),
            _V7QuickActions(chips: _defaultQuickActions, onTap: _onQuickAction),
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
                card,
                if (m.text.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _V7AydenGroup(children: [_V7AydenSpeech(text: m.text)]),
                ],
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

/// §19 — the four canned quick actions under the current vision. The first is an
/// opinion ask (→ advice, text only); the rest are change requests (→ refine).
const List<String> _defaultQuickActions = [
  'What do you think?',
  'Make it warmer',
  'More natural light',
  'Open the kitchen',
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
        color: av7HeaderBlack,
        border: Border(bottom: BorderSide(color: Color(0x29D3B064))),
      ),
      child: Row(
        children: [
          _V7BackButton(compact: compact, onTap: onBack),
          _V7ProjectsButton(onTap: onProjects),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'AYDEN STUDIO',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: av7Sans(
                    fontSize: compact ? 16 : 22,
                    fontWeight: FontWeight.w400,
                    color: av7OnDark,
                    letterSpacing: compact ? 3.0 : 7.0,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'DESIGN WORKSPACE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: av7Eyebrow(
                    fontSize: compact ? 8.5 : 10,
                    letterSpacing: 4.0,
                  ),
                ),
              ],
            ),
          ),
          // No vision navigator here: the chronology IS the navigation, and the
          // prev/next stepper lives on the Full Reveal.
          SizedBox(width: compact ? 36 : 96),
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
      label: 'Back home',
      child: Tooltip(
        message: 'Back home',
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
                    color: av7OnDark,
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 12),
                    Text(
                      'Back home',
                      style: av7Sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: av7OnDark,
                      ),
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
      label: 'My Projects',
      child: Tooltip(
        message: 'My Projects',
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            key: const ValueKey('av7-projects-button'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.grid_view_rounded, size: 19, color: av7OnDark),
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
const String _kV7ChatBackdrop = 'assets/atmospheres/ftue/ftue_warm_modern.jpg';

class _V7ChatBackdrop extends StatelessWidget {
  const _V7ChatBackdrop({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: const ValueKey('av7-warm-modern-backdrop'),
      fit: StackFit.expand,
      children: [
        // Softened, never erased: the room must still read as a room behind
        // the glass — that is the whole point of the surface.
        Positioned.fill(
          child: ImageFiltered(
            // Just enough to sit behind glass: the sofa, the lamps, the wood
            // and the shelves all have to stay recognisable.
            imageFilter: ui.ImageFilter.blur(
              sigmaX: kPwaBackdropBlur,
              sigmaY: kPwaBackdropBlur,
            ),
            child: Image.asset(
              _kV7ChatBackdrop,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (_, _, _) => const ColoredBox(color: av7Canvas),
            ),
          ),
        ),
        // 2) Warm-ivory veil (editorial paper). Keeps the surface light and the
        //    text crisp; slightly thinner through the middle so the image is
        //    clearly, but gently, present — never a flat block, never busy.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  av7Canvas.withValues(alpha: 0.86),
                  av7Canvas.withValues(alpha: 0.76),
                  av7Canvas.withValues(alpha: 0.88),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ),
        // 3) The conversation, on its own opaque surfaces.
        child,
      ],
    );
  }
}

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
        'Vision ${state.currentVision!.visionNumber}',
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
                  'AYDEN ARCHITECT',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: av7Eyebrow(fontSize: 10.5, letterSpacing: 2.2),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: av7Sans(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    color: kPwaOnGlass,
                    height: 1.2,
                  ),
                ),
                if (bits.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    bits.join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: av7Sans(fontSize: 12.5, color: kPwaOnGlassSoft),
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
          color: kPwaWarmBubble.withValues(alpha: 0.94),
          border: Border.all(color: av7Line),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Text(
          text,
          style: av7Sans(fontSize: 15, height: 1.47, color: av7Ink),
        ),
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
            decoration: BoxDecoration(
              color: const Color(0xFF2B211C).withValues(alpha: 0.94),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Text(
              text,
              style: av7Sans(fontSize: 15, height: 1.47, color: av7UserText),
            ),
          ),
        ),
      ],
    );
  }
}

/// §23 — inline generation state (no full-screen route).
class _V7InlineGenerating extends StatelessWidget {
  const _V7InlineGenerating();
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _V7Avatar(),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: av7Surface,
            border: Border.all(color: av7Line),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: av7Gold,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Ayden is creating your next vision…',
                style: av7Sans(fontSize: 14, color: av7Muted),
              ),
            ],
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
  });
  final PwaVision vision;
  final String atmosphereName;
  final bool highlighted;

  /// Ceiling for the render, derived from the space the thread actually has.
  final double maxImageHeight;
  final VoidCallback onOpenReveal;
  final VoidCallback onRefine;
  final VoidCallback onTryAtmosphere;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Av7Motion.component,
      decoration: BoxDecoration(
        color: kPwaWarmBubble,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted ? av7Gold : av7Line,
          width: highlighted ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Text(
              'Vision ${vision.visionNumber} · $atmosphereName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: av7Sans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: av7Ink,
              ),
            ),
          ),
          // The render itself opens the Full Reveal — the obvious gesture — and
          // an explicit expand control makes that possibility visible.
          // Big and edge-to-edge in the column: `cover` fills the frame, so a
          // landscape render is never boxed between two charcoal bands. The
          // Full Reveal remains the place to see the image uncropped.
          // Align first: the card's Column stretches its children, which gives a
          // TIGHT width that a bare ConstrainedBox cannot shrink below.
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: kPwaVisionMaxWidth,
                maxHeight: maxImageHeight,
              ),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Semantics(
                      button: true,
                      label:
                          'Open Vision ${vision.visionNumber}, $atmosphereName, in the Full Reveal',
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: onOpenReveal,
                          child: PwaStoredImage(
                            key: ValueKey('vision-card-${vision.versionId}'),
                            reference: vision.afterAsset,
                            placeholderColor: av7RevealRaised,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _VisionAction(
                  icon: Icons.open_in_full_rounded,
                  label: 'View full reveal',
                  primary: true,
                  onTap: onOpenReveal,
                ),
                _VisionAction(
                  icon: Icons.tune_rounded,
                  label: 'Refine this',
                  onTap: onRefine,
                ),
                _VisionAction(
                  icon: Icons.auto_awesome,
                  label: 'Try another atmosphere',
                  onTap: onTryAtmosphere,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One action attached to a vision card. The primary one is filled; the others
/// are outlined, so the card reads as a result with a clear next step rather
/// than a toolbar.
class _VisionAction extends StatelessWidget {
  const _VisionAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? av7Ink : av7InkSecondary;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: primary ? av7Gold : av7Surface,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: primary
                  ? null
                  : Border.all(color: av7GoldDeep.withValues(alpha: 0.34)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: primary ? av7Ink : av7GoldDeep),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: av7Sans(
                      fontSize: 12,
                      fontWeight: primary ? FontWeight.w700 : FontWeight.w500,
                      color: fg,
                    ),
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
      label: 'Open full reveal',
      child: Tooltip(
        message: 'Open full reveal',
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          cursor: SystemMouseCursors.click,
          child: Material(
            color: const Color(
              0xFF211914,
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
                  color: _hover ? av7Gold : Colors.white,
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
              'Refining Vision ${vision.visionNumber}',
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
            label: 'Cancel refinement',
            child: Tooltip(
              message: 'Cancel refinement',
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
      'What would you like to change?',
      style: av7Sans(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: kPwaOnGlass,
      ),
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
    final light = _V7OnLightGlass.of(context);
    final edge = light ? av7GoldDeep : kPwaGlassEdge;
    return Padding(
      padding: EdgeInsets.zero,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in chips)
            Material(
              color: light
                  ? const Color(0xFFFFFBF8).withValues(alpha: 0.66)
                  : kPwaWarmAccent.withValues(alpha: 0.46),
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => onTap(c),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: edge.withValues(alpha: 0.40)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_chipIcon(c), size: 14, color: edge),
                      const SizedBox(width: 6),
                      Text(
                        c,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: av7Sans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: light ? kPwaOnPlate : kPwaOnGlass,
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
  });
  final PwaState state;
  final PwaController controller;
  final String messageId;
  final String instruction;
  @override
  Widget build(BuildContext context) {
    final nextN = state.versionCount + 1;
    final busy = state.generating;
    final light = _V7OnLightGlass.of(context);
    final ink = light ? kPwaOnPlate : kPwaOnGlass;
    final soft = light ? kPwaOnPlateSoft : kPwaOnGlassSoft;
    final edge = light ? av7GoldDeep : kPwaGlassEdge;
    return Padding(
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: light
              ? const Color(0xFFFFFBF8).withValues(alpha: 0.72)
              : kPwaWarmAccent.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: edge.withValues(alpha: 0.40)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Apply this change?',
              style: av7Sans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              controller.refineSummaryText(instruction),
              style: av7Sans(fontSize: 13, height: 1.46, color: soft),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 14, color: av7GoldDeep),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Creates Vision $nextN · Uses 1 Space',
                    style: av7Sans(fontSize: 11.5, color: soft),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => controller.dismissRefine(messageId),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ink,
                      side: BorderSide(color: edge.withValues(alpha: 0.4)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
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
                            controller.applyRefine(instruction);
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: av7Gold,
                      foregroundColor: av7Ink,
                    ),
                    child: Text(busy ? 'Creating…' : 'Create vision'),
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
    final light = _V7OnLightGlass.of(context);
    // The FIELD carries its own light surface, so its ink is dark on desktop.
    // The disclaimer sits bare on the plate, so it keeps the light ink.
    final ink = light ? kPwaOnPlate : kPwaOnGlass;
    final fieldSoft = light ? kPwaOnPlateSoft : kPwaOnGlassSoft;
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
                      style: av7Sans(fontSize: 15, color: ink, height: 1.4),
                      cursorColor: light ? av7GoldDeep : av7Gold,
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: light
                            ? const Color(0xFFFFFBF8).withValues(alpha: 0.68)
                            : kPwaWarmAccent.withValues(alpha: 0.48),
                        hintText: 'Ask Ayden anything…',
                        hintStyle: av7Sans(fontSize: 15, color: fieldSoft),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 15,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(
                            color: light
                                ? Colors.white.withValues(alpha: 0.46)
                                : kPwaGlassEdge.withValues(alpha: 0.34),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(
                            color: light ? av7GoldDeep : av7Gold,
                            width: 1.5,
                          ),
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
            Text(
              'Ayden can make mistakes. Always review design details.',
              style: av7Sans(fontSize: 10.5, color: kPwaOnGlassSoft),
            ),
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
      label: 'Send message',
      child: Material(
        color: enabled ? av7Gold : av7Line,
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
              color: enabled ? av7Ink : av7MutedSoft,
            ),
          ),
        ),
      ),
    );
  }
}
