/// CREATE, aligned to iOS. Phase 3.
///
/// The four-step journey the phone runs, on the one scrolling page the web
/// already had.
///
///     ← Upload your space                    header, close returns Home
///     ①──②──③──④                             sticky stepper, tap to jump
///     STEP 1 OF 4  Upload your space
///     STEP 2 OF 4  What type of space…
///     STEP 3 OF 4  Choose your atmosphere
///     STEP 4 OF 4  Describe your vision   [Optional]      ← NEW
///     Generate my design ✨                  sticky, above the home indicator
///
/// WHY ONE PAGE AND FOUR STEPS ARE NOT A CONTRADICTION
/// ---------------------------------------------------
/// iOS does exactly this. `upload_screen.dart` is a single
/// `SingleChildScrollView` holding four `_StepSection`s separated by
/// `AppSpacing.xxl`; what makes it FEEL like four steps is the badge on each
/// section and the stepper that tracks which one you are reading. Nothing is
/// gated, nothing is a route, and you can scroll straight past 2, 3 and 4 to
/// the CTA — which is the fast path the web was built around and does not lose.
///
/// So this screen reproduces the perception, not a wizard: same badges, same
/// order, same copy, same scroll-driven current step, same tap-to-jump.
///
/// WHAT STEP 4 ADDS, AND WHAT IT DOES NOT
/// --------------------------------------
/// The web had no free-text brief. The REQUEST already carried one:
/// `PwaGenerationRequest.userInstruction` → `user_instruction`, which the
/// staging backend feeds to `_run_canonical_engine` for a first vision exactly
/// as mobile's `desc` query parameter does. Step 4 is therefore a front-end
/// surface over a capability that shipped long ago — no new endpoint, no new
/// field, no change to the generation contract.
///
/// It is genuinely optional: blank is the default, the value is trimmed, and an
/// empty brief produces byte-for-byte the request the web sent yesterday.
///
/// THE ONE THING iOS HAS HERE THAT THIS DOES NOT
/// ---------------------------------------------
/// A microphone. iOS's `_DescriptionField` wraps `VoiceService` (Apple STT) and
/// its subtitle offers "You can speak or type." The web build has no such
/// service, so the mic is absent AND the sentence offering it is absent — see
/// `PwaL10n.step4Sub`. Copying the sentence without the button would have been
/// the worst of the three options.
library;

import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/media/image_pipeline.dart';
import '../../cards/card_catalog.dart';
import '../../cards/widgets/ai_action_card.dart';
import '../../cards/widgets/atmosphere_hero_card.dart';
import '../../cards/widgets/room_card.dart';
import '../application/pwa_controller.dart';
import '../domain/pwa_models.dart';
import '../l10n/pwa_l10n.dart';
import 'pwa_account_chip.dart';
import 'pwa_entry_screen.dart'
    show kPwaExamples, kPwaPopularAtmosphereIds, kPwaRooms;
import 'pwa_language_switcher.dart';
import 'pwa_primitives.dart';
import 'pwa_scaffold.dart';
import 'pwa_theme.dart';
import 'pwa_type.dart';

/// Where the stepper switches from a top rail to a side rail. iOS's own
/// threshold in `upload_screen.dart`.
const double kPwaCreateWideBreakpoint = 720;

/// How far below the viewport top a step header counts as "the one being
/// read". iOS uses 120 under its sticky AppBar; this page's header + stepper
/// occupy a comparable band.
const double kPwaStepReadingLine = 120;

/// Where a tapped step's badge lands, as a fraction of the viewport. Small
/// enough that the badge is unmistakably the first thing read, and well inside
/// [kPwaStepReadingLine] so the rail marks that step current on arrival.
const double kPwaStepLandingAlignment = 0.02;

/// How far off the landing point still counts as arrival. Two logical pixels —
/// tight enough that a real miss is caught, loose enough that sub-pixel
/// rounding never triggers a pointless correction.
const double kPwaStepLandingTolerance = 2.0;

/// The pre-composed AYDEN SIGNATURE card art, with the wordmark baked in — the
/// same file iOS's carousel names. Not in the atmosphere card catalogue,
/// because Signature is a delegation rather than an atmosphere.
const String kPwaSignatureCardAsset = 'assets/atmospheres/ayden_signature.jpg';

