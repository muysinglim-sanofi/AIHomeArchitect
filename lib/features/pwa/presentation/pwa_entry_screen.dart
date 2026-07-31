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

import 'package:flutter/foundation.dart' show kIsWeb;
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
import 'hero/pwa_hero_sequence.dart';
import 'hero/pwa_hero_video.dart';
import 'pwa_brand.dart';
import 'pwa_select_card.dart';
import 'pwa_theme.dart';

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
String pwaAtmosphereSubtitle(String id) =>
    kAtmosphereCardById[id]?.subtitle ??
    (id == 'ayden_signature' ? 'Selected by Ayden' : '');

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

class _PwaEntryScreenState extends ConsumerState<PwaEntryScreen>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  final _picker = ImagePicker();
  final _focus = FocusNode();
  final _uploadKey = GlobalKey();
  PwaHeroSequence? _seq;
  PwaHeroMedia _heroMedia = kHeroMediaDesktop;
  bool _seqStarted = false;

  @override
  void initState() {
    super.initState();
    pwaHardenDebugPaints(); // no debug baseline/size overlays
    // Reused app cards (RoomCard/AtmosphereHeroCard → AppTheme uses google_fonts):
    // keep the PWA fully offline — no runtime font fetch, ever.
    pwaDisableRemoteFonts();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seqStarted) return;
    _seqStarted = true;
    final mq = MediaQuery.of(context);
    final reduce = mq.disableAnimations;
    // The cinematic plays on EVERY viewport (desktop / tablet / mobile) — it no
    // longer skips to the static poster just because the viewport is narrow.
    // Media (paths + crop) is chosen once for this page instance by form factor.
    final isMobile = mq.size.width < 700;
    final media = pwaHeroMediaFor(isMobile);
    _heroMedia = media;
    final useVideo = pwaHeroUseVideo(isWeb: kIsWeb, reduceMotion: reduce);
    precacheImage(
      const AssetImage(kAydenLogoHero),
      context,
      onError: (_, _) {},
    );
    if (useVideo) {
      precacheImage(
        NetworkImage(media.startPoster),
        context,
        onError: (_, _) {},
      );
    }
    precacheImage(NetworkImage(media.endPoster), context, onError: (_, _) {});
    _seq = PwaHeroSequence(
      useVideo: useVideo,
      createVideo: ({required onReady, required onEnded, required onError}) =>
          createPwaHeroVideo(
            mp4: media.mp4,
            webm: media.webm,
            poster: media.startPoster,
            objectPosition: media.videoObjectPosition,
            onReady: onReady,
            onEnded: onEnded,
            onError: onError,
          ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _seq?.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _seq?.onVisible();
    } else {
      _seq?.onHidden(); // hidden / paused / inactive → pause the video
    }
  }

  void _skipCinematic() => _seq?.skip();

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyDownEvent &&
        (e.logicalKey == LogicalKeyboardKey.enter ||
            e.logicalKey == LogicalKeyboardKey.space ||
            e.logicalKey == LogicalKeyboardKey.escape)) {
      _skipCinematic();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _scrollToUpload() async {
    _skipCinematic();
    final ctx = _uploadKey.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 750),
      curve: Curves.easeInOutCubic,
      alignment: 0,
    );
  }

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
  }

  Future<void> _useExample() async {
    final img = await ImagePipeline.fromAsset(
      'assets/examples/living_room.jpg',
    );
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
        onKeyEvent: _onKey,
        child: LayoutBuilder(
          builder: (context, c) {
            final ff = pwaFormFactorForWidth(c.maxWidth);
            final isMobile = ff == PwaFormFactor.mobile;
            final twoPane = ff == PwaFormFactor.desktop;
            final vh = c.maxHeight;
            final collapsed = pwaCollapsedHeaderExtent(isMobile);

            return CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _RoomHeaderDelegate(
                    max: vh,
                    min: collapsed,
                    seq: _seq!,
                    media: _heroMedia,
                    userBytes: bytes,
                    isMobile: isMobile,
                    onUpload: _scrollToUpload,
                    onSkip: _skipCinematic,
                    hasSource: bytes != null,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _WorkspaceSection(
                    key: _uploadKey,
                    twoPane: twoPane,
                    isMobile: isMobile,
                    viewportHeight: vh,
                    collapsedHeader: collapsed,
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
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Pinned hero → slim brand bar ──────────────────────────────────────────────

class _RoomHeaderDelegate extends SliverPersistentHeaderDelegate {
  _RoomHeaderDelegate({
    required this.max,
    required this.min,
    required this.seq,
    required this.media,
    required this.userBytes,
    required this.isMobile,
    required this.onUpload,
    required this.onSkip,
    required this.hasSource,
  });

  final double max, min;
  final PwaHeroSequence seq;
  final PwaHeroMedia media;
  final Uint8List? userBytes;
  final bool isMobile;
  final VoidCallback onUpload;
  final VoidCallback onSkip;
  final bool hasSource;

  @override
  double get maxExtent => max;
  @override
  double get minExtent => min;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final collapse = entryCollapse(shrinkOffset, max - min);
    final heroOpacity =
        1.0 - Curves.easeInCubic.transform((collapse / 0.68).clamp(0.0, 1.0));
    final compactOpacity = Curves.easeOutCubic.transform(
      ((collapse - 0.72) / 0.28).clamp(0.0, 1.0),
    );

    return ClipRect(
      child: ColoredBox(
        color: pwaBlack,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (heroOpacity > 0.01)
              Opacity(
                opacity: heroOpacity,
                child: IgnorePointer(
                  ignoring: heroOpacity < 0.5,
                  child: AnimatedBuilder(
                    animation: seq,
                    builder: (context, _) => _videoCinematic(
                      context,
                      seq,
                      media,
                      isMobile,
                      userBytes,
                      onUpload,
                      onSkip,
                    ),
                  ),
                ),
              ),
            if (compactOpacity > 0.01)
              IgnorePointer(
                ignoring: compactOpacity < 0.5,
                child: Opacity(
                  opacity: compactOpacity,
                  child: _CompactBar(hasSource: hasSource, isMobile: isMobile),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _RoomHeaderDelegate old) =>
      old.max != max ||
      old.min != min ||
      old.userBytes != userBytes ||
      old.isMobile != isMobile ||
      old.hasSource != hasSource ||
      old.media != media ||
      old.seq != seq;
}

/// Cinematic hero — ONE full-bleed frame shared by poster / video / final
/// poster (all BoxFit.cover, no layout shift). Zero-wait: the empty-room poster
/// paints from frame 0, the logo fades in over it, and the native video
/// cross-fades in on a real "playing" event. NO Flutter gold line over the
/// video (the source already carries the transformation). Final state = the
/// full designed room with the copy composed bottom-left.
Widget _videoCinematic(
  BuildContext context,
  PwaHeroSequence seq,
  PwaHeroMedia media,
  bool isMobile,
  Uint8List? userBytes,
  VoidCallback onUpload,
  VoidCallback onSkip,
) {
  final logoW = isMobile ? 210.0 : 300.0;
  final phase = seq.phase;
  final videoSupported = seq.video?.isSupported ?? false;
  final showVideo = phase == PwaHeroPhase.transform && videoSupported;
  final posterUrl = phase == PwaHeroPhase.promise
      ? media.endPoster
      : media.startPoster;

  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onSkip,
    child: Stack(
      fit: StackFit.expand,
      children: [
        // 1) Full-bleed poster (user photo once uploaded, else room poster).
        Positioned.fill(
          child: userBytes != null
              ? Image.memory(
                  userBytes,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: pwaCharcoal),
                )
              : _HeroPoster(posterUrl, alignment: media.posterAlignment),
        ),
        // 2) Full-bleed native video, cross-faded in on a real playing frame.
        if (userBytes == null && videoSupported)
          Positioned.fill(
            child: AnimatedOpacity(
              opacity: showVideo ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 180),
              child: seq.video!.buildView(),
            ),
          ),
        // 3) Readability gradient (bottom-weighted for the copy).
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.16),
                    Colors.black.withValues(alpha: 0.0),
                    Colors.black.withValues(alpha: 0.62),
                  ],
                  stops: const [0.0, 0.42, 1.0],
                ),
              ),
            ),
          ),
        ),
        // 4) Logo fades in OVER the room during intro; fades out as it plays.
        if (userBytes == null)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: phase == PwaHeroPhase.intro ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 350),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PwaHeroLogo(reveal: 1.0, size: logoW),
                      SizedBox(height: isMobile ? 12 : 18),
                      Text(
                        'Your Personal AI Architect',
                        style: pwaSans(
                          fontSize: isMobile ? 12.5 : 13.5,
                          color: pwaOnDark.withValues(alpha: 0.85),
                          letterSpacing: 1.6,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        // 5) Final composition — copy + CTA composed bottom-left over the room.
        if (phase == PwaHeroPhase.promise)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _HeroPromise(isMobile: isMobile, onUpload: onUpload),
          ),
        // 6) Persistent Ayden Studio brand logo, top-left (present on every
        // hero phase, including the final promise state).
        if (userBytes == null)
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(isMobile ? 20 : 40, 20, 0, 0),
                child: Image.asset(
                  kAydenLogoHero,
                  height: isMobile ? 30 : 42,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        // 7) Skip affordance during the cinematic only.
        if (userBytes == null && phase != PwaHeroPhase.promise)
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Tap to skip',
                  style: pwaSans(
                    fontSize: 11.5,
                    color: pwaOnDark.withValues(alpha: 0.5),
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Same-origin runtime poster (webp under /media/hero, served at /media/hero).
/// Never a Flutter asset → stays out of the app-shell bundle. Full-bleed cover.
class _HeroPoster extends StatelessWidget {
  const _HeroPoster(this.url, {this.alignment = Alignment.center});
  final String url;
  final Alignment alignment;
  @override
  Widget build(BuildContext context) => Image.network(
    url,
    fit: BoxFit.cover,
    alignment: alignment,
    gaplessPlayback: true,
    errorBuilder: (_, _, _) => const ColoredBox(color: pwaCharcoal),
  );
}

class _CompactBar extends StatelessWidget {
  const _CompactBar({required this.hasSource, required this.isMobile});
  final bool hasSource;
  final bool isMobile;
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        height: pwaCollapsedHeaderExtent(isMobile),
        decoration: const BoxDecoration(
          color: pwaBlack,
          border: Border(
            bottom: BorderSide(color: Color(0x22FFFFFF), width: 1),
          ),
        ),
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 18 : 36),
        child: Row(
          children: [
            const PwaLogoBadge(size: 34),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                hasSource ? 'Your space' : 'Ayden Studio',
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
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: pwaOnDark.withValues(alpha: 0.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroPromise extends StatelessWidget {
  const _HeroPromise({required this.isMobile, required this.onUpload});
  final bool isMobile;
  final VoidCallback onUpload;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        isMobile ? 24 : 64,
        0,
        isMobile ? 24 : 64,
        isMobile ? 34 : 52,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your home.',
            style: pwaDisplay(
              fontSize: isMobile ? 40 : 58,
              color: pwaOnDark,
              height: 1.02,
            ),
          ),
          Text(
            'Reimagined.',
            style: pwaDisplay(
              fontSize: isMobile ? 40 : 58,
              color: pwaGold,
              fontWeight: FontWeight.w400,
              height: 1.02,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'One photo. Infinite possibilities.',
            style: pwaSans(
              fontSize: 15.5,
              color: pwaOnDark.withValues(alpha: 0.82),
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 24),
          _HeroCta(onTap: onUpload),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: pwaOnDark.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'First vision free · No account required',
                  style: pwaSans(
                    fontSize: 12.5,
                    color: pwaOnDark.withValues(alpha: 0.6),
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

class _HeroCta extends StatelessWidget {
  const _HeroCta({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: pwaGold.withValues(alpha: 0.85),
              width: 1.3,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  'Upload your room',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: pwaSans(
                    fontSize: 14.5,
                    color: pwaGoldSoft,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.arrow_forward, size: 16, color: pwaGoldSoft),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared chrome ─────────────────────────────────────────────────────────────

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.label);
  final String label;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 24, height: 1.4, color: pwaGold),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: pwaEyebrow(color: pwaGold),
          ),
        ),
      ],
    );
  }
}

/// Premium photo frame — warm neutral canvas, BoxFit.contain, never a black
/// letterbox.
/// Fills the box it is given (its parent picks the 16:10 size). Warm neutral
/// canvas, BoxFit.contain — never a black letterbox.
class _PhotoFrame extends StatelessWidget {
  const _PhotoFrame({super.key, required this.bytes});
  final Uint8List? bytes;
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(PwaGap.radius),
      child: ColoredBox(
        color: pwaCharcoalSoft,
        child: bytes == null
            ? const SizedBox.expand()
            : Center(
                child: Image.memory(
                  bytes!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: pwaCharcoalSoft),
                ),
              ),
      ),
    );
  }
}

// ── Workspace: upload showroom  OR  fast path ─────────────────────────────────

class _WorkspaceSection extends StatelessWidget {
  const _WorkspaceSection({
    super.key,
    required this.twoPane,
    required this.isMobile,
    required this.viewportHeight,
    required this.collapsedHeader,
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
  final double viewportHeight;
  final double collapsedHeader;
  final Uint8List? bytes;
  final List<PwaAtmosphere> atmospheres;
  final String? selectedRoomId;
  final String selectedAtmosphereId;
  final VoidCallback onPick;
  final VoidCallback onExample;
  final VoidCallback onRemove;
  final VoidCallback onGenerate;
  final ValueChanged<String?> onSelectRoom;
  final ValueChanged<String> onSelectAtmosphere;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: pwaCharcoalSoft,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOut,
        child: bytes == null
            ? KeyedSubtree(
                key: const ValueKey('upload'),
                child: _UploadShowroom(
                  twoPane: twoPane,
                  viewportHeight: viewportHeight,
                  collapsedHeader: collapsedHeader,
                  onPick: onPick,
                  onExample: onExample,
                ),
              )
            : _FastPath(
                key: const ValueKey('fast'),
                twoPane: twoPane,
                isMobile: isMobile,
                viewportHeight: viewportHeight,
                collapsedHeader: collapsedHeader,
                bytes: bytes!,
                atmospheres: atmospheres,
                selectedRoomId: selectedRoomId,
                selectedAtmosphereId: selectedAtmosphereId,
                onGenerate: onGenerate,
                onSelectRoom: onSelectRoom,
                onSelectAtmosphere: onSelectAtmosphere,
                onReplace: onPick,
                onRemove: onRemove,
              ),
      ),
    );
  }
}

/// SCREEN 1 — premium architectural upload showroom (faithful to
/// REF-PWA-UPLOAD-FASTPATH-V3, Screen 1): header (official logo left + trust
/// right), left editorial column (~38%), right premium upload zone (~62%).
class _UploadShowroom extends StatelessWidget {
  const _UploadShowroom({
    required this.twoPane,
    required this.viewportHeight,
    required this.collapsedHeader,
    required this.onPick,
    required this.onExample,
  });
  final bool twoPane;
  final double viewportHeight;
  final double collapsedHeader;
  final VoidCallback onPick;
  final VoidCallback onExample;

  Widget _header() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Official Ayden Studio lockup (transparent → composites cleanly on the
      // dark panel). Not redrawn / retyped / faked.
      Image.asset(
        kAydenLogoHero,
        height: twoPane ? 54 : 42,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
      const Spacer(),
      const _TrustBadge(),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final copy = _UploadCopy(twoPane: twoPane, onExample: onExample);
    final canvas = _DropZone(onPick: onPick);

    if (!twoPane) {
      // Mobile — header, editorial, then a tall premium upload canvas.
      return Padding(
        padding: EdgeInsets.fromLTRB(24, collapsedHeader + 24, 24, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            const SizedBox(height: 28),
            copy,
            const SizedBox(height: 26),
            SizedBox(height: 320, child: canvas),
          ],
        ),
      );
    }

    // Desktop — full-viewport composition: header pinned top, editorial (left)
    // centred against a dominant upload surface (right).
    return SizedBox(
      width: double.infinity,
      height: viewportHeight,
      child: Padding(
        padding: EdgeInsets.fromLTRB(64, collapsedHeader + 28, 64, 44),
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth > 1360 ? 1360.0 : c.maxWidth;
            return Center(
              child: SizedBox(
                width: w,
                height: c.maxHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 38, child: Center(child: copy)),
                          const SizedBox(width: 56),
                          Expanded(flex: 62, child: canvas),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Left editorial column of SCREEN 1 (concise, no invented marketing).
class _UploadCopy extends StatelessWidget {
  const _UploadCopy({required this.twoPane, required this.onExample});
  final bool twoPane;
  final VoidCallback onExample;
  @override
  Widget build(BuildContext context) {
    final hs = twoPane ? 50.0 : 34.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Eyebrow('YOUR SPACE'),
        SizedBox(height: twoPane ? 24 : 18),
        // "Show Ayden / your room." — the second line gold (upright serif, as
        // in the reference — no slant).
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Show Ayden\n',
                style: pwaDisplay(fontSize: hs, color: pwaOnDark, height: 1.03),
              ),
              TextSpan(
                text: 'your room.',
                style: pwaDisplay(fontSize: hs, color: pwaGold, height: 1.03),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'One clear photo is enough.',
          style: pwaSans(
            fontSize: 16.5,
            color: pwaOnDark,
            fontWeight: FontWeight.w500,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Ayden will understand your space and\n'
          'prepare your first design direction.',
          style: pwaSans(
            fontSize: 14.5,
            color: pwaOnDark.withValues(alpha: 0.62),
            height: 1.55,
          ),
        ),
        SizedBox(height: twoPane ? 30 : 22),
        _TryExampleCard(onTap: onExample),
      ],
    );
  }
}

/// Compact trust badge (top-right of SCREEN 1) — a single, non-duplicated place.
class _TrustBadge extends StatelessWidget {
  const _TrustBadge();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.verified_user_outlined,
          size: 18,
          color: pwaGold.withValues(alpha: 0.9),
        ),
        const SizedBox(width: 10),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'First vision free',
              style: pwaSans(
                fontSize: 13,
                color: pwaOnDark,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'No account required',
              style: pwaSans(
                fontSize: 12,
                color: pwaOnDark.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Premium secondary action card — "Try an example / See how it works".
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
                      'Try an example',
                      style: pwaSans(
                        fontSize: 14.5,
                        color: pwaOnDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'See how it works',
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
            child: Stack(
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
                      const SizedBox(height: 20),
                      Text(
                        'Drop your photo here',
                        style: pwaSans(
                          fontSize: 18,
                          color: pwaOnDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'or browse from your device',
                        style: pwaSans(
                          fontSize: 14,
                          color: pwaOnDark.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'JPG, PNG or HEIC',
                        style: pwaSans(
                          fontSize: 12,
                          color: pwaOnDark.withValues(alpha: 0.45),
                          letterSpacing: 0.8,
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

// ── FAST PATH — photo + ROOM + ATMOSPHERE + Generate, one viewport ───────────

class _FastPath extends StatefulWidget {
  const _FastPath({
    super.key,
    required this.twoPane,
    required this.isMobile,
    required this.viewportHeight,
    required this.collapsedHeader,
    required this.bytes,
    required this.atmospheres,
    required this.selectedRoomId,
    required this.selectedAtmosphereId,
    required this.onGenerate,
    required this.onSelectRoom,
    required this.onSelectAtmosphere,
    required this.onReplace,
    required this.onRemove,
  });
  final bool twoPane;
  final bool isMobile;
  final double viewportHeight;
  final double collapsedHeader;
  final Uint8List bytes;
  final List<PwaAtmosphere> atmospheres;
  final String? selectedRoomId;
  final String selectedAtmosphereId;
  final VoidCallback onGenerate;
  final ValueChanged<String?> onSelectRoom;
  final ValueChanged<String> onSelectAtmosphere;
  final VoidCallback onReplace;
  final VoidCallback onRemove;

  @override
  State<_FastPath> createState() => _FastPathState();
}

class _FastPathState extends State<_FastPath> {
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

  /// Scroll a horizontal row the minimum amount so card [index] is FULLY
  /// visible — only when it is currently clipped at an edge. No-op otherwise.
  void _revealIndexIfClipped(ScrollController c, int index) {
    if (!c.hasClients) return;
    const gap = 12.0;
    final pos = c.position;
    final start = index * (kPwaCardW + gap);
    final end = start + kPwaCardW;
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
    width: kPwaCardW,
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
        'Ayden Decide',
        'assets/cards/rooms/ayden_decide.png',
        'Auto-detect',
        sel == null,
      ),
    ];
    for (final r in pwaPopularRooms()) {
      cards.add(_roomCard(r.id, r.label, r.asset, '', r.id == sel));
    }
    if (!_roomExpanded && sel != null && !kPwaPopularRoomIds.contains(sel)) {
      final r = pwaRoomById(sel)!;
      cards.add(_roomCard(r.id, r.label, r.asset, '', true));
    }
    return cards;
  }

  List<Widget> _roomOptionalCards() {
    final sel = widget.selectedRoomId;
    return [
      for (final r in pwaOptionalRooms())
        _roomCard(r.id, r.label, r.asset, '', r.id == sel),
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
    width: kPwaCardW,
    child: PwaSelectCard(
      title: a.name,
      subtitle: a.id == 'ayden_signature' ? 'Selected by Ayden' : '',
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
  Widget build(BuildContext context) {
    final roomLevel = _SelectionLevel(
      rowKey: 'room',
      heading: '1. ROOM',
      collapsedLabel: 'More rooms',
      expandedLabel: 'Fewer rooms',
      optionalLabel: 'MORE ROOMS',
      expanded: _roomExpanded,
      onToggle: _toggleRoom,
      popularController: _roomPopScroll,
      optionalController: _roomOptScroll,
      cardHeight: kPwaCardH,
      popularCards: _roomPopularCards(),
      optionalCards: _roomOptionalCards(),
      showArrows: widget.twoPane,
    );

    final atmosLevel = _SelectionLevel(
      rowKey: 'atmos',
      heading: '2. ATMOSPHERE',
      collapsedLabel: 'More atmospheres',
      expandedLabel: 'Fewer atmospheres',
      optionalLabel: 'MORE ATMOSPHERES',
      expanded: _atmosExpanded,
      onToggle: _toggleAtmos,
      popularController: _atmosPopScroll,
      optionalController: _atmosOptScroll,
      cardHeight: kPwaCardH,
      popularCards: _atmosPopularCards(),
      optionalCards: _atmosOptionalCards(),
      showArrows: widget.twoPane,
    );

    final generate = _GenerateArea(onGenerate: widget.onGenerate);

    if (!widget.twoPane) {
      return SizedBox(
        width: double.infinity,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, widget.collapsedHeader + 24, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PhotoPanel(
                bytes: widget.bytes,
                onReplace: widget.onReplace,
                onRemove: widget.onRemove,
              ),
              const SizedBox(height: 24),
              roomLevel,
              const SizedBox(height: 20),
              atmosLevel,
              const SizedBox(height: 24),
              generate,
            ],
          ),
        ),
      );
    }

    // Desktop — the workspace fits ENTIRELY below the pinned collapsed hero bar
    // (which always occupies collapsedHeader at the top), so Generate stays
    // visible without vertical scroll. The photo is the dominant hero on the
    // left; the two aligned rows + anchored Generate on the right.
    final botPad = widget.collapsedHeader + 40;
    final boxH =
        (widget.viewportHeight - (widget.collapsedHeader + 32) - botPad).clamp(
          280.0,
          widget.viewportHeight,
        );
    return SizedBox(
      width: double.infinity,
      height: widget.viewportHeight,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          64,
          widget.collapsedHeader + 32,
          64,
          botPad,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1500),
            child: SizedBox(
              height: boxH,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 40,
                    child: _PhotoPanel(
                      bytes: widget.bytes,
                      onReplace: widget.onReplace,
                      onRemove: widget.onRemove,
                      fillHeight: true,
                    ),
                  ),
                  const SizedBox(width: 44),
                  Expanded(
                    flex: 60,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                roomLevel,
                                const SizedBox(height: 26),
                                atmosLevel,
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        generate,
                      ],
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

class _PhotoPanel extends StatelessWidget {
  const _PhotoPanel({
    required this.bytes,
    required this.onReplace,
    required this.onRemove,
    this.fillHeight = false,
  });
  final Uint8List bytes;
  final VoidCallback onReplace;
  final VoidCallback onRemove;

  /// Desktop — the photo is the hero of this screen and fills the column height.
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    final actions = Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 18,
        runSpacing: 6,
        children: [
          _MiniAction(
            icon: Icons.sync,
            label: 'Replace photo',
            onTap: onReplace,
          ),
          _MiniAction(
            icon: Icons.delete_outline,
            label: 'Remove photo',
            onTap: onRemove,
          ),
        ],
      ),
    );

    if (fillHeight) {
      // The frame fills all remaining vertical space (contain → the whole photo
      // stays visible, aspect preserved); the actions sit compactly beneath.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _PhotoFrame(key: const ValueKey('pwaPhoto'), bytes: bytes),
          ),
          actions,
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.hasBoundedWidth ? c.maxWidth : 480.0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: w,
              height: w * 3 / 4, // 4:3 — large, dominant on mobile
              child: _PhotoFrame(key: const ValueKey('pwaPhoto'), bytes: bytes),
            ),
            actions,
          ],
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
    required this.cardHeight,
    required this.cards,
    required this.showArrows,
  });
  final ScrollController controller;
  final double cardHeight;
  final List<Widget> cards;
  final bool showArrows;

  @override
  State<_CarouselRow> createState() => _CarouselRowState();
}

class _CarouselRowState extends State<_CarouselRow> {
  static const double _extent = kPwaCardW + 12; // card width + gap

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

class _GenerateArea extends StatelessWidget {
  const _GenerateArea({required this.onGenerate});
  final VoidCallback onGenerate;
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: pwaGold,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onGenerate,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      'Generate my vision',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: pwaSans(
                        fontSize: 15.5,
                        color: pwaBlack,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.auto_awesome, size: 18, color: pwaBlack),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'First vision free · No account required',
          textAlign: TextAlign.center,
          style: pwaSans(
            fontSize: 12.5,
            color: pwaOnDark.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}
