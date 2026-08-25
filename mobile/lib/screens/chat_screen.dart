import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/chat_provider.dart';
import '../widgets/chat_bubble.dart';

/// Mobile equivalent of the web `AssistantTab`
/// (frontend/src/components/AppShell.tsx).
///
/// Header: "Assistant" + "Bienvenue ! Je suis votre guide."
/// Empty state mirrors the web: "Posez-moi une question sur votre destination."
/// No conversation text is hardcoded — assistant replies come exclusively
/// from the API envelope, rendered by ChatBubble.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    setState(() {});
    context.read<ChatProvider>().sendMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final hasMessages = chat.messages.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Assistant'),
            Text('Bienvenue ! Je suis votre guide.',
                style: TextStyle(fontSize: 12)),
          ],
        ),
        titleSpacing: 0,
        actions: [
          if (chat.error != null)
            IconButton(
              key: const Key('chat_clear_error'),
              tooltip: 'Clear error',
              icon: const Icon(Icons.close),
              onPressed: () => chat.clearError(),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: !hasMessages && chat.error == null
                ? const _EmptyState()
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 8),
                    itemCount: chat.messages.length,
                    itemBuilder: (context, index) {
                      final msg =
                          chat.messages[chat.messages.length - 1 - index];
                      return ChatBubble(message: msg);
                    },
                  ),
          ),
                    if (chat.isSending && hasMessages)
            Container(
              alignment: Alignment.centerLeft,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: Colors.grey)),
                  const SizedBox(width: 6),
                  Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: Colors.grey)),
                  const SizedBox(width: 6),
                  Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: Colors.grey)),
                  const SizedBox(width: 8),
                  const Text('En train de réfléchir…',
                      style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          if (chat.error != null)
            Container(
              key: const Key('chat_error'),
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                chat.error!,
                style: TextStyle(
                    color:
                        Theme.of(context).colorScheme.onErrorContainer),
              ),
            ),
          _InputBar(
            controller: _controller,
            sending: chat.isSending,
            onSend: _send,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Posez-moi une question sur votre destination.',
            key: Key('chat_empty'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
}

class _InputBar extends StatefulWidget {
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final canSend =
        !widget.sending && widget.controller.text.trim().isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('chat_input'),
                controller: widget.controller,
                decoration: const InputDecoration(
                  hintText: 'Poser une question…',
                  border: OutlineInputBorder(),
                ),
                maxLines: 4,
                minLines: 1,
                enabled: !widget.sending,
                onSubmitted: (_) => canSend ? widget.onSend() : null,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const Key('chat_send'),
              icon: widget.sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              onPressed: canSend ? widget.onSend : null,
            ),
          ],
        ),
      ),
    );
  }
}

