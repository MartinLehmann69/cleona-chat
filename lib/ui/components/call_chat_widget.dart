import 'package:flutter/material.dart';
import 'package:cleona/core/i18n/app_locale.dart';

/// A single chat message entry for display.
class ChatDisplayEntry {
  final String messageId;
  final String senderName;
  final String text;
  final DateTime timestamp;
  final bool isOwn;
  final String? replyToText;

  const ChatDisplayEntry({
    required this.messageId,
    required this.senderName,
    required this.text,
    required this.timestamp,
    this.isOwn = false,
    this.replyToText,
  });
}

/// Ephemeral in-call chat widget (Architecture S10.5.3.2).
///
/// Shows as a side panel or overlay during calls.
/// Messages are NOT persisted after call ends.
class CallChatWidget extends StatefulWidget {
  final List<ChatDisplayEntry> messages;
  final void Function(String text, {String? replyToId})? onSendMessage;
  final VoidCallback? onClose;

  const CallChatWidget({
    super.key,
    required this.messages,
    this.onSendMessage,
    this.onClose,
  });

  @override
  State<CallChatWidget> createState() => _CallChatWidgetState();
}

class _CallChatWidgetState extends State<CallChatWidget> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  String? _replyToId;
  String? _replyToText;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CallChatWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length > oldWidget.messages.length) {
      // Scroll to bottom on new message
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = AppLocale.read(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(left: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                Icon(Icons.chat_bubble_outline,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(locale.tr('collab_chat'), style: theme.textTheme.titleSmall),
                const Spacer(),
                if (widget.onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: widget.onClose,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),

          // Messages
          Expanded(
            child: widget.messages.isEmpty
                ? Center(
                    child: Text(
                      locale.tr('collab_no_messages'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: widget.messages.length,
                    itemBuilder: (_, i) =>
                        _buildMessage(context, widget.messages[i]),
                  ),
          ),

          // Reply preview
          if (_replyToText != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
              ),
              child: Row(
                children: [
                  Icon(Icons.reply,
                      size: 14, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _replyToText!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 14),
                    onPressed: () => setState(() {
                      _replyToId = null;
                      _replyToText = null;
                    }),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

          // Input field
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              border: Border(top: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Message...',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onSubmitted: _sendMessage,
                    textInputAction: TextInputAction.send,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.send,
                      size: 20, color: theme.colorScheme.primary),
                  onPressed: () => _sendMessage(_controller.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(BuildContext context, ChatDisplayEntry msg) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: GestureDetector(
        onLongPress: () {
          setState(() {
            _replyToId = msg.messageId;
            _replyToText = '${msg.senderName}: ${msg.text}';
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: msg.isOwn
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (msg.replyToText != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 2),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                          color: theme.colorScheme.primary, width: 2),
                    ),
                  ),
                  child: Text(
                    msg.replyToText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${msg.senderName}: ',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: msg.isOwn
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      msg.text,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    '${msg.timestamp.hour.toString().padLeft(2, '0')}:'
                    '${msg.timestamp.minute.toString().padLeft(2, '0')}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;
    // replyToId needs to be bytes for the manager. We pass as String here,
    // the integration layer converts.
    widget.onSendMessage?.call(text.trim(), replyToId: _replyToId);
    _controller.clear();
    setState(() {
      _replyToId = null;
      _replyToText = null;
    });
  }
}
