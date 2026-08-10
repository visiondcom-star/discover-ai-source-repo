import 'package:flutter_test/flutter_test.dart';
import 'package:discover_ai/providers/chat_provider.dart';

void main() {
  group('ChatProvider', () {
    test('initial state is empty', () {
      final cp = ChatProvider();
      expect(cp.messages.isEmpty, true);
      expect(cp.isLoading, false);
      expect(cp.suggestions.isEmpty, true);
    });

    test('clear resets messages', () {
      final cp = ChatProvider();
      cp.messages.add(ChatMessage(role: 'user', content: 'test'));
      cp.clear();
      expect(cp.messages.isEmpty, true);
    });
  });
}