/// The four content column widths iOS's grid resolves to, restated for the web
/// so a 2560px monitor does not stretch a room grid to six across.
const double kPwaCreateMaxContent = 760;

class PwaCreateIos extends ConsumerStatefulWidget {
  const PwaCreateIos({super.key});

  @override
  ConsumerState<PwaCreateIos> createState() => _PwaCreateIosState();
}

class _PwaCreateIosState extends ConsumerState<PwaCreateIos> {
  final _picker = ImagePicker();
  final _scroll = ScrollController();

  /// Step 4's text. Local, exactly as iOS keeps `_descController` local: the
  /// brief belongs to THIS generation, not to the session. Nothing persists it,
  /// and nothing needs to.
  final _desc = TextEditingController();

  final _stepKeys = List.generate(4, (_) => GlobalKey());
  int _currentStep = 1;

  /// Guards the verify-and-correct jump against re-entry from a second tap.
  bool _jumping = false;

  @override
  void initState() {
    super.initState();
    pwaHardenDebugPaints();
    // The reused iOS cards reach AppTheme, which reaches google_fonts. Keep the
    // PWA offline: bundled faces only, never a runtime fetch.
    pwaDisableRemoteFonts();
    _scroll.addListener(_recomputeCurrentStep);
  }

  @override
  void dispose() {
    _scroll.removeListener(_recomputeCurrentStep);
    _scroll.dispose();
    _desc.dispose();
    super.dispose();
  }

