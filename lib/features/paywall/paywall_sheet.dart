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
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/feature_flags.dart';
import '../../data/services/revenuecat_service.dart';
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

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    final offerings = await RevenuecatService.instance.loadOfferings();
    if (!mounted) return;
    setState(() {
      _offering = offerings?.current;
      _loading = false;
    });
  }

  Future<void> _onPurchasePressed(Package pkg) async {
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
          _errorMessage = 'Purchase did not complete. Please try again.';
        });
      }
    } on RevenuecatNotConfiguredException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = 'Purchases are not available in this test build yet.';
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
        setState(() => _busy = false);
        return;
      }
      setState(() {
        _busy = false;
        _errorMessage = e.message ?? 'Purchase failed.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = 'Purchase failed. Please try again.';
      });
    }
  }

  Future<void> _onRestorePressed() async {
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
          _errorMessage = 'No prior purchases found on this device.';
        });
      }
    } on RevenuecatNotConfiguredException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = 'Purchases are not available in this test build yet.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = 'Restore failed. Please try again.';
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
      decoration: const BoxDecoration(
        color: _paywallBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Stack(
          children: [
            _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _gold),
                  )
                : _buildScrollableContent(
                    heroHeight: heroHeight,
                    weekly: weekly,
                    annual: annual,
                  ),
            // Wave 5.17d.2 — explicit dismiss affordance in the top-
            // right. The drag-down gesture is preserved (and the
            // bottom "Not now" button is too), but the explicit X is
            // the universal "close this overlay" cue. Sits above the
            // hero with a soft scrim background so it stays legible
            // over varied artwork.
            Positioned(
              top: 8,
              right: 8,
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
}

// ── Close button (top-right overlay) ────────────────────────────────────────

class _CloseButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Close',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: const Icon(
              Icons.close,
              size: 18,
              color: Colors.white,
            ),
          ),
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
  const _KenBurnsImage({required this.asset});

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
    _scale = Tween<double>(begin: 1.0, end: 1.06).animate(
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
    return AnimatedBuilder(
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
        errorBuilder: (_, _, _) => Container(color: _paywallCardSoft),
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
  final bool enabled;
  final VoidCallback? onTap;

  const _PrimaryPaywallButton({
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.5,
        duration: const Duration(milliseconds: 150),
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
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
            children: const [
              Icon(Icons.shield_outlined, color: _gold, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '7-day satisfaction guarantee',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.only(left: 26),
            child: Text(
              'Not in love? Get a full refund within 7 days.',
              style: TextStyle(color: _textMuted, fontSize: 11),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Secure payments',
            style: TextStyle(
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
            const Text(
              'Already subscribed? ',
              style: TextStyle(color: _textDim, fontSize: 13),
            ),
            TextButton(
              onPressed: busy ? null : onRestore,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: _gold,
              ),
              child: const Text(
                'Restore Purchase',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        AppButton(
          label: 'Not now',
          variant: AppButtonVariant.ghost,
          fullWidth: true,
          onPressed: busy ? null : onDismiss,
        ),
      ],
    );
  }
}
