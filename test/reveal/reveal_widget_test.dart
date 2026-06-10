import 'package:ai_home_architect/shared/reveal/reveal_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _harness(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 300, height: 200, child: child),
        ),
      ),
    );

void main() {
  group('RevealWidget', () {
    testWidgets('renders the feathered sweep with before+after', (tester) async {
      await tester.pumpWidget(_harness(
        const RevealWidget(
          afterImage: ColoredBox(color: Color(0xFF00FF00)),
          beforeImage: ColoredBox(color: Color(0xFFFF0000)),
          autoPlay: false,
        ),
      ));

      expect(find.byType(ShaderMask), findsOneWidget); // the sweep
    });

    testWidgets('AUTO mode shows NO chrome (no handle / no divider)',
        (tester) async {
      await tester.pumpWidget(_harness(
        const RevealWidget(
          afterImage: ColoredBox(color: Color(0xFF00FF00)),
          beforeImage: ColoredBox(color: Color(0xFFFF0000)),
          autoPlay: false,
        ),
      ));

      expect(find.byKey(const Key('reveal_handle')), findsNothing);
      expect(find.byKey(const Key('reveal_divider')), findsNothing);
    });

    testWidgets('MANUAL mode (after a drag) shows divider + handle',
        (tester) async {
      await tester.pumpWidget(_harness(
        const RevealWidget(
          afterImage: ColoredBox(color: Color(0xFF00FF00)),
          beforeImage: ColoredBox(color: Color(0xFFFF0000)),
          autoPlay: false,
          interaction: RevealInteraction.surface,
        ),
      ));

      // Dragging switches the controller to manual → chrome appears.
      await tester.drag(find.byType(RevealWidget), const Offset(-40, 0));
      await tester.pump();

      expect(find.byKey(const Key('reveal_handle')), findsOneWidget);
      expect(find.byKey(const Key('reveal_divider')), findsOneWidget);
    });

    testWidgets('after auto-play completes, chrome reappears (slider cue)',
        (tester) async {
      await tester.pumpWidget(_harness(
        const RevealWidget(
          afterImage: ColoredBox(color: Color(0xFF00FF00)),
          beforeImage: ColoredBox(color: Color(0xFFFF0000)),
          autoPlay: true,
        ),
      ));

      await tester.pump(); // post-frame → play()
      // During the reveal: no chrome yet.
      expect(find.byKey(const Key('reveal_handle')), findsNothing);

      // Run past the cinematic total (~5.8s) to completion.
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();

      // Settled on AFTER → handle parks at the left as the "still draggable" cue.
      expect(find.byKey(const Key('reveal_handle')), findsOneWidget);
      expect(find.byKey(const Key('reveal_divider')), findsOneWidget);
    });

    testWidgets('no before ⇒ just the after image, no reveal machinery',
        (tester) async {
      await tester.pumpWidget(_harness(
        const RevealWidget(
          afterImage: ColoredBox(color: Color(0xFF00FF00)),
          autoPlay: false,
        ),
      ));

      expect(find.byType(ShaderMask), findsNothing);
      expect(find.byKey(const Key('reveal_handle')), findsNothing);
    });
  });
}
