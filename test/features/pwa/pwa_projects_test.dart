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

    testWidgets('2. seeded mock projects render', (tester) async {
      await _pumpLibrary(tester);
      for (final title in const [
        'Living Room Concept',
        'Bedroom Retreat',
        'Kitchen Transformation',
        'Terrace Escape',
        'Home Office',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
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

    testWidgets('4. project metadata is correct', (tester) async {
      await _pumpLibrary(tester);
      expect(find.text('Living Room · Ayden Signature'), findsOneWidget);
      expect(find.text('3 visions · Updated today'), findsOneWidget);
      expect(
        find.text('1 vision · 2 weeks ago'),
        findsOneWidget,
      ); // Home Office
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

    test('27. duplicate creates a new projectId', () {
      final c = _container();
      addTearDown(c.dispose);
      final src = _seed(c, 'Living Room Concept');
      final dup = _notifier(c).duplicateProject(src.projectId)!;
      expect(dup.projectId, isNot(src.projectId));
      expect(dup.title, 'Living Room Concept Copy');
      expect(_state(c).library.length, 6);
    });

    test('28. duplicate is independent of its source', () {
      final c = _container();
      addTearDown(c.dispose);
      final src = _seed(c, 'Living Room Concept');
      final dup = _notifier(c).duplicateProject(src.projectId)!;
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
    testWidgets('36. desktop grid renders at 1920×1080', (tester) async {
      await _pumpLibrary(tester, size: const Size(1920, 1080));
      expect(tester.takeException(), isNull);
      expect(find.text('Living Room Concept'), findsOneWidget);
    });
    testWidgets('37. desktop grid renders at 1536×864', (tester) async {
      await _pumpLibrary(tester, size: const Size(1536, 864));
      expect(tester.takeException(), isNull);
      expect(find.text('Kitchen Transformation'), findsOneWidget);
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
    testWidgets('41. mobile sort sheet opens', (tester) async {
      await _pumpLibrary(tester, size: const Size(390, 844));
      await tester.tap(find.byKey(const ValueKey('pwa-sort-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pwa-sort-sheet')), findsOneWidget);
    });
    testWidgets('42. mobile New project remains reachable', (tester) async {
      final c = await _pumpLibrary(tester, size: const Size(390, 844));
      final btn = find.byTooltip('New project');
      expect(btn, findsOneWidget);
      await tester.tap(btn); // fires newProject without mounting the cinematic
      expect(_state(c).phase, PwaPhase.entry);
    });
  });

  // ── ISOLATION & FROZEN SCREENS ─────────────────────────────────────────────
  group('isolation', () {
    const pwaSources = [
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

    test('43. no backend / network / generation dependency', () {
      for (final path in pwaSources) {
        final imports = importsOf(path);
        for (final banned in const [
          'generation_service',
          'status_service',
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
          expect(code.contains(call), isFalse, reason: '$path uses $call');
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
      expect(find.text('Upload your room'), findsOneWidget);
      // Architect (resumed) still renders its workspace + chat panel.
      _notifier(c).openProject(_seed(c, 'Kitchen Transformation').projectId);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const ValueKey('av7-global-header')), findsOneWidget);
      expect(find.byKey(const ValueKey('av7-chat-panel')), findsOneWidget);
    });
  });
}
