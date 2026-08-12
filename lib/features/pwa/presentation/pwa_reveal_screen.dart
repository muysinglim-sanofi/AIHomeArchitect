/// The Full Reveal — the secondary, exploration-only view of ONE vision.
///
/// Route: `/projects/{projectId}/reveal?vision={visionId}`.
///
/// It is deliberately the visual opposite of the conversation: a dark, immersive
/// gold-on-charcoal room for looking at the image, where Architect is a warm,
/// light place for talking. It holds the large Before/After, the vision details,
/// the atmosphere rail and the vision-to-vision navigation — everything that used
/// to compete with the chat for attention on one screen.
///
/// It never contains a second conversation. `Back to conversation` and `Open in
/// conversation` are the only ways back, and both return to the SAME chat.
///
/// The Before/After itself is [PwaRevealCard] → the production `RevealHero`,
/// which is shared with the frozen mobile app and is used strictly read-only:
/// everything here composes AROUND it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pwa_controller.dart';
import '../domain/pwa_models.dart';
import 'pwa_architect_tokens.dart';
import 'pwa_brand.dart';
import 'pwa_widgets.dart';

/// Desktop puts the details panel beside the image; below this the panel drops
/// under it and the atmospheres become a full-width rail.
bool pwaRevealIsWide(double w) => w >= 1200;

/// Width of the right-hand details panel on a wide viewport.
const double kPwaRevealPanelW = 380;

class PwaRevealScreen extends ConsumerStatefulWidget {
  const PwaRevealScreen({super.key});

  @override
  ConsumerState<PwaRevealScreen> createState() => _PwaRevealScreenState();
}

class _PwaRevealScreenState extends ConsumerState<PwaRevealScreen> {
  final _atmosphereKey = GlobalKey(debugLabel: 'reveal-atmospheres');
  final _scroll = ScrollController();

