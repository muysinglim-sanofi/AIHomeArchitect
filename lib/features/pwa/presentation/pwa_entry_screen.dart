/// Tranche 1.4 — Inline ROOM & ATMOSPHERE selection (approved fast-path mockup).
///
/// The product value is: photo → Ayden Decide (room) & Ayden Signature
/// (atmosphere) already prepared → Generate immediately. Room/atmosphere
/// galleries are hidden behind progressive disclosure ("More rooms" / "More
/// atmospheres", one-open-at-a-time). The default user never opens either.
///
///   ┌─ Hero (pinned)  cinematic 5.4s → collapses FAST to a slim 72/92px bar
///   ▼
///   └─ WORKSPACE (one viewport, morphs in place — no navigation):
///        • no photo  → upload showroom (editorial + large canvas)
///        • has photo → LEFT photo · RIGHT [ROOM: Ayden Decide + selected card +
///                      More rooms] [ATMOSPHERE: Ayden Signature + selected card
///                      + More atmospheres] and an anchored "Generate my vision".
///
/// Room & atmosphere cards use the shared PWA card [PwaSelectCard] (image +
/// external caption) driven by the app's own card_catalog metadata — offline
/// (Image.asset), no service/network. Fully offline. Reduced-motion → final frame.
library;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/media/image_pipeline.dart';
import '../../cards/card_catalog.dart';
import '../application/pwa_controller.dart';
import '../application/pwa_layout.dart';
import '../domain/pwa_models.dart';
import 'pwa_brand.dart';
import 'pwa_select_card.dart';
import 'pwa_theme.dart';
import '../l10n/pwa_l10n.dart';

/// Which fast-path selector is expanded (one-open-at-a-time accordion).
enum PwaExpandedSelector { none, room, atmosphere }

// Cinematic timeline (fractions of the ~5.4s sequence). The logo is held at
// FULL opacity for ~1.35s (0.05→0.30) so it never "disappears too quickly".
const double kHeroLogoRevealEnd = 0.05; //  ~0.27s — gentle reveal complete
const double kHeroLogoHoldEnd = 0.30; //    ~1.62s — full logo held & readable
const double kHeroRoomInEnd = 0.481; //     ~2.6s — empty room fully present
const double kHeroTransformEnd = 0.815; //  ~4.4s — transformation complete

/// All selectable rooms, in the app's canonical order (hero then more spaces).
const List<RoomCardData> kPwaRooms = [...kHeroRooms, ...kMoreRooms];

/// Post-upload ROOM row order (existing catalog only — nothing invented, no
/// duplicated labels/paths; resolved by id). Popular = the reference's visible
/// set (Ayden Decide is prepended separately); "More rooms" appends the rest.
const List<String> kPwaPopularRoomIds = <String>[
  'livingRoom',
  'masterBedroom',
  'kitchen',
  'bathroom',
  'homeOffice',
];
List<RoomCardData> pwaPopularRooms() => [
  for (final id in kPwaPopularRoomIds) pwaRoomById(id)!,
];
List<RoomCardData> pwaOptionalRooms() => [
  for (final r in kPwaRooms)
    if (!kPwaPopularRoomIds.contains(r.id)) r,
];

/// Post-upload ATMOSPHERE visible catalog (PWA-only ordered list of existing
/// ids, starting with the preselected Ayden Signature). All MVP atmospheres are
/// visible by default — Nordic Warmth included — so there is no optional
/// atmosphere; the "More/Fewer atmospheres" toggle simply hides itself when a
/// level has nothing more to reveal (ROOM still has its optional rooms).
const List<String> kPwaPopularAtmosphereIds = <String>[
  'ayden_signature',
  'warm_modern',
  'soft_luxury',
  'japandi_calm',
  'tropical_escape',
  'nordic_warmth',
];

/// Collapsed sticky-header height: a slim brand bar, NOT a half-screen banner.
double pwaCollapsedHeaderExtent(bool isMobile) => isMobile ? 72.0 : 92.0;

/// Gap between two cards in a selection carousel.
const double kPwaCardGap = 12;

/// How many primary choices must read at a glance in a selection row.
const int kPwaVisibleChoices = 5;

/// The card width that lets [kPwaVisibleChoices] cards sit fully inside a row of
/// [rowWidth]. The mandated desktop composition (45/55, padding 48, maxWidth
/// 1440) yields a ~715px selection column, where the full-size 158px card only
/// fits four — so the card scales down rather than the row clipping a choice.
/// Clamped so cards never become unreadable, and never grow past their design
/// footprint on very wide screens.
double pwaCardWidthFor(double rowWidth) {
  if (rowWidth <= 0) return kPwaCardW;
  final fit =
      (rowWidth - kPwaCardGap * (kPwaVisibleChoices - 1)) / kPwaVisibleChoices;
  return fit.clamp(124.0, kPwaCardW);
}

/// Height a [PwaSelectCard] needs at [cardWidth].
///
/// Only the image scales with the width (it is an `AspectRatio(3/2)`); the
/// caption block underneath keeps its intrinsic height. Scaling the whole card
/// proportionally therefore starves the caption and overflows it — this keeps
/// the caption allowance constant and lets only the image shrink.
double pwaCardHeightFor(double cardWidth) =>
    cardWidth / 1.5 + (kPwaCardH - kPwaCardW / 1.5);

/// Pure: room/gold-line reveal fraction (0→1) for timeline position [t].
double heroRoomReveal(double t) =>
    ((t - kHeroRoomInEnd) / (kHeroTransformEnd - kHeroRoomInEnd)).clamp(
      0.0,
      1.0,
    );

/// Pure: how far the pinned hero has collapsed toward the slim bar (0→1).
double entryCollapse(double shrinkOffset, double range) =>
    range <= 0 ? 1.0 : (shrinkOffset / range).clamp(0.0, 1.0);

/// Short subtitle for an atmosphere id (from the app card catalog).
/// A top-level helper has no BuildContext, so it cannot localize. It returns
/// the catalog subtitle or the EMPTY string, and the caller — which does have a
/// context — supplies `PwaL10n.selectedByAyden` for Ayden Signature. Reaching
/// for a context here is what produced the compile error; passing the localized
/// default down is the fix, not a global.
String pwaAtmosphereSubtitle(String id) =>
    kAtmosphereCardById[id]?.subtitle ?? '';

