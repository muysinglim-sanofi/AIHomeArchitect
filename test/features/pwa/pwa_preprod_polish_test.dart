/// PRE-PRODUCTION POLISH — the four defects reported from the phone, held.
///
///   VISION-WIDTH  every vision renders at the same width, not just the first
///   ATM           a switch waits on the same canvas V1 waits on
///   REFINE        Ayden advises; the user decides
///   AUTH-UI       the Facebook action carries Facebook's mark
///
/// Each group states the defect it is defending against, because every one of
/// them looked like a detail and read, on a phone, as the product being wrong.
library;

import 'package:ai_home_architect/core/l10n/app_localizations.dart';
import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_generation_service.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_image_export.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_mock_generation_service.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_experience.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'dart:typed_data';

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

/// A chat brain the test drives: what the server would answer, and a record of
/// what the controller told it was outstanding.
class _ScriptedChat implements PwaGenerationService {
  _ScriptedChat(this._inner);

  final PwaGenerationService _inner;
  final List<String> pendingSeen = <String>[];
  final List<List<Map<String, String>>> historySeen =
      <List<Map<String, String>>>[];
  final List<String> refined = <String>[];
  final List<bool> refineConfirms = <bool>[];

  /// Holds `generate` open. A render takes about two minutes in the world;
  /// the mock returns in zero, which is exactly the window the waiting state
  /// lives in. Without this the test could never see it.
  Completer<void>? gate;

  /// When set, the next `generate` answers the way the canonical advisor does:
  /// an objection, and no image.
  PwaGenerationAdvisory? advisory;

  /// Answers, in order. Each one stands in for one canonical `/chat` turn.
  final List<PwaChatTurn> script = <PwaChatTurn>[];

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
    final g = gate;
    if (g != null) await g.future;
    final a = advisory;
    if (a != null) throw PwaAdvisoryRaised(a);
    return _inner.generate(intent);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Function.apply((_inner as dynamic).noSuchMethod, [invocation]);
}

ProviderContainer _container({_ScriptedChat? chat}) {
  final repo = MockPwaExperienceRepository(workDelay: Duration.zero);
  return ProviderContainer(
    overrides: [
      pwaRepositoryProvider.overrideWithValue(repo),
      pwaGenerationServiceProvider
          .overrideWithValue(chat ?? PwaMockGenerationService(repo)),
    ],
  );
}

Widget _app(ProviderContainer c, Size size) => MediaQuery(
      data: MediaQueryData(disableAnimations: true, size: size),
      child: UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('en'), Locale('km'), Locale('fr')],
          home: PwaExperience(),
        ),
      ),
    );

