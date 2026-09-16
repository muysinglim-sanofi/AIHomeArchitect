/// SIGNOUT-06..15 — the guest a sign-out creates cannot spend a trial it will
/// not be allowed to keep.
///
/// THE ABUSE, reproduced on staging (2026-09-16). Nothing fires on account
/// creation and the free bucket ADDS the trial while no TRIAL row exists, so
/// every new anonymous user is projected a fresh one — three successive fresh
/// guests, three full trials. A guest cannot sign out (the button is behind
/// `if (identified)`), but an identified account can, and lands on a guest with
/// a full trial. Sign in, sign out, repeat: one authorisation per lap.
///
/// The marker that closes it is written by the CLIENT, because the backend
/// genuinely cannot tell that guest from a first-ever visitor — at one second
/// old they are identical, and marking every anonymous sign-in would take the
/// trial away from real first visits (SIGNOUT-13).
///
/// A client-written marker is only worth anything if losing the network cannot
/// turn it off. Hence the pending flag: raised BEFORE the entitlement is
/// re-read, persisted, and lowered only on a confirmed marker. These tests are
/// about that flag — that it blocks generation, that it survives a reload, and
/// that it never touches a first visit.
library;

import 'package:ai_home_architect/core/providers/post_signout_pending_provider.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_generation_service.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_pending_generation.dart';
import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:io';
import 'dart:typed_data';

// ── doubles ──────────────────────────────────────────────────────────────────

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
    AydenImageSource(bytes: _png, filename: 'r.png', mimeType: 'image/png');

/// The marker transport, scripted. Counts every attempt.
class _Marker {
  _Marker({this.succeeds = true});

  bool succeeds;
  int attempts = 0;

  Future<bool> post() async {
    attempts++;
    return succeeds;
  }
}

/// A controller wired exactly as production wires it, with the pending flag
/// injected the same way.
({PwaController controller, PwaFakeGenerationService generation})
    _rig({required bool Function() pending}) {
  final repo = MockPwaExperienceRepository(workDelay: Duration.zero,
      seedLibrary: false);
  final generation = PwaFakeGenerationService();
  final controller = PwaController(
    repo,
    generation: generation,
    pending: PwaMemoryPendingGenerationStore(),
    guestSetupPending: pending,
  );
  return (controller: controller, generation: generation);
}

