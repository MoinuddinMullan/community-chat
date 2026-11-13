import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/chat_item.dart';
import 'image_message_bubble.dart';

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.currentUserId,
    required this.maxWidth,
    this.onRetry,
  });

  final ChatMessage message;
  final String? currentUserId;
  final double maxWidth;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (message.type == 'image') {
      return ImageMessageBubble(
        message: message,
        currentUserId: currentUserId,
        maxWidth: maxWidth,
        onRetry: onRetry,
      );
    }

    final isMe =
        currentUserId != null &&
        currentUserId!.trim().isNotEmpty &&
        message.senderId.trim().toLowerCase() ==
            currentUserId!.trim().toLowerCase();

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          bottom: 10,
          left: isMe ? 48 : 0,
          right: isMe ? 0 : 48,
        ),
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? CommunityTheme.bubbleOut : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Text(message.text),
      ),
    );
  }
}
