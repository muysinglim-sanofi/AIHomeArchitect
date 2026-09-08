// Round 4 — the Profile, complete, against the frozen iOS Profile.
//
// Read from `features/profile/profile_screen.dart`: title, identity header,
// one stat card (redesigns), access card, ACCOUNT (language…), SUPPORT (Help
// Center · Rate · About), Privacy, sign out, build tag. The web keeps what has
// a real web meaning and a real destination:
//
//   IMPLEMENTED  stat card · Help Center (FAQ + support page) · Privacy
//                (the published policy) · About
//   ADAPTED      identity (guest / e-mail) · access = the authoritative wallet
//                + "Get more Spaces" · sign out only when signed in
//   OMITTED      Edit Profile (device-local name store) · Notifications (native
//                push) · Rate the App (App Store) · Restore / subscription
//                (RevenueCat) · admin · build tag · Terms (no web page exists)
//
// These tests pin the guest and signed-in shapes, every row's destination, the
// three languages, and that every sub-flow returns to the Profile it left.

import 'dart:typed_data';

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/core/providers/locale_provider.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_auth_controller.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_auth_service.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_verification_channel.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_entitlement.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_entitlement_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_l10n.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_experience.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_external_links.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_paywall.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_profile_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── identity rig (same shape as pwa_profile_parity_test.dart) ────────────────

class _FakeAuth implements GoTrueSlice {
  String _id = 'guest-uid';
  String _email = '';
  bool _anon = true;
  bool _session = true;
  int signOuts = 0;

  @override
  String? get currentUserId => _session ? _id : null;
  @override
  String get currentEmail => _email;
  @override
  bool get isAnonymous => _anon;
  @override
  bool get hasCurrentSession => _session;
  @override
  Future<void> signInAnonymously() async {
    _id = 'guest-uid-2';
    _email = '';
    _anon = true;
    _session = true;
  }

  @override
  Future<void> signOutLocal() async {
    signOuts++;
    _session = false;
  }
}

class _FakeChannel implements PwaVerificationChannel {
  _FakeChannel({this.onVerified});
  final void Function()? onVerified;
  @override
  PwaVerificationKind get kind => PwaVerificationKind.email;
  @override
  bool get isConfigured => true;
  @override
  bool looksValid(String d) => d.contains('@');
  @override
  Future<PwaVerificationResult> send(String d) async =>
      const PwaVerificationResult.ok();
  @override
  Future<PwaVerificationResult> verify(String d, String code) async {
    onVerified?.call();
    return const PwaVerificationResult.ok();
  }

  @override
  Future<PwaVerificationResult> resend(String d) async =>
      const PwaVerificationResult.ok();
}

class _Identity {
  _Identity() {
    link = _FakeChannel(onVerified: () {
      auth._email = _pending;
      auth._anon = false;
    });
    service = PwaAuthService.forTest(auth, link, _FakeChannel());
  }
  final auth = _FakeAuth();
  late final _FakeChannel link;
  late final PwaAuthService service;
  String _pending = '';

  Future<void> identify(ProviderContainer c, String email) async {
    _pending = email;
    final n = c.read(pwaAuthProvider.notifier);
    await n.beginLink(email);
    await n.submitCode(email, '123456');
  }
}

class _FrozenEntitlement extends PwaEntitlementController {
  _FrozenEntitlement(PwaEntitlement value) : super(null) {
    state = value;
  }
  @override
  Future<void> refresh() async {}
  @override
  Future<void> onIdentityChanged() async {}
}

const _holder = PwaEntitlement(
  state: PwaBillingState.freeAvailable,
  canGenerate: true,
  freeCredits: 300,
  creditsAvailable: 300,
  paymentProvider: 'khqr',
  paymentConfigured: true,
  products: [
    PwaProduct(
      sku: 'pack_10',
      type: 'CREDIT_PACK',
      credits: 10,
      priceUsd: 1.99,
      currency: 'USD',
      storeOnly: false,
      webEnabled: true,
    ),
  ],
);

