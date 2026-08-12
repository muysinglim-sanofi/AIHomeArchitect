// The staging generation client — contract, idempotency, error mapping and
// secret hygiene. Driven against a real local HTTP server rather than a mocked
// Dio, so the wire shape is actually exercised. No real generation is triggered:
// the server returns fixtures.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_home_architect/features/pwa/data/pwa_generation_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// A throwaway backend that records what it was sent.
class _FakeBackend {
  late HttpServer _server;
  final requests = <Map<String, dynamic>>[];
  final headers = <HttpHeaders>[];
  int status = 200;
  Object body = const {
    'status': 'completed',
    'replayed': false,
    'vision_id': 'v-1',
    'vision_number': 1,
    'image_path': 'users/u/projects/p/generated/v-1.jpg',
  };
  Duration delay = Duration.zero;

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(() async {
      await for (final req in _server) {
        final raw = await utf8.decoder.bind(req).join();
        requests.add(jsonDecode(raw) as Map<String, dynamic>);
        headers.add(req.headers);
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        req.response.statusCode = status;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(body));
        await req.response.close();
      }
    }());
  }

  Future<void> stop() => _server.close(force: true);
}

PwaGenerationRequest _req({String idem = 'idem-1', int n = 1}) =>
    PwaGenerationRequest(
      projectId: 'p-1',
      roomId: 'living_room',
      roomLabel: 'Living Room',
      atmosphereId: 'warm_modern',
      atmosphereLabel: 'Warm Modern',
      originalImagePath: 'users/u/projects/p-1/original/o.jpg',
      idempotencyKey: idem,
      visionNumber: n,
    );

