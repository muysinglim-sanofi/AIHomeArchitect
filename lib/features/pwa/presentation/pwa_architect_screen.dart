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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pwa_controller.dart';
import '../domain/pwa_models.dart';
import 'pwa_architect_tokens.dart';
import 'pwa_brand.dart';
import 'pwa_widgets.dart';

// V7 responsive tiers (§4). Local to the Architect so the shared
// `pwaFormFactorForWidth` (used by the frozen entry screen) stays untouched.
bool _isDesktopW(double w) => w >= 1200;
bool _isMobileW(double w) => w < 768;

class PwaArchitectScreen extends ConsumerStatefulWidget {
  const PwaArchitectScreen({super.key});

  @override
  ConsumerState<PwaArchitectScreen> createState() => _PwaArchitectScreenState();
}

class _PwaArchitectScreenState extends ConsumerState<PwaArchitectScreen> {
  final _chatScroll = ScrollController();
  final Map<String, GlobalKey> _visionKeys = {};
  // §13 — a stable target for the mobile/tablet Full Reveal so a Vision card can
  // scroll the single feed back up to it.
  final _mobileRevealKey = GlobalKey(debugLabel: 'mobile-full-reveal');
  String? _highlightVersionId;
  Timer? _highlightTimer;
  bool _revealPulse = false; // §16 — temporary Full-Reveal focus emphasis
  Timer? _revealPulseTimer;

  PwaController get _c => ref.read(pwaControllerProvider.notifier);

  GlobalKey _visionKey(String versionId) => _visionKeys.putIfAbsent(
    versionId,
    () => GlobalKey(debugLabel: versionId),
  );

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

