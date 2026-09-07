/// Phase 8 — Profile.
///
/// The screen is small. What these tests are really holding is the line between
/// what the WEB has and what iOS has, because the failure mode of a parity
/// phase is copying a native control that cannot work here: a Restore Purchases
/// that restores nothing, an Apple button that opens nothing, a subscription
/// status read from a store the browser cannot see.
///
/// So the assertions come in two kinds. The first: every row goes somewhere
/// that already existed — the account sheet, the paywall, the locale notifier.
/// The second, and the one worth having: the native-only controls are ABSENT,
/// stated by name, so re-adding one is a test failure rather than a review
/// comment.
library;

import 'dart:typed_data';

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/core/providers/locale_provider.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_route.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_auth_controller.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_auth_service.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_verification_channel.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_entitlement.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_entitlement_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_persistence_repository.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_l10n.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_experience.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_nav_shell.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_paywall.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_profile_ios.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The identity fakes, modelled on `pwa_auth_paywall_test.dart`'s. They exist
/// so the identified state is REACHED through the real service and controller
/// rather than painted into the widget: what this file is checking is that
/// Profile reads the identity the product already has.
class _FakeAuth implements GoTrueSlice {
  _FakeAuth();

  String _id = 'internal-uid-never-printed';
  String _email = '';
  bool _anon = true;
  bool _session = true;
  int signOuts = 0;

  void becomeIdentified(String email) {
    _email = email;
    _anon = false;
  }

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
    _id = 'internal-uid-never-printed-2';
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
  final calls = <String>[];

  @override
  PwaVerificationKind get kind => PwaVerificationKind.email;

  @override
  bool get isConfigured => true;

  @override
  bool looksValid(String destination) => destination.contains('@');

  @override
  Future<PwaVerificationResult> send(String destination) async {
    calls.add('send:$destination');
    return const PwaVerificationResult.ok();
  }

  @override
  Future<PwaVerificationResult> verify(String destination, String code) async {
    calls.add('verify:$destination');
    onVerified?.call();
    return const PwaVerificationResult.ok();
  }

  @override
  Future<PwaVerificationResult> resend(String destination) async {
    calls.add('resend:$destination');
    return const PwaVerificationResult.ok();
  }
}

/// One identity rig: the session, the transport, and the service over both.
class _Identity {
  _Identity() {
    link = _FakeChannel(onVerified: () => auth.becomeIdentified(_pending));
    service = PwaAuthService.forTest(auth, link, _FakeChannel());
  }

  final auth = _FakeAuth();
  late final _FakeChannel link;
  late final PwaAuthService service;
  String _pending = '';

  /// Walk the REAL journey — begin, then submit the code.
  Future<void> identify(ProviderContainer c, String email) async {
    _pending = email;
    final n = c.read(pwaAuthProvider.notifier);
    await n.beginLink(email);
    await n.submitCode(email, '123456');
  }
}

final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

ProviderContainer _container({
  _Identity? identity,
  PwaEntitlement? entitlement,
}) =>
    ProviderContainer(
      overrides: [
        pwaRepositoryProvider.overrideWithValue(
          MockPwaExperienceRepository(workDelay: Duration.zero),
        ),
        if (identity != null)
          pwaAuthServiceProvider.overrideWithValue(identity.service),
        if (entitlement != null)
          pwaEntitlementProvider.overrideWith(
            (ref) => _FrozenEntitlement(entitlement),
          ),
      ],
    );

/// An entitlement that is simply a value — the row must render the SERVER's
/// answer, so the test hands it one and never lets the widget compute.
class _FrozenEntitlement extends PwaEntitlementController {
  _FrozenEntitlement(PwaEntitlement value) : super(null) {
    state = value;
  }


  @override
  Future<void> refresh() async {}