  /// The deepest step whose header has crossed the reading line. Ported from
  /// iOS `_recomputeCurrentStep` rather than reinvented — the subtlety is that
  /// a very tall section (the atmosphere carousel) must not keep the NEXT step
  /// from becoming current the moment its header is on screen.
  void _recomputeCurrentStep() {
    final ctx = _scroll.position.context.notificationContext;
    final box = ctx?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final readingLine = box.localToGlobal(Offset.zero).dy + kPwaStepReadingLine;
    var next = 1;
    for (var i = 0; i < _stepKeys.length; i++) {
      final c = _stepKeys[i].currentContext;
      final b = c?.findRenderObject() as RenderBox?;
      if (b == null) continue;
      if (b.localToGlobal(Offset.zero).dy <= readingLine) {
        next = i + 1;
      } else {
        break;
      }
    }
    // At the very bottom, the last step IS the one being read — it simply
    // cannot be scrolled to the top, because there is nothing beneath it to
    // scroll. Without this, tapping "4" moves the page as far as it goes and
    // the rail keeps highlighting 3, which reads as a control that did not
    // work. iOS has the same arithmetic and the same blind spot; the web
    // notices it because its sections are taller.
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 1) next = _stepKeys.length;
    if (next != _currentStep && mounted) setState(() => _currentStep = next);
  }

  /// Bring [step]'s badge to the top of the reading area.
  ///
  /// iOS calls `Scrollable.ensureVisible(alignment: 0.05)` on the whole step
  /// SECTION. Ported literally, that measured wrong in a browser: tapping a
  /// step moved the page part of the way and left the previous one filling the
  /// screen, and repeated taps crept toward the target instead of landing on
  /// it.
  ///
  /// The cause is the target, not the call. `ensureVisible` resolves an
  /// alignment against `viewport - target`, which goes negative once the
  /// target is taller than the viewport — and a step section routinely is: the
  /// same copy wraps to more lines in French and Khmer than in English, and
  /// the rooms are a grid rather than a row. iOS gets away with it on a phone;
  /// the web does not.
  ///
  /// The fix is to anchor on the BADGE, which is 26px tall in every language
  /// and on every screen. `ensureVisible` then has one correct answer, and the
  /// same anchor tells [_recomputeCurrentStep] which step is being read — so
  /// the jump and the rail can never disagree.
  /// …and it VERIFIES, because one call is not enough in a browser.
  ///
  /// Measured on the deployed build: a single `ensureVisible` consistently
  /// landed short, and tapping the same node again crept closer — the
  /// signature of a scroll animation cut off by a relayout while it was
  /// running. This page has several things that can relayout mid-flight: six
  /// multi-megabyte room photographs decoding, the web fonts swapping in, and
  /// the billing watcher pushing state through the provider the build reads.
  ///
  /// Rather than hunt each one, the jump re-measures after it settles and
  /// corrects once if the badge is not where it was sent. Bounded, so it can
  /// never become a loop, and a no-op in the normal case where the first pass
  /// lands.
  Future<void> _scrollToStep(int step) async {
    if (_jumping) return;
    _jumping = true;
    try {
      final target = _offsetOfStep(step);
      if (target == null) return;
      await _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOutCubic,
      );
      if (!mounted) return;
      // Let the frame that follows the animation actually lay out before
      // measuring. Without this the residual is read in the same microtask the
      // drift completed in — ahead of any relayout still queued — and the
      // correction is computed from stale geometry, which is how the first
      // attempt at this managed to "correct" to the wrong place.
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return;
      // Then LAND IT. The animation can be cut short by a relayout while it
      // runs — this page has candidates (six multi-megabyte room photographs
      // decoding, the web fonts swapping in, the billing watcher pushing state
      // through the provider this build reads), and on the deployed build a
      // tap consistently arrived short while a second tap only crept closer.
      //
      // So the animation carries the motion and an instantaneous correction
      // guarantees the destination, re-measured after everything has settled.
      // A jump cannot be interrupted, so this always terminates, and in the
      // normal case the correction is zero and invisible.
      final residual = _offsetOfStep(step);
      if (residual != null &&
          (residual - _scroll.offset).abs() > kPwaStepLandingTolerance) {
        _scroll.jumpTo(residual);
      }
    } finally {
      _jumping = false;
      if (mounted) _recomputeCurrentStep();
    }
  }

  /// The scroll offset that puts [step]'s badge at the landing point, or null
  /// if the geometry is not available yet. Clamped, so a late step that cannot
  /// come further up simply stops at the end of the page.
  double? _offsetOfStep(int step) {
    if (!_scroll.hasClients) return null;
    final box =
        _stepKeys[step - 1].currentContext?.findRenderObject() as RenderBox?;
    final viewport = _scroll.position.context.notificationContext
        ?.findRenderObject() as RenderBox?;
    if (box == null || viewport == null) return null;
    // Two absolute positions, subtracted — the SAME form
    // [_recomputeCurrentStep] uses and the reason the rail has always been
    // right. The `ancestor:` overload was tried first and produced a target
    // that was silently short; it only returns a relative offset when the
    // ancestor really is one in the render tree, and quietly falls back
    // otherwise. Subtraction cannot fall back.
    final dy = box.localToGlobal(Offset.zero).dy -
        viewport.localToGlobal(Offset.zero).dy;
    final inset = viewport.size.height * kPwaStepLandingAlignment;
    return (_scroll.offset + dy - inset)
        .clamp(0.0, _scroll.position.maxScrollExtent);
  }

  PwaController get _controller => ref.read(pwaControllerProvider.notifier);

  Future<void> _pick() async {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (x == null) return;
    final img = await ImagePipeline.fromXFile(x);
    _controller.setSource(img, origin: PwaImageOrigin.userUpload);
  }

  Future<void> _useExample(String assetPath) async {
    final img = await ImagePipeline.fromAsset(assetPath);
    if (!mounted) return;
    _controller.setSource(img, origin: PwaImageOrigin.bundledExample);
  }

  /// The only place Step 4's text leaves this screen. Trimmed here so the
  /// controller receives what mobile's `_start` sends: the brief, or nothing.
  void _generate() =>
      _controller.generateFirstVision(userInstruction: _desc.text.trim());

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    final state = ref.watch(pwaControllerProvider);
    final hasPhoto = state.source != null;
    final wide = MediaQuery.sizeOf(context).width >= kPwaCreateWideBreakpoint;

    final content = _StepColumn(
      scroll: _scroll,
      stepKeys: _stepKeys,
      state: state,
      desc: _desc,
      onPick: _pick,
      onExample: _useExample,
      onRemove: _controller.removeSource,
      onSelectRoom: _controller.selectRoom,
      onSelectAtmosphere: _controller.selectEntryAtmosphere,
    );

    return PwaScreen(
      key: const ValueKey('pwa-create'),
      // The CTA is capped to the same column as the content. Without this the
      // button stretched the full window on a desktop browser — a 1400px pill
      // under a 760px flow, which is the sort of thing that only ever happens
      // on a platform the design was not drawn for.
      footer: _FooterColumn(
        children: [
          PwaPrimaryButton(
            key: const ValueKey('pwa-generate'),
            label: '${l.uplGenerateDesign} ✨',
            onPressed: hasPhoto ? _generate : null,
          ),
          const SizedBox(height: PwaGap.sm),
          // iOS puts the same line under its CTA: what will happen, or what is
          // still missing. It is the reason a disabled button is never a dead
          // end on either platform.
          Text(
            hasPhoto ? l.uplWillCreate : l.uploadCta,
            textAlign: TextAlign.center,
            style: PwaType.caption(),
          ),
        ],
      ),
      child: Column(
        children: [
          _CreateHeader(
            onClose: _controller.openHome,
            onProjects: _controller.openLibrary,
          ),
          if (!wide)
            _StepperTop(current: _currentStep, onStep: _scrollToStep),
          Expanded(
            // topCenter, NOT center. `Center` centres on BOTH axes, and a
            // SingleChildScrollView under a loose vertical constraint shrinks
            // to its content — so on any viewport taller than the page (a
            // desktop window, a tall capture) the whole flow floated with a
            // band of dead canvas above Step 1 and below the CTA. Only the
            // horizontal centring was ever wanted.
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: kPwaCreateMaxContent),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                                PwaGap.page, PwaGap.lg, 0, 0),
                            child: _StepperSide(
                                current: _currentStep, onStep: _scrollToStep),
                          ),
                          Expanded(child: content),
                        ],
                      )
                    : content,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The sticky CTA, held to the content column's width.
