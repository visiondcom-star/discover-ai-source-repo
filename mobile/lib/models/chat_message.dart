/// Mirrors the backend `ChatResponse` schema (backend/app/schemas.py),
/// extended with a [ChatRole] so the same model renders a full
/// user/assistant conversation in the in-memory list.
///
/// Backend contract (`backend/app/api/v1/endpoints/chat.py` → POST /chat/):
///   request  → ChatRequest{ message: str, context?: Dict }
///   response → ChatResponse{ message: str, suggestions: List[str], context: Dict }
///
/// No conversation text is ever hardcoded here — content comes exclusively
/// from the API response envelope.
enum ChatRole { user, assistant }

class ChatMessage {
  ChatMessage({
    required this.role,
    required this.message,
    this.suggestions = const [],
  });

  final ChatRole role;

  /// Text content of the turn. This is the `message` field of the
  /// backend [ChatResponse] for assistant turns, and the user's typed
  /// input for user turns.
  final String message;

  /// Follow-up suggestions returned by the backend with assistant turns.
  /// Always empty for user turns (unused by the UI on the user side).
  final List<String> suggestions;

  /// Builds an assistant turn from the raw `POST /chat/` response envelope.
  /// Reads `message` and `suggestions` directly — nothing else assumed.
  factory ChatMessage.fromApiResponse(Map<String, dynamic> json) =>
      ChatMessage(
        role: ChatRole.assistant,
        message: json['message'] as String? ?? '',
        suggestions:
            List<String>.from(json['suggestions'] as List? ?? []),
      );

  Map<String, dynamic> toJson() => {
        'role': role == ChatRole.user ? 'user' : 'assistant',
        'message': message,
        'suggestions': suggestions,
      };
}
