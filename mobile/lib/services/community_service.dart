import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../core/config.dart';
import '../core/theme.dart';
import '../models/chat_item.dart';

class CommunityApiService {
  CommunityApiService({required String accessToken})
    : _accessToken = accessToken,
      _dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: AppConfig.connectTimeout,
          sendTimeout: AppConfig.sendTimeout,
          receiveTimeout: AppConfig.receiveTimeout,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
        ),
      );

  final Dio _dio;
  final String _accessToken;

  Future<List<ChatItem>> fetchChats() async {
    final response = await _dio.get('/api/chats');
    final payload = response.data is List ? response.data as List : const [];
    return payload.map<ChatItem>((entry) {
      final item = Map<String, dynamic>.from(entry as Map);
      final peer = item['peer'] is Map
          ? Map<String, dynamic>.from(item['peer'] as Map)
          : <String, dynamic>{};
      final lastMessage = item['lastMessage'] is Map
          ? Map<String, dynamic>.from(item['lastMessage'] as Map)
          : null;
      final timestampRaw = lastMessage != null
          ? lastMessage['createdAt']
          : item['updatedAt'];
      final timestamp = timestampRaw == null
          ? DateTime.now()
          : DateTime.tryParse(timestampRaw.toString()) ?? DateTime.now();

      return ChatItem(
        id: item['chatId']?.toString() ?? '',
        name: (peer['displayName'] ?? peer['userId'] ?? 'Community chat')
            .toString(),
        lastMessage: lastMessage == null
            ? 'No messages yet'
            : lastMessage['type'] == 'image'
            ? 'Photo'
            : (lastMessage['payload']?.toString().startsWith('enc1:') ?? false)
            ? 'Encrypted message'
            : (lastMessage['payload'] ?? '').toString(),
        timestamp: timestamp,
        unreadCount: int.tryParse('${item['unreadCount'] ?? 0}') ?? 0,
        online: true,
        avatarColor: AppColors.avatarFallbackBg,
        peerPublicKey: peer['publicKey']?.toString(),
      );
    }).toList();
  }

  Future<List<ContactRequestItem>> fetchRequests() async {
    final response = await _dio.get('/api/requests');
    final payload = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : <String, dynamic>{};
    final incoming = payload['incoming'] is List
        ? payload['incoming'] as List
        : const [];
    final outgoing = payload['outgoing'] is List
        ? payload['outgoing'] as List
        : const [];
    final incomingItems = incoming.map<ContactRequestItem>((entry) {
      final item = Map<String, dynamic>.from(entry as Map);
      return ContactRequestItem(
        id: item['id']?.toString() ?? '',
        name: (item['displayName'] ?? item['userId'] ?? 'Neighbour').toString(),
        message: 'Pending neighbourhood connection request',
        timestamp: DateTime.now(),
        isIncoming: true,
      );
    });
    final outgoingItems = outgoing.map<ContactRequestItem>((entry) {
      final item = Map<String, dynamic>.from(entry as Map);
      return ContactRequestItem(
        id: item['id']?.toString() ?? '',
        name: (item['displayName'] ?? item['userId'] ?? 'Neighbour').toString(),
        message: 'Connection request sent',
        timestamp: DateTime.now(),
        isIncoming: false,
      );
    });
    return [...incomingItems, ...outgoingItems];
  }

  Future<UserSearchResult> searchUser(String userId) async {
    final response = await _dio.get(
      '/api/users/search',
      queryParameters: {'userId': userId.trim()},
    );
    final payload = Map<String, dynamic>.from(response.data as Map);
    return UserSearchResult(
      userId: payload['userId'].toString(),
      displayName: payload['displayName'].toString(),
    );
  }

  Future<void> sendConnectionRequest(String userId) async {
    await _dio.post('/api/requests', data: {'toUserId': userId});
  }

  Future<List<ContactEntry>> fetchContacts() async {
    final response = await _dio.get('/api/contacts');
    final payload = response.data is List ? response.data as List : const [];
    return payload.map<ContactEntry>((entry) {
      final item = Map<String, dynamic>.from(entry as Map);
      return ContactEntry(
        id: item['userId']?.toString() ?? '',
        name: (item['displayName'] ?? item['userId'] ?? 'Neighbour').toString(),
        group: 'Neighbourhood connection',
        online: true,
      );
    }).toList();
  }

  Future<void> acceptRequest(String requestId) async {
    await _dio.post('/api/requests/$requestId/accept');
  }

  Future<void> declineRequest(String requestId) async {
    await _dio.post('/api/requests/$requestId/decline');
  }

  Future<ChatMessage> sendMessage(
    String chatId,
    String text, {
    required String clientId,
  }) async {
    final response = await _dio.post(
      '/api/chats/$chatId/messages',
      data: {'type': 'text', 'payload': text, 'clientId': clientId},
    );
    final body = Map<String, dynamic>.from(response.data as Map);
    return ChatMessage.fromJson(
      Map<String, dynamic>.from(body['message'] as Map),
    );
  }

  Future<String> uploadImage(
    String chatId,
    Uint8List bytes, {
    required void Function(int sent, int total) onProgress,
  }) async {
    final response = await _dio.post(
      '/api/media/$chatId/upload',
      data: bytes,
      options: Options(
        contentType: 'application/octet-stream',
        headers: {'X-Image-Content-Type': 'application/octet-stream'},
      ),
      onSendProgress: onProgress,
    );
    final payload = Map<String, dynamic>.from(response.data as Map);
    final imageUrl = payload['imageUrl']?.toString();
    if (imageUrl == null || imageUrl.isEmpty) {
      throw const FormatException('Image upload returned no image URL.');
    }
    return imageUrl;
  }

  Future<Uint8List> downloadImage(String imageUrl) async {
    final response = await _dio.get<List<int>>(
      imageUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = response.data;
    if (data == null) {
      throw const FormatException('Image download returned no data.');
    }
    return Uint8List.fromList(data);
  }

  Future<ChatMessage> sendImageMessage(
    String chatId, {
    required String imageUrl,
    required String clientId,
    String? caption,
  }) async {
    final response = await _dio.post(
      '/api/chats/$chatId/messages',
      data: {
        'type': 'image',
        'imageUrl': imageUrl,
        if (caption != null && caption.isNotEmpty) 'caption': caption,
        'clientId': clientId,
      },
    );
    final body = Map<String, dynamic>.from(response.data as Map);
    return ChatMessage.fromJson(
      Map<String, dynamic>.from(body['message'] as Map),
    );
  }

  Future<List<ChatMessage>> fetchMessages(String chatId) async {
    const pageSize = 30;
    final messages = <ChatMessage>[];
    String? before;

    while (true) {
      final response = await _dio.get(
        '/api/chats/$chatId/messages',
        queryParameters: {'limit': pageSize, 'before': ?before},
      );
      final payload = response.data is List ? response.data as List : const [];
      final page = payload
          .map<ChatMessage>(
            (entry) =>
                ChatMessage.fromJson(Map<String, dynamic>.from(entry as Map)),
          )
          .toList();
      messages.addAll(page);

      if (page.length < pageSize) break;
      final nextCursor = page.first.id;
      if (nextCursor.isEmpty || nextCursor == before) {
        throw const FormatException('Chat history pagination did not advance.');
      }
      before = nextCursor;
    }

    return messages;
  }

  Future<void> deleteMessage(String chatId, String messageId) async {
    await _dio.delete('/api/chats/$chatId/messages/$messageId');
  }

  Future<void> deleteMessages(String chatId, List<String> messageIds) async {
    await _dio.post(
      '/api/chats/$chatId/messages/delete',
      data: {'messageIds': messageIds},
    );
  }

  Future<void> markChatRead(String chatId) async {
    await _dio.post('/api/chats/$chatId/read');
  }

  Future<void> clearChat(String chatId) async {
    await _dio.delete('/api/chats/$chatId/messages');
  }

  io.Socket connectMessageSocket(
    void Function(String chatId, ChatMessage message) onMessage, {
    void Function(String chatId, String messageId)? onMessageDeleted,
    void Function(String chatId)? onChatCleared,
    void Function(String chatId, List<String> messageIds, DateTime readAt)?
    onMessagesRead,
  }) {
    final socket = io.io(AppConfig.apiBaseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'timeout': 60000,
      'auth': {'token': _accessToken},
    });
    socket.on('chat:message', (data) {
      if (data is! Map || data['chatId'] == null || data['message'] is! Map) {
        return;
      }
      onMessage(
        data['chatId'].toString(),
        ChatMessage.fromJson(Map<String, dynamic>.from(data['message'] as Map)),
      );
    });
    socket.on('chat:message_deleted', (data) {
      if (data is! Map || data['chatId'] == null || data['messageId'] == null) {
        return;
      }
      onMessageDeleted?.call(
        data['chatId'].toString(),
        data['messageId'].toString(),
      );
    });
    socket.on('chat:cleared', (data) {
      if (data is! Map || data['chatId'] == null) return;
      onChatCleared?.call(data['chatId'].toString());
    });
    socket.on('chat:read', (data) {
      if (data is! Map ||
          data['chatId'] == null ||
          data['messageIds'] is! List) {
        return;
      }
      final readAt = DateTime.tryParse(data['readAt']?.toString() ?? '');
      if (readAt == null) return;
      final messageIds = (data['messageIds'] as List)
          .map((id) => id.toString())
          .toList();
      onMessagesRead?.call(data['chatId'].toString(), messageIds, readAt);
    });
    socket.connect();
    return socket;
  }
}
