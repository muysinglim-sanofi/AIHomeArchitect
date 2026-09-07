/// Round 3 — what happens the moment a person becomes a different user.
///
/// Three defects, one seam. Signing in to an existing account left the app
/// showing a verified email beside the PREVIOUS identity's entitlement and the
/// PREVIOUS identity's project library — and offered, as the only way forward,
/// a button labelled "Not now".
///
/// They were the same bug seen three ways: post-authentication hydration was
/// the CALLER's job, ran after the authenticated UI was already on screen, and
/// only on one of the sheet's several dismissal paths. It is the sheet's job
/// now, it runs before the sheet closes, and it covers the library too — which
/// nothing had ever reloaded after boot.
library;

import 'dart:io';

import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_persistence_repository.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_persistence_repository.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_models.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_project.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

PwaVision _vision(String id, String projectId) => PwaVision(
      versionId: id,
      projectId: projectId,
      visionNumber: 1,
      title: 'Warm Modern',
      atmosphereId: 'warm_modern',
      actionType: PwaActionType.signature,
      afterAsset: 'assets/showcase/apartment_after.jpg',
      order: 1,
    );

PwaProjectSnapshot _project(String id, String room) => PwaProjectSnapshot(
      projectId: id,
      title: room,
      originalImageAsset: 'assets/showcase/apartment_before.jpg',
      roomId: room.toLowerCase(),
      roomLabel: room,
      selectedAtmosphereId: 'warm_modern',
      atmosphereLabel: 'Warm Modern',
      visions: [_vision('v-$id', id)],
      messages: const [],
      currentVisionId: 'v-$id',
      createdOrder: 1,
      updatedOrder: 1,
      updatedLabel: 'Updated today',
      status: PwaProjectStatus.active,
    );

