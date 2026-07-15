// FT2-B spike — pure model / guard / state-machine tests (no network, no device).
// The trustworthy logic (phase ordering, protected-account guard, UUID- and
// session-preservation, sanitized-report shape) is proven here; the device run
// only supplies raw inputs. The REAL Supabase error code is NOT asserted here —
// it will be captured on-device.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/debug/ft2b_spike/ft2b_spike_models.dart';

void main() {
  group('state machine — Phase C cannot precede Phase B', () {
    test('canRunPhaseC only at phaseCPrepared', () {
      expect(canRunPhaseC(SpikePhase.start), isFalse);
      expect(canRunPhaseC(SpikePhase.anonReady), isFalse);
      expect(
        canRunPhaseC(SpikePhase.phaseBDone),
        isFalse,
      ); // must prepare first
      expect(canRunPhaseC(SpikePhase.phaseCPrepared), isTrue);
      expect(canRunPhaseC(SpikePhase.phaseCDone), isFalse);
    });

    test('canPreparePhaseC only after Phase B', () {
      expect(canPreparePhaseC(SpikePhase.start), isFalse);
      expect(canPreparePhaseC(SpikePhase.anonReady), isFalse);
      expect(canPreparePhaseC(SpikePhase.phaseBDone), isTrue);
    });

    test('canRunPhaseB needs anonReady AND isAnonymous', () {
      expect(canRunPhaseB(SpikePhase.anonReady, isAnonymous: true), isTrue);
      expect(canRunPhaseB(SpikePhase.anonReady, isAnonymous: false), isFalse);
      expect(canRunPhaseB(SpikePhase.start, isAnonymous: true), isFalse);
      expect(canRunPhaseB(SpikePhase.phaseBDone, isAnonymous: true), isFalse);
    });
  });

  group('uuidPreserved', () {
    test('same non-null → true', () {
      expect(uuidPreserved('u-1', 'u-1'), isTrue);
    });
    test('different → false', () {
      expect(uuidPreserved('u-1', 'u-2'), isFalse);
    });
    test('any null → false', () {
      expect(uuidPreserved(null, 'u-1'), isFalse);
      expect(uuidPreserved('u-1', null), isFalse);
    });
  });

  group('sessionPreserved (after Phase C collision)', () {
    test('session present AND user unchanged → true', () {
      expect(
        sessionPreserved(
          hasSessionAfter: true,
          anonIdBefore: 'anon-1',
          activeUserIdAfter: 'anon-1',
        ),
        isTrue,
      );
    });
    test('no session → false', () {
      expect(
        sessionPreserved(
          hasSessionAfter: false,
          anonIdBefore: 'anon-1',
          activeUserIdAfter: 'anon-1',
        ),
        isFalse,
      );
    });
    test('user changed → false', () {
      expect(
        sessionPreserved(
          hasSessionAfter: true,
          anonIdBefore: 'anon-1',
          activeUserIdAfter: 'other',
        ),
        isFalse,
      );
    });
    test('nulls → false', () {
      expect(
        sessionPreserved(
          hasSessionAfter: true,
          anonIdBefore: null,
          activeUserIdAfter: null,
        ),
        isFalse,
      );
    });
  });

  group('protected-account guard', () {
    test('exact protected UUID → true', () {
      expect(isProtectedAccount(kProtectedAccountId), isTrue);
    });
    test('other / null → false', () {
      expect(
        isProtectedAccount('11111111-2222-3333-4444-555555555555'),
        isFalse,
      );
      expect(isProtectedAccount(null), isFalse);
    });
  });

  group('sanitized report — no secret ever leaks', () {
    SpikeReport nastyReport() {
      final err = SpikeAuthError.from(
        error: Object(),
        statusCode: '422',
        code: 'identity_already_exists', // hypothetical — for shape only
        message:
            'already linked. Bearer abcTOKEN123456 jwt eyJaa.eyJbb.SIGcc '
            'email a@b.com nonce=NONCEsecretVALUE',
      );
      final phaseC = PhaseCResult(
        collisionAnonIdBefore: 'anon-2',
        linkSucceeded: false,
        error: err,
        activeUserIdAfter: 'anon-2',
        activeSessionPreserved: true,
        isAnonymousAfter: true,
        identitiesAfter: const [],
      );
      return SpikeReport(
        testUserId: 'anon-2',
        phaseB: null,
        phaseC: phaseC,
        verify: null,
        capturedAtIso: '2026-07-15T00:00:00.000Z',
      );
    }

    test('report JSON contains no raw token / jwt / email / nonce', () {
      final json = jsonEncode(nastyReport().toSanitizedJson());
      expect(json.contains('abcTOKEN123456'), isFalse);
      expect(json.contains('eyJaa'), isFalse);
      expect(json.contains('a@b.com'), isFalse);
      expect(json.contains('NONCEsecretVALUE'), isFalse);
      // structural fields ARE present
      expect(json.contains('422'), isTrue);
      expect(json.contains('identity_already_exists'), isTrue);
      expect(json.contains('ft2b_apple_identity_link'), isTrue);
    });

    test('error toString exposes no raw secret', () {
      final dump = nastyReport().phaseC!.error!.toString();
      expect(dump.contains('abcTOKEN123456'), isFalse);
      expect(dump.contains('eyJaa'), isFalse);
      expect(dump.contains('a@b.com'), isFalse);
      expect(dump.contains('NONCEsecretVALUE'), isFalse);
    });

    test('documented versions are pinned in the report', () {
      final map = nastyReport().toSanitizedJson();
      final versions = map['versions'] as Map<String, dynamic>;
      expect(versions['gotrue'], '2.20.0');
      expect(versions['supabase_flutter'], '2.12.4');
    });
  });

  group('VerifySignInResult — Phase B match', () {
    test('same id → matchesPhaseB true via serialization', () {
      const r = VerifySignInResult(
        signedInUserId: 'perm-1',
        phaseBPermanentId: 'perm-1',
        matchesPhaseB: true,
        error: null,
      );
      expect(r.toJson()['matches_phase_b'], true);
    });
  });
}
