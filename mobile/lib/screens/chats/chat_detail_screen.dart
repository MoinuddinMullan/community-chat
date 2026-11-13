import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../models/chat_item.dart';
import '../../providers/auth_provider.dart';
import '../../providers/community_provider.dart';
import '../../services/crypto_service.dart';
import '../../services/image_processing_service.dart';
import 'message_bubble.dart';

class ChatDetailScreen extends StatefulWidget {
  const ChatDetailScreen({super.key, required this.chat});

  final ChatItem chat;

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _controller = TextEditingController();
  final _cryptoService = CryptoService();
  final _imageProcessingService = ImageProcessingService();
  final _imagePicker = ImagePicker();
  Future<List<ChatMessage>>? _messagesFuture;
  final List<ChatMessage> _additionalMessages = [];
  List<ChatMessage> _historyMessages = [];
  io.Socket? _messageSocket;
  Timer? _expiryTimer;
  int _historyRequestId = 0;
  List<int>? _chatKey;
  bool _isPickingImage = false;
  bool _isClearingChat = false;
  bool _isMarkingRead = false;
  bool _markReadQueued = false;
  int _pendingSends = 0;
  final Set<String> _selectedMessageIds = {};

  @override
  void initState() {
    super.initState();
    _reloadMessages();
    _messageSocket = context.read<CommunityProvider>().connectMessageSocket(
      _receiveSocketMessage,
      onMessageDeleted: _handleMessageDeleted,
      onChatCleared: _handleChatCleared,
      onMessagesRead: _handleMessagesRead,
    );
  }

  void _reloadMessages() {
    final requestId = ++_historyRequestId;
    _messagesFuture = context
        .read<CommunityProvider>()
        .fetchMessages(widget.chat.id)
        .then((messages) async {
          final decodedMessages = <ChatMessage>[];
          for (final message in messages) {
            if (!mounted || requestId != _historyRequestId) return messages;
            decodedMessages.add(await _decodeMessage(message));
          }
          if (mounted && requestId == _historyRequestId) {
            _historyMessages = decodedMessages;
            _scheduleExpiry();
            unawaited(_markChatRead());
          }
          return decodedMessages;
        });
    if (mounted) setState(() {});
  }

  Future<List<int>> _getChatKey() async {
    final cached = _chatKey;
    if (cached != null) return cached;

    final auth = context.read<AuthProvider>();
    await auth.ensureEncryptionIdentity();
    final privateKey = auth.privateKey;
    final peerPublicKey = widget.chat.peerPublicKey;
    if (privateKey == null || peerPublicKey == null || peerPublicKey.isEmpty) {
      throw StateError('Secure chat keys are unavailable. Sign in again.');
    }

    final pair = await _cryptoService.keyPairFromPrivateKey(privateKey);
    final key = await _cryptoService.deriveChatKey(
      widget.chat.id,
      peerPublicKey,
      pair,
    );
    _chatKey = key;
    return key;
  }

  Future<ChatMessage> _decodeMessage(ChatMessage message) async {
    final provider = context.read<CommunityProvider>();
    if (message.type == 'text' && message.text.startsWith('enc1:')) {
      try {
        final key = await _getChatKey();
        final result = await _cryptoService.decryptText(
          message.text,
          widget.chat.id,
          message.senderId,
          key,
        );
        return message.copyWith(text: result['text'] as String);
      } catch (_) {
        return message.copyWith(text: '🔒 This message can\'t be opened');
      }
    }
    if (message.type != 'image') return message;

    var caption = message.caption;
    if (message.encryptedCaption != null) {
      try {
        final key = await _getChatKey();
        final result = await _cryptoService.decryptText(
          message.encryptedCaption!,
          widget.chat.id,
          message.senderId,
          key,
          type: 'image',
        );
        caption = result['text'] as String;
      } catch (_) {
        caption = '🔒 This caption can\'t be opened';
      }
    }
    if (message.imageUrl == null || message.localImageBytes != null) {
      return message.copyWith(caption: caption);
    }

    try {
      final encryptedBytes = await provider.downloadImage(message.imageUrl!);
      final key = await _getChatKey();
      final imageBytes = await _cryptoService.decryptBytes(
        encryptedBytes,
        widget.chat.id,
        message.senderId,
        key,
        type: 'image',
      );
      return message.copyWith(
        localImageBytes: imageBytes,
        caption: caption,
        isLoadingImage: false,
        imageLoadFailed: false,
      );
    } catch (_) {
      return message.copyWith(
        caption: caption ?? '🔒 This photo can\'t be opened',
        isLoadingImage: false,
        imageLoadFailed: true,
      );
    }
  }

