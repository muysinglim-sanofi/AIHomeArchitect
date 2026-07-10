/// Wave 5.17d.1 — Premium paywall sheet (RevenueCat purchase + restore).
///
/// Layout (top → bottom, scrollable) — pricing-first :
///   1. Drag handle
///   2. Compact animated before/after hero (auto-cycling slider)
///   3. Atmosphere preview strip (horizontal scroll)
///   4. Headline "Redesign an entire home / for less than $8"
///   5. Pricing : Weekly (gold) + Annual (green) — ABOVE THE FOLD
///   6. Benefits row (4 compact icon chips)
///   7. Social proof (single line — stars + rating + reviews)
///   8. Trust footer : 7-day guarantee + payment chips
///   9. Restore Purchase + Not now
///
/// Design intent : the user should see the price without much scrolling.
/// The paywall sells fast, not as a long landing page. Heavy marketing
/// content (social proof, benefits) sits BELOW the pricing cards.
///
/// Pricing (Wave 5.17d.1 re-pivot — supersedes the brief Weekly-only)
///   Weekly Premium  — $7.99 / week  (PackageType.weekly)
///   Annual Premium  — $79.99 / year (PackageType.annual)
/// Both prices come from RevenueCat at runtime ; placeholder strings
/// render only when RC is not configured (degraded mode in dev).
///
/// Sign-in routing (Wave 5.17d Decision D8)
///   The sheet does NOT open SignInScreen. Sign-in is hidden in V1
///   (FeatureFlags.signInEnabled=false). Restore Purchases handles the
///   "I bought premium on another device" case via Apple/Google store
///   account binding ; no sign-in flow is presented.
///
/// Payment chips
///   Apple Pay, Google Pay, Visa, Mastercard render unconditionally.
///   ABA / ACLEDA gated by FeatureFlags.cambodianPaymentBadges (OFF
///   until a real Cambodian processor is wired and store policy is
///   reviewed — showing those badges without a backing processor would
///   violate App Store + Play "misleading payment claims" rules).
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_fonts/google_fonts.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/feature_flags.dart';
import '../../core/l10n/app_localizations.dart';
import '../../data/services/revenuecat_service.dart';
import '../promo/promo_redeem_sheet.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/reveal_hero.dart';

// ── Palette (paywall-local — dark luxury theme) ─────────────────────────────

const Color _paywallBg = Color(0xFF0E0C09);
const Color _paywallCard = Color(0xFF1A1612);
const Color _paywallCardSoft = Color(0xFF15110D);
const Color _gold = Color(0xFFD6A85F);
const Color _green = Color(0xFF6CBF8F);
const Color _textPrimary = Colors.white;
const Color _textMuted = Color(0xFFD8D1C8);
const Color _textDim = Color(0xFF8C857B);
const Color _borderSubtle = Color(0xFF2A241D);
// Antique champagne gold — luxe, NOT a bright/canva yellow.
const Color _goldBright = Color(0xFFD6B25E); // MAIN gold: text, price, borders
const Color _goldLight = Color(0xFFE7CB82); // light highlight / glow / sheen only
const Color _champagne = Color(0xFFFFF3DC); // warm off-white for headings/cards
const Color _planMuted = Color(0xFFC8B99B); // muted warm grey for descriptions

/// Removes the Android overscroll STRETCH (and the glow) from the paywall
/// scroll view. The stretch was distorting the hero layer on overscroll and
/// briefly exposing the image's bottom edge under the fixed fade.
class _NoStretchScrollBehavior extends MaterialScrollBehavior {
  const _NoStretchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;
}

enum PaywallTrigger {
  quota,    // QUOTA_EXHAUSTED — used all free generations
  freeTier, // FREE_TIER_RESTRICTED — out-of-scope choice
  locked,   // user tapped a locked card directly
}

class PaywallSheet extends StatefulWidget {
  /// Discriminator for the contextual lead-in copy.
  final PaywallTrigger trigger;

  /// When trigger == PaywallTrigger.freeTier, the specific field that
  /// was restricted ('room', 'atmosphere', 'delegated_choice', '').
  final String restrictedField;

  const PaywallSheet({
    super.key,
    this.trigger = PaywallTrigger.quota,
    this.restrictedField = '',
  });

