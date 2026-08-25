import 'package:flutter/material.dart';

import '../models/chat_message.dart';

/// Chat bubble — mobile equivalent of the web `ChatBubble.tsx` component.
///
/// Visual mapping (frontend/src/components/ChatBubble.tsx):
///   - leading circular avatar: User icon (gray) for the user, Bot icon
///     (primary) for the assistant.
///   - user turn   → right-aligned, primary background, white text,
///                    rounded top-right cut (rounded-tr-sm).
///   - assistant turn → left-aligned, white background, border,
///                       rounded top-left cut (rounded-tl-sm).
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
  });

  final ChatMessage message;

  bool get _isUser => message.role == ChatRole.user;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isUser = _isUser;

    final bgColor = isUser
        ? colorScheme.primary
        : colorScheme.surface;
    final fgColor = isUser ? colorScheme.onPrimary : colorScheme.onSurface;
    final borderColor =
        isUser ? Colors.transparent : colorScheme.outlineVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: isUser
                ? colorScheme.surfaceContainerHighest
                : colorScheme.primary,
            foregroundColor: isUser
                ? colorScheme.onSurfaceVariant
                : colorScheme.onPrimary,
            child: Icon(
              isUser ? Icons.person : Icons.smart_toy_outlined,
              size: 18,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: isUser ? const Radius.circular(20) : Radius.zero,
                  bottomRight:
                      isUser ? Radius.zero : const Radius.circular(20),
                ),
                border: isUser
                    ? null
                    : Border.all(color: borderColor, width: 1),
              ),
              child: SelectableText(
                message.message,
                style: TextStyle(
                  color: fgColor,
                  fontSize: 15,
                  height: 1.4,
                ),
                textAlign: isUser ? TextAlign.right : TextAlign.left,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