  void _receiveSocketMessage(String chatId, ChatMessage message) {
    if (!mounted ||
        chatId != widget.chat.id ||
        (message.expiresAt != null &&
            !message.expiresAt!.isAfter(DateTime.now()))) {
      return;
    }
    if (!_isCurrentUserMessage(message)) {
      unawaited(_markChatRead());
    }
    final pending = message.type == 'image' && message.imageUrl != null
        ? message.copyWith(isLoadingImage: true)
        : message;
    setState(() => _upsertAdditionalMessage(pending));
    unawaited(
      _decodeMessage(message).then((decoded) {
        if (mounted && chatId == widget.chat.id) {
          setState(() => _upsertAdditionalMessage(decoded));
        }
      }),
    );
  }

  List<ChatMessage> _mergeMessages(List<ChatMessage> history) {
    final now = DateTime.now();
    final messages = history
        .where(
          (message) =>
              message.expiresAt == null || message.expiresAt!.isAfter(now),
        )
        .toList();
    for (final additional in _additionalMessages) {
      if (additional.expiresAt != null && !additional.expiresAt!.isAfter(now)) {
        continue;
      }
      final alreadyLoaded = messages.any(
        (message) =>
            message.id == additional.id ||
            (additional.clientId != null &&
                message.clientId == additional.clientId),
      );
      if (!alreadyLoaded) messages.add(additional);
    }
    messages.sort(
      (left, right) =>
          (left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
            right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          ),
    );
    return messages;
  }

  void _upsertAdditionalMessage(ChatMessage message) {
    final previous = _additionalMessages.where(
      (existing) =>
          existing.id == message.id ||
          (message.clientId != null && existing.clientId == message.clientId),
    );
    if (message.readAt == null && previous.isNotEmpty) {
      final previousReadAt = previous.first.readAt;
      if (previousReadAt != null) {
        message = message.copyWith(readAt: previousReadAt);
      }
    }
    _additionalMessages.removeWhere(
      (existing) =>
          existing.id == message.id ||
          (message.clientId != null && existing.clientId == message.clientId),
    );
    _additionalMessages.add(message);
    _scheduleExpiry();
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final now = DateTime.now();
    final expiries =
        [
            ..._historyMessages,
            ..._additionalMessages,
          ].map((message) => message.expiresAt).whereType<DateTime>().toList()
          ..removeWhere((expiry) => !expiry.isAfter(now))
          ..sort();
    if (expiries.isEmpty) return;

    _expiryTimer = Timer(expiries.first.difference(now), () {
      if (!mounted) return;
      final currentTime = DateTime.now();
      setState(() {
        _historyRequestId++;
        _historyMessages.removeWhere(
          (message) =>
              message.expiresAt != null &&
              !message.expiresAt!.isAfter(currentTime),
        );
        _additionalMessages.removeWhere(
          (message) =>
              message.expiresAt != null &&
              !message.expiresAt!.isAfter(currentTime),
        );
        _messagesFuture = Future.value(List.of(_historyMessages));
        _scheduleExpiry();
      });
    });
  }