class _FooterColumn extends StatelessWidget {
  const _FooterColumn({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kPwaCreateMaxContent),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      );
}

/// The header. A close that returns Home — iOS's own `Icons.close` leading
/// action — plus the two affordances a browser tab needs and a phone does not:
/// the language switcher and the identity chip.
class _CreateHeader extends StatelessWidget {
  const _CreateHeader({required this.onClose, required this.onProjects});

  final VoidCallback onClose;
  final VoidCallback onProjects;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          PwaGap.page, PwaGap.sm, PwaGap.page, PwaGap.sm),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('pwa-create-home'),
            onPressed: onClose,
            tooltip: l.backHome,
            icon: const Icon(Icons.close, color: pwaInk),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          const SizedBox(width: PwaGap.sm),
          Expanded(
            child: Text(
              l.uploadTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PwaType.cardTitle(),
            ),
          ),
          IconButton(
            key: const ValueKey('pwa-compact-projects'),
            onPressed: onProjects,
            tooltip: l.myProjects,
            icon: const Icon(Icons.grid_view_rounded, color: pwaInk, size: 20),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          const PwaLanguageSwitcher(compact: true),
          const PwaAccountChip(),
        ],
      ),
    );
  }
}

/// The scrolling body: four sections, `xxl` apart, in iOS's order.
class _StepColumn extends StatelessWidget {
  const _StepColumn({
    required this.scroll,
    required this.stepKeys,
    required this.state,
    required this.desc,
    required this.onPick,
    required this.onExample,
    required this.onRemove,
    required this.onSelectRoom,
    required this.onSelectAtmosphere,
  });

  final ScrollController scroll;
  final List<GlobalKey> stepKeys;
  final PwaState state;
  final TextEditingController desc;
  final VoidCallback onPick;
  final ValueChanged<String> onExample;
  final VoidCallback onRemove;
  final ValueChanged<String?> onSelectRoom;
  final ValueChanged<String> onSelectAtmosphere;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    final bytes = state.source?.bytes;

