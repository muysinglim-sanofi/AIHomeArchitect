/// Phase 10 — the release pass.
///
/// These are not feature tests. They are the small, cross-cutting rules that
/// no single screen owns and that therefore nothing was holding: a count that
/// reads correctly at one, a window that stops widening, a typeface that never
/// falls back to the platform's.
///
/// Each one exists because it was found, not because it was imagined.
library;

import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_route.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_persistence_repository.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_l10n.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_home_ios.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_profile_ios.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_projects_ios.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('POL02  a wide window is a composition, not a canvas', () {
    // Home ran to both edges while Projects and Profile were already bounded.
    test('Home stops widening, and stops well before the grid does', () {
      expect(pwaHomeColumnWidth(390), 390, reason: 'a phone is full bleed');
      expect(pwaHomeColumnWidth(768), 720, reason: 'the shared tablet ceiling');
      expect(pwaHomeColumnWidth(1440), 900);
      expect(pwaHomeColumnWidth(1920), 900);
      // Narrower than the Projects grid, which earns its width by fitting more
      // work into it. Home has exactly one thing to show.
      expect(pwaHomeColumnWidth(1920),
          lessThan(pwaProjectsColumnWidth(1920)));
      // And wider than Profile, which is a list of rows.
      expect(pwaHomeColumnWidth(1920),
          greaterThan(pwaProfileColumnWidth(1920)));
    });

    testWidgets('every routed screen is bounded on a 1920 monitor',
        (tester) async {
      // The rule, stated once: no routed surface may run to the edges of a
      // large window. Held as arithmetic rather than as a screenshot so it
      // cannot rot silently.
      for (final w in const [1440.0, 1920.0, 2560.0]) {
        expect(pwaHomeColumnWidth(w), lessThanOrEqualTo(900.0));
        expect(pwaProfileColumnWidth(w), lessThanOrEqualTo(640.0));
        expect(pwaProjectsColumnWidth(w), lessThanOrEqualTo(1360.0));
      }
    });
  });

  group('POL03  a first-time visitor can open the links worth sending', () {
    // Phase 8 exempted /profile from the empty-library fallback and left
    // /create behind — the one link worth sending someone who has never used
    // the product, and whose library is therefore empty by definition.
    for (final (route, page) in const [
      (PwaRoute.create, PwaPage.create),
      (PwaRoute.profile, PwaPage.profile),
    ]) {
      test('${route.location} survives an empty library', () async {
        final restore = await pwaResolveBootRestore(
          MockPwaPersistenceRepository(),
          route: route,
        );
        expect(restore.library, isEmpty);
        expect(restore.route?.page, page);
      });
    }

    test('and a project URL still falls back, because there is no project',
        () async {
      for (final r in const [
        PwaRoute(PwaPage.architect, projectId: 'nope'),
        PwaRoute(PwaPage.reveal, projectId: 'nope'),
        PwaRoute(PwaPage.draft, projectId: 'nope'),
        PwaRoute.projects,
      ]) {
        final restore = await pwaResolveBootRestore(
          MockPwaPersistenceRepository(),
          route: r,
        );
        expect(restore.route?.page, PwaPage.home, reason: r.location);
      }
    });

    test('the first frame matches the route it resolved', () async {
      for (final (route, phase) in const [
        (PwaRoute.create, PwaPhase.entry),
        (PwaRoute.profile, PwaPhase.profile),
      ]) {
        final restore = await pwaResolveBootRestore(
          MockPwaPersistenceRepository(),
          route: route,
        );
        final c = ProviderContainer(overrides: [
          pwaRepositoryProvider.overrideWithValue(
            MockPwaExperienceRepository(workDelay: Duration.zero),
          ),
          pwaBootRestoreProvider.overrideWithValue(restore),
        ]);
        addTearDown(c.dispose);
        expect(c.read(pwaControllerProvider).phase, phase,
            reason: route.location);
      }
    });
  });

  group('POL04  the dark screen does not leak through the menu', () {
    // Phase 7 reused PwaProjectCardMenu from the retired dark screen without
    // following where its actions LED. Tapping ⋯ on a cream project card
    // dropped a near-black sheet; Rename and Delete opened near-black dialogs.
    // Held as a source assertion because the surfaces are inside showDialog /
    // showModalBottomSheet, which a widget test can only reach one at a time —
    // and because the rule is "this block owns no dark token", which is
    // exactly what a source check states.
    test('the card-action menu carries no dark-screen colour', () {
      final src = File('lib/features/pwa/presentation/pwa_projects_screen.dart')
          .readAsStringSync();
      final start = src.indexOf('// ── Card action menu');
      final end = src.indexOf('// ── Empty / no-results');
      expect(start, greaterThan(0));
      expect(end, greaterThan(start));
      final menu = src.substring(start, end);

      for (final token in const [
        // Hard-coded literals count too: the rename field kept a near-black
        // fill and a gold hairline through the token sweep, so the dialog was
        // white with a black box in the middle of it.
        'Color(0xFF1A1712)',
        'Color(0x22D3B064)',
        'av7CardDark',
        'av7Muted',
        'av7OnDarkSoft',
        'av7Gold',
        'Color(0xFFE0857A)',
      ]) {
        expect(menu, isNot(contains(token)), reason: token);
      }
      // The one dark thing that stays: the ⋯ disc, which sits on the person's
      // own render and would vanish on a pale one.
      expect(menu, contains('av7OnDark'),
          reason: 'the disc over the cover is still light-on-dark');
    });
  });

  group('POL01  counts read correctly at one', () {
    // '{n} spaces left' with n = 1 said "1 spaces left" on a real wallet, and
    // '{n} redesigns' said "1 redesigns" on the Projects header of anyone who
    // had made exactly one thing — which is every new person, on the screen
    // that is meant to celebrate it.
    for (final code in const ['en', 'fr', 'km']) {
      test('$code: no "1 <plural>" anywhere a count is shown', () {
        final l = pwaL10nFor(Locale(code));
        final singulars = <String>[
          l.transformationsCount(1),
          l.passSpacesLeft(1),
          l.paywallSpaces(1),
        ];
        for (final s in singulars) {
          expect(s, isNotEmpty, reason: code);
          expect(s.startsWith('pwa'), isFalse,
              reason: '$code: missing key — $s');
        }
        // The singular must DIFFER from the plural rendered at 1, in the
        // languages that have a plural. Khmer does not, and says so by using
        // the same sentence — which is correct, not a gap.
        if (code != 'km') {
          expect(l.transformationsCount(1), isNot(l.transformationsCount(2)));
          expect(l.passSpacesLeft(1), isNot(contains('1 Spaces')));
          expect(l.passSpacesLeft(1), isNot(contains('1 spaces')));
          expect(l.paywallSpaces(1), isNot(contains('1 spaces')));
        }
      });

      test('$code: plurals still read correctly above one', () {
        final l = pwaL10nFor(Locale(code));
        expect(l.transformationsCount(3), contains('3'));
        expect(l.passSpacesLeft(30), contains('30'));
        expect(l.paywallSpaces(300), contains('300'));
      });
    }

    test('a month-old project is not "1 months ago"', () {
      final l = pwaL10nFor(const Locale('en'));
      final now = DateTime.utc(2026, 3, 1);
      // 31 days: the first day the months bucket is used at all.
      final s = l.updatedRelative(DateTime.utc(2026, 1, 29), now: now);
      expect(s, isNot(contains('1 months')));
      expect(s, isNotEmpty);
      // Two months still reads as a number.
      expect(l.updatedRelative(DateTime.utc(2025, 12, 20), now: now),
          contains('2'));
    });

    test('zero is a plural in every language', () {
      for (final code in const ['en', 'fr', 'km']) {
        final l = pwaL10nFor(Locale(code));
        expect(l.transformationsCount(0), contains('0'), reason: code);
      }
    });
  });
}