  void _handleMessageDeleted(String chatId, String messageId) {
    if (!mounted || chatId != widget.chat.id) return;
    setState(() {
      _historyRequestId++;
      _historyMessages.removeWhere((message) => message.id == messageId);
      _additionalMessages.removeWhere((message) => message.id == messageId);
      _selectedMessageIds.remove(messageId);
      _messagesFuture = Future.value(List.of(_historyMessages));
      _scheduleExpiry();
    });
  }

  void _handleMessagesRead(
    String chatId,
    List<String> messageIds,
    DateTime readAt,
  ) {
    if (!mounted || chatId != widget.chat.id) return;
    final ids = messageIds.toSet();
    setState(() {
      for (var index = 0; index < _historyMessages.length; index++) {
        final message = _historyMessages[index];
        if (ids.contains(message.id)) {
          _historyMessages[index] = message.copyWith(readAt: readAt);
        }
      }
      for (var index = 0; index < _additionalMessages.length; index++) {
        final message = _additionalMessages[index];
        if (ids.contains(message.id)) {
          _additionalMessages[index] = message.copyWith(readAt: readAt);
        }
      }
      _messagesFuture = Future.value(List.of(_historyMessages));
    });
  }

  Future<void> _markChatRead() async {
    if (_isMarkingRead) {
      _markReadQueued = true;
      return;
    }
    _isMarkingRead = true;
    try {
      do {
        _markReadQueued = false;
        await context.read<CommunityProvider>().markChatRead(widget.chat.id);
      } while (mounted && _markReadQueued);
    } catch (error) {
      if (mounted) {
        _showMessageError('Read status could not be updated: $error');
      }
    } finally {
      _isMarkingRead = false;
    }
  }

  void _clearVisibleMessages() {
    _historyRequestId++;
    _expiryTimer?.cancel();
    _selectedMessageIds.clear();
    _historyMessages = [];
    _additionalMessages.clear();
    _messagesFuture = Future.value(const <ChatMessage>[]);
  }

  void _handleChatCleared(String chatId) {
    if (!mounted || chatId != widget.chat.id) return;
    setState(_clearVisibleMessages);
  }

  bool _isCurrentUserMessage(ChatMessage message) {
    final currentUserId = context.read<AuthProvider>().userSubjectId;
    return currentUserId != null &&
        currentUserId.trim().isNotEmpty &&
        message.senderId.trim().toLowerCase() ==
            currentUserId.trim().toLowerCase();
  }

  void _toggleMessageSelection(ChatMessage message) {
    if (!_isCurrentUserMessage(message) || message.id.startsWith('local:')) {
      _showMessageError('You can select and delete messages you sent.');
      return;
    }
    setState(() {
      if (!_selectedMessageIds.add(message.id)) {
        _selectedMessageIds.remove(message.id);
      }
    });
  }

  Future<void> _deleteSelectedMessages() async {
    if (_selectedMessageIds.isEmpty) return;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Delete ${_selectedMessageIds.length == 1 ? 'message' : 'messages'}?',
        ),
        content: Text(
          'This removes ${_selectedMessageIds.length == 1 ? 'this message' : 'these messages'} and any attached photos from both sides of this chat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete != true || !mounted) return;

    try {
      final messageIds = List<String>.of(_selectedMessageIds);
      await context.read<CommunityProvider>().deleteMessages(
        widget.chat.id,
        messageIds,
      );
      if (!mounted) return;
      setState(() {
        _selectedMessageIds.clear();
        _historyRequestId++;
        _historyMessages.removeWhere(
          (message) => messageIds.contains(message.id),
        );
        _additionalMessages.removeWhere(
          (message) => messageIds.contains(message.id),
        );
        _messagesFuture = Future.value(List.of(_historyMessages));
        _scheduleExpiry();
      });
    } catch (error) {
      if (mounted) {
        _showMessageError('Selected messages could not be deleted: $error');
      }
    }
  }

