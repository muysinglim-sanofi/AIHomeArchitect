import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_home_architect/core/services/pending_generation_store.dart';
import 'package:ai_home_architect/core/services/pending_recovery_service.dart';
import 'package:ai_home_architect/data/models/pending_generation.dart';
import 'package:ai_home_architect/data/services/generation_service.dart';

/// Fake GenerationService — controls the backend probe + the /generate outcome,
/// and RECORDS every generate() call so we can prove "no double POST".
class FakeGen extends GenerationService {
  Map<String, dynamic>? probe; // getLatestIntent returns this (null = request failed)
  Object? generateError; // thrown from generate (GenerationException / DioException)
  Map<String, dynamic> generateResult = {'after_image_url': 'http://img'};
  Completer<void>? gate; // if set, generate awaits it (to test sweep overlap)
  final List<String> generated = [];
  int probeCalls = 0;

  @override
  Future<Map<String, dynamic>?> getLatestIntent(String sessionId) async {
    probeCalls++;
    return probe;
  }

  @override
  Future<Map<String, dynamic>> generate({
    required String sessionId,
    required String prompt,
    required String beforeImageUrl,
    required String styleLabel,
    String roomType = '',
    String roomTypeId = '',
    String atmosphereId = '',
    int iteration = 1,
    String history = '',
    String originalImageUrl = '',
    String clientRequestId = '',
    bool letAiDecide = false,
    bool surpriseMe = false,
    String structuralIdentity = '',
    String versions = '',
    String generationMode = 'preserve',
    String sourceMode = '',
    String sourceVersionId = '',
    String uiLocale = 'en',
    String generationTrigger = 'unknown',
    int generationAttempt = 0,
  }) async {
    generated.add(sessionId);
    if (gate != null) await gate!.future;
    if (generateError != null) throw generateError!;
    return generateResult;
  }
}