void main() {
  late _FakeBackend backend;
  late PwaGenerationApi api;

  setUp(() async {
    backend = _FakeBackend();
    await backend.start();
    api = PwaGenerationApi(
      baseUrl: backend.baseUrl,
      tokenProvider: () async => 'test-session-token',
    );
  });

  tearDown(() async {
    api.dispose();
    await backend.stop();
  });

  group('contract', () {
    test('a successful generation is parsed into a typed result', () async {
      final r = await api.generate(_req());
      expect(r.visionId, 'v-1');
      expect(r.visionNumber, 1);
      expect(r.imagePath, endsWith('v-1.jpg'));
      expect(r.replayed, isFalse);
    });

    test('the request carries structured intent — and no prompt', () async {
      await api.generate(
        PwaGenerationRequest(
          projectId: 'p-9',
          roomId: 'bedroom',
          roomLabel: 'Bedroom',
          atmosphereId: 'japandi_calm',
          atmosphereLabel: 'Japandi Calm',
          originalImagePath: 'users/u/projects/p-9/original/o.jpg',
          idempotencyKey: 'k-9',
          actionType: 'refine',
          parentVisionId: 'v-8',
          userInstruction: 'warmer lighting',
          visionNumber: 2,
        ),
      );
      final sent = backend.requests.single;
      expect(sent['project_id'], 'p-9');
      expect(sent['atmosphere_id'], 'japandi_calm');
      expect(sent['action_type'], 'refine');
      expect(sent['parent_vision_id'], 'v-8');
      expect(sent['user_instruction'], 'warmer lighting');
      expect(sent['vision_number'], 2);
      // The engine owns prompt construction. If one of these ever appears, the
      // business prompt has started leaking into Flutter.
      for (final forbidden in const [
        'prompt',
        'design_prompt',
        'system_prompt',
        'model',
      ]) {
        expect(sent.containsKey(forbidden), isFalse, reason: forbidden);
      }
    });

    test('the session token travels as a bearer header', () async {
      await api.generate(_req());
      expect(
        backend.headers.single.value('authorization'),
        'Bearer test-session-token',
      );
    });

    test('a replayed generation is reported as such', () async {
      backend.body = const {
        'status': 'completed',
        'replayed': true,
        'vision_id': 'v-1',
        'vision_number': 1,
        'image_path': 'users/u/projects/p/generated/v-1.jpg',
      };
      expect((await api.generate(_req())).replayed, isTrue);
    });
  });

  group('idempotency', () {
    test('the key is sent verbatim and is stable across retries', () async {
      await api.generate(_req(idem: 'stable-key'));
      await api.generate(_req(idem: 'stable-key'));
      expect(
        backend.requests.map((r) => r['idempotency_key']),
        everyElement('stable-key'),
      );
    });

    test('a deliberate second generation carries a different key', () async {
      await api.generate(_req(idem: 'first'));
      await api.generate(_req(idem: 'second', n: 2));
      expect(backend.requests[0]['idempotency_key'], 'first');
      expect(backend.requests[1]['idempotency_key'], 'second');
    });
  });

  group('errors', () {
    test('a FastAPI detail envelope is unwrapped', () async {
      backend.status = 403;
      backend.body = const {
        'detail': {
          'error_code': 'PROJECT_FORBIDDEN',
          'user_message': 'This project belongs to a different session.',
          'retryable': false,
        },
      };
      final e = await api
          .generate(_req())
          .then<Object?>((v) => v, onError: (Object e) => e);
      expect(e, isA<PwaGenerationApiError>());
      e as PwaGenerationApiError;
      expect(e.code, 'PROJECT_FORBIDDEN');
      expect(e.userMessage, contains('different session'));
      expect(e.retryable, isFalse);
    });

    test('a flat error envelope works too', () async {
      backend.status = 502;
      backend.body = const {
        'error_code': 'EMPTY_RESULT',
        'user_message': 'The engine returned no image. Try again.',
        'retryable': true,
      };
      final e =
          await api
                  .generate(_req())
                  .then<Object?>((v) => v, onError: (Object e) => e)
              as PwaGenerationApiError;
      expect(e.code, 'EMPTY_RESULT');
      expect(e.retryable, isTrue);
    });

    test('an unlabelled 5xx is retryable, an unlabelled 4xx is not', () async {
      backend.status = 500;
      backend.body = const {};
      var e =
          await api
                  .generate(_req())
                  .then<Object?>((v) => v, onError: (Object e) => e)
              as PwaGenerationApiError;
      expect(e.retryable, isTrue);

      backend.status = 400;
      e =
          await api
                  .generate(_req())
                  .then<Object?>((v) => v, onError: (Object e) => e)
              as PwaGenerationApiError;
      expect(e.retryable, isFalse);
    });

    test('a malformed success body is an error, never a fake vision', () async {
      backend.body = const {'status': 'completed'}; // no vision_id / image_path
      final e = await api
          .generate(_req())
          .then<Object?>((v) => v, onError: (Object e) => e);
      expect(e, isA<PwaGenerationApiError>());
      expect((e as PwaGenerationApiError).code, 'MALFORMED_RESPONSE');
    });

    test('an unreachable backend is a typed error, not a crash', () async {
      final dead = PwaGenerationApi(
        // Port 1 is reserved and never listening.
        baseUrl: 'http://127.0.0.1:1',
        tokenProvider: () async => 'tok',
      );
      final e =
          await dead
                  .generate(_req())
                  .then<Object?>((v) => v, onError: (Object e) => e)
              as PwaGenerationApiError;
      expect(e.code, anyOf('BACKEND_UNREACHABLE', 'NETWORK_ERROR'));
      expect(e.retryable, isTrue);
      dead.dispose();
    });

    test('a missing session never reaches the network', () async {
      final anon = PwaGenerationApi(
        baseUrl: backend.baseUrl,
        tokenProvider: () async => null,
      );
      final e =
          await anon
                  .generate(_req())
                  .then<Object?>((v) => v, onError: (Object e) => e)
              as PwaGenerationApiError;
      expect(e.code, 'SESSION_EXPIRED');
      expect(e.retryable, isFalse);
      expect(backend.requests, isEmpty);
      anon.dispose();
    });

    test(
      'a save failure is reported as a save failure, not as a bad connection',
      () async {
        // The 2026-08-06 incident: the render succeeded and was billed, the
        // upload to Storage could not open a socket, and the handler died
        // without answering — so the app told the user to check their
        // connection for a problem that had nothing to do with it.
        //
        // The backend answers now. This pins both halves of that answer: a 502
        // is NOT read as an unreachable backend, and the message shown is the
        // one the backend chose.
        backend.status = 502;
        backend.body = const {
          'detail': {
            'error_code': 'RESULT_SAVE_FAILED',
            'user_message':
                'Your vision was created but could not be saved. Try again.',
            'retryable': true,
          },
        };
        final e =
            await api
                    .generate(_req())
                    .then<Object?>((v) => v, onError: (Object e) => e)
                as PwaGenerationApiError;

        expect(e.code, 'RESULT_SAVE_FAILED');
        expect(e.code, isNot('BACKEND_UNREACHABLE'));
        expect(e.userMessage, contains('could not be saved'));
        expect(
          e.userMessage.toLowerCase(),
          isNot(contains('connection')),
          reason: 'a storage outage is not a connectivity problem',
        );
        expect(e.retryable, isTrue);
      },
    );

    test('the failure kinds stay distinguishable', () async {
      // One message per cause, so "can't reach Ayden" means exactly that.
      final seen = <String, String>{};
      for (final kind in const [
        ('UPSTREAM_UNAVAILABLE', 'Ayden could not reach its storage.'),
        ('SOURCE_FETCH_FAILED', "Couldn't load your photo. Try again."),
        ('PERSIST_FAILED', 'Your vision could not be saved. Try again.'),
        ('SESSION_EXPIRED', 'Your session expired. Reload to continue.'),
      ]) {
        backend.status = kind.$1 == 'SESSION_EXPIRED' ? 401 : 502;
        backend.body = {
          'detail': {
            'error_code': kind.$1,
            'user_message': kind.$2,
            'retryable': kind.$1 != 'SESSION_EXPIRED',
          },
        };
        final e =
            await api
                    .generate(_req())
                    .then<Object?>((v) => v, onError: (Object e) => e)
                as PwaGenerationApiError;
        expect(e.code, kind.$1);
        seen[e.code] = e.userMessage;
      }
      expect(seen, hasLength(4));
      expect(
        seen.values.toSet(),
        hasLength(4),
        reason: 'four causes must not collapse into one message',
      );
    });

    test('no error message ever carries the session token', () async {
      backend.status = 500;
      backend.body = const {};
      final e =
          await api
                  .generate(_req())
                  .then<Object?>((v) => v, onError: (Object e) => e)
              as PwaGenerationApiError;
      expect(e.toString(), isNot(contains('test-session-token')));
      expect(e.userMessage, isNot(contains('test-session-token')));
    });
  });

  group('lifecycle', () {
    test('dispose cancels an in-flight generation', () async {
      backend.delay = const Duration(seconds: 5);
      final pending = api
          .generate(_req())
          .then<Object?>((v) => v, onError: (Object e) => e);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      api.dispose();
      final e = await pending;
      expect(e, isA<PwaGenerationApiError>());
      expect((e as PwaGenerationApiError).code, 'CANCELLED');
    });

    test('a disposed client refuses to start a new generation', () async {
      api.dispose();
      final e = await api
          .generate(_req())
          .then<Object?>((v) => v, onError: (Object e) => e);
      expect((e as PwaGenerationApiError).code, 'CANCELLED');
      expect(backend.requests, isEmpty);
    });
  });

  group('timeouts', () {
    test('the receive timeout outlasts a real render by a wide margin', () {
      // Measured against the live engine: 115 s and 125 s for a first vision.
      // The guard is the margin, not the number — a client that gives up at
      // 2 minutes would fail renders that were about to succeed.
      expect(kPwaGenerateReceiveTimeout.inSeconds, greaterThan(125 * 2));
    });
  });
}
