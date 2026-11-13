import express from 'express';
import mongoose from 'mongoose';
import { z } from 'zod';
import Chat from '../models/Chat.js';
import Connection from '../models/Connection.js';
import User from '../models/User.js';
import Message from '../models/Message.js';
import Media from '../models/Media.js';
import { env } from '../config/env.js';
import { requireAuth } from '../middleware/auth.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { validateBody } from '../middleware/validate.js';
import { toMessageDto } from '../utils/dto.js';

const router = express.Router();

const messageSchema = z.discriminatedUnion('type', [
  z.object({
    type: z.literal('text'),
    payload: z.string().regex(/^enc1:[A-Za-z0-9+/]+={0,2}$/).max(3000),
    clientId: z.string().min(1).max(200),
  }).strict(),
  z.object({
    type: z.literal('image'),
    imageUrl: z.string().regex(/^\/api\/media\/[a-fA-F0-9]{24}$/),
    caption: z.string().regex(/^enc1:[A-Za-z0-9+/]+={0,2}$/).max(4000).optional(),
    clientId: z.string().min(1).max(200),
  }).strict(),
]);

function isParticipant(chat, userId) {
  return chat.participants.some((participant) => participant.toString() === userId);
}

function emitMessage(io, chat, message) {
  emitToParticipants(io, chat, 'chat:message', {
    chatId: chat._id.toString(),
    message,
  });
}

function emitToParticipants(io, chat, event, payload) {
  for (const participant of chat.participants) {
    io?.to(`user:${participant.toString()}`).emit(event, payload);
  }
}

router.get('/', requireAuth, asyncHandler(async (req, res) => {
  const chats = await Chat.find({ participants: req.user.sub }).populate('participants');
  const results = [];
  const now = new Date();

  for (const chat of chats) {
    const peer = chat.participants.find((p) => p._id.toString() !== req.user.sub);
    const lastMessage = await Message.findOne({
      chat: chat._id,
      expiresAt: mongoose.trusted({ $gt: now }),
    }).sort({ createdAt: -1 });
    const unreadCount = await Message.countDocuments({
      chat: chat._id,
      sender: mongoose.trusted({ $ne: req.user.sub }),
      readAt: null,
      expiresAt: mongoose.trusted({ $gt: now }),
    });
    results.push({
      chatId: chat._id.toString(),
      peer: {
        userId: peer.userId,
        displayName: peer.displayName,
        publicKey: peer.publicKey,
      },
      lastMessage: lastMessage ? toMessageDto(lastMessage) : null,
      unreadCount,
    });
  }

  res.json(results);
}));

router.get('/:chatId/messages', requireAuth, asyncHandler(async (req, res) => {
  const chat = await Chat.findById(req.params.chatId);
  if (!chat || !isParticipant(chat, req.user.sub)) return res.status(404).json({ error: { code: 'CHAT_NOT_FOUND', message: 'Chat not found.' } });

  const connection = await Connection.findOne({
    $or: [
      { requester: req.user.sub, recipient: mongoose.trusted({ $in: chat.participants }) },
      { recipient: req.user.sub, requester: mongoose.trusted({ $in: chat.participants }) },
    ],
    status: 'accepted',
  });
  if (!connection) return res.status(404).json({ error: { code: 'CHAT_NOT_FOUND', message: 'Chat not found.' } });

  const before = req.query.before ? req.query.before.toString() : null;
  const requestedLimit = Number(req.query.limit || 30);
  const limit = Number.isFinite(requestedLimit)
    ? Math.max(1, Math.min(requestedLimit, 30))
    : 30;
  const query = {
    chat: chat._id,
    expiresAt: mongoose.trusted({ $gt: new Date() }),
  };
  if (before) query._id = mongoose.trusted({ $lt: before });

  const messages = await Message.find(query).sort({ _id: -1 }).limit(limit);
  res.json(messages.map(toMessageDto).reverse());
}));