PendingGeneration _p(String sid, {required int createdAtMs}) => PendingGeneration(
      sessionId: sid,
      createdAtMs: createdAtMs,
      prompt: 'p',
      beforeImageUrl: 'b',
      styleLabel: 'st',
      roomType: 'r',
      roomTypeId: 'rid',
      atmosphereId: 'aid',
      iteration: 1,
      history: '[]',
      originalImageUrl: 'o',
      clientRequestId: 'creq',
      letAiDecide: false,
      surpriseMe: false,
      structuralIdentity: '',
      versions: '',
      generationMode: 'preserve',
      sourceMode: '',
      sourceVersionId: '',
      uiLocale: 'en',
      generationTrigger: 'auto',
      generationAttempt: 0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const now = 10 * 60 * 60 * 1000; // arbitrary "now" (10h) in epoch ms

  setUpAll(() {
    // GenerationService()'s constructor reads dotenv for the base URL.
    dotenv.testLoad(mergeWith: {'API_BASE_URL': 'http://localhost:8000'});
  });

  Future<PendingGenerationStore> storeWith(List<PendingGeneration> ps) async {
    SharedPreferences.setMockInitialValues({});
    final s = await PendingGenerationStore.create();
    for (final p in ps) {
      await s.save(p);
    }
    return s;
  }

  final svc = PendingRecoveryService.instance;

  test('no intent + fresh → RE-LAUNCH once, pending cleared', () async {
    final store = await storeWith([_p('s1', createdAtMs: now - 60000)]);
    final gen = FakeGen()..probe = {'intent_id': null};
    await svc.sweep(gen: gen, store: store, nowMs: now, reason: 'test');
    expect(gen.generated, ['s1']); // exactly one POST
    expect(await store.load('s1'), isNull); // cleared on success
  });

  test('intent RUNNING → clearOnly, NO re-launch (backend wins)', () async {
    final store = await storeWith([_p('s1', createdAtMs: now)]);
    final gen = FakeGen()..probe = {'intent_id': 'x', 'status': 'RUNNING'};
    await svc.sweep(gen: gen, store: store, nowMs: now);
    expect(gen.generated, isEmpty);
    expect(await store.load('s1'), isNull);
  });

  test('intent SUCCEEDED → clearOnly, no re-launch', () async {
    final store = await storeWith([_p('s1', createdAtMs: now)]);
    final gen = FakeGen()..probe = {'intent_id': 'x', 'status': 'SUCCEEDED'};
    await svc.sweep(gen: gen, store: store, nowMs: now);
    expect(gen.generated, isEmpty);
    expect(await store.load('s1'), isNull);
  });

  test('intent FAILED → clearOnly, NOT auto-retried', () async {
    final store = await storeWith([_p('s1', createdAtMs: now)]);
    final gen = FakeGen()..probe = {'intent_id': 'x', 'status': 'FAILED'};
    await svc.sweep(gen: gen, store: store, nowMs: now);
    expect(gen.generated, isEmpty);
    expect(await store.load('s1'), isNull);
  });

  test('probe null (network) → skip, pending KEPT, no re-launch', () async {
    final store = await storeWith([_p('s1', createdAtMs: now)]);
    final gen = FakeGen()..probe = null;
    await svc.sweep(gen: gen, store: store, nowMs: now);
    expect(gen.generated, isEmpty);
    expect(await store.load('s1'), isNotNull); // kept for next sweep
  });

  test('no intent + older than 2h → dropStale, no re-launch, cleared', () async {
    final store = await storeWith(
        [_p('s1', createdAtMs: now - PendingRecoveryService.maxAgeMs - 1)]);
    final gen = FakeGen()..probe = {'intent_id': null};
    await svc.sweep(gen: gen, store: store, nowMs: now);
    expect(gen.generated, isEmpty);
    expect(await store.load('s1'), isNull);
  });

  test('re-launch transport error (DioException) → pending KEPT', () async {
    final store = await storeWith([_p('s1', createdAtMs: now)]);
    final gen = FakeGen()
      ..probe = {'intent_id': null}
      ..generateError =
          DioException(requestOptions: RequestOptions(path: '/generate'));
    await svc.sweep(gen: gen, store: store, nowMs: now);
    expect(gen.generated, ['s1']); // attempted once
    expect(await store.load('s1'), isNotNull); // KEPT (no backend confirmation)
  });

  test('re-launch structured GenerationException → pending cleared', () async {
    final store = await storeWith([_p('s1', createdAtMs: now)]);
    final gen = FakeGen()
      ..probe = {'intent_id': null}
      ..generateError = const GenerationException(
        errorCode: 'QUOTA_EXHAUSTED',
        userMessage: 'x',
        retryable: false,
        quotaExhausted: true,
      );
    await svc.sweep(gen: gen, store: store, nowMs: now);
    expect(gen.generated, ['s1']);
    expect(await store.load('s1'), isNull); // cleared (backend responded)
  });

  test('two pendings → both re-launched exactly once', () async {
    final store = await storeWith(
        [_p('s1', createdAtMs: now), _p('s2', createdAtMs: now)]);
    final gen = FakeGen()..probe = {'intent_id': null};
    await svc.sweep(gen: gen, store: store, nowMs: now);
    expect(gen.generated..sort(), ['s1', 's2']);
    expect(await store.load('s1'), isNull);
    expect(await store.load('s2'), isNull);
  });

  test('concurrent sweeps → second no-ops, generate called ONCE (no double)',
      () async {
    final store = await storeWith([_p('s1', createdAtMs: now)]);
    final gate = Completer<void>();
    final gen = FakeGen()
      ..probe = {'intent_id': null}
      ..gate = gate; // first sweep stalls inside generate()
    final f1 = svc.sweep(gen: gen, store: store, nowMs: now); // in-flight
    final f2 = svc.sweep(gen: gen, store: store, nowMs: now); // guarded → no-op
    await f2; // returns immediately (sweep already running)
    gate.complete();
    await f1;
    expect(gen.generated, ['s1']); // exactly one → the guard held
    expect(await store.load('s1'), isNull);
  });

  test('#5 deleted session (pending cleared) → sweep re-launches NOTHING',
      () async {
    final store = await storeWith([_p('s1', createdAtMs: now)]);
    // Simulate the delete handler (SessionNotifier.deleteSession) clearing the
    // pending. Even though the backend would report "no intent" for the (now
    // deleted) session, the sweep must NOT re-launch an orphan generation.
    await store.clear('s1');
    final gen = FakeGen()..probe = {'intent_id': null};
    await svc.sweep(gen: gen, store: store, nowMs: now);
    expect(gen.generated, isEmpty); // no orphan OpenAI call
    expect(await store.loadAll(), isEmpty);
  });
}