  @override
  State<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<PaywallSheet> {
  Offering? _offering;
  bool _loading = true;
  bool _busy = false;
  String? _errorMessage;
  // Wave 6.17 — single-CTA model: the cards are radio-selectable and one
  // global CTA purchases the selected plan. Annual = default (best value).
  bool _annualSelected = true;

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    // FAST_BOOT — RevenueCat configure() runs fire-and-forget at boot. Ensure it
    // has finished (or finish it now) before reading offerings, so a paywall
    // opened in the first seconds isn't empty. No-op once configured; safe in
    // legacy boot (already configured before runApp).
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      await RevenuecatService.instance.ensureConfigured(userId: userId);
      if (!mounted) return;
    }
    final offerings = await RevenuecatService.instance.loadOfferings();
    if (!mounted) return;
    setState(() {
      _offering = offerings?.current;
      _loading = false;
    });
  }

  Future<void> _onPurchasePressed(Package pkg) async {
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final activated = await RevenuecatService.instance.purchasePackage(pkg);
      if (!mounted) return;
      if (activated) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _busy = false;
          _errorMessage = l10n.pwErrIncomplete;
        });
      }
    } on RevenuecatNotConfiguredException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = l10n.pwErrNotAvailable;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
        setState(() => _busy = false);
        return;
      }
      if (errorCode == PurchasesErrorCode.productAlreadyPurchasedError) {
        // P0 (2026-07-10) — Apple « You're currently subscribed » → NE PAS juste
        // afficher premium : restaurer + synchroniser le pass mesuré côté backend.
        // _onRestorePressed re-déclenche RC restore → webhook → pass ; le refetch
        // /me/status (à la fermeture du paywall) montre la vérité (spaces ou restore).
        await _onRestorePressed();
        return;
      }
      setState(() {
        _busy = false;
        _errorMessage = e.message ?? l10n.pwErrFailed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = l10n.pwErrFailed;
      });
    }
  }

  Future<void> _onRestorePressed() async {
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final restored = await RevenuecatService.instance.restorePurchases();
      if (!mounted) return;
      if (restored) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _busy = false;
          _errorMessage = l10n.pwErrNoRestore;
        });
      }
    } on RevenuecatNotConfiguredException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = l10n.pwErrNotAvailable;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = l10n.pwErrFailed;
      });
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final sheetHeight = media.size.height * 0.94;
    // Wave 5.17d.2 — hero takes 40% of screen height. Dominant visual
    // anchor : the user understands "this app transforms real spaces"
    // immediately. Pricing cards still land within ~1 finger-scroll on
    // Pixel-6-class devices thanks to the 3-line trust block and the
    // benefits row being removed (below the fold was redundant with
    // the in-card checklists).
    final heroHeight = media.size.height * 0.40;

    final selectedPackages = _selectPackages(_offering);
    final weekly = selectedPackages.weekly;
    final annual = selectedPackages.annual;

    return Container(
      height: sheetHeight,
      // clipBehavior so the full-bleed hero's top corners follow the 28px radius.
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: _paywallBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Stack(
          children: [
            // ── Wave 6.19 — full-background cinematic illusion (V2) ──
            // The animated image extends to 72% of the screen, BEHIND the
            // content, with FIXED overlays darkening it into the warm dark
            // interface. Only the image scales; overlays + content are siblings.
            if (FeatureFlags.paywallV2) ...[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: media.size.height * 0.72,
                child: const _KenBurnsImage(
                  asset: 'assets/cards/atmospheres/warm_modern.png',
                  // Center keeps the sofa/table/rug context — less aggressive crop.
                  alignment: Alignment.center,
                ),
              ),
              const Positioned.fill(
                child: IgnorePointer(child: _HeroVerticalFade()),
              ),
              const Positioned.fill(
                child: IgnorePointer(child: _HeroWarmDepth()),
              ),
              // Subtle top cinematic film so the gold logo reads (separate from
              // the bottom fade; fixed — never animates with the image).
              const Positioned.fill(
                child: IgnorePointer(child: _HeroTopScrim()),
              ),
            ],
            _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _gold),
                  )
                : _buildScrollableContent(
                    heroHeight: heroHeight,
                    weekly: weekly,
                    annual: annual,
                  ),
            // Fixed AYDEN STUDIO logo pinned at the top — the real brand asset
            // (clean compass + AYDEN + STUDIO crop) on the subtle top scrim.
            if (FeatureFlags.paywallV2)
              Positioned(
                top: (media.viewPadding.top > 0 ? media.viewPadding.top : 24) + 20,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Opacity(
                      opacity: 0.90,
                      child: Image.asset(
                        // Mixed logo (per-element dosed): WHITE AYDEN + AI
                        // ARCHITECT ASSISTANT at full, gold compass −28% & STUDIO
                        // −18% → AYDEN is the visual anchor, compass recedes.
                        'assets/branding/ayden_logo_mixed.png',
                        width: (media.size.width * 0.245).clamp(102.0, 138.0),
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (_, _, _) => const _AydenWordmark(),
                      ),
                    ),
                  ),
                ),
              ),
            // Wave 5.17d.2 — explicit dismiss affordance in the top-
            // right. The drag-down gesture is preserved (and the
            // bottom "Not now" button is too), but the explicit X is
            // the universal "close this overlay" cue. Sits above the
            // hero with a soft scrim background so it stays legible
            // over varied artwork.
            // The sheet content runs under the status bar (SafeArea top:false
            // so the hero reaches the top). The close button MUST sit BELOW the
            // status bar / notch — otherwise the OS intercepts the taps there.
            // Use viewPadding (the REAL notch inset — never zeroed by the modal,
            // unlike padding.top which the bottom-sheet route reports as 0) with
            // a floor so it's always clearly below the system UI.
            // Subtle drag affordance, centered over the hero (white so it reads
            // over the artwork). The drag-to-dismiss gesture is unchanged.
            Positioned(
              top: (media.viewPadding.top > 0 ? media.viewPadding.top : 24) + 10,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: (media.viewPadding.top > 0 ? media.viewPadding.top : 24) + 14,
              right: 12,
              child: _CloseButton(
                onTap: _busy ? null : () => Navigator.of(context).pop(false),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollableContent({
    required double heroHeight,
    required Package? weekly,
    required Package? annual,
  }) {
    if (FeatureFlags.paywallV2) {
      return _buildContentV2(weekly: weekly, annual: annual);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: [
        // ── Above the fold : hero → title → social proof → pricing ───
        const _DragHandle(),
        const SizedBox(height: 10),
        _PaywallAnimatedHero(height: heroHeight),
        const SizedBox(height: 14),
        const _MarketingHeadline(),
        const SizedBox(height: 10),
        const _CompactSocialProof(),
        const SizedBox(height: 14),
        _PricingSection(
          weeklyPackage: weekly,
          annualPackage: annual,
          busy: _busy,
          onWeekly:
              weekly == null ? null : () => _onPurchasePressed(weekly),
          onAnnual:
              annual == null ? null : () => _onPurchasePressed(annual),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF3A1F1F),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _errorMessage!,
              style: const TextStyle(
                color: Color(0xFFE8A8A8),
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
        // ── Below the fold : secondary details ───────────────────────
        // Wave 5.17d.2 — _BenefitsRow removed : the in-card 3-bullet
        // checklists already convey the value, an extra row below the
        // prices was visual noise.
        const SizedBox(height: 16),
        const _PaymentTrustFooter(),
        const SizedBox(height: 14),
        _RestoreAndDismissActions(
          busy: _busy,
          onRestore: _onRestorePressed,
          onDismiss: () => Navigator.of(context).pop(false),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  // ── V2 — premium emotional redesign (flag-gated, FeatureFlags.paywallV2) ───
  // Frontend/UI only. Reuses the exact pricing/purchase wiring (onWeekly /
  // onAnnual → _onPurchasePressed) — nothing about subscription logic changes.
  Widget _buildContentV2({
    required Package? weekly,
    required Package? annual,
  }) {
    final selectedPkg = _annualSelected ? annual : weekly;
    final screenH = MediaQuery.of(context).size.height;
    // The hero image + fade + warm depth are FIXED layers BEHIND this scroll
    // view (built in build()). Here the top is a transparent spacer that reveals
    // them; the headline sits on the dark fade; the lower section carries its own
    // warm-charcoal background that scrolls WITH it (covers the image during
    // scroll) and fades in at the top so it reads as the SAME cinematic fade.
    // ClampingScrollPhysics + no-stretch kills the overscroll strip exposure.
    return ScrollConfiguration(
      behavior: const _NoStretchScrollBehavior(),
      child: ListView(
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          // 1. Hero zone — transparent (the FIXED image + fade show through).
          //    screenH-based + a small fixed nudge so the headline settles a
          //    touch deeper into the cinematic fade.
          SizedBox(height: screenH * 0.43 + 32),
          // 2. Headline + subtitle — emerges from the fixed dark fade.
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: _HeadlineV2(),
          ),
          // 3. Lower section — warm-charcoal bg (NOT flat black). Fades in from
          //    transparent at the top (continuous with the fade) → opaque body
          //    that covers the image during scroll → settles to base #0E0C09.
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                // Warm charcoal (NOT flat black). Transparent at the very top so
                // the room/fade shows through the transition; opaque WARM body
                // (covers the image on scroll); settles to base #0E0C09.
                stops: [0.0, 0.18, 0.55, 1.0],
                colors: [
                  Color(0x00120D08),
                  Color(0xFF1A130C), // warm charcoal (brownish, opaque)
                  Color(0xFF130F0A),
                  Color(0xFF0E0C09), // base — exact match
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 30, 22, 30),
              child: Column(
                children: [
                  // 4 feature pills — sells the value fast.
                  const _FeaturesRowV2(),
                  const SizedBox(height: 28),
                  // Radio-selectable plan cards — single global CTA below.
                  _PricingV2(
                    weeklyPackage: weekly,
                    annualPackage: annual,
                    annualSelected: _annualSelected,
                    onSelectAnnual: () =>
                        setState(() => _annualSelected = true),
                    onSelectWeekly: () =>
                        setState(() => _annualSelected = false),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    _PaywallErrorBox(message: _errorMessage!),
                  ],
                  const SizedBox(height: 22),
                  // ── Single global CTA → purchases the SELECTED plan ──
                  _PrimaryPaywallButton(
                    label: context.l10n.pwUnlockPremium,
                    color: _goldBright,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFE2C06B),
                        Color(0xFFC79B3A),
                        Color(0xFFB8862C),
                      ],
                    ),
                    leadingIcon: Icons.workspace_premium_rounded,
                    showArrow: true,
                    // Always live (bright) — never a dead washed button. If the
                    // store returned no offering (e.g. billing unconfigured),
                    // tapping surfaces a clear message instead of doing nothing.
                    enabled: !_busy,
                    loading: _busy,
                    onTap: _busy
                        ? null
                        : () {
                            if (selectedPkg == null) {
                              setState(() => _errorMessage =
                                  context.l10n.pwErrNotAvailable);
                            } else {
                              _onPurchasePressed(selectedPkg);
                            }
                          },
                  ),
                  const SizedBox(height: 11),
                  Text(
                    context.l10n.pwCancelAnytime,
                    style: const TextStyle(color: _textDim, fontSize: 11.5),
                  ),
                  const SizedBox(height: 24),
                  const _PaymentTrustFooter(),
                  const SizedBox(height: 16),
                  _RestoreAndDismissActions(
                    busy: _busy,
                    onRestore: _onRestorePressed,
                    onDismiss: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Close button (top-right overlay) ────────────────────────────────────────

class _CloseButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Raw pointer handling via Listener — it does NOT join the gesture arena,
    // so it can't lose the tap to the modal's drag-to-dismiss recognizer (the
    // reason a GestureDetector/IconButton overlay here never fired). onPointerUp
    // always fires when the finger lifts over the 44px opaque target.
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerUp: onTap == null ? null : (_) => onTap!(),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          ),
          child: const Icon(Icons.close, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}

// ── Package selection helper ────────────────────────────────────────────────

class _SelectedPackages {
  const _SelectedPackages({required this.weekly, required this.annual});
  final Package? weekly;
  final Package? annual;
}

_SelectedPackages _selectPackages(Offering? offering) {
  final pkgs = offering?.availablePackages ?? const <Package>[];
  Package? findByType(PackageType type) {
    for (final p in pkgs) {
      if (p.packageType == type) return p;
    }
    return null;
  }

  return _SelectedPackages(
    weekly: findByType(PackageType.weekly),
    annual: findByType(PackageType.annual),
  );
}

// ── Drag handle ─────────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 4,
        decoration: BoxDecoration(
          color: _textDim.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

// ── Paywall animated hero (Wave 5.17d.2 — final) ────────────────────────────
//
// Carousel of 3 before/after photo pairs (villa, apartment, facade),
// using the SAME RevealHero + PageView pattern as the home screen so
// the rhythm is proven : auto-sweep settles to fraction ~0.42 and holds
// long enough for the user to see the "After" before transitioning.
//
// Layered surprise : a subtle Ken-Burns transform (slow scale + tiny
// pan) is applied to the "After" image so the result feels alive
// during the hold window — premium cinematic cue, not a gimmick.
//
// Timer rhythm : 8s per photo (vs home's 10s) — paywall context is
// intent-driven, slightly tighter pacing. Sweep 2.8s (RevealHero
// internal) + hold ~5s + crossfade 250ms → next photo.

class _PaywallAnimatedHero extends StatefulWidget {
  const _PaywallAnimatedHero({required this.height});

  final double height;

  @override
  State<_PaywallAnimatedHero> createState() => _PaywallAnimatedHeroState();
}

class _PaywallAnimatedHeroState extends State<_PaywallAnimatedHero> {
  static const _photos = <_PhotoPair>[
    _PhotoPair(
      before: 'assets/showcase/villa_before.jpg',
      after: 'assets/showcase/villa_after.jpg',
    ),
    _PhotoPair(
      before: 'assets/showcase/apartment_before.jpg',
      after: 'assets/showcase/apartment_after.jpg',
    ),
    _PhotoPair(
      before: 'assets/showcase/facade_before.jpg',
      after: 'assets/showcase/facade_after.jpg',
    ),
  ];

  late final PageController _pageController;
  int _currentPage = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startTimer();
  }

  void _startTimer() {
    // 6s per photo : ~0.8s autoSweep delay + ~2.8s sweep + ~2.4s hold
    // on the settled position before the page transitions. Tighter than
    // the home carousel's 10s — paywall context is intent-driven, the
    // user is comparing photos to decide, not browsing.
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted) return;
      final next = (_currentPage + 1) % _photos.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: PageView.builder(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _photos.length,
          onPageChanged: (i) => setState(() => _currentPage = i),
          itemBuilder: (_, index) {
            final p = _photos[index];
            // dragMode.handle : the autoSweep animation is gated on
            // `dragMode != none` inside RevealHero — using `.none`
            // would visually freeze the slider at initialFraction.
            // `.handle` keeps the auto-sweep running AND gives the
            // user a 44px draggable strip on the slider if they want
            // to compare the photos manually.
            return RevealHero(
              key: ValueKey<int>(index),
              afterImage: _KenBurnsImage(asset: p.after),
              beforeImage: _PlainAssetImage(asset: p.before),
              initialFraction: 0.30,
              autoSweep: true,
              dragMode: RevealDragMode.handle,
              beforeLabel: 'Before',
              afterLabel: 'After',
              showLabels: true,
            );
          },
        ),
      ),
    );
  }
}

class _PhotoPair {
  final String before;
  final String after;
  const _PhotoPair({required this.before, required this.after});
}

class _PlainAssetImage extends StatelessWidget {
  final String asset;
  const _PlainAssetImage({required this.asset});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(color: _paywallCardSoft),
    );
  }
}

/// Subtle Ken-Burns motion (slow scale + tiny pan) on the After image.
/// Premium cinematic cue : the result image breathes during the hold
/// window so the slide doesn't feel static. 12-second cycle, reverses.
class _KenBurnsImage extends StatefulWidget {
  final String asset;
  final Alignment alignment;
  const _KenBurnsImage({required this.asset, this.alignment = Alignment.center});

  @override
  State<_KenBurnsImage> createState() => _KenBurnsImageState();
}

class _KenBurnsImageState extends State<_KenBurnsImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<Offset> _pan;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.035).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _pan = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.012, 0.0),
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _ctrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ClipRect is ESSENTIAL: the scale (from center) makes the image overflow
    // its box top & bottom. Without clipping, the bottom edge bleeds DOWN past
    // the hero, painting over the content below the fixed gradient — which reads
    // as the dark band "rising" during the zoom. Clipping keeps only the image
    // pixels moving, fully contained; the gradient/text siblings never move.
    return ClipRect(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          return Transform.scale(
            scale: _scale.value,
            child: FractionalTranslation(
              translation: _pan.value,
              child: child,
            ),
          );
        },
        child: Image.asset(
          widget.asset,
          fit: BoxFit.cover,
          alignment: widget.alignment,
          errorBuilder: (_, _, _) => Container(color: _paywallCardSoft),
        ),
      ),
    );
  }
}


