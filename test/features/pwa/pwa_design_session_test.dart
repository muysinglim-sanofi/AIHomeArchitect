/// Phase 4, as corrected in round 1 — the wait, INSIDE the Design Session.
///
/// The screen these tests were written against is gone. It was a full-screen
/// loading page between Create and the conversation, and the round-1 phone
/// acceptance found it (with the unveiling after it) to be the thing that made
/// a generated vision feel like a separate product the person then had to
/// leave. iOS has never worked that way: the loading is a bubble in the
/// thread, and the render replaces it in place.
///
/// The two contracts below did NOT change with the container, so they are held
/// here still, against the Architect instead of against the deleted screen.
///
/// Phase 4 — the New Design Session, and the wait inside it.
///
/// Two things are being protected here, and they pull in opposite directions.
///
/// The first is CONTINUITY: what the person chose on Create must still be on
/// screen while Ayden works — their photo, their room, their atmosphere, and
/// the words they typed. That is the whole difference between a design session
/// and a form submission, and it is the thing a restyle would quietly lose.
///
/// The second is TRUTHFULNESS: the screen must not buy that continuity by
/// inventing progress. There is no progress signal in this pipeline, so there
/// is no number to show, and a bar that fills would be a claim nobody can
/// stand behind. These tests assert the absence of one as carefully as the
/// presence of the other.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_generation_service.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_models.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_l10n.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_architect_screen.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_experience.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_loading_screen.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_render_aspect.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_theme.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_working_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 1×1 PNG — decodable, so `Image.memory` renders rather than erroring.
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

/// A generation that never answers.
///
/// Held with a Completer rather than a long `Future.delayed`, because the
/// session screen is the thing under test and it has to stay on screen to be
/// looked at — and a pending Timer fails every widget test in this file on
/// teardown. Nothing here is scheduled, so nothing outlives the test.
class _HeldGeneration implements PwaGenerationService {
  final List<PwaGenerationIntent> calls = <PwaGenerationIntent>[];
  final _held = Completer<PwaGeneratedVision>();

  @override
  Future<PwaGeneratedVision> generate(PwaGenerationIntent intent) {
    calls.add(intent);
    return _held.future;
  }

  /// Answer the held call with a failure, so the error and retry paths can be
  /// exercised at the moment they really occur — mid-session.
  void fail(PwaGenerationFailure f) {
    if (!_held.isCompleted) _held.completeError(f);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

late _HeldGeneration _generation;

ProviderContainer _container() {
  _generation = _HeldGeneration();
  return ProviderContainer(
    overrides: [
      pwaRepositoryProvider.overrideWithValue(
        MockPwaExperienceRepository(workDelay: Duration.zero),
      ),
      pwaGenerationServiceProvider.overrideWithValue(_generation),
    ],
  );
}

/// Drive the real journey — Create, choose, then Generate — and stop on the
/// session. Deliberately NOT a hand-built state: what is being tested is that
/// the choices survive the transition, so they have to be made the way a
/// person makes them.
Future<ProviderContainer> _pumpSession(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  String? room = 'kitchen',
  String atmosphere = 'warm_modern',
  String brief = '',
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final c = _container();
  addTearDown(c.dispose);
  final n = c.read(pwaControllerProvider.notifier);
  n.newProject();
  n.setSource(_source(), origin: PwaImageOrigin.userUpload);
  if (room != null) n.selectRoom(room);
  n.selectEntryAtmosphere(atmosphere);
  // Not awaited: the generation never answers by construction.
  unawaited(n.generateFirstVision(userInstruction: brief));

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: true, size: size),
      child: UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: PwaExperience()),
      ),
    ),
  );
  await tester.pump();
  return c;
}

void unawaited(Future<void> f) {}

