// Account-scoped state must NOT survive a user change (BUG 1). These unit tests
// drive AuthState events + the fetch through SessionNotifier/PendingGenerations-
// Notifier test seams — no Supabase, no widgets. They prove: sign-out clears the
// old user's sessions IMMEDIATELY, a new anonymous session reloads only its own
// rows, a slow fetch that finishes AFTER a user change is discarded (race guard),
// and pending-generation badges are wiped on sign-out.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ai_home_architect/core/providers/session_provider.dart';
import 'package:ai_home_architect/core/providers/pending_generations_provider.dart';
import 'package:ai_home_architect/data/services/supabase_service.dart';

Map<String, dynamic> _row(String id) => {
  'id': id,
  'title': 't-$id',
  'room_type': 'livingRoom',
  'atmosphere': 'warm_modern',
  'before_image_url': null,
  'latest_preview': 'https://x/$id.png',
  'status': 'completed',
  'created_at': '2026-07-16T00:00:00Z',
  'updated_at': '2026-07-16T00:00:00Z',
};

AuthState _evt(AuthChangeEvent e) => AuthState(e, null);
Future<void> _tick([int ms = 20]) => Future.delayed(Duration(milliseconds: ms));

void main() {
  group('SessionNotifier — auth-scoped invalidation', () {
    test('sign-out clears the old user\'s sessions IMMEDIATELY', () async {
      final ctrl = StreamController<AuthState>.broadcast();
      final n = SessionNotifier(
        SupabaseService(),
        authStream: ctrl.stream,
        currentUid: () => 'old',
        fetchSessions: () async => List.generate(34, (i) => _row('old$i')),
      );
      await _tick();
      expect(n.state.length, 34); // old user loaded

      ctrl.add(_evt(AuthChangeEvent.signedOut));
      await _tick(0);
      expect(n.state, isEmpty); // wiped before any guest UI shows

      await ctrl.close();
      n.dispose();
    });

    test('new anonymous session reloads ONLY its own rows', () async {
      final ctrl = StreamController<AuthState>.broadcast();
      var uid = 'old';
      var rows = List.generate(34, (i) => _row('old$i'));
      final n = SessionNotifier(
        SupabaseService(),
        authStream: ctrl.stream,
        currentUid: () => uid,
        fetchSessions: () async => rows,
      );
      await _tick();
      expect(n.state.length, 34);

      ctrl.add(_evt(AuthChangeEvent.signedOut));
      await _tick(0);
      expect(n.state, isEmpty);

      uid = 'new-anon';
      rows = [_row('new1')];
      ctrl.add(_evt(AuthChangeEvent.signedIn));
      await _tick();
      expect(n.state.length, 1);
      expect(n.state.first.id, 'new1'); // only the new anon's session

      await ctrl.close();
      n.dispose();
    });

    test('slow OLD fetch finishing AFTER a user change is DISCARDED (race)', () async {
      final ctrl = StreamController<AuthState>.broadcast();
      var uid = 'old';
      final oldGate = Completer<List<Map<String, dynamic>>>();
      var useGate = true;
      final n = SessionNotifier(
        SupabaseService(),
        authStream: ctrl.stream,
        currentUid: () => uid,
        fetchSessions: () => useGate ? oldGate.future : Future.value([_row('new1')]),
      );
      await _tick(0);
      expect(n.state, isEmpty); // constructor load still in flight (gated)

      // user change: sign-out then a fresh anon that loads instantly
      ctrl.add(_evt(AuthChangeEvent.signedOut));
      await _tick(0);
      uid = 'new-anon';
      useGate = false;
      ctrl.add(_evt(AuthChangeEvent.signedIn));
      await _tick();
      expect(n.state.length, 1);
      expect(n.state.first.id, 'new1');

      // the OLD slow fetch now returns 34 stale rows — must be ignored
      oldGate.complete(List.generate(34, (i) => _row('old$i')));
      await _tick();
      expect(n.state.length, 1); // still the new anon only
      expect(n.state.first.id, 'new1');

      await ctrl.close();
      n.dispose();
    });
  });

  group('PendingGenerationsNotifier — auth-scoped invalidation', () {
    test('sign-out wipes state + start timestamps', () async {
      final ctrl = StreamController<AuthState>.broadcast();
      final n = PendingGenerationsNotifier(authStream: ctrl.stream);
      n.markInFlight('s1');
      n.markReadyUnseen('s2');
      expect(n.state.length, 2);
      expect(n.startedAt('s1'), isNotNull);

      ctrl.add(_evt(AuthChangeEvent.signedOut));
      await _tick(0);
      expect(n.state, isEmpty);
      expect(n.startedAt('s1'), isNull);

      await ctrl.close();
      n.dispose();
    });
  });
}
