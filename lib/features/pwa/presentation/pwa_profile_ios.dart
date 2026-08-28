/// Phase 8 — Profile.
///
/// iOS's Profile, built from what the WEB actually has.
///
/// The visual grammar is iOS's, measured rather than approximated:
/// `headlineLarge` title, a 64pt identity row, `_SettingsCard` (surface, 16
/// radius, hairline border, `ListTile` rows with a 54 indent divider), and the
/// `settingsAccount` / `settingsSupport` section headers at 12/w600/+1.
///
/// WHAT IS DELIBERATELY NOT HERE
///
/// iOS's Profile is half a native surface. Restore Purchases, the Premium
/// Center, App Store subscription state, push-notification toggles and Rate the
/// App are Apple and RevenueCat, and the brief is explicit: do not fake parity.
/// Edit Profile is not here either — the first/last-name store it writes is
/// mobile's `ProfileService`, and a field that saves nowhere is worse than no
/// field. The build marker is not here because `kBuildTag` identifies a MOBILE
/// build and would be a lie on the web.
///
/// What is left is small, and every row of it goes somewhere that already
/// existed: the account sheet, the paywall, the locale notifier, the hero
/// cinematic. This screen adds no capability. It is a place to reach them.
library;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/providers/locale_provider.dart';
import '../application/pwa_controller.dart';
import '../application/pwa_layout.dart';
import '../auth/pwa_auth_controller.dart';
import '../auth/pwa_auth_service.dart';
import '../billing/pwa_entitlement.dart';
import '../billing/pwa_entitlement_controller.dart';
import '../l10n/pwa_l10n.dart';
import 'hero/pwa_hero_sequence.dart';
import 'hero/pwa_hero_video.dart';
import 'pwa_account_sheet.dart';
import 'pwa_nav_shell.dart';
import 'pwa_paywall.dart';
import 'pwa_primitives.dart';
import 'pwa_scaffold.dart';
import 'pwa_theme.dart';
import 'pwa_type.dart';

/// iOS `AppSpacing.cardRadius`.
const double kPwaProfileCardRadius = 16;

/// The identity avatar. iOS: 64, circle, accentLight ground, accentDark letter.
const double kPwaProfileAvatar = 64;

