// Batch 2.3 FINAL POLISH — seed coherence, draft clarity, badge simplification,
// three-dot menu polish, search-result context / zero state, deep duplication
// integrity, and reference-PNG independence. Deterministic + offline.

import 'dart:io';
import 'dart:typed_data';

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_project.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_experience.dart';
import 'package:flutter/gestures.dart';
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
PwaProjectSnapshot _lib(ProviderContainer c, String id) =>
    _state(c).library.firstWhere((p) => p.projectId == id);

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
  bool withDraft = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final c = _container();
  addTearDown(c.dispose);
  if (withDraft) _notifier(c).setSource(_fakeSource());
  _notifier(c).openLibrary();
  await tester.pumpWidget(_app(c, size));
  await tester.pump();
  return c;
}

void main() {
  // ── SEED COHERENCE (§16) ───────────────────────────────────────────────────
  group('seed coherence', () {
    late ProviderContainer c;
    setUp(() => c = _container());
    tearDown(() => c.dispose());

    test('1. exactly five seeded projects', () {
      expect(_state(c).library.length, 5);
    });
    test('2. every seed has a unique projectId', () {
      final ids = _state(c).library.map((p) => p.projectId).toSet();
      expect(ids.length, 5);
    });
    test('3. every seed uses a DISTINCT cover asset', () {
      final covers = _state(
        c,
      ).library.map((p) => p.coverVision!.afterAsset).toSet();
      expect(covers.length, 5);
    });
    test('4. Living Room Concept → living-room cover', () {
      expect(
        _seed(c, 'Living Room Concept').coverVision!.afterAsset,
        'assets/showcase/living_after.jpg',
      );
    });
    test('5. Bedroom Retreat → private-suite/bedroom cover', () {
      expect(
        _seed(c, 'Bedroom Retreat').coverVision!.afterAsset,
        'assets/showcase/smallspace_after.jpg',
      );
    });
    test('6. Kitchen Transformation → kitchen cover', () {
      expect(
        _seed(c, 'Kitchen Transformation').coverVision!.afterAsset,
        'assets/showcase/apartment_after.jpg',
      );
    });
    test('7. Terrace Escape → outdoor cover', () {
      expect(
        _seed(c, 'Terrace Escape').coverVision!.afterAsset,
        'assets/showcase/villa_after.jpg',
      );
    });
    test('8. Home Office cover is NOT an unrelated exterior', () {
      final cover = _seed(c, 'Home Office').coverVision!.afterAsset;
      expect(cover, isNot('assets/showcase/facade_after.jpg'));
      expect(cover, isNot('assets/showcase/villa_after.jpg'));
      expect(cover, 'assets/atmospheres/ftue/ftue_nordic_warmth.jpg');
    });
    test('9. Room labels match each project', () {
      expect(_seed(c, 'Kitchen Transformation').roomLabel, 'Kitchen');
      expect(_seed(c, 'Terrace Escape').roomLabel, 'Terrace');
      expect(_seed(c, 'Home Office').roomLabel, 'Home Office');
    });
    test('10. Atmosphere labels match each project', () {
      expect(_seed(c, 'Bedroom Retreat').atmosphereLabel, 'Soft Luxury');
      expect(_seed(c, 'Kitchen Transformation').atmosphereLabel, 'Warm Modern');
      expect(_seed(c, 'Home Office').atmosphereLabel, 'Japandi Calm');
    });

    testWidgets('11/12. no normal project shows New or Refined', (
      tester,
    ) async {
      await _pumpLibrary(tester);
      expect(find.text('New'), findsNothing);
      expect(find.text('Refined'), findsNothing);
    });
  });

  // ── DRAFT (§17) ────────────────────────────────────────────────────────────
  group('draft card', () {
    testWidgets(
      'Step 6A: a pre-Generate creation shows NO Draft card in My Projects',
      (tester) async {
        await _pumpLibrary(tester, withDraft: true);
        // The synthetic Draft card was removed: before Generate there is no
        // project, hence no card (no "Continue setup", no Draft badge).
        expect(find.byKey(const ValueKey('pwa-draft-card')), findsNothing);
        expect(find.text('Draft · Continue setup'), findsNothing);
      },
    );
    testWidgets('17. completed active project shows no Draft badge', (
      tester,
    ) async {
      await _pumpLibrary(tester); // seeds only, no active draft
      expect(find.text('Draft'), findsNothing);
    });
    test(
      '18. first Vision converts the draft into an active project',
      () async {
        final c = _container();
        addTearDown(c.dispose);
        _notifier(c).setSource(_fakeSource());
        expect(_state(c).activeDraft, isNotNull); // draft before generation
        await _notifier(c).generateFirstVision();
        expect(_state(c).activeDraft, isNull); // no longer a draft
        final id = _state(c).activeProjectId;
        expect(_lib(c, id).status, PwaProjectStatus.active);
      },
    );
    test('19. automatic title is Room-based and meaningful', () async {
      final c = _container();
      addTearDown(c.dispose);
      _notifier(c).setSource(_fakeSource());
      _notifier(c).selectRoom('livingRoom');
      await _notifier(c).generateFirstVision();
      expect(_lib(c, _state(c).activeProjectId).title, 'Living Room Concept');

      final c2 = _container();
      addTearDown(c2.dispose);
      _notifier(c2).setSource(_fakeSource()); // Ayden Decide (no room)
      await _notifier(c2).generateFirstVision();
      expect(
        _lib(c2, _state(c2).activeProjectId).title,
        'Open-plan Living Space',
      );
    });
  });

  // ── SEARCH CONTEXT + ZERO STATE (§18) ──────────────────────────────────────
  // ── The search SURFACE is gone; the search STATE is not (Phase 7) ─────────
  //
  // The old Projects screen carried a search field, a sort menu, a
  // "3 projects found for “room”" context row, a Clear-search control and a
  // separate search-empty state. Seven tests here described that apparatus.
  //
  // iOS's Projects has none of it — a title, a count, a grid, one button — and
  // the brief names "a dense project database" as the thing to avoid. So the
  // controls went and the CONTROLLER did not: `librarySearch` and
  // `librarySort` still filter and order `visibleProjects` exactly as before,
  // which is what the tests below assert. Putting a field back is a few lines.
  group('search and sort survive as state', () {
    test('a query still filters the canonical list', () {
      final c = _container();
      addTearDown(c.dispose);
      _notifier(c).setLibrarySearch('kitchen');
      final v = _state(c).visibleProjects;
      expect(v, hasLength(1));
      expect(v.single.title, 'Kitchen Transformation');
      _notifier(c).setLibrarySearch('');
      expect(_state(c).visibleProjects.length, greaterThan(1));
    });

    test('filtering and sorting still apply together', () {
      final c = _container();
      addTearDown(c.dispose);
      _notifier(c).setLibrarySearch('room');
      _notifier(c).setLibrarySort(PwaProjectSort.nameAsc);
      expect(_state(c).visibleProjects.first.title, 'Bedroom Retreat');
    });

    testWidgets('and the screen shows neither control', (tester) async {
      await _pumpLibrary(tester);
      expect(find.byKey(const ValueKey('pwa-search-context')), findsNothing);
      expect(find.byKey(const ValueKey('pwa-sort-button')), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });


  group('three-dot menu', () {
    testWidgets('33/34. ≥44×44 target, disc glyph much smaller', (
      tester,
    ) async {
      final c = await _pumpLibrary(tester);
      final key = ValueKey(
        'project-menu-${_seed(c, 'Living Room Concept').projectId}',
      );
      final size = tester.getSize(find.byKey(key));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(key),
          matching: find.byIcon(Icons.more_vert_rounded),
        ),
      );
      expect(icon.size!, lessThan(24)); // glyph ≪ 44 target
    });
    testWidgets('the menu stays legible on the cover, hover or not', (
      tester,
    ) async {
      // It used to sit at 60% until the pointer entered the card. That was
      // safe on the old dark card; the Phase 7 card is the person's own
      // render, and dimming a control to 60% over a photograph nobody chose is
      // the same contrast bet this alignment has been removing everywhere.
      final c = await _pumpLibrary(tester);
      final card = find.byKey(
        ValueKey('project-card-${_seed(c, 'Living Room Concept').projectId}'),
      );
      final menuKey = ValueKey(
        'project-menu-${_seed(c, 'Living Room Concept').projectId}',
      );
      AnimatedOpacity ao() => tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.byKey(menuKey),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(ao().opacity, 1.0);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(card));
      await tester.pump();
      expect(ao().opacity, 1.0);
    });
    testWidgets('37. mobile menu is visible (no reduced-opacity wrapper)', (
      tester,
    ) async {
      final c = await _pumpLibrary(tester, size: const Size(390, 844));
      final menuKey = ValueKey(
        'project-menu-${_state(c).visibleProjects.first.projectId}',
      );
      expect(find.byKey(menuKey), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(menuKey),
          matching: find.byType(AnimatedOpacity),
        ),
        findsNothing,
      );
    });
    testWidgets('38. Rename/Duplicate/Delete remain functional', (
      tester,
    ) async {
      final c = await _pumpLibrary(tester);
      final id = _seed(c, 'Terrace Escape').projectId;
      await tester.tap(find.byKey(ValueKey('project-menu-$id')));
      await tester.pumpAndSettle();
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Duplicate'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });
  });

  // ── DEEP DUPLICATION (§20) ─────────────────────────────────────────────────
  group('deep duplication', () {
    // A project whose 2nd vision carries lineage (parent) AND a sourceMessageId.
    Future<ProviderContainer> withLineage() async {
      final c = _container();
      _notifier(c).setSource(_fakeSource());
      await _notifier(c).generateFirstVision(); // v1
      _notifier(c).stageAtmosphere('warm_modern');
      await _notifier(
        c,
      ).applyAtmosphere(); // v2 (parent=v1, sourceMessageId set)
      return c;
    }

    test(
      '39-51. full independent remap (ids, projectId, lineage, refs)',
      () async {
        final c = await withLineage();
        addTearDown(c.dispose);
        final src = _lib(c, _state(c).activeProjectId);
        final dup = (await _notifier(c).duplicateProject(src.projectId))!;

        final srcV = src.visions.map((v) => v.versionId).toSet();
        final srcM = src.messages.map((m) => m.id).toSet();

        // 39 new projectId
        expect(dup.projectId, isNot(src.projectId));
        // 40/41/49/51 every vision new id, new projectId, no old id / source pid
        for (final v in dup.visions) {
          expect(srcV.contains(v.versionId), isFalse);
          expect(v.projectId, dup.projectId);
          expect(v.projectId, isNot(src.projectId));
        }
        // 42/50 every message new id, no old id
        for (final m in dup.messages) {
          expect(srcM.contains(m.id), isFalse);
        }
        // 43/44 current + cover remapped
        expect(dup.currentVisionId, isNot(src.currentVisionId));
        expect(
          dup.visions.map((v) => v.versionId),
          contains(dup.currentVisionId),
        );
        expect(dup.coverVisionId, isNot(src.coverVisionId));
        // 45 lineage remapped: child.parent points at the dup's own first vision
        final child = dup.visions.firstWhere((v) => v.parentVersionId != null);
        expect(child.parentVersionId, dup.visions.first.versionId);
        // 46 sourceMessageId remapped into the dup message id space
        expect(child.sourceMessageId, isNotNull);
        expect(srcM.contains(child.sourceMessageId), isFalse);
        expect(dup.messages.map((m) => m.id), contains(child.sourceMessageId));
        // 47/48 message→vision references remapped
        for (final m in dup.messages.where((m) => m.visionId != null)) {
          expect(srcV.contains(m.visionId), isFalse);
          expect(dup.visions.map((v) => v.versionId), contains(m.visionId));
        }
      },
    );

    test(
      '52-54. collections independent; edits do not leak either way',
      () async {
        final c = _container();
        addTearDown(c.dispose);
        final src = _seed(c, 'Living Room Concept');
        final dup = (await _notifier(c).duplicateProject(src.projectId))!;
        expect(identical(dup.visions, src.visions), isFalse);
        expect(identical(dup.messages, src.messages), isFalse);
        _notifier(c).renameProject(dup.projectId, 'Edited Copy');
        expect(
          _lib(c, src.projectId).title,
          'Living Room Concept',
        ); // src intact
        _notifier(c).renameProject(src.projectId, 'Edited Source');
        expect(_lib(c, dup.projectId).title, 'Edited Copy'); // dup intact
      },
    );

    test('55/56. deterministic, collision-free copy titles', () async {
      final c = _container();
      addTearDown(c.dispose);
      final id = _seed(c, 'Living Room Concept').projectId;
      final d1 = (await _notifier(c).duplicateProject(id))!;
      final d2 = (await _notifier(c).duplicateProject(id))!;
      expect(d1.title, 'Living Room Concept Copy');
      expect(d2.title, 'Living Room Concept Copy 2');
      // Duplicating a copy strips the suffix (never "Copy Copy").
      final d3 = (await _notifier(c).duplicateProject(d1.projectId))!;
      expect(d3.title, 'Living Room Concept Copy 3');
    });

    test(
      '57-60. duplicate opens in Architect, coherent, current vision, no gen',
      () async {
        final c = _container();
        addTearDown(c.dispose);
        final dup = (await _notifier(
          c,
        ).duplicateProject(_seed(c, 'Kitchen Transformation').projectId))!;
        _notifier(c).openProject(dup.projectId);
        expect(_state(c).phase, PwaPhase.architect); // 57
        expect(_state(c).versions.length, dup.visions.length); // 58 chronology
        expect(_state(c).messages.length, dup.messages.length);
        expect(_state(c).previewedVision!.versionId, dup.currentVisionId); // 59
        expect(_state(c).generating, isFalse); // 60
      },
    );
  });

  // ── REFERENCES (§21) ───────────────────────────────────────────────────────
  group('reference PNG independence', () {
    test('61/65. no runtime PWA code LOADS a references/ path', () {
      // A quoted string literal is an asset/file path (runtime access); backtick
      // doc-comments that merely cite a design reference are allowed.
      final dir = Directory('lib/features/pwa');
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        expect(src.contains("'references/"), isFalse, reason: f.path);
        expect(src.contains('"references/'), isFalse, reason: f.path);
      }
    });
    test('62. pubspec production assets exclude references/', () {
      final assets = File('pubspec.yaml')
          .readAsLinesSync()
          .where((l) => l.trimLeft().startsWith('- '))
          .join('\n');
      expect(assets.contains('references/'), isFalse);
    });
  });

  // ── RESPONSIVE (§22) ───────────────────────────────────────────────────────
  group('responsive (no overflow)', () {
    for (final size in const [
      Size(1920, 1080),
      Size(1536, 864),
      Size(768, 1024),
      Size(430, 932),
      Size(390, 844),
    ]) {
      testWidgets('${size.width.toInt()}×${size.height.toInt()} library', (
        tester,
      ) async {
        await _pumpLibrary(tester, size: size);
        expect(tester.takeException(), isNull);
      });
      testWidgets('${size.width.toInt()}×${size.height.toInt()} with draft', (
        tester,
      ) async {
        await _pumpLibrary(tester, size: size, withDraft: true);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
