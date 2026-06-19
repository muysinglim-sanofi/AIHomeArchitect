import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart' show Share;
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/free_tier.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/providers/premium_provider.dart';
import '../../core/providers/access_provider.dart';
import '../../core/providers/me_status_provider.dart';
import '../../core/providers/session_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../data/mock/mock_projects.dart';
import '../../data/models/message_model.dart';
import '../../shared/widgets/app_pill.dart';
import '../../shared/widgets/atmosphere_card.dart';
import '../../shared/widgets/pinch_zoom.dart';
import '../../shared/widgets/reveal_hero.dart';
import '../../core/feature_flags.dart';
import '../../shared/reveal/reveal_controller.dart';
import '../../shared/reveal/reveal_fullscreen.dart';
import '../../shared/reveal/reveal_profile.dart';
import '../../shared/reveal/reveal_widget.dart';
import '../cards/card_catalog.dart';
import '../cards/widgets/atmosphere_hero_card.dart';
import '../paywall/paywall_sheet.dart';

// ── Wave 5.15 → 5.15d — Cinematic Full Reveal Screen Rebuild ─────────────────
// Layout-only evolution of the 5.13d reveal. Goal: make the reveal surface
// feel like the emotional climax of the product (Apple-reveal / Airbnb-Luxe
// vocabulary) instead of a grid-style result page.
//
// History (each wave addressed a device-test regression of the previous one):
//   • 5.15  — first cinematic rebuild ; 0.62 × screenH + cover. Too much
//             horizontal crop (~56 % on 3:2), windows amputated.
//   • 5.15b — fit cover → contain to preserve architecture. Container
//             stayed at 0.62 → ~296 dp of dead walnut letterbox above and
//             below = "museum debug viewer", emotionally cold.
//   • 5.15c — fit reverted to cover, height 0.62 → 0.54. Lowered crop to
//             ~37 % but still too aggressive on lateral architecture ;
//             frame still read as "boxed photo" not "integrated reveal".
//   • 5.15d — TRUE full reveal + cinematic matte. Three locked decisions :
//
// 5.15d (preserved here):
//   • Image fit : BoxFit.contain — the architecture is ALWAYS fully
//     visible. Zero crop guarantee. The "Full Reveal" promise honoured.
//   • Matte : a BoxFit.cover copy of the AFTER image, heavily blurred
//     (sigma 36) and RepaintBoundary-cached, sits as the first Stack
//     layer behind the contain'd foreground. The letterbox is no longer
//     dead walnut — it's the photo's own colour-extended halo (Apple TV /
//     Netflix / Spotify album-art vocabulary). The boxShadow is dropped
//     because the matte halo IS the new ambient depth.
//   • Container height : 0.56 × screenH (clamp 360…540). Mid of the
//     5.15d spec window (54–58 %).
//   • Generate CTA below the carousel. Auto-scroll to maxScrollExtent.
//
// 5.15m polish (this revision, post-device-test of 5.15l):
//   Ultra-minimal cleanup — surgical removals only, no structural
//   changes, no spacing rebalance, no typography touch.
//     • "Refine this direction in chat" OutlinedButton.icon removed
//       from the in-hero CTAs Positioned block (redundant — Continue
//       this vision already returns to chat). The 8 dp gap between
//       Continue and Refine dropped with it ; Column collapses naturally
//       so Continue stays as the single in-hero CTA at its existing
//       position (bottom: 14).
//     • "Generations use your latest image as the starting point"
//       footer microcopy removed from _buildControls (reads as
//       engineering noise). The preceding 18 dp gap dropped with it.
//       Scroll bottom padding (28 + safeArea.bottom) keeps the carousel
//       + Generate clear of the home indicator.
//     • `pageInset` local in _buildControls dropped (was only used by
//       the removed footer Padding).
//   Everything else 5.15l verbatim : hero geometry, image fit, backdrop
//   blur, ShaderMask feathering, walnut body gradient, RevealHero
//   slider, hold-to-peek, Continue / Generate CTA sizes and positions,
//   carousel responsive cardWidth, section title, hint copy.
//
// 5.15m–p PRIOR EXPERIMENTS (ALL REVERTED PRE-CURRENT-5.15m, kept as guardrail).
// The 5.15m–5.15p arc tried to refine the hero matte boundary :
//   5.15m added a top+bottom backdrop ShaderMask fade ;
//   5.15n trimmed it to top-only ;
//   5.15o flattened the body walnut gradient to uniform #181410 ;
//   5.15p removed the ShaderMask entirely.
// None of the four read better than 5.15l on device, so the stack is
// restored to its 5.15l state : warm 4-stop walnut body (#3F3220 →
// #181410), backdrop blur with no ShaderMask, rounded ClipRRect 22
// carrying the matte→walnut transition. Block kept as a guardrail
// against re-proposing the same matte experiments in future waves —
// the user explicitly preferred 5.15l.
//
// Original 5.15p polish documentation (now reverted):
//   • Backdrop blur ShaderMask removed. 5.15n's [0.0, 0.12] top-only
//     feather still produced a visible ~58 dp gradient at the hero's
//     upper edge. The user noticed the bottom edge has always been a
//     sharp matte→walnut transition (masked by the rounded ClipRRect
//     corner + the in-hero CTAs covering that band) and wants the top
//     to read the same way. Combined with 5.15o's uniform dark canvas,
//     the sharp matte→#181410 transition at the top is much less
//     jarring than it was on the legacy warm-walnut gradient, so the
//     fade can go entirely. Foreground image ShaderMask
//     (stops 0.30/0.70) is untouched and continues to soft-edge the
//     contain'd render itself.
//
// 5.15o polish (post-device-test of 5.15n):
//   • Body walnut canvas flattened from a 4-stop warm gradient (#3F3220
//     top → #181410 bottom) to a uniform #181410. The lighter top
//     (#3F3220) was the residual source of the top demarcation : the
//     5.15n ShaderMask hid the matte→walnut transition at the very
//     edge but the EYE still caught the colour step a few dp below,
//     where backdrop blur emerged at full opacity into the warmer
//     walnut. Uniform dark #181410 (matching the gradient's previous
//     bottom colour where immersion already worked) gives the matte
//     room to read as a warm halo against a deep dark canvas, top
//     and bottom now equivalent.
//
// 5.15n polish (post-device-test of 5.15m):
//   • Backdrop blur ShaderMask reduced to a TOP-only feather. 5.15m's
//     symmetric fade (top + bottom 12 %) fixed the top demarcation but
//     produced a fresh bottom one : the bright warm backdrop fading
//     into the dark walnut body created a luminance step at the
//     hero's rounded bottom edge that was absent pre-5.15m (the
//     in-hero CTAs already masked that area visually). Stops trimmed
//     to [0.0, 0.12] with colors [transparent, white] — Flutter
//     extends the last color to the end so the bottom 88 % stays
//     fully opaque. Top demarcation still hidden, bottom restored to
//     its pre-5.15m clean state.
//
// 5.15m polish (post-device-test of 5.15l):
//   • Backdrop blur top/bottom feather via ShaderMask (LinearGradient
//     stops 0.0/0.12/0.88/1.0, BlendMode.dstIn). The hero matte
//     previously stopped on a visible horizontal line at the rounded
//     edge — the user reported "trop de démarcation". With the new
//     mask, the top and bottom 12 % of the backdrop fade to
//     transparent, letting the walnut body show through. (Bottom
//     fade reverted in 5.15n — see above.)
//
// 5.15l polish (post-device-test of 5.15k):
//   • Scroll view bottom padding 14 → 28. The 5.15k footer microcopy
//     "Generations use your latest image…" was clipped by Android's
//     home indicator / gesture bar when the carousel was scrolled to
//     the end. MediaQuery.padding.bottom rounds near 0 on some Android
//     gesture configs, so adding a hard +14 dp guarantees the footer
//     clears the indicator regardless.
//
// 5.15k polish (post-device-test of 5.15j):
//   • Generate <atmosphere> CTA aligns visually with the in-hero
//     Continue : moves off the shared AppButton onto an inline
//     ElevatedButton with identical sizing (h 38, font 11 w600,
//     padding 20, radius 22). The two champagne accents now speak
//     one visual language across the screen.
//   • Carousel strip height 120 → 105 → drops AtmosphereCard from
//     `semi` mode (nameSize 15) into `compact` mode (nameSize 12.5),
//     i.e. ~17 % smaller atmosphere names. Combined with #3 below,
//     full names like "Tropical Escape" are reachable instead of
//     truncated to "Tropical ...".
//   • cardWidth formula ((W-72)/3.8).clamp(85,115) →
//     ((W-64)/3.3).clamp(95,125). On Pixel 393 dp : 85 → 100 dp wide
//     cards. Visible ratio stays close to 3.2 (3 fully visible + 0.2
//     peek) thanks to the new font landing in compact mode.
//   • AppButton import removed (no callsite left in this file ;
//     both in-hero CTAs and the Generate CTA are now inline).
//
// 5.15j polish (post-device-test of 5.15i):
//   Uniform -20 % size pass on the in-hero bottom block to bring it in
//   line with the target's compact bottom pair. Touch targets drop
//   below Material's 48 dp minimum — explicit trade for visual
//   match on this reveal screen.
//     • Continue : 48→38 / font 14→11 / sparkle 14→11 / radius 28→22 /
//       padding 24→20 / gap-icon-text 8→6.
//     • Refine   : 46→37 / font 13→10 / chat icon 14→11 / radius 28→22 /
//       padding 24→20.
//     • Hint     : touch icon 12→10 / text 10.5→8.5.
//     • Spacing  : hint→Continue 14→11 ; Continue→Refine 10→8 ;
//                  block bottom anchor 18→14.
//
// 5.15i polish (post-device-test of 5.15h):
//   The 5.15h spacing pass landed but the in-hero CTAs still read
//   heavier than the target's compact pair, and the "Explore other
//   atmospheres" label competed with the hero typographically.
//     • Continue this vision migrates from the shared AppButton to an
//       inline ElevatedButton so this single callsite can own its
//       sizing without altering the design-system widget. Height
//       58 → 48, font 16 → 14 (w600), sparkle 18 → 14.
//     • Refine this direction in chat : height 50 → 46, font 14 → 13,
//       chat icon 16 → 14. Slight hierarchy below Continue.
//     • "Explore other atmospheres" label : fontSize 18 → 14 (w500
//       preserved). Reads as a quiet section header, not a heading.
//
// 5.15h polish (post-device-test of 5.15g):
//   Annotated side-by-side vs the target showed four residual gaps :
//     1. hero block sat too high (subtitle ↔ matte top overlapped),
//     2. CTAs-in-hero rode with the hero so they felt glued to the image,
//     3. carousel cards too large → only ~2.5 visible (target ~3.5–4),
//     4. carousel ↔ Generate CTA too tight, bottom felt compressed.
//   Pure spacing/size pass (no structural change) :
//     • Image padding top 56 → 80 → pushes the whole hero down 24 dp,
//       drops the CTAs-in-hero in tandem ; subtitle ↔ matte gains a
//       clean 22 dp gap (was -2 dp overlap).
//     • cardWidth formula ((W-72)/3.4).clamp(96,128) →
//       ((W-72)/3.8).clamp(85,115). On Pixel 393 dp : 96 → 85 dp.
//       Visible cards 2.5 → 3.7.
//     • Strip height 130 → 120 (more thumbnail proportion), separator
//       10 → 8 (tighter strip rhythm).
//     • Title → carousel gap 14 → 18 ; carousel → Generate gap 14 → 24 ;
//       scroll top padding 8 → 12 — generous breathing across the
//       secondary section, premium pacing.
//
// 5.15g polish (post-device-test of 5.15e):
//   • Continue this vision + Refine this direction in chat migrate INTO
//     the hero frame, stacked right below the "Touch & hold to see
//     original" hint inside a single Positioned(left:24,right:24,bottom:18)
//     block. The "reveal + primary actions" sequence now reads as one
//     cinematic unit instead of "image card" + "buttons section" — matches
//     the target mockup. CTAs stay opaque during the hold-original peek
//     (affordance > visual purity) ; the hint still cross-fades.
//   • _buildControls loses the Continue + Refine pair and the 28 dp gap
//     that came after it. The scroll viewport gains ~120 dp of vertical
//     room, so the atmosphere carousel cards land in full rather than
//     getting cropped by the bottom safe area.
//   • _continueAction lifted to a State method so both the in-hero CTAs
//     share one definition.
//
// 5.15e polish (post-device-test of 5.15d):
//   • ShaderMask feather on the foreground image. 5.15d's matte was
//     correct but its boundary with the contain'd image read as a hard
//     horizontal cut on bright sources. A LinearGradient (stops 0.0,
//     0.30, 0.70, 1.0 ; alpha transparent → opaque → opaque → transparent)
//     applied via BlendMode.dstIn fades the top/bottom 30 % of the
//     image into transparency, so the foreground dissolves smoothly
//     into the blurred matte instead of ending on a sharp edge. The
//     hold-to-original cross-fade rides inside the same mask for
//     consistency.
//   • Labels (BEFORE / AI Vision) relocated OUTSIDE the ShaderMask :
//     at top:14 the mask alpha is ~9 %, which would ghost them. They
//     are now Positioned widgets in the outer image Stack and
//     cross-fade in sync with the Original pill (visible when not
//     peeking, hidden when peeking).
//   • Full Reveal title + Swipe to compare subtitle added at body Stack
//     level (top:SafeArea+12, centred). Cormorant-Garamond serif via
//     AppTheme.atmosphereTitle ; text-shadows for legibility against
//     bright matte. IgnorePointer so the tap immersive toggle still
//     fires.
//   • Carousel densified : cardWidth = clamp(((screenW-72)/3.4), 96, 128)
//     so ~3.3 cards land on Pixel (was ~1.7). Strip height 160 → 130,
//     separator 12 → 10. Premium thumbnails, not feed tiles.
//
// Visual shifts vs 5.13d:
//   • image dominance — surface jumps from AspectRatio(1.5) (~31 % screen
//     height, native 3:2 letterboxed) to SizedBox(screenH * 0.62) with
//     ClipRRect(22 dp) + deeper drop shadow. BoxFit.cover crops a touch
//     horizontally — the user explicitly preferred dominance over native
//     composition on the reveal surface.
//   • short edge gradients — top 0 → -0.6 (black 0.45 → 0) + bottom 0 → 0.6
//     (black 0.55 → 0) inside the image Stack. Local to the ~20 % edge
//     bands so the middle of the render stays untouched (the 5.13d note
//     rejected long edge-to-centre scrims as too aggressive — this stays
//     under that line while still adding cinematic legibility for the
//     BEFORE / AI VISION pills + touch-and-hold hint).
//   • atmospheres pushed lower — 2-col grid + 7th banner replaced by a
//     horizontal carousel (175 dp cards, 160 dp strip). Cards extend
//     edge-to-edge so the rightmost peeks past the screen edge, inviting
//     scroll. Section is now visually secondary to the reveal.
//   • outlined secondary CTA — "Refine this direction in chat" promoted
//     from tiny caption to outlined cream pill (50 dp), same action as
//     Continue (both pop to chat) — editorial duality reassures the user.
//   • walnut canvas preserved (#3F3220 → #181410) — the warm gradient
//     prolongs the render ambiance ; a flat dark would feel dashboard.
//
// Preserved verbatim (non-regression): RevealHero compare + slider,
// hold-to-peek ORIGINAL upload, immersive tap-toggle, the wave-4.8.3
// reveal-source resolution + fallback + debug log, the
// context.pop(_selectedAtmosphere) contract chat depends on, Share,
// floating back, mock/featured fallback. No backend / routing / session
// / generation changes.