/// Room metadata by id (null id / unknown → null = Ayden auto-detect).
RoomCardData? pwaRoomById(String? id) {
  if (id == null) return null;
  for (final r in kPwaRooms) {
    if (r.id == id) return r;
  }
  return null;
}

class PwaEntryScreen extends ConsumerStatefulWidget {
  const PwaEntryScreen({super.key});

  @override
  ConsumerState<PwaEntryScreen> createState() => _PwaEntryScreenState();
}

class _PwaEntryScreenState extends ConsumerState<PwaEntryScreen> {
  final _picker = ImagePicker();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    pwaHardenDebugPaints(); // no debug baseline/size overlays
    // Reused app cards (RoomCard/AtmosphereHeroCard → AppTheme uses google_fonts):
    // keep the PWA fully offline — no runtime font fetch, ever.
    pwaDisableRemoteFonts();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  // §4 — global access to the My Projects library from the slim brand bar.
  void _openLibrary() => ref.read(pwaControllerProvider.notifier).openLibrary();
  void _openHome() => ref.read(pwaControllerProvider.notifier).openHome();

  void _selectRoom(String? id) =>
      ref.read(pwaControllerProvider.notifier).selectRoom(id);
  void _selectAtmosphere(String id) =>
      ref.read(pwaControllerProvider.notifier).selectEntryAtmosphere(id);

  Future<void> _pick() async {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (x == null) return;
    final img = await ImagePipeline.fromXFile(x);
    ref
        .read(pwaControllerProvider.notifier)
        .setSource(img, origin: PwaImageOrigin.userUpload);
    // UX-A1 — the composition no longer swaps screens: the photo simply replaces
    // the drop zone in place, so there is nothing to scroll to.
  }

  /// Load one of the bundled example rooms as the local source. Same seam as a
  /// real pick — no second selection path, no durable project, no upload.
  Future<void> _useExample(String assetPath) async {
    final img = await ImagePipeline.fromAsset(assetPath);
    if (!mounted) return;
    ref
        .read(pwaControllerProvider.notifier)
        .setSource(img, origin: PwaImageOrigin.bundledExample);
  }