void main() {
  group('SESSION01  the transition from Create loses nothing', () {
    testWidgets('Generate enters the SESSION, and the work runs inside it',
        (tester) async {
      final c = await _pumpSession(tester);
      // The container is the conversation, from the tap onward.
      expect(c.read(pwaControllerProvider).phase, PwaPhase.architect);
      expect(find.byType(PwaArchitectScreen), findsOneWidget);
      // …and the wait is a card in the thread, not a page.
      expect(
        find.byKey(const ValueKey('pwa-working-first-vision')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the photo, the room and the atmosphere are all still there',
        (tester) async {
      final c = await _pumpSession(tester);
      final s = c.read(pwaControllerProvider);
      // The state kept them…
      expect(s.source, isNotNull);
      expect(s.source!.bytes, _png);
      expect(s.selectedRoomId, 'kitchen');
      expect(s.selectedAtmosphereId, 'warm_modern');
      // …and the SESSION shows them, which is the part that matters. A wait
      // that holds the context in state and renders a bare spinner is exactly
      // the form-submission feeling this phase exists to remove. The photo is
      // in the working card; the room names the session in its header.
      final photo = find.byKey(const ValueKey('pwa-working-source'));
      expect(photo, findsOneWidget);
      // The keyed widget is the measuring wrapper; the picture is inside it.
      final img = tester.widget<Image>(
          find.descendant(of: photo, matching: find.byType(Image)));
      expect((img.image as MemoryImage).bytes, _png);
      final l = pwaL10nFor(const Locale('en'));
      // The session header names them, joined into one line, so this reads
      // the line rather than expecting two standalone labels.
      expect(
        find.textContaining(l.roomCardLabel('kitchen', 'Kitchen')),
        findsWidgets,
      );
      expect(find.textContaining('Warm Modern'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the words the person typed are given back to them',
        (tester) async {
      final c = await _pumpSession(tester, brief: '  more natural light  ');
      // Trimmed on the way in — the session records what was SENT.
      expect(c.read(pwaControllerProvider).visionBrief, 'more natural light');
      expect(find.byKey(const ValueKey('pwa-session-brief')), findsOneWidget);
      expect(find.text('“more natural light”'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a skipped Step 4 leaves no empty quote on the screen',
        (tester) async {
      final c = await _pumpSession(tester);
      expect(c.read(pwaControllerProvider).visionBrief, isEmpty);
      expect(find.byKey(const ValueKey('pwa-session-brief')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('SESSION02  it says nothing it cannot know', () {
    testWidgets('no percentage, anywhere', (tester) async {
      await _pumpSession(tester);
      // Every rendered string, checked for a numeric progress claim. Written as
      // a sweep rather than as three `findsNothing`s so a percentage added
      // later, anywhere on this screen, fails too.
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();
      expect(texts, isNotEmpty);
      for (final t in texts) {
        expect(
          RegExp(r'\d+\s*%').hasMatch(t),
          isFalse,
          reason: 'the session must never claim a percentage: "$t"',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('there is no progress bar of any kind', (tester) async {
      await _pumpSession(tester);
      // The old screen carried a travelling band of constant width — motion
      // without a claim. The in-session indicator does not even have that: a
      // breathing dot, the phase sentence, and an ellipsis. Anything that
      // could be read as an amount of remaining work is absent, and this test
      // says so in the same terms the old one did.
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(FractionallySizedBox), findsNothing);
      expect(tester.takeException(), isNull);
    });

    // The deleted screen owned its own phrase cadence (`pwaSessionPhaseFor`,
    // a pure function over elapsed time). The session's indicator has always
    // owned its own — `PwaWorkingIndicator`, on `kPwaPhaseDuration` — so there
    // is now ONE cadence in the product instead of two, and no pure function
    // to call. What survives the merge is the rule that mattered: the phrases
    // are the approved dictionary's, they start at the beginning, and the last
    // one HOLDS rather than looping back to "Reading your space…" and telling
    // someone the work had restarted.
    test('the wait speaks the approved dictionary, and holds on the last', () {
      final l = pwaL10nFor(const Locale('en'));
      final phases = pwaWorkingPhasesFor(PwaWorkKind.firstVision, '', l);
      // The SHARED dictionary's seven, which is what the phone says for the
      // same beat (`chat_screen.dart:3661`) — not the web's own shorter four.
      expect(phases, l.shared.genInitPhrases);
      expect(phases.first, 'Reading your space…');
      expect(phases, isNotEmpty);
      // The indicator clamps into the list rather than wrapping, which is what
      // makes the last beat hold for as long as the render takes.
      for (final i in [0, phases.length - 1, phases.length, 999]) {
        expect(
          phases[i.clamp(0, phases.length - 1)],
          isNotEmpty,
          reason: 'beat $i must resolve to a real sentence, never wrap to 0',
        );
      }
      expect(phases[999.clamp(0, phases.length - 1)], phases.last);
    });

    testWidgets('the first thing it says is the approved mobile sentence',
        (tester) async {
      await _pumpSession(tester);
      final l = pwaL10nFor(const Locale('en'));
      expect(l.genInitPhrases.first, 'Reading your space…');
      expect(find.text(l.genInitPhrases.first), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('SESSION03  the iOS shell, not the legacy dark one', () {
    testWidgets('the canvas is the product canvas', (tester) async {
      await _pumpSession(tester);
      final scaffold = tester.widget<Scaffold>(
        find
            .descendant(
              of: find.byType(PwaArchitectScreen),
              matching: find.byType(Scaffold),
            )
            .first,
      );
      expect(scaffold.backgroundColor, isNot(Colors.black));
      expect(scaffold.backgroundColor, isNot(pwaBlack));
      expect(tester.takeException(), isNull);
    });

    testWidgets('no retired loading screen is mounted', (tester) async {
      // `PwaLoadingScreen` is kept on disk, unreferenced, as the fast way back
      // if this needs reverting — the same terms as the dark Home and the dark
      // Create. This asserts the router actually stopped using it, which is
      // the only part a reader cannot see from the file being present. Its
      // successor, the full-screen Design Session, is now deleted outright:
      // there is no third loading surface left to mount.
      await _pumpSession(tester);
      expect(find.byType(PwaLoadingScreen), findsNothing);
      expect(find.byType(PwaArchitectScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failure leaves Create, keeps the banner, and offers Retry',
        (tester) async {
      // Phase 4 restyled the failure banner's TYPE ROLE and nothing else. The
      // semantics are load-bearing and are asserted here rather than assumed:
      // a retryable failure must return the person to Create with their photo
      // and choices intact, show the banner, and offer Retry.
      final c = await _pumpSession(tester, brief: 'warmer');
      _generation.fail(
        const PwaGenerationFailure(
          userMessage: 'The engine is unreachable.',
          code: 'ENGINE_UNREACHABLE',
          retryable: true,
        ),
      );
      await tester.pumpAndSettle();

      final s = c.read(pwaControllerProvider);
      expect(s.phase, PwaPhase.entry, reason: 'a failure returns to Create');
      expect(s.generating, isFalse);
      expect(s.generationRetryable, isTrue);
      // Nothing the person chose was thrown away by the failure.
      expect(s.source, isNotNull);
      expect(s.selectedRoomId, 'kitchen');
      expect(s.selectedAtmosphereId, 'warm_modern');
      expect(s.visionBrief, 'warmer');

      expect(
        find.byKey(const ValueKey('pwa-generation-error')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('pwa-generation-retry')), findsOneWidget);
      // A failed generation is never dressed up as a success.
      expect(s.versions, isEmpty);
      expect(find.byKey(const ValueKey('pwa-working-first-vision')),
          findsNothing);
    });

    testWidgets('the working card takes the shape the render will take',
        (tester) async {
      final c = await _pumpSession(tester);
      // iOS's own rule for this moment: "Card height matches the _LoadingBubble
      // formula so the shape doesn't jump between generating and generated."
      // The render takes the PHOTO's orientation (the engine sizes its output
      // from the source), so the working card frames the photo at the photo's
      // own measured shape — and the engine's 3:2 until it is measured. The
      // test's photo is a 1x1 PNG, so once decoded the frame is square; the
      // render of that photo would be square too.
      final ratio = tester.widget<AspectRatio>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('pwa-working-source')),
              matching: find.byType(AspectRatio),
            )
            .first,
      );
      final measured = c.read(pwaRenderAspectsProvider)[kPwaSourceAspectKey];
      expect(ratio.aspectRatio, measured ?? kPwaRenderAspect);
      expect(tester.takeException(), isNull);
    });

    testWidgets('it holds together at every mandated viewport',
        (tester) async {
      for (final size in const [
        Size(390, 844), // iPhone
        Size(430, 932), // iPhone Pro Max
        Size(768, 1024), // tablet
        Size(1440, 900), // desktop
      ]) {
        await _pumpSession(tester, size: size, brief: 'warmer, more light');
        expect(
          find.byKey(const ValueKey('pwa-working-first-vision')),
          findsOneWidget,
          reason: '$size',
        );
        expect(tester.takeException(), isNull, reason: '$size');
      }
    });
  });

  group('SESSION04  one Generate is one generation', () {
    testWidgets('reaching the session does not fire a second request',
        (tester) async {
      final c = await _pumpSession(tester);
      // Rebuilding the session — which happens on every phrase change and on
      // every provider tick — must never re-enter the generation.
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 30));
      final s = c.read(pwaControllerProvider);
      expect(s.generating, isTrue);
      expect(s.phase, PwaPhase.architect);
      expect(s.versions, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a second Generate while one is in flight is refused',
        (tester) async {
      final c = await _pumpSession(tester, brief: 'first');
      // A duplicated request is a duplicated charge. The guard is set
      // synchronously, before the first await, so a second tap in the same
      // frame finds it already true.
      unawaited(
        c
            .read(pwaControllerProvider.notifier)
            .generateFirstVision(userInstruction: 'second'),
      );
      await tester.pump();
      expect(
        _generation.calls,
        hasLength(1),
        reason: 'one Generate must reach the engine exactly once',
      );
      expect(_generation.calls.single.userInstruction, 'first');
      expect(c.read(pwaControllerProvider).visionBrief, 'first');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the brief that was recorded is the brief that was sent',
        (tester) async {
      await _pumpSession(tester, brief: '  a reading corner  ');
      // The screen shows the trimmed text, and the ENGINE received the same
      // trimmed text. One value, one journey — the session cannot show the
      // person something other than what was asked for.
      expect(_generation.calls, hasLength(1));
      expect(_generation.calls.single.userInstruction, 'a reading corner');
      expect(find.text('“a reading corner”'), findsOneWidget);
    });

    testWidgets('a skipped Step 4 sends an empty instruction', (tester) async {
      await _pumpSession(tester);
      expect(_generation.calls, hasLength(1));
      expect(_generation.calls.single.userInstruction, isEmpty);
    });

    testWidgets('the room and atmosphere reach the engine, not just the screen',
        (tester) async {
      await _pumpSession(tester);
      final intent = _generation.calls.single;
      expect(intent.roomId, 'kitchen');
      expect(intent.atmosphereId, 'warm_modern');
      expect(intent.originalImagePath, isNotEmpty);
      expect(intent.visionNumber, 1);
    });
  });

  group('SESSION05  the deployment may not freeze the app shell', () {
    // RELEASE-CRITICAL, and a config assertion rather than a widget one.
    //
    // `immutable, max-age=1y` is only ever safe for a URL that changes when its
    // bytes do. Flutter's web shell keeps the same filenames on every build, so
    // caching it that way tells every returning browser to keep the app it
    // already has for a year — through a pricing change, through a payment fix,
    // through anything. It shipped once; it is not shipping again.
    //
    // Parsed, not pattern-matched. The first version of this test regexed the
    // file and was fooled by the word "immutable" inside the explanatory
    // comment that lives in the config — a test that reads its subject
    // approximately is a test that will eventually be wrong about it.
    final config =
        jsonDecode(File('firebase.json').readAsStringSync()) as Map;
    // `hosting` became a LIST the day preprod got its own Firebase site
    // (B1.5). Every target must satisfy this rule — asserting only the first
    // would let a second site freeze browsers — so the rules are flattened and
    // each one is checked. A single-target config still parses, so the test
    // does not depend on which shape the file happens to have.
    final rawHosting = config['hosting'];
    final targets = (rawHosting is List ? rawHosting : [rawHosting]).cast<Map>();
    final headers = [
      for (final t in targets) ...(t['headers'] as List).cast<Map>(),
    ];

    test('every hosting target carries the shell rules', () {
      expect(targets, isNotEmpty);
      for (final t in targets) {
        final sources = (t['headers'] as List)
            .cast<Map>()
            .map((r) => r['source'] as String)
            .toSet();
        for (final path in const ['/main.dart.js', '/index.html', '/']) {
          expect(sources, contains(path),
              reason: 'target ${t['target'] ?? 'default'} is missing $path');
        }
      }
    });

    String? cacheFor(String source) {
      for (final rule in headers) {
        if (rule['source'] != source) continue;
        for (final h in (rule['headers'] as List).cast<Map>()) {
          if ((h['key'] as String).toLowerCase() == 'cache-control') {
            return h['value'] as String;
          }
        }
      }
      return null;
    }

    test('the shell files are not served immutable for a year', () {
      for (final path in const [
        '/main.dart.js',
        '/flutter_bootstrap.js',
        // Phase 10: the loader itself was uncovered, and it is mutable by
        // name like the rest of the shell. Left out, it kept a returning
        // browser on last year's bootstrap.
        '/flutter.js',
        '/version.json',
        '/index.html',
        '/',
      ]) {
        final value = cacheFor(path);
        expect(value, isNotNull,
            reason: '$path needs an explicit cache rule');
        expect(value, contains('no-cache'), reason: path);
        expect(value, isNot(contains('immutable')), reason: path);
        expect(value, isNot(contains('max-age=31536000')), reason: path);
      }
    });

    test('no rule broad enough to sweep the shell up again', () {
      // The original defect was not a wrong VALUE — it was a rule broad enough
      // to catch files nobody had reasoned about: `**/*.@(js|css|wasm|json|…)`
      // matched main.dart.js by accident and froze the app for a year.
      for (final rule in headers) {
        final source = rule['source'] as String;
        final values = (rule['headers'] as List)
            .cast<Map>()
            .where((h) => (h['key'] as String).toLowerCase() == 'cache-control')
            .map((h) => h['value'] as String);
        for (final v in values) {
          if (!v.contains('immutable')) continue;
          expect(
            source.contains('js') || source.contains('json'),
            isFalse,
            reason: 'an immutable rule must not be able to match the app '
                'shell: "$source"',
          );
        }
      }
    });

    test('versioned static assets keep their long cache', () {
      // The correction must not have thrown away the performance it was
      // protecting: canvaskit is versioned by the Flutter release, so its URLs
      // really do change when its bytes do.
      final canvaskit = cacheFor('/canvaskit/**');
      expect(canvaskit, isNotNull);
      expect(canvaskit, contains('immutable'));
      expect(canvaskit, contains('max-age=31536000'));
    });
  });
}
