import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ChatMessage {
  final String role;
  final String content;
  ChatMessage({required this.role, required this.content});
}

class ChatProvider extends ChangeNotifier {
  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  List<String> _suggestions = [];

  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  List<String> get suggestions => _suggestions;

  Future<void> sendMessage(String text) async {
    _messages.add(ChatMessage(role: 'user', content: text));
    _isLoading = true;
    _suggestions = [];
    notifyListeners();

    try {
      final data = await ApiService().chat(text);
      _messages.add(ChatMessage(role: 'assistant', content: data['message']));
      _suggestions = List<String>.from(data['suggestions'] ?? []);
    } catch (e) {
      _messages.add(ChatMessage(role: 'assistant', content: 'Desole, une erreur est survenue.'));
    }
    _isLoading = false;
    notifyListeners();
  }

  void clear() {
    _messages = [];
    _suggestions = [];
    notifyListeners();
  }
}
