import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../services/api_service.dart';

/// In-memory conversation state for the mobile chat screen.
///
/// Same injectable-seam pattern as [POIProvider]/[TripProvider]: tests run
/// against a fake [ChatApi], never the network. The conversation history
/// lives only in memory — content comes exclusively from POST /chat/.
class ChatProvider extends ChangeNotifier {
  ChatProvider({ChatApi? chatApi}) : _api = chatApi ?? ApiService();

  final ChatApi _api;

  final List<ChatMessage> _messages = [];
  bool _isSending = false;
  String? _error;

  /// Most-recent-first is *not* used; the screen renders [messages] newest
  /// at the bottom via a reverse ListView, so this stays chronological.
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isSending => _isSending;
  String? get error => _error;
  bool get isEmpty => _messages.isEmpty;

  /// Follow-up suggestions of the latest assistant turn. Empty until an
  /// assistant reply arrives — and while a reply is pending, since the last
  /// turn is then the user's. The UI never invents suggestions: content
  /// comes exclusively from the backend envelope.
  List<String> get suggestions =>
      _messages.isNotEmpty && _messages.last.role == ChatRole.assistant
          ? _messages.last.suggestions
          : const [];

  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Appends the user turn immediately, then awaits POST /chat/ and appends
  /// the assistant turn built from the [ChatResponse] envelope
  /// (`{message, suggestions, context}`). Errors surface via [error], never
  /// as a hardcoded conversation bubble.
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isSending) return;

    _messages.add(ChatMessage(role: ChatRole.user, message: trimmed));
    _isSending = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _api.sendMessage(trimmed);
      _messages.add(ChatMessage.fromApiResponse(data));
    } catch (e) {
      _error = e.toString();
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }
}
