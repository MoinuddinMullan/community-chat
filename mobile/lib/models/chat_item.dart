import 'dart:typed_data';

import 'package:flutter/material.dart';

class ChatItem {
  const ChatItem({
    required this.id,
    required this.name,
    required this.lastMessage,
    required this.timestamp,
    required this.unreadCount,
    required this.online,
    required this.avatarColor,
    this.peerPublicKey,
  });

  final String id;
  final String name;
  final String lastMessage;
  final DateTime timestamp;
  final int unreadCount;
  final bool online;
  final Color avatarColor;
  final String? peerPublicKey;
}

class ContactRequestItem {
  const ContactRequestItem({
    required this.id,
    required this.name,
    required this.message,
    required this.timestamp,
    required this.isIncoming,
  });

  final String id;
  final String name;
  final String message;
  final DateTime timestamp;
  final bool isIncoming;
}

class UserSearchResult {
  const UserSearchResult({required this.userId, required this.displayName});

  final String userId;
  final String displayName;
}

class ContactEntry {
  const ContactEntry({
    required this.id,
    required this.name,
    required this.group,
    required this.online,
  });

  final String id;
  final String name;
  final String group;
  final bool online;
}

class ChatMessage {
  factory ChatMessage.fromJson(Map<String, dynamic> item) {
    final rawSender =
        item['senderId'] ?? item['sender'] ?? item['from'] ?? item['userId'];
    final senderId = rawSender is Map
        ? (rawSender['_id'] ?? rawSender['id'] ?? rawSender['userId'] ?? '')
              .toString()
        : rawSender?.toString() ?? '';

    return ChatMessage(
      id: (item['id'] ?? item['_id'] ?? '').toString(),
      senderId: senderId.trim(),
      text: (item['payload'] ?? '').toString(),
      clientId: item['clientId']?.toString(),
      createdAt: DateTime.tryParse(item['createdAt']?.toString() ?? ''),
      expiresAt: DateTime.tryParse(item['expiresAt']?.toString() ?? ''),
      type: item['type'] == 'image' ? 'image' : 'text',
      imageUrl: item['imageUrl']?.toString(),
      encryptedCaption:
          (item['caption']?.toString().startsWith('enc1:') ?? false)
          ? item['caption']?.toString()
          : null,
      caption: (item['caption']?.toString().startsWith('enc1:') ?? false)
          ? null
          : item['caption']?.toString(),
    );
  }

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    this.type = 'text',
    this.imageUrl,
    this.encryptedCaption,
    this.caption,
    this.encryptedImageBytes,
    this.clientId,
    this.createdAt,
    this.expiresAt,
    this.localImageBytes,
    this.isUploading = false,
    this.uploadProgress = 0,
    this.uploadFailed = false,
    this.isLoadingImage = false,
    this.imageLoadFailed = false,
  });

  final String id;
  final String senderId;
  final String text;
  final String type;
  final String? imageUrl;
  final String? encryptedCaption;
  final String? caption;
  final Uint8List? encryptedImageBytes;
  final String? clientId;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final Uint8List? localImageBytes;
  final bool isUploading;
  final double uploadProgress;
  final bool uploadFailed;
  final bool isLoadingImage;
  final bool imageLoadFailed;

  ChatMessage copyWith({
    String? id,
    String? senderId,
    String? text,
    String? type,
    String? imageUrl,
    String? encryptedCaption,
    String? caption,
    Uint8List? encryptedImageBytes,
    bool clearEncryptedImageBytes = false,
    String? clientId,
    DateTime? createdAt,
    DateTime? expiresAt,
    Uint8List? localImageBytes,
    bool clearLocalImageBytes = false,
    bool? isUploading,
    double? uploadProgress,
    bool? uploadFailed,
    bool? isLoadingImage,
    bool? imageLoadFailed,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      type: type ?? this.type,
      imageUrl: imageUrl ?? this.imageUrl,
      encryptedCaption: encryptedCaption ?? this.encryptedCaption,
      caption: caption ?? this.caption,
      encryptedImageBytes: clearEncryptedImageBytes
          ? null
          : encryptedImageBytes ?? this.encryptedImageBytes,
      clientId: clientId ?? this.clientId,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      localImageBytes: clearLocalImageBytes
          ? null
          : localImageBytes ?? this.localImageBytes,
      isUploading: isUploading ?? this.isUploading,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      uploadFailed: uploadFailed ?? this.uploadFailed,
      isLoadingImage: isLoadingImage ?? this.isLoadingImage,
      imageLoadFailed: imageLoadFailed ?? this.imageLoadFailed,
    );
  }
}
