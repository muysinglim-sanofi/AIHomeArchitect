// Batch 2.3 — My Projects library (offline, mocked). Deterministic controller
// tests (in-memory, zero-delay) + widget tests (responsive, no overflow),
// covering the 48 acceptance checks. No backend / Supabase / auth / generation.

import 'dart:io';
import 'dart:typed_data';

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_project.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_experience.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_projects_ios.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _container() => ProviderContainer(
  overrides: [
    pwaRepositoryProvider.overrideWithValue(
      MockPwaExperienceRepository(workDelay: Duration.zero),
    ),
  ],
);

PwaState _state(ProviderContainer c) => c.read(pwaControllerProvider);
PwaController _notifier(ProviderContainer c) =>
    c.read(pwaControllerProvider.notifier);

PwaProjectSnapshot _seed(ProviderContainer c, String title) =>
    _state(c).library.firstWhere((p) => p.title == title);

PwaProjectSnapshot _libProject(ProviderContainer c, String projectId) =>
    _state(c).library.firstWhere((p) => p.projectId == projectId);

AydenImageSource _fakeSource() => AydenImageSource(
  bytes: Uint8List.fromList(const [1, 2, 3, 4]),
  filename: 'room.jpg',
);

Widget _app(ProviderContainer c, Size size) => MediaQuery(
  data: MediaQueryData(disableAnimations: true, size: size),
  child: UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: PwaExperience()),
  ),
);

Future<ProviderContainer> _pumpLibrary(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final c = _container();
  addTearDown(c.dispose);
  _notifier(c).openLibrary();
  await tester.pumpWidget(_app(c, size));
  await tester.pump();
  return c;
}

bool _hasAssetImage(WidgetTester t, Finder within, String asset) => t
    .widgetList<Image>(
      find.descendant(of: within, matching: find.byType(Image)),
    )
    .any(
      (im) =>
          im.image is AssetImage && (im.image as AssetImage).assetName == asset,
    );