Future<void> _tapGenerate(PwaController c) async {
  c.newProject();
  c.setSource(_source());
  c.selectRoom('living_room');
  c.selectEntryAtmosphere('warm_modern');
  await c.generateFirstVision();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ══════════════════════════════════════════════════════════════════════════
  group('THE GATE  a pending marker stops a generation dead', () {
    test('SIGNOUT-06/09 pending -> Generate refuses, and spends nothing',
        () async {
      final r = _rig(pending: () => true);
      addTearDown(r.controller.dispose);
      await _tapGenerate(r.controller);

      expect(r.generation.generatedCount, 0,
          reason: 'SIGNOUT-06: the projected Spaces are not spendable');
      expect(r.controller.state.generationErrorCode, 'GUEST_SETUP_PENDING');
      expect(r.controller.state.generationRetryable, isTrue,
          reason: 'it is a wait, not a refusal — the marker is being retried');
      expect(r.controller.state.generating, isFalse);
    });

    test('SIGNOUT-09b the race is closed: entitlement may still SAY three',
        () async {
      // The engine cannot help projecting a trial onto a one-second-old
      // anonymous account — that is the whole reason the flag exists. What must
      // never happen is that the projection is spendable. The gate is not the
      // number on screen; it is this.
      final r = _rig(pending: () => true);
      addTearDown(r.controller.dispose);
      for (var i = 0; i < 3; i++) {
        await _tapGenerate(r.controller);
      }
      expect(r.generation.generatedCount, 0,
          reason: 'three taps, three refusals, nothing consumed');
    });

    test('SIGNOUT-08 once the marker is confirmed, Generate works again',
        () async {
      var pending = true;
      final r = _rig(pending: () => pending);
      addTearDown(r.controller.dispose);
      await _tapGenerate(r.controller);
      expect(r.generation.generatedCount, 0);

      pending = false; // the marker came back confirmed
      await _tapGenerate(r.controller);
      expect(r.generation.generatedCount, 1,
          reason: 'the guest generates normally once it is secured');
    });

    test('SIGNOUT-13 a FIRST visit is never gated', () async {
      // Nobody signed out, so nothing raised the flag. This is the case the
      // marker must never touch: a real first visitor keeps their trial.
      final r = _rig(pending: () => false);
      addTearDown(r.controller.dispose);
      await _tapGenerate(r.controller);
      expect(r.generation.generatedCount, 1);
      expect(r.controller.state.generationErrorCode, isNot('GUEST_SETUP_PENDING'));
    });

    test('the default is NOT gated — the flag must be wired to bite', () {
      final repo = MockPwaExperienceRepository(workDelay: Duration.zero,
          seedLibrary: false);
      final c = PwaController(repo,
          generation: PwaFakeGenerationService(),
          pending: PwaMemoryPendingGenerationStore());
      addTearDown(c.dispose);
      // No `guestSetupPending` passed: the offline build and every existing
      // test have no sign-out to recover from.
      expect(c.state.generationErrorCode, isNot('GUEST_SETUP_PENDING'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('THE FLAG  it survives everything except a confirmed marker', () {
    test('SIGNOUT-06b a failed marker leaves the flag UP', () async {
      final marker = _Marker(succeeds: false);
      final n = PostSignoutPendingNotifier(
          postMarker: marker.post, isAnonymous: () => true);
      addTearDown(n.dispose);
      await n.setPending(true);

      final lifted = await n.resolve();
      expect(lifted, isFalse);
      expect(n.state, isTrue, reason: 'still pending: nothing was confirmed');
      // At least one: the notifier also retries by itself at boot, which is
      // exactly the behaviour being relied on. The count is a floor, not a
      // fixture.
      expect(marker.attempts, greaterThanOrEqualTo(1));
    });

    test('SIGNOUT-07 …and survives a reload', () async {
      final marker = _Marker(succeeds: false);
      final first = PostSignoutPendingNotifier(
          postMarker: marker.post, isAnonymous: () => true);
      await first.setPending(true);
      first.dispose();

      // A reload is a new notifier over the SAME SharedPreferences.
      final second = PostSignoutPendingNotifier(
          postMarker: marker.post, isAnonymous: () => true);
      addTearDown(second.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(second.state, isTrue,
          reason: 'SIGNOUT-07: closing the tab does not clear the debt');
      expect(marker.attempts, greaterThanOrEqualTo(1),
          reason: 'and the boot retries it by itself');
    });

    test('SIGNOUT-08b a confirmed marker lowers it, and it stays down',
        () async {
      final marker = _Marker(succeeds: true);
      final n = PostSignoutPendingNotifier(
          postMarker: marker.post, isAnonymous: () => true);
      addTearDown(n.dispose);
      await n.setPending(true);

      expect(await n.resolve(), isTrue);
      expect(n.state, isFalse);

      final afterReload = PostSignoutPendingNotifier(
          postMarker: marker.post, isAnonymous: () => true);
      addTearDown(afterReload.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(afterReload.state, isFalse, reason: 'the debt is paid, once');
    });

    test('SIGNOUT-10 three sign-out laps mark three guests, never zero',
        () async {
      final marker = _Marker(succeeds: true);
      for (var lap = 1; lap <= 3; lap++) {
        final n = PostSignoutPendingNotifier(
            postMarker: marker.post, isAnonymous: () => true);
        await n.setPending(true);
        expect(await n.resolve(), isTrue, reason: 'lap $lap');
        expect(n.state, isFalse, reason: 'lap $lap');
        n.dispose();
      }
      expect(marker.attempts, greaterThanOrEqualTo(3),
          reason: 'every lap is marked — no lap yields a spendable trial');
    });

    test('a flag left over for an account that signed back IN is dropped',
        () async {
      // The person linked or signed in before the retry landed. The marker no
      // longer applies to them, and must not gate a real account.
      final marker = _Marker(succeeds: true);
      final n = PostSignoutPendingNotifier(
          postMarker: marker.post, isAnonymous: () => false);
      addTearDown(n.dispose);
      await n.setPending(true);

      expect(await n.resolve(), isTrue);
      expect(n.state, isFalse);
      expect(marker.attempts, 0, reason: 'nothing is posted for a real account');
    });

    test('an undecided session keeps the flag rather than guessing', () async {
      final marker = _Marker(succeeds: true);
      final n = PostSignoutPendingNotifier(
          postMarker: marker.post, isAnonymous: () => null);
      addTearDown(n.dispose);
      await n.setPending(true);

      expect(await n.resolve(), isFalse);
      expect(n.state, isTrue, reason: 'fail closed while the session is unknown');
      expect(marker.attempts, 0);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('THE ORDER  the flag is up before anything can be spent', () {
    test('sign-out raises it BEFORE the entitlement is re-read', () {
      final src = _readSheet();
      final raise = src.indexOf('pending.setPending(true)');
      final hydrate = src.indexOf('pwaHydrateForIdentity(ref, switchedUser: true)');
      final resolve = src.indexOf('pending.resolve()');
      expect(raise, greaterThan(-1));
      expect(hydrate, greaterThan(raise),
          reason: 'SIGNOUT-09: no frame where a projected trial is spendable');
      expect(resolve, greaterThan(hydrate),
          reason: 'the marker is confirmed last, and may safely fail');
    });

    test('both sign-out doors go through the one helper', () {
      for (final path in const [
        'lib/features/pwa/presentation/pwa_profile_ios.dart',
        'lib/features/pwa/presentation/pwa_account_chip.dart',
      ]) {
        final src = _read(path);
        expect(src.contains('pwaSignOutAndSecureGuest(ref)'), isTrue,
            reason: path);
        expect(src.contains('.signOut();'), isFalse,
            reason: '$path must not sign out around the helper');
      }
    });

    test('SIGNOUT-11/12 the helper touches no billing, payment or project data',
        () {
      final src = _readSheet();
      final body = src.substring(
          src.indexOf('Future<void> pwaSignOutAndSecureGuest'),
          src.indexOf('/// Make the app BE the current identity'));
      for (final forbidden in const [
        'ledger', 'payway', 'checkout', 'passes', 'credits', 'premium',
        'deleteProject', 'saveProject',
      ]) {
        expect(body.contains(forbidden), isFalse, reason: forbidden);
      }
    });
  });
}

String _read(String path) => File(path).readAsStringSync();
String _readSheet() =>
    _read('lib/features/pwa/presentation/pwa_account_sheet.dart');
