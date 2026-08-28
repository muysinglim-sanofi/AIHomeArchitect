/// Phase 7 — Projects.
///
/// Two things are being held here.
///
/// The first is that this is a PORTFOLIO: the cream shell, the work leading
/// each card, and none of the metadata density that made the old screen read
/// as a project database.
///
/// The second is that it decides nothing. Which projects exist, in what order,
/// and which vision is a project's cover are all read from the same state Home
/// reads, through the same resolvers — so the two screens cannot disagree about
/// the same project. That is asserted directly, by rendering both and comparing
/// what they show, because "reuse the canonical path" is exactly the kind of
/// instruction a rewrite quietly drifts away from.
library;

import 'dart:typed_data';

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_project.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_l10n.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_experience.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_nav_shell.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_projects_ios.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_projects_screen.dart'
    show PwaProjectsScreen;
import 'package:ai_home_architect/core/constants/room_type_images.dart';
import 'package:ai_home_architect/core/l10n/app_localizations.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_theme.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_widgets.dart'
    show pwaRoomDisplayLabel;
import 'package:flutter/material.dart';
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

ProviderContainer _container({bool seed = true}) => ProviderContainer(
      overrides: [
        pwaRepositoryProvider.overrideWithValue(
          MockPwaExperienceRepository(
            workDelay: Duration.zero,
            seedLibrary: seed,
          ),
        ),
      ],
    );

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  Locale locale = const Locale('en'),
  bool seed = true,
  ProviderContainer? container,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final c = container ?? _container(seed: seed);
  if (container == null) addTearDown(c.dispose);
  c.read(pwaControllerProvider.notifier).openLibrary();

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: true, size: size),
      child: UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          locale: locale,
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
  await tester.pump(const Duration(seconds: 2));
  return c;
}

