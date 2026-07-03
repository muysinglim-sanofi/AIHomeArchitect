import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_home_architect/core/services/pending_generation_store.dart';
import 'package:ai_home_architect/data/models/pending_generation.dart';

PendingGeneration _p(String sid, {int createdAtMs = 1000}) => PendingGeneration(
      sessionId: sid,
      createdAtMs: createdAtMs,
      prompt: 'p',
      beforeImageUrl: 'b',
      styleLabel: 'st',
      roomType: 'r',
      roomTypeId: 'rid',
      atmosphereId: 'aid',
      iteration: 2,
      history: '[]',
      originalImageUrl: 'o',
      clientRequestId: 'creq-123',
      letAiDecide: true,
      surpriseMe: false,
      structuralIdentity: 'sid-tok',
      versions: 'v-ledger',
      generationMode: 'preserve',
      sourceMode: 'LATEST',
      sourceVersionId: 'ver9',
      uiLocale: 'fr',
      generationTrigger: 'auto',
      generationAttempt: 3,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('save → load round-trips the tuple 1:1 (all fields)', () async {
    final store = await PendingGenerationStore.create();
    await store.save(_p('s1', createdAtMs: 42));
    final p = await store.load('s1');
    expect(p, isNotNull);
    expect(p!.sessionId, 's1');
    expect(p.createdAtMs, 42);
    expect(p.clientRequestId, 'creq-123');
    expect(p.iteration, 2);
    expect(p.letAiDecide, true);
    expect(p.sourceMode, 'LATEST');
    expect(p.sourceVersionId, 'ver9');
    expect(p.uiLocale, 'fr');
    expect(p.generationAttempt, 3);
  });

  test('clear removes the pending', () async {
    final store = await PendingGenerationStore.create();
    await store.save(_p('s1'));
    await store.clear('s1');
    expect(await store.load('s1'), isNull);
  });

  test("save/load ignore 'new' and empty ids (R2: never a real key)", () async {
    final store = await PendingGenerationStore.create();
    await store.save(_p('new'));
    await store.save(_p(''));
    expect(await store.load('new'), isNull);
    expect(await store.load(''), isNull);
    expect(await store.loadAll(), isEmpty);
  });

  test('loadAll returns every pending, skipping unrelated keys', () async {
    SharedPreferences.setMockInitialValues({'unrelated:key': 'x'});
    final store = await PendingGenerationStore.create();
    await store.save(_p('s1'));
    await store.save(_p('s2'));
    final all = await store.loadAll();
    expect(all.map((p) => p.sessionId).toSet(), {'s1', 's2'});
  });

  test('stale schema / malformed json → null (ignored, never misread)', () async {
    SharedPreferences.setMockInitialValues({
      'aih:pending:sbad': '{"schemaVersion": 999, "sessionId": "sbad"}',
      'aih:pending:sjunk': 'not json at all',
    });
    final store = await PendingGenerationStore.create();
    expect(await store.load('sbad'), isNull);
    expect(await store.load('sjunk'), isNull);
    expect(await store.loadAll(), isEmpty);
  });
}