  Widget _dateSeparator(DateTime? timestamp) {
    if (timestamp == null) return const SizedBox.shrink();
    final date = timestamp.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(date.year, date.month, date.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final label = messageDay == today
        ? 'Today'
        : messageDay == yesterday
        ? 'Yesterday'
        : DateFormat('EEEE, d MMMM yyyy').format(date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(220),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmClearChat() async {
    if (_pendingSends > 0 ||
        _additionalMessages.any((message) => message.isUploading)) {
      _showMessageError(
        'Wait for sending or photo uploads to finish before clearing chat.',
      );
      return;
    }

    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear this chat?'),
        content: const Text(
          'All messages and photos will be permanently removed for both people.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear chat'),
          ),
        ],
      ),
    );
    if (shouldClear != true || !mounted) return;

    setState(() => _isClearingChat = true);
    try {
      await context.read<CommunityProvider>().clearChat(widget.chat.id);
      if (!mounted) return;
      setState(_clearVisibleMessages);
      try {
        await context.read<CommunityProvider>().refresh();
      } catch (error) {
        if (mounted) {
          _showMessageError(
            'Chat cleared, but the chat list could not refresh: $error',
          );
        }
      }
    } catch (error) {
      if (mounted) _showMessageError('Chat could not be cleared: $error');
    } finally {
      if (mounted) setState(() => _isClearingChat = false);
    }
  }

  Future<void> _sendMessage() async {
    if (_isClearingChat) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final senderId = context.read<AuthProvider>().userSubjectId;
    if (senderId == null || senderId.isEmpty) {
      _showMessageError(
        'Your session identity is unavailable. Please sign in again.',
      );
      return;
    }

    final clientId =
        'mobile-$senderId-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = ChatMessage(
      id: 'local:$clientId',
      senderId: senderId,
      text: text,
      clientId: clientId,
      createdAt: DateTime.now(),
    );
    setState(() {
      _pendingSends++;
      _upsertAdditionalMessage(optimistic);
      _controller.clear();
    });

    final provider = context.read<CommunityProvider>();
    try {
      final key = await _getChatKey();
      final encryptedText = await _cryptoService.encryptText(
        text,
        widget.chat.id,
        senderId,
        key,
      );
      final sent = await provider.sendMessage(
        widget.chat.id,
        encryptedText,
        clientId: clientId,
      );
      if (!mounted) return;
      setState(() => _upsertAdditionalMessage(sent.copyWith(text: text)));
      _reloadMessages();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _additionalMessages.removeWhere(
          (message) => message.clientId == clientId,
        );
      });
      _showMessageError('Message could not be sent: $error');
    } finally {
      if (mounted) setState(() => _pendingSends--);
    }
  }

  Future<void> _showAttachmentOptions() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(kIsWeb ? 'Choose image' : 'Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
          ],
        ),
      ),
    );
    if (source != null) await _pickImage(source);
  }

  Future<void> _pickImage(ImageSource requestedSource) async {
    if (_isPickingImage) return;
    setState(() => _isPickingImage = true);
    try {
      final file = await _imagePicker.pickImage(
        source: kIsWeb ? ImageSource.gallery : requestedSource,
        maxWidth: ImageProcessingService.maxWidth.toDouble(),
        imageQuality: 80,
      );
      if (file == null) return;

      final processed = _imageProcessingService.process(
        await file.readAsBytes(),
      );
      await _previewImage(processed.bytes);
    } catch (error) {
      if (mounted) {
        _showMessageError(
          error is ImagePreparationException
              ? error.message
              : 'Could not open that image. Please try another photo.',
        );
      }
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  Future<void> _previewImage(Uint8List bytes) async {
    final captionController = TextEditingController();
    final shouldSend = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Send photo'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: captionController,
                maxLength: 2000,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Caption (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    final caption = captionController.text.trim();
    captionController.dispose();
    if (shouldSend == true && mounted) {
      await _sendImage(bytes, caption);
    }
  }

  Future<void> _sendImage(Uint8List bytes, String caption) async {
    if (_isClearingChat) return;
    final senderId = context.read<AuthProvider>().userSubjectId;
    if (senderId == null || senderId.isEmpty) {
      _showMessageError(
        'Your session identity is unavailable. Please sign in again.',
      );
      return;
    }

    late final Uint8List encryptedImage;
    late final String? encryptedCaption;
    try {
      final key = await _getChatKey();
      encryptedImage = await _cryptoService.encryptBytes(
        bytes,
        widget.chat.id,
        senderId,
        key,
        type: 'image',
      );
      encryptedCaption = caption.isEmpty
          ? null
          : await _cryptoService.encryptText(
              caption,
              widget.chat.id,
              senderId,
              key,
              type: 'image',
            );
    } catch (error) {
      if (mounted) _showMessageError('Photo could not be encrypted: $error');
      return;
    }
    if (!mounted) return;

    final clientId = 'image-$senderId-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = ChatMessage(
      id: 'local:$clientId',
      senderId: senderId,
      text: '',
      type: 'image',
      caption: caption.isEmpty ? null : caption,
      clientId: clientId,
      createdAt: DateTime.now(),
      localImageBytes: bytes,
      encryptedImageBytes: encryptedImage,
      encryptedCaption: encryptedCaption,
      isUploading: true,
    );
    setState(() => _upsertAdditionalMessage(optimistic));
    await _uploadAndSendImage(optimistic);
  }

  Future<void> _retryImage(ChatMessage message) async {
    if (_isClearingChat) return;
    final retrying = message.copyWith(
      isUploading: true,
      uploadFailed: false,
      uploadProgress: 0,
    );
    setState(() => _upsertAdditionalMessage(retrying));
    await _uploadAndSendImage(retrying);
  }

  Future<void> _uploadAndSendImage(ChatMessage pending) async {
    var imageUrl = pending.imageUrl;
    if (mounted) setState(() => _pendingSends++);
    try {
      final provider = context.read<CommunityProvider>();
      if (imageUrl == null) {
        final bytes = pending.encryptedImageBytes;
        if (bytes == null) {
          throw StateError(
            'The selected photo is no longer available. Please choose it again.',
          );
        }
        imageUrl = await provider.uploadImage(
          widget.chat.id,
          bytes,
          onProgress: (sent, total) {
            if (!mounted || total <= 0) return;
            final progress = (sent / total).clamp(0.0, 1.0);
            setState(() {
              _upsertAdditionalMessage(
                pending.copyWith(
                  imageUrl: imageUrl,
                  isUploading: true,
                  uploadProgress: progress,
                ),
              );
            });
          },
        );
        if (!mounted) return;
        setState(() {
          _upsertAdditionalMessage(
            pending.copyWith(
              imageUrl: imageUrl,
              isUploading: true,
              uploadProgress: 1,
            ),
          );
        });
      }

      final sent = await provider.sendImageMessage(
        widget.chat.id,
        imageUrl: imageUrl,
        clientId: pending.clientId!,
        caption: pending.encryptedCaption,
      );
      if (!mounted) return;
      final decoded = await _decodeMessage(sent);
      if (!mounted) return;
      setState(
        () => _upsertAdditionalMessage(
          decoded.copyWith(
            localImageBytes: decoded.localImageBytes ?? pending.localImageBytes,
            caption: pending.caption,
            clearEncryptedImageBytes: true,
            isUploading: false,
            uploadProgress: 0,
          ),
        ),
      );
      _reloadMessages();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _upsertAdditionalMessage(
          pending.copyWith(
            imageUrl: imageUrl,
            isUploading: false,
            uploadFailed: true,
          ),
        );
      });
      _showMessageError('Photo could not be sent: $error');
    } finally {
      if (mounted) setState(() => _pendingSends--);
    }
  }

  void _showMessageError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _messageSocket?.disconnect();
    _messageSocket?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUserId = authProvider.userSubjectId;
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (_selectedMessageIds.isNotEmpty) ...[
            IconButton(
              tooltip: 'Cancel selection',
              onPressed: () => setState(_selectedMessageIds.clear),
              icon: const Icon(Icons.close),
            ),
            IconButton(
              tooltip: 'Delete selected messages',
              onPressed: _deleteSelectedMessages,
              icon: const Icon(Icons.delete_outline),
            ),
          ] else
            IconButton(
              tooltip: 'Clear chat',
              onPressed: _isClearingChat ? null : _confirmClearChat,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
        title: _selectedMessageIds.isNotEmpty
            ? Text('${_selectedMessageIds.length} selected')
            : Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: widget.chat.avatarColor,
                    child: Text(
                      widget.chat.name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.chat.name,
                          style: const TextStyle(fontSize: 16),
                        ),
                        Text(
                          widget.chat.online ? 'online' : 'offline',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      body: Container(
        color: const Color(0xFFEDE7E3),
        child: Column(
          children: [
            Expanded(
              child: FutureBuilder<List<ChatMessage>>(
                future: _messagesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      _additionalMessages.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError && _additionalMessages.isEmpty) {
                    return const Center(
                      child: Text(
                        'Could not load messages. Please go back and try again.',
                      ),
                    );
                  }

                  final messages = _mergeMessages(
                    snapshot.data ?? const <ChatMessage>[],
                  );
                  if (messages.isEmpty) {
                    return const Center(
                      child: Text(
                        'No messages yet. Start the encrypted conversation.',
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(14),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isOwnSavedMessage =
                          _isCurrentUserMessage(message) &&
                          !message.id.startsWith('local:');
                      final isSelected = _selectedMessageIds.contains(
                        message.id,
                      );
                      final previousCreatedAt = index > 0
                          ? messages[index - 1].createdAt
                          : null;
                      final currentCreatedAt = message.createdAt;
                      final showDateSeparator =
                          currentCreatedAt != null &&
                          (previousCreatedAt == null ||
                              currentCreatedAt.toLocal().year !=
                                  previousCreatedAt.toLocal().year ||
                              currentCreatedAt.toLocal().month !=
                                  previousCreatedAt.toLocal().month ||
                              currentCreatedAt.toLocal().day !=
                                  previousCreatedAt.toLocal().day);
                      final bubble = ChatMessageBubble(
                        message: message,
                        currentUserId: currentUserId,
                        maxWidth:
                            MediaQuery.sizeOf(context).width *
                            (message.type == 'image' ? 0.65 : 0.75),
                        onRetry: message.uploadFailed
                            ? () => _retryImage(message)
                            : null,
                      );
                      return Column(
                        children: [
                          if (showDateSeparator)
                            _dateSeparator(currentCreatedAt),
                          GestureDetector(
                            onLongPress: () {
                              if (isOwnSavedMessage) {
                                _toggleMessageSelection(message);
                              } else {
                                _showMessageError(
                                  'You can select and delete messages you sent.',
                                );
                              }
                            },
                            onSecondaryTap: isOwnSavedMessage
                                ? () => _toggleMessageSelection(message)
                                : null,
                            onTap: _selectedMessageIds.isNotEmpty
                                ? () => _toggleMessageSelection(message)
                                : null,
                            child: Container(
                              color: isSelected
                                  ? Colors.black.withAlpha(20)
                                  : null,
                              child: IgnorePointer(
                                ignoring: _selectedMessageIds.isNotEmpty,
                                child: bubble,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Attach photo',
                      onPressed: _isPickingImage
                          ? null
                          : _showAttachmentOptions,
                      icon: const Icon(Icons.attach_file),
                    ),
                    IconButton(
                      tooltip: 'Take photo',
                      onPressed: _isPickingImage
                          ? null
                          : () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        maxLength: 2000,
                        decoration: InputDecoration(
                          hintText: 'Type a private message',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FloatingActionButton.small(
                      onPressed: _sendMessage,
                      child: const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
