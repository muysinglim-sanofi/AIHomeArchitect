import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/core/services/pending_recovery_service.dart';
import 'package:ai_home_architect/data/models/pending_generation.dart';

// PR2b Slice 3 — the recovery decision is a PURE function (backend-first). These
// tests pin the 4 branches the user asked to prove.

PendingGeneration _p({required int createdAtMs}) => PendingGeneration(
      sessionId: 's1',
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
  const now = 1000000000000;

  group('PendingRecoveryService.decide', () {
    test('probe == null (request FAILED) → skip (never act blind)', () {
      expect(
        PendingRecoveryService.decide(
            pending: _p(createdAtMs: now), probe: null, nowMs: now),
        RecoveryAction.skip,
      );
    });

    test('intent exists RUNNING → clearOnly (backend wins)', () {
      expect(
        PendingRecoveryService.decide(
            pending: _p(createdAtMs: now),
            probe: {'intent_id': 'abc', 'status': 'RUNNING'},
            nowMs: now),
        RecoveryAction.clearOnly,
      );
    });

    test('intent exists SUCCEEDED → clearOnly', () {
      expect(
        PendingRecoveryService.decide(
            pending: _p(createdAtMs: now),
            probe: {'intent_id': 'abc', 'status': 'SUCCEEDED'},
            nowMs: now),
        RecoveryAction.clearOnly,
      );
    });

    test('intent exists FAILED → clearOnly (not auto-retried)', () {
      expect(
        PendingRecoveryService.decide(
            pending: _p(createdAtMs: now),
            probe: {'intent_id': 'abc', 'status': 'FAILED'},
            nowMs: now),
        RecoveryAction.clearOnly,
      );
    });

    test('no intent + fresh → relaunch', () {
      expect(
        PendingRecoveryService.decide(
            pending: _p(createdAtMs: now - 60000), // 1 min ago
            probe: {'intent_id': null, 'status': null},
            nowMs: now),
        RecoveryAction.relaunch,
      );
    });

    test('no intent + exactly at the 2h boundary → relaunch (not > maxAge)', () {
      expect(
        PendingRecoveryService.decide(
            pending: _p(createdAtMs: now - PendingRecoveryService.maxAgeMs),
            probe: {'intent_id': null},
            nowMs: now),
        RecoveryAction.relaunch,
      );
    });

    test('no intent + older than 2h → dropStale (no re-launch)', () {
      expect(
        PendingRecoveryService.decide(
            pending: _p(createdAtMs: now - PendingRecoveryService.maxAgeMs - 1),
            probe: {'intent_id': null},
            nowMs: now),
        RecoveryAction.dropStale,
      );
    });
  });
}