class PwaProfileIos extends ConsumerWidget {
  const PwaProfileIos({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.pwaL10n;
    final controller = ref.read(pwaControllerProvider.notifier);
    final auth = ref.watch(pwaAuthProvider);
    final authController = ref.read(pwaAuthProvider.notifier);
    // Whether an identity can be attached AT ALL is the service's answer, not
    // this screen's. In mock builds there is no verification channel, and a
    // "Save your work" button that cannot send a code would be a lie.
    final canVerify = authController.isAvailable;
    final identified = canVerify && auth.stage == PwaAuthStage.identified;

    final columnWidth = pwaProfileColumnWidth(MediaQuery.sizeOf(context).width);

    return PwaNavShell(
      key: const ValueKey('pwa-profile'),
      current: PwaNavDestination.profile,
      onSelect: (d) {
        switch (d) {
          case PwaNavDestination.home:
            controller.openHome();
          case PwaNavDestination.projects:
            controller.openLibrary();
          case PwaNavDestination.profile:
            break; // already here
        }
      },
      child: PwaScreen(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: columnWidth),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  PwaGap.page, PwaGap.lg, PwaGap.page, PwaGap.xl),
              children: [
                Text(l.shared.profileTitle, style: PwaType.screenTitle()),
                const SizedBox(height: PwaGap.lg),
                _IdentityCard(
                  identified: identified,
                  email: auth.email,
                  canVerify: canVerify,
                ),
                if (canVerify && !identified) ...[
                  const SizedBox(height: PwaGap.md),
                  PwaPrimaryButton(
                    key: const ValueKey('pwa-profile-save-work'),
                    label: l.accountTitle,
                    onPressed: () async {
                      final ok = await showPwaAccountSheet(context);
                      if (ok) {
                        // A new identity is a different entitlement. Ask again;
                        // never carry the old answer forward. (Same call the
                        // account chip makes — one behaviour, two entries.)
                        await ref
                            .read(pwaEntitlementProvider.notifier)
                            .onIdentityChanged();
                      }
                    },
                  ),
                ],
                const SizedBox(height: PwaGap.lg),
                const _WalletRow(),
                const SizedBox(height: PwaGap.lg),
                _SectionHeader(label: l.shared.settingsAccount),
                const SizedBox(height: PwaGap.sm),
                _SettingsCard(
                  items: [
                    _SettingItem(
                      itemKey: const ValueKey('pwa-profile-language'),
                      icon: Icons.language,
                      label: l.shared.settingsLanguage,
                      value: pwaLanguageEndonym(
                          ref.watch(localeProvider).languageCode),
                      onTap: () => _showLanguageSheet(context, ref),
                    ),
                  ],
                ),
                const SizedBox(height: PwaGap.lg),
                _SectionHeader(label: l.shared.settingsSupport),
                const SizedBox(height: PwaGap.sm),
                _SettingsCard(
                  items: [
                    _SettingItem(
                      itemKey: const ValueKey('pwa-profile-guide'),
                      icon: Icons.play_circle_outline,
                      label: l.seeHowItWorks,
                      onTap: () => showPwaGuide(context),
                    ),
                  ],
                ),
                if (identified) ...[
                  const SizedBox(height: PwaGap.lg),
                  _SettingsCard(
                    items: [
                      _SettingItem(
                        itemKey: const ValueKey('pwa-profile-signout'),
                        icon: Icons.logout,
                        label: l.accountSignOut,
                        destructive: true,
                        onTap: () async {
                          await authController.signOut();
                          await ref
                              .read(pwaEntitlementProvider.notifier)
                              .onIdentityChanged();
                        },
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The same ceiling the rest of the web app uses. Profile is a column of rows;
/// letting it run to the edges of a monitor would turn it into the account
/// dashboard the brief rules out.
double pwaProfileColumnWidth(double screenWidth) {
  final ceiling = pwaMaxContentWidth(pwaFormFactorForWidth(screenWidth));
  // Rows read badly when they are wider than a paragraph. Projects widens
  // because MORE WORK fits; a settings list gains nothing from the space.
  const rowCeiling = 640.0;
  final bounded = ceiling < screenWidth ? ceiling : screenWidth;
  return bounded < rowCeiling ? bounded : rowCeiling;
}

/// Who the person is, stated truthfully.
///
/// The web has exactly two states and they are not the mobile ones. A Guest is
/// a real, working user with real projects — not a locked-out visitor — so the
/// card says where the work lives rather than warning anybody. An identified
/// person gets the address they verified, and nothing else: the user id is an
/// internal identifier and is never printed.
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.identified,
    required this.email,
    required this.canVerify,
  });

  final bool identified;
  final String email;
  final bool canVerify;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    final title = identified ? l.accountLinkedTitle : l.accountGuestLabel;
    // A Guest is told how to keep their work ONLY where they can actually do
    // it. In a build with no verification channel there is no email to add, so
    // the card says who you are and promises nothing — rather than offering a
    // step that leads to a button that is not there.
    final body = identified
        ? (email.isNotEmpty ? email : l.accountLinkedBody)
        : (canVerify ? l.accountBody : '');
    final initial = identified && email.isNotEmpty
        ? email.characters.first.toUpperCase()
        : null;

    return Container(
      key: const ValueKey('pwa-profile-identity'),
      padding: const EdgeInsets.all(PwaGap.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(kPwaProfileCardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: kPwaProfileAvatar,
            height: kPwaProfileAvatar,
            decoration: BoxDecoration(
              color: identified ? AppColors.accentLight : pwaWell,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: initial != null
                  ? Text(
                      initial,
                      style: PwaType.screenTitle(color: AppColors.accentDark)
                          .copyWith(fontSize: 28),
                    )
                  : const Icon(Icons.person_outline,
                      size: 30, color: AppColors.textTertiary),
            ),
          ),
          const SizedBox(width: PwaGap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: PwaType.subsectionTitle()),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(body, style: PwaType.bodyMuted()),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What the wallet row says, for a given answer from the server.
///
/// Keyed on the STATE, which is the backend's own discriminator — the same
/// shape iOS's status card takes off `access_source`. Reading the counters
/// instead is how the first cut of this row told a free Guest they held
/// "1 Spaces restants": true arithmetic, wrong sentence, and a Space is a paid
/// thing. Every sentence here already existed; none is composed locally.
///
/// A `switch` rather than an if-chain so a new billing state is a compile error
/// rather than a blank line in front of a paying customer.
String pwaWalletSentence(PwaL10n l, PwaEntitlement e) => switch (e.state) {
      PwaBillingState.loading => '',
      PwaBillingState.freeAvailable => l.freeVisionAvailable,
      PwaBillingState.freeExhausted => l.billingFreeExhausted,
      PwaBillingState.passActive => l.passSpacesLeft(e.creditsAvailable),
      PwaBillingState.passExhausted => l.billingPassExhausted,
      PwaBillingState.passRequired => l.billingPassRequired,
      PwaBillingState.entitled => l.paywallActiveTitle,
      PwaBillingState.billingError => l.billingUnavailable,
    };

/// The wallet, as the SERVER sees it.
///
/// Every number here comes from `pwaEntitlementProvider`, which is the
/// frontend's copy of the backend's answer. Nothing is added up locally, and
/// while the answer is still `loading` the row renders nothing at all rather
/// than a reassuring zero — the same rule iOS's status card follows.
///
/// Tapping it opens the paywall that already exists. It does not redesign it,
/// price anything, or decide what may be bought.
class _WalletRow extends ConsumerWidget {
  const _WalletRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.pwaL10n;
    final e = ref.watch(pwaEntitlementProvider);
    if (!e.isKnown) return const SizedBox.shrink();

    final value = pwaWalletSentence(l, e);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(kPwaProfileCardRadius),
      child: InkWell(
        key: const ValueKey('pwa-profile-wallet'),
        borderRadius: BorderRadius.circular(kPwaProfileCardRadius),
        onTap: () => showPwaPaywall(context, ref),
        child: Container(
          padding: const EdgeInsets.all(PwaGap.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kPwaProfileCardRadius),
            border: Border.all(
              color: e.requiresPurchase
                  ? AppColors.border
                  : pwaGold.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: pwaGold.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome_outlined,
                    color: pwaGold, size: 20),
              ),
              const SizedBox(width: PwaGap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.yourSpaces, style: pwaEyebrow()),
                    const SizedBox(height: 3),
                    Text(value, style: PwaType.subsectionTitle()),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppColors.textTertiary, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// ── iOS's settings furniture ────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: PwaType.caption().copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      );
}

class _SettingItem {
  const _SettingItem({
    required this.itemKey,
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
    this.destructive = false,
  });

  final Key itemKey;
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback onTap;
  final bool destructive;
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.items});
  final List<_SettingItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(kPwaProfileCardRadius),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            ListTile(
              key: items[i].itemKey,
              leading: Icon(
                items[i].icon,
                size: 22,
                color: items[i].destructive
                    ? AppColors.error
                    : AppColors.textSecondary,
              ),
              title: Text(
                items[i].label,
                style: PwaType.body(
                  color: items[i].destructive
                      ? AppColors.error
                      : AppColors.textPrimary,
                ),
              ),
              trailing: items[i].destructive
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (items[i].value != null)
                          Text(items[i].value!, style: PwaType.bodyMuted()),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right,
                            color: AppColors.textTertiary, size: 20),
                      ],
                    ),
              onTap: items[i].onTap,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            ),
            if (i < items.length - 1)
              const Divider(height: 1, indent: 54, color: AppColors.border),
          ],
        ],
      ),
    );
  }
}

