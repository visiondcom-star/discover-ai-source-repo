import 'package:flutter/material.dart';

import '../models/chat_message.dart';

/// Chat bubble — mobile equivalent of the web `ChatBubble.tsx` component,
/// restyled on the P0 design system (Material 3 + Poppins via the app theme).
///
/// Visual mapping (frontend/src/components/ChatBubble.tsx):
///   - circular avatar beside the tail: person (neutral) on the user side,
///     guide bot (brand) on the assistant side.
///   - user turn      → right-aligned, primary (brand) background, white text,
///                      top-right corner cut (rounded-tr-sm on web).
///   - assistant turn → left-aligned, surface background, hairline border,
///                      top-left corner cut (rounded-tl-sm on web).
///
/// Content contract unchanged: [message] is rendered verbatim from the API
/// envelope — nothing is hardcoded or appended here.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
  });

  final ChatMessage message;

  bool get _isUser => message.role == ChatRole.user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isUser = _isUser;

    final bgColor = isUser ? colorScheme.primary : colorScheme.surface;
    final fgColor = isUser ? colorScheme.onPrimary : colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              child: const Icon(Icons.smart_toy_outlined, size: 18),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(isUser ? 20 : 6),
                  topRight: Radius.circular(isUser ? 6 : 20),
                  bottomLeft: const Radius.circular(20),
                  bottomRight: const Radius.circular(20),
                ),
                border: isUser
                    ? null
                    : Border.all(color: colorScheme.outlineVariant, width: 1),
              ),
              child: SelectableText(
                message.message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: fgColor,
                  height: 1.4,
                  fontWeight: isUser ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: colorScheme.surfaceContainerHighest,
              foregroundColor: colorScheme.onSurfaceVariant,
              child: const Icon(Icons.person, size: 18),
            ),
          ],
        ],
      ),
    );
  }
}

