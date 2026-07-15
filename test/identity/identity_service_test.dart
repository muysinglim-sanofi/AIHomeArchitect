// FT2-A — IdentityService pure-classification tests.
//
// No real network: every case drives the PURE result factories
// (Result.from(statusCode, data)) + the pure header helper, mirroring the
// repo's "test the pure function" convention (e.g. restoreOutcomeFromSync).
// Covers the four dormant endpoints' success/idempotence/feature-OFF/merged/
// retryable/terminal mappings + the dormant flag default.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/data/services/identity_service.dart';
import 'package:ai_home_architect/core/feature_flags.dart';

Map<String, dynamic> _err(String code) => {
  'detail': {'error_code': code, 'user_message': 'x'},
};

/// Fake Dio adapter: records the OUTGOING request (method / path / headers /
/// wire body) and returns a canned response — or throws a transport error.
/// No socket is ever opened, so these are real HTTP-layer tests with zero
/// network. Reading `requestStream` captures the exact serialized body bytes.
class _CapturingAdapter implements HttpClientAdapter {
  _CapturingAdapter({
    this.status = 200,
    this.body,
    this.throwTransport = false,
  });

  int status;
  Object? body; // encoded as JSON response body when non-null
  bool throwTransport;

  RequestOptions? last;
  String? capturedBody; // exact bytes sent on the wire (null if no body)

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    if (requestStream != null) {
      final chunks = await requestStream.toList();
      final bytes = chunks.expand((c) => c).toList();
      capturedBody = bytes.isEmpty ? null : utf8.decode(bytes);
    }
    if (throwTransport) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'boom',
      );
    }
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Builds a dormant IdentityService whose Dio is wired to [adapter] (fake
/// transport) with a fixed test [token]. validateStatus mirrors production
/// (< 500) so 4xx bodies are read, not thrown.
IdentityService _svc(_CapturingAdapter adapter, {String? token = 'jwt-abc'}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'http://test.local',
      validateStatus: (s) => s != null && s < 500,
    ),
  )..httpClientAdapter = adapter;
  return IdentityService(dio: dio, accessTokenProvider: () => token);
}