/// A session with [visions] completed visions: the first generated, the rest
/// reached by switching atmosphere, exactly as a person reaches them.
Future<ProviderContainer> _sessionWith(
  WidgetTester tester,
  int visions, {
  Size size = const Size(390, 844),
  _ScriptedChat? chat,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final c = _container(chat: chat);
  addTearDown(c.dispose);
  final n = c.read(pwaControllerProvider.notifier);
  n.newProject();
  n.setSource(_source(), origin: PwaImageOrigin.userUpload);
  n.selectRoom('living_room');
  n.selectEntryAtmosphere('warm_modern');
  await n.generateFirstVision();
  const others = ['soft_luxury', 'japandi_calm'];
  for (var i = 1; i < visions; i++) {
    n.stageAtmosphere(others[(i - 1) % others.length]);
    await n.applyAtmosphere();
  }
  await tester.pumpWidget(_app(c, size));
  await tester.pumpAndSettle();
  return c;
}

/// The painted width of every vision render in the thread, top to bottom.
///
/// `skipOffstage: false` is not a shortcut: a thread with three renders is far
/// taller than a 390x844 phone, so at most one vision is ever ON stage. The
/// other two are laid out in the list's cache region — real geometry, just not
/// painted — and that geometry is exactly what this defect is about.
List<double> _visionWidths(WidgetTester tester) => tester
    .widgetList(find.byKey(const ValueKey('pwa-result-vision'), skipOffstage: false))
    .map((w) => tester.getSize(find.byWidget(w, skipOffstage: false)).width)
    .toList();

void main() {
  group('VISION-WIDTH  every vision is the same size as the first', () {
    // THE DEFECT. Vision 1 was laid out at the thread's full width; every
    // later vision was nested inside `_V7AydenGroup`, a Row whose 32pt avatar
    // and 10pt gutter indent everything after it. On a 390pt phone the render
    // lost 42 of 342 points — 12% — and the phone review read it, correctly,
    // as "V1 large, V2/V3 smaller cards".
    testWidgets('VISION-WIDTH-01  V1, V2 and V3 have one width', (tester) async {
      await _sessionWith(tester, 3);
      final widths = _visionWidths(tester);
      expect(widths.length, 3, reason: 'three visions should be on the thread');
      expect(widths[1], widths[0],
          reason: 'V2 must be laid out as wide as V1');
      expect(widths[2], widths[0],
          reason: 'V3 must be laid out as wide as V1');
    });

    testWidgets('VISION-WIDTH-02  switching atmosphere does not shrink it',
        (tester) async {
      final c = await _sessionWith(tester, 1);
      final before = _visionWidths(tester).single;
      final n = c.read(pwaControllerProvider.notifier);
      n.stageAtmosphere('soft_luxury');
      await n.applyAtmosphere();
      await tester.pumpAndSettle();
      final after = _visionWidths(tester);
      expect(after.length, 2);
      expect(after.last, before,
          reason: 'the new vision keeps the geometry of the one before it');
    });

    testWidgets('VISION-WIDTH-03  it holds on a 1440x900 window',
        (tester) async {
      await _sessionWith(tester, 3, size: const Size(1440, 900));
      final widths = _visionWidths(tester);
      expect(widths.length, 3, reason: 'three visions should be on the thread');
      expect(widths.toSet().length, 1,
          reason: 'one width for all three, on desktop too');
    });
  });

  group('ATM  a switch waits the way the first vision waits', () {
    // THE DEFECT. Only `PwaWorkKind.firstVision` drew the full canvas; a
    // switch or a refine drew a small ivory bubble with three dots, appended
    // at the end of a long thread. After choosing an atmosphere in the Full
    // Reveal the person was returned to the conversation with no visible sign
    // that anything had started.
    testWidgets('ATM-01/03  the waiting state is the canvas, not three dots',
        (tester) async {
      final chat = _ScriptedChat(
          PwaMockGenerationService(MockPwaExperienceRepository(workDelay: Duration.zero)));
      final c = await _sessionWith(tester, 1, chat: chat);
      final n = c.read(pwaControllerProvider.notifier);
      chat.gate = Completer<void>();
      n.stageAtmosphere('soft_luxury');
      unawaited(n.applyAtmosphere());
      await tester.pump();
      await tester.pump();
      expect(
          find.byKey(const ValueKey('pwa-working-canvas'), skipOffstage: false),
          findsOneWidget,
          reason: 'a switch waits on the same canvas the first vision uses');
      expect(
          find.byKey(const ValueKey('pwa-working-canvas-indicator'),
              skipOffstage: false),
          findsOneWidget);
      chat.gate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('ATM-02  arriving mid-switch lands ON the work, not above it',
        (tester) async {
      // THE DEFECT. Confirming an atmosphere in the Full Reveal leaves that
      // screen and mounts the Architect with the working canvas already
      // appended at the END of a long thread. `ref.listen` fires on CHANGES,
      // so it does not fire for the build that mounts the screen, and a fresh
      // scroll controller starts at the top - the person landed above the
      // conversation with the work happening off-screen below, and had to
      // scroll to discover that anything was happening at all.
      final chat = _ScriptedChat(PwaMockGenerationService(
          MockPwaExperienceRepository(workDelay: Duration.zero)));
      final c = await _sessionWith(tester, 3, chat: chat);
      final n = c.read(pwaControllerProvider.notifier);
      chat.gate = Completer<void>();
      n.stageAtmosphere('soft_luxury');
      unawaited(n.applyAtmosphere());
      await tester.pump();

      // Mount the Architect FRESH, the way leaving the Reveal does.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_app(c, const Size(390, 844)));
      await tester.pump();
      // Two deferrals and then an animation: the mount's post-frame callback
      // asks for the scroll, the scroll defers one more frame to let the list
      // measure itself, and only then does `animateTo` run. `pumpAndSettle`
      // cannot be used here - the working indicator animates forever by
      // design - so the frames are pumped by hand.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }

      final list = tester.widget<ListView>(
          find.descendant(
              of: find.byKey(const ValueKey('av7-chat-feed')),
              matching: find.byType(ListView)));
      final pos = list.controller!.position;
      expect(pos.maxScrollExtent, greaterThan(0),
          reason: 'a three-vision thread is taller than the phone - otherwise '
              'this test proves nothing');
      expect(pos.pixels, closeTo(pos.maxScrollExtent, 1),
          reason: 'the thread opens ON the work, not above it');
      chat.gate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('ATM-05  the finished switch keeps the expected width',
        (tester) async {
      final c = await _sessionWith(tester, 1);
      final first = _visionWidths(tester).single;
      final n = c.read(pwaControllerProvider.notifier);
      n.stageAtmosphere('japandi_calm');
      await n.applyAtmosphere();
      await tester.pumpAndSettle();
      expect(_visionWidths(tester).last, first);
    });
  });

  group('REFINE  Ayden advises, the user decides', () {
    // THE DEFECT, measured on staging: `classify_intent` answers MIXED for
    // "break the wall on the left and do a living room" — its FALLBACK for an
    // unclassified longer message, at confidence 0.40 — and the canonical
    // chat maps MIXED to should_generate=false. So a real instruction came
    // back as words. And "do it anyway" classifies as CONVERSATION, so the
    // override never resumed anything.
    //
    // The server now re-reads a MIXED line with the refine parser, and
    // recognises an override against the instruction the client says is
    // outstanding. These tests hold the CLIENT half of that contract: what it
    // reports as outstanding, and what it replays.
    testWidgets('REFINE-01  a declined design line stays outstanding',
        (tester) async {
      final repo = MockPwaExperienceRepository(workDelay: Duration.zero);
      final chat = _ScriptedChat(PwaMockGenerationService(repo));
      final c = ProviderContainer(overrides: [
        pwaRepositoryProvider.overrideWithValue(repo),
        pwaGenerationServiceProvider.overrideWithValue(chat),
      ]);
      addTearDown(c.dispose);
      final n = c.read(pwaControllerProvider.notifier);
      n.newProject();
      n.setSource(_source(), origin: PwaImageOrigin.userUpload);
      n.selectRoom('living_room');
      n.selectEntryAtmosphere('warm_modern');
      await n.generateFirstVision();

      // Turn 1: Ayden answers with words, and says the line carried change
      // intent (MIXED). Nothing was outstanding when it was asked.
      chat.script.add(const PwaChatTurn(
        aiMessage: "I wouldn't break the wall.",
        shouldGenerate: false,
        intent: 'mixed',
      ));
      n.sendUserText('break the wall on the left and create a living room');
      await tester.pump(const Duration(milliseconds: 50));
      expect(chat.pendingSeen.single, '',
          reason: 'nothing was outstanding on the first turn');

      // Turn 2: whatever the person says next, the outstanding instruction
      // travels with it — that is what lets the server recognise an override.
      chat.script.add(const PwaChatTurn(
        aiMessage: '',
        shouldGenerate: false,
        intent: 'conversation',
      ));
      n.sendUserText('do it anyway');
      await tester.pump(const Duration(milliseconds: 50));
      expect(chat.pendingSeen.last,
          'break the wall on the left and create a living room',
          reason: 'the declined instruction must be offered for confirmation');

      // And the PRIOR conversation travels with it: roles, oldest first,
      // ENDING WITH AYDEN'S TURN — the one the reply answers. The line being
      // sent is not in it: the canonical resolvers stop at a trailing user
      // turn (measured: "yes" resolves to nothing with it, to GENERATE
      // without it), and mobile's shape, which includes it, is why they never
      // fired there either.
      final sent = chat.historySeen.last;
      expect(sent.last, {'role': 'ai', 'content': "I wouldn't break the wall."},
          reason: 'the turn being answered is the last entry');
      expect(sent.any((m) => m['content'] == 'do it anyway'), isFalse,
          reason: 'the line being sent is not its own history');
      expect(
          sent.any((m) =>
              m['content'] ==
              'break the wall on the left and create a living room'),
          isTrue,
          reason: 'the pending request has to be IN the thread that is judged');
    });

    testWidgets('REFINE-02  an override replays the ORIGINAL line, confirmed',
        (tester) async {
      final repo = MockPwaExperienceRepository(workDelay: Duration.zero);
      final chat = _ScriptedChat(PwaMockGenerationService(repo));
      final c = ProviderContainer(overrides: [
        pwaRepositoryProvider.overrideWithValue(repo),
        pwaGenerationServiceProvider.overrideWithValue(chat),
      ]);
      addTearDown(c.dispose);
      final n = c.read(pwaControllerProvider.notifier);
      n.newProject();
      n.setSource(_source(), origin: PwaImageOrigin.userUpload);
      n.selectRoom('living_room');
      n.selectEntryAtmosphere('warm_modern');
      await n.generateFirstVision();

      chat.script.add(const PwaChatTurn(
        aiMessage: 'That would change the layout a great deal.',
        shouldGenerate: false,
        intent: 'mixed',
      ));
      n.sendUserText('break the wall on the left');
      await tester.pump(const Duration(milliseconds: 50));

      // The server recognised the confirmation and named what it confirms.
      chat.script.add(const PwaChatTurn(
        aiMessage: '',
        shouldGenerate: true,
        intent: 'conversation',
        overrideInstruction: 'break the wall on the left',
      ));
      n.sendUserText('do it anyway');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(chat.refined, ['break the wall on the left'],
          reason: 'the instruction is what renders, never the confirmation');
      expect(chat.refineConfirms, [true],
          reason: 'the advisor has already been read — it must not re-object');
    });

    testWidgets('REFINE-04  after a RED warning, "do it anyway" runs the original',
        (tester) async {
      // The owner's rule, set after the phone test: Ayden advises, the user
      // decides — on RED too. A red verdict now leaves the person's own
      // sentence outstanding, verbatim, and the server's resolution of "do it
      // anyway" replays exactly that sentence, confirmed.
      final repo = MockPwaExperienceRepository(workDelay: Duration.zero);
      final chat = _ScriptedChat(PwaMockGenerationService(repo));
      final c = ProviderContainer(overrides: [
        pwaRepositoryProvider.overrideWithValue(repo),
        pwaGenerationServiceProvider.overrideWithValue(chat),
      ]);
      addTearDown(c.dispose);
      final n = c.read(pwaControllerProvider.notifier);
      n.newProject();
      n.setSource(_source(), origin: PwaImageOrigin.userUpload);
      n.selectRoom('living_room');
      n.selectEntryAtmosphere('warm_modern');
      await n.generateFirstVision();

      chat.advisory = const PwaGenerationAdvisory(
          verdict: 'red', message: "As your architect, I don't recommend it.");
      await n.applyRefine('break the wall on the left');
      await tester.pump(const Duration(milliseconds: 50));
      chat.advisory = null;

      chat.script.add(const PwaChatTurn(
        aiMessage: '',
        shouldGenerate: true,
        intent: 'conversation',
        overrideInstruction: 'break the wall on the left',
      ));
      n.sendUserText('do it anyway');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(chat.pendingSeen.last, 'break the wall on the left',
          reason: 'a red verdict leaves the original outstanding, verbatim');
      expect(chat.refined,
          ['break the wall on the left', 'break the wall on the left']);
      expect(chat.refineConfirms, [false, true],
          reason: 'the second pass is the decision, not another question');
    });

    testWidgets('REFINE-05  a plain question leaves nothing outstanding',
        (tester) async {
      final repo = MockPwaExperienceRepository(workDelay: Duration.zero);
      final chat = _ScriptedChat(PwaMockGenerationService(repo));
      final c = ProviderContainer(overrides: [
        pwaRepositoryProvider.overrideWithValue(repo),
        pwaGenerationServiceProvider.overrideWithValue(chat),
      ]);
      addTearDown(c.dispose);
      final n = c.read(pwaControllerProvider.notifier);
      n.newProject();
      n.setSource(_source(), origin: PwaImageOrigin.userUpload);
      n.selectRoom('living_room');
      n.selectEntryAtmosphere('warm_modern');
      await n.generateFirstVision();

      chat.script.add(const PwaChatTurn(
        aiMessage: 'It reads calm and warm.',
        shouldGenerate: false,
        intent: 'design_discussion',
      ));
      n.sendUserText('what do you think?');
      await tester.pump(const Duration(milliseconds: 50));

      chat.script.add(const PwaChatTurn(
          aiMessage: '', shouldGenerate: false, intent: 'conversation'));
      n.sendUserText('yes');
      await tester.pump(const Duration(milliseconds: 50));
      expect(chat.pendingSeen.last, '',
          reason: 'a question is not an instruction, so "yes" can confirm '
              'nothing and cannot buy an image');
    });
  });

  group('EXPORT  a vision leaves as the image itself', () {
    test('SHARE-03  the file is named after the vision, not a uuid', () {
      expect(
        pwaVisionFileName(
            visionNumber: 2,
            roomLabel: 'Living Room',
            atmosphereLabel: 'Warm Modern'),
        'Ayden-Studio-Living-Room-Warm-Modern-v2.jpg',
      );
      // Missing parts simply drop out; the name never contains a stray dash.
      expect(pwaVisionFileName(visionNumber: 1), 'Ayden-Studio-v1.jpg');
    });

    test('SHARE-05  a sheet that refuses still saves the file', () {
      // Measured on preprod: desktop Chrome answers `canShare({files}) == true`
      // and its sheet is the Windows share flyout — apps to send to, no way to
      // save. SAVE now downloads on a pointer platform; this holds the rest of
      // the rule, for a touch platform whose sheet is offered and does not work.
      expect(pwaSheetAnsweredSave(PwaExportOutcome.unsupported), isFalse,
          reason: 'an unusable sheet leaves the download still to run');
      expect(pwaSheetAnsweredSave(PwaExportOutcome.failed), isFalse,
          reason: 'a failed sheet is not a saved file');
    });

    test('SHARE-06  a sheet the person closed is an answer, not a fallback',
        () {
      // The one outcome that must NOT fall through: they saw the sheet and
      // chose to close it. Downloading anyway would be the app overruling them.
      expect(pwaSheetAnsweredSave(PwaExportOutcome.cancelled), isTrue);
      expect(pwaSheetAnsweredSave(PwaExportOutcome.done), isTrue);
    });

    test('SHARE-04  with no browser support nothing is claimed', () async {
      const e = PwaUnsupportedImageExporter();
      expect(e.canShareFiles, isFalse);
      expect(await e.share(url: 'u', fileName: 'f.jpg', title: 't'),
          PwaExportOutcome.unsupported);
      expect(await e.save(url: 'u', fileName: 'f.jpg'),
          PwaExportOutcome.unsupported);
    });
  });
}
