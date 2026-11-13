import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/chat_item.dart';
import 'full_screen_image_viewer.dart';

class ImageMessageBubble extends StatelessWidget {
  const ImageMessageBubble({
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

  bool get _isMe =>
      currentUserId != null &&
      currentUserId!.trim().isNotEmpty &&
      message.senderId.trim().toLowerCase() ==
          currentUserId!.trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    final isMe = _isMe;
    final imageBytes = message.localImageBytes;
    final contentWidth = (maxWidth - 16).clamp(0.0, maxWidth).toDouble();

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          bottom: 10,
          left: isMe ? 48 : 0,
          right: isMe ? 0 : 48,
        ),
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isMe ? CommunityTheme.bubbleOut : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imageBytes != null ||
                message.isLoadingImage ||
                message.imageUrl != null)
              GestureDetector(
                onTap: imageBytes == null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              FullScreenImageViewer(imageBytes: imageBytes),
                        ),
                      ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (imageBytes != null)
                        Image.memory(
                          imageBytes,
                          width: contentWidth,
                          fit: BoxFit.contain,
                          frameBuilder:
                              (context, child, frame, wasSynchronouslyLoaded) {
                                if (wasSynchronouslyLoaded || frame != null) {
                                  return child;
                                }
                                return _loadingPlaceholder(contentWidth, null);
                              },
                          errorBuilder: _brokenImage,
                        )
                      else
                        message.isLoadingImage
                            ? _loadingPlaceholder(contentWidth, null)
                            : _brokenImage(
                                context,
                                StateError('Image could not be decrypted.'),
                                null,
                              ),
                      if (message.isUploading)
                        Positioned.fill(
                          child: ColoredBox(
                            color: Colors.black.withAlpha(70),
                            child: Center(
                              child: SizedBox(
                                width: contentWidth * 0.7,
                                child: LinearProgressIndicator(
                                  value: message.uploadProgress > 0
                                      ? message.uploadProgress
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (message.uploadFailed)
                        Positioned.fill(
                          child: ColoredBox(
                            color: Colors.black.withAlpha(90),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  color: Colors.white,
                                ),
                                TextButton.icon(
                                  onPressed: onRetry,
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              )
            else
              SizedBox(
                width: contentWidth,
                height: 180,
                child: _brokenImage(
                  context,
                  StateError('Missing image data'),
                  null,
                ),
              ),
            if (message.caption != null && message.caption!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: Text(message.caption!),
              ),
          ],
        ),
      ),
    );
  }

  Widget _loadingPlaceholder(double width, ImageChunkEvent? progress) {
    final total = progress?.expectedTotalBytes;
    return SizedBox(
      width: width,
      height: 180,
      child: Center(
        child: CircularProgressIndicator(
          value: progress == null || total == null || total == 0
              ? null
              : progress.cumulativeBytesLoaded / total,
        ),
      ),
    );
  }

  Widget _brokenImage(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) {
    return SizedBox(
      width: contentWidthForError,
      height: 180,
      child: const Center(child: Icon(Icons.broken_image_outlined, size: 42)),
    );
  }

  double get contentWidthForError =>
      (maxWidth - 16).clamp(0.0, maxWidth).toDouble();
}