  PwaController get _c => ref.read(pwaControllerProvider.notifier);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// "Try another atmosphere" from the chat lands here — bring the rail into
  /// view so the action the user asked for is the thing they see.
  Future<void> _focusAtmospheres() async {
    final ctx = _atmosphereKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await Scrollable.ensureVisible(
      ctx,
      alignment: 0.6,
      duration: MediaQuery.of(context).disableAnimations
          ? Duration.zero
          : Av7Motion.component,
      curve: Av7Motion.curve,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pwaControllerProvider);
    final vision = state.previewedVision;
    // A Reveal without a vision cannot exist (the route model normalizes it
    // away). Fall back to the conversation rather than dereferencing null.
    if (vision == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _c.backToConversation();
      });
      return const ColoredBox(color: av7DarkBg);
    }

    return Scaffold(
      backgroundColor: av7DarkBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final wide = pwaRevealIsWide(c.maxWidth);
            return Column(
              children: [
                PwaRevealHeader(
                  shownNumber: state.previewedIndex + 1,
                  total: state.versionCount,
                  hasPrev: state.hasPreviousVision,
                  hasNext: state.hasNextVision,
                  compact: !wide,
                  onBack: () =>
                      _c.backToConversation(focusVisionId: vision.versionId),
                  onPrev: _c.previewPrevious,
                  onNext: _c.previewNext,
                ),
                Expanded(
                  child: wide ? _wide(state, vision) : _narrow(state, vision),
                ),
                if (state.pendingAtmosphereId != null)
                  PwaRevealPendingBar(state: state, controller: _c),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Wide: image left, details right, atmospheres beneath ───────────────────
  Widget _wide(PwaState state, PwaVision vision) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(24, 18, 12, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, c) {
                    // Keep the hero large but never taller than the viewport.
                    final h = (MediaQuery.sizeOf(context).height * 0.62).clamp(
                      380.0,
                      720.0,
                    );
                    return PwaRevealFrame(
                      child: PwaRevealCard(
                        vision: vision,
                        source: state.source,
                        versions: state.versions,
                        project: state.project,
                        aspectRatio: (c.maxWidth - 16) / h,
                        onDark: true,
                        showCaption: false,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                PwaVisionMeta(
                  vision: vision,
                  atmosphereName: pwaAtmosphereNameOf(
                    state,
                    vision.atmosphereId,
                  ),
                ),
                const SizedBox(height: 22),
                PwaAtmosphereRail(
                  key: _atmosphereKey,
                  state: state,
                  controller: _c,
                  cardWidth: 156,
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: kPwaRevealPanelW,
          child: PwaVisionDetailsPanel(
            state: state,
            vision: vision,
            controller: _c,
            onTryAtmosphere: _focusAtmospheres,
          ),
        ),
      ],
    );
  }

  // ── Narrow: image, then details, then the rail ─────────────────────────────
  Widget _narrow(PwaState state, PwaVision vision) {
    final mobile = MediaQuery.sizeOf(context).width < 768;
    return SingleChildScrollView(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(mobile ? 12 : 20, 14, mobile ? 12 : 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PwaRevealFrame(
            child: PwaRevealCard(
              vision: vision,
              source: state.source,
                        versions: state.versions,
              project: state.project,
              aspectRatio: mobile ? 4 / 3 : 16 / 10,
              onDark: true,
              showCaption: false,
            ),
          ),
          const SizedBox(height: 12),
          PwaVisionMeta(
            vision: vision,
            atmosphereName: pwaAtmosphereNameOf(state, vision.atmosphereId),
          ),
          const SizedBox(height: 16),
          PwaVisionDetailsPanel(
            state: state,
            vision: vision,
            controller: _c,
            onTryAtmosphere: _focusAtmospheres,
            boxed: true,
          ),
          const SizedBox(height: 22),
          PwaAtmosphereRail(
            key: _atmosphereKey,
            state: state,
            controller: _c,
            cardWidth: mobile ? 132 : 156,
          ),
        ],
      ),
    );
  }
}

/// The atmosphere name for an id, or the signature default.
String pwaAtmosphereNameOf(PwaState state, String? id) {
  for (final a in state.atmospheres) {
    if (a.id == id) return a.name;
  }
  return 'Ayden Signature';
}

// ════════════════════════════════════════════════════════════════════════════
// HEADER
// ════════════════════════════════════════════════════════════════════════════

/// Reveal header: leave, identity, and the vision-to-vision navigation — which
/// lives HERE and nowhere else, so the conversation keeps a single purpose.
class PwaRevealHeader extends StatelessWidget {
  const PwaRevealHeader({
    super.key,
    required this.shownNumber,
    required this.total,
    required this.hasPrev,
    required this.hasNext,
    required this.compact,
    required this.onBack,
    required this.onPrev,
    required this.onNext,
  });
  final int shownNumber;
  final int total;
  final bool hasPrev;
  final bool hasNext;
  final bool compact;
  final VoidCallback onBack;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('pwa-reveal-header'),
      height: compact ? 60 : 72,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 24),
      decoration: const BoxDecoration(
        color: av7HeaderBlack,
        border: Border(bottom: BorderSide(color: Color(0x29D3B064))),
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Back to conversation',
            child: Tooltip(
              message: 'Back to conversation',
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  key: const ValueKey('pwa-back-to-conversation'),
                  onTap: onBack,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
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
                          const SizedBox(width: 10),
                          Text(
                            'Back to conversation',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
          ),
          const Spacer(),
          if (!compact)
            Text(
              'FULL REVEAL',
              style: av7Eyebrow(fontSize: 10, letterSpacing: 4),
            ),
          const Spacer(),
          PwaVisionNav(
            shownNumber: shownNumber,
            total: total,
            hasPrev: hasPrev,
            hasNext: hasNext,
            onPrev: onPrev,
            onNext: onNext,
            arrowSize: compact ? 34 : 40,
          ),
        ],
      ),
    );
  }
}

/// "Vision N of M ‹ ›" — the ONLY vision navigator in the product.
class PwaVisionNav extends StatelessWidget {
  const PwaVisionNav({
    super.key,
    required this.shownNumber,
    required this.total,
    required this.hasPrev,
    required this.hasNext,
    required this.onPrev,
    required this.onNext,
    required this.arrowSize,
  });
  final int shownNumber;
  final int total;
  final bool hasPrev;
  final bool hasNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final double arrowSize;