void main() {
  group('IdentityService — anon-init', () {
    test('1. 200 {eligible:true, reason:marked} → success', () {
      final r = AnonInitResult.from(200, {
        'eligible': true,
        'reason': 'marked',
      });
      expect(r.outcome, IdentityOutcome.success);
      expect(r.eligible, true);
      expect(r.reason, 'marked');
      expect(r.errorCode, isNull);
    });
    test(
      '200 not_anonymous business reason still success (eligible:false)',
      () {
        final r = AnonInitResult.from(200, {
          'eligible': false,
          'reason': 'not_anonymous',
        });
        expect(r.outcome, IdentityOutcome.success);
        expect(r.eligible, false);
        expect(r.reason, 'not_anonymous');
      },
    );
    test('2. 404 not_found (backend flag OFF) → featureDisabled', () {
      final r = AnonInitResult.from(404, _err('not_found'));
      expect(r.outcome, IdentityOutcome.featureDisabled);
    });
  });

  group('IdentityService — claim-signup-bonus', () {
    test('3. 200 granted +2 → success / isGranted', () {
      final r = SignupBonusResult.from(200, {
        'decision': 'granted',
        'bonus_granted': 2,
        'reason': '',
      });
      expect(r.outcome, IdentityOutcome.success);
      expect(r.decision, 'granted');
      expect(r.bonusGranted, 2);
      expect(r.isGranted, true);
      expect(r.isAlready, false);
    });
    test(
      '4. 200 already_entitled (legacy TRIAL+3) bonus 0 → success / isAlready',
      () {
        final r = SignupBonusResult.from(200, {
          'decision': 'already_entitled',
          'bonus_granted': 0,
        });
        expect(r.outcome, IdentityOutcome.success);
        expect(r.bonusGranted, 0);
        expect(r.isAlready, true);
        expect(r.isGranted, false);
      },
    );
    test(
      '5. 200 already_processed (double call idempotent) → success / isAlready',
      () {
        final r = SignupBonusResult.from(200, {
          'decision': 'already_processed',
          'bonus_granted': 0,
        });
        expect(r.outcome, IdentityOutcome.success);
        expect(r.isAlready, true);
      },
    );
    test('200 not_eligible (existing account) → success (no bonus)', () {
      final r = SignupBonusResult.from(200, {
        'decision': 'not_eligible',
        'bonus_granted': 0,
        'reason': 'not_marked_eligible',
      });
      expect(r.outcome, IdentityOutcome.success);
      expect(r.decision, 'not_eligible');
      expect(r.isGranted, false);
    });
  });

  group('IdentityService — merged_closed guard', () {
    test('6. 403 identity_merged → mergedIdentity (all endpoints)', () {
      expect(
        AnonInitResult.from(403, _err('identity_merged')).outcome,
        IdentityOutcome.mergedIdentity,
      );
      expect(
        SignupBonusResult.from(403, _err('identity_merged')).outcome,
        IdentityOutcome.mergedIdentity,
      );
      expect(
        MergeTicketResult.from(403, _err('identity_merged')).outcome,
        IdentityOutcome.mergedIdentity,
      );
      expect(
        ClaimResult.from(403, _err('identity_merged')).outcome,
        IdentityOutcome.mergedIdentity,
      );
    });
  });

  group('IdentityService — merge-ticket & claim', () {
    test('7. merge-ticket 200 {ticket, expires_at} → success', () {
      final r = MergeTicketResult.from(200, {
        'ticket': 'abc-DEF_123',
        'expires_at': '2026-07-15T10:00:00Z',
      });
      expect(r.outcome, IdentityOutcome.success);
      expect(r.ticket, 'abc-DEF_123');
      expect(r.expiresAt, '2026-07-15T10:00:00Z');
    });
    test(
      '8. claim 410 ticket_expired / 404 ticket_invalid → terminalFailure',
      () {
        expect(
          ClaimResult.from(410, _err('ticket_expired')).outcome,
          IdentityOutcome.terminalFailure,
        );
        final inv = ClaimResult.from(404, _err('ticket_invalid'));
        expect(inv.outcome, IdentityOutcome.terminalFailure);
        expect(inv.errorCode, 'ticket_invalid');
      },
    );
    test('merge-ticket 400 not_anonymous → terminalFailure', () {
      expect(
        MergeTicketResult.from(400, _err('not_anonymous')).outcome,
        IdentityOutcome.terminalFailure,
      );
    });
    test('9. claim 200 {status:completed, merge_id} → success', () {
      final r = ClaimResult.from(200, {
        'status': 'completed',
        'merge_id': '11111111-2222-3333-4444-555555555555',
      });
      expect(r.outcome, IdentityOutcome.success);
      expect(r.status, 'completed');
      expect(r.mergeId, isNotNull);
    });
    test('claim 202 identity_merge_pending → success (async finalize)', () {
      final r = ClaimResult.from(202, {
        'status': 'identity_merge_pending',
        'merge_id': 'm1',
      });
      expect(r.outcome, IdentityOutcome.success);
      expect(r.status, 'identity_merge_pending');
    });
    test(
      '10. claim 409 both_users_premium (merged conflict) → terminalFailure',
      () {
        final r = ClaimResult.from(409, _err('both_users_premium'));
        expect(r.outcome, IdentityOutcome.terminalFailure);
        expect(r.errorCode, 'both_users_premium');
      },
    );
    test('claim 409 conflict carries existing_merge_id loss-lessly', () {
      final r = ClaimResult.from(409, {
        'detail': {'error_code': 'conflict', 'existing_merge_id': 'em-123'},
      });
      expect(r.outcome, IdentityOutcome.terminalFailure);
      expect(r.errorCode, 'conflict');
      expect(r.existingMergeId, 'em-123');
    });
  });

  group('IdentityService — retryable & auth', () {
    test('11. network (null status) & 503 → retryableFailure', () {
      expect(
        AnonInitResult.from(null, null).outcome,
        IdentityOutcome.retryableFailure,
      );
      expect(
        SignupBonusResult.from(503, _err('signup_bonus_unavailable')).outcome,
        IdentityOutcome.retryableFailure,
      );
      expect(
        ClaimResult.from(503, _err('identity_rpc_unavailable')).outcome,
        IdentityOutcome.retryableFailure,
      );
    });
    test(
      '11b. claim 409 settlement_active → retryableFailure (not terminal)',
      () {
        expect(
          ClaimResult.from(409, _err('settlement_active')).outcome,
          IdentityOutcome.retryableFailure,
        );
      },
    );
    test(
      '12. JWT absent/empty → no Authorization header; present → Bearer',
      () {
        expect(bearerHeader(null), isNull);
        expect(bearerHeader(''), isNull);
        expect(bearerHeader('jwt-token'), 'Bearer jwt-token');
      },
    );
    test(
      '13. result models expose only business fields (no JWT/secret leak)',
      () {
        final r = SignupBonusResult.from(200, {
          'decision': 'granted',
          'bonus_granted': 2,
        });
        // Public surface = business-only (decision/bonusGranted/reason/errorCode/outcome).
        expect(r.reason, isNull);
        expect(r.errorCode, isNull);
        expect(r.toString().toLowerCase(), isNot(contains('bearer')));
        expect(r.toString().toLowerCase(), isNot(contains('authorization')));
      },
    );
  });

  group('FT2 flag', () {
    test('freeTrialAuthGate default false (dormant)', () {
      expect(FeatureFlags.freeTrialAuthGate, isFalse);
    });
  });

  // ── HTTP-level tests: the four PUBLIC methods over a fake adapter ──────────
  // Prove the real wire contract (method / URL / body / JWT) without a network.

  group('IdentityService.anonInit — HTTP', () {
    test(
      'A. POST /identity/anon-init, no business body, Bearer set, 200→success',
      () async {
        final a = _CapturingAdapter(
          status: 200,
          body: {'eligible': true, 'reason': 'marked'},
        );
        final r = await _svc(a).anonInit();

        expect(a.last!.method, 'POST');
        expect(a.last!.path, '/identity/anon-init');
        expect(a.last!.headers['Authorization'], 'Bearer jwt-abc');
        // No invented body (no user_id, nothing) — endpoint derives user from JWT.
        expect(a.capturedBody == null || a.capturedBody!.isEmpty, isTrue);
        expect(r.outcome, IdentityOutcome.success);
        expect(r.eligible, true);
        expect(r.reason, 'marked');
      },
    );

    test('A. 404 not_found (server flag OFF) → featureDisabled', () async {
      final a = _CapturingAdapter(status: 404, body: _err('not_found'));
      final r = await _svc(a).anonInit();
      expect(a.last!.path, '/identity/anon-init');
      expect(r.outcome, IdentityOutcome.featureDisabled);
    });
  });

  group('IdentityService.claimSignupBonus — HTTP', () {
    test(
      'B. POST /identity/claim-signup-bonus, no body, granted→success',
      () async {
        final a = _CapturingAdapter(
          status: 200,
          body: {'decision': 'granted', 'bonus_granted': 2, 'reason': ''},
        );
        final r = await _svc(a).claimSignupBonus();

        expect(a.last!.method, 'POST');
        expect(a.last!.path, '/identity/claim-signup-bonus');
        expect(a.last!.headers['Authorization'], 'Bearer jwt-abc');
        // No user_id / body invented by the client.
        expect(a.capturedBody == null || a.capturedBody!.isEmpty, isTrue);
        expect(r.outcome, IdentityOutcome.success);
        expect(r.isGranted, true);
        expect(r.bonusGranted, 2);
      },
    );

    test('B. 200 already_entitled → success / isAlready', () async {
      final a = _CapturingAdapter(
        status: 200,
        body: {'decision': 'already_entitled', 'bonus_granted': 0},
      );
      final r = await _svc(a).claimSignupBonus();
      expect(r.outcome, IdentityOutcome.success);
      expect(r.isAlready, true);
    });

    test('B. 403 identity_merged → mergedIdentity', () async {
      final a = _CapturingAdapter(status: 403, body: _err('identity_merged'));
      final r = await _svc(a).claimSignupBonus();
      expect(a.last!.path, '/identity/claim-signup-bonus');
      expect(r.outcome, IdentityOutcome.mergedIdentity);
    });
  });

  group('IdentityService.createMergeTicket — HTTP', () {
    test(
      'C. POST /identity/merge-ticket, no body, ticket/expires_at parsed',
      () async {
        final a = _CapturingAdapter(
          status: 200,
          body: {'ticket': 'T-abc_123', 'expires_at': '2026-07-15T10:00:00Z'},
        );
        final r = await _svc(a).createMergeTicket();

        expect(a.last!.method, 'POST');
        expect(a.last!.path, '/identity/merge-ticket');
        expect(a.last!.headers['Authorization'], 'Bearer jwt-abc');
        expect(a.capturedBody == null || a.capturedBody!.isEmpty, isTrue);
        expect(r.outcome, IdentityOutcome.success);
        expect(r.ticket, 'T-abc_123');
        expect(r.expiresAt, '2026-07-15T10:00:00Z');
        // The raw ticket must NOT surface in the result's toString().
        expect(r.toString().contains('T-abc_123'), isFalse);
      },
    );

    test('C. 400 not_anonymous → terminalFailure', () async {
      final a = _CapturingAdapter(status: 400, body: _err('not_anonymous'));
      final r = await _svc(a).createMergeTicket();
      expect(a.last!.path, '/identity/merge-ticket');
      expect(r.outcome, IdentityOutcome.terminalFailure);
    });
  });

  group('IdentityService.claimExistingIdentity — HTTP', () {
    test(
      'D. POST /identity/claim, body EXACTLY {ticket}, 200→success',
      () async {
        final a = _CapturingAdapter(
          status: 200,
          body: {
            'status': 'completed',
            'merge_id': '11111111-2222-3333-4444-555555555555',
          },
        );
        final r = await _svc(a).claimExistingIdentity('T-xyz_789');

        expect(a.last!.method, 'POST');
        expect(a.last!.path, '/identity/claim');
        expect(a.last!.headers['Authorization'], 'Bearer jwt-abc');
        // Body is exactly {"ticket": "..."} — no user_id, nothing else.
        expect(jsonDecode(a.capturedBody!), {'ticket': 'T-xyz_789'});
        expect(r.outcome, IdentityOutcome.success);
        expect(r.status, 'completed');
        expect(r.mergeId, isNotNull);
      },
    );

    test('D. 202 identity_merge_pending → success', () async {
      final a = _CapturingAdapter(
        status: 202,
        body: {'status': 'identity_merge_pending', 'merge_id': 'm1'},
      );
      final r = await _svc(a).claimExistingIdentity('T-1');
      expect(r.outcome, IdentityOutcome.success);
      expect(r.status, 'identity_merge_pending');
    });

    test(
      'D. 404 ticket_invalid → terminalFailure (distinct from anon 404)',
      () async {
        final a = _CapturingAdapter(status: 404, body: _err('ticket_invalid'));
        final r = await _svc(a).claimExistingIdentity('T-bad');
        // Same HTTP status as anon-init's featureDisabled, but different code →
        // different outcome. This is the two-404 discrimination.
        expect(r.outcome, IdentityOutcome.terminalFailure);
        expect(r.errorCode, 'ticket_invalid');
        expect(r.outcome, isNot(IdentityOutcome.featureDisabled));
      },
    );

    test('D. 410 ticket_expired → terminalFailure', () async {
      final a = _CapturingAdapter(status: 410, body: _err('ticket_expired'));
      final r = await _svc(a).claimExistingIdentity('T-old');
      expect(r.outcome, IdentityOutcome.terminalFailure);
    });

    test('D. 409 settlement_active → retryableFailure', () async {
      final a = _CapturingAdapter(status: 409, body: _err('settlement_active'));
      final r = await _svc(a).claimExistingIdentity('T-busy');
      expect(r.outcome, IdentityOutcome.retryableFailure);
    });

    test('D. 409 conflict carries existing_merge_id (loss-less)', () async {
      final a = _CapturingAdapter(
        status: 409,
        body: {
          'detail': {'error_code': 'conflict', 'existing_merge_id': 'em-42'},
        },
      );
      final r = await _svc(a).claimExistingIdentity('T-dup');
      expect(r.outcome, IdentityOutcome.terminalFailure);
      expect(r.existingMergeId, 'em-42');
    });
  });

  group('IdentityService — auth header at request time', () {
    test('E1. no token → no Authorization header', () async {
      final a = _CapturingAdapter(
        status: 200,
        body: {'eligible': true, 'reason': 'marked'},
      );
      await _svc(a, token: null).anonInit();
      expect(a.last!.headers.containsKey('Authorization'), isFalse);
    });

    test(
      'E2. token change between calls → 2nd request uses NEW token',
      () async {
        String? tok = 'first';
        final a = _CapturingAdapter(
          status: 200,
          body: {'eligible': true, 'reason': 'marked'},
        );
        final dio = Dio(
          BaseOptions(validateStatus: (s) => s != null && s < 500),
        )..httpClientAdapter = a;
        final svc = IdentityService(dio: dio, accessTokenProvider: () => tok);

        await svc.anonInit();
        expect(a.last!.headers['Authorization'], 'Bearer first');
        tok = 'second'; // simulate a session refresh
        await svc.anonInit();
        expect(a.last!.headers['Authorization'], 'Bearer second');
      },
    );
  });

  group('IdentityService — transport error', () {
    test(
      'F. adapter throws → no throw, retryableFailure, no token leak',
      () async {
        final a = _CapturingAdapter(throwTransport: true);
        final r = await _svc(a).claimExistingIdentity('T-secret');

        expect(r.outcome, IdentityOutcome.retryableFailure);
        expect(r.errorCode, 'network');
        final dump = r.toString().toLowerCase();
        expect(dump.contains('bearer'), isFalse);
        expect(dump.contains('t-secret'), isFalse);
        expect(dump.contains('authorization'), isFalse);
      },
    );
  });
}