    return SingleChildScrollView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(
          PwaGap.page, PwaGap.lg, PwaGap.page, PwaGap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── STEP 1 — Upload your space ──────────────────────────────────
          _StepSection(
            anchorKey: stepKeys[0],
            stepNumber: 1,
            title: l.uploadYourSpace,
            subtitle: l.uplStep1Sub,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _UploadZone(
                  key: const ValueKey('pwa-create-upload'),
                  bytes: bytes,
                  onTap: onPick,
                  onRemove: onRemove,
                ),
                if (bytes == null) ...[
                  const SizedBox(height: PwaGap.md),
                  _ExamplesRow(onPick: onExample),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.shield_outlined,
                        size: 14, color: pwaFaint),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(l.uplPrivacy, style: PwaType.caption()),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: PwaGap.xxl),

          // ── STEP 2 — What type of space ─────────────────────────────────
          _StepSection(
            anchorKey: stepKeys[1],
            stepNumber: 2,
            title: l.uplStep2Title,
            subtitle: l.uplStep2Sub,
            child: _RoomPicker(
              selected: state.selectedRoomId,
              onSelect: onSelectRoom,
            ),
          ),
          const SizedBox(height: PwaGap.xxl),

          // ── STEP 3 — Choose your atmosphere ─────────────────────────────
          _StepSection(
            anchorKey: stepKeys[2],
            stepNumber: 3,
            title: l.uplStep3Title,
            subtitle: l.uplStep3Sub,
            child: _AtmospherePicker(
              atmospheres: state.atmospheres,
              selected: state.selectedAtmosphereId ?? 'ayden_signature',
              onSelect: onSelectAtmosphere,
            ),
          ),
          const SizedBox(height: PwaGap.xxl),

          // ── STEP 4 — Describe your vision (NEW) ─────────────────────────
          _StepSection(
            anchorKey: stepKeys[3],
            stepNumber: 4,
            title: l.uplStep4Title,
            titleTrailing: PwaOptionalBadge(l.uplOptional),
            subtitle: l.step4Sub,
            child: _VisionBriefField(controller: desc),
          ),
          const SizedBox(height: PwaGap.xxl),
        ],
      ),
    );
  }
}

/// iOS `_StepSection`, measured: badge → 10 → title (+ optional trailing) → 6
/// → subtitle → `lg` → child.
class _StepSection extends StatelessWidget {
  const _StepSection({
    required this.anchorKey,
    required this.stepNumber,
    required this.title,
    required this.subtitle,
    required this.child,
    this.titleTrailing,
  });

  final GlobalKey anchorKey;
  final int stepNumber;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? titleTrailing;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // THE ANCHOR IS THE BADGE, not the section.
        //
        // Anchoring on the section made both the jump and the current-step
        // read unreliable, because a section is routinely taller than the
        // viewport, and every reveal-this calculation in Flutter degrades on
        // a target that does not fit. A badge is 26px tall on every screen, in
        // every language, so `ensureVisible` has one correct answer for it.
        KeyedSubtree(
          key: anchorKey,
          child: PwaStepPill(l.uplStepBadge(stepNumber)),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                title,
                // iOS `displayEditorial(22, w500, height 1.18, ls -0.2)`.
                // French and Khmer are longer than the English this was set
                // for, so the web wraps where the phone does not.
                style: PwaType.atmosphereTitle(fontSize: 22).copyWith(
                  fontWeight: FontWeight.w500,
                  height: 1.18,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            if (titleTrailing != null) ...[
              const SizedBox(width: PwaGap.sm),
              titleTrailing!,
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(subtitle, style: PwaType.bodyMuted()),
        const SizedBox(height: PwaGap.lg),
        child,
      ],
    );
  }
}

// ── the stepper ─────────────────────────────────────────────────────────────

/// Horizontal rail under the header — iOS `_StepperTop`, phones and narrow
/// windows.
class _StepperTop extends StatelessWidget {
  const _StepperTop({required this.current, required this.onStep});

  final int current;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('pwa-create-stepper'),
        padding: const EdgeInsets.fromLTRB(PwaGap.page, 12, PwaGap.page, 12),
        decoration: const BoxDecoration(
          color: pwaCanvas,
          border: Border(bottom: BorderSide(color: pwaHairlineSoft)),
        ),
        child: Row(
          children: List.generate(
            4,
            (i) => Expanded(
              child: _StepperNode(
                step: i + 1,
                current: current,
                isLast: i == 3,
                vertical: false,
                onTap: () => onStep(i + 1),
              ),
            ),
          ),
        ),
      );
}

/// Vertical rail beside the content — iOS `_StepperSide`, tablets and desktop.
class _StepperSide extends StatelessWidget {
  const _StepperSide({required this.current, required this.onStep});

  final int current;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) => Column(
        key: const ValueKey('pwa-create-stepper'),
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          4,
          (i) => _StepperNode(
            step: i + 1,
            current: current,
            isLast: i == 3,
            vertical: true,
            onTap: () => onStep(i + 1),
          ),
        ),
      );
}

/// iOS `_StepperNode`: a 28px numbered circle, ink when current or passed,
/// with a connector to the next one.
class _StepperNode extends StatelessWidget {
  const _StepperNode({
    required this.step,
    required this.current,
    required this.isLast,
    required this.vertical,
    required this.onTap,
  });

