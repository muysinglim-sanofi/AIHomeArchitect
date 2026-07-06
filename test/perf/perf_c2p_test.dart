import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/core/perf/perf_c2p.dart';

// PR0 — click-to-pixel telemetry. Free tests (no widget, no network, no gen).
void main() {
  // The tracker is a singleton that persists across tests → reset each time.
  setUp(() => PerfC2P.instance.resetForTest());

  group('parseServerTimingMs (pure)', () {
    test('present "app;dur=16" → 16.0', () {
      expect(PerfC2P.parseServerTimingMs('app;dur=16'), 16.0);
    });
    test('decimal "app;dur=16.4" → 16.4', () {
      expect(PerfC2P.parseServerTimingMs('app;dur=16.4'), 16.4);
    });
    test('multi-metric "cache;dur=1, app;dur=16" → 16.0 (prefers app)', () {
      expect(PerfC2P.parseServerTimingMs('cache;dur=1, app;dur=16'), 16.0);
    });
    test('no app metric → falls back to first dur', () {
      expect(PerfC2P.parseServerTimingMs('db;dur=5'), 5.0);
    });
    test('absent (null) → null', () {
      expect(PerfC2P.parseServerTimingMs(null), isNull);
    });
    test('empty / whitespace → null', () {
      expect(PerfC2P.parseServerTimingMs(''), isNull);
      expect(PerfC2P.parseServerTimingMs('   '), isNull);
    });
    test('malformed → null (never throws)', () {
      expect(PerfC2P.parseServerTimingMs('garbage-no-dur'), isNull);
      expect(PerfC2P.parseServerTimingMs('app;dur='), isNull);
      expect(PerfC2P.parseServerTimingMs('app;dur=abc'), isNull);
    });
  });

  group('PerfC2P tracker (singleton, keyed by request_id)', () {
    test('first visible frame recorded EXACTLY once per request_id', () {
      final p = PerfC2P.instance;
      p.beginRequest('req-once', genType: 'v1', iteration: 1);
      p.markHttpStart('req-once');
      p.markResponse('req-once', serverAppMs: 20);
      p.markImageLoaded('req-once');
      expect(p.markFirstVisibleFrame('req-once'), isTrue); // 1st → logs
      expect(p.markFirstVisibleFrame('req-once'), isFalse); // 2nd → guarded
      expect(p.isTracking('req-once'), isFalse); // freed after log
    });

    test('two independent request_ids do not interfere', () {
      final p = PerfC2P.instance;
      p.beginRequest('req-A', genType: 'v1', iteration: 1);
      p.beginRequest('req-B', genType: 'switch', iteration: 2);
      expect(p.markFirstVisibleFrame('req-A'), isTrue);
      expect(p.isTracking('req-A'), isFalse);
      expect(p.isTracking('req-B'), isTrue); // B untouched by A
      expect(p.markFirstVisibleFrame('req-B'), isTrue);
    });

    test('unknown / already-freed request_id is safe (no throw, returns false)',
        () {
      final p = PerfC2P.instance;
      expect(p.markFirstVisibleFrame('never-began'), isFalse);
      // marks on unknown ids are silent no-ops, never throw (disposed widget)
      p.markHttpStart('never-began');
      p.markResponse('never-began', serverAppMs: null);
      p.markImageLoaded('never-began');
      p.discard('never-began');
      expect(p.isTracking('never-began'), isFalse);
    });

    test('empty request_id is ignored (never tracked)', () {
      final p = PerfC2P.instance;
      p.beginRequest('', genType: 'v1', iteration: 1);
      expect(p.isTracking(''), isFalse);
    });

    test('server_app_ms null (header absent) does not break the flow', () {
      final p = PerfC2P.instance;
      p.beginRequest('req-null-st', genType: 'v2', iteration: 3);
      p.markResponse('req-null-st', serverAppMs: null);
      p.markImageLoaded('req-null-st');
      expect(p.markFirstVisibleFrame('req-null-st'), isTrue);
    });
  });

  group('reconcile lifecycle (long >60s gen)', () {
    test('#5 tracker survives the long-gen wait (no discard) → first-frame still logs once', () {
      final p = PerfC2P.instance;
      p.beginRequest('recon-long', genType: 'v1', iteration: 1);
      p.markHttpStart('recon-long');
      // >60s elapse, HTTP has NOT returned; the reconcile poll marks the response.
      p.markResponse('recon-long', serverAppMs: null);
      p.markImageLoaded('recon-long');
      expect(p.isTracking('recon-long'), isTrue); // never discarded during reconcile
      expect(p.markFirstVisibleFrame('recon-long'), isTrue); // logs once
      expect(p.markFirstVisibleFrame('recon-long'), isFalse); // #10 — no double log
    });

    test('#8 terminal abandon (reconcile timeout) discards → no first-frame log', () {
      final p = PerfC2P.instance;
      p.beginRequest('recon-abandon', genType: 'v1', iteration: 1);
      p.discard('recon-abandon');
      expect(p.isTracking('recon-abandon'), isFalse);
      expect(p.markFirstVisibleFrame('recon-abandon'), isFalse);
    });

    test('#10 two card instances (nav away + back) → exactly one [PerfC2P]', () {
      final p = PerfC2P.instance;
      p.beginRequest('recon-twocards', genType: 'switch', iteration: 2);
      p.markImageLoaded('recon-twocards');
      expect(p.markFirstVisibleFrame('recon-twocards'), isTrue); // first card
      expect(p.markFirstVisibleFrame('recon-twocards'), isFalse); // second card → no log
    });

    test('observer: exactly ONE real emission with the correct fields (not debugPrint)', () {
      final p = PerfC2P.instance;
      p.beginRequest('obs-1', genType: 'v1', iteration: 1);
      p.markResponse('obs-1', serverAppMs: 20);
      p.markImageLoaded('obs-1');
      p.markFirstVisibleFrame('obs-1');
      p.markFirstVisibleFrame('obs-1'); // guarded → no 2nd emission
      final hits =
          p.emittedForTest.where((e) => e['request_id'] == 'obs-1').toList();
      expect(hits.length, 1); // observed, not parsed from logs
      expect(hits.single['generation_type'], 'v1');
      expect(hits.single['server_app_ms'], 20);
    });
  });

  group('widget mount / dispose (real)', () {
    testWidgets(
        'first-frame mark scheduled at dispose fires safely AFTER the card is gone',
        (tester) async {
      PerfC2P.instance.beginRequest('wt-dispose', genType: 'v1', iteration: 1);
      await tester.pumpWidget(
          const MaterialApp(home: _DisposableProbe(requestId: 'wt-dispose')));
      expect(find.byType(_DisposableProbe), findsOneWidget);
      // Replace the tree → the probe is DISPOSED; its dispose() schedules the
      // same post-frame first-frame mark the real image card uses.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      expect(find.byType(_DisposableProbe), findsNothing);
      await tester.pump(); // run pending post-frame callbacks (widget already gone)
      expect(tester.takeException(), isNull); // no crash after dispose
      expect(PerfC2P.instance.isTracking('wt-dispose'), isFalse); // mark actually ran
    });
  });
}

/// Mirrors the real image card: on dispose it schedules the first-frame mark to
/// run AFTER this State is gone. If markFirstVisibleFrame touched context /
/// setState, this would throw — proving the hook is genuinely disposal-safe.
class _DisposableProbe extends StatefulWidget {
  const _DisposableProbe({required this.requestId});
  final String requestId;
  @override
  State<_DisposableProbe> createState() => _DisposableProbeState();
}

class _DisposableProbeState extends State<_DisposableProbe> {
  @override
  void dispose() {
    final id = widget.requestId;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => PerfC2P.instance.markFirstVisibleFrame(id));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
