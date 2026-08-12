// The working state must feel alive — and must never be able to end anything.
//
// A render takes about two minutes. The previous placeholder was one static
// line for the whole of it, indistinguishable from a hung page. The danger in
// fixing that is the obvious one: a timer that "finishes" the generation, or a
// progress bar measuring a duration nobody knows. Neither is allowed, and both
// are asserted against here.

import 'package:ai_home_architect/features/pwa/presentation/pwa_working_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(List<String> phases) => MaterialApp(
  home: Scaffold(
    body: Center(child: PwaWorkingIndicator(phases: phases)),
  ),
);

void main() {
  group('the loading state is alive', () {
    testWidgets('LOAD01: the first phase appears immediately', (tester) async {
      await tester.pumpWidget(_host(kPwaRefinePhases));
      await tester.pump();
      expect(find.text('Understanding your change'), findsOneWidget);
    });

    testWidgets('LOAD02: the phase advances over time', (tester) async {
      await tester.pumpWidget(_host(kPwaRefinePhases));
      await tester.pump();
      expect(find.text(kPwaRefinePhases[0]), findsOneWidget);

      await tester.pump(kPwaPhaseDuration + const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(kPwaRefinePhases[1]), findsOneWidget);

      await tester.pump(kPwaPhaseDuration + const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(kPwaRefinePhases[2]), findsOneWidget);
    });

    testWidgets('LOAD03: it settles on the LAST phase and stays there', (
      tester,
    ) async {
      await tester.pumpWidget(_host(kPwaRefinePhases));
      await tester.pump();
      // Far beyond every phase boundary — a real render can take minutes.
      for (var i = 0; i < 12; i++) {
        await tester.pump(kPwaPhaseDuration + const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.text(kPwaRefinePhases.last), findsOneWidget);
      expect(
        find.text(kPwaRefinePhases.first),
        findsNothing,
        reason: 'it does not loop back to the beginning',
      );
    });

    testWidgets('LOAD04: no percentage is ever shown', (tester) async {
      await tester.pumpWidget(_host(kPwaRefinePhases));
      await tester.pump(const Duration(seconds: 40));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('LOAD05: each flow gets its own wording', (tester) async {
      for (final phases in [
        kPwaFirstVisionPhases,
        kPwaAtmospherePhases,
        kPwaRefinePhases,
      ]) {
        await tester.pumpWidget(_host(phases));
        await tester.pump();
        expect(find.text(phases.first), findsOneWidget);
      }
      // They are genuinely different sets, not one list relabelled.
      expect({
        kPwaFirstVisionPhases.first,
        kPwaAtmospherePhases.first,
        kPwaRefinePhases.first,
      }, hasLength(3));
    });

    testWidgets('LOAD06: it disposes cleanly mid-flight', (tester) async {
      await tester.pumpWidget(_host(kPwaRefinePhases));
      await tester.pump(const Duration(seconds: 5));
      // Removing it while the timer and animation are live must not throw —
      // this is what happens on every completion and every failure.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(seconds: 60));
      expect(tester.takeException(), isNull);
    });

    testWidgets('LOAD07: an empty phase list degrades quietly', (tester) async {
      await tester.pumpWidget(_host(const []));
      await tester.pump(const Duration(seconds: 30));
      expect(tester.takeException(), isNull);
    });
  });
}