  final int step;
  final int current;
  final bool isLast;
  final bool vertical;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isCurrent = step == current;
    final isPast = step < current;
    final filled = isCurrent || isPast;

    final circle = AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: filled ? pwaInk : pwaSurface,
        shape: BoxShape.circle,
        border: Border.all(
          color: filled ? pwaInk : pwaHairline,
          width: isCurrent ? 1.6 : 1,
        ),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: pwaInk.withValues(alpha: 0.18),
                  blurRadius: 16,
                ),
              ]
            : const [],
      ),
      alignment: Alignment.center,
      child: Text(
        '$step',
        style: PwaType.caption(color: filled ? pwaSurface : pwaFaint)
            .copyWith(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );

    final connector = isPast ? pwaInk.withValues(alpha: 0.4) : pwaHairline;

    return Semantics(
      button: true,
      selected: isCurrent,
      label: context.pwaL10n.uplStepBadge(step),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: vertical
            ? Column(
                children: [
                  circle,
                  if (!isLast)
                    Container(
                      width: 1,
                      height: 36,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: connector,
                    ),
                ],
              )
            : Row(
                children: [
                  circle,
                  if (!isLast)
                    Expanded(
                      child: Container(
                        height: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        color: connector,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

// ── step 1 ──────────────────────────────────────────────────────────────────

/// iOS `_UploadZone`: 4:3, well-coloured and hairlined when empty, gold-bordered
/// with the photo LETTERBOXED when filled.
///
/// Letterboxed, not cropped, is the part that matters and iOS annotates it as
/// such: cover-cropping a portrait photo to 4:3 hides the part of the room the
/// customer is asking to have redesigned.
///
/// The old web zone advertised "or drag & drop it here". There is no drop
/// target in this build and never was — no `DropTarget`, no drag listener, the
/// whole panel is an InkWell — so the sentence promised a gesture that silently
/// did nothing on the desktop browsers most likely to try it. Following iOS
/// retires the claim. Real drop support needs a package, and `pubspec.yaml` is
/// shared with the frozen mobile app, so it is a separate change rather than
/// something to bolt on here.
class _UploadZone extends StatelessWidget {
  const _UploadZone({
    super.key,
    required this.bytes,
    required this.onTap,
    required this.onRemove,
  });

  final Uint8List? bytes;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    final filled = bytes != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: filled ? pwaSurface : pwaWell,
          borderRadius: BorderRadius.circular(PwaGap.radius),
          border: Border.all(
            color: filled ? pwaGold : pwaHairline,
            width: filled ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: filled
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: pwaImageFrame),
                    // An undecodable byte string is a possibility on the web —
                    // a truncated read, a file the browser named .jpg and did
                    // not encode as one. It must render as an empty frame the
                    // person can replace, never as an exception into the
                    // framework. iOS has no equivalent risk: it hands over a
                    // File the system already decoded.
                    Image.memory(
                      bytes!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: pwaImageFrame),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: _ZoneAction(
                        key: const ValueKey('pwa-create-replace'),
                        icon: Icons.edit_outlined,
                        label: l.replacePhoto,
                        onTap: onTap,
                      ),
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: _ZoneAction(
                        key: const ValueKey('pwa-create-remove'),
                        icon: Icons.close,
                        label: l.removePhoto,
                        onTap: onRemove,
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_photo_alternate_outlined,
                        size: 30, color: pwaFaint),
                    const SizedBox(height: 12),
                    Text(
                      l.uploadPrompt,
                      textAlign: TextAlign.center,
                      style: PwaType.bodyMuted(color: pwaMuted)
                          .copyWith(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    // What the staging bucket actually accepts — the web
                    // allowlist, not iOS's "JPG · PNG · HEIC", because a HEIC
                    // dropped here would be refused on upload.
                    Text(l.fileConstraints, style: PwaType.caption()),
                  ],
                ),
        ),
      ),
    );
  }
}

/// A dark pill over the loaded photo — iOS `AppPill(dark: true)`.
class _ZoneAction extends StatelessWidget {
  const _ZoneAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: Material(
          color: pwaImageFrame.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(PwaGap.radiusPill),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(PwaGap.radiusPill),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: pwaOnDark),
                  const SizedBox(width: 6),
                  Text(label, style: PwaType.caption(color: pwaOnDark)),
                ],
              ),
            ),
          ),
        ),
      );
}