  void _remove() => ref.read(pwaControllerProvider.notifier).removeSource();
  void _generate() =>
      ref.read(pwaControllerProvider.notifier).generateFirstVision();

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pwaControllerProvider);
    final Uint8List? bytes = state.source?.bytes;

    // Material provides the ink canvas for the reused app cards / buttons and
    // paints the black backdrop.
    return Material(
      color: pwaBlack,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, c) {
            final ff = pwaFormFactorForWidth(c.maxWidth);
            final isMobile = ff == PwaFormFactor.mobile;
            final twoPane = ff == PwaFormFactor.desktop;

            // Create is a step, not the front door: the cinematic belongs to the
            // Home dashboard, so nothing overlays this screen.
            return Column(
              children: [
                _SlimBar(
                  isMobile: isMobile,
                  onHome: _openHome,
                  onProjects: _openLibrary,
                ),
                Expanded(
                  child: _CreateWorkspace(
                    key: const ValueKey('pwa-create'),
                    twoPane: twoPane,
                    isMobile: isMobile,
                    bytes: bytes,
                    atmospheres: state.atmospheres,
                    selectedRoomId: state.selectedRoomId,
                    selectedAtmosphereId:
                        state.selectedAtmosphereId ?? 'ayden_signature',
                    onPick: _pick,
                    onExample: _useExample,
                    onRemove: _remove,
                    onGenerate: _generate,
                    onSelectRoom: _selectRoom,
                    onSelectAtmosphere: _selectAtmosphere,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The permanent slim brand bar of the Create screen. Present from the first
/// frame — Create sits directly beneath it and is never scrolled to. Carries the
/// two global affordances: back to Home, and My Projects.
class _SlimBar extends StatelessWidget {
  const _SlimBar({
    required this.isMobile,
    required this.onHome,
    required this.onProjects,
  });
  final bool isMobile;
  final VoidCallback onHome;
  final VoidCallback onProjects;
  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('pwa-slim-bar'),
      height: pwaCollapsedHeaderExtent(isMobile),
      decoration: const BoxDecoration(
        color: pwaBlack,
        border: Border(bottom: BorderSide(color: Color(0x22FFFFFF), width: 1)),
      ),
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 18 : 36),
      child: Row(
        children: [
          // Create is reached FROM Home, so it always offers the way back.
          Semantics(
            button: true,
            label: context.pwaL10n.backHome,
            child: Tooltip(
              message: context.pwaL10n.backHome,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  key: const ValueKey('pwa-create-home'),
                  onTap: onHome,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      size: 20,
                      color: pwaOnDark.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          const PwaLogoBadge(size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              // Branding is stable across both Create states — selecting a photo
              // is not yet a project, so the bar must not rename itself.
              'Ayden Studio',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: pwaSans(
                fontSize: 13.5,
                color: pwaOnDark,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(width: 8),

          _CompactProjectsButton(isMobile: isMobile, onTap: onProjects),
        ],
      ),
    );
  }
}

/// My Projects access on the collapsed brand bar — text on desktop, icon on
/// mobile. Discreet, and never present over the frozen cinematic (this bar only
/// appears once the hero has collapsed).
class _CompactProjectsButton extends StatelessWidget {
  const _CompactProjectsButton({required this.isMobile, required this.onTap});
  final bool isMobile;
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
            key: const ValueKey('pwa-compact-projects'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 6 : 10,
                vertical: 6,
              ),
              child: isMobile
                  ? Icon(
                      Icons.grid_view_rounded,
                      size: 19,
                      color: pwaOnDark.withValues(alpha: 0.8),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.grid_view_rounded,
                          size: 16,
                          color: pwaOnDark.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          context.pwaL10n.myProjects,
                          style: pwaSans(
                            fontSize: 13,
                            color: pwaOnDark.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Shared chrome ─────────────────────────────────────────────────────────────

// ── Create workspace: ONE composition, two states ─────────────────────────────

/// Reassurance under the source pane — where the photo actually is.
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();
  @override
  Widget build(BuildContext context) {
    final muted = pwaOnDark.withValues(alpha: 0.45);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, size: 14, color: muted),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              context.pwaL10n.dataPrivate,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: pwaSans(fontSize: 12, color: muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// The single commercial footnote, under the primary CTA.
class _CreateFooter extends StatelessWidget {
  const _CreateFooter({required this.isMobile});
  final bool isMobile;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: isMobile ? 12 : 14),
      child: Text(
        context.pwaL10n.firstVisionFree,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: pwaSans(fontSize: 12, color: pwaOnDark.withValues(alpha: 0.45)),
      ),
    );
  }
}

/// The bundled example rooms offered before any source is chosen. Assets are
/// already shipped with the app — nothing is downloaded and no dependency added.
const List<(String, String)> kPwaExamples = [
  ('Living Room', 'assets/examples/living_room.jpg'),
  ('Bedroom', 'assets/examples/bedroom.jpg'),
  ('Kitchen', 'assets/examples/kitchen.jpg'),
];

/// Compact horizontal strip of example rooms. Scrolls rather than wraps, so it
/// never grows tall enough to push the drop zone off a short viewport.
class _ExamplesStrip extends StatelessWidget {
  const _ExamplesStrip({required this.onPick});
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.pwaL10n.orStartWithExample,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: pwaSans(
            fontSize: 12.5,
            color: pwaOnDark.withValues(alpha: 0.55),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 84,
          child: ScrollConfiguration(
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
                return _ExampleCard(
                  // Displayed localized, keyed by the EN catalog label. The
                  // tuple's label stays English because it is also the room
                  // the example stands for.
                  label: switch (label) {
                    'Living Room' => context.pwaL10n.roomLabel('living_room'),
                    'Bedroom' => context.pwaL10n.roomLabel('master_bedroom'),
                    'Kitchen' => context.pwaL10n.roomLabel('kitchen'),
                    _ => label,
                  },
                  asset: asset,
                  onTap: () => onPick(asset),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ExampleCard extends StatelessWidget {
  const _ExampleCard({
    required this.label,
    required this.asset,
    required this.onTap,
  });
  final String label;
  final String asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.pwaL10n.startWithExample(label),
      child: SizedBox(
        width: 112,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    height: 58,
                    width: 112,
                    child: Image.asset(
                      asset,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: pwaCharcoal),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: pwaSans(
                    fontSize: 11.5,
                    color: pwaOnDark.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w500,
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

/// Premium secondary action card — "Try an example / See how it works".
///
/// UX-A1 — no longer surfaced in Create (absent from the approved mockup). Kept
/// with its loader ([_PwaEntryScreenState._useExample]) for the follow-up batch.
// ignore: unused_element
class _TryExampleCard extends StatelessWidget {
  const _TryExampleCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: pwaGold.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: pwaGold.withValues(alpha: 0.12),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    size: 18,
                    color: pwaGold,
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.pwaL10n.tryAnExample,
                      style: pwaSans(
                        fontSize: 14.5,
                        color: pwaOnDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.pwaL10n.seeHowItWorks,
                      style: pwaSans(
                        fontSize: 12.5,
                        color: pwaOnDark.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 18),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: pwaGold.withValues(alpha: 0.8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Premium architectural upload zone — dimmed interior backdrop + gold frame +
/// gold ring icon. Hover (gold response) + focus/keyboard via InkWell. Fills the
/// height it is given (the reference's dominant right surface).
class _DropZone extends StatefulWidget {
  const _DropZone({required this.onPick});
  final VoidCallback onPick;
  @override
  State<_DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<_DropZone> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final border = pwaGold.withValues(alpha: _hover ? 0.9 : 0.5);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(PwaGap.radiusLg),
      child: InkWell(
        onTap: widget.onPick,
        onHover: (h) => setState(() => _hover = h),
        borderRadius: BorderRadius.circular(PwaGap.radiusLg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PwaGap.radiusLg),
            border: Border.all(color: border, width: _hover ? 1.4 : 1.0),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(PwaGap.radiusLg),
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                fit: StackFit.expand,
                children: [
                  // Existing architectural interior asset, heavily dimmed for
                  // depth (never the uploaded user photo, which is absent here).
                  Image.asset(
                    'assets/showcase/living_after.jpg',
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, -0.1),
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: pwaCharcoal),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          pwaBlack.withValues(alpha: _hover ? 0.70 : 0.80),
                          pwaBlack.withValues(alpha: _hover ? 0.82 : 0.90),
                        ],
                      ),
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 78,
                          height: 78,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: pwaGold.withValues(
                              alpha: _hover ? 0.18 : 0.10,
                            ),
                            border: Border.all(
                              color: pwaGold.withValues(
                                alpha: _hover ? 0.95 : 0.75,
                              ),
                              width: 1.4,
                            ),
                          ),
                          child: Icon(
                            Icons.file_upload_outlined,
                            size: 34,
                            color: pwaGold.withValues(alpha: 0.95),
                          ),
                        ),
                        const SizedBox(height: 18),
                        // ONE visible action. The whole zone is the button, and
                        // drag & drop is stated as the alternative rather than
                        // competing with a second control.
                        Text(
                          context.pwaL10n.uploadCta,
                          textAlign: TextAlign.center,
                          style: pwaSans(
                            fontSize: 19,
                            color: pwaOnDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          context.pwaL10n.dragAndDropHint,
                          textAlign: TextAlign.center,
                          style: pwaSans(
                            fontSize: 14,
                            color: pwaOnDark.withValues(alpha: 0.66),
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Exactly what the staging bucket accepts (MIME allowlist
                        // image/jpeg|png|webp, 10 MiB limit) — never a format the
                        // upload would reject.
                        Text(
                          context.pwaL10n.fileConstraints,
                          style: pwaSans(
                            fontSize: 12,
                            color: pwaOnDark.withValues(alpha: 0.45),
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Quiet guidance, bottom-left — only where there is real room
                  // for it (never on a short mobile canvas).
                  if (constraints.maxHeight >= 380)
                    const Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: _UploadTips(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Quiet, non-blocking guidance inside the drop zone.
class _UploadTips extends StatelessWidget {
  const _UploadTips();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: pwaBlack.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lightbulb_outline_rounded,
            size: 16,
            color: pwaGold.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.pwaL10n.tipsForBestResults,
                  style: pwaSans(
                    fontSize: 12.5,
                    color: pwaOnDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  context.pwaL10n.tipBody,
                  style: pwaSans(
                    fontSize: 12,
                    color: pwaOnDark.withValues(alpha: 0.6),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── FAST PATH — photo + ROOM + ATMOSPHERE + Generate, one viewport ───────────

/// UX-A1 — the SINGLE Create composition. The skeleton never changes between
/// "no photo yet" and "photo ready": the left pane holds the drop zone or the
/// photo, the right pane always holds ROOM → ATMOSPHERE → Generate. Before a
/// photo exists the right pane is visible but genuinely inert (no pointer, no
/// focus), so the journey is legible without ever being clickable too early.
class _CreateWorkspace extends StatefulWidget {
  const _CreateWorkspace({
    super.key,
    required this.twoPane,
    required this.isMobile,
    required this.bytes,
    required this.atmospheres,
    required this.selectedRoomId,
    required this.selectedAtmosphereId,
    required this.onPick,
    required this.onExample,
    required this.onRemove,
    required this.onGenerate,
    required this.onSelectRoom,
    required this.onSelectAtmosphere,
  });
  final bool twoPane;
  final bool isMobile;

  /// null → the drop zone is shown; non-null → the photo takes its place.
  final Uint8List? bytes;
  final List<PwaAtmosphere> atmospheres;
  final String? selectedRoomId;
  final String selectedAtmosphereId;
  final VoidCallback onPick;

  /// Loads one of the bundled example rooms as the local source.
  final ValueChanged<String> onExample;
  final VoidCallback onRemove;
  final VoidCallback onGenerate;
  final ValueChanged<String?> onSelectRoom;
  final ValueChanged<String> onSelectAtmosphere;

  bool get hasPhoto => bytes != null;

  @override
  State<_CreateWorkspace> createState() => _CreateWorkspaceState();
}

class _CreateWorkspaceState extends State<_CreateWorkspace> {
  bool _roomExpanded = false;
  bool _atmosExpanded = false;
  // §7: one dedicated ScrollController per horizontal row (popular + optional,
  // for ROOM and ATMOSPHERE) — four total, never shared.
  final _roomPopScroll = ScrollController();
  final _roomOptScroll = ScrollController();
  final _atmosPopScroll = ScrollController();
  final _atmosOptScroll = ScrollController();

  @override
  void dispose() {
    _roomPopScroll.dispose();
    _roomOptScroll.dispose();
    _atmosPopScroll.dispose();
    _atmosOptScroll.dispose();
    super.dispose();
  }

  bool get _roomIsAuto => widget.selectedRoomId == null;
  String get _roomLabel =>
      pwaRoomById(widget.selectedRoomId)?.label ?? 'Ayden Decide';
  String get _atmosphereName {
    for (final a in widget.atmospheres) {
      if (a.id == widget.selectedAtmosphereId) return a.name;
    }
    return 'Ayden Signature';
  }

  /// Scroll a horizontal row the minimum amount so card [index] is FULLY
  /// visible — only when it is currently clipped at an edge. No-op otherwise.
  /// Card footprint for the current row width — see [pwaCardWidthFor]. Derived
  /// in build; every geometry helper below reads it instead of the constant.
  double _cardW = kPwaCardW;

  void _revealIndexIfClipped(ScrollController c, int index) {
    if (!c.hasClients) return;
    final pos = c.position;
    final start = index * (_cardW + kPwaCardGap);
    final end = start + _cardW;
    final vpStart = c.offset;
    final vpEnd = c.offset + pos.viewportDimension;
    double? target;
    if (start < vpStart) {
      target = start; // clipped at the left
    } else if (end > vpEnd) {
      target = end - pos.viewportDimension; // clipped at the right
    }
    if (target != null) {
      c.animateTo(
        target.clamp(0.0, pos.maxScrollExtent),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Widget _roomCard(
    String? id,
    String title,
    String asset,
    String subtitle,
    bool selected,
  ) => SizedBox(
    width: _cardW,
    child: PwaSelectCard(
      title: title,
      subtitle: subtitle,
      asset: asset,
      selected: selected,
      onTap: () => _selectRoom(id),
    ),
  );

  // ── ROOM ─────────────────────────────────────────────────────────────────
  // Popular row: Ayden Decide + popular rooms. When COLLAPSED with an optional
  // room selected, that card is PROMOTED to the END of the popular row so the
  // active selection stays visible. Optional row (second row): every optional
  // room — appears inline only when expanded.
  List<Widget> _roomPopularCards() {
    final sel = widget.selectedRoomId;
    final cards = <Widget>[
      _roomCard(
        null,
        context.pwaL10n.uplAiDecide,
        'assets/cards/rooms/ayden_decide.png',
        context.pwaL10n.autoDetect,
        sel == null,
      ),
    ];
    for (final r in pwaPopularRooms()) {
      cards.add(_roomCard(r.id, context.pwaL10n.roomCardLabel(r.id, r.label),
          r.asset, '', r.id == sel));
    }
    if (!_roomExpanded && sel != null && !kPwaPopularRoomIds.contains(sel)) {
      final r = pwaRoomById(sel)!;
      cards.add(_roomCard(r.id, context.pwaL10n.roomCardLabel(r.id, r.label),
          r.asset, '', true));
    }
    return cards;
  }

  List<Widget> _roomOptionalCards() {
    final sel = widget.selectedRoomId;
    return [
      for (final r in pwaOptionalRooms())
        _roomCard(r.id, context.pwaL10n.roomCardLabel(r.id, r.label),
            r.asset, '', r.id == sel),
    ];
  }

  int _roomPopularIndex(String? id) {
    if (id == null) return 0; // Ayden Decide
    final populars = pwaPopularRooms();
    final p = populars.indexWhere((r) => r.id == id);
    if (p >= 0) return p + 1;
    return populars.length + 1; // promoted optional at the row end
  }

  int _roomOptionalIndex(String id) {
    final p = pwaOptionalRooms().indexWhere((r) => r.id == id);
    return p < 0 ? 0 : p;
  }

  void _selectRoom(String? id) {
    widget.onSelectRoom(id);
    // §4/§9: keep the selection visible; scroll ONLY the row the card lives in,
    // and only when it is genuinely clipped. Never scroll the page vertically.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final isOptional = id != null && !kPwaPopularRoomIds.contains(id);
      if (isOptional && _roomExpanded) {
        _revealIndexIfClipped(_roomOptScroll, _roomOptionalIndex(id));
      } else {
        _revealIndexIfClipped(_roomPopScroll, _roomPopularIndex(id));
      }
    });
  }

  void _toggleRoom() {
    final expanding = !_roomExpanded;
    setState(() => _roomExpanded = expanding);
    // §9: expanding must NOT auto-scroll (popular row stays put). Collapsing
    // with an optional room selected promotes it to the popular row's end and
    // reveals it there.
    if (!expanding) {
      final sel = widget.selectedRoomId;
      if (sel != null && !kPwaPopularRoomIds.contains(sel)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _revealIndexIfClipped(_roomPopScroll, _roomPopularIndex(sel));
          }
        });
      }
    }
  }

  // ── ATMOSPHERE ───────────────────────────────────────────────────────────
  Widget _atmosCard(PwaAtmosphere a, String sel) => SizedBox(
    width: _cardW,
    child: PwaSelectCard(
      title: a.name,
      subtitle: a.id == 'ayden_signature' ? context.pwaL10n.selectedByAyden : '',
      asset: a.asset,
      selected: a.id == sel,
      onTap: () => _selectAtmosphere(a.id),
    ),
  );

  List<Widget> _atmosPopularCards() {
    final sel = widget.selectedAtmosphereId;
    final byId = {for (final a in widget.atmospheres) a.id: a};
    final cards = <Widget>[];
    for (final id in kPwaPopularAtmosphereIds) {
      final a = byId[id];
      if (a != null) cards.add(_atmosCard(a, sel));
    }
    if (!_atmosExpanded && !kPwaPopularAtmosphereIds.contains(sel)) {
      final a = byId[sel];
      if (a != null) cards.add(_atmosCard(a, sel)); // promoted optional
    }
    return cards;
  }

  List<Widget> _atmosOptionalCards() {
    final sel = widget.selectedAtmosphereId;
    return [
      for (final a in widget.atmospheres)
        if (!kPwaPopularAtmosphereIds.contains(a.id)) _atmosCard(a, sel),
    ];
  }

  int _atmosPopularIndex(String id) {
    final p = kPwaPopularAtmosphereIds.indexOf(id);
    return p >= 0 ? p : kPwaPopularAtmosphereIds.length;
  }

  int _atmosOptionalIndex(String id) {
    final opts = [
      for (final a in widget.atmospheres)
        if (!kPwaPopularAtmosphereIds.contains(a.id)) a.id,
    ];
    final p = opts.indexOf(id);
    return p < 0 ? 0 : p;
  }

  void _selectAtmosphere(String id) {
    widget.onSelectAtmosphere(id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final isOptional = !kPwaPopularAtmosphereIds.contains(id);
      if (isOptional && _atmosExpanded) {
        _revealIndexIfClipped(_atmosOptScroll, _atmosOptionalIndex(id));
      } else {
        _revealIndexIfClipped(_atmosPopScroll, _atmosPopularIndex(id));
      }
    });
  }

  void _toggleAtmos() {
    final expanding = !_atmosExpanded;
    setState(() => _atmosExpanded = expanding);
    if (!expanding) {
      final sel = widget.selectedAtmosphereId;
      if (!kPwaPopularAtmosphereIds.contains(sel)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _revealIndexIfClipped(_atmosPopScroll, _atmosPopularIndex(sel));
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      // Derive the card footprint from the row that will actually hold it, so
      // the five primary choices read at a glance instead of the last one being
      // clipped by a fixed 158px card.
      // Only the two-pane composition is constrained enough to need scaling:
      // the single-column flow keeps the full design footprint and simply
      // scrolls, so narrowing the cards there would cost readability for nothing.
      _cardW = widget.twoPane
          ? pwaCardWidthFor((c.maxWidth.clamp(0.0, 1440.0) - 96 - 44) * 0.55)
          : kPwaCardW;
      return _buildBody(context);
    },
  );

  Widget _buildBody(BuildContext context) {
    final roomLevel = _SelectionLevel(
      rowKey: 'room',
      heading: context.pwaL10n.stepRoom,
      collapsedLabel: context.pwaL10n.moreRooms,
      expandedLabel: context.pwaL10n.fewerRooms,
      optionalLabel: context.pwaL10n.moreRoomsCaps,
      expanded: _roomExpanded,
      onToggle: _toggleRoom,
      popularController: _roomPopScroll,
      optionalController: _roomOptScroll,
      cardWidth: _cardW,
      cardHeight: pwaCardHeightFor(_cardW),
      popularCards: _roomPopularCards(),
      optionalCards: _roomOptionalCards(),
      showArrows: widget.twoPane,
    );

    final atmosLevel = _SelectionLevel(
      rowKey: 'atmos',
      heading: context.pwaL10n.stepAtmosphere,
      collapsedLabel: context.pwaL10n.moreAtmospheres,
      expandedLabel: context.pwaL10n.fewerAtmospheres,
      optionalLabel: context.pwaL10n.moreAtmospheresCaps,
      expanded: _atmosExpanded,
      onToggle: _toggleAtmos,
      popularController: _atmosPopScroll,
      optionalController: _atmosOptScroll,
      cardWidth: _cardW,
      cardHeight: pwaCardHeightFor(_cardW),
      popularCards: _atmosPopularCards(),
      optionalCards: _atmosOptionalCards(),
      showArrows: widget.twoPane,
    );

    final enabled = widget.hasPhoto;
    final generate = _GenerateArea(
      onGenerate: enabled ? widget.onGenerate : null,
    );
    final intro = _CreateIntro(
      hasPhoto: enabled,
      roomLabel: _roomLabel,
      roomIsAuto: _roomIsAuto,
      atmosphereName: _atmosphereName,
      twoPane: widget.twoPane,
      isMobile: widget.isMobile,
    );
    final summary = _FastPathSummary(
      roomLabel: _roomLabel,
      roomIsAuto: _roomIsAuto,
      atmosphereName: _atmosphereName,
    );

    // Visible in BOTH states, but genuinely inert until a photo exists: no
    // pointer, no focus, no keyboard traversal — never a misleading affordance.
    final selectors = _InertWhen(
      inert: !enabled,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          roomLevel,
          SizedBox(height: widget.twoPane ? 26 : 20),
          atmosLevel,
          SizedBox(height: widget.twoPane ? 16 : 20),
          summary,
        ],
      ),
    );

    final sourcePane = widget.bytes == null
        ? _DropZone(onPick: widget.onPick)
        : _PhotoPanel(
            bytes: widget.bytes!,
            onReplace: widget.onPick,
            onRemove: widget.onRemove,
          );
    // The bundled example rooms live with the drop zone and leave with it.
    final examples = widget.bytes == null
        ? _ExamplesStrip(onPick: widget.onExample)
        : null;

    if (!widget.twoPane) {
      // Mobile / tablet — one natural vertical flow. No hero to scroll past:
      // the composition starts directly under the slim bar.
      return ColoredBox(
        color: pwaCharcoalSoft,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              intro,
              const SizedBox(height: 22),
              // The drop zone has a fixed slot; the photo sizes to its ratio.
              widget.bytes == null
                  ? SizedBox(height: 300, child: sourcePane)
                  : sourcePane,
              if (examples != null) ...[const SizedBox(height: 14), examples],
              const _PrivacyNote(),
              const SizedBox(height: 24),
              selectors,
              const SizedBox(height: 12),
              generate,
              _CreateFooter(isMobile: widget.isMobile),
            ],
          ),
        ),
      );
    }

    // Desktop — the approved two-column composition, sized to the viewport that
    // is left under the slim bar. Only the selectors scroll, so Generate and the
    // footer stay anchored and no short window can overflow.
    return ColoredBox(
      color: pwaCharcoalSoft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(48, 24, 48, 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 45,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // The drop zone fills the column; a photo takes the
                            // height its own ratio needs (see _PhotoPanel).
                            Expanded(
                              child: widget.bytes == null
                                  ? sourcePane
                                  : Align(
                                      alignment: Alignment.topCenter,
                                      child: sourcePane,
                                    ),
                            ),
                            if (examples != null) ...[
                              const SizedBox(height: 14),
                              examples,
                            ],
                            const _PrivacyNote(),
                          ],
                        ),
                      ),
                      const SizedBox(width: 44),
                      Expanded(
                        flex: 55,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            intro,
                            const SizedBox(height: 20),
                            Expanded(
                              child: SingleChildScrollView(child: selectors),
                            ),
                            const SizedBox(height: 12),
                            generate,
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _CreateFooter(isMobile: widget.isMobile),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Blocks pointer, focus and keyboard traversal, and dims what it wraps. Used
/// for the pre-upload ROOM / ATMOSPHERE panes: present and legible, never
/// interactive.
class _InertWhen extends StatelessWidget {
  const _InertWhen({required this.inert, required this.child});
  final bool inert;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (!inert) return child;
    // Dimmed enough to read as "not yet", light enough to stay legible — the
    // pre-upload state must explain the journey, not hide it.
    return ExcludeFocus(
      child: IgnorePointer(child: Opacity(opacity: 0.55, child: child)),
    );
  }
}

// ── Fast-Path editorial introduction (§4) ────────────────────────────────────

const Color _fpGold = Color(0xFFD3B064);
const Color _fpWhite = Color(0xFFFFFDFC);

class _CreateIntro extends StatelessWidget {
  const _CreateIntro({
    required this.hasPhoto,
    required this.roomLabel,
    required this.roomIsAuto,
    required this.atmosphereName,
    required this.twoPane,
    required this.isMobile,
  });

  /// Drives the one sentence that changes between the two states, and whether
  /// the readiness pills are meaningful at all.
  final bool hasPhoto;
  final String roomLabel;
  final bool roomIsAuto;
  final String atmosphereName;
  final bool twoPane;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final titleSize = twoPane ? 30.0 : (isMobile ? 25.0 : 27.0);
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.pwaL10n.createFirstVision,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: isMobile ? 10 : 11,
            fontWeight: FontWeight.w600,
            // Raw TextStyle rather than `pwaEyebrow`, so it needs the same
            // guard: 2.2 of tracking pulls Khmer clusters apart.
            letterSpacing: pwaTracking(2.2),
            color: _fpGold,
            height: 1.3,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.pwaL10n.shapeYourSpace,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.3,
            color: _fpWhite,
            height: 1.15,
            decoration: TextDecoration.none,
          ),
        ),
        SizedBox(height: isMobile ? 6 : 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            // One sentence, two states — the journey is explained before the
            // photo exists, then hands over to the choices once it does.
            hasPhoto
                ? context.pwaL10n.nowChooseRoomAndAtmosphere
                : context.pwaL10n.addPhotoToStart,
            maxLines: isMobile ? 2 : 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: isMobile ? 13.5 : 14,
              fontWeight: FontWeight.w400,
              color: _fpWhite.withValues(alpha: 0.62),
              height: 1.45,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ],
    );

    // The readiness pills are gone in every state: the selection cards already
    // show what is chosen, and the pills only restated it.
    return copy;
  }
}

/// §6 — one-line selection summary above Generate (Room/Atmosphere in gold).
class _FastPathSummary extends StatelessWidget {
  const _FastPathSummary({
    required this.roomLabel,
    required this.roomIsAuto,
    required this.atmosphereName,
  });
  final String roomLabel;
  final bool roomIsAuto;
  final String atmosphereName;
  @override
  Widget build(BuildContext context) {
    final room = roomIsAuto ? 'Ayden Decide' : roomLabel;
    const goldSpan = TextStyle(color: _fpGold, fontWeight: FontWeight.w600);
    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: _fpWhite.withValues(alpha: 0.55),
          decoration: TextDecoration.none,
        ),
        children: [
          TextSpan(text: context.pwaL10n.fastPathPrefix),
          TextSpan(text: room, style: goldSpan),
          const TextSpan(text: '  ·  '),
          TextSpan(text: atmosphereName, style: goldSpan),
        ],
      ),
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Height a photo card needs for a source of [aspect] (width / height) laid out
/// at [width], never exceeding [available].
///
/// Pure so the decision is testable without decoding an image: `contain` alone
/// kept whatever height the column offered, which is what put a landscape photo
/// between two large charcoal bands. A null [aspect] (not decoded yet) falls
/// back to the common landscape shape so the first frame is never wildly wrong.
double pwaPhotoImageHeight({
  required double width,
  required double? aspect,
  required double available,
}) {
  const minImage = 180.0;
  const maxImage = 620.0;
  final a = (aspect == null || !aspect.isFinite || aspect <= 0)
      ? 4 / 3
      : aspect;
  final cap = available.isFinite ? available : maxImage;
  return (width / a).clamp(minImage, cap.clamp(minImage, maxImage));
}

/// The chosen photo, occupying the drop zone's place — at the ratio the source
/// actually has.
///
/// `contain` alone was not enough: the card kept whatever height the column gave
/// it, so a landscape photo sat in a tall box between two large charcoal bands.
/// The card now measures the decoded image and asks for the height that ratio
/// needs, clamped so a very tall portrait can never push the page off screen.
/// Portraits are still shown whole on charcoal — never cropped, never on white.
class _PhotoPanel extends StatefulWidget {
  const _PhotoPanel({
    required this.bytes,
    required this.onReplace,
    required this.onRemove,
  });
  final Uint8List bytes;
  final VoidCallback onReplace;
  final VoidCallback onRemove;

  @override
  State<_PhotoPanel> createState() => _PhotoPanelState();
}

class _PhotoPanelState extends State<_PhotoPanel> {
  /// width / height of the decoded source. Null until the first frame decodes.
  double? _aspect;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  static const double _barHeight = 46;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _PhotoPanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.bytes, widget.bytes)) {
      _aspect = null;
      _resolve();
    }
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  void _resolve() {
    _detach();
    final stream = MemoryImage(
      widget.bytes,
    ).resolve(const ImageConfiguration());
    final listener = ImageStreamListener((info, _) {
      final a = info.image.width / info.image.height;
      if (mounted && a.isFinite && a > 0 && a != _aspect) {
        setState(() => _aspect = a);
      }
    }, onError: (_, _) {});
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.hasBoundedWidth ? c.maxWidth : 480.0;
        final imageH = pwaPhotoImageHeight(
          width: w,
          aspect: _aspect,
          available: c.hasBoundedHeight && c.maxHeight.isFinite
              ? c.maxHeight - _barHeight
              : double.infinity,
        );
        return SizedBox(
          height: imageH + _barHeight,
          child: ClipRRect(
            key: const ValueKey('pwaPhoto'),
            borderRadius: BorderRadius.circular(PwaGap.radiusLg),
            child: ColoredBox(
              color: pwaCharcoal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Center(
                      child: Image.memory(
                        widget.bytes,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const ColoredBox(color: pwaCharcoal),
                      ),
                    ),
                  ),
                  Container(
                    height: _barHeight,
                    color: pwaBlack.withValues(alpha: 0.62),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    // Both actions stay whole on a narrow card: they share the
                    // width and scale together rather than one being clipped.
                    child: Row(
                      children: [
                        Flexible(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: _MiniAction(
                                icon: Icons.sync,
                                label: context.pwaL10n.replacePhoto,
                                onTap: widget.onReplace,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: _MiniAction(
                                icon: Icons.delete_outline,
                                label: context.pwaL10n.removePhoto,
                                onTap: widget.onRemove,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: pwaOnDark.withValues(alpha: 0.7)),
            const SizedBox(width: 7),
            Text(
              label,
              style: pwaSans(
                fontSize: 13,
                color: pwaOnDark.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Horizontal selection level (ROOM / ATMOSPHERE) ────────────────────────────

/// One heading + "More/Fewer" toggle + a single horizontal, non-wrapping card
/// carousel. Room and Atmosphere each own an independent scroll controller.
/// One heading + "More/Fewer" toggle + a SINGLE horizontal, non-wrapping card
/// row. Expanding appends the optional cards to the SAME ListView — never a
/// Wrap, grid, second row, modal or new page. On desktop, subtle prev/next
/// arrows appear at the edges when the row overflows its width.
/// One selection level: heading + More/Fewer toggle + the POPULAR horizontal
/// row, and — when expanded — a discreet label + a SECOND horizontal row of the
/// optional cards, revealed inline below (AnimatedSize). Never a Wrap / grid /
/// second popular-row / modal. The popular row stays visible and unchanged when
/// expanded. Each row is a [_CarouselRow] with its OWN ScrollController.
class _SelectionLevel extends StatelessWidget {
  const _SelectionLevel({
    required this.rowKey,
    required this.heading,
    required this.collapsedLabel,
    required this.expandedLabel,
    required this.optionalLabel,
    required this.expanded,
    required this.onToggle,
    required this.popularController,
    required this.optionalController,
    required this.cardWidth,
    required this.cardHeight,
    required this.popularCards,
    required this.optionalCards,
    required this.showArrows,
  });

  /// Stable role prefix for the two rows ("room" / "atmos") — the carousels
  /// get keys ValueKey('$rowKey-popular') / ValueKey('$rowKey-optional').
  final String rowKey;
  final String heading;
  final String collapsedLabel;
  final String expandedLabel;
  final String optionalLabel;
  final bool expanded;
  final VoidCallback onToggle;
  final ScrollController popularController;
  final ScrollController optionalController;
  final double cardWidth;
  final double cardHeight;
  final List<Widget> popularCards;
  final List<Widget> optionalCards;

  /// Desktop only — touch surfaces scroll by drag and need no arrows.
  final bool showArrows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                heading,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: pwaEyebrow(color: pwaGold, fontSize: 13),
              ),
            ),
            // No More/Fewer toggle when there is nothing more to reveal (a level
            // whose whole catalog already fits in the popular row).
            if (optionalCards.isNotEmpty) ...[
              const SizedBox(width: 8),
              _MoreButton(
                label: expanded ? expandedLabel : collapsedLabel,
                expanded: expanded,
                onTap: onToggle,
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        // POPULAR row — always visible, exactly one horizontal carousel.
        _CarouselRow(
          key: ValueKey('$rowKey-popular'),
          controller: popularController,
          cardWidth: cardWidth,
          cardHeight: cardHeight,
          cards: popularCards,
          showArrows: showArrows,
        ),
        // Optional cards live in a SECOND horizontal row that reveals inline
        // below (never appended to the popular row, never a grid). Smooth height
        // reveal; collapsed / no-optionals → zero height.
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topLeft,
          child: (expanded && optionalCards.isNotEmpty)
              ? Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Discreet label — NOT a repeat of the large "1. ROOM".
                      Text(
                        optionalLabel,
                        style: pwaEyebrow(
                          color: pwaGoldSoft.withValues(alpha: 0.7),
                          fontSize: 10.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _CarouselRow(
                        key: ValueKey('$rowKey-optional'),
                        controller: optionalController,
                        cardWidth: cardWidth,
                        cardHeight: cardHeight,
                        cards: optionalCards,
                        showArrows: showArrows,
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// A single horizontal, non-wrapping carousel with its OWN ScrollController,
/// web-safe physics (primary:false + Clamping), desktop edge arrows that move
/// in WHOLE-CARD increments, and edge fades. A horizontal gesture is consumed
/// here and never bubbles to the vertical page or the browser history.
class _CarouselRow extends StatefulWidget {
  const _CarouselRow({
    super.key,
    required this.controller,
    required this.cardWidth,
    required this.cardHeight,
    required this.cards,
    required this.showArrows,
  });
  final ScrollController controller;
  final double cardWidth;
  final double cardHeight;
  final List<Widget> cards;
  final bool showArrows;

  @override
  State<_CarouselRow> createState() => _CarouselRowState();
}

class _CarouselRowState extends State<_CarouselRow> {
  double get _extent => widget.cardWidth + kPwaCardGap;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(covariant _CarouselRow old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
    }
    // Card set may have changed → re-evaluate arrow/fade state once laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (mounted) setState(() {});
  }

  bool get _canLeft =>
      widget.controller.hasClients && widget.controller.offset > 4;

  bool get _canRight =>
      widget.controller.hasClients &&
      widget.controller.offset < widget.controller.position.maxScrollExtent - 4;

  // Arrow navigation moves in WHOLE-CARD increments and lands on a card
  // boundary (§9) — no card is ever left half-cut by an arrow click.
  void _page(int dir) {
    final c = widget.controller;
    if (!c.hasClients) return;
    final perClick = ((c.position.viewportDimension * 0.8) / _extent)
        .floor()
        .clamp(1, 99);
    final currentCard = (c.offset / _extent).round();
    final target = ((currentCard + perClick * dir) * _extent).clamp(
      0.0,
      c.position.maxScrollExtent,
    );
    c.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.cardHeight,
      child: Stack(
        children: [
          ScrollConfiguration(
            // Click-drag + trackpad horizontal scroll on desktop web.
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
              controller: widget.controller,
              // Never the primary scrollable → the horizontal gesture is
              // consumed here and does not drive the vertical page.
              primary: false,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.only(right: 8),
              itemCount: widget.cards.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => widget.cards[i],
            ),
          ),
          // Subtle edge fades — a cue that more cards exist off-screen.
          if (_canLeft) const _EdgeFade(left: true),
          if (_canRight) const _EdgeFade(left: false),
          if (widget.showArrows && _canLeft)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: _RowArrow(
                  icon: Icons.chevron_left_rounded,
                  onTap: () => _page(-1),
                ),
              ),
            ),
          if (widget.showArrows && _canRight)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: _RowArrow(
                  icon: Icons.chevron_right_rounded,
                  onTap: () => _page(1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Subtle desktop scroll affordance shown at a row edge on overflow.
/// Subtle gradient fade at a row edge — signals more cards off-screen. The
/// panel colour (charcoal) fades to transparent over the outermost ~28px.
class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.left});
  final bool left;
  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left ? 0 : null,
      right: left ? null : 0,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: SizedBox(
          width: 28,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: left ? Alignment.centerLeft : Alignment.centerRight,
                end: left ? Alignment.centerRight : Alignment.centerLeft,
                colors: [pwaCharcoalSoft, pwaCharcoalSoft.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RowArrow extends StatelessWidget {
  const _RowArrow({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: pwaBlack.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 22, color: pwaGoldSoft),
          ),
        ),
      ),
    );
  }
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({
    required this.label,
    required this.expanded,
    required this.onTap,
  });
  final String label;
  final bool expanded;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: pwaGold.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: pwaSans(
                    fontSize: 12.5,
                    color: pwaGoldSoft,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: pwaGoldSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Generate ─────────────────────────────────────────────────────────────────

/// The single primary CTA. A null [onGenerate] renders it visibly present but
/// genuinely disabled — the pre-upload state shows where the journey ends
/// without ever pretending to be clickable.
class _GenerateArea extends StatelessWidget {
  const _GenerateArea({required this.onGenerate});
  final VoidCallback? onGenerate;
  @override
  Widget build(BuildContext context) {
    final enabled = onGenerate != null;
    final fg = enabled ? pwaBlack : pwaOnDark.withValues(alpha: 0.38);
    return Semantics(
      button: true,
      enabled: enabled,
      label: context.pwaL10n.generateMyVision,
      child: Material(
        color: enabled ? pwaGold : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          key: const ValueKey('pwa-generate'),
          borderRadius: BorderRadius.circular(999),
          onTap: onGenerate,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: enabled
                  ? null
                  : Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    context.pwaL10n.generateMyVision,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: pwaSans(
                      fontSize: 15.5,
                      color: fg,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.auto_awesome, size: 18, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
