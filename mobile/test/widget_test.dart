import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:discover_ai/widgets/selection_card.dart';
import 'package:discover_ai/widgets/chat_bubble.dart';
import 'package:discover_ai/widgets/timeline_item.dart';
import 'package:discover_ai/widgets/custom_tabs.dart';
import 'package:discover_ai/providers/chat_provider.dart';

void main() {
  group('SelectionCard', () {
    testWidgets('renders title and handles tap', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SelectionCard(
            title: 'Test Card',
            isSelected: false,
            onTap: () => tapped = true,
          ),
        ),
      ));
      expect(find.text('Test Card'), findsOneWidget);
      await tester.tap(find.byType(SelectionCard));
      expect(tapped, true);
    });

    testWidgets('shows check when selected', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SelectionCard(title: 'Selected', isSelected: true, onTap: () {}),
        ),
      ));
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });
  });

  group('ChatBubble', () {
    testWidgets('renders user message with primary color', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChatBubble(message: ChatMessage(role: 'user', content: 'Hello')),
        ),
      ));
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('renders assistant message with grey', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChatBubble(message: ChatMessage(role: 'assistant', content: 'Hi there')),
        ),
      ));
      expect(find.text('Hi there'), findsOneWidget);
    });
  });

  group('TimelineItem', () {
    testWidgets('renders title and time', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: TimelineItem(title: 'Visit', time: '10:00')),
      ));
      expect(find.text('Visit'), findsOneWidget);
      expect(find.text('10:00'), findsOneWidget);
    });
  });

  group('CustomTabs', () {
    testWidgets('renders tabs and handles selection', (tester) async {
      int selected = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CustomTabs(
            tabs: const ['A', 'B', 'C'],
            selectedIndex: selected,
            onTap: (i) => selected = i,
          ),
        ),
      ));
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      await tester.tap(find.text('B'));
      expect(selected, 1);
    });
  });
}
