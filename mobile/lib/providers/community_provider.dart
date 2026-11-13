import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../models/chat_item.dart';
import '../services/community_service.dart';

class CommunityProvider extends ChangeNotifier {
  CommunityProvider({this._accessToken = ''});

  String _accessToken;

  CommunityApiService get _service =>
      CommunityApiService(accessToken: _accessToken);

  bool isLoading = false;
  List<ChatItem> chats = const [];
  List<ContactRequestItem> requests = const [];
  List<ContactEntry> contacts = const [];

  void updateToken(String? accessToken) {
    _accessToken = accessToken ?? '';
    if (_accessToken.isEmpty) {
      chats = const [];
      requests = const [];
      contacts = const [];
    }
    notifyListeners();
  }

  Future<void> loadAll() async {
    if (_accessToken.isEmpty) {
      chats = const [];
      requests = const [];
      contacts = const [];
      notifyListeners();
      return;
    }

    isLoading = true;
    notifyListeners();

    try {
      final results = await Future.wait([
        _service.fetchChats(),
        _service.fetchRequests(),
        _service.fetchContacts(),
      ]);

      chats = results[0] as List<ChatItem>;
      requests = results[1] as List<ContactRequestItem>;
      contacts = results[2] as List<ContactEntry>;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<List<ChatMessage>> fetchMessages(String chatId) async {
    if (_accessToken.isEmpty) {
      return const <ChatMessage>[];
    }
    return _service.fetchMessages(chatId);
  }

  io.Socket connectMessageSocket(
    void Function(String chatId, ChatMessage message) onMessage, {
    void Function(String chatId, String messageId)? onMessageDeleted,
    void Function(String chatId)? onChatCleared,
    void Function(String chatId, List<String> messageIds, DateTime readAt)?
    onMessagesRead,
  }) {
    if (_accessToken.isEmpty) {
      throw StateError('Sign in before connecting to chat updates.');
    }
    return _service.connectMessageSocket(
      onMessage,
      onMessageDeleted: onMessageDeleted,
      onChatCleared: onChatCleared,
      onMessagesRead: onMessagesRead,
    );
  }

  Future<UserSearchResult> searchUser(String userId) {
    if (_accessToken.isEmpty) {
      throw StateError('Sign in before searching for neighbours.');
    }
    return _service.searchUser(userId);
  }

  Future<void> sendConnectionRequest(String userId) async {
    if (_accessToken.isEmpty) {
      throw StateError('Sign in before sending a connection request.');
    }
    await _service.sendConnectionRequest(userId);
    await loadAll();
  }

  Future<void> refresh() => loadAll();

  Future<void> acceptRequest(String requestId) async {
    await _service.acceptRequest(requestId);
    await loadAll();
  }

  Future<void> declineRequest(String requestId) async {
    await _service.declineRequest(requestId);
    await loadAll();
  }

  Future<ChatMessage> sendMessage(
    String chatId,
    String text, {
    required String clientId,
  }) {
    if (text.trim().isEmpty) {
      throw ArgumentError.value(text, 'text', 'Message cannot be empty.');
    }
    return _service.sendMessage(chatId, text, clientId: clientId);
  }

  Future<String> uploadImage(
    String chatId,
    Uint8List bytes, {
    required void Function(int sent, int total) onProgress,
  }) {
    if (_accessToken.isEmpty) {
      throw StateError('Sign in before uploading an image.');
    }
    return _service.uploadImage(chatId, bytes, onProgress: onProgress);
  }

  Future<Uint8List> downloadImage(String imageUrl) {
    if (_accessToken.isEmpty) {
      throw StateError('Sign in before downloading an image.');
    }
    return _service.downloadImage(imageUrl);
  }

  Future<ChatMessage> sendImageMessage(
    String chatId, {
    required String imageUrl,
    required String clientId,
    String? caption,
  }) {
    if (_accessToken.isEmpty) {
      throw StateError('Sign in before sending an image.');
    }
    return _service.sendImageMessage(
      chatId,
      imageUrl: imageUrl,
      clientId: clientId,
      caption: caption,
    );
  }

  Future<void> deleteMessage(String chatId, String messageId) {
    if (_accessToken.isEmpty) {
      throw StateError('Sign in before deleting a message.');
    }
    return _service.deleteMessage(chatId, messageId);
  }

  Future<void> deleteMessages(String chatId, List<String> messageIds) {
    if (_accessToken.isEmpty) {
      throw StateError('Sign in before deleting messages.');
    }
    return _service.deleteMessages(chatId, messageIds);
  }

  Future<void> markChatRead(String chatId) async {
    if (_accessToken.isEmpty) {
      throw StateError('Sign in before marking a chat as read.');
    }
    await _service.markChatRead(chatId);
    chats = chats
        .map((chat) => chat.id == chatId ? chat.copyWith(unreadCount: 0) : chat)
        .toList();
    notifyListeners();
  }

  Future<void> clearChat(String chatId) {
    if (_accessToken.isEmpty) {
      throw StateError('Sign in before clearing a chat.');
    }
    return _service.clearChat(chatId);
  }
}
