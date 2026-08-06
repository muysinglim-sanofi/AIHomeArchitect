// The generation seam and the signed-URL resolver. Both are the places where a
// "helpful" fallback would quietly turn a failure into a fake success, so the
// assertions here are mostly about what must NOT happen.

import 'package:ai_home_architect/features/pwa/data/pwa_generation_api.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_generation_service.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_image_url_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

PwaGenerationIntent _intent({
  String idem = 'k-1',
  int n = 1,
  String action = 'initial',
  String parent = '',
  String instruction = '',
}) => PwaGenerationIntent(
  projectId: 'p-1',
  roomId: 'living_room',
  roomLabel: 'Living Room',
  atmosphereId: 'warm_modern',
  atmosphereLabel: 'Warm Modern',
  originalImagePath: 'users/u/projects/p-1/original/o.jpg',
  idempotencyKey: idem,
  visionNumber: n,
  actionType: action,
  parentVisionId: parent,
  userInstruction: instruction,
);

void main() {
  group('the seam never invents a result', () {
    test('a backend error surfaces as a typed failure, not a vision', () async {
      final svc = PwaFakeGenerationService(
        failure: const PwaGenerationFailure(
          code: 'BACKEND_UNREACHABLE',
          userMessage: "Can't reach Ayden right now.",
          retryable: true,
        ),
      );
      final out = await svc
          .generate(_intent())
          .then<Object?>((v) => v, onError: (Object e) => e);
      expect(out, isA<PwaGenerationFailure>());
      expect((out as PwaGenerationFailure).retryable, isTrue);
    });

    test('a produced image is a Storage path, never a bundle asset', () async {
      final r = await PwaFakeGenerationService().generate(_intent());
      expect(r.imagePath, startsWith('users/'));
      expect(r.imagePath, isNot(startsWith('assets/')));
      expect(pwaIsStoragePath(r.imagePath), isTrue);
    });

    test('the API error contract maps onto the service failure', () async {
      // The staging service must not leak the transport type upward, and must
      // not lose the backend's user-facing message on the way.
      const api = PwaGenerationApiError(
        code: 'PROJECT_FORBIDDEN',
        userMessage: 'This project belongs to a different session.',
        retryable: false,
      );
      final failure = PwaGenerationFailure(
        code: api.code,
        userMessage: api.userMessage,
        retryable: api.retryable,
      );
      expect(failure.code, 'PROJECT_FORBIDDEN');
      expect(failure.userMessage, contains('different session'));
      expect(failure.retryable, isFalse);
    });
  });

  group('idempotency at the seam', () {
    test('the same key never generates twice', () async {
      final svc = PwaFakeGenerationService();
      final a = await svc.generate(_intent(idem: 'same'));
      final b = await svc.generate(_intent(idem: 'same'));
      expect(svc.generatedCount, 1);
      expect(b.replayed, isTrue);
      expect(b.imagePath, a.imagePath);
      expect(svc.calls, hasLength(2)); // both were attempted…
    });

    test(
      'a deliberate second generation uses a new key and really runs',
      () async {
        final svc = PwaFakeGenerationService();
        await svc.generate(_intent(idem: 'first'));
        final second = await svc.generate(_intent(idem: 'second', n: 2));
        expect(svc.generatedCount, 2);
        expect(second.replayed, isFalse);
      },
    );

    test('refinement carries its parent and instruction through', () async {
      final svc = PwaFakeGenerationService();
      await svc.generate(
        _intent(
          idem: 'r-1',
          n: 2,
          action: 'refine',
          parent: 'v-1',
          instruction: 'warmer lighting',
        ),
      );
      final sent = svc.calls.single;
      expect(sent.actionType, 'refine');
      expect(sent.parentVisionId, 'v-1');
      expect(sent.userInstruction, 'warmer lighting');
      expect(sent.visionNumber, 2);
    });

    test('an atmosphere switch is a real generation, not a relabel', () async {
      final svc = PwaFakeGenerationService();
      await svc.generate(_intent(idem: 'a-1'));
      final switched = await svc.generate(
        PwaGenerationIntent(
          projectId: 'p-1',
          roomId: 'living_room',
          roomLabel: 'Living Room',
          atmosphereId: 'japandi_calm',
          atmosphereLabel: 'Japandi Calm',
          originalImagePath: 'users/u/projects/p-1/original/o.jpg',
          idempotencyKey: 'a-2',
          visionNumber: 2,
          actionType: 'switch_atmosphere',
          parentVisionId: 'v-1',
        ),
      );
      expect(svc.generatedCount, 2, reason: 'a new image must be produced');
      expect(switched.imagePath, isNot(svc.calls.first.originalImagePath));
      expect(svc.calls.last.atmosphereId, 'japandi_calm');
      expect(svc.calls.last.actionType, 'switch_atmosphere');
    });
  });

  group('signed URL resolution', () {
    test('a bundle asset is passed through untouched', () async {
      var signed = 0;
      final r = PwaImageUrlResolver(
        signer: (p, e) async {
          signed++;
          return 'signed:$p';
        },
      );
      expect(
        await r.resolve('assets/atmospheres/x.jpg'),
        'assets/atmospheres/x.jpg',
      );
      expect(signed, 0, reason: 'bundle assets need no signature');
    });

    test('a storage path is signed once and then cached', () async {
      var signed = 0;
      final r = PwaImageUrlResolver(
        signer: (p, e) async {
          signed++;
          return 'signed:$p#$signed';
        },
      );
      const path = 'users/u/projects/p/generated/v.jpg';
      expect(await r.resolve(path), 'signed:$path#1');
      expect(await r.resolve(path), 'signed:$path#1');
      expect(signed, 1);
    });

    test('concurrent misses mint exactly one URL', () async {
      var signed = 0;
      final r = PwaImageUrlResolver(
        signer: (p, e) async {
          signed++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return 'signed:$p';
        },
      );
      const path = 'users/u/projects/p/generated/v.jpg';
      await Future.wait([r.resolve(path), r.resolve(path), r.resolve(path)]);
      expect(signed, 1, reason: 'five covers must not mint five URLs');
    });

    test('an expiring URL is re-minted before it dies', () async {
      var now = DateTime(2026, 1, 1, 12);
      var signed = 0;
      final r = PwaImageUrlResolver(
        signer: (p, e) async {
          signed++;
          return 'signed#$signed';
        },
        ttl: const Duration(hours: 1),
        clock: () => now,
      );
      const path = 'users/u/projects/p/generated/v.jpg';
      expect(await r.resolve(path), 'signed#1');
      now = now.add(const Duration(minutes: 30));
      expect(
        await r.resolve(path),
        'signed#1',
        reason: 'still comfortably valid',
      );
      // Inside the refresh margin: renewed BEFORE expiry, not after a failure.
      now = now.add(const Duration(minutes: 27));
      expect(await r.resolve(path), 'signed#2');
    });

    test('invalidate forces a fresh URL from the SAME durable path', () async {
      var signed = 0;
      final r = PwaImageUrlResolver(
        signer: (p, e) async {
          signed++;
          return 'signed#$signed';
        },
      );
      const path = 'users/u/projects/p/generated/v.jpg';
      expect(await r.resolve(path), 'signed#1');
      r.invalidate(path); // what an image load failure triggers
      expect(await r.resolve(path), 'signed#2');
      // The recovery is a new signature, never a substituted fixture.
      expect(await r.resolve(path), isNot(startsWith('assets/')));
    });

    test('the signing TTL is requested in seconds', () async {
      int? seen;
      final r = PwaImageUrlResolver(
        signer: (p, e) async {
          seen = e;
          return 'u';
        },
        ttl: const Duration(hours: 2),
      );
      await r.resolve('users/u/projects/p/generated/v.jpg');
      expect(seen, 7200);
    });
  });

  group('path classification', () {
    test('storage paths and bundle assets are told apart', () {
      expect(pwaIsStoragePath('users/u/projects/p/generated/v.jpg'), isTrue);
      expect(pwaIsStoragePath('assets/atmospheres/ftue/x.jpg'), isFalse);
      expect(pwaIsStoragePath(''), isFalse);
    });
  });
}