void main() {
  // ── §1 — success is not something you postpone ───────────────────────────
  group('HYD01  the success state offers nothing to press', () {
    test('HYD01: the identified branch is a settling state, not a button', () {
      // Comments stripped: the branch's own comment NAMES the button it
      // replaced, which is the point of the comment and the opposite of the
      // defect.
      final src = File('lib/features/pwa/presentation/pwa_account_sheet.dart')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join(String.fromCharCode(10));
      final start = src.indexOf('auth.stage == PwaAuthStage.identified');
      final end = src.indexOf('} else if (auth.failure ==', start);
      expect(start, greaterThan(0));
      final branch = src.substring(start, end);

      // THE defect: the only action after a successful authentication was the
      // PAYWALL's "Not now" — an invitation to postpone something that had
      // already happened, and the one path that told the app to refresh.
      expect(branch, isNot(contains('paywallClose')));
      expect(branch, isNot(contains('onPrimary')));
      expect(branch, isNot(contains('_Message')));
      expect(branch, contains('_Settling'));
    });

    test('HYD02: the settling state has no action at all', () {
      final src =
          File('lib/features/pwa/presentation/pwa_account_sheet.dart')
              .readAsStringSync();
      final start = src.indexOf('class _Settling');
      final end = src.indexOf('class _Message', start);
      final w = src.substring(start, end);
      for (final action in const [
        'onPressed',
        'onTap',
        '_PrimaryButton',
        'TextButton',
      ]) {
        expect(w, isNot(contains(action)), reason: action);
      }
      // It does say what happened, and that something is still finishing.
      expect(w, contains('CircularProgressIndicator'));
    });
  });

  // ── §2 / §3 / §4 — hydration is the sheet's, and it is complete ──────────
  group('HYD03  authentication hydrates before it hands back control', () {
    test('HYD03: the sheet refreshes entitlement AND library, then closes', () {
      final src =
          File('lib/features/pwa/presentation/pwa_account_sheet.dart')
              .readAsStringSync();
      final start = src.indexOf('Future<void> _verifyAndSettle()');
      expect(start, greaterThan(0), reason: 'the hydration seam must exist');
      // To the end of the method, anchored on its last statement rather than
      // on an indentation pattern.
      final fn = src.substring(start, src.indexOf('pop(true);', start) + 10);

      // Order matters, and so does each step.
      final iVerify = fn.indexOf('submitCode');
      final iGuard = fn.indexOf('PwaAuthStage.identified');
      final iHydrate = fn.indexOf('pwaHydrateForIdentity');
      final iPop = fn.indexOf('Navigator.of(context).pop');
      for (final e in {
        'submitCode': iVerify,
        'the identified guard': iGuard,
        'pwaHydrateForIdentity': iHydrate,
        'the self-dismissal': iPop,
      }.entries) {
        expect(e.value, greaterThan(-1), reason: '${e.key} is missing');
      }
      expect(iGuard, greaterThan(iVerify),
          reason: 'refused codes hydrate nothing');
      expect(iHydrate, greaterThan(iGuard));
      expect(iPop, greaterThan(iHydrate),
          reason: 'the sheet must not close before the account has settled');
      // The library is reloaded only on a SWITCH: linking keeps the same user,
      // and resetting the session would throw away the work being saved.
      expect(fn, contains('switchedUser: s.switchedAccount'));

      // …and the seam itself does both halves, in that order.
      final seamStart = src.indexOf('Future<void> pwaHydrateForIdentity');
      // To the next declaration. NOT to the first line starting with `}` —
      // that is the signature's own `}) async {`, which slices the body away
      // and makes every assertion below pass on an empty string.
      final seam = src.substring(seamStart, src.indexOf('class ', seamStart));
      expect(seam.indexOf('onIdentityChanged'), greaterThan(-1));
      expect(seam.indexOf('reloadForIdentity'),
          greaterThan(seam.indexOf('onIdentityChanged')));
      expect(seam, contains('if (switchedUser)'));
    });

    test('HYD04: no caller refreshes on its own any more', () {
      // The refresh used to live in three places and ran only when the sheet
      // returned `true` — so a swipe-to-dismiss skipped it entirely. One seam
      // now, and these three must not grow their own.
      // Sign-OUT is an identity change too, and had the same half-fix: it
      // re-read entitlement and left the previous account's projects in the
      // library. Both sign-out entries go through the seam now.
      for (final f in const [
        'lib/features/pwa/presentation/pwa_profile_ios.dart',
        'lib/features/pwa/presentation/pwa_account_chip.dart',
        'lib/features/pwa/presentation/pwa_paywall.dart',
      ]) {
        final src = File(f).readAsStringSync();
        expect(src, isNot(contains('onIdentityChanged()')),
            reason: '$f still hydrates by hand');
      }
      for (final f in const [
        'lib/features/pwa/presentation/pwa_profile_ios.dart',
        'lib/features/pwa/presentation/pwa_account_chip.dart',
      ]) {
        final src = File(f).readAsStringSync();
        expect(src, contains('pwaHydrateForIdentity('),
            reason: '\$f signs out without reloading the library');
        expect(src, contains('switchedUser: true'), reason: f);
      }
    });
  });

  // ── §3 — the library follows the identity ────────────────────────────────
  group('HYD05  the project library is reloaded for the new user', () {
    ProviderContainer container(PwaPersistenceRepository p) {
      final c = ProviderContainer(overrides: [
        pwaRepositoryProvider.overrideWithValue(
          MockPwaExperienceRepository(
              workDelay: Duration.zero, seedLibrary: false),
        ),
        pwaPersistenceProvider.overrideWithValue(p),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('HYD05: an empty guest library becomes the account\'s projects',
        () async {
      // The exact reported shape: a FRESH browser (no guest projects) signs in
      // to an account that has three, and Projects said "0 redesigns".
      final p = MockPwaPersistenceRepository();
      final c = container(p);
      final n = c.read(pwaControllerProvider.notifier);
      expect(c.read(pwaControllerProvider).library, isEmpty);

      for (final s in [
        _project('p1', 'Kitchen'),
        _project('p2', 'Living Room'),
        _project('p3', 'Bedroom'),
      ]) {
        await p.saveProject(s);
      }
      await n.reloadForIdentity();

      final s = c.read(pwaControllerProvider);
      expect(s.library, hasLength(3));
      expect(s.visibleProjects, hasLength(3),
          reason: 'and they are all displayable — this is what Projects reads');
      // Home reads the SAME list, so it cannot disagree.
      expect(s.visibleProjects.map((x) => x.projectId).toSet(),
          {'p1', 'p2', 'p3'});
    });

    test('HYD06: the previous identity\'s rows are REPLACED, never merged',
        () async {
      final p = MockPwaPersistenceRepository();
      final c = container(p);
      final n = c.read(pwaControllerProvider.notifier);

      // A guest with work of its own, in the working library.
      final repo = c.read(pwaRepositoryProvider);
      repo.saveProject(_project('guest-1', 'Terrace'));
      expect(repo.listProjects(), hasLength(1));

      // …and an account with different work in the durable store.
      await p.saveProject(_project('acct-1', 'Kitchen'));
      await n.reloadForIdentity();

      final ids =
          c.read(pwaControllerProvider).library.map((x) => x.projectId).toSet();
      expect(ids, {'acct-1'});
      expect(ids, isNot(contains('guest-1')),
          reason: 'two accounts\' work must never mix');
    });

    test('HYD07: it lands on Home, because the open session was someone '
        'else\'s', () async {
      final p = MockPwaPersistenceRepository();
      await p.saveProject(_project('acct-1', 'Kitchen'));
      final c = container(p);
      await c.read(pwaControllerProvider.notifier).reloadForIdentity();
      final s = c.read(pwaControllerProvider);
      expect(s.phase, PwaPhase.home);
      expect(s.versions, isEmpty);
      expect(s.canonicalRoute.location, '/');
    });
  });

  // ── §7 — Create's atmosphere cards are room-card sized ───────────────────
  group('CRE01  Step 3 uses the room grid\'s footprint', () {
    test('CRE01: the picker is a grid at the rooms\' own numbers', () {
      final src =
          File('lib/features/pwa/presentation/pwa_create_ios.dart')
              .readAsStringSync();
      final start = src.indexOf('class _AtmospherePicker');
      final picker = src.substring(start);

      // The page-snapped hero is gone: 274 x 228 on a 390dp phone, one choice
      // filling the screen and the next sliced in half at the edge.
      expect(picker, isNot(contains('PageView')));
      expect(picker, isNot(contains('viewportFraction')));
      // …replaced by the room grid's own geometry, stated identically.
      expect(picker, contains('crossAxisCount: c.maxWidth >= 600 ? 3 : 2'));
      expect(picker, contains('childAspectRatio: 6 / 5'));
      expect(picker, contains('crossAxisSpacing: 12'));
      expect(picker, contains('compact: true'));
    });

    test('CRE02: and it is the SAME arithmetic the room grid uses', () {
      final src =
          File('lib/features/pwa/presentation/pwa_create_ios.dart')
              .readAsStringSync();
      // Both grids, read out of one file: same columns rule, same ratio, same
      // gap. On a 390dp phone that is a 165 x 137 card in each step.
      expect('crossAxisCount: cols'.allMatches(src).length, 1);
      expect('childAspectRatio: 6 / 5'.allMatches(src).length, 2,
          reason: 'rooms and atmospheres, at the same footprint');
      const content = 390.0 - 24 * 2; // page padding
      final cardW = (content - 12) / 2;
      expect(cardW.round(), 165);
      expect((cardW * 5 / 6).round(), 138);
    });
  });

  // ── §6 — the selection images are thumbnails, not production art ─────────
  group('IMG01  the Create flow loads derivatives, not 2.5 MB PNGs', () {
    test('IMG01: every selection asset has a small WebP beside it', () {
      final sources = [
        ...Directory('assets/cards/rooms').listSync().whereType<File>(),
        ...Directory('assets/cards/atmospheres').listSync().whereType<File>(),
        File('assets/atmospheres/ayden_signature.jpg'),
        File('assets/branding/ayden_decide_card.png'),
      ].where((f) => f.existsSync());

      var src = 0, thumb = 0, n = 0;
      for (final f in sources) {
        // `assets/cards/rooms/kitchen.png` → `cards__rooms__kitchen.webp` —
        // the same flattening the generator and the bundle both use.
        final path = f.path.replaceAll(r'\', '/');
        final rel = path.substring(path.indexOf('assets/') + 'assets/'.length);
        final stem = rel.substring(0, rel.lastIndexOf('.'));
        final t = File('web/thumbs/${stem.replaceAll('/', '__')}.webp');
        if (!t.existsSync()) continue;
        src += f.lengthSync();
        thumb += t.lengthSync();
        n++;
      }
      expect(n, greaterThanOrEqualTo(18),
          reason: 'the grids must be covered, not a sample');
      // The measurement that justifies the whole mechanism.
      expect(thumb, lessThan(src ~/ 20),
          reason: 'a thumbnail must be a fraction of the art behind it');
      expect(thumb, lessThan(2 * 1024 * 1024),
          reason: 'the whole selection set fits in a couple of megabytes');
    });

    test('IMG02: the mapping covers the grids and nothing else', () {
      // Renders, showcase images and the paywall hero are displayed LARGE. A
      // blanket rule over assets/ would have quietly downgraded them.
      final src =
          File('lib/features/pwa/data/pwa_thumbnail_bundle.dart')
              .readAsStringSync();
      expect(src, contains("'assets/cards/rooms/'"));
      expect(src, contains("'assets/cards/atmospheres/'"));
      expect(src, isNot(contains("'assets/showcase/")));
      expect(src, isNot(contains("'assets/images/")));
      // Fail-open: a missing derivative falls back to the real asset.
      expect(src, contains('_inner.load(key)'));
    });

    test('IMG03: they are web-only, so the frozen mobile bundle cannot grow',
        () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, isNot(contains('thumbs')));
      expect(Directory('web/thumbs').existsSync(), isTrue);
    });
  });
}