router.post('/:chatId/messages', requireAuth, validateBody(messageSchema), asyncHandler(async (req, res) => {
  const chat = await Chat.findById(req.params.chatId);
  if (!chat || !isParticipant(chat, req.user.sub)) return res.status(404).json({ error: { code: 'CHAT_NOT_FOUND', message: 'Chat not found.' } });

  const connection = await Connection.findOne({
    $or: [
      { requester: req.user.sub, recipient: mongoose.trusted({ $in: chat.participants }) },
      { recipient: req.user.sub, requester: mongoose.trusted({ $in: chat.participants }) },
    ],
    status: 'accepted',
  });
  if (!connection) return res.status(404).json({ error: { code: 'CHAT_NOT_FOUND', message: 'Chat not found.' } });

  let media = null;
  if (req.body.type === 'image') {
    const mediaId = req.body.imageUrl.slice('/api/media/'.length);
    media = await Media.findOne({
      _id: mediaId,
      chat: chat._id,
      uploader: req.user.sub,
    });
    if (!media) {
      return res.status(400).json({ error: { code: 'INVALID_IMAGE', message: 'Upload a valid image for this chat before sending it.' } });
    }
  }

  const caption = req.body.type === 'image'
    ? req.body.caption?.trim() || null
    : null;
  const existingMessage = await Message.findOne({
    chat: chat._id,
    sender: req.user.sub,
    clientId: req.body.clientId,
  });
  if (existingMessage) {
    const sameContent = existingMessage.type === req.body.type
      && (req.body.type === 'text'
        ? existingMessage.payload === req.body.payload
        : existingMessage.imageUrl === req.body.imageUrl
          && existingMessage.caption === caption);
    if (!sameContent) {
      return res.status(409).json({
        error: {
          code: 'CLIENT_ID_CONFLICT',
          message: 'This client message ID was already used for different content.',
        },
      });
    }

    const existingDto = toMessageDto(existingMessage);
    emitMessage(req.app.get('io'), chat, existingDto);
    return res.status(200).json({ ok: true, message: existingDto });
  }

  const createdAt = new Date();
  const message = await Message.create({
    chat: chat._id,
    sender: req.user.sub,
    type: req.body.type,
    payload: req.body.type === 'text' ? req.body.payload : null,
    imageUrl: req.body.type === 'image' ? req.body.imageUrl : null,
    caption,
    media: media?._id ?? null,
    clientId: req.body.clientId,
    createdAt,
    expiresAt: new Date(createdAt.getTime() + env.CHAT_VISIBLE_DAYS * 86400000),
    purgeAt: new Date(createdAt.getTime() + env.DB_PURGE_DAYS * 86400000),
  });

  const messageDto = toMessageDto(message);
  emitMessage(req.app.get('io'), chat, messageDto);

  res.status(201).json({ ok: true, message: messageDto });
}));

router.post('/:chatId/read', requireAuth, asyncHandler(async (req, res) => {
  const chat = await Chat.findById(req.params.chatId);
  if (!chat || !isParticipant(chat, req.user.sub)) return res.status(404).json({ error: { code: 'CHAT_NOT_FOUND', message: 'Chat not found.' } });

  await Message.updateMany({ chat: chat._id, sender: mongoose.trusted({ $ne: req.user.sub }), readAt: null }, { readAt: new Date() });
  res.json({ ok: true });
}));

router.delete('/:chatId/messages', requireAuth, asyncHandler(async (req, res) => {
  const chat = await Chat.findById(req.params.chatId);
  if (!chat || !isParticipant(chat, req.user.sub)) return res.status(404).json({ error: { code: 'CHAT_NOT_FOUND', message: 'Chat not found.' } });

  await Message.deleteMany({ chat: chat._id });
  await Media.deleteMany({ chat: chat._id });
  emitToParticipants(req.app.get('io'), chat, 'chat:cleared', {
    chatId: chat._id.toString(),
  });
  res.json({ ok: true });
}));

router.delete('/:chatId/messages/:messageId', requireAuth, asyncHandler(async (req, res) => {
  const chat = await Chat.findById(req.params.chatId);
  if (!chat || !isParticipant(chat, req.user.sub)) return res.status(404).json({ error: { code: 'CHAT_NOT_FOUND', message: 'Chat not found.' } });

  const message = await Message.findOne({ _id: req.params.messageId, chat: chat._id, sender: req.user.sub });
  if (!message) return res.status(404).json({ error: { code: 'MESSAGE_NOT_FOUND', message: 'Message not found.' } });
  await message.deleteOne();
  const mediaId = message.media
    ?? message.imageUrl?.match(/^\/api\/media\/([a-fA-F0-9]{24})$/)?.[1];
  if (mediaId) await Media.deleteOne({ _id: mediaId, chat: chat._id });
  emitToParticipants(req.app.get('io'), chat, 'chat:message_deleted', {
    chatId: chat._id.toString(),
    messageId: message._id.toString(),
  });
  res.json({ ok: true });
}));

export default router;