// ── Language ────────────────────────────────────────────────────────────────

/// iOS's `_LanguageSelectorSheet`, on the web's locale notifier.
///
/// It writes through [LocaleNotifier] — the same `ui_locale` preference the
/// top-bar switcher and the mobile app write. There is one language setting in
/// this product and this is a second door to it, not a second store.
Future<void> _showLanguageSheet(BuildContext context, WidgetRef ref) {
  final l = context.pwaL10n;
  final current = ref.read(localeProvider);
  return showModalBottomSheet<void>(
    context: context,
    // The sheet takes its own height instead of the default 9/16 cap. Three
    // rows fit either way today; a fourth language, or a short viewport, would
    // not — and the row that falls off the bottom of an uncapped list is the
    // last one, which in this order is French.
    //
    // (This was first written as a fix for a clipped sheet seen in the staging
    // browser. That turned out to be the capture harness: an occluded tab
    // freezes the frame ticker, so the sheet was photographed mid-slide. The
    // flag is kept on its own merits and the harness is fixed in cdp.mjs.)
    isScrollControlled: true,
    backgroundColor: pwaSurface,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(PwaGap.lg),
        child: Column(
          key: const ValueKey('pwa-profile-language-sheet'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: PwaGap.lg),
            Text(l.shared.chooseLanguage, style: PwaType.subsectionTitle()),
            const SizedBox(height: PwaGap.sm),
            // Each language written IN that language — a menu that says
            // "Khmer" in English is unreadable to the person who needs it.
            for (final code in const ['km', 'en', 'fr'])
              ListTile(
                key: ValueKey('pwa-profile-lang-$code'),
                title: Text(pwaLanguageEndonym(code), style: PwaType.body()),
                trailing: current.languageCode == code
                    ? const Icon(Icons.check_rounded, color: pwaGold)
                    : null,
                onTap: () {
                  ref.read(localeProvider.notifier).setLocale(Locale(code));
                  Navigator.of(sheetContext).pop();
                },
              ),
          ],
        ),
      ),
    ),
  );
}