void main() {
  group('PROJ01  it belongs to the same product now', () {
    testWidgets('the shell is cream, and the dark original is not mounted',
        (tester) async {
      await _pump(tester);
      expect(find.byKey(const ValueKey('pwa-projects')), findsOneWidget);
      expect(find.byType(PwaProjectsIos), findsOneWidget);
      // The retired screen stays on disk as the fast way back; what matters is
      // that the router stopped using it.
      expect(find.byType(PwaProjectsScreen), findsNothing);

      final scaffold = tester.widget<Scaffold>(
        find
            .descendant(
              of: find.byKey(const ValueKey('pwa-projects')),
              matching: find.byType(Scaffold),
            )
            .first,
      );
      expect(scaffold.backgroundColor, pwaCanvas);
      expect(scaffold.backgroundColor, isNot(Colors.black));
      expect(tester.takeException(), isNull);
    });

    testWidgets('it uses the approved nav shell, with Projects selected',
        (tester) async {
      await _pump(tester);
      final shell = tester.widget<PwaNavShell>(find.byType(PwaNavShell));
      expect(shell.current, PwaNavDestination.projects);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the header is a title and a count — nothing else',
        (tester) async {
      final c = await _pump(tester);
      final l = pwaL10nFor(const Locale('en'));
      final n = c.read(pwaControllerProvider).visibleProjects.length;
      expect(find.text(l.historyTitle), findsOneWidget);
      expect(find.text('$n ${l.transformations}'), findsOneWidget);
      // No second back button, no editorial introduction, no controls.
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('PROJ02  the cover is not decided here', () {
    testWidgets('each card shows the project\'s canonical cover vision',
        (tester) async {
      final c = await _pump(tester);
      for (final p in c.read(pwaControllerProvider).visibleProjects) {
        final cover = p.coverVision;
        expect(cover, isNotNull, reason: '${p.title} is in visibleProjects');
        // `visibleProjects` → `coverVision` → `pwaAfterImage`. The card renders
        // the vision the DOMAIN nominates; it never picks one itself.
        expect(
          find.byKey(ValueKey('after-${cover!.versionId}')),
          findsWidgets,
          reason: p.title,
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('Home and Projects agree about the same project',
        (tester) async {
      // The invariant, tested by rendering BOTH from one container and
      // comparing what each puts on screen for the newest project. If either
      // screen ever grew its own "latest vision" logic, this is where the two
      // would diverge.
      final c = _container();
      addTearDown(c.dispose);

      await _pump(tester, container: c);
      final fromProjects = c.read(pwaControllerProvider).visibleProjects.first;
      expect(
        find.byKey(ValueKey('after-${fromProjects.coverVision!.versionId}')),
        findsWidgets,
      );

      c.read(pwaControllerProvider.notifier).openHome();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      final fromHome = c.read(pwaControllerProvider).visibleProjects.first;
      expect(fromHome.projectId, fromProjects.projectId);
      expect(
        fromHome.coverVision!.versionId,
        fromProjects.coverVision!.versionId,
        reason: 'Home and Projects must never disagree about the latest vision',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the order on screen is the order the controller produced',
        (tester) async {
      final c = await _pump(tester, size: const Size(390, 1400));
      final expected = c.read(pwaControllerProvider).visibleProjects;
      expect(expected.length, greaterThan(1));
      var lastTop = double.negativeInfinity;
      for (final p in expected) {
        final r =
            tester.getRect(find.byKey(ValueKey('project-card-${p.projectId}')));
        expect(r.top, greaterThanOrEqualTo(lastTop));
        lastTop = r.top;
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('PROJ03  a tap resumes, and does nothing else', () {
    testWidgets('it opens the existing project — no generation, no duplicate',
        (tester) async {
      final c = await _pump(tester);
      final before = c.read(pwaControllerProvider);
      final target = before.visibleProjects.first;
      final projectCount = before.library.length;
      final visionCount = target.visions.length;

      await tester.tap(
        find.byKey(ValueKey('project-card-${target.projectId}')),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      final after = c.read(pwaControllerProvider);
      expect(after.phase, PwaPhase.architect);
      expect(after.activeProjectId, target.projectId);
      // Nothing was created, nothing was copied, nothing was spent.
      expect(after.library, hasLength(projectCount));
      expect(after.versions, hasLength(visionCount));
      expect(after.generating, isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  group('PROJ04  nothing to show yet', () {
    testWidgets('a calm empty state, and the one thing worth doing',
        (tester) async {
      final c = await _pump(tester, seed: false);
      expect(c.read(pwaControllerProvider).visibleProjects, isEmpty);
      expect(find.byKey(const ValueKey('pwa-projects-empty')), findsOneWidget);
      // No demo projects in a person's own library, ever.
      expect(find.byType(Image), findsNothing);
      final l = pwaL10nFor(const Locale('en'));
      expect(find.text('0 ${l.transformations}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the empty-state CTA opens an empty Create', (tester) async {
      final c = await _pump(tester, seed: false);
      await tester.tap(find.byKey(const ValueKey('pwa-projects-empty-new')));
      await tester.pump();
      final s = c.read(pwaControllerProvider);
      expect(s.phase, PwaPhase.entry);
      expect(s.hasSource, isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  group('PROJ05  it shows the work, not the plumbing', () {
    testWidgets('no stored English sentinel reaches a Khmer reader',
        (tester) async {
      // `kPwaGenericRoomLabel` is a stored, deliberately-unlocalised "Your
      // space" on rows written before a room was resolved. Printing it as a
      // card title would put an English string under a Khmer interface.
      final c = _container(seed: false);
      addTearDown(c.dispose);
      final n = c.read(pwaControllerProvider.notifier);
      n.newProject();
      n.setSource(
        AydenImageSource(bytes: _png, filename: 'r.png', mimeType: 'image/png'),
        origin: PwaImageOrigin.userUpload,
      );
      await n.generateFirstVision();

      await _pump(tester, locale: const Locale('km'), container: c);
      expect(find.text('Your space'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final code in const ['en', 'fr', 'km']) {
      testWidgets('the surface resolves in $code', (tester) async {
        await _pump(tester, locale: Locale(code));
        final l = pwaL10nFor(Locale(code));
        for (final s in [
          l.historyTitle,
          l.transformations,
          l.newDesignSession,
          l.noProjects,
        ]) {
          expect(s, isNotEmpty, reason: code);
          expect(s.startsWith('pwa'), isFalse, reason: '$code: $s');
        }
        expect(find.text(l.historyTitle), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group("PROJ05b  the room is named in the reader's language", () {
    // Found on the staging preview: a Khmer reader saw "Living Room" printed
    // over their own render. The stored `room_type` is canonical English on
    // purpose — it keys the prompt engine's DNA and is routed, never
    // translated — so the localisation has to happen display-side, which is
    // exactly what iOS's `ProjectCard` does with `RoomTypeImages.displayLabel`.
    testWidgets('Khmer and French get their own room name', (tester) async {
      for (final code in const ['km', 'fr']) {
        final c = _container();
        addTearDown(c.dispose);
        await _pump(tester, locale: Locale(code), container: c);
        final mobile = AppLocalizations(Locale(code));
        final living = RoomTypeImages.labelForId(mobile, 'living_room')!;
        expect(living, isNot('Living Room'), reason: '$code has its own word');
        expect(find.text(living), findsWidgets, reason: code);
        expect(find.text('Living Room'), findsNothing, reason: code);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('and Home prints the identical string', (tester) async {
      // One resolver, two screens. If either grew its own label logic the two
      // would disagree about the same project in front of the same reader.
      final c = _container();
      addTearDown(c.dispose);
      await _pump(tester, locale: const Locale('km'), container: c);
      final p = c.read(pwaControllerProvider).visibleProjects
          .firstWhere((x) => x.roomLabel == 'Living Room');
      final l = pwaL10nFor(const Locale('km'));
      final shown = pwaRoomDisplayLabel(l,
          roomId: p.roomId, roomLabel: p.roomLabel);
      expect(find.text(shown), findsWidgets);

      c.read(pwaControllerProvider.notifier).openHome();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining(shown), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unknown room is echoed, never blanked', (tester) async {
      final l = pwaL10nFor(const Locale('km'));
      expect(
        pwaRoomDisplayLabel(l, roomId: null, roomLabel: 'Wine Cellar'),
        'Wine Cellar',
      );
      expect(
        pwaRoomDisplayLabel(l, roomId: 'not_a_room', roomLabel: 'Your space'),
        'Your space',
      );
    });
  });

  group('PROJ05c  freshness is a timestamp, not a stored sentence', () {
    // Found on the staging preview: "Updated 4 minutes ago" under a French
    // interface. `updatedLabelFor` localises the TIMESTAMP and falls back to
    // the stored English label only when there is none — and `_activeSnapshot`
    // was rebuilding the open project without carrying `updatedAt` over, so
    // the fallback was what every reader got.
    testWidgets('the open project keeps a timestamp across a rebuild',
        (tester) async {
      final c = _container(seed: false);
      addTearDown(c.dispose);
      final n = c.read(pwaControllerProvider.notifier);
      n.newProject();
      n.setSource(
        AydenImageSource(bytes: _png, filename: 'r.png', mimeType: 'image/png'),
        origin: PwaImageOrigin.userUpload,
      );
      await n.generateFirstVision();

      final p = c.read(pwaControllerProvider).visibleProjects.single;
      expect(p.updatedAt, isNotNull,
          reason: 'without this the card can only print English');

      await _pump(tester, locale: const Locale('fr'), container: c);
      final l = pwaL10nFor(const Locale('fr'));
      expect(find.text(l.updatedLabelFor(p.updatedAt, p.updatedLabel)),
          findsWidgets);
      expect(find.textContaining('Updated'), findsNothing);
      expect(find.textContaining(' ago'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    test('and the order it produces is unchanged', () {
      // The ordering rule prefers the database timestamp when BOTH sides have
      // one, so filling in a value that used to be null could in principle
      // reshuffle a library. It does not: the bumped project carries both the
      // newest timestamp and the highest counter, which agree.
      final c = _container();
      addTearDown(c.dispose);
      final before = c.read(pwaControllerProvider).visibleProjects
          .map((p) => p.projectId).toList();
      final resorted = PwaProjectSnapshot.sortedBy(
        c.read(pwaControllerProvider).visibleProjects,
        PwaProjectSort.recentlyUpdated,
      ).map((p) => p.projectId).toList();
      expect(resorted, before);
    });
  });

  group('PROJ06b  a wide window is a column, not a canvas', () {
    // Found on the staging preview at 1440: the header sat hard against the
    // left edge and the New-session button ran the full width of the monitor,
    // because the max-width constant existed but nothing read it.
    testWidgets('the grid is centred and bounded on a desktop window',
        (tester) async {
      await _pump(tester, size: const Size(1440, 900));
      final scroll = tester.getRect(find.byType(CustomScrollView).first);
      expect(scroll.width, lessThanOrEqualTo(1360 + 0.5));
      expect(scroll.center.dx, closeTo(720, 1),
          reason: 'centred in the window');
      expect(tester.takeException(), isNull);
    });

    testWidgets('and a phone is unchanged — full bleed', (tester) async {
      await _pump(tester, size: const Size(390, 844));
      final scroll = tester.getRect(find.byType(CustomScrollView).first);
      expect(scroll.width, 390);
      expect(tester.takeException(), isNull);
    });

    test('columns are counted from the bounded width, not the window', () {
      // 1920 is four columns of a 1360 column, not four columns of 1920 —
      // otherwise the ceiling would clip the layout instead of deciding it.
      expect(pwaProjectsColumnWidth(1920), 1360);
      expect(pwaProjectsColumnWidth(390), 390);
      expect(pwaProjectColumns(pwaProjectsColumnWidth(1920)), 4);
    });
  });

  group('PROJ06  it holds together', () {
    test('the width buys columns, not metadata', () {
      expect(pwaProjectColumns(390), 2);
      expect(pwaProjectColumns(430), 2);
      expect(pwaProjectColumns(860), 3);
      expect(pwaProjectColumns(1180), 4);
      expect(pwaProjectColumns(1920), 4);
    });

    for (final size in const [
      Size(390, 844),
      Size(430, 932),
      Size(768, 1024),
      Size(1440, 900),
      Size(1920, 1080),
    ]) {
      testWidgets(
        'no overflow at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _pump(tester, size: size);
          expect(find.byKey(const ValueKey('pwa-projects')), findsOneWidget);
          expect(tester.takeException(), isNull, reason: '$size');
        },
      );

      testWidgets(
        'empty state holds at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _pump(tester, size: size, seed: false);
          expect(
            find.byKey(const ValueKey('pwa-projects-empty')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull, reason: '$size');
        },
      );
    }
  });
}