/// Every link the Profile opens lands here instead of in a browser tab.
class _Links {
  final opened = <Uri>[];
  Future<bool> open(Uri url) async {
    opened.add(url);
    return true;
  }
}

ProviderContainer _container({
  _Identity? identity,
  PwaEntitlement entitlement = _holder,
  _Links? links,
}) =>
    ProviderContainer(overrides: [
      pwaRepositoryProvider.overrideWithValue(
        MockPwaExperienceRepository(workDelay: Duration.zero),
      ),
      if (identity != null)
        pwaAuthServiceProvider.overrideWithValue(identity.service),
      pwaEntitlementProvider
          .overrideWith((ref) => _FrozenEntitlement(entitlement)),
      if (links != null) pwaLinkOpenerProvider.overrideWithValue(links.open),
    ]);

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer c, {
  Size size = const Size(390, 844),
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  c.read(pwaControllerProvider.notifier).openProfile();
  c.read(localeProvider.notifier).setLocale(locale);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          locale: ref.watch(localeProvider),
          supportedLocales: PwaL10n.supportedLocales,
          localizationsDelegates: const [
            PwaL10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const PwaExperience(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// A ListView builds what is on screen; bring [key] into it first.
Future<Finder> _row(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.scrollUntilVisible(f, 160,
      scrollable: find.byType(Scrollable).first);
  await tester.pump();
  return f;
}

Future<void> _closeSheet(WidgetTester tester) async {
  // Back — the system gesture / browser back a person uses to leave a sheet.
  // A tall sheet covers the barrier, so this is the honest way to dismiss.
  final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
  nav.pop();
  await tester.pumpAndSettle();
}

String _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => (t.data ?? '').toLowerCase())
    .join(' | ');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PROF10  the guest Profile', () {
    testWidgets('identity, Save my designs, Sign in, Spaces, rows — no Sign out',
        (tester) async {
      final c = _container(identity: _Identity());
      addTearDown(c.dispose);
      await _pump(tester, c);
      final l = pwaL10nFor(const Locale('en'));

      expect(find.text(l.accountGuestLabel), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-profile-save-work')), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-profile-sign-in')), findsOneWidget);
      expect(find.text(l.authSecureCta), findsOneWidget); // Secure my account
      expect(find.text(l.accountSignInTitle), findsOneWidget); // Sign in
      // Spaces: the server's figure, and the voluntary door to more.
      expect(find.text(l.passSpacesLeft(300)), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-profile-get-spaces')), findsOneWidget);
      // The stat card counts what Projects lists.
      final n = c.read(pwaControllerProvider).visibleProjects.length;
      expect(find.byKey(const ValueKey('pwa-profile-stats')), findsOneWidget);
      expect(
        find.descendant(
            of: find.byKey(const ValueKey('pwa-profile-stats')),
            matching: find.text('$n')),
        findsOneWidget,
      );
      for (final k in [
        'pwa-profile-language',
        'pwa-profile-guide',
        'pwa-profile-help',
        'pwa-profile-privacy',
        'pwa-profile-about',
      ]) {
        expect(await _row(tester, k), findsOneWidget, reason: k);
      }
      expect(find.byKey(const ValueKey('pwa-profile-signout')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('nothing native leaks: no Rate, Restore, Notifications, '
        'App Store, Edit Profile, build tag', (tester) async {
      final c = _container(identity: _Identity());
      addTearDown(c.dispose);
      await _pump(tester, c);
      await _row(tester, 'pwa-profile-about');
      final texts = _allText(tester);
      for (final banned in const [
        'rate ', 'restore', 'notification', 'app store', 'apple',
        'subscription', 'edit profile', 'pr2b', 'admin', 'terms',
      ]) {
        expect(texts, isNot(contains(banned)), reason: banned);
      }
    });
  });

  group('PROF11  the signed-in Profile', () {
    testWidgets('e-mail, Spaces, Get more Spaces, rows, Sign out — no guest CTA',
        (tester) async {
      final id = _Identity();
      final c = _container(identity: id);
      addTearDown(c.dispose);
      await id.identify(c, 'someone@example.com');
      await _pump(tester, c);
      final l = pwaL10nFor(const Locale('en'));

      // The card is titled by the account's own label (the address) and says
      // HOW it is connected; "Your work is saved" is the sheet's line, not
      // the profile's, since Cambodia auth.
      expect(find.text('someone@example.com'), findsOneWidget);
      expect(find.text(l.authConnectedEmail), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-profile-methods')), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-profile-save-work')), findsNothing);
      expect(find.byKey(const ValueKey('pwa-profile-sign-in')), findsNothing);
      expect(find.text(l.passSpacesLeft(300)), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-profile-get-spaces')), findsOneWidget);
      for (final k in [
        'pwa-profile-language', 'pwa-profile-guide', 'pwa-profile-help',
        'pwa-profile-privacy', 'pwa-profile-about', 'pwa-profile-signout',
      ]) {
        expect(await _row(tester, k), findsOneWidget, reason: k);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('Sign out is real: the session is dropped and the Profile '
        'reads as a guest again', (tester) async {
      final id = _Identity();
      final c = _container(identity: id);
      addTearDown(c.dispose);
      await id.identify(c, 'someone@example.com');
      await _pump(tester, c);
      await tester.tap(await _row(tester, 'pwa-profile-signout'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(id.auth.signOuts, 1);
      expect(c.read(pwaAuthProvider).stage, isNot(PwaAuthStage.identified));
      // Sign-out is a change of user: the app returns Home; the Profile, when
      // reopened, is the guest one.
      c.read(pwaControllerProvider.notifier).openProfile();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('pwa-profile-save-work')), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-profile-signout')), findsNothing);
    });
  });

  group('PROF12  every row goes somewhere real, and comes back', () {
    testWidgets('Help Center: iOS\'s FAQ, a support address, and the published '
        'support page — then back to the Profile', (tester) async {
      final links = _Links();
      final c = _container(identity: _Identity(), links: links);
      addTearDown(c.dispose);
      await _pump(tester, c);
      final s = pwaL10nFor(const Locale('en')).shared;

      await tester.tap(await _row(tester, 'pwa-profile-help'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pwa-profile-help-sheet')), findsOneWidget);
      expect(find.text(s.helpCenter), findsWidgets);
      expect(find.text(s.spFaq1Q), findsOneWidget);
      expect(find.text(s.spFaq1A), findsNothing, reason: 'collapsed');
      await tester.tap(find.byKey(const ValueKey('pwa-faq-0')));
      await tester.pumpAndSettle();
      expect(find.text(s.spFaq1A), findsOneWidget, reason: 'expanded');
      expect(find.text(kPwaSupportEmail), findsOneWidget);

      final contact = find.byKey(const ValueKey('pwa-profile-contact-support'));
      // The button is at the foot of a scrolling sheet on a phone.
      await tester.scrollUntilVisible(contact, 120,
          scrollable: find.byType(Scrollable).last);
      await tester.pump();
      await tester.tap(contact);
      await tester.pump();
      expect(links.opened, [kPwaSupportUrl]);
      // Opening a page in a new tab changes nothing here.
      expect(find.byKey(const ValueKey('pwa-profile-help-sheet')), findsOneWidget);
      expect(c.read(pwaControllerProvider).phase, PwaPhase.profile);

      await _closeSheet(tester);
      expect(find.byKey(const ValueKey('pwa-profile-help-sheet')), findsNothing);
      expect(find.byKey(const ValueKey('pwa-profile')), findsOneWidget);
      expect(c.read(pwaControllerProvider).phase, PwaPhase.profile);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Privacy opens the published policy in a new tab; the Profile '
        'stays', (tester) async {
      final links = _Links();
      final c = _container(identity: _Identity(), links: links);
      addTearDown(c.dispose);
      await _pump(tester, c);
      await tester.tap(await _row(tester, 'pwa-profile-privacy'));
      await tester.pump();
      expect(links.opened, [kPwaPrivacyUrl]);
      expect(kPwaPrivacyUrl.toString(), 'https://aydenstudio.com/privacy');
      expect(find.byKey(const ValueKey('pwa-profile')), findsOneWidget);
      expect(c.read(pwaControllerProvider).phase, PwaPhase.profile);
    });

    testWidgets('About: name, version line, tagline, copyright — then back',
        (tester) async {
      final c = _container(identity: _Identity());
      addTearDown(c.dispose);
      await _pump(tester, c);
      final l = pwaL10nFor(const Locale('en'));
      final s = l.shared;
      await tester.tap(await _row(tester, 'pwa-profile-about'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pwa-profile-about-sheet')), findsOneWidget);
      expect(find.text(s.appName), findsWidgets);
      expect(find.text(l.aboutVersion), findsOneWidget);
      expect(l.aboutVersion, 'Version 1.0');
      expect(find.textContaining('MVP'), findsNothing);
      expect(find.text(s.spAboutTagline), findsOneWidget);
      expect(find.text(s.spCopyright), findsOneWidget);
      await _closeSheet(tester);
      expect(find.byKey(const ValueKey('pwa-profile-about-sheet')), findsNothing);
      expect(find.byKey(const ValueKey('pwa-profile')), findsOneWidget);
    });

    testWidgets('Language: the sheet opens and returns; the row shows the '
        'current language', (tester) async {
      final c = _container(identity: _Identity());
      addTearDown(c.dispose);
      await _pump(tester, c);
      await tester.tap(await _row(tester, 'pwa-profile-language'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pwa-profile-language-sheet')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pwa-profile-lang-fr')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pwa-profile-language-sheet')), findsNothing);
      expect(c.read(localeProvider).languageCode, 'fr');
      expect(find.text(pwaLanguageFlagLabel('fr')), findsOneWidget);
      expect(pwaLanguageFlagLabel('fr'), '🇫🇷 Français');
      expect(find.byKey(const ValueKey('pwa-profile')), findsOneWidget);
    });

    testWidgets('Get more Spaces with 300 Spaces opens the catalogue; gating '
        'is untouched', (tester) async {
      final c = _container(identity: _Identity());
      addTearDown(c.dispose);
      await _pump(tester, c);
      expect(c.read(pwaEntitlementProvider).requiresPurchase, isFalse);
      expect(c.read(pwaEntitlementProvider).canGenerate, isTrue);
      await tester.tap(find.byKey(const ValueKey('pwa-profile-get-spaces')));
      await tester.pumpAndSettle();
      expect(find.byType(PwaPaywallSheet), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-pack-pack_10')), findsOneWidget);
      await _closeSheet(tester);
      expect(find.byType(PwaPaywallSheet), findsNothing);
      expect(find.byKey(const ValueKey('pwa-profile')), findsOneWidget);
      expect(c.read(pwaControllerProvider).phase, PwaPhase.profile);
    });
  });

  group('PROF13  three languages, no English fallback', () {
    for (final code in ['en', 'fr', 'km']) {
      testWidgets('rows and sheets read in $code', (tester) async {
        final c = _container(identity: _Identity());
        addTearDown(c.dispose);
        await _pump(tester, c, locale: Locale(code));
        final l = pwaL10nFor(Locale(code));
        final s = l.shared;
        final en = pwaL10nFor(const Locale('en'));
        await _row(tester, 'pwa-profile-about');
        expect(find.text(s.helpCenter), findsOneWidget);
        expect(find.text(s.privacy), findsOneWidget);
        expect(find.text(s.about), findsOneWidget);
        expect(find.text(s.projectsCount), findsOneWidget);
        if (code != 'en') {
          expect(l.contactSupport, isNot(en.contactSupport), reason: code);
          expect(s.helpCenter, isNot(en.shared.helpCenter), reason: code);
        }
        await tester.tap(find.byKey(const ValueKey('pwa-profile-help')));
        await tester.pumpAndSettle();
        expect(find.text(l.contactSupport), findsOneWidget);
        expect(find.text(s.spFaq1Q), findsOneWidget);
        await _closeSheet(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('PROF15  the language sheet carries flags, and nothing moves', () {
    for (final code in ['en', 'fr', 'km']) {
      testWidgets('in $code: the row shows the active flag + name; the sheet '
          'shows all three flags and the check, aligned', (tester) async {
        final c = _container(identity: _Identity());
        addTearDown(c.dispose);
        await _pump(tester, c, locale: Locale(code));
        // Profile row: globe on the left (unchanged), flag + short name on the
        // right.
        expect(find.text(pwaLanguageFlagLabel(code)), findsOneWidget);
        expect(
          find.descendant(
              of: find.byKey(const ValueKey('pwa-profile-language')),
              matching: find.byIcon(Icons.language)),
          findsOneWidget,
        );
        await tester.tap(await _row(tester, 'pwa-profile-language'));
        await tester.pumpAndSettle();
        final rects = <String, Rect>{};
        for (final k in ['km', 'en', 'fr']) {
          expect(find.byKey(ValueKey('pwa-profile-lang-flag-$k')), findsOneWidget);
          expect(find.text(pwaLanguageShortName(k)), findsOneWidget);
          rects[k] = tester.getRect(find.byKey(ValueKey('pwa-profile-lang-$k')));
        }
        // Same height whether or not a row carries the check.
        expect(rects['km']!.height, closeTo(rects['en']!.height, 0.5));
        expect(rects['en']!.height, closeTo(rects['fr']!.height, 0.5));
        // Flags line up: the same left edge for all three.
        final lefts = ['km', 'en', 'fr']
            .map((k) => tester
                .getTopLeft(find.byKey(ValueKey('pwa-profile-lang-flag-$k')))
                .dx)
            .toList();
        expect(lefts[0], closeTo(lefts[1], 0.5));
        expect(lefts[1], closeTo(lefts[2], 0.5));
        // Exactly one check, on the active language.
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        final check = tester.getRect(find.byIcon(Icons.check_rounded));
        expect(rects[code]!.contains(check.center), isTrue);
        await _closeSheet(tester);
        expect(tester.takeException(), isNull);
      });
    }

    test('the labels match the brief', () {
      expect(pwaLanguageFlagLabel('km'), '🇰🇭 ខ្មែរ');
      expect(pwaLanguageFlagLabel('en'), '🇬🇧 English');
      expect(pwaLanguageFlagLabel('fr'), '🇫🇷 Français');
    });
  });

  group('PROF14  it holds together', () {
    for (final size in const [
      Size(390, 844),
      Size(430, 932),
      Size(768, 1024),
      Size(1440, 900),
    ]) {
      testWidgets('guest and signed-in, no overflow at '
          '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        final id = _Identity();
        final c = _container(identity: id);
        addTearDown(c.dispose);
        await _pump(tester, c, size: size);
        await _row(tester, 'pwa-profile-about');
        expect(tester.takeException(), isNull);
        await tester.tap(await _row(tester, 'pwa-profile-language'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('pwa-profile-lang-flag-km')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _closeSheet(tester);
        await id.identify(c, 'someone@example.com');
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await _row(tester, 'pwa-profile-signout');
        expect(tester.takeException(), isNull);
      });
    }

    test('the stat card and the sheets are plain widgets', () {
      expect(const PwaStatCard(value: '3', label: 'Redesigns'), isA<Widget>());
      expect(const PwaHelpCenterSheet(), isA<Widget>());
      expect(const PwaAboutSheet(), isA<Widget>());
      // Silence the unused-import lint for the source type, and pin the type.
      const AydenImageSource? none = null;
      expect(none, isNull);
      expect(Uint8List(0), isEmpty);
    });
  });
}
