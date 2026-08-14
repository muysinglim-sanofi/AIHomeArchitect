import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/core/services/pending_recovery_service.dart';
import 'package:ai_home_architect/data/models/pending_generation.dart';

// Issue 11 (2026-08-14) — un Intent resté RUNNING ne doit plus ramener le
// spinner indéfiniment.
//
// Le défaut : `decide()` sortait sur `keepRunning` dès que le backend répondait
// RUNNING, et `maxAgeMs` n'était consulté que dans la branche SANS intent, plus
// bas. Une mort dure du backend (OOM/SIGKILL — aucun handler d'exception ne
// tourne, donc aucun RELEASE) laissait l'Intent RUNNING en base, et chaque
// réouverture de l'app réaffichait « Generating… ».
//
// La correction applique la MÊME borne (maxAgeMs) à la branche RUNNING. Ces
// tests épinglent les deux sens : un RUNNING légitime continue de récupérer,
// un RUNNING périmé s'arrête — et un SUCCEEDED n'est JAMAIS perdu par l'âge.

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

Map<String, dynamic> _running() => {'intent_id': 'i1', 'status': 'RUNNING'};
Map<String, dynamic> _succeeded() => {'intent_id': 'i1', 'status': 'SUCCEEDED'};
Map<String, dynamic> _failed() => {'intent_id': 'i1', 'status': 'FAILED'};
Map<String, dynamic> _noIntent() => {'intent_id': null};

const int _max = PendingRecoveryService.maxAgeMs;

RecoveryAction _decide(Map<String, dynamic>? probe, int ageMs) =>
    PendingRecoveryService.decide(
      pending: _p(createdAtMs: 0),
      probe: probe,
      nowMs: ageMs,
    );

void main() {
  group('Issue 11 — borne d\'âge sur RUNNING', () {
    test('R1 — RUNNING frais → keepRunning (une génération normale dure ~40 s)', () {
      expect(_decide(_running(), 45 * 1000), RecoveryAction.keepRunning);
    });

    test('R2 — RUNNING encore sous la borne → keepRunning', () {
      expect(_decide(_running(), _max - 1), RecoveryAction.keepRunning);
    });

    test('R2b — RUNNING exactement à la borne → keepRunning (strictement >)', () {
      expect(_decide(_running(), _max), RecoveryAction.keepRunning);
    });

    test('R3 — RUNNING au-delà de la borne → ne reste PAS keepRunning', () {
      final action = _decide(_running(), _max + 1);
      expect(action, isNot(RecoveryAction.keepRunning));
      expect(action, RecoveryAction.dropStale);
    });

    test('R3b — RUNNING très périmé (24 h) → dropStale', () {
      expect(_decide(_running(), 24 * 60 * 60 * 1000), RecoveryAction.dropStale);
    });

    test('la borne RUNNING laisse largement passer la fenêtre de réconciliation '
        'serveur (JOB_TIMEOUT 12 min + balayage 5 min ≈ 17 min)', () {
      const reconcileWorstCaseMs = 17 * 60 * 1000;
      expect(reconcileWorstCaseMs, lessThan(_max));
      expect(_decide(_running(), reconcileWorstCaseMs), RecoveryAction.keepRunning);
    });
  });

  group('Issue 11 — sûreté du résultat : un succès n\'est jamais perdu', () {
    test('R5 — SUCCEEDED frais → clearOnly (adoption backend, jamais dropStale)', () {
      expect(_decide(_succeeded(), 45 * 1000), RecoveryAction.clearOnly);
    });

    test('R5b — SUCCEEDED TRÈS ancien → clearOnly malgré l\'âge', () {
      // Le garde d'âge ne doit JAMAIS s'appliquer à un terminal : le pending est
      // effacé parce que le backend a gagné, pas parce qu'il est vieux.
      expect(_decide(_succeeded(), 10 * _max), RecoveryAction.clearOnly);
    });

    test('R4 — FAILED → clearOnly quel que soit l\'âge', () {
      expect(_decide(_failed(), 45 * 1000), RecoveryAction.clearOnly);
      expect(_decide(_failed(), 10 * _max), RecoveryAction.clearOnly);
    });
  });

  group('Issue 11 — comportements préexistants préservés', () {
    test('R0/R6 — sonde en échec → skip (ne jamais agir à l\'aveugle)', () {
      expect(_decide(null, 45 * 1000), RecoveryAction.skip);
      expect(_decide(null, 10 * _max), RecoveryAction.skip);
    });

    test('R6b — aucun intent + pending frais → relaunch (inchangé)', () {
      expect(_decide(_noIntent(), 45 * 1000), RecoveryAction.relaunch);
    });

    test('R7 — aucun intent + pending périmé → dropStale (inchangé)', () {
      expect(_decide(_noIntent(), _max + 1), RecoveryAction.dropStale);
    });

    test('R7b — aucun intent, bornes exactes', () {
      expect(_decide(_noIntent(), _max), RecoveryAction.relaunch);
      expect(_decide(_noIntent(), _max + 1), RecoveryAction.dropStale);
    });

    test('un statut inconnu reste terminal → clearOnly', () {
      expect(_decide({'intent_id': 'i1', 'status': 'WHATEVER'}, 45 * 1000),
          RecoveryAction.clearOnly);
    });
  });
}