// ── The guide ───────────────────────────────────────────────────────────────

/// "See how it works" — replay the cinematic the product already owns.
///
/// This is the explainer the PWA has: [PwaHeroSequence], the empty room
/// becoming a Warm Modern interior, with the hero's own approved copy. It was
/// retired from Home when the Featured Vision took the hero slot (Phase 2) and
/// kept for exactly this. Nothing new is written, no onboarding funnel is
/// started, and it can be replayed as often as anyone likes.
///
/// iOS's own onboarding screen is deliberately NOT reused: it drives
/// `context.go('/home')` into the MOBILE router, which does not exist in the
/// mock target and means something else entirely in the web app.
Future<void> showPwaGuide(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: pwaSurface,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _PwaGuideSheet(),
    );

class _PwaGuideSheet extends StatefulWidget {
  const _PwaGuideSheet();

  @override
  State<_PwaGuideSheet> createState() => _PwaGuideSheetState();
}

class _PwaGuideSheetState extends State<_PwaGuideSheet> {
  PwaHeroSequence? _seq;
  PwaHeroMedia _media = kHeroMediaDesktop;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seq != null) return;
    final mq = MediaQuery.of(context);
    _media = pwaHeroMediaFor(mq.size.width < 700);
    // Reduced motion, no video support, an error or a slow file all resolve to
    // the finished frame. The sheet never spins and never blocks.
    final useVideo =
        pwaHeroUseVideo(isWeb: kIsWeb, reduceMotion: mq.disableAnimations);
    _seq = PwaHeroSequence(
      useVideo: useVideo,
      createVideo: ({required onReady, required onEnded, required onError}) =>
          createPwaHeroVideo(
        mp4: _media.mp4,
        webm: _media.webm,
        poster: _media.startPoster,
        objectPosition: _media.videoObjectPosition,
        onReady: onReady,
        onEnded: onEnded,
        onError: onError,
      ),
    );
  }

  @override
  void dispose() {
    _seq?.dispose();
    super.dispose();
  }

  void _replay() {
    final old = _seq;
    setState(() {
      _seq = PwaHeroSequence(
        useVideo: pwaHeroUseVideo(
          isWeb: kIsWeb,
          reduceMotion: MediaQuery.of(context).disableAnimations,
        ),
        createVideo: ({required onReady, required onEnded, required onError}) =>
            createPwaHeroVideo(
          mp4: _media.mp4,
          webm: _media.webm,
          poster: _media.startPoster,
          objectPosition: _media.videoObjectPosition,
          onReady: onReady,
          onEnded: onEnded,
          onError: onError,
        ),
      );
    });
    old?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    final seq = _seq!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(PwaGap.lg),
        child: AnimatedBuilder(
          animation: seq,
          builder: (context, _) {
            final supported = seq.video?.isSupported ?? false;
            final showVideo =
                seq.phase == PwaHeroPhase.transform && supported;
            final poster = seq.phase == PwaHeroPhase.promise
                ? _media.endPoster
                : _media.startPoster;
            return Column(
              key: const ValueKey('pwa-guide-sheet'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(PwaGap.radiusLg),
                  child: AspectRatio(
                    aspectRatio: 3 / 2,
                    child: ColoredBox(
                      color: pwaCharcoal,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            poster,
                            fit: BoxFit.cover,
                            alignment: _media.posterAlignment,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) =>
                                const ColoredBox(color: pwaCharcoal),
                          ),
                          if (supported)
                            AnimatedOpacity(
                              opacity: showVideo ? 1 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: seq.video!.buildView(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: PwaGap.md),
                Text(l.heroSub, style: PwaType.bodyMuted()),
                const SizedBox(height: PwaGap.md),
                PwaSecondaryButton(
                  key: const ValueKey('pwa-guide-replay'),
                  label: l.seeHowItWorks,
                  onPressed: _replay,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