  @override
  Widget build(BuildContext context) {
    final label = total <= 0
        ? 'Vision 0 of 0'
        : 'Vision $shownNumber of $total';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: av7Sans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: av7OnDark,
            ),
          ),
        ),
        const SizedBox(width: 10),
        _NavArrow(
          icon: Icons.chevron_left_rounded,
          size: arrowSize,
          enabled: hasPrev,
          onTap: onPrev,
          semantic: 'Previous vision',
        ),
        const SizedBox(width: 8),
        _NavArrow(
          icon: Icons.chevron_right_rounded,
          size: arrowSize,
          enabled: hasNext,
          onTap: onNext,
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
    required this.semantic,
  });
  final IconData icon;
  final double size;
  final bool enabled;
  final VoidCallback onTap;
  final String semantic;

  @override
  Widget build(BuildContext context) {
    final border = av7Gold.withValues(alpha: 0.5);
    return Semantics(
      button: true,
      enabled: enabled,
      label: semantic,
      child: Material(
        color: Colors.transparent,
        shape: CircleBorder(
          side: BorderSide(
            color: enabled ? border : border.withValues(alpha: 0.4),
          ),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: size * 0.46,
              color: enabled ? av7OnDark : av7OnDark.withValues(alpha: 0.28),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// IMAGE FRAME + METADATA
// ════════════════════════════════════════════════════════════════════════════

/// Dark, gold-edged frame around the Before/After.
class PwaRevealFrame extends StatelessWidget {
  const PwaRevealFrame({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: av7Reveal,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: av7Gold.withValues(alpha: 0.35)),
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

/// One clean metadata strip beneath the reveal.
class PwaVisionMeta extends StatelessWidget {
  const PwaVisionMeta({
    super.key,
    required this.vision,
    required this.atmosphereName,
  });
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

// ════════════════════════════════════════════════════════════════════════════
// DETAILS PANEL
// ════════════════════════════════════════════════════════════════════════════

/// Vision details + the actions that belong to exploring a render. Deliberately
/// NOT a conversation: it links back to the one that exists.
class PwaVisionDetailsPanel extends StatelessWidget {
  const PwaVisionDetailsPanel({
    super.key,
    required this.state,
    required this.vision,
    required this.controller,
    required this.onTryAtmosphere,
    this.boxed = false,
  });
  final PwaState state;
  final PwaVision vision;
  final PwaController controller;
  final VoidCallback onTryAtmosphere;

  /// Narrow layouts render the panel as a card inside the scroll flow.
  final bool boxed;

  /// The Ayden line that introduced this vision, if the conversation has one.
  String? get _aydenNote {
    for (final m in state.messages) {
      if (m.kind == PwaMessageKind.reveal &&
          m.visionId == vision.versionId &&
          m.text.isNotEmpty) {
        return m.text;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final note = _aydenNote;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('VISION DETAILS', style: av7Eyebrow(fontSize: 11)),
        const SizedBox(height: 14),
        Text(
          'Vision ${vision.visionNumber}',
          style: av7Sans(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: av7OnDark,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          vision.reasonLabel,
          style: av7Sans(fontSize: 13, color: av7OnDarkSoft),
        ),
        if (note != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: av7MetaBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: av7Gold.withValues(alpha: 0.18)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PwaLogoBadge(size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    note,
                    style: av7Sans(
                      fontSize: 13.5,
                      height: 1.5,
                      color: av7OnDarkSoft,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        // "Back to conversation" in the header already covers a plain return —
        // this action exists only because it carries an intent with it.
        _RevealAction(
          icon: Icons.tune_rounded,
          label: 'Refine with Ayden',
          subtitle: 'Continue this vision in the conversation',
          onTap: () => controller.startRefineContext(vision.versionId),
        ),
        const SizedBox(height: 10),
        _RevealAction(
          icon: Icons.auto_awesome,
          label: 'Try another atmosphere',
          subtitle: 'Explore a different style',
          onTap: onTryAtmosphere,
        ),
        if (state.isPreviewingOther) ...[
          const SizedBox(height: 18),
          PwaRevealPreviewActions(state: state, controller: controller),
        ],
      ],
    );

    if (boxed) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: av7Reveal,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: av7Gold.withValues(alpha: 0.18)),
        ),
        child: body,
      );
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Color(0x29D3B064))),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: body,
      ),
    );
  }
}

class _RevealAction extends StatelessWidget {
  const _RevealAction({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const fg = av7OnDark;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: av7RevealRaised.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: av7Gold.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: av7Gold),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: av7Sans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: fg,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: av7Sans(
                          fontSize: 11.5,
                          color: av7OnDark.withValues(alpha: 0.5),
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
    );
  }
}

/// "Previewing an older vision" affordance — set as current / continue from.
class PwaRevealPreviewActions extends StatelessWidget {
  const PwaRevealPreviewActions({
    super.key,
    required this.state,
    required this.controller,
  });
  final PwaState state;
  final PwaController controller;

  @override
  Widget build(BuildContext context) {
    final v = state.previewedVision!;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: av7RevealRaised.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: av7Gold.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Previewing Vision ${v.visionNumber}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: av7Sans(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: av7OnDark,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => controller.setCurrentVision(v.versionId),
                icon: const Icon(
                  Icons.check_circle_outline,
                  size: 15,
                  color: av7OnDark,
                ),
                label: const Text('Set as current'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: av7OnDark,
                  side: BorderSide(color: av7Gold.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => controller.continueFromVision(v.versionId),
                icon: const Icon(
                  Icons.alt_route_rounded,
                  size: 15,
                  color: av7OnDark,
                ),
                label: const Text('Continue from this vision'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: av7OnDark,
                  side: BorderSide(color: av7Gold.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ATMOSPHERE RAIL  (lives here, and only here)
// ════════════════════════════════════════════════════════════════════════════

class PwaAtmosphereRail extends StatelessWidget {
  const PwaAtmosphereRail({
    super.key,
    required this.state,
    required this.controller,
    required this.cardWidth,
  });
  final PwaState state;
  final PwaController controller;
  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    final imgH = cardWidth * (106 / 156);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ATMOSPHERES', style: av7Eyebrow()),
        const SizedBox(height: 12),
        SizedBox(
          height: imgH + 64,
          child: ListView.separated(
            key: const ValueKey('pwa-reveal-atmospheres'),
            scrollDirection: Axis.horizontal,
            primary: false,
            physics: const ClampingScrollPhysics(),
            itemCount: state.atmospheres.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final a = state.atmospheres[i];
              final appliedId =
                  state.currentVision?.atmosphereId ??
                  state.selectedAtmosphereId;
              final selected = a.id == appliedId;
              return _AtmosphereCard(
                atmosphere: a,
                selected: selected,
                pending: state.pendingAtmosphereId == a.id && !selected,
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

class _AtmosphereCard extends StatelessWidget {
  const _AtmosphereCard({
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
    final borderColor = selected
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

/// Atmosphere pending confirmation — a full-width footer bar on the Reveal.
class PwaRevealPendingBar extends StatelessWidget {
  const PwaRevealPendingBar({
    super.key,
    required this.state,
    required this.controller,
  });
  final PwaState state;
  final PwaController controller;

  @override
  Widget build(BuildContext context) {
    final atmo = state.atmospheres.firstWhere(
      (a) => a.id == state.pendingAtmosphereId,
      orElse: () => state.atmospheres.first,
    );
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
                '· Creates Vision ${state.versionCount + 1}',
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
      // A new vision is a conversation event: create it, then return to the
      // chat where it will appear in the chronology.
      onPressed: busy
          ? null
          : () {
              controller.applyAtmosphere();
              controller.backToConversation();
            },
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
      decoration: const BoxDecoration(
        color: av7PendingBg,
        border: Border(top: BorderSide(color: Color(0x33D3B064))),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
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