// ── Marketing headline ──────────────────────────────────────────────────────
//
// Two-line gold-accent headline. No subtitle, no lead-in — pricing
// sits directly underneath so the user reads price within the first
// scroll. Contextual messaging (quota exhausted / atmosphere locked)
// is conveyed by the surrounding flow ; adding it here would push the
// pricing cards below the fold.

class _MarketingHeadline extends StatelessWidget {
  const _MarketingHeadline();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'Redesign an entire home',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        RichText(
          textAlign: TextAlign.center,
          text: const TextSpan(
            children: [
              TextSpan(
                text: 'for less than ',
                style: TextStyle(
                  color: _textMuted,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
              TextSpan(
                text: '\$8',
                style: TextStyle(
                  color: _gold,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Compact social proof (above pricing) ────────────────────────────────────
//
// Three-line emotional trust block, centred between the marketing
// headline and the pricing cards :
//
//                 ★ ★ ★ ★ ★
//        Loved by 12,500+ homeowners
//                TrustScore 4.9
//
// Emotional ("Loved by ... homeowners") rather than clinical ("4.9/5
// from 12,500 reviews"). No Trustpilot logo — "TrustScore" is the
// neutral generic-rating language we can use without licensing. The
// "12,500+" number is highlighted in gold to draw the eye.

class _CompactSocialProof extends StatelessWidget {
  const _CompactSocialProof();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _paywallCardSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              5,
              (_) => const Padding(
                padding: EdgeInsets.symmetric(horizontal: 1.5),
                child: Icon(Icons.star, color: _gold, size: 15),
              ),
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            textAlign: TextAlign.center,
            text: const TextSpan(
              children: [
                TextSpan(
                  text: 'Loved by ',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: '12,500+',
                  style: TextStyle(
                    color: _gold,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(
                  text: ' homeowners',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'TrustScore 4.9',
            style: TextStyle(
              color: _textDim,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pricing section ─────────────────────────────────────────────────────────

class _PricingSection extends StatelessWidget {
  final Package? weeklyPackage;
  final Package? annualPackage;
  final bool busy;
  final VoidCallback? onWeekly;
  final VoidCallback? onAnnual;

  const _PricingSection({
    required this.weeklyPackage,
    required this.annualPackage,
    required this.busy,
    required this.onWeekly,
    required this.onAnnual,
  });

  @override
  Widget build(BuildContext context) {
    // Wave 5.17d.2 — always 2-col (mobile included). Side-by-side
    // anchors MOST POPULAR vs BEST VALUE so the value comparison is
    // immediate, matching the reference mockup. Cards are kept narrow
    // on phones by dropping HomeProjectTiles + trimming checklists to
    // 3 items in `_WeeklyCard` / `_AnnualCard`.
    final weekly = _WeeklyCard(
      package: weeklyPackage,
      enabled: !busy && onWeekly != null,
      onTap: onWeekly,
    );
    final annual = _AnnualCard(
      package: annualPackage,
      enabled: !busy && onAnnual != null,
      onTap: onAnnual,
    );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: weekly),
          const SizedBox(width: 10),
          Expanded(child: annual),
        ],
      ),
    );
  }
}

// ── Pricing card shell ──────────────────────────────────────────────────────

class _PremiumCardShell extends StatelessWidget {
  final Color accent;
  final String badge;
  final Widget child;

  const _PremiumCardShell({
    required this.accent,
    required this.badge,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // Wave 5.17d.2 — compact padding for 2-col mobile cards. Badge sits
    // floating above the card via a negative top offset.
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
            decoration: BoxDecoration(
              color: _paywallCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: accent.withValues(alpha: 0.55),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.10),
                  blurRadius: 16,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: child,
          ),
          Positioned(
            top: -10,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
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

// ── Weekly card ─────────────────────────────────────────────────────────────

class _WeeklyCard extends StatelessWidget {
  final Package? package;
  final bool enabled;
  final VoidCallback? onTap;

  const _WeeklyCard({
    required this.package,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final price = package?.storeProduct.priceString ?? '\$7.99';

    return _PremiumCardShell(
      accent: _gold,
      badge: 'MOST POPULAR',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Weekly',
            style: TextStyle(
              color: _gold,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    price,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  '/ wk',
                  style: TextStyle(color: _textMuted, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Wave 5.17d.2 — house + condo marketing tiles stacked
          // vertically with a thin "OR" divider between them. Tells
          // the prospect "for less than $8 you can redesign an entire
          // home" — much more vivid than a feature bullet list alone.
          const _CompactProjectTile(
            asset: 'assets/showcase/villa_after.jpg',
            title: 'Large house',
            caption: 'up to 6 spaces',
          ),
          const SizedBox(height: 5),
          const _StackedOrDivider(),
          const SizedBox(height: 5),
          const _CompactProjectTile(
            asset: 'assets/showcase/apartment_after.jpg',
            title: '2 condos',
            caption: 'one project each',
          ),
          const SizedBox(height: 10),
          const _CheckList(
            accent: _gold,
            fontSize: 10.5,
            items: [
              'All rooms unlocked',
              'All atmospheres',
              'HD exports',
            ],
          ),
          const SizedBox(height: 12),
          _PrimaryPaywallButton(
            label: 'Subscribe',
            color: _gold,
            enabled: enabled,
            onTap: onTap,
          ),
          const SizedBox(height: 5),
          Text(
            'Billed weekly · Cancel anytime',
            style: const TextStyle(color: _textDim, fontSize: 9.5),
          ),
        ],
      ),
    );
  }
}

// ── Project tiles + horizontal OR divider (Weekly card) ─────────────────────

class _CompactProjectTile extends StatelessWidget {
  final String asset;
  final String title;
  final String caption;

  const _CompactProjectTile({
    required this.asset,
    required this.title,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 42,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              asset,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(color: _paywallCardSoft),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.65),
                    Colors.black.withValues(alpha: 0.15),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 9.5,
                      height: 1.1,
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

class _StackedOrDivider extends StatelessWidget {
  const _StackedOrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(child: Container(height: 1, color: _borderSubtle)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            'OR',
            style: TextStyle(
              color: _textDim,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Expanded(child: Container(height: 1, color: _borderSubtle)),
      ],
    );
  }
}

// ── Annual card ─────────────────────────────────────────────────────────────

class _AnnualCard extends StatelessWidget {
  final Package? package;
  final bool enabled;
  final VoidCallback? onTap;

  const _AnnualCard({
    required this.package,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final price = package?.storeProduct.priceString ?? '\$79.99';

    return _PremiumCardShell(
      accent: _green,
      badge: 'BEST VALUE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Annual',
            style: TextStyle(
              color: _green,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    price,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  '/ yr',
                  style: TextStyle(color: _textMuted, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Best for serious projects',
            style: TextStyle(
              color: _green,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          const _CheckList(
            accent: _green,
            fontSize: 11,
            items: [
              'Everything in Weekly',
              'Best for multiple homes',
              'Priority support',
            ],
          ),
          const SizedBox(height: 10),
          // Savings box — compact for 2-col mobile.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _green.withValues(alpha: 0.35)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Save 65%',
                  style: TextStyle(
                    color: _green,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  '\$1.55 / wk',
                  style: TextStyle(color: _textMuted, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _PrimaryPaywallButton(
            label: 'Subscribe',
            color: _green,
            enabled: enabled,
            onTap: onTap,
          ),
          const SizedBox(height: 6),
          Text(
            'Billed yearly · Cancel anytime',
            style: const TextStyle(color: _textDim, fontSize: 9.5),
          ),
        ],
      ),
    );
  }
}

// ── Checklist ───────────────────────────────────────────────────────────────

class _CheckList extends StatelessWidget {
  final List<String> items;
  final Color accent;
  final double fontSize;

  const _CheckList({
    required this.items,
    required this.accent,
    this.fontSize = 13,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.map((label) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_circle, color: accent, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: _textMuted,
                    fontSize: fontSize,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ── Primary CTA ─────────────────────────────────────────────────────────────

class _PrimaryPaywallButton extends StatelessWidget {
  final String label;
  final Color color;
  // When set, the button fills with this gradient (bright gold CTA). Falls
  // back to the flat [color] otherwise (legacy per-card buttons).
  final Gradient? gradient;
  // Premium CTA extras: a leading icon (e.g. crown) + a trailing arrow.
  final IconData? leadingIcon;
  final bool showArrow;
  final bool enabled;
  final bool loading;
  final VoidCallback? onTap;

  const _PrimaryPaywallButton({
    required this.label,
    required this.color,
    this.gradient,
    this.leadingIcon,
    this.showArrow = false,
    required this.enabled,
    this.loading = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const Color ink = Color(0xFF120E08);
    final Color glow = gradient != null ? _goldBright : color;
    const TextStyle labelStyle = TextStyle(
      color: ink,
      fontSize: 16.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.2,
    );
    final Widget inner;
    if (loading) {
      inner = const Center(
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2.2, color: ink),
        ),
      );
    } else if (leadingIcon != null) {
      inner = Row(
        children: [
          const SizedBox(width: 18),
          const Spacer(),
          Icon(leadingIcon, color: ink, size: 20),
          const SizedBox(width: 8),
          Text(label, style: labelStyle),
          const Spacer(),
          showArrow
              ? const Icon(Icons.arrow_forward_ios_rounded, color: ink, size: 16)
              : const SizedBox(width: 18),
        ],
      );
    } else {
      inner = Center(
        child: Text(label, textAlign: TextAlign.center, style: labelStyle),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.5,
        duration: const Duration(milliseconds: 150),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: gradient,
            color: gradient == null ? color : null,
            borderRadius: BorderRadius.circular(18),
            border: gradient != null
                ? Border.all(
                    color: _goldLight.withValues(alpha: 0.55), width: 1)
                : null,
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: glow.withValues(alpha: 0.22),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: (enabled && !loading) ? onTap : null,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
                child: inner,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Payment trust footer ────────────────────────────────────────────────────

class _PaymentTrustFooter extends StatelessWidget {
  const _PaymentTrustFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _paywallCardSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined, color: _gold, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.l10n.pwGuarantee,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Text(
              context.l10n.pwGuaranteeSub,
              style: const TextStyle(color: _textMuted, fontSize: 11),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            context.l10n.pwSecurePayments,
            style: const TextStyle(
              color: _textDim,
              fontSize: 11,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const _PaymentChipRow(),
        ],
      ),
    );
  }
}

class _PaymentChipRow extends StatelessWidget {
  const _PaymentChipRow();

  @override
  Widget build(BuildContext context) {
    final chips = <_PaymentChip>[
      if (Platform.isIOS)
        const _PaymentChip(icon: Icons.apple, label: 'Apple Pay'),
      if (Platform.isAndroid)
        const _PaymentChip(icon: Icons.android, label: 'Google Pay'),
      const _PaymentChip(icon: Icons.credit_card, label: 'Visa'),
      const _PaymentChip(icon: Icons.credit_card, label: 'Mastercard'),
      if (FeatureFlags.cambodianPaymentBadges) ...const [
        _PaymentChip(icon: Icons.account_balance, label: 'ABA'),
        _PaymentChip(icon: Icons.account_balance, label: 'ACLEDA'),
      ],
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips,
    );
  }
}

class _PaymentChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _PaymentChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _paywallCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _textMuted),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: _textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Restore + dismiss ───────────────────────────────────────────────────────

class _RestoreAndDismissActions extends StatelessWidget {
  final bool busy;
  final VoidCallback onRestore;
  final VoidCallback onDismiss;

  const _RestoreAndDismissActions({
    required this.busy,
    required this.onRestore,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              context.l10n.pwAlreadySubscribed,
              style: const TextStyle(color: _textDim, fontSize: 13),
            ),
            TextButton(
              onPressed: busy ? null : onRestore,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: _gold,
              ),
              child: Text(
                context.l10n.pwRestore,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Sprint 1B — discreet promo entry (never competes with the sub CTAs).
        const PromoCodeLink(),
        const SizedBox(height: 6),
        AppButton(
          label: context.l10n.pwNotNow,
          variant: AppButtonVariant.ghost,
          fullWidth: true,
          onPressed: busy ? null : onDismiss,
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// V2 — PREMIUM EMOTIONAL REDESIGN (FeatureFlags.paywallV2)
// Frontend/UI only — no pricing/RevenueCat/subscription logic touched.
// ════════════════════════════════════════════════════════════════════════════

/// FIXED full-sheet vertical fade (Wave 6.19). Sibling of the image — never
/// animates. Darkens the WHOLE paywall progressively so the living-room image
/// dissolves into the warm dark interface and the pricing sits on the SAME
/// cinematic fade. Reaches fully-solid #0E0C09 (≈0.74) BEFORE the image layer
/// ends (0.72 screen ≈ 0.766 of the 0.94 sheet) — the image disappears before
/// its edge, so no scroll/stretch can expose a raw strip.
class _HeroVerticalFade extends StatelessWidget {
  const _HeroVerticalFade();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          // Smoky cinematic "dark glass" — 7 stops for a soft, continuous
          // transition (no mathematical banding). Starts almost clear (0x08),
          // never fully opaque (max 0xF2) so it never reads as a black block.
          // The opaque lower-section bg (which scrolls) hides the image edge in
          // the pricing area, so the fixed fade can stay translucent.
          stops: [0.0, 0.24, 0.42, 0.58, 0.74, 0.90, 1.0],
          colors: [
            Color(0x080E0C09),
            Color(0x180E0C09),
            Color(0x3D0E0C09),
            Color(0x700E0C09),
            Color(0xA80E0C09),
            Color(0xD90E0C09),
            Color(0xF20E0C09),
          ],
        ),
      ),
    );
  }
}

/// FIXED warm-brown depth overlay (Wave 6.19). Keeps the dark area WARM, not
/// flat black — a soft brown glow near the top + gentle darkening at the
/// bottom. Very subtle; sits over the fade for cinematic depth.
class _HeroWarmDepth extends StatelessWidget {
  const _HeroWarmDepth();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topCenter,
          radius: 1.2,
          colors: [
            Color(0x186B431F), // very subtle warm brown (not orange/gold)
            Color(0x00000000),
            Color(0x660E0C09), // gentle bottom depth
          ],
          stops: [0.0, 0.45, 1.0],
        ),
      ),
    );
  }
}

/// FIXED top cinematic film (Wave 6.21). A very subtle dark scrim at the TOP
/// only, so the gold AYDEN logo reads over bright artwork. Separate from the
/// bottom fade; fades to transparent by ~0.34 — no black band.
class _HeroTopScrim extends StatelessWidget {
  const _HeroTopScrim();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          // Cinematic top film — softened so it reads as "the logo is naturally
          // legible", not as a visible overlay. Room stays luminous.
          stops: [0.0, 0.25, 0.45],
          colors: [
            Color(0xB30B0B0B),
            Color(0x4D0B0B0B),
            Color(0x000B0B0B),
          ],
        ),
      ),
    );
  }
}

/// Typographic AYDEN STUDIO signature (Montserrat) — fallback if the logo PNG
/// is ever unavailable.
class _AydenWordmark extends StatelessWidget {
  const _AydenWordmark();

  @override
  Widget build(BuildContext context) {
    // A discreet luxury signature — reduced opacity + soft glow so it never
    // competes with the headline.
    return Opacity(
      opacity: 0.72,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'AYDEN',
            style: GoogleFonts.montserrat(
              color: Colors.white.withValues(alpha: 0.90),
              fontSize: 21,
              fontWeight: FontWeight.w300,
              letterSpacing: 7,
              shadows: [
                Shadow(color: _gold.withValues(alpha: 0.18), blurRadius: 8),
                const Shadow(color: Color(0x4D000000), blurRadius: 6),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'STUDIO',
            style: GoogleFonts.montserrat(
              color: _gold.withValues(alpha: 0.82),
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
              letterSpacing: 5.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeadlineV2 extends StatelessWidget {
  const _HeadlineV2();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final double w = MediaQuery.sizeOf(context).width;
    final bool small = w < 380;
    // 3-line editorial hierarchy: "Design your" (serif), "dream home" (larger
    // serif), "with AI" (fine antique-gold script signature — deliberately small,
    // NOT a huge word). Strong shadows keep it legible over the photo.
    const List<Shadow> shadows = [
      Shadow(color: Color(0xB3000000), blurRadius: 12),
      Shadow(color: Color(0x66000000), blurRadius: 4),
    ];
    final l1 = GoogleFonts.playfairDisplay(
      color: _champagne,
      fontSize: small ? 30 : 32,
      height: 0.95,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.5,
      shadows: shadows,
    );
    final l2 = GoogleFonts.playfairDisplay(
      color: _champagne,
      fontSize: small ? 37 : 40,
      height: 0.95,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.9,
      shadows: shadows,
    );
    final l3 = GoogleFonts.greatVibes(
      color: _goldBright,
      fontSize: small ? 29 : 32,
      height: 0.82,
      fontWeight: FontWeight.w400,
      shadows: shadows,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.pwHeadlineLead, textAlign: TextAlign.center, style: l1),
        Transform.translate(
          offset: const Offset(0, -2),
          child: Text(l10n.pwHeadlineTrail,
              textAlign: TextAlign.center, style: l2),
        ),
        Transform.translate(
          offset: const Offset(0, -6),
          child: Text(l10n.pwHeadlineAccent,
              textAlign: TextAlign.center, style: l3),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(
            l10n.pwSubheadline,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFE9DDC7),
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              height: 1.32,
              shadows: [Shadow(color: Color(0x99000000), blurRadius: 8)],
            ),
          ),
        ),
      ],
    );
  }
}

/// 4 feature pills (Wave 6.17) — Unlimited / HD / All Styles & Rooms / No
/// Watermark. Sells the value fast; replaces the old "how it works" steps.
class _FeaturesRowV2 extends StatelessWidget {
  const _FeaturesRowV2();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = <(IconData, String)>[
      (Icons.meeting_room_outlined, l10n.pwFeatUnlimited),
      (Icons.high_quality_outlined, l10n.pwFeatHd),
      (Icons.chair_outlined, l10n.pwFeatAllStyles),
      (Icons.verified_outlined, l10n.pwFeatNoWatermark),
    ];
    // Premium glass capsule holding the 4 benefits, with thin gold dividers.
    return Container(
      height: 84,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0B08).withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _goldBright.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 42,
                color: _goldBright.withValues(alpha: 0.12),
              ),
            Expanded(
                child: _FeaturePill(icon: items[i].$1, label: items[i].$2)),
          ],
        ],
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeaturePill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _goldBright, size: 20),
          const SizedBox(height: 7),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFEADFCB),
              fontSize: 11.5,
              height: 1.15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PricingV2 extends StatelessWidget {
  final Package? weeklyPackage;
  final Package? annualPackage;
  final bool annualSelected;
  final VoidCallback onSelectAnnual;
  final VoidCallback onSelectWeekly;

  const _PricingV2({
    required this.weeklyPackage,
    required this.annualPackage,
    required this.annualSelected,
    required this.onSelectAnnual,
    required this.onSelectWeekly,
  });

  @override
  Widget build(BuildContext context) {
    final annualPrice = annualPackage?.storeProduct.priceString ?? '\$79.99';
    final weeklyPrice = weeklyPackage?.storeProduct.priceString ?? '\$7.99';
    // Horizontal side-by-side — editorial + compact, preserves the hero space
    // and brings the CTA into view sooner. Annual (left) is the hero option.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _PlanCardV2(
              badge: context.l10n.pwPlanBadgeAnnual,
              name: context.l10n.pwAnnual,
              price: annualPrice,
              period: context.l10n.pwPerYear,
              included: context.l10n.pwAnnualSpaces,
              description: context.l10n.pwAnnualSpacesSub,
              selected: annualSelected,
              onTap: onSelectAnnual,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _PlanCardV2(
              badge: context.l10n.pwPlanBadgeWeekly,
              name: context.l10n.pwWeekly,
              price: weeklyPrice,
              period: context.l10n.pwPerWeek,
              included: context.l10n.pwWeeklySpaces,
              description: context.l10n.pwWeeklySpacesSub,
              selected: !annualSelected,
              onTap: onSelectWeekly,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact vertical plan card (Wave 6.20). Side-by-side; no per-card button —
/// a single global CTA purchases the selected plan. Selected = gold border +
/// soft glow + warmer fill. Faux warm-glass via a subtle vertical sheen (no
/// BackdropFilter — the bg behind is opaque, a blur would be a no-op).
class _PlanCardV2 extends StatelessWidget {
  final String badge;
  final String name;
  final String price;
  final String period;
  final String included;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _PlanCardV2({
    required this.badge,
    required this.name,
    required this.price,
    required this.period,
    required this.included,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Dark glass card. Selected = gold border + strong gold glow + a warm
    // top-right sheen + a GOLD price; unselected stays subtle. Selection is pure
    // UI → always tappable, never gated on store offerings.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: selected
                  ? const [Color(0xFF1E170F), Color(0xFF0D0A07)]
                  : const [Color(0xFF15120E), Color(0xFF0B0907)],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color:
                  selected ? _goldBright : _goldBright.withValues(alpha: 0.16),
              width: selected ? 1.5 : 1.0,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _goldBright.withValues(alpha: 0.22),
                      blurRadius: 22,
                      spreadRadius: 1,
                      offset: const Offset(0, 9),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.38),
                      blurRadius: 18,
                      offset: const Offset(0, 12),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.30),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          // Warm gold sheen in the top-right corner (selected only).
          foregroundDecoration: selected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: RadialGradient(
                    center: const Alignment(0.95, -0.95),
                    radius: 0.75,
                    colors: [
                      _goldLight.withValues(alpha: 0.16),
                      _goldLight.withValues(alpha: 0.0),
                    ],
                  ),
                )
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                children: [
                  _PlanBadgeV2(label: badge, selected: selected),
                  const Spacer(),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected
                        ? _goldBright
                        : _champagne.withValues(alpha: 0.45),
                    size: 26,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                name,
                style: const TextStyle(
                  color: _champagne,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(height: 10),
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: price,
                    style: TextStyle(
                      color: selected ? _goldBright : _champagne,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                      letterSpacing: -0.6,
                    ),
                  ),
                  TextSpan(
                    text: '\n$period',
                    style: const TextStyle(
                      color: _planMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.5,
                    ),
                  ),
                ]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Divider(
                color: _goldBright.withValues(alpha: selected ? 0.24 : 0.14),
                height: 1,
              ),
              const SizedBox(height: 14),
              // Spaces language — what the plan lets you design. No "credits"
              // / "generations" / "Save 65%".
              Text(
                included,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  color: selected ? _goldBright : _champagne,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  height: 1.12,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(
                  color: _planMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  height: 1.18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pill badge for the plan cards — gold on a translucent gold fill, brighter
/// when its card is selected.
class _PlanBadgeV2 extends StatelessWidget {
  final String label;
  final bool selected;
  const _PlanBadgeV2({required this.label, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _goldBright.withValues(alpha: selected ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: _goldBright.withValues(alpha: selected ? 0.55 : 0.30)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: _goldBright.withValues(alpha: selected ? 1.0 : 0.82),
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _PaywallErrorBox extends StatelessWidget {
  final String message;
  const _PaywallErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF3A1F1F),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Color(0xFFE8A8A8), fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }
}
