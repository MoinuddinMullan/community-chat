import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/chat_item.dart';

class MessageMetadata extends StatelessWidget {
  const MessageMetadata({super.key, required this.message, required this.isMe});

  final ChatMessage message;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final createdAt = message.createdAt;
    final time = createdAt == null
        ? ''
        : DateFormat.jm().format(createdAt.toLocal());
    final isPending = message.id.startsWith('local:') || message.isUploading;

    return Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            time,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
          if (isMe) ...[
            const SizedBox(width: 4),
            Icon(
              isPending ? Icons.access_time_rounded : Icons.done_all_rounded,
              size: 15,
              color: isPending
                  ? Colors.grey.shade600
                  : message.readAt != null
                  ? const Color(0xFF34B7F1)
                  : Colors.grey.shade700,
            ),
          ],
        ],
      ),
    );
  }
}