  @override
  Future<void> onIdentityChanged() async {}
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  Locale locale = const Locale('en'),
  ProviderContainer? container,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final c = container ?? _container();
  if (container == null) addTearDown(c.dispose);
  c.read(pwaControllerProvider.notifier).openProfile();
  c.read(localeProvider.notifier).setLocale(locale);

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: true, size: size),
      child: UncontrolledProviderScope(
        container: c,
        // The app takes its locale FROM the notifier, as the real one does —
        // otherwise the language row could write a preference that changes
        // nothing on screen and the test would still pass.
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
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return c;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PROF01  it is a real destination', () {
    testWidgets('the route exists and is canonical', (tester) async {
      final c = await _pump(tester);
      expect(c.read(pwaControllerProvider).phase, PwaPhase.profile);
      expect(c.read(pwaControllerProvider).canonicalRoute.location, '/profile');
      expect(PwaRoute.parse(Uri.parse('/profile')).page, PwaPage.profile);
    });

    testWidgets('a /profile URL opens it', (tester) async {
      final c = _container();
      addTearDown(c.dispose);
      final n = c.read(pwaControllerProvider.notifier);
      n.applyRoute(PwaRoute.parse(Uri.parse('/profile')));
      expect(c.read(pwaControllerProvider).phase, PwaPhase.profile);
      // Idempotent — re-applying must not rebuild the world.
      n.applyRoute(PwaRoute.profile);
      expect(c.read(pwaControllerProvider).phase, PwaPhase.profile);
    });

    test('a first-time visitor can deep-link straight to it', () async {
      // Found in the staging browser: `/profile` bounced to `/`. The boot
      // resolver forces a project URL back to the Hero when the library is
      // empty, which is right for a project and wrong for Profile — Profile
      // depends on nothing durable, which is what `normalize` already says.
      final restore = await pwaResolveBootRestore(
        MockPwaPersistenceRepository(),
        route: PwaRoute.profile,
      );
      expect(restore.library, isEmpty);
      expect(restore.route?.page, PwaPage.profile);

      // …and a project URL still falls back, because there is no project.
      final fallback = await pwaResolveBootRestore(
        MockPwaPersistenceRepository(),
        route: const PwaRoute(PwaPage.architect, projectId: 'nope'),
      );
      expect(fallback.route?.page, PwaPage.home);
    });

    test('and the first frame is Profile, not the Hero', () async {
      // Resolving the route was only half of it: the initial STATE is built
      // from the restore, and it knew about `/projects` and `/create` but not
      // `/profile` — so the URL was rewritten back to `/` on the first frame
      // by the sync scope, which is what the browser actually showed.
      final restore = await pwaResolveBootRestore(
        MockPwaPersistenceRepository(),
        route: PwaRoute.profile,
      );
      final c = ProviderContainer(overrides: [
        pwaRepositoryProvider.overrideWithValue(
          MockPwaExperienceRepository(workDelay: Duration.zero),
        ),
        pwaBootRestoreProvider.overrideWithValue(restore),
      ]);
      addTearDown(c.dispose);
      expect(c.read(pwaControllerProvider).phase, PwaPhase.profile);
      expect(c.read(pwaControllerProvider).canonicalRoute.location, '/profile');
    });

    testWidgets('the tab is selected, and no longer inert', (tester) async {
      await _pump(tester);
      expect(find.byKey(const ValueKey('pwa-profile')), findsOneWidget);
      expect(find.byType(PwaProfileIos), findsOneWidget);
      final shell = tester.widget<PwaNavShell>(find.byType(PwaNavShell));
      expect(shell.current, PwaNavDestination.profile);
      expect(shell.enabled[PwaNavDestination.profile], isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the shell is the product cream, not a dashboard',
        (tester) async {
      await _pump(tester);
      final scaffold = tester.widget<Scaffold>(
        find
            .descendant(
              of: find.byKey(const ValueKey('pwa-profile')),
              matching: find.byType(Scaffold),
            )
            .first,
      );
      expect(scaffold.backgroundColor, pwaCanvas);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Home and Projects can reach it, and it can reach them',
        (tester) async {
      final c = await _pump(tester);
      final n = c.read(pwaControllerProvider.notifier);
      final shell = tester.widget<PwaNavShell>(find.byType(PwaNavShell));
      shell.onSelect(PwaNavDestination.home);
      await tester.pump();
      // Home mounts a RevealHero, whose 800ms auto-sweep would otherwise be a
      // pending timer at teardown.
      await tester.pump(const Duration(seconds: 1));
      expect(c.read(pwaControllerProvider).phase, PwaPhase.home);
      n.openProfile();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(c.read(pwaControllerProvider).phase, PwaPhase.profile);
      tester
          .widget<PwaNavShell>(find.byType(PwaNavShell))
          .onSelect(PwaNavDestination.projects);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(c.read(pwaControllerProvider).phase, PwaPhase.projects);
    });

    testWidgets('opening it never loses an in-progress project',
        (tester) async {
      final c = _container();
      addTearDown(c.dispose);
      final n = c.read(pwaControllerProvider.notifier);
      n.newProject();
      n.setSource(
        AydenImageSource(bytes: _png, filename: 'r.png', mimeType: 'image/png'),
        origin: PwaImageOrigin.userUpload,
      );
      await n.generateFirstVision();
      final before = c.read(pwaControllerProvider).visibleProjects.length;

      n.openProfile();
      expect(c.read(pwaControllerProvider).phase, PwaPhase.profile);
      expect(c.read(pwaControllerProvider).visibleProjects.length, before);
    });
  });

  group('PROF02  it tells the truth about who you are', () {
    testWidgets('a Guest is called a Guest, and is not implied to have an '
        'account', (tester) async {
      final id = _Identity();
      final c = _container(identity: id);
      addTearDown(c.dispose);
      await _pump(tester, container: c);
      final l = pwaL10nFor(const Locale('en'));

      expect(find.byKey(const ValueKey('pwa-profile-identity')), findsOneWidget);
      expect(find.text(l.accountGuestLabel), findsOneWidget);
      // "Your work is saved" must NOT appear over an anonymous session.
      expect(find.text(l.accountLinkedTitle), findsNothing);
      // Opening Profile must not have created anything.
      expect(id.link.calls, isEmpty);
      expect(c.read(pwaAuthProvider).stage, PwaAuthStage.guest);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a build with no verification channel promises nothing',
        (tester) async {
      // The mock target has no way to send a code. Offering "add an email so
      // your projects follow you" there would describe a step that leads to a
      // button which is not on the screen.
      final c = _container(); // no identity override → no service
      addTearDown(c.dispose);
      await _pump(tester, container: c);
      final l = pwaL10nFor(const Locale('en'));
      expect(find.text(l.accountGuestLabel), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-profile-save-work')), findsNothing);
      expect(find.text(l.accountBody), findsNothing);
      expect(find.text(l.accountLinkedBody), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Save your work opens the EXISTING account sheet',
        (tester) async {
      final id = _Identity();
      final c = _container(identity: id);
      addTearDown(c.dispose);
      await _pump(tester, container: c);

      final btn = find.byKey(const ValueKey('pwa-profile-save-work'));
      expect(btn, findsOneWidget);
      await tester.tap(btn);
      await tester.pumpAndSettle();
      // The sheet's own copy, not a second auth mechanism built here.
      final l = pwaL10nFor(const Locale('en'));
      expect(find.text(l.accountEmailLabel), findsOneWidget);
      expect(find.text(l.accountSend), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a verified person sees the address and the saved state',
        (tester) async {
      final id = _Identity();
      final c = _container(identity: id);
      addTearDown(c.dispose);
      await id.identify(c, 'someone@example.com');
      await _pump(tester, container: c);

      final l = pwaL10nFor(const Locale('en'));
      expect(c.read(pwaAuthProvider).stage, PwaAuthStage.identified);
      expect(find.text(l.accountLinkedTitle), findsOneWidget);
      expect(find.text('someone@example.com'), findsOneWidget);
      expect(find.text(l.accountGuestLabel), findsNothing);
      // Nothing left to save — the CTA is gone.
      expect(find.byKey(const ValueKey('pwa-profile-save-work')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no internal identifier is ever printed', (tester) async {
      final id = _Identity();
      final c = _container(identity: id);
      addTearDown(c.dispose);
      await id.identify(c, 'someone@example.com');
      await _pump(tester, container: c);

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' | ');
      expect(texts, isNot(contains('internal-uid-never-printed')));
      expect(texts, isNot(contains(c.read(pwaAuthProvider).userId)));
    });

    testWidgets('sign-out uses the existing controller path', (tester) async {
      final id = _Identity();
      final c = _container(identity: id);
      addTearDown(c.dispose);
      await id.identify(c, 'someone@example.com');
      await _pump(tester, container: c);
      // The Profile grew (Help Center, Privacy, About): the sign-out card now
      // sits below the fold of a 390x844 window, and a ListView does not build
      // what is off screen.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('pwa-profile-signout')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      final row = find.byKey(const ValueKey('pwa-profile-signout'));
      expect(row, findsOneWidget);
      await tester.tap(row);
      await tester.pumpAndSettle();
      // Signing out is a change of USER, so the session resets to Home — the
      // previous account's open project must not stay on screen. Home's hero
      // arms the shared reveal auto-sweep (a Future.delayed in the FROZEN
      // widget iOS uses too), so the test advances past it rather than the
      // product weakening its own animation for a harness.
      await tester.pump(const Duration(seconds: 1));
      expect(id.auth.signOuts, 1);
      expect(c.read(pwaAuthProvider).stage, PwaAuthStage.guest);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a Guest is offered no sign-out — there is nothing to leave',
        (tester) async {
      final c = _container(identity: _Identity());
      addTearDown(c.dispose);
      await _pump(tester, container: c);
      expect(find.byKey(const ValueKey('pwa-profile-signout')), findsNothing);
    });
  });

  // ── Two intents, two doors ────────────────────────────────────────────────
  //
  // AUTH01-05. "Save your work" is the right sentence for someone who has just
  // made something and has nowhere to keep it. It is the wrong one for someone
  // whose work is already on a server and who is simply on a new browser —
  // and that person could previously only reach the sign-in journey by typing
  // an address into the SAVE screen and being told it was taken.
  //
  // Both journeys already existed in `PwaAuthService`, and they are different
  // operations: linking attaches an address to the current anonymous user and
  // keeps their work; signing in switches to an account that already exists
  // and carries nothing over. Nothing about that separation changed here —
  // only which of them a person can ask for.
  group('AUTH  Save your work vs Sign in', () {
    testWidgets('AUTH01: a Guest is offered BOTH, and the primary is Save',
        (tester) async {
      final id = _Identity();
      final c = _container(identity: id);
      addTearDown(c.dispose);
      await _pump(tester, container: c);
      final l = pwaL10nFor(const Locale('en'));

      final save = find.byKey(const ValueKey('pwa-profile-save-work'));
      final signIn = find.byKey(const ValueKey('pwa-profile-sign-in'));
      expect(save, findsOneWidget);
      expect(signIn, findsOneWidget);
      expect(find.text(l.accountHaveOne), findsOneWidget);
      // Hierarchy, as geometry: the returning-user door sits BELOW the primary
      // one, because the guest in front of us is far more often new. iOS keeps
      // the same order (a primary create, a secondary acctSignInExisting).
      expect(tester.getTopLeft(signIn).dy,
          greaterThan(tester.getTopLeft(save).dy));
      // Drawing them creates nothing.
      expect(id.link.calls, isEmpty);
      expect(c.read(pwaAuthProvider).stage, PwaAuthStage.guest);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AUTH02: Sign in opens the sheet ON the sign-in journey',
        (tester) async {
      final id = _Identity();
      final c = _container(identity: id);
      addTearDown(c.dispose);
      await _pump(tester, container: c);
      final l = pwaL10nFor(const Locale('en'));

      await tester.tap(find.byKey(const ValueKey('pwa-profile-sign-in')));
      await tester.pumpAndSettle();
      // Scoped to the SHEET: the Profile card behind it carries `accountBody`
      // of its own, so an unscoped count would be reading the wrong surface.
      Finder inSheet(String s) => find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text(s),
          );
      // Its own title and body — not "Save your work" with a link underneath.
      expect(inSheet(l.accountSignInTitle), findsOneWidget);
      expect(inSheet(l.accountSignInBody), findsOneWidget);
      expect(inSheet(l.accountBody), findsNothing);
      // …and the way back to the other journey is still offered.
      expect(find.text(l.accountBackToLink), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AUTH03: Save your work still opens on the LINK journey',
        (tester) async {
      final id = _Identity();
      final c = _container(identity: id);
      addTearDown(c.dispose);
      await _pump(tester, container: c);
      final l = pwaL10nFor(const Locale('en'));

      await tester.tap(find.byKey(const ValueKey('pwa-profile-save-work')));
      await tester.pumpAndSettle();
      Finder inSheet(String s) => find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text(s),
          );
      expect(inSheet(l.accountTitle), findsOneWidget);
      expect(inSheet(l.accountBody), findsOneWidget);
      expect(inSheet(l.accountSignInBody), findsNothing);
      // The fork to the other journey is the one that was always there.
      expect(find.text(l.accountSignInInstead), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AUTH04: linking keeps the same user, and says so',
        (tester) async {
      final id = _Identity();
      final c = _container(identity: id);
      addTearDown(c.dispose);
      await _pump(tester, container: c);

      final before = id.auth.currentUserId;
      await id.identify(c, 'someone@example.com');
      await tester.pumpAndSettle();

      final s = c.read(pwaAuthProvider);
      expect(s.stage, PwaAuthStage.identified);
      // MEASURED, not assumed — the service captures the id either side of
      // verifyOTP and the UI only claims continuity when they match.
      expect(id.auth.currentUserId, before);
      expect(s.identityPreserved, isTrue);
      expect(s.switchedAccount, isFalse);
      expect(s.journey, PwaAuthJourney.linkNewIdentity);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AUTH05: once identified, neither door is offered any more',
        (tester) async {
      final id = _Identity();
      final c = _container(identity: id);
      addTearDown(c.dispose);
      await _pump(tester, container: c);
      await id.identify(c, 'someone@example.com');
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('pwa-profile-save-work')), findsNothing);
      expect(find.byKey(const ValueKey('pwa-profile-sign-in')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    test('AUTH06: the two journeys stay separate in the service', () {
      // The guard that matters is not in the UI. `beginLinkIdentity` and
      // `beginSignInExisting` drive DIFFERENT channels, and the sheet only
      // names which one is meant — it can neither merge them nor infer one
      // from the other.
      final id = _Identity();
      expect(id.service.runtimeType, PwaAuthService);
      // A link that finds the address already registered STOPS, and moving on
      // is a decision the person makes on screen — not a silent fallback.
      expect(PwaVerificationFailure.values,
          contains(PwaVerificationFailure.destinationAlreadyRegistered));
    });
  });

  group('PROF03  the wallet is the server, quoted', () {
    testWidgets('an unknown answer shows nothing at all', (tester) async {
      final c = _container(
        entitlement: const PwaEntitlement(state: PwaBillingState.loading),
      );
      addTearDown(c.dispose);
      await _pump(tester, container: c);
      expect(find.byKey(const ValueKey('pwa-profile-wallet')), findsNothing);
    });

    testWidgets('a pass shows the SERVER credit count, verbatim',
        (tester) async {
      final c = _container(
        entitlement: const PwaEntitlement(
          state: PwaBillingState.passActive,
          canGenerate: true,
          hasActivePass: true,
          passCredits: 7,
          creditsAvailable: 7,
        ),
      );
      addTearDown(c.dispose);
      await _pump(tester, container: c);
      final l = pwaL10nFor(const Locale('en'));
      expect(find.text(l.passSpacesLeft(7)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an exhausted free tier says so and opens the existing paywall',
        (tester) async {
      final c = _container(
        entitlement: const PwaEntitlement(
          state: PwaBillingState.freeExhausted,
          canGenerate: false,
          freeCredits: 0,
          creditsAvailable: 0,
        ),
      );
      addTearDown(c.dispose);
      await _pump(tester, container: c);
      final l = pwaL10nFor(const Locale('en'));
      expect(find.text(l.billingFreeExhausted), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pwa-profile-wallet')));
      await tester.pumpAndSettle();
      // The paywall that already exists, in the state the SERVER put us in —
      // this screen neither builds one nor chooses which one to show.
      expect(find.text(l.paywallFreeUsedTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('PROF03b  the wallet says the right KIND of thing', () {
    testWidgets('a free Guest is never told they hold paid Spaces',
        (tester) async {
      // Found on the staging preview: a fresh Guest read "1 Spaces restants".
      // The arithmetic was right and the sentence was wrong — a Space is a
      // thing you buy, and this person has a free vision.
      final c = _container(
        entitlement: const PwaEntitlement(
          state: PwaBillingState.freeAvailable,
          canGenerate: true,
          freeCredits: 1,
          creditsAvailable: 1,
        ),
      );
      addTearDown(c.dispose);
      await _pump(tester, container: c);
      final l = pwaL10nFor(const Locale('en'));
      expect(find.text(l.freeVisionAvailable), findsOneWidget);
      expect(find.text(l.passSpacesLeft(1)), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'PROF03c: a granted balance is REPORTED, not reduced to "1 free vision"',
        (tester) async {
      // Found on the live phone. The account held a canonical ADMIN ledger
      // adjustment of +300 and the entitlement endpoint said so —
      // credits_available 300, free_credits 300, tier free, no pass — and
      // Profile answered "1 free vision".
      //
      // ROOT CAUSE: the row is keyed on the billing STATE, which is the right
      // discriminator for WHY access was granted, and `freeAvailable` means
      // only "granted from the non-pass bucket". An ADMIN adjustment lands in
      // exactly that bucket. The state was correct; the sentence under it was
      // a constant. The count now comes off `creditsAvailable` — the server's
      // own `credits_available` — and nothing is added up locally.
      final c = _container(
        entitlement: const PwaEntitlement(
          state: PwaBillingState.freeAvailable,
          canGenerate: true,
          accessSource: 'free',
          tier: 'free',
          freeCredits: 300,
          creditsAvailable: 300,
        ),
      );
      addTearDown(c.dispose);
      await _pump(tester, container: c);
      final l = pwaL10nFor(const Locale('en'));
      expect(find.text(l.passSpacesLeft(300)), findsOneWidget);
      expect(find.text(l.freeVisionAvailable), findsNothing);
      expect(tester.takeException(), isNull);
    });

    test('PROF03d: the sentence follows the BALANCE, not the tier', () {
      // Stated as arithmetic so the boundary is explicit and cannot drift: ONE
      // is the welcome vision and keeps its name; anything above it is a
      // count. `tier` is deliberately 'free' throughout — the whole defect was
      // treating that classification as a quantity.
      final l = pwaL10nFor(const Locale('en'));
      String at(int n) => pwaWalletSentence(
            l,
            PwaEntitlement(
              state: PwaBillingState.freeAvailable,
              canGenerate: true,
              tier: 'free',
              accessSource: 'free',
              freeCredits: n,
              creditsAvailable: n,
            ),
          );
      expect(at(1), l.freeVisionAvailable);
      expect(at(2), l.passSpacesLeft(2));
      expect(at(30), l.passSpacesLeft(30));
      expect(at(300), l.passSpacesLeft(300));
      expect(at(300), contains('300'));
      // …and the untouched welcome vision is still never called a Space.
      expect(at(1), isNot(contains('space')));
      expect(at(1), isNot(contains('Space')));
    });

    test('PROF03e: every language reports the granted balance', () {
      for (final code in const ['en', 'fr', 'km']) {
        final l = pwaL10nFor(Locale(code));
        final s = pwaWalletSentence(
          l,
          const PwaEntitlement(
            state: PwaBillingState.freeAvailable,
            canGenerate: true,
            tier: 'free',
            freeCredits: 300,
            creditsAvailable: 300,
          ),
        );
        expect(s, contains('300'), reason: code);
        expect(s, isNot(l.freeVisionAvailable), reason: code);
        expect(s.startsWith('pwa'), isFalse, reason: '$code: $s');
      }
    });

    test('every billing state the server can emit has a sentence', () {
      // The row is a `switch` over the state precisely so a new state is a
      // compile error rather than a blank line in front of a paying customer.
      final l = pwaL10nFor(const Locale('en'));
      for (final st in PwaBillingState.values) {
        final e = PwaEntitlement(state: st, creditsAvailable: 3);
        expect(pwaWalletSentence(l, e), st == PwaBillingState.loading
            ? isEmpty
            : isNotEmpty, reason: '$st');
      }
    });
  });

  group('PROF04  no native control leaks onto the web', () {
    testWidgets('Apple, RevenueCat and the App Store are absent',
        (tester) async {
      final id = _Identity();
      final c = _container(identity: id);
      addTearDown(c.dispose);
      await id.identify(c, 'someone@example.com');
      await _pump(tester, container: c);

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => (t.data ?? '').toLowerCase())
          .join(' | ');
      for (final banned in const [
        'apple',
        'restore',
        'app store',
        'subscription',
        'manage plan',
        'notification',
        'rate ',
      ]) {
        expect(texts, isNot(contains(banned)), reason: banned);
      }
      // And no editable identity fields: the store they would write to is
      // mobile's, and a field that saves nowhere is worse than no field.
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('PROF05  language is the one the product already has', () {
    testWidgets('the row writes through the shared locale notifier',
        (tester) async {
      final c = await _pump(tester);
      expect(c.read(localeProvider).languageCode, 'en');

      await tester.tap(find.byKey(const ValueKey('pwa-profile-language')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pwa-profile-language-sheet')),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pwa-profile-lang-km')));
      await tester.pumpAndSettle();
      // One preference, changed — not a second store.
      expect(c.read(localeProvider).languageCode, 'km');
      // And the screen is now Khmer.
      expect(find.text(pwaL10nFor(const Locale('km')).shared.profileTitle),
          findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('all three languages are reachable on a phone', (tester) async {
      // Not a regression test — the clipped sheet this was written for turned
      // out to be a frozen browser tab, not the app. It is kept because the
      // invariant is real and cheap: a capped sheet, a fourth language or a
      // shorter viewport would each push a row off the bottom, and a row you
      // cannot reach is a language the product does not offer. GEOMETRY is the
      // assertion; merely FINDING a row is not, because a clipped one is still
      // findable.
      await _pump(tester, size: const Size(390, 844));
      await tester.tap(find.byKey(const ValueKey('pwa-profile-language')));
      await tester.pumpAndSettle();
      for (final code in const ['km', 'en', 'fr']) {
        final row = find.byKey(ValueKey('pwa-profile-lang-$code'));
        expect(row, findsOneWidget, reason: code);
        final r = tester.getRect(row);
        expect(r.bottom, lessThanOrEqualTo(844), reason: '$code is cut off');
        expect(r.top, greaterThanOrEqualTo(0), reason: code);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('changing language starts nothing', (tester) async {
      final c = await _pump(tester);
      final before = c.read(pwaControllerProvider);
      await tester.tap(find.byKey(const ValueKey('pwa-profile-language')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pwa-profile-lang-fr')));
      await tester.pumpAndSettle();
      final after = c.read(pwaControllerProvider);
      expect(after.phase, before.phase);
      expect(after.versions.length, before.versions.length);
      expect(after.visibleProjects.length, before.visibleProjects.length);
    });

    for (final code in const ['en', 'fr', 'km']) {
      testWidgets('the whole surface resolves in $code', (tester) async {
        final c = _container(identity: _Identity());
        addTearDown(c.dispose);
        await _pump(tester, locale: Locale(code), container: c);
        final l = pwaL10nFor(Locale(code));
        for (final s in [
          l.shared.profileTitle,
          l.shared.settingsAccount,
          l.shared.settingsSupport,
          l.shared.settingsLanguage,
          l.accountGuestLabel,
          l.accountTitle,
          l.seeHowItWorks,
          l.yourSpaces,
          // Round 1 — the returning user's door, in every language.
          l.accountHaveOne,
          l.accountSignInTitle,
        ]) {
          expect(s, isNotEmpty, reason: code);
          expect(s.startsWith('pwa'), isFalse, reason: '$code: $s');
        }
        // 'Profile' is also the nav label — the title is the 26pt one.
        expect(find.text(l.shared.profileTitle), findsWidgets);
        expect(find.text(l.accountHaveOne), findsOneWidget, reason: code);
        // The Settings list is lazily built and the identity block above it
        // grew by a row, so Language can sit below the first build window.
        // Scroll to it the way a reader does, rather than widening the test
        // viewport until the assertion happens to pass.
        await tester.scrollUntilVisible(
          find.text(l.shared.settingsLanguage),
          200,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 40,
        );
        expect(find.text(l.shared.settingsLanguage), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('PROF06  the guide is the explainer that already exists', () {
    testWidgets('it opens, and starts no onboarding funnel', (tester) async {
      final c = await _pump(tester);
      final before = c.read(pwaControllerProvider).phase;
      await tester.tap(find.byKey(const ValueKey('pwa-profile-guide')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pwa-guide-sheet')), findsOneWidget);
      // It is a sheet over Profile — not a route, not a phase change.
      expect(c.read(pwaControllerProvider).phase, before);
      expect(tester.takeException(), isNull);
    });

    testWidgets('it can be replayed', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const ValueKey('pwa-profile-guide')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pwa-guide-replay')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pwa-guide-sheet')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('PROF07  it holds together', () {
    for (final size in const [
      Size(390, 844),
      Size(430, 932),
      Size(768, 1024),
      Size(1440, 900),
      Size(1920, 1080),
    ]) {
      testWidgets('no overflow at ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        final c = _container(identity: _Identity());
        addTearDown(c.dispose);
        await _pump(tester, size: size, container: c);
        expect(tester.takeException(), isNull);
      });
    }

    test('a wide window is a column, never a two-pane dashboard', () {
      expect(pwaProfileColumnWidth(390), 390);
      expect(pwaProfileColumnWidth(1440), 640);
      expect(pwaProfileColumnWidth(1920), 640);
    });
  });

  // A deliberate WEB addition over iOS (Round 3, phone review item 4): a person
  // who still has Spaces may want more, and the only shop on this platform is
  // the paywall sheet. iOS needs no such line — its store handles top-ups.
  group('PROF08  a holder of Spaces can choose to buy more', () {
    const holder = PwaEntitlement(
      state: PwaBillingState.freeAvailable,
      canGenerate: true,
      freeCredits: 300,
      creditsAvailable: 300,
    );

    testWidgets('the balance row carries a "Get more Spaces" line',
        (tester) async {
      final c = _container(entitlement: holder);
      addTearDown(c.dispose);
      await _pump(tester, container: c);
      final l = pwaL10nFor(const Locale('en'));
      expect(find.text(l.passSpacesLeft(300)), findsOneWidget,
          reason: 'the authoritative balance is still what the row states');
      expect(find.byKey(const ValueKey('pwa-profile-get-spaces')),
          findsOneWidget);
      expect(find.text(l.getMoreSpaces), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping it opens the existing paywall — with Spaces in hand',
        (tester) async {
      final c = _container(entitlement: holder);
      addTearDown(c.dispose);
      await _pump(tester, container: c);
      // Nothing about gating changed: this person is not required to buy.
      expect(c.read(pwaEntitlementProvider).requiresPurchase, isFalse);
      expect(c.read(pwaEntitlementProvider).canGenerate, isTrue);

      await tester.tap(find.byKey(const ValueKey('pwa-profile-get-spaces')));
      await tester.pumpAndSettle();
      expect(find.byType(PwaPaywallSheet), findsOneWidget,
          reason: 'the sheet that already exists, opened voluntarily');
      expect(tester.takeException(), isNull);
    });

    for (final (code, label) in const [
      ('en', 'Get more Spaces'),
      ('fr', 'Acheter des Spaces'),
      ('km', 'ទិញ Spaces បន្ថែម'),
    ]) {
      testWidgets('the line reads "$label" in $code', (tester) async {
        final c = _container(entitlement: holder);
        addTearDown(c.dispose);
        await _pump(tester, container: c, locale: Locale(code));
        expect(find.text(label), findsOneWidget);
      });
    }
  });
}
