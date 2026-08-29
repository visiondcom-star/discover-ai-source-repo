import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:discover_ai/providers/chat_provider.dart';
import 'package:discover_ai/screens/chat_screen.dart';

import 'helpers/fakes.dart';

void main() {
  testWidgets(
      'ChatScreen renders user turn then assistant reply from the API, '
      'and surfaces a real API error without a hardcoded bubble',
      (tester) async {
    final fake = FakeChatApi();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ChatProvider(chatApi: fake)),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Empty state mirrors the web screen.
    expect(find.byKey(const Key('chat_empty')), findsOneWidget);
    expect(find.text('Posez-moi une question sur votre destination.'),
        findsOneWidget);

    // Type a real message and send.
        await tester.enterText(
        find.byKey(const Key('chat_input')),
        'Bonjour, quels sont les sites à Alger ?');
    await tester.pump(); // flush controller listener -> canSend=true
    await tester.tap(find.byKey(const Key('chat_send')));
    await tester.pumpAndSettle();

    // The user turn is added locally...
    expect(find.text('Bonjour, quels sont les sites à Alger ?'), findsOneWidget);
    // ...and the assistant reply is built exclusively from the API envelope.
    expect(fake.calls, 1);
    expect(fake.lastMessage, 'Bonjour, quels sont les sites à Alger ?');
    expect(
      find.text(
          'Mocked assistant reply to: Bonjour, quels sont les sites à Alger ?'),
      findsOneWidget,
    );
  });

  testWidgets('ChatScreen surfaces a real API error in a banner (no bubble)',
      (tester) async {
    final fake = FakeChatApi(failReply: true);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ChatProvider(chatApi: fake)),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pumpAndSettle();

        await tester.enterText(
        find.byKey(const Key('chat_input')), 'Test erreur');
    await tester.pump(); // flush controller listener -> canSend=true
    await tester.tap(find.byKey(const Key('chat_send')));
    await tester.pumpAndSettle();

    expect(fake.calls, 1);
    expect(find.byKey(const Key('chat_error')), findsOneWidget);
    expect(find.textContaining('chat service unavailable'), findsOneWidget);
    // No assistant bubble carrying a hardcoded apology — only the banner.
    expect(find.text('Désolé, une erreur est survenue.'), findsNothing);
    // No suggestion chips either: the envelope never arrived, so the
    // provider exposes none (last turn is still the user's).
    expect(find.byKey(const Key('chat_suggestions')), findsNothing);
  });

  testWidgets(
      'assistant reply renders the API follow-up suggestions as chips '
      'and tapping one sends it as a new turn', (tester) async {
    final fake = FakeChatApi();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ChatProvider(chatApi: fake)),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('chat_input')), 'Sites ?');
    await tester.pump(); // flush controller listener -> canSend=true
    await tester.tap(find.byKey(const Key('chat_send')));
    await tester.pumpAndSettle();

    // Chips come verbatim from the API envelope (FakeChatApi defaults).
    expect(find.byKey(const Key('chat_suggestions')), findsOneWidget);
    expect(find.text('Suggestion 1'), findsOneWidget);
    expect(find.text('Suggestion 2'), findsOneWidget);

    // Tapping a chip sends its text as a new user turn — no typing needed.
    await tester.tap(find.byKey(const Key('chat_suggestion_0')));
    await tester.pumpAndSettle();
    expect(fake.calls, 2);
    expect(fake.lastMessage, 'Suggestion 1');
    expect(find.text('Suggestion 1'), findsNWidgets(2),
        reason: 'the user bubble text plus the refreshed chip');
    expect(find.text('Mocked assistant reply to: Suggestion 1'),
        findsOneWidget);
  });
}
