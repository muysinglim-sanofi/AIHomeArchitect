import 'package:ai_home_architect/features/cards/cards_preview_screen.dart';
import 'package:ai_home_architect/features/cards/widgets/ai_action_card.dart';
import 'package:ai_home_architect/features/cards/widgets/room_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CardsPreviewScreen', () {
    testWidgets('renders the rooms section with indoor cards', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: CardsPreviewScreen()));
      await tester.pump();

      expect(find.text('ROOMS'), findsOneWidget);
      expect(find.text('More Spaces'), findsOneWidget);
      expect(find.byType(RoomCard), findsWidgets);
    });
  });

  group('RoomCard', () {
    testWidgets('fires onTap and shows the check when selected',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 140,
            child: RoomCard(
              label: 'Living Room',
              asset: 'assets/cards/rooms/living_room.png',
              selected: true,
              onTap: () => tapped = true,
            ),
          ),
        ),
      ));

      expect(find.text('Living Room'), findsOneWidget); // Title Case, no number
      expect(find.byIcon(Icons.check), findsOneWidget); // selected
      await tester.tap(find.byType(RoomCard));
      expect(tapped, isTrue);
    });
  });

  group('AiActionCard', () {
    testWidgets('renders title (uppercased) + sparkle', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 140,
            child: AiActionCard(
              title: 'AI Decide',
              subtitle: 'Let AI choose the perfect room',
            ),
          ),
        ),
      ));

      expect(find.text('AI DECIDE'), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    });
  });
}