  /// §12/§13 — mobile/tablet: preview a Vision, then scroll the single feed back
  /// up to the Full Reveal (it is the feed's first item) and pulse its frame.
  /// Creates no version, changes no lineage.
  Future<void> _openVisionInReveal(String versionId) async {
    _c.previewVision(versionId);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_chatScroll.hasClients) return;
    final reduce = MediaQuery.of(context).disableAnimations;
    // Prefer the precise Full-Reveal target (below the sticky header); fall back
    // to the top of the feed (the reveal is its first item).
    final ctx = _mobileRevealKey.currentContext;
    if (ctx != null && ctx.mounted) {
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.0,
        duration: reduce ? Duration.zero : Av7Motion.page,
        curve: Av7Motion.curve,
      );
    } else if (reduce) {
      _chatScroll.jumpTo(0);
    } else {
      await _chatScroll.animateTo(
        0,
        duration: Av7Motion.page,
        curve: Av7Motion.curve,
      );
    }
    _pulseReveal();
  }

  void _pulseReveal() {
    if (!mounted) return;
    final reduce = MediaQuery.of(context).disableAnimations;
    _revealPulseTimer?.cancel();
    setState(() => _revealPulse = true);
    _revealPulseTimer = Timer(Duration(milliseconds: reduce ? 250 : 800), () {
      if (mounted) setState(() => _revealPulse = false);
    });
  }

  void _prevVision() {
    _c.previewPrevious();
    final id = ref.read(pwaControllerProvider).previewedVision?.versionId;
    if (id != null) _revealVision(id);
  }

  void _nextVision() {
    _c.previewNext();
    final id = ref.read(pwaControllerProvider).previewedVision?.versionId;
    if (id != null) _revealVision(id);
  }

  void _onQuickAction(String action) => _c.sendUserText(action);

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _revealPulseTimer?.cancel();
    _chatScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(pwaControllerProvider.select((s) => s.messages.length), (_, _) {
      _scrollChatToBottom();
    });
    final state = ref.watch(pwaControllerProvider);

    return Scaffold(
      backgroundColor: av7DarkBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            return _isDesktopW(c.maxWidth)
                ? _desktop(context, state, c.maxWidth, c.maxHeight)
                : _stacked(context, state, c.maxWidth, c.maxHeight);
          },
        ),
      ),
    );
  }

  // ── Desktop — two-pane studio (§5–§13) ──────────────────────────────────────

  Widget _desktop(BuildContext context, PwaState state, double w, double h) {
    const headerH = 72.0;
    final bodyH = h - headerH;
    final chatW = (w * 0.335).clamp(440.0, 520.0);

    return Column(
      children: [
        _V7GlobalHeader(
          compact: false,
          shownNumber: state.previewedIndex + 1,
          total: state.versionCount,
          hasPrev: state.hasPreviousVision,
          hasNext: state.hasNextVision,
          onBack: _c.returnToStudio,
          onPrev: _prevVision,
          onNext: _nextVision,
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // LEFT — dominant design canvas on warm charcoal.
              Expanded(
                child: _V7DesignCanvas(
                  state: state,
                  controller: _c,
                  bodyHeight: bodyH,
                ),
              ),
              // RIGHT — Ayden Architect conversation on warm ivory (§12).
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 16, 16),
                child: SizedBox(
                  width: chatW,
                  child: _V7ChatPanel(
                    state: state,
                    scroll: _chatScroll,
                    shownNumber: state.previewedIndex + 1,
                    total: state.versionCount,
                    hasPrev: state.hasPreviousVision,
                    hasNext: state.hasNextVision,
                    onPrev: _prevVision,
                    onNext: _nextVision,
                    messages: _chatMessages(state, stacked: false),
                    onSend: _c.sendUserText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Tablet + mobile — one chronological feed (§28–§29) ──────────────────────

  Widget _stacked(BuildContext context, PwaState state, double w, double h) {
    final mobile = _isMobileW(w);
    return Column(
      children: [
        _V7GlobalHeader(
          compact: true,
          shownNumber: state.previewedIndex + 1,
          total: state.versionCount,
          hasPrev: state.hasPreviousVision,
          hasNext: state.hasNextVision,
          onBack: _c.returnToStudio,
          onPrev: _prevVision,
          onNext: _nextVision,
        ),
        Expanded(
          child: _V7ChatBackdrop(
            child: ListView(
              controller: _chatScroll,
              cacheExtent: 4000,
              padding: EdgeInsets.fromLTRB(
                mobile ? 12 : 20,
                12,
                mobile ? 12 : 20,
                16,
              ),
              children: [
                // The Full Reveal is the first rich visual item (§28) and the
                // scroll target for Vision-card taps (§13).
                _V7RevealFrame(
                  key: _mobileRevealKey,
                  highlighted: _revealPulse,
                  child: PwaRevealCard(
                    vision: state.previewedVision!,
                    source: state.source,
                    project: state.project,
                    aspectRatio: mobile ? 4 / 3 : 16 / 10,
                    onDark: true,
                    showCaption: false,
                  ),
                ),
                const SizedBox(height: 10),
                _V7Metadata(
                  vision: state.previewedVision!,
                  atmosphereName: _atmoNameOf(
                    state,
                    state.previewedVision!.atmosphereId,
                  ),
                ),
                if (state.isPreviewingOther) ...[
                  const SizedBox(height: 10),
                  _V7PreviewActions(state: state, controller: _c),
                ],
                const SizedBox(height: 20),
                _V7AtmosphereBlock(
                  state: state,
                  controller: _c,
                  cardWidth: mobile ? 132 : 156,
                ),
                if (state.pendingAtmosphereId != null) ...[
                  const SizedBox(height: 12),
                  _V7PendingBar(state: state, controller: _c, inset: false),
                ],
                const SizedBox(height: 20),
                const _V7FeedDivider(),
                const SizedBox(height: 12),
                ..._chatMessages(state, stacked: true),
                // §17 — keep the last result clear of the fixed composer.
                SizedBox(height: MediaQuery.viewPaddingOf(context).bottom + 20),
              ],
            ),
          ),
        ),
        _V7Composer(enabled: !state.generating, onSend: _c.sendUserText),
      ],
    );
  }

  // ── Shared chat chronology builder ──────────────────────────────────────────

  List<Widget> _chatMessages(PwaState state, {required bool stacked}) {
    final out = <Widget>[];
    for (final m in state.messages) {
      out.addAll(_messageWidgets(state, m, stacked));
    }
    return out;
  }

  List<Widget> _messageWidgets(PwaState state, PwaMessage m, bool stacked) {
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
        final isWorkspace =
            vision.versionId == state.previewedVision?.versionId;
        final isCurrentReveal =
            vision.versionId == state.currentVision?.versionId;
        return [
          const _V7ChatGap(),
          // §18/§12/§19 — full-width rich vision result card. Tapping it previews
          // the vision; on the stacked feed it also scrolls up to the Full Reveal
          // and shows a "View in Full Reveal" affordance (desktop needs neither,
          // the reveal is beside the chat).
          _V7VisionCard(
            key: _visionKey(vision.versionId),
            vision: vision,
            atmosphereName: _atmoNameOf(state, vision.atmosphereId),
            inWorkspace: isWorkspace,
            highlighted: _highlightVersionId == vision.versionId,
            showRevealAffordance: stacked,
            onTap: stacked
                ? () => _openVisionInReveal(vision.versionId)
                : () => _c.previewVision(vision.versionId),
          ),
          const SizedBox(height: 10),
          // §19 — a short Ayden explanation follows the result.
          _V7AydenBubble(text: m.text),
          // §19/§20 — quick actions under the CURRENT vision's explanation.
          if (isCurrentReveal && !state.generating) ...[
            const SizedBox(height: 8),
            _V7QuickActions(chips: _defaultQuickActions, onTap: _onQuickAction),
          ],
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

class _V7DesignCanvas extends StatelessWidget {
  const _V7DesignCanvas({
    required this.state,
    required this.controller,
    required this.bodyHeight,
  });
  final PwaState state;
  final PwaController controller;
  final double bodyHeight;

  @override
  Widget build(BuildContext context) {
    final shown = state.previewedVision;
    if (shown == null) return const SizedBox.shrink();
    // §7/§8/§33 — reveal height ≈ 60vh, clamped so Atmospheres stay above fold.
    final revealH = (bodyHeight * 0.66).clamp(470.0, 620.0);

    return Column(
      children: [
        Expanded(
          // §8 — the left canvas is its own vertical scroll; the Reveal stays
          // dominant and the Atmosphere row is always reachable (never clipped),
          // with a comfortable bottom padding after the last card labels.
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, c) {
                    // Exact aspect so the RevealHero renders at ~revealH tall
                    // regardless of the pane width (8px frame inset each side).
                    final aspect = (c.maxWidth - 16) / revealH;
                    return _V7RevealFrame(
                      child: PwaRevealCard(
                        vision: shown,
                        source: state.source,
                        project: state.project,
                        aspectRatio: aspect,
                        onDark: true,
                        showCaption: false,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                _V7Metadata(
                  vision: shown,
                  atmosphereName: _atmoNameOf(state, shown.atmosphereId),
                ),
                if (state.isPreviewingOther) ...[
                  const SizedBox(height: 10),
                  _V7PreviewActions(state: state, controller: controller),
                ],
                const SizedBox(height: 24),
                _V7AtmosphereBlock(
                  state: state,
                  controller: controller,
                  cardWidth: 156,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        // §11 — the atmosphere pending confirmation is a full-width footer bar.
        if (state.pendingAtmosphereId != null)
          _V7PendingBar(state: state, controller: controller, inset: true),
      ],
    );
  }
}

String _atmoNameOf(PwaState state, String? id) {
  for (final a in state.atmospheres) {
    if (a.id == id) return a.name;
  }
  return 'Ayden Signature';
}

/// §6.3/§8 — dark, gold-edged frame around the Full Reveal. When [highlighted]
/// (arriving from a Vision-card tap, §16) the gold edge briefly intensifies.
class _V7RevealFrame extends StatelessWidget {
  const _V7RevealFrame({
    super.key,
    required this.child,
    this.highlighted = false,
  });
  final Widget child;
  final bool highlighted;
  @override
  Widget build(BuildContext context) {
    // §16 — respect reduced motion: the highlight snaps (no fade) instead of
    // animating the gold edge in and out.
    final reduce = MediaQuery.of(context).disableAnimations;
    return AnimatedContainer(
      duration: reduce ? Duration.zero : Av7Motion.component,
      curve: Av7Motion.curve,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: av7Reveal,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: av7Gold.withValues(alpha: highlighted ? 0.95 : 0.35),
          width: highlighted ? 2 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 26,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// §9 — one clean metadata strip beneath the reveal.
class _V7Metadata extends StatelessWidget {
  const _V7Metadata({required this.vision, required this.atmosphereName});
  final PwaVision vision;
  final String atmosphereName;
  @override
  Widget build(BuildContext context) {
    Widget dot() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '•',
        style: av7Sans(fontSize: 13, color: av7Gold.withValues(alpha: 0.75)),
      ),
    );
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: av7MetaBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const PwaLogoBadge(size: 24),
          const SizedBox(width: 10),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Vision ${vision.visionNumber}',
                    maxLines: 1,
                    style: av7Sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: av7Gold,
                    ),
                  ),
                  dot(),
                  Text(
                    atmosphereName,
                    maxLines: 1,
                    style: av7Sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: av7OnDarkSoft,
                    ),
                  ),
                  dot(),
                  Text(
                    'Created just now',
                    maxLines: 1,
                    style: av7Sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: av7OnDarkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slim "previewing an older vision" affordance (§25) — Back to current.
class _V7PreviewActions extends StatelessWidget {
  const _V7PreviewActions({required this.state, required this.controller});
  final PwaState state;
  final PwaController controller;
  @override
  Widget build(BuildContext context) {
    final v = state.previewedVision!;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      decoration: BoxDecoration(
        color: av7RevealRaised.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: av7Gold.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Previewing Vision ${v.visionNumber} · ${v.reasonLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: av7Sans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: av7OnDark,
                  ),
                ),
              ),
              TextButton(
                onPressed: controller.clearPreview,
                style: TextButton.styleFrom(foregroundColor: av7Gold),
                child: const Text('Back to current'),
              ),
            ],
          ),
          // §25 — version actions for the previewed vision (existing semantics).
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _V7PreviewActionButton(
                icon: Icons.check_circle_outline,
                label: 'Set as current',
                onTap: () => controller.setCurrentVision(v.versionId),
              ),
              _V7PreviewActionButton(
                icon: Icons.alt_route_rounded,
                label: 'Continue from this vision',
                onTap: () => controller.continueFromVision(v.versionId),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _V7PreviewActionButton extends StatelessWidget {
  const _V7PreviewActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15, color: av7OnDark),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: av7OnDark,
        side: BorderSide(color: av7Gold.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── Atmosphere (§10) ─────────────────────────────────────────────────────────

class _V7AtmosphereBlock extends StatelessWidget {
  const _V7AtmosphereBlock({
    required this.state,
    required this.controller,
    required this.cardWidth,
  });
  final PwaState state;
  final PwaController controller;
  final double cardWidth;
  @override
  Widget build(BuildContext context) {
    // §9 — slightly shorter post-generation cards (156×106 image + ~64 text) so
    // the Atmosphere row is never clipped in the scrollable left canvas.
    final imgH = cardWidth * (106 / 156);
    final rowH = imgH + 64;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ATMOSPHERE', style: av7Eyebrow()),
        const SizedBox(height: 12),
        SizedBox(
          height: rowH,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            primary: false,
            physics: const ClampingScrollPhysics(),
            itemCount: state.atmospheres.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final a = state.atmospheres[i];
              // §10/§11 — the gold border + check follow the APPLIED atmosphere
              // (the current vision's). A staged choice shows only in the
              // pending bar, so tapping a card never relocates the check; the
              // tapped card gets a lighter "pending" outline for feedback.
              final appliedId =
                  state.currentVision?.atmosphereId ??
                  state.selectedAtmosphereId;
              final selected = a.id == appliedId;
              final pending = state.pendingAtmosphereId == a.id && !selected;
              return _V7AtmosphereCard(
                atmosphere: a,
                selected: selected,
                pending: pending,
                width: cardWidth,
                imageHeight: imgH,
                enabled: !state.generating,
                onTap: () => controller.stageAtmosphere(a.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _V7AtmosphereCard extends StatelessWidget {
  const _V7AtmosphereCard({
    required this.atmosphere,
    required this.selected,
    required this.pending,
    required this.width,
    required this.imageHeight,
    required this.enabled,
    required this.onTap,
  });
  final PwaAtmosphere atmosphere;
  final bool selected;
  final bool pending;
  final double width;
  final double imageHeight;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color borderColor = selected
        ? av7Gold
        : pending
        ? av7Gold.withValues(alpha: 0.55)
        : Colors.white.withValues(alpha: 0.08);
    return Semantics(
      button: true,
      selected: selected,
      label: 'Select ${atmosphere.name} atmosphere',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: width,
          decoration: BoxDecoration(
            color: av7CardDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor,
              width: selected || pending ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(13),
                    ),
                    child: SizedBox(
                      height: imageHeight,
                      width: double.infinity,
                      child: Image.asset(
                        atmosphere.asset,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const ColoredBox(color: av7RevealRaised),
                      ),
                    ),
                  ),
                  if (selected)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: av7Surface,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: av7Ink,
                        ),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      atmosphere.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: av7Sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: av7OnDark,
                        height: 1.3,
                      ),
                    ),
                    if (atmosphere.descriptor.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        atmosphere.descriptor,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: av7Sans(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w400,
                          color: av7OnDark.withValues(alpha: 0.62),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// §11 — atmosphere pending confirmation. Desktop: full-width canvas footer.
class _V7PendingBar extends StatelessWidget {
  const _V7PendingBar({
    required this.state,
    required this.controller,
    required this.inset,
  });
  final PwaState state;
  final PwaController controller;
  final bool inset;
  @override
  Widget build(BuildContext context) {
    final atmo = state.atmospheres.firstWhere(
      (a) => a.id == state.pendingAtmosphereId,
      orElse: () => state.atmospheres.first,
    );
    final nextN = state.versionCount + 1;
    final busy = state.generating;

    final info = Row(
      children: [
        const Icon(Icons.auto_awesome, size: 18, color: av7Gold),
        const SizedBox(width: 10),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                '${atmo.name} selected',
                style: av7Sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: av7OnDark,
                ),
              ),
              Text(
                '· Creates Vision $nextN',
                style: av7Sans(fontSize: 13, color: av7OnDarkSoft),
              ),
              Text(
                '· Uses 1 Space',
                style: av7Sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: av7Gold,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final cancel = TextButton(
      onPressed: busy ? null : controller.cancelPendingAtmosphere,
      style: TextButton.styleFrom(
        foregroundColor: av7OnDarkSoft,
        minimumSize: const Size(80, 40),
      ),
      child: const Text('Cancel'),
    );
    final create = FilledButton(
      onPressed: busy ? null : controller.applyAtmosphere,
      style: FilledButton.styleFrom(
        backgroundColor: av7Gold,
        foregroundColor: av7Ink,
        minimumSize: const Size(120, 40),
      ),
      child: Text(
        busy ? 'Creating…' : 'Create vision',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: av7PendingBg,
        borderRadius: BorderRadius.circular(inset ? 0 : 14),
        border: inset
            ? const Border(top: BorderSide(color: Color(0x33D3B064)))
            : Border.all(color: av7Gold.withValues(alpha: 0.34)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          // Narrow (mobile stacked feed): stack the info above a full-width
          // button row so two fixed buttons can't starve the label text.
          if (c.maxWidth < 460) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: cancel),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: create),
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 12),
              cancel,
              const SizedBox(width: 8),
              create,
            ],
          );
        },
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// GLOBAL HEADER (§5)
// ════════════════════════════════════════════════════════════════════════════

class _V7GlobalHeader extends StatelessWidget {
  const _V7GlobalHeader({
    required this.compact,
    required this.shownNumber,
    required this.total,
    required this.hasPrev,
    required this.hasNext,
    required this.onBack,
    required this.onPrev,
    required this.onNext,
  });
  final bool compact;
  final int shownNumber;
  final int total;
  final bool hasPrev;
  final bool hasNext;
  final VoidCallback onBack;
  final VoidCallback onPrev;
  final VoidCallback onNext;

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
          _V7VisionNav(
            shownNumber: shownNumber,
            total: total,
            hasPrev: hasPrev,
            hasNext: hasNext,
            onPrev: onPrev,
            onNext: onNext,
            arrowSize: compact ? 34 : 40,
            onDark: true,
          ),
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

/// "Vision N of M  ‹  ›" — global (arrows 40px, dark) and chat pill (30px, light).
class _V7VisionNav extends StatelessWidget {
  const _V7VisionNav({
    required this.shownNumber,
    required this.total,
    required this.hasPrev,
    required this.hasNext,
    required this.onPrev,
    required this.onNext,
    required this.arrowSize,
    required this.onDark,
  });
  final int shownNumber;
  final int total;
  final bool hasPrev;
  final bool hasNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final double arrowSize;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final label = total <= 0
        ? 'Vision 0 of 0'
        : 'Vision $shownNumber of $total';
    final textColor = onDark ? av7OnDark : av7Ink;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: av7Sans(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: textColor,
          ),
        ),
        const SizedBox(width: 10),
        _NavArrow(
          icon: Icons.chevron_left_rounded,
          size: arrowSize,
          enabled: hasPrev,
          onTap: onPrev,
          onDark: onDark,
          semantic: 'Previous vision',
        ),
        const SizedBox(width: 8),
        _NavArrow(
          icon: Icons.chevron_right_rounded,
          size: arrowSize,
          enabled: hasNext,
          onTap: onNext,
          onDark: onDark,
          semantic: 'Next vision',
        ),
      ],
    );
  }
}

class _NavArrow extends StatelessWidget {
  const _NavArrow({
    required this.icon,
    required this.size,
    required this.enabled,
    required this.onTap,
    required this.onDark,
    required this.semantic,
  });
  final IconData icon;
  final double size;
  final bool enabled;
  final VoidCallback onTap;
  final bool onDark;
  final String semantic;
  @override
  Widget build(BuildContext context) {
    final active = enabled;
    final border = onDark ? av7Gold.withValues(alpha: 0.5) : av7Line;
    final iconColor = active
        ? (onDark ? av7OnDark : av7Ink)
        : (onDark ? av7OnDark.withValues(alpha: 0.28) : av7MutedSoft);
    return Semantics(
      button: true,
      enabled: active,
      label: semantic,
      child: Material(
        color: Colors.transparent,
        shape: CircleBorder(
          side: BorderSide(
            color: active ? border : border.withValues(alpha: 0.4),
          ),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: active ? onTap : null,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: size * 0.46, color: iconColor),
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
      fit: StackFit.expand,
      children: [
        // 1) Warm modern salon — cropped to cover, centred, softened by the veil.
        Positioned.fill(
          child: Image.asset(
            _kV7ChatBackdrop,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (_, _, _) => const ColoredBox(color: av7Canvas),
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

class _V7ChatPanel extends StatelessWidget {
  const _V7ChatPanel({
    required this.state,
    required this.scroll,
    required this.shownNumber,
    required this.total,
    required this.hasPrev,
    required this.hasNext,
    required this.onPrev,
    required this.onNext,
    required this.messages,
    required this.onSend,
  });
  final PwaState state;
  final ScrollController scroll;
  final int shownNumber;
  final int total;
  final bool hasPrev;
  final bool hasNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final List<Widget> messages;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('av7-chat-panel'),
      decoration: BoxDecoration(
        color: av7Canvas,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: av7GoldDeep.withValues(alpha: 0.18)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _V7ChatBackdrop(
        child: Column(
          children: [
            _V7ChatHeader(
              shownNumber: shownNumber,
              total: total,
              hasPrev: hasPrev,
              hasNext: hasNext,
              onPrev: onPrev,
              onNext: onNext,
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                // The conversation is short; keep every message laid out so
                // navigation / highlight / find never target an unbuilt row.
                cacheExtent: 4000,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                children: messages,
              ),
            ),
            _V7Composer(enabled: !state.generating, onSend: onSend),
          ],
        ),
      ),
    );
  }
}

class _V7ChatHeader extends StatelessWidget {
  const _V7ChatHeader({
    required this.shownNumber,
    required this.total,
    required this.hasPrev,
    required this.hasNext,
    required this.onPrev,
    required this.onNext,
  });
  final int shownNumber;
  final int total;
  final bool hasPrev;
  final bool hasNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: av7Line)),
      ),
      child: Row(
        children: [
          const PwaLogoBadge(size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AYDEN ARCHITECT',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: av7Sans(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: av7Ink,
                    letterSpacing: 0.6,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Your design conversation',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: av7Sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: av7Muted,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          _V7ChatNavPill(
            shownNumber: shownNumber,
            total: total,
            hasPrev: hasPrev,
            hasNext: hasNext,
            onPrev: onPrev,
            onNext: onNext,
          ),
        ],
      ),
    );
  }
}

/// §13 — compact "Vision N of M ‹ ›" pill inside the chat header.
class _V7ChatNavPill extends StatelessWidget {
  const _V7ChatNavPill({
    required this.shownNumber,
    required this.total,
    required this.hasPrev,
    required this.hasNext,
    required this.onPrev,
    required this.onNext,
  });
  final int shownNumber;
  final int total;
  final bool hasPrev;
  final bool hasNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  @override
  Widget build(BuildContext context) {
    final label = total <= 0 ? '0 of 0' : '$shownNumber of $total';
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: av7Surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: av7Line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PillArrow(
            icon: Icons.chevron_left_rounded,
            enabled: hasPrev,
            onTap: onPrev,
            semantic: 'Previous vision',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Vision $label',
              style: av7Sans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: av7Ink,
              ),
            ),
          ),
          _PillArrow(
            icon: Icons.chevron_right_rounded,
            enabled: hasNext,
            onTap: onNext,
            semantic: 'Next vision',
          ),
        ],
      ),
    );
  }
}

class _PillArrow extends StatelessWidget {
  const _PillArrow({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.semantic,
  });
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final String semantic;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: semantic,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(icon, size: 18, color: enabled ? av7Ink : av7MutedSoft),
        ),
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

class _V7FeedDivider extends StatelessWidget {
  const _V7FeedDivider();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, thickness: 1, color: av7Line);
}

class _V7Avatar extends StatelessWidget {
  const _V7Avatar();
  @override
  Widget build(BuildContext context) => const PwaLogoBadge(size: 32);
}

/// §16 — Ayden message: avatar + ivory bubble, left aligned.
class _V7AydenBubble extends StatelessWidget {
  const _V7AydenBubble({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _V7Avatar(),
        const SizedBox(width: 10),
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: av7Surface,
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
        ),
      ],
    );
  }
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
              color: av7UserBubble,
              borderRadius: BorderRadius.only(
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

/// §18 — full-width vision result card (After image + "Currently in workspace").
class _V7VisionCard extends StatelessWidget {
  const _V7VisionCard({
    super.key,
    required this.vision,
    required this.atmosphereName,
    required this.inWorkspace,
    required this.highlighted,
    required this.showRevealAffordance,
    required this.onTap,
  });
  final PwaVision vision;
  final String atmosphereName;
  final bool inWorkspace;
  final bool highlighted;

  /// §14 — on the stacked feed the image shows a "View in Full Reveal" (or
  /// "Currently in Full Reveal") affordance; on desktop the reveal is beside the
  /// chat so none is needed.
  final bool showRevealAffordance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = highlighted || inWorkspace ? av7Gold : av7Line;
    final borderW = (highlighted || inWorkspace) ? 2.0 : 1.0;
    return Semantics(
      button: true,
      label:
          'Open Vision ${vision.visionNumber}, $atmosphereName, in the Full Reveal',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Av7Motion.component,
            decoration: BoxDecoration(
              color: av7Surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: borderW),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header (§18) — title + the "Currently in workspace" badge only
                // (no invented overflow control; version actions live in the
                // preview-actions bar under the reveal — §25/§35).
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
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
                      if (inWorkspace) const _WorkspaceBadge(),
                    ],
                  ),
                ),
                // 16:9 After image (§18 — capped at 250px tall on wide panels).
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Semantics(
                          image: true,
                          label:
                              'After image, Vision ${vision.visionNumber}, $atmosphereName',
                          child: Image.asset(
                            vision.afterAsset,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const ColoredBox(color: av7RevealRaised),
                          ),
                        ),
                        if (showRevealAffordance)
                          Positioned(
                            bottom: 10,
                            right: 10,
                            child: _RevealAffordance(active: inWorkspace),
                          ),
                      ],
                    ),
                  ),
                ),
                // Footer (§18) — a light timestamp, as in the reference.
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 9, 14, 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Just now',
                      maxLines: 1,
                      style: av7Sans(fontSize: 11.5, color: av7MutedSoft),
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

/// §14 — the on-image affordance: "View in Full Reveal ↑" for a vision not in
/// the workspace, "Currently in Full Reveal" (gold wash) for the shown one.
class _RevealAffordance extends StatelessWidget {
  const _RevealAffordance({required this.active});
  final bool active;
  @override
  Widget build(BuildContext context) {
    if (active) {
      return Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: av7GoldWash,
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: Alignment.center,
        child: Text(
          'Currently in Full Reveal',
          maxLines: 1,
          style: av7Sans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: av7GoldDeep,
          ),
        ),
      );
    }
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xD1191511),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'View in Full Reveal',
            maxLines: 1,
            style: av7Sans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: av7OnDark,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_upward_rounded, size: 14, color: av7OnDark),
        ],
      ),
    );
  }
}

