export function toMessageDto(message) {
  const senderId = message.sender?._id?.toString() ?? message.sender?.toString() ?? null;
  return {
    id: message._id.toString(),
    chatId: message.chat.toString(),
    sender: senderId,
    senderId,
    type: message.type,
    payload: message.payload ?? null,
    imageUrl: message.imageUrl ?? (message.media ? `/api/media/${message.media.toString()}` : null),
    caption: message.caption ?? null,
    clientId: message.clientId ?? null,
    mediaId: message.media?.toString() ?? null,
    createdAt: message.createdAt,
    expiresAt: message.expiresAt,
    readAt: message.readAt ?? null,
  };
}

export function toUserDto(user) {
  return {
    userId: user.userId,
    displayName: user.displayName,
    publicKey: user.publicKey ?? null,
    publicKeyUpdatedAt: user.publicKeyUpdatedAt ?? null,
  };
}