class BeforeAfterScreen extends ConsumerStatefulWidget {
  final String projectId;
  // GeneratedResult passed as Object? so the router doesn't need a direct import.
  final Object? resultExtra;
  const BeforeAfterScreen(
      {super.key, required this.projectId, this.resultExtra});

  @override
  ConsumerState<BeforeAfterScreen> createState() => _BeforeAfterScreenState();
}

class _BeforeAfterScreenState extends ConsumerState<BeforeAfterScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _fadeAnim;

  // AYDEN Part A — owned only when the cinematic reveal flag is on. Lifted to
  // the screen (vs RevealWidget-owned) so the floating Replay control can
  // re-trigger the same reveal without leaving/re-entering the screen. Null
  // when the flag is off → zero behaviour change.
  RevealController? _revealController;

  // Wave 4.10f — three distinct concepts kept separate:
  //   _beforeUrl        → reveal SLIDER "before" = PREVIOUS SOURCE VISION
  //                       (per-step generation source: V1→upload, V2→V1,
  //                       V3→V2). Restored 4.8.3 semantics (4.10e wrongly
  //                       forced the initial upload onto the slider).
  //   _originalUploadUrl → HOLD-to-original = the INITIAL uploaded user
  //                       photo (4.10e session resolution retained, now on
  //                       its own field, independent of the slider).
  //   _afterUrl         → CURRENT vision (generation source — untouched).
  String? _beforeUrl;
  String? _originalUploadUrl;
  String? _afterUrl;
  String _title = '';
  // Wave 5.13b — _subtitle field dropped : the AppBar title slot no
  // longer exists in the reveal screen, and _title is still kept since
  // Share uses it ("Check out my AI home redesign — $_title!").
  // Wave 4.9.3 — display label for the compare SOURCE (left pill), passed by
  // chat_screen._openReveal ("Original" / an atmosphere name). Null → the left
  // pill falls back to the generic "Original" label.
  String? _sourceDisplayLabel;
  String? _selectedAtmosphere;

  // Wave 4.9.3 — the current vision's atmosphere for the RIGHT compare pill,
  // parsed from the style label ("Warm Modern · Vision 3" → "Warm Modern").
  // Falls back to the legacy "AI Vision" when no style is available (mock /
  // showcase rows).
  String get _currentAtmosphereLabel {
    final s = _title.split('·').first.trim();
    return s.isNotEmpty ? s : 'AI Vision';
  }

  // While the user holds, the original is shown full-bleed (temporary
  // override — NOT a second compare system).
  bool _holdingOriginal = false;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();
    _fadeAnim = CurvedAnimation(parent: _entryController, curve: Curves.easeOut);

    if (FeatureFlags.cinematicReveal) {
      _revealController =
          RevealController(vsync: this, profile: RevealProfile.cinematic);
    }

    final extra = widget.resultExtra;
    if (extra is GeneratedResult) {
      final after = extra.afterImageUrl.isNotEmpty ? extra.afterImageUrl : null;
      final beforeRaw =
          extra.beforeImageUrl.isNotEmpty ? extra.beforeImageUrl : null;
      // Wave 4.10f (#1): the SLIDER compares the PREVIOUS SOURCE VISION →
      // CURRENT vision. extra.beforeImageUrl IS that per-step source (the
      // 4.8.3 branch-safe source chat passes): for V1 it is the initial
      // upload, for V2 it is V1, for V3 it is V2 — exactly the natural
      // evolution comparison. 4.10e wrongly overrode this with the initial
      // upload; restore the 4.8.3 deterministic dedup here.
      final before =
          (beforeRaw != null && beforeRaw != after) ? beforeRaw : null;
      final mode = before != null
          ? 'pair'
          : (beforeRaw == null ? 'fallback_no_source' : 'fallback_same_pair');
      // Wave 4.10f (#2): the HOLD-to-original is a DIFFERENT concept — it
      // ALWAYS shows the very first uploaded user photo, independent of the
      // slider. The initial upload lives immutably on the session row
      // (ProjectModel.beforeImageUrl — set once at createSession, never
      // mutated). Resolve it by projectId; honest fallback to the per-step
      // source ONLY when no session upload exists (featured · mock ·
      // deep-link · legacy · no persisted upload). _afterUrl (generation
      // source) is untouched — three different concepts.
      final sessionOriginal = _sessionOriginalUrl();
      final originalUpload = sessionOriginal ?? beforeRaw;
      final src = sessionOriginal != null ? 'session' : 'extra';
      debugPrint('[Reveal] resolve — slider mode=$mode before=$before '
          'after=$after | hold-original src=$src original=$originalUpload');
      _beforeUrl = before;
      _originalUploadUrl = originalUpload;
      _afterUrl = after;
      _title = extra.styleLabel;
      _sourceDisplayLabel = extra.sourceDisplayLabel;
    } else {
      // Fallback: mock / featured data (showcase usage)
      final project = widget.projectId.startsWith('featured')
          ? featuredShowcase.firstWhere(
              (p) => p.id == widget.projectId,
              orElse: () => featuredShowcase.first,
            )
          : mockProjects.firstWhere(
              (p) => p.id == widget.projectId,
              orElse: () => mockProjects.first,
            );
      // Showcase/mock has no separate vision chain — the project "before"
      // is also the only original; slider and hold coincide here.
      _beforeUrl = project.beforeImageUrl;
      _originalUploadUrl = project.beforeImageUrl;
      _afterUrl = project.afterImageUrl;
      _title = project.title;
    }
  }

  // Wave 4.10e (#3): authoritative initial-upload URL for this project from
  // session state. ProjectModel.beforeImageUrl is set once at createSession
  // and never mutated (only afterImageUrl/title/messages change), so it is a
  // reliable source of the very first uploaded photo. Null ⇒ the caller
  // falls back to the GeneratedResult's before (featured · mock · deep-link ·
  // legacy · session with no persisted upload) — an honest fallback, never a
  // fabricated original.
  String? _sessionOriginalUrl() {
    for (final p in ref.read(sessionProvider)) {
      if (p.id == widget.projectId) {
        final b = p.beforeImageUrl;
        return (b != null && b.isNotEmpty) ? b : null;
      }
    }
    return null;
  }

  @override
  void dispose() {
    // Wave 5.10 — always restore system chrome on exit so the user
    // returns to chat with status + nav bars visible.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _entryController.dispose();
    _revealController?.dispose();
    super.dispose();
  }

  // Wave 4.9.3 — toggle the selected atmosphere. The Generate CTA now lives
  // in a fixed reserved slot below the carousel (no vertical scroll), so the
  // old counter-scroll-to-CTA is gone — re-tap deselects in place.
  void _selectAtmosphere(String name) {
    setState(() {
      _selectedAtmosphere = _selectedAtmosphere == name ? null : name;
    });
  }

  // Wave 5.17d — locked-card tap in the Full Reveal atmosphere
  // carousel. Surfaces the standard paywall sheet ; same trigger and
  // restricted_field semantics as the upload-screen lock handler so
  // analytics and copy stay consistent across surfaces.
  Future<void> _openCarouselPaywall(
    BuildContext context, String restrictedField,
  ) async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PaywallSheet(
        trigger: PaywallTrigger.locked,
        restrictedField: restrictedField,
      ),
    );
  }

  // Wave 5.15g — Continue this vision / Refine this direction in chat
  // both pop back to chat with the current resultExtra so the user can
  // keep iterating on this vision. Lifted to a State method so both the
  // in-hero CTAs (image Stack) and any future callsites share one
  // implementation.
  void _continueAction() => context.canPop()
      ? context.pop(widget.resultExtra)
      : context.go('/home');

  // AYDEN Part A (A4) — open the immersive fullscreen reveal (option A). A
  // dedicated route with its own controller; a soft fade in/out. Flag-gated +
  // only when a before exists (a reveal needs two images).
  void _openFullscreenReveal() {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) => RevealFullscreenScreen(
          beforeUrl: _beforeUrl,
          afterUrl: _afterUrl,
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  // Slider availability (previous-source-vision → current). Gates the
  // RevealHero before-image + its compare wipe.
  bool get _hasBefore => _beforeUrl != null && _beforeUrl!.isNotEmpty;

  // Hold-to-original availability — INDEPENDENT of the slider (Wave 4.10f
  // distinction). Gates the long-press gesture + the discoverability hint:
  // hold is offered whenever there is a real initial upload to reveal.
  bool get _hasOriginal =>
      _originalUploadUrl != null && _originalUploadUrl!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final screenH = MediaQuery.sizeOf(context).height;
    // Wave 5.15d — true full reveal with cinematic matte. Image fit
    // switches back to BoxFit.contain (zero crop on the architecture)
    // and the letterbox is no longer dead walnut — a blurred BoxFit.cover
    // copy of the AFTER image fills the matte (see image Stack below),
    // so the framing reads "image extending into its own halo" (Apple TV /
    // Netflix vocabulary). Height 0.56 sits mid-range (54–58 % spec window)
    // : enough matte to feel cinematic, not so much that the foreground
    // photo collapses on small phones. Clamp 360…540 keeps SE usable
    // and avoids over-scaling on tablets.
    // Wave 4.9.3 — 0.56 → 0.50: give the enlarged atmosphere carousel more
    // vertical room while the image stays clearly dominant. Then minus the
    // section-header allowance (the "Explore other atmospheres" title moved out
    // of the hero overlay into the cards section): trimming the hero by exactly
    // that height keeps the controls Expanded — and thus the card size —
    // identical to the validated layout.
    const sectionHeaderH = 34.0;
    final imageH =
        (screenH * 0.50).clamp(340.0, 500.0) - sectionHeaderH;

    return Scaffold(
      backgroundColor: AppColors.textPrimary,
      // Wave 5.13b — AppBar removed entirely. The image now reaches the
      // safe-area top edge. Back navigation lives in a floating discreet
      // button overlay at top-left (see Stack below). Style + subtitle
      // metadata dropped from the top — the user came in via the chat
      // bubble eyebrow which already established context. The reveal
      // becomes a near-gallery contemplation surface, not a Material
      // screen with chrome around an image.
      body: FadeTransition(
        opacity: _fadeAnim,
        // Wave 5.13b cleanup — architectural reset of the reveal layout.
        // Dropped : RevealCanvas ambient blur backdrop (the "dead zone"
        // above the image that wasted vertical real estate without
        // adding value), top/bottom scrims, bottomOverlay slot.
        // Restored : a simple Column structure with the image surface
        // anchored to the safe-area top and the controls anchored to
        // the bottom. The image now reads as the structural centre of
        // the reveal, not a component centred inside chrome.
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Full-bleed warm walnut canvas (Wave 5.13d simplify) ──────
            // Gradient lives at the BOTTOM of the Stack so it covers the
            // entire body — including the buffer space below the image
            // inside the image block. Previously this buffer fell on the
            // Scaffold's near-black backgroundColor, creating a visible
            // "dead zone" between the image and the bottom controls.
            // Now the image floats on a continuous warm canvas from top
            // to bottom — galleria, not dashboard.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.0, 0.30, 0.65, 1.0],
                    colors: [
                      Color(0xFF3F3220),
                      Color(0xFF2F2519),
                      Color(0xFF221C14),
                      Color(0xFF181410),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // ── Main image (Wave 5.13d simplify) ─────────────────────
                  // Single dominant image experience. The compare slider
                  // and the hold-to-peek BOTH live inside this surface —
                  // no duplicated mini block below. Sized to ~48 % of
                  // screen height — large enough to anchor the top half
                  // visually, tight enough that the gap below the native
                  // 3:2 image stays a calm transition zone (not a
                  // gaping black wasteland). Native 3:2 image sits
                  // anchored to the very top ; warm canvas continues
                  // beneath, blending seamlessly into the bottom
                  // controls' background.
                  //
                  // Gesture stack (Flutter arena resolves naturally) :
                  //   • horizontal drag → RevealHero slider (surface mode)
                  //   • tap             → immersive toggle (chrome out)
                  //   • long-press      → hold-to-peek ORIGINAL upload
                  //                       (architecturally distinct from
                  //                       the slider's "before" which on
                  //                       V2+ is the previous vision)
                  // Wave 5.13d.8 — full-composition reveal. The reveal
                  // is the place where the user expects to see the
                  // COMPLETE architectural render — windows, sofa, TV,
                  // ceiling, corners. No cover crop. Image renders at
                  // its native 3:2 ratio, edge-to-edge full width,
                  // anchored just below the safe-area top. Warm walnut
                  // gradient (Positioned.fill behind the Stack) fills
                  // whatever vertical space remains. Immersion comes
                  // from top anchoring + tight bottom chrome, not from
                  // zooming the image. Scrims dropped : a 110 dp top
                  // scrim would have darkened ~40 % of the native-ratio
                  // image — too aggressive ; the floating back/share
                  // buttons already carry their own dark circle backdrop
                  // for legibility, and the hint has a text-shadow.
                  Padding(
                    // Wave 5.15 — cinematic full-reveal block. Top inset
                    // 56 dp keeps a calm floating zone for the back +
                    // share buttons, horizontal 8 dp keeps the surface
                    // away from the hard screen edge, bottom 8 dp lets
                    // the warm walnut canvas breathe before the CTA
                    // stack starts.
                    padding: const EdgeInsets.fromLTRB(8, 80, 8, 8),
                    child: SizedBox(
                      height: imageH,
                      width: double.infinity,
                      // Wave 5.15d — boxShadow dropped. The blurred matte
                      // backdrop inside the Stack creates its own ambient
                      // halo ; an external drop shadow on top of that
                      // re-introduced a hard "card on walnut" reading
                      // that fought the blend. ClipRRect kept (rounded
                      // 22 dp) so the matte itself has soft corners.
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          // Wave 4.9.3 — tapping the photo now ENLARGES it
                          // (opens the fullscreen reveal), replacing the old
                          // immersive-chrome toggle + the removed expand button.
                          onTap: _openFullscreenReveal,
                          onLongPressStart: _hasOriginal
                              ? (_) =>
                                  setState(() => _holdingOriginal = true)
                              : null,
                          onLongPressEnd: _hasOriginal
                              ? (_) =>
                                  setState(() => _holdingOriginal = false)
                              : null,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // ── Cinematic blurred matte (Wave 5.15d) ──
                              // A BoxFit.cover copy of the AFTER image,
                              // heavily blurred and RepaintBoundary-cached.
                              // Fills the entire surface, so the
                              // BoxFit.contain foreground (slider + hold-
                              // peek) is now framed by a continuation of
                              // its OWN tones rather than dead walnut.
                              // Apple-TV / Netflix vocabulary : the photo
                              // extends into its own halo. Cover crop on
                              // the matte is fine — it's a backdrop, not
                              // the architecture surface. Anchored as the
                              // first layer so the slider + labels + hint
                              // paint on top, never affected by the blur.
                              // Wave 5.15d backdrop blur (preserved
                              // through 5.15l). A BoxFit.cover copy of
                              // the AFTER image, heavily blurred and
                              // RepaintBoundary-cached, fills the entire
                              // surface so the BoxFit.contain foreground
                              // is now framed by a continuation of its
                              // OWN tones rather than dead walnut. The
                              // 5.15m/n ShaderMask feathers tried and
                              // were reverted (see header comment) :
                              // sharper matte→walnut edges read more
                              // cleanly under the rounded ClipRRect.
                              if (_afterUrl != null &&
                                  _afterUrl!.isNotEmpty)
                                Positioned.fill(
                                  child: RepaintBoundary(
                                    child: ImageFiltered(
                                      imageFilter: ui.ImageFilter.blur(
                                          sigmaX: 36, sigmaY: 36),
                                      child: _RevealImage(
                                        url: _afterUrl,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ),
                              // Wave 5.15e — ShaderMask soft-feather the
                              // foreground image into the blurred matte.
                              // BlendMode.dstIn means the gradient's alpha
                              // drives the child's alpha : opaque centre
                              // (0.30..0.70 of the surface) shows the image
                              // fully, top and bottom 30 % fade to
                              // transparent so the contain'd image's edges
                              // dissolve into the matte rather than
                              // ending in a hard horizontal cut. Wraps
                              // BOTH the slider AND the hold-original
                              // cross-fade so the softening stays
                              // consistent when peeking the upload.
                              // showLabels: false on RevealHero —
                              // labels live OUTSIDE the mask now (top:14
                              // would otherwise be ~10 % opacity).
                              ShaderMask(
                                shaderCallback: (rect) =>
                                    const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  stops: [0.0, 0.30, 0.70, 1.0],
                                  colors: [
                                    Colors.transparent,
                                    Colors.white,
                                    Colors.white,
                                    Colors.transparent,
                                  ],
                                ).createShader(rect),
                                blendMode: BlendMode.dstIn,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    // Slider surface (or plain image when
                                    // no before). BoxFit.contain via
                                    // _RevealImage default — full
                                    // composition guaranteed.
                                    AnimatedOpacity(
                                      opacity: _holdingOriginal ? 0.0 : 1.0,
                                      duration:
                                          const Duration(milliseconds: 150),
                                      curve: Curves.easeOut,
                                      // Pinch (2 fingers) zooms in place, snaps
                                      // back on release. Pan disabled so the
                                      // 1-finger RevealHero slider drag, tap and
                                      // long-press-peek all still pass through.
                                      child: PinchZoom(
                                        child: _hasBefore
                                          // AYDEN Part A (A2) — behind a
                                          // feature flag (OFF by default). When
                                          // on, the cinematic RevealWidget
                                          // replaces the RevealHero slider on
                                          // this surface only; everything else
                                          // (incl. Home/FTUE) keeps RevealHero
                                          // verbatim.
                                          ? (FeatureFlags.cinematicReveal
                                              ? RevealWidget(
                                                  afterImage: _RevealImage(
                                                      url: _afterUrl),
                                                  beforeImage: _RevealImage(
                                                      url: _beforeUrl),
                                                  controller: _revealController,
                                                  profile:
                                                      RevealProfile.cinematic,
                                                  interaction: RevealInteraction
                                                      .surface,
                                                  showLabels: false,
                                                )
                                              : RevealHero(
                                                  afterImage: _RevealImage(
                                                      url: _afterUrl),
                                                  beforeImage: _RevealImage(
                                                      url: _beforeUrl),
                                                  initialFraction: 0.5,
                                                  autoSweep: false,
                                                  dragMode:
                                                      RevealDragMode.surface,
                                                  // 5.13d.11 — compact handle
                                                  // 30 dp (vs 38) softens the
                                                  // white circle's weight.
                                                  variant:
                                                      RevealVariant.compact,
                                                  showLabels: false,
                                                ))
                                          : _RevealImage(url: _afterUrl),
                                      ),
                                    ),
                                    // Original upload cross-fade — wrapped
                                    // inside the same ShaderMask so peek
                                    // gets the same edge feather.
                                    IgnorePointer(
                                      child: AnimatedOpacity(
                                        opacity:
                                            _holdingOriginal ? 1.0 : 0.0,
                                        duration: const Duration(
                                            milliseconds: 150),
                                        curve: Curves.easeOut,
                                        child: _RevealImage(
                                            url: _originalUploadUrl),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                                // Wave 5.15 — short cinematic gradients
                                // hugging the top and bottom edges only.
                                // The 5.13d note correctly rejected long
                                // edge-to-centre scrims as too aggressive
                                // (~40 % of the native render darkened) ;
                                // these stop at ~20 % of the surface
                                // height so the architecture composition
                                // stays untouched in the middle while
                                // the labels + hint gain legibility.
                                // IgnorePointer so the gradient layer
                                // never traps the slider drag.
                                const IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment(0, -0.6),
                                        colors: [
                                          Color(0x73000000),
                                          Color(0x00000000),
                                        ],
                                      ),
                                    ),
                                    child: SizedBox.expand(),
                                  ),
                                ),
                                const IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment(0, 0.6),
                                        colors: [
                                          Color(0x8C000000),
                                          Color(0x00000000),
                                        ],
                                      ),
                                    ),
                                    child: SizedBox.expand(),
                                  ),
                                ),
                                // Wave 5.15e — labels relocated OUTSIDE
                                // the ShaderMask so they stay fully
                                // opaque at top:14 (the mask's top fade
                                // would otherwise crush them to ~10 %
                                // opacity). Cross-fade with
                                // _holdingOriginal mirrors the Original
                                // pill below : Before/AI Vision visible
                                // when not peeking, Original visible
                                // when peeking, same spot.
                                if (_hasBefore)
                                  Positioned(
                                    top: 14,
                                    left: 14,
                                    child: IgnorePointer(
                                      child: AnimatedOpacity(
                                        opacity:
                                            _holdingOriginal ? 0.0 : 1.0,
                                        duration: const Duration(
                                            milliseconds: 150),
                                        curve: Curves.easeOut,
                                        // Wave 4.9.3 — contextual SOURCE label
                                        // ("Original" / "Warm Modern" / …)
                                        // instead of generic "Before"; falls
                                        // back to the localized "Original".
                                        child: AppPill(
                                            text: _sourceDisplayLabel ??
                                                context.l10n.beforeLabel),
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  top: 14,
                                  right: 14,
                                  child: IgnorePointer(
                                    child: AnimatedOpacity(
                                      opacity: _holdingOriginal ? 0.0 : 1.0,
                                      duration:
                                          const Duration(milliseconds: 150),
                                      curve: Curves.easeOut,
                                      // Wave 4.9.3 — the current vision's
                                      // atmosphere instead of generic "AI
                                      // Vision".
                                      child: AppPill(
                                          text: _currentAtmosphereLabel,
                                          dark: true),
                                    ),
                                  ),
                                ),
                                // "Original" label, fades with the upload.
                                Positioned(
                                  top: 14,
                                  left: 14,
                                  child: IgnorePointer(
                                    child: AnimatedOpacity(
                                      opacity: _holdingOriginal ? 1.0 : 0.0,
                                      duration:
                                          const Duration(milliseconds: 150),
                                      curve: Curves.easeOut,
                                      child:
                                          AppPill(text: context.l10n.beforeLabel),
                                    ),
                                  ),
                                ),
                                // Wave 5.15g — hint + Continue + Refine
                                // all live in ONE Positioned block at
                                // the bottom of the hero frame. Pulls
                                // the primary actions INTO the reveal
                                // surface so the moment "reveal +
                                // decide" reads as one cinematic unit,
                                // and frees the scroll area below for
                                // the atmosphere carousel (no more
                                // cropped cards). CTAs stay opaque
                                // during the hold-original peek
                                // (affordance > visual purity) ; only
                                // the hint cross-fades, like before.
                                Positioned(
                                  left: 24,
                                  right: 24,
                                  bottom: 14,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (_hasOriginal) ...[
                                        IgnorePointer(
                                          child: AnimatedOpacity(
                                            opacity: _holdingOriginal
                                                ? 0.0
                                                : 1.0,
                                            duration: const Duration(
                                                milliseconds: 150),
                                            curve: Curves.easeOut,
                                            child: Center(
                                              child: Row(
                                                mainAxisSize:
                                                    MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons
                                                        .touch_app_outlined,
                                                    size: 10,
                                                    color: AppColors
                                                        .surface
                                                        .withValues(
                                                            alpha: 0.85),
                                                    shadows: const [
                                                      Shadow(
                                                        color: Color(
                                                            0x99000000),
                                                        blurRadius: 4,
                                                        offset:
                                                            Offset(0, 1),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'Touch & hold to see original',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: AppColors
                                                              .surface
                                                              .withValues(
                                                                  alpha:
                                                                      0.88),
                                                          fontSize: 8.5,
                                                          letterSpacing:
                                                              0.3,
                                                          shadows: const [
                                                            Shadow(
                                                              color: Color(
                                                                  0x99000000),
                                                              blurRadius: 4,
                                                              offset:
                                                                  Offset(
                                                                      0,
                                                                      1),
                                                            ),
                                                          ],
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        // Wave 4.9.3 — the hint stays at the
                                        // image bottom; "Explore other
                                        // atmospheres" moved OUT of this overlay
                                        // into the section header above the
                                        // cards (see _buildControls).
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  // ── Editorial content below image ────────────────────────
                  // No own decoration — the warm walnut gradient is applied
                  // full-bleed by the Positioned.fill above so the canvas
                  // is continuous from the top of the image block down to
                  // the bottom safe-area edge.
                  // Wave 4.9.3 — the whole Full Reveal fits on ONE page (no
                  // vertical scroll): _buildControls is a bounded column whose
                  // carousel Expands to fill this remaining height. Horizontal
                  // scroll of the carousel is preserved.
                  Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: 12,
                          // Wave 4.9.3 — 28 → 8: push the Generate CTA lower,
                          // closer to the home indicator (safeArea.bottom still
                          // keeps it clear of the gesture bar).
                          bottom: 8 + MediaQuery.of(context).padding.bottom,
                        ),
                        child: _buildControls(context, l10n, screenH),
                      ),
                    ),
                ],
              ),
            ),
            // Wave 5.13b — floating back button. Discreet, semi-transparent
            // backdrop ; sits at the safe-area corner over the image and
            // any scrim layer. Always available (not hidden by immersive
            // mode) so navigation escape is one-tap from anywhere. The
            // smaller icon (16dp vs the old 18dp AppBar back) and lower
            // background alpha (0.65 vs 0.86) lighten the visual weight.
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 12,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => context.canPop()
                      ? context.pop()
                      : context.go('/home'),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.65),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_back,
                      size: 16,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
            // Wave 5.13c — floating Share button top-right. Mirrors the
            // back button visual weight (same backdrop alpha, same icon
            // sizing). Share emotionally belongs to the reveal experience
            // ; was previously in the bottom CTA row.
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              right: 12,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Share.share(
                    'Check out my AI home redesign — $_title!',
                  ),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.65),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.ios_share,
                      size: 16,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
            // Wave 4.9.3 — "Refine in chat" pencil. Replaces the old in-hero
            // "Continue this vision" CTA (same _continueAction → pop back to
            // chat to keep editing this vision). Top-LEFT, right of Back, in
            // the slot freed by the removed expand button (right:52 was hidden
            // behind the Replay control). Same floating visual language.
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 52,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _continueAction,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.65),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.edit_outlined,
                      size: 16,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
            // Wave 4.9.3 — the floating Fullscreen (expand) button is removed.
            // Tapping the photo now opens the fullscreen reveal (see the image
            // GestureDetector onTap), and the freed left:52 slot holds the
            // Refine pencil above.
            // AYDEN Part A — floating Replay control (flag-gated). Re-triggers
            // the cinematic reveal in place so the user never has to leave and
            // re-enter Full Reveal. Sits left of Share, same visual language.
            if (FeatureFlags.cinematicReveal &&
                _hasBefore &&
                _revealController != null)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 8,
                right: 52,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _revealController!.replay(),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.65),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.replay,
                        size: 16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            // Wave 5.15e — Full Reveal title + Swipe to compare subtitle.
            // Overlays the very top of the image area (where the top
            // gradient + ShaderMask fade darken the matte) so the white
            // serif type reads without fighting the architecture below.
            // IgnorePointer so taps pass through to the image's
            // immersive toggle. Centred between the back / share
            // buttons ; no horizontal overlap since the floating
            // buttons hug the screen edges (left:12 / right:12) while
            // the title column is centred and ~200 dp wide.
            Positioned(
              top: MediaQuery.paddingOf(context).top + 12,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Full Reveal',
                      textAlign: TextAlign.center,
                      style: AppTheme.atmosphereTitle(
                        fontSize: 30,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.95),
                        height: 1.1,
                        letterSpacing: -0.3,
                      ).copyWith(
                        shadows: const [
                          Shadow(
                            color: Color(0x66000000),
                            blurRadius: 10,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.swipe,
                          size: 13,
                          color: Colors.white.withValues(alpha: 0.70),
                          shadows: const [
                            Shadow(
                              color: Color(0x66000000),
                              blurRadius: 6,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Swipe to compare',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.70),
                            letterSpacing: 0.3,
                            shadows: const [
                              Shadow(
                                color: Color(0x66000000),
                                blurRadius: 6,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Wave 5.15g — Continue + Refine CTAs migrated INTO the hero frame
  // (see image Stack above). _buildControls now starts directly with
  // the atmosphere section : title, carousel, Generate CTA on select,
  // footer. The scroll viewport gains ~120 dp of vertical room, so the
  // carousel cards land in full instead of getting cropped by the
  // bottom safe area.
  Widget _buildControls(
      BuildContext context, AppLocalizations l10n, double screenH) {
    final screenW = MediaQuery.sizeOf(context).width;
    // Wave 4.9.3 — section = header title + carousel + Generate slot. The
    // "Explore other atmospheres" title now lives HERE (above the cards) as the
    // section header, not in the hero overlay. The hero image was trimmed by
    // sectionHeaderH so the carousel Expanded — and thus the card size — is
    // unchanged from the validated layout.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Section header — "Explore other atmospheres" (localized) ──────
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.pagePadding, 0, AppSpacing.pagePadding, 10),
          child: Text(
            context.l10n.exploreOtherAtmospheres,
            textAlign: TextAlign.left,
            style: const TextStyle(
              color: AppColors.surface,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
        // ── Enlarged atmosphere carousel — fills the section height ───────
        // The whole Full Reveal stays on ONE page (no vertical scroll), so the
        // carousel Expands to fill the available height. Card width is
        // proportional to that height (new-design ~1.2 w/h), capped at 80% of
        // the screen so a card never exceeds the viewport. HORIZONTAL scroll
        // preserved — the next card peeks past the right edge.
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              // Wave 4.9.3 (hierarchy rebalance) — cards fill ~82% of the
              // section height (was 100%) so the generated vision stays the
              // hero. WIDTH unchanged (still derived from the FULL section
              // height), only the height shrinks ~18%; the shorter strip is
              // centred so the freed space reads as calm breathing room.
              final cardW = (c.maxHeight * 1.35).clamp(170.0, screenW * 0.86);
              final cardH = c.maxHeight * 0.82;
              return Align(
                alignment: Alignment.center,
                child: SizedBox(
                  height: cardH,
                  child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.pagePadding),
                itemCount: AppLocalizations.atmospheres.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final a = AppLocalizations.atmospheres[i];
                  // Wave 5.17d — free-tier scope: non-premium users get
                  // Nordic Warmth + Soft Luxury tappable; the rest dimmed
                  // with a lock chip; locked tap → paywall. Admin / promo
                  // grant bypass the lock.
                  final isPremium = ref.watch(premiumProvider);
                  final isAdmin = ref.watch(accessProvider);
                  final hasPromo =
                      ref.watch(meStatusProvider)?.hasActivePromo ?? false;
                  final locked = !isPremium && !isAdmin && !hasPromo
                      && !kFreeAtmosphereIds.contains(a.id);
                  final onTap = locked
                      ? () => _openCarouselPaywall(context, 'atmosphere')
                      : () => _selectAtmosphere(a.name);
                  return SizedBox(
                    width: cardW,
                    child: FeatureFlags.newDesignCards
                        ? AtmosphereHeroCard(
                            name: a.name,
                            subtitle: context.l10n.atmosphereSubtitle(a.id),
                            asset: kAtmosphereCardById[a.id]?.asset ??
                                'assets/cards/atmospheres/${a.id}.png',
                            selected: _selectedAtmosphere == a.name,
                            locked: locked,
                            // Wave 4.9.3 — photo fills the card (no black
                            // letterbox frame), corners stay rounded via the
                            // card's ClipRRect; type dialed down for these
                            // mid-size cards.
                            fillPhoto: true,
                            nameFontSize: 16,
                            subtitleFontSize: 11,
                            onTap: onTap,
                          )
                        : AtmosphereCard(
                            atmosphere: a,
                            selected: _selectedAtmosphere == a.name,
                            dark: true,
                            variant: AtmosphereCardVariant.compact,
                            locked: locked,
                            onTap: onTap,
                          ),
                  );
                },
                  ),
                ),
              );
            },
          ),
        ),
        // ── Generate CTA — fixed reserved slot below the carousel ────────
        // Wave 4.9.3 — a constant-height slot (not AnimatedSize) so picking
        // a card reveals the CTA WITHOUT shrinking the carousel above. Same
        // behaviour: pops with the atmosphere name, chat fires the switch.
        SizedBox(
          height: 52,
          child: _selectedAtmosphere != null
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pagePadding, 14, AppSpacing.pagePadding, 0),
                  child: SizedBox(
                    height: 38,
                    child: ElevatedButton(
                      onPressed: () => context.pop(_selectedAtmosphere),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.surface,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                      child: Text(
                        'Generate $_selectedAtmosphere',
                        style: TextStyle(
                          color: AppColors.surface,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

}

// ── Image widget — handles local assets and network URLs (kept) ───────────────

class _RevealImage extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  const _RevealImage({this.url, this.fit = BoxFit.contain});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return const ColoredBox(color: AppColors.shimmerBase);
    }
    // Wave 5.15d — true full reveal. Default fit is BoxFit.contain so
    // the FULL architectural composition (windows, openings, ceiling,
    // sofa, TV…) is always visible on the slider + hold-original
    // surfaces. 5.15b had the same fit but felt cold (image floating
    // in a flat walnut letterbox) ; 5.15d solves that at the parent
    // level by stacking a blurred BoxFit.cover variant of the same
    // image BEHIND the contain'd foreground — the matte continues the
    // image's own tones, no more dead-frame feel.
    //
    // `fit` is exposed so the parent can request the cover-blur
    // backdrop variant. Callers other than the backdrop should leave
    // the default and stay full-composition.
    if (url!.startsWith('assets/')) {
      return Image.asset(
        url!,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, _, _) =>
            const ColoredBox(color: AppColors.shimmerBase),
      );
    }
    return CachedNetworkImage(
      imageUrl: url!,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      placeholder: (_, _) => const ColoredBox(color: AppColors.shimmerBase),
      errorWidget: (_, _, _) => const ColoredBox(color: AppColors.shimmerBase),
    );
  }
}