class _WorkspaceBadge extends StatelessWidget {
  const _WorkspaceBadge();
  @override
  Widget build(BuildContext context) => Container(
    height: 24,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    margin: const EdgeInsets.only(right: 4),
    decoration: BoxDecoration(
      color: av7GoldWash,
      borderRadius: BorderRadius.circular(999),
    ),
    alignment: Alignment.center,
    child: Text(
      'Currently in workspace',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: av7Sans(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: av7GoldDeep,
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
    return Padding(
      padding: const EdgeInsets.only(left: 42),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in chips)
            Material(
              color: av7Surface,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => onTap(c),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: av7GoldDeep.withValues(alpha: 0.34),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_chipIcon(c), size: 14, color: av7GoldDeep),
                      const SizedBox(width: 6),
                      Text(
                        c,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: av7Sans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: av7InkSecondary,
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
    return Padding(
      padding: const EdgeInsets.only(left: 42),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: av7Surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: av7GoldDeep.withValues(alpha: 0.38)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Apply this change?',
              style: av7Sans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: av7Ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              controller.refineSummaryText(instruction),
              style: av7Sans(
                fontSize: 13,
                height: 1.46,
                color: av7InkSecondary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 14, color: av7GoldDeep),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Creates Vision $nextN · Uses 1 Space',
                    style: av7Sans(fontSize: 11.5, color: av7MutedSoft),
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
                      foregroundColor: av7Ink,
                      side: const BorderSide(color: av7Line),
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
  const _V7Composer({required this.enabled, required this.onSend});
  final bool enabled;
  final ValueChanged<String> onSend;
  @override
  State<_V7Composer> createState() => _V7ComposerState();
}

class _V7ComposerState extends State<_V7Composer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
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
    return Container(
      // Translucent so the warm backdrop reads continuously to the panel's
      // foot; the input field keeps its own opaque fill, so the composer stays
      // perfectly legible.
      color: av7Canvas.withValues(alpha: 0.82),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
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
                    style: av7Sans(fontSize: 15, color: av7Ink, height: 1.4),
                    cursorColor: av7GoldDeep,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: av7Surface,
                      hintText: 'Ask Ayden anything…',
                      hintStyle: av7Sans(fontSize: 15, color: av7Muted),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: const BorderSide(color: av7Line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: const BorderSide(
                          color: av7Gold,
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
          const SizedBox(height: 6),
          Text(
            'Ayden can make mistakes. Always review design details.',
            style: av7Sans(fontSize: 10, color: av7MutedSoft),
          ),
        ],
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
