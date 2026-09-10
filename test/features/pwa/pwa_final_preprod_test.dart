/// FINAL PRE-PRODUCTION PASS — the real-device defects of 2026-09-10.
///
///   AUTH-STATE  an identified account is stated, never re-offered a door
///   COUNT       the Profile number is every finished Vision
///   REVEAL      the canvas breathes under the toolbar, at the same width
///   FULLSCREEN  the control carries its icon, opens the viewer, comes back
///   UPLOAD      the photo menu is anchored on the zone that was tapped
///   REFINE      a reply is resolved against the turn it answers
library;

import 'package:ai_home_architect/core/l10n/app_localizations.dart';
import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_auth_controller.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_auth_service.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_generation_service.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_mock_generation_service.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_l10n.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_account_chip.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_account_sheet.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_experience.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_file_picker_anchor.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_render_aspect.dart'
    show pwaRevealHeroHeight;
import 'package:ai_home_architect/features/pwa/presentation/pwa_render_canvas.dart'
    show pwaRevealBlockHeight;
import 'package:ai_home_architect/features/pwa/presentation/pwa_reveal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

AydenImageSource _source() =>
    AydenImageSource(bytes: _png, filename: 'room.png', mimeType: 'image/png');

final _en = pwaL10nFor(const Locale('en'));

// ── identity: a fixed account, no network ───────────────────────────────────

class _FixedAuth extends PwaAuthController {
  _FixedAuth(PwaAuthState initial) : super(null) {
    state = initial;
  }

  int signOuts = 0;

  // The project offers Facebook and not phone — preprod's configuration.
  @override
  bool get isAvailable => true;
  @override
  bool get canFacebook => true;
  @override
  bool get canPhone => false;
  @override
  PwaAuthProviders get providers =>
      PwaAuthProviders(facebook: true, phone: false);
  @override
  void cancel() {}
  @override
  Future<void> signOut() async {
    signOuts++;
    state = const PwaAuthState(stage: PwaAuthStage.guest);
  }
}

/// The account from the phone review: Facebook and e-mail both attached.
const _mike = PwaAuthState(
  stage: PwaAuthStage.identified,
  displayName: 'Mike Lim',
  email: 'mike@example.com',
  providers: ['facebook', 'email'],
  userId: 'user-mike',
  isAnonymous: false,
);

const _guest = PwaAuthState(stage: PwaAuthStage.guest);

// ── a scripted chat brain ───────────────────────────────────────────────────

class _ScriptedChat implements PwaGenerationService {
  _ScriptedChat(this._inner);

  final PwaGenerationService _inner;
  final List<String> pendingSeen = <String>[];
  final List<List<Map<String, String>>> historySeen =
      <List<Map<String, String>>>[];
  final List<String> refined = <String>[];
  final List<bool> refineConfirms = <bool>[];
  final List<PwaChatTurn> script = <PwaChatTurn>[];
  PwaGenerationAdvisory? advisory;

  @override
  Future<PwaChatTurn> chat({
    required String projectId,
    required String message,
    String uiLocale = 'en',
    List<Map<String, String>> history = const [],
    String pendingInstruction = '',
  }) async {
    pendingSeen.add(pendingInstruction);
    historySeen.add(history);
    return script.isEmpty ? const PwaChatTurn.silent() : script.removeAt(0);
  }

  @override
  Future<PwaGeneratedVision> generate(PwaGenerationIntent intent) async {
    if (intent.actionType == 'refine') {
      refined.add(intent.userInstruction);
      refineConfirms.add(intent.confirm);
    }
    final a = advisory;
    if (a != null) throw PwaAdvisoryRaised(a);
    return _inner.generate(intent);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Function.apply((_inner as dynamic).noSuchMethod, [invocation]);
}

// ── rigs ────────────────────────────────────────────────────────────────────

ProviderContainer _container({List<Override> extra = const []}) {
  final repo = MockPwaExperienceRepository(workDelay: Duration.zero);
  return ProviderContainer(overrides: [
    pwaRepositoryProvider.overrideWithValue(repo),
    pwaGenerationServiceProvider.overrideWithValue(PwaMockGenerationService(repo)),
    ...extra,
  ]);
}

Widget _app(
  ProviderContainer c, {
  Size size = const Size(390, 844),
  Widget home = const PwaExperience(),
}) =>
    MediaQuery(
      data: MediaQueryData(disableAnimations: true, size: size),
      child: UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('km'), Locale('fr')],
          home: home,
        ),
      ),
    );