void main() {
  // ── PROJECT LIBRARY ────────────────────────────────────────────────────────
  group('project library', () {
    testWidgets('1. My Projects opens from global navigation', (tester) async {
      // From a resumed project in the Architect, the header control opens it.
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = _container();
      addTearDown(c.dispose);
      _notifier(c).openProject(_seed(c, 'Living Room Concept').projectId);
      await tester.pumpWidget(_app(c, const Size(1440, 900)));
      await tester.pump(const Duration(seconds: 3)); // drain architect timers
      expect(find.byKey(const ValueKey('av7-projects-button')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('av7-projects-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pwa-projects')), findsOneWidget);
    });

    testWidgets('2. every persisted project renders, by its ROOM', (
      tester,
    ) async {
      // The card is led by the room now, not the stored project title: a
      // person recognises "Kitchen" under a picture of their kitchen. Each
      // project is still individually present — asserted by key, which is the
      // identity that does not depend on what the card chooses to print.
      final c = await _pumpLibrary(tester);
      final projects = _state(c).visibleProjects;
      expect(projects, isNotEmpty);
      for (final p in projects) {
        expect(
          find.byKey(ValueKey('project-card-${p.projectId}')),
          findsOneWidget,
          reason: p.title,
        );
      }
      for (final room in const ['Living Room', 'Kitchen', 'Home Office']) {
        expect(find.text(room), findsWidgets, reason: room);
      }
    });

    testWidgets('3. project cards use their current Vision image', (
      tester,
    ) async {
      final c = await _pumpLibrary(tester);
      final living = _seed(c, 'Living Room Concept');
      final card = find.byKey(ValueKey('project-card-${living.projectId}'));
      expect(
        _hasAssetImage(tester, card, living.coverVision!.afterAsset),
        isTrue,
      );
    });

    testWidgets('4. the card says what it is, not how it is stored', (
      tester,
    ) async {
      await _pumpLibrary(tester);
      // Room, atmosphere and when it was last touched — each on its own line,
      // over the render. What is NOT there is the point: the dense
      // "3 visions · Updated today" metadata block is gone, and so is every
      // internal identifier.
      expect(find.text('Living Room'), findsWidgets);
      expect(find.text('Ayden Signature'), findsWidgets);
      expect(find.text('Updated today'), findsWidgets);
      expect(find.text('Living Room · Ayden Signature'), findsNothing);
      expect(find.text('3 visions · Updated today'), findsNothing);
      // The vision count survives as a chip — a measure of how far the work
      // has come, which is the one number worth a person's attention.
      expect(find.text('3 visions'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no internal identifier is ever printed', (tester) async {
      final c = await _pumpLibrary(tester);
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' | ');
      for (final p in _state(c).visibleProjects) {
        expect(texts, isNot(contains(p.projectId)));
        for (final v in p.visions) {
          expect(texts, isNot(contains(v.versionId)));
        }
      }
      expect(tester.takeException(), isNull);
    });

    test('5. search filters by title', () {
      final c = _container();
      addTearDown(c.dispose);
      _notifier(c).setLibrarySearch('Transformation');
      final v = _state(c).visibleProjects;
      expect(v.length, 1);
      expect(v.single.title, 'Kitchen Transformation');
    });

    test('6. search filters by Room', () {
      final c = _container();
      addTearDown(c.dispose);
      _notifier(c).setLibrarySearch('master'); // only "Master Bedroom" room
      final v = _state(c).visibleProjects;
      expect(v.length, 1);
      expect(v.single.title, 'Bedroom Retreat');
    });

    test('7. search filters by Atmosphere', () {
      final c = _container();
      addTearDown(c.dispose);
      _notifier(c).setLibrarySearch('japandi'); // only Japandi Calm atmosphere
      final v = _state(c).visibleProjects;
      expect(v.length, 1);
      expect(v.single.title, 'Home Office');
    });

    test('8. sort Recently updated', () {
      final c = _container();
      addTearDown(c.dispose);
      _notifier(c).setLibrarySort(PwaProjectSort.recentlyUpdated);
      expect(_state(c).visibleProjects.first.title, 'Living Room Concept');
    });

    test('9. sort Newest', () {
      final c = _container();
      addTearDown(c.dispose);
      _notifier(c).setLibrarySort(PwaProjectSort.newest);
      expect(_state(c).visibleProjects.first.title, 'Kitchen Transformation');
    });

    test('10. sort Oldest', () {
      final c = _container();
      addTearDown(c.dispose);
      _notifier(c).setLibrarySort(PwaProjectSort.oldest);
      final v = _state(c).visibleProjects;
      expect(v.first.title, 'Home Office');
      expect(v.last.title, 'Kitchen Transformation');
    });

    test('11. sort Name A–Z', () {
      final c = _container();
      addTearDown(c.dispose);
      _notifier(c).setLibrarySort(PwaProjectSort.nameAsc);
      final v = _state(c).visibleProjects;
      expect(v.first.title, 'Bedroom Retreat');
      expect(v.last.title, 'Terrace Escape');
    });
  });

  // ── OPEN PROJECT ───────────────────────────────────────────────────────────
  group('open (resume) project', () {
    late ProviderContainer c;
    late PwaProjectSnapshot kitchen;
    setUp(() {
      c = _container();
      kitchen = _seed(c, 'Kitchen Transformation');
      _notifier(c).openProject(kitchen.projectId);
    });
    tearDown(() => c.dispose());

    test('12. restores its photo (before asset)', () {
      expect(_state(c).project.originalAsset, kitchen.originalImageAsset);
    });
    test('13. Room is restored', () {
      expect(_state(c).selectedRoomId, kitchen.roomId);
    });
    test('14. Atmosphere is restored', () {
      expect(_state(c).selectedAtmosphereId, kitchen.selectedAtmosphereId);
    });
    test('15. all Visions are restored', () {
      expect(_state(c).versions.length, kitchen.visions.length);
    });
    test('16. current Vision is restored', () {
      expect(_state(c).currentVisionId, kitchen.currentVisionId);
    });
    test('17. chat chronology is restored', () {
      expect(_state(c).messages.length, kitchen.messages.length);
      expect(_state(c).messages.first.id, kitchen.messages.first.id);
    });
    test('18. opening creates no Vision', () {
      expect(_state(c).versionCount, kitchen.visionCount);
    });
    test('19. no generation starts', () {
      expect(_state(c).generating, isFalse);
      expect(_state(c).phase, PwaPhase.architect);
    });
  });

  // ── NEW PROJECT ────────────────────────────────────────────────────────────
  group('new project', () {
    late ProviderContainer c;
    setUp(() {
      c = _container();
      // Start from a resumed project so the reset is meaningful.
      _notifier(c).openProject(_seed(c, 'Kitchen Transformation').projectId);
      _notifier(c).newProject();
    });
    tearDown(() => c.dispose());

    test('20. clears the active photo', () {
      expect(_state(c).source, isNull);
    });
    test('21. resets Room to Ayden Decide', () {
      expect(_state(c).selectedRoomId, isNull);
    });
    test('22. resets Atmosphere to Ayden Signature', () {
      expect(_state(c).selectedAtmosphereId, 'ayden_signature');
    });
    test('23. clears active Visions and chat', () {
      expect(_state(c).versions, isEmpty);
      expect(_state(c).messages, isEmpty);
    });
    test('24. preserves saved projects', () {
      final titles = _state(c).library.map((p) => p.title).toSet();
      expect(
        titles,
        containsAll(const ['Kitchen Transformation', 'Home Office']),
      );
      expect(_state(c).library.length, 5);
    });
  });

  // ── PROJECT ACTIONS ────────────────────────────────────────────────────────
  group('project actions', () {
    test('25. rename updates the title', () {
      final c = _container();
      addTearDown(c.dispose);
      final id = _seed(c, 'Living Room Concept').projectId;
      _notifier(c).renameProject(id, 'My Living Space');
      expect(_libProject(c, id).title, 'My Living Space');
    });

    test('26. empty rename is rejected', () {
      final c = _container();
      addTearDown(c.dispose);
      final id = _seed(c, 'Living Room Concept').projectId;
      _notifier(c).renameProject(id, '   ');
      expect(_libProject(c, id).title, 'Living Room Concept');
    });

    test('27. duplicate creates a new projectId', () async {
      final c = _container();
      addTearDown(c.dispose);
      final src = _seed(c, 'Living Room Concept');
      final dup = (await _notifier(c).duplicateProject(src.projectId))!;
      expect(dup.projectId, isNot(src.projectId));
      expect(dup.title, 'Living Room Concept Copy');
      expect(_state(c).library.length, 6);
    });

    test('28. duplicate is independent of its source', () async {
      final c = _container();
      addTearDown(c.dispose);
      final src = _seed(c, 'Living Room Concept');
      final dup = (await _notifier(c).duplicateProject(src.projectId))!;
      _notifier(c).renameProject(dup.projectId, 'Independent Copy');
      expect(_libProject(c, src.projectId).title, 'Living Room Concept');
      expect(_libProject(c, dup.projectId).title, 'Independent Copy');
    });

    testWidgets('29. delete requires confirmation', (tester) async {
      final c = await _pumpLibrary(tester);
      final id = _seed(c, 'Terrace Escape').projectId;
      await tester.tap(find.byKey(ValueKey('project-menu-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      // A confirmation dialog appears; nothing is deleted yet.
      expect(find.byKey(const ValueKey('pwa-delete-dialog')), findsOneWidget);
      expect(_state(c).library.any((p) => p.projectId == id), isTrue);
    });

    test('30. delete removes only the selected project', () {
      final c = _container();
      addTearDown(c.dispose);
      final id = _seed(c, 'Living Room Concept').projectId;
      _notifier(c).deleteProject(id);
      expect(_state(c).library.any((p) => p.projectId == id), isFalse);
      expect(_state(c).library.length, 4);
      expect(_seed(c, 'Home Office').title, 'Home Office'); // others survive
    });
  });

  // ── AUTOMATIC UPDATE AFTER GENERATION ──────────────────────────────────────
  group('automatic project updates', () {
    Future<ProviderContainer> withFirstVision() async {
      final c = _container();
      _notifier(c).setSource(_fakeSource());
      await _notifier(c).generateFirstVision();
      return c;
    }

    test('31. first Vision creates/saves a project', () async {
      final c = await withFirstVision();
      addTearDown(c.dispose);
      final id = _state(c).activeProjectId;
      expect(_state(c).library.any((p) => p.projectId == id), isTrue);
      expect(_libProject(c, id).visionCount, 1);
    });

    test('32. Refine updates the Vision count', () async {
      final c = await withFirstVision();
      addTearDown(c.dispose);
      final id = _state(c).activeProjectId;
      await _notifier(c).applyRefine('Make it warmer');
      expect(_libProject(c, id).visionCount, 2);
    });

    test('33. Atmosphere generation updates the current Vision', () async {
      final c = await withFirstVision();
      addTearDown(c.dispose);
      final id = _state(c).activeProjectId;
      final before = _libProject(c, id).currentVisionId;
      _notifier(c).stageAtmosphere('warm_modern');
      await _notifier(c).applyAtmosphere();
      expect(_libProject(c, id).currentVisionId, isNot(before));
    });

    test('34. Advice creates no Vision', () async {
      final c = await withFirstVision();
      addTearDown(c.dispose);
      final id = _state(c).activeProjectId;
      _notifier(c).sendUserText('What do you think?');
      expect(_state(c).versionCount, 1);
      expect(_libProject(c, id).visionCount, 1);
    });

    test('35. project updatedAt changes after generation', () async {
      final c = await withFirstVision();
      addTearDown(c.dispose);
      final id = _state(c).activeProjectId;
      final before = _libProject(c, id).updatedOrder;
      await _notifier(c).applyRefine('Make it warmer');
      expect(_libProject(c, id).updatedOrder, greaterThan(before));
    });
  });

  // ── RESPONSIVE ─────────────────────────────────────────────────────────────
  group('responsive', () {
    testWidgets('36. desktop shows MORE WORK, not more metadata', (
      tester,
    ) async {
      final c = await _pumpLibrary(tester, size: const Size(1920, 1080));
      expect(tester.takeException(), isNull);
      // Every project still on screen, and the extra width bought columns.
      for (final p in _state(c).visibleProjects) {
        expect(find.byKey(ValueKey('project-card-${p.projectId}')),
            findsOneWidget);
      }
      expect(pwaProjectColumns(1920), greaterThan(pwaProjectColumns(390)));
    });
    testWidgets('37. desktop grid renders at 1536×864', (tester) async {
      final c = await _pumpLibrary(tester, size: const Size(1536, 864));
      expect(tester.takeException(), isNull);
      final kitchen = _seed(c, 'Kitchen Transformation');
      expect(find.byKey(ValueKey('project-card-${kitchen.projectId}')),
          findsOneWidget);
    });
    testWidgets('38. tablet has no overflow at 768×1024', (tester) async {
      await _pumpLibrary(tester, size: const Size(768, 1024));
      expect(tester.takeException(), isNull);
    });
    testWidgets('39. mobile has no overflow at 390×844', (tester) async {
      await _pumpLibrary(tester, size: const Size(390, 844));
      expect(tester.takeException(), isNull);
    });
    testWidgets('40. mobile card is fully tappable → resumes project', (
      tester,
    ) async {
      final c = await _pumpLibrary(tester, size: const Size(390, 844));
      final id = _state(c).visibleProjects.first.projectId;
      await tester.tap(find.byKey(ValueKey('project-card-$id')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3)); // drain architect timers
      expect(_state(c).phase, PwaPhase.architect);
      expect(find.byKey(const ValueKey('av7-global-header')), findsOneWidget);
    });
    testWidgets('41. the order is the controller\'s, with no control to argue '
        'with it', (tester) async {
      // The sort sheet is gone with the search field — see the polish suite.
      // What matters is that the ORDER on screen is still the one the
      // controller produces, which is also the order Home reads.
      final c = await _pumpLibrary(tester, size: const Size(390, 844));
      final expected = _state(c).visibleProjects;
      final onScreen = expected
          .map((p) => tester
              .getRect(find.byKey(ValueKey('project-card-${p.projectId}')))
              .top)
          .toList();
      for (var i = 1; i < onScreen.length; i++) {
        expect(onScreen[i], greaterThanOrEqualTo(onScreen[i - 1]));
      }
      expect(find.byKey(const ValueKey('pwa-sort-button')), findsNothing);
      expect(tester.takeException(), isNull);
    });
    testWidgets('42. New Design Session remains reachable on a phone', (
      tester,
    ) async {
      final c = await _pumpLibrary(tester, size: const Size(390, 844));
      final btn = find.byKey(const ValueKey('pwa-projects-new'));
      // iOS puts this below the grid, so on a phone holding five projects it
      // is genuinely off-screen and not yet built — scroll to it the way a
      // person would rather than asserting it is already there.
      await tester.scrollUntilVisible(btn, 300);
      await tester.pumpAndSettle();
      await tester.tap(btn);
      expect(_state(c).phase, PwaPhase.entry);
      expect(_state(c).hasSource, isFalse);
    });
  });

  // ── ISOLATION & FROZEN SCREENS ─────────────────────────────────────────────
  group('isolation', () {
    const pwaSources = [
      'lib/features/pwa/presentation/pwa_projects_ios.dart',
      'lib/features/pwa/presentation/pwa_projects_screen.dart',
      'lib/features/pwa/domain/pwa_project.dart',
      'lib/features/pwa/application/pwa_controller.dart',
      'lib/features/pwa/data/mock_pwa_experience_repository.dart',
      'lib/features/pwa/data/pwa_experience_repository.dart',
    ];

    // Scan the DEPENDENCY SURFACE (import statements + live instantiation), not
    // prose — the files legitimately name these services in doc-comments to
    // document that they are never used.
    String importsOf(String path) => File(path)
        .readAsStringSync()
        .split('\n')
        .where((l) => l.trimLeft().startsWith('import '))
        .join('\n')
        .toLowerCase();

    // The PWA has its OWN generation seam (`data/pwa_generation_service.dart`)
    // and its own HTTP client behind it. What must never appear in these files
    // is the MOBILE stack — `data/services/generation_service.dart`,
    // StatusService, or a raw network client used directly by state/domain
    // code. The paths below name the mobile files exactly, so the PWA's own
    // seam is not caught by a substring.
    test('43. no backend / network / generation dependency', () {
      for (final path in pwaSources) {
        final imports = importsOf(path);
        for (final banned in const [
          'data/services/generation_service',
          'data/services/status_service',
          'package:http',
          'package:dio',
          'dart:io',
        ]) {
          expect(
            imports.contains(banned),
            isFalse,
            reason: '$path import $banned',
          );
        }
        final code = File(path).readAsStringSync();
        for (final call in const [
          'GenerationService(',
          'StatusService(',
          'SupabaseService(',
        ]) {
          // A preceding letter means this is a DIFFERENT type whose name merely
          // ends in the same word — `PwaMockGenerationService(` is the PWA's own
          // offline seam, not the mobile `GenerationService`.
          expect(
            RegExp('(?<![A-Za-z])${RegExp.escape(call)}').hasMatch(code),
            isFalse,
            reason: '$path uses $call',
          );
        }
      }
    });

    test('44. no Supabase import', () {
      for (final path in pwaSources) {
        expect(importsOf(path).contains('supabase'), isFalse, reason: path);
        expect(
          File(path).readAsStringSync().contains('Supabase.instance'),
          isFalse,
          reason: path,
        );
      }
    });

    test('45. no auth / RevenueCat dependency', () {
      for (final path in pwaSources) {
        final imports = importsOf(path);
        for (final banned in const ['purchases_flutter', 'revenue', 'auth']) {
          expect(
            imports.contains(banned),
            isFalse,
            reason: '$path import $banned',
          );
        }
        expect(
          File(path).readAsStringSync().contains('Purchases.'),
          isFalse,
          reason: path,
        );
      }
    });

    test('46. pubspec.lock present, pins no new source/git dependency', () {
      final lock = File('pubspec.lock');
      expect(lock.existsSync(), isTrue);
      final txt = lock.readAsStringSync();
      expect(RegExp(r'\n\s+source: git').hasMatch(txt), isFalse);
      expect(RegExp(r'\n\s+source: path').hasMatch(txt), isFalse);
    });

    test('47. iOS Runner tree exists (untouched, out of scope)', () {
      expect(Directory('ios/Runner').existsSync(), isTrue);
    });

    testWidgets('48. approved Hero / Fast Path / Architect still render', (
      tester,
    ) async {
      // Entry (Hero + upload showroom) unchanged.
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = _container();
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(c, const Size(1440, 900)));
      await tester.pump();
      // The app opens on the dashboard; Create is one deliberate step away.
      expect(find.byKey(const ValueKey('pwa-home')), findsOneWidget);
      _notifier(c).newProject();
      await tester.pump();
      expect(find.byKey(const ValueKey('pwa-create')), findsOneWidget);
      // Architect (resumed) still renders its workspace + chat panel.
      _notifier(c).openProject(_seed(c, 'Kitchen Transformation').projectId);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const ValueKey('av7-global-header')), findsOneWidget);
      expect(find.byKey(const ValueKey('av7-chat-feed')), findsOneWidget);
    });
  });
}
