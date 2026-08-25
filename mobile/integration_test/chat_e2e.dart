/// Focused end-to-end test for the chat assistant against the live Docker
/// backend. Run on Chrome (web is not supported by `flutter test` for
/// integration tests, so `flutter drive` is required):
///
///   flutter drive --target=integration_test/chat_e2e.dart -d chrome \
///       --dart-define=API_BASE_URL=http://localhost:8000/api/v1 \
///       --dart-define=TENANT_SLUG=algeria
///
/// No mocks: the app boots its real [ApiService] (singleton), signs in with
/// the seeded demo account, opens the chat, and sends a real message to
/// POST /chat/. The rendered [ChatBubble] text is read straight off the
/// widget tree — it is built exclusively from the API envelope — and printed
/// to the test log so the exact backend content on screen is captured.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:discover_ai/app.dart';
import 'package:discover_ai/models/chat_message.dart';
import 'package:discover_ai/providers/auth_provider.dart';
import 'package:discover_ai/providers/chat_provider.dart';
import 'package:discover_ai/providers/poi_provider.dart';
import 'package:discover_ai/providers/trip_provider.dart';
import 'package:discover_ai/widgets/chat_bubble.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  const demoEmail = String.fromEnvironment(
    'E2E_EMAIL',
    defaultValue: 'demo@algeria.travel',
  );
  const demoPassword = String.fromEnvironment(
    'E2E_PASSWORD',
    defaultValue: 'demo1234',
  );

  // Real stack: real ApiService HTTP calls, real JWT, real POI data.
  Widget boot() => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => POIProvider()),
          ChangeNotifierProvider(create: (_) => TripProvider()),
          ChangeNotifierProvider(create: (_) => ChatProvider()),
        ],
        child: const DiscoverAIApp(),
      );

  /// Polls until [finder] matches, pumping real frames meanwhile.
  /// pumpAndSettle never settles while a spinner is painting.
  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 250));
      try {
        if (finder.evaluate().isNotEmpty) return;
      } catch (_) {
        // keep polling
      }
    }
    fail('Timed out after $timeout waiting for $finder');
  }

  Future<void> typeCredentials(
    WidgetTester tester,
    String password,
  ) async {
    await tester.enterText(find.byKey(const Key('login_email')), demoEmail);
    await tester.enterText(find.byKey(const Key('login_password')), password);
    await tester.tap(find.text('Sign in'));
  }

  testWidgets('V6 — chat assistant renders the real /chat/ reply on screen',
      (tester) async {
    await tester.pumpWidget(boot());
    await waitFor(tester, find.byKey(const Key('login_email')));

    // Sign in with the seeded demo account, then land on the POI list.
    await typeCredentials(tester, demoPassword);
    await waitFor(tester, find.byKey(const Key('open_chat_button')),
        timeout: const Duration(seconds: 20));

    // Open the chat assistant from the POI list AppBar.
    await tester.tap(find.byKey(const Key('open_chat_button')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(ChatBubble), findsNothing); // empty state first
    expect(find.byKey(const Key('chat_input')), findsOneWidget);

    // Send a real question to the real backend (POST /chat/, bearer JWT).
    await tester.enterText(
      find.byKey(const Key('chat_input')),
      'Bonjour, quels sont les meilleurs sites à Alger ?',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('chat_send')));

    // Poll the round-trip: two bubbles (user + assistant), or an error banner.
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.byKey(const Key('chat_error')).evaluate().isNotEmpty) break;
      if (find.byType(ChatBubble).evaluate().length >= 2) break;
    }

    // A backend/network failure must surface as the error banner, never as a
    // bubble carrying conversation text.
    expect(find.byKey(const Key('chat_error')), findsNothing,
        reason: 'POST /chat/ must not surface the on-screen error banner');

    final bubbles =
        tester.widgetList<ChatBubble>(find.byType(ChatBubble)).toList();
    expect(bubbles.length, greaterThanOrEqualTo(2),
        reason: 'both user and assistant turns must be rendered');

    final assistant =
        bubbles.lastWhere((b) => b.message.role == ChatRole.assistant);
    final reply = assistant.message.message;
    expect(reply, isNotEmpty,
        reason: 'assistant reply must come from the API envelope');

    // The reply must be a coherent answer, never a degraded error payload
    // (e.g. a surfaced OpenAI 429 / insufficient-quota message). Reject the
    // usual markers so a misconfigured provider cannot silently pass.
    final lower = reply.toLowerCase();
    for (final marker in const [
      'quota',
      'insufficient_quota',
      'credit_balance_exhausted',
      '429',
      'rate limit',
      'erreur de quota',
      'clé api invalide',
    ]) {
      expect(lower.contains(marker), isFalse,
          reason: 'assistant reply must not contain error marker "$marker": '
              'got "$reply"');
    }

    // Print the EXACT backend content rendered on screen. It is read straight
    // out of the ChatBubble (built from the /chat/ response envelope) and is
    // corroborated separately via curl.
    debugPrint('V6_PASS: real /chat/ reply rendered on screen');
    debugPrint('V6_ASSISTANT_REPLY="$reply"');

    // Visual proof: capture the chat screen with the assistant bubble visible.
    try {
      await binding.takeScreenshot('chat_reply');
      debugPrint('V6_SCREENSHOT: test_driver/chat_reply.png');
    } catch (e) {
      debugPrint('V6_SCREENSHOT_FAILED: $e');
    }
  });
}