/// A first vision, then [more] atmosphere switches — how a person reaches V2
/// and V3.
Future<void> _visions(PwaController n, {int more = 0, String room = 'living_room'}) async {
  n.newProject();
  n.setSource(_source(), origin: PwaImageOrigin.userUpload);
  n.selectRoom(room);
  n.selectEntryAtmosphere('warm_modern');
  await n.generateFirstVision();
  const others = ['soft_luxury', 'japandi_calm'];
  for (var i = 0; i < more; i++) {
    n.stageAtmosphere(others[i % others.length]);
    await n.applyAtmosphere();
  }
}

Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  group('AUTH-STATE  an identified account is stated, never re-offered a door',
      () {
    // THE DEFECT, from a real iPhone: Profile said "Mike Lim · Connected with
    // Facebook", and the header menu offered "Signed in as Mike Lim" as an
    // item that opened the account sheet — "Secure your Ayden account" and
    // "Continue with Facebook", for an account signed in with Facebook.
    Future<(ProviderContainer, _FixedAuth)> openChip(
        WidgetTester tester, PwaAuthState s) async {
      final fixed = _FixedAuth(s);
      final c = _container(extra: [pwaAuthProvider.overrideWith((ref) => fixed)]);
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(c,
          home: const Scaffold(
            body: Align(alignment: Alignment.topRight, child: PwaAccountChip()),
          )));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pwa-account-chip')));
      await tester.pumpAndSettle();
      return (c, fixed);
    }

    testWidgets('AUTH-STATE-01/02  a Facebook account sees who it is, and no door',
        (tester) async {
      await openChip(tester, _mike);
      expect(find.text('Mike Lim'), findsOneWidget);
      expect(find.text(_en.authConnectedVia(PwaAuthMethod.facebook)),
          findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-account-profile')), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-account-signout')), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-account-open')), findsNothing);
      expect(find.byKey(const ValueKey('pwa-account-signin')), findsNothing);
      // The identity is a fact, not a door: tapping it opens nothing at all.
      await tester.tap(find.byKey(const ValueKey('pwa-account-identity')),
          warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pwa-auth-facebook')), findsNothing);
      expect(find.text(_en.authSecureTitle), findsNothing);
      expect(find.text(_en.authContinueFacebook), findsNothing);
    });

    testWidgets('AUTH-STATE-01  Profile is one tap away', (tester) async {
      final (c, _) = await openChip(tester, _mike);
      await tester.tap(find.byKey(const ValueKey('pwa-account-profile')));
      await tester.pumpAndSettle();
      expect(c.read(pwaControllerProvider).phase, PwaPhase.profile);
    });

    testWidgets('AUTH-STATE-03  Sign out is there, and it signs out',
        (tester) async {
      final (_, fixed) = await openChip(tester, _mike);
      await tester.tap(find.byKey(const ValueKey('pwa-account-signout')));
      await tester.pumpAndSettle();
      expect(fixed.signOuts, 1);
      expect(fixed.state.stage, PwaAuthStage.guest);
    });

    testWidgets('AUTH-STATE-04/05  a Guest keeps both doors, and they stay two',
        (tester) async {
      await openChip(tester, _guest);
      expect(find.byKey(const ValueKey('pwa-account-open')), findsOneWidget);
      expect(find.text(_en.accountTitle), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-account-signin')), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-account-identity')), findsNothing);
      expect(find.byKey(const ValueKey('pwa-account-profile')), findsNothing);
    });

    Future<void> openSheet(WidgetTester tester, PwaAuthState s) async {
      final fixed = _FixedAuth(s);
      final c = _container(extra: [pwaAuthProvider.overrideWith((ref) => fixed)]);
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(c,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPwaAccountSheet(context),
                child: const Text('open'),
              ),
            ),
          )));
      // MaterialApp builds its home once the localisation delegates resolve —
      // one frame after the first.
      await tester.pump();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('AUTH-STATE-02  whatever opens the sheet, an attached Facebook '
        'is never offered', (tester) async {
      await openSheet(tester, _mike);
      expect(find.byKey(const ValueKey('pwa-auth-facebook')), findsNothing);
      expect(find.byKey(const ValueKey('pwa-auth-email')), findsNothing);
      expect(find.text(_en.accountLinkedTitle), findsOneWidget);
    });

    testWidgets('AUTH-STATE-05  an e-mail account may still ADD Facebook — only '
        'what is attached disappears', (tester) async {
      await openSheet(
        tester,
        const PwaAuthState(
          stage: PwaAuthStage.identified,
          email: 'a@example.com',
          providers: ['email'],
          userId: 'user-mail',
          isAnonymous: false,
        ),
      );
      expect(find.byKey(const ValueKey('pwa-auth-facebook')), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-auth-email')), findsNothing,
          reason: 'it already has an e-mail');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('COUNT  the Profile number is every finished Vision', () {
    // THE DEFECT: 300 → 297 Spaces after three renders, and Profile said
    // "2 Redesigns". The number was the PROJECT count under a redesign label.
    test('COUNT-01/02  three renders in two projects count three, once each',
        () async {
      final c = _container();
      addTearDown(c.dispose);
      final n = c.read(pwaControllerProvider.notifier);
      await _visions(n, more: 1); // project A: V1 + a switch
      final a = c.read(pwaControllerProvider).project.projectId;
      await _visions(n, room: 'kitchen'); // project B: V1
      final s = c.read(pwaControllerProvider);
      final b = s.project.projectId;
      // The mock library carries demo projects of its own; count around them.
      final others = s.library
          .where((p) => p.projectId != a && p.projectId != b)
          .fold<int>(0, (sum, p) => sum + p.visions.length);
      final mine = s.library
          .where((p) => p.projectId == a || p.projectId == b)
          .toList();
      expect(mine, hasLength(2), reason: 'two projects — what the old stat showed');
      // B's vision sits both in the library and in the session in hand; it
      // is one render and counts once.
      expect(s.versions.length, 1);
      expect(s.completedVisionCount - others, 3,
          reason: 'three finished renders, V1 included, each counted once');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('REVEAL  the canvas breathes under the toolbar, at the same width', () {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      testWidgets(
          'REVEAL-SPACING-01/02  V1, V2, V3 at '
          '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final c = _container();
        addTearDown(c.dispose);
        final n = c.read(pwaControllerProvider.notifier);
        await _visions(n, more: 2);
        final versions = c.read(pwaControllerProvider).versions;
        expect(versions, hasLength(3));
        n.openReveal(versions.first.versionId);
        await tester.pumpWidget(_app(c, size: size));
        await _frames(tester);
        final widths = <double>[];
        for (final v in versions) {
          n.openReveal(v.versionId);
          await _frames(tester);
          final header =
              tester.getRect(find.byKey(const ValueKey('pwa-reveal-header')));
          final canvas = tester.getRect(
              find.byKey(ValueKey('full-reveal-canvas-${v.versionId}')));
          expect(
              canvas.top - header.bottom,
              closeTo(
                  kPwaRevealChromeGap +
                      pwaRevealExtraGap(size.height, size.width),
                  0.5),
              reason: 'air between the toolbar and the picture — 28 on a '
                  'phone, 12 on a desktop window');
          widths.add(canvas.width);
        }
        expect(widths.toSet(), hasLength(1),
            reason: 'V1, V2 and V3 share one canvas width');
        final column =
            size.width < kPwaRevealMaxWidth ? size.width : kPwaRevealMaxWidth;
        expect(widths.first, closeTo(column - 24, 0.5),
            reason: 'the width is the column\'s, untouched by the gap');
      });
    }
  });

  test("REVEAL-SPACING-03  a phone's extra air is paid by the rail, never by "
      'the render', () {
    // Installed iPhone (797 = 844 minus the status bar), the same phone in
    // Safari with its toolbars (664), a test-size phone (844), a Pro Max (873).
    for (final (h, w) in const [
      (797.0, 390.0),
      (664.0, 390.0),
      (844.0, 390.0),
      (873.0, 430.0),
    ]) {
      final extra = pwaRevealExtraGap(h, w);
      final strip = pwaRevealStripHeight(h, w);
      double canvas(double chrome, double rail) {
        final available = h -
            (kPwaRevealSectionHeaderH +
                rail +
                kPwaRevealSlotH +
                kPwaRevealSlotPadV);
        final hero = pwaRevealHeroHeight(
          blockH: pwaRevealBlockHeight(h),
          available: available,
          chromeH: chrome,
          footH: kPwaRevealFootH,
        );
        return hero - chrome - kPwaRevealFootH;
      }

      expect(kPwaRevealChromeGap + extra, inInclusiveRange(24, 32),
          reason: '${w}x$h: the air the review asked for');
      expect(canvas(kPwaRevealChromeH + extra, strip - extra),
          closeTo(canvas(kPwaRevealChromeH, strip), 0.01),
          reason: '${w}x$h: the canvas, and the render in it, is unchanged');
    }
    expect(pwaRevealExtraGap(900, 1440), 0, reason: 'a desktop window keeps 12');
    expect(pwaRevealExtraGap(500, 390), 0,
        reason: 'a rail already at its floor pays nothing, so the canvas '
            'never pays instead');
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('FULLSCREEN  the control carries its icon, opens, and comes back', () {
    testWidgets('FULLSCREEN-01..05  icon, viewer, zoom and the way back — '
        'V1, V2, V3', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = _container();
      addTearDown(c.dispose);
      final n = c.read(pwaControllerProvider.notifier);
      await _visions(n, more: 2);
      final versions = c.read(pwaControllerProvider).versions;
      n.openReveal(versions.first.versionId);
      await tester.pumpWidget(_app(c));
      await _frames(tester);
      for (final v in versions) {
        n.openReveal(v.versionId);
        await _frames(tester);
        final button = find.byKey(const ValueKey('pwa-reveal-fullscreen'));
        expect(
            find.descendant(
                of: button, matching: find.byIcon(Icons.fullscreen_rounded)),
            findsOneWidget,
            reason: 'the control draws its glyph');
        await tester.tap(button);
        await _frames(tester);
        final viewer = tester.widget<InteractiveViewer>(
            find.byKey(const ValueKey('pwa-viewer-interactive')));
        expect(viewer.maxScale, greaterThan(1), reason: 'it zooms');
        expect(find.byKey(ValueKey('pwa-viewer-${v.afterAsset}')),
            findsOneWidget,
            reason: 'the viewer shows THIS vision');
        await tester.tap(find.byKey(const ValueKey('pwa-viewer-close')));
        await _frames(tester);
        expect(find.byKey(const ValueKey('pwa-viewer-interactive')),
            findsNothing);
        final s = c.read(pwaControllerProvider);
        expect(s.phase, PwaPhase.reveal);
        expect(s.previewVisionId, v.versionId,
            reason: 'back on the same vision, nothing lost');
        expect(find.byKey(ValueKey('full-reveal-canvas-${v.versionId}')),
            findsOneWidget);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('UPLOAD  the photo menu grows from the zone that was tapped', () {
    // WebKit grows "Photo Library · Take Photo · Choose File" from the input it
    // is clicking. The plugin leaves that input unstyled in the page's
    // top-left corner (measured: 0,0 253×21), so the menu appeared there — or,
    // when that corner was scrolled out, at the last touch point.
    testWidgets('UPLOAD-02  the input is anchored on the zone BEFORE it opens',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final anchored = <Rect>[];
      var anchoredFirst = false;
      const channel = MethodChannel('plugins.flutter.io/image_picker');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        anchoredFirst = anchored.isNotEmpty;
        return null; // the person closed the picker
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final c = _container(extra: [
        pwaFilePickerAnchorProvider.overrideWithValue(anchored.add),
      ]);
      addTearDown(c.dispose);
      c.read(pwaControllerProvider.notifier).newProject();
      await tester.pumpWidget(_app(c));
      await tester.pumpAndSettle();
      final zone = find.byKey(const ValueKey('pwa-create-upload'));
      expect(zone, findsOneWidget);
      await tester.tap(zone);
      await tester.pump();
      await tester.pump();
      expect(anchored, hasLength(1));
      expect(anchored.single, tester.getRect(zone),
          reason: 'the menu grows from the zone that was tapped');
      expect(anchoredFirst, isTrue,
          reason: 'placed before the picker opens, or it is too late');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('REFINE  a reply is resolved against the turn it answers', () {
    Future<(ProviderContainer, _ScriptedChat)> session() async {
      final repo = MockPwaExperienceRepository(workDelay: Duration.zero);
      final chat = _ScriptedChat(PwaMockGenerationService(repo));
      final c = ProviderContainer(overrides: [
        pwaRepositoryProvider.overrideWithValue(repo),
        pwaGenerationServiceProvider.overrideWithValue(chat),
      ]);
      addTearDown(c.dispose);
      await _visions(c.read(pwaControllerProvider.notifier));
      return (c, chat);
    }

    const warning = "As your architect, I don't recommend « add a living room "
        'behind ». Would you like to consider creating a separate living area '
        'adjacent to the bedroom instead?';

    testWidgets('REFINE-06  after a RED warning, the warning IS the last turn '
        'the server receives', (tester) async {
      // The mandatory proof: for the exact phone sequence, the assistant
      // message immediately preceding "yes" is present in the request — as
      // its LAST entry, which is where every resolver looks.
      final (c, chat) = await session();
      final n = c.read(pwaControllerProvider.notifier);
      chat.advisory = const PwaGenerationAdvisory(verdict: 'red', message: warning);
      await n.applyRefine('break the wall on the left and add a living room behind');
      await tester.pump(const Duration(milliseconds: 50));
      chat.advisory = null;
      n.sendUserText('yes');
      await tester.pump(const Duration(milliseconds: 50));
      expect(chat.historySeen.last.last, {'role': 'ai', 'content': warning});
      expect(chat.pendingSeen.last,
          'break the wall on the left and add a living room behind',
          reason: 'and the original travels too, for "do it anyway"');
    });

    testWidgets('REFINE-07  a resolved "yes" renders Ayden\'s PROPOSAL, confirmed',
        (tester) async {
      final (c, chat) = await session();
      final n = c.read(pwaControllerProvider.notifier);
      chat.advisory = const PwaGenerationAdvisory(verdict: 'red', message: warning);
      await n.applyRefine('break the wall on the left and add a living room behind');
      await tester.pump(const Duration(milliseconds: 50));
      chat.advisory = null;
      chat.script.add(const PwaChatTurn(
        aiMessage: '',
        shouldGenerate: true,
        intent: 'conversation',
        overrideInstruction:
            'create a separate living area adjacent to the bedroom',
      ));
      n.sendUserText('yes');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(chat.refined.last,
          'create a separate living area adjacent to the bedroom',
          reason: 'the proposal is what renders — never the word "yes"');
      expect(chat.refineConfirms.last, isTrue);
    });

    testWidgets('REFINE-08  "which one?" and "no" render nothing', (tester) async {
      final (c, chat) = await session();
      final n = c.read(pwaControllerProvider.notifier);
      const question = 'Which one would you like — the reading nook, or the desk?';
      chat.script.add(const PwaChatTurn(
          aiMessage: question, shouldGenerate: false, intent: 'conversation'));
      n.sendUserText('yes');
      await tester.pump(const Duration(milliseconds: 50));
      chat.script.add(const PwaChatTurn(
          aiMessage: 'Understood — it stays as it is.',
          shouldGenerate: false,
          intent: 'conversation'));
      n.sendUserText('no');
      await tester.pump(const Duration(milliseconds: 50));
      expect(chat.refined, isEmpty);
      expect(c.read(pwaControllerProvider).versions, hasLength(1));
      expect(
          c.read(pwaControllerProvider).messages.any((m) => m.text == question),
          isTrue,
          reason: 'the question is asked, in Ayden\'s voice');
    });
  });
}