/// The bundled example rooms — web-only, and kept because a browser visitor
/// with no photo to hand still has to be able to see what the product does.
/// Leaves with the drop zone, exactly as before.
class _ExamplesRow extends StatelessWidget {
  const _ExamplesRow({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.orStartWithExample, style: PwaType.caption()),
        const SizedBox(height: PwaGap.sm),
        SizedBox(
          // 56 thumbnail + 4 + one caption line (12 × 1.4 = 16.8), rounded up.
          // Stated rather than eyeballed: at 76 this overflowed by exactly the
          // 0.8px the line height contributes.
          height: 80,
          child: ScrollConfiguration(
            // A mouse does not drag a horizontal list by default. On a desktop
            // browser that is the difference between a strip that scrolls and
            // one that appears stuck.
            behavior: const MaterialScrollBehavior().copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
                PointerDeviceKind.stylus,
              },
              scrollbars: false,
            ),
            child: ListView.separated(
              key: const ValueKey('pwa-examples'),
              scrollDirection: Axis.horizontal,
              primary: false,
              physics: const ClampingScrollPhysics(),
              itemCount: kPwaExamples.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final (label, asset) = kPwaExamples[i];
                // Displayed localised, keyed by the EN catalogue label — the
                // mapping the old strip already used, moved verbatim.
                final display = switch (label) {
                  'Living Room' => l.roomLabel('living_room'),
                  'Bedroom' => l.roomLabel('master_bedroom'),
                  'Kitchen' => l.roomLabel('kitchen'),
                  _ => label,
                };
                return Semantics(
                  button: true,
                  label: l.startWithExample(display),
                  child: GestureDetector(
                    onTap: () => onPick(asset),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.asset(
                            asset,
                            width: 84,
                            height: 56,
                            // These are the FULL-SIZE example rooms (2.4 MB and
                            // 2.5 MB of JPEG) also used as a generation source,
                            // so they cannot be swapped for thumbnails. Without
                            // a cap the browser decodes each at its native
                            // resolution to paint an 84px box — measured as a
                            // visible delay before the strip appears at all.
                            // 3× the box covers every DPR this ships to.
                            cacheWidth: 252,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox(
                              width: 84,
                              height: 56,
                              child: ColoredBox(color: pwaWell),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 84,
                          child: Text(
                            display,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PwaType.caption(),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ── step 2 ──────────────────────────────────────────────────────────────────

/// iOS `_RoomScroller` under `newDesignCards`: Ayden Decide + the hero rooms in
/// a grid, then "More spaces →" and the rest in a horizontal strip.
///
/// The web keeps iOS's two columns on a phone and three from 600px up, and uses
/// the SAME `RoomCard` / `AiActionCard` widgets. The dark PWA-only
/// `PwaSelectCard` is not used here: its caption is `pwaOnDark`, which is
/// invisible on the cream canvas, and restyling a web-only card would have been
/// more invention than reusing the one iOS ships.
///
/// NO LOCKS. iOS gates rooms behind `premiumProvider` and opens a StoreKit
/// paywall on a locked tap. The web sells one-time credit packs through ABA and
/// meters at generation time, so every room is selectable here and the Billing
/// Engine answers at Generate — unchanged by this phase.
class _RoomPicker extends StatelessWidget {
  const _RoomPicker({required this.selected, required this.onSelect});

  /// null = Ayden Decide (auto-detect).
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    final more = [
      for (final r in kPwaRooms)
        if (!kHeroRooms.any((h) => h.id == r.id)) r,
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 600 ? 3 : 2;
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
                AiActionCard(
                  key: const ValueKey('pwa-room-ayden-decide'),
                  title: l.uplAiDecide,
                  subtitle: l.autoDetect,
                  selected: selected == null,
                  onTap: () => onSelect(null),
                  backgroundImageAsset: 'assets/branding/ayden_decide_card.png',
                ),
                for (final r in kHeroRooms) _card(context, r),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  l.uplMoreSpaces,
                  style: PwaType.cardSubtitle()
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward, size: 15, color: pwaFaint),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: secH,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: more.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) =>
                    SizedBox(width: secW, child: _card(context, more[i])),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _card(BuildContext context, RoomCardData r) => RoomCard(
        key: ValueKey('pwa-room-${r.id}'),
        // Display localises; the VALUE routed to the controller stays the
        // canonical card ID, exactly as before this phase. The English-label
        // contract lives further down, in the repository — untouched here.
        label: context.pwaL10n.roomCardLabel(r.id, r.label),
        asset: r.asset,
        selected: selected == r.id,
        onTap: () => onSelect(r.id),
      );
}

// ── step 3 ──────────────────────────────────────────────────────────────────

/// iOS `_AtmosphereScroller` under `newDesignCards`: a page-snapped carousel of
/// mini-hero cards at 80% of the width, ratio 1.2, Ayden Signature first.
///
/// The order comes from `kPwaPopularAtmosphereIds` — the same MVP list the web
/// already showed, with Ayden Signature leading — so nothing about which
/// atmospheres exist or in what order changes; only how they are drawn.
class _AtmospherePicker extends StatefulWidget {
  const _AtmospherePicker({
    required this.atmospheres,
    required this.selected,
    required this.onSelect,
  });

  final List<PwaAtmosphere> atmospheres;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  State<_AtmospherePicker> createState() => _AtmospherePickerState();
}

class _AtmospherePickerState extends State<_AtmospherePicker> {
  // Held rather than rebuilt: iOS constructs a PageController inline every
  // build, which on the web resets the carousel's position on every keystroke
  // in Step 4. Same viewportFraction, one instance.
  final _pages = PageController(viewportFraction: 0.80);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    final byId = {for (final a in widget.atmospheres) a.id: a};
    final ordered = <PwaAtmosphere>[
      for (final id in kPwaPopularAtmosphereIds)
        if (byId[id] != null) byId[id]!,
      for (final a in widget.atmospheres)
        if (!kPwaPopularAtmosphereIds.contains(a.id)) a,
    ];

    return LayoutBuilder(
      builder: (context, c) => SizedBox(
        height: c.maxWidth * 0.80 / 1.2,
        child: PageView.builder(
          controller: _pages,
          padEnds: false,
          itemCount: ordered.length,
          itemBuilder: (context, i) {
            final a = ordered[i];
            final signature = a.id == 'ayden_signature';
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: AtmosphereHeroCard(
                key: ValueKey('pwa-atmos-${a.id}'),
                // The AYDEN SIGNATURE wordmark is baked into that card's art,
                // so iOS leaves the name blank and lets the image carry it.
                name: signature ? '' : a.name,
                subtitle: signature
                    ? l.selectedByAyden
                    : l.atmosphereSubtitle(a.id),
                // Ayden Signature is NOT in `kAtmosphereCardById` — it is a
                // delegation, not an atmosphere — so the generic fallback
                // resolved to `assets/cards/atmospheres/ayden_signature.png`,
                // which does not exist, and the lead card of Step 3 rendered
                // as a black rectangle. iOS names its art explicitly for the
                // same reason; so does this.
                asset: signature
                    ? kPwaSignatureCardAsset
                    : (kAtmosphereCardById[a.id]?.asset ??
                        'assets/cards/atmospheres/${a.id}.png'),
                selected: widget.selected == a.id,
                onTap: () => widget.onSelect(a.id),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── step 4 ──────────────────────────────────────────────────────────────────

/// The free-text brief. iOS `_DescriptionField`, minus the microphone.
///
/// Geometry is iOS's: min 3 / max 5 lines, `surfaceVariant` fill, 16 padding,
/// card radius, hairline border that turns gold at 1.5px on focus.
class _VisionBriefField extends StatelessWidget {
  const _VisionBriefField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(PwaGap.radius),
          borderSide: BorderSide(color: c, width: w),
        );

    return TextField(
      key: const ValueKey('pwa-create-brief'),
      controller: controller,
      minLines: 3,
      maxLines: 5,
      textInputAction: TextInputAction.newline,
      keyboardType: TextInputType.multiline,
      style: PwaType.body().copyWith(fontSize: 15),
      decoration: InputDecoration(
        hintText: l.step4Hint,
        hintStyle: PwaType.bodyMuted(color: pwaFaint),
        filled: true,
        fillColor: pwaWell,
        contentPadding: const EdgeInsets.all(16),
        border: border(pwaHairline),
        enabledBorder: border(pwaHairline),
        focusedBorder: border(pwaGold, 1.5),
      ),
    );
  }
}
