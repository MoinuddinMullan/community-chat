import express from 'express';
import mongoose from 'mongoose';
import Media from '../models/Media.js';
import Chat from '../models/Chat.js';
import Connection from '../models/Connection.js';
import { env } from '../config/env.js';
import { requireAuth } from '../middleware/auth.js';
import { asyncHandler } from '../middleware/asyncHandler.js';

const router = express.Router();

async function findAcceptedChat(chatId, userId) {
  const chat = await Chat.findById(chatId);
  if (!chat || !chat.participants.some((participant) => participant.toString() === userId)) {
    return null;
  }

  const connection = await Connection.findOne({
    $or: [
      { requester: userId, recipient: mongoose.trusted({ $in: chat.participants }) },
      { recipient: userId, requester: mongoose.trusted({ $in: chat.participants }) },
    ],
    status: 'accepted',
  });
  return connection ? chat : null;
}

router.post('/:chatId/upload', requireAuth, asyncHandler(async (req, res) => {
  const chat = await findAcceptedChat(req.params.chatId, req.user.sub);
  if (!chat) {
    return res.status(404).json({ error: { code: 'CHAT_NOT_FOUND', message: 'Chat not found.' } });
  }

  const buffer = Buffer.isBuffer(req.body) ? req.body : Buffer.alloc(0);
  if (buffer.length < 29) {
    return res.status(400).json({ error: { code: 'INVALID_IMAGE', message: 'Encrypted image data is required.' } });
  }
  if (buffer.length > env.MAX_IMAGE_BYTES) {
    return res.status(413).json({ error: { code: 'IMAGE_TOO_LARGE', message: 'Images must be 5 MB or smaller.' } });
  }

  const declaredContentType = req.get('X-Image-Content-Type');
  if (declaredContentType !== 'application/octet-stream') {
    return res.status(400).json({ error: { code: 'INVALID_IMAGE', message: 'Encrypted image data is required.' } });
  }

  const createdAt = new Date();
  const media = await Media.create({
    chat: chat._id,
    uploader: req.user.sub,
    data: buffer,
    size: buffer.length,
    contentType: 'application/octet-stream',
    createdAt,
    expiresAt: new Date(createdAt.getTime() + env.CHAT_VISIBLE_DAYS * 86400000),
    purgeAt: new Date(createdAt.getTime() + env.DB_PURGE_DAYS * 86400000),
  });

  res.status(201).json({
    ok: true,
    mediaId: media._id.toString(),
    imageUrl: `/api/media/${media._id.toString()}`,
  });
}));

router.get('/:mediaId', requireAuth, asyncHandler(async (req, res) => {
  const media = await Media.findById(req.params.mediaId).populate('chat');
  if (!media) return res.status(404).json({ error: { code: 'MEDIA_NOT_FOUND', message: 'Media not found.' } });
  if (media.expiresAt <= new Date()) {
    return res.status(404).json({ error: { code: 'MEDIA_NOT_FOUND', message: 'Media not found.' } });
  }
  const chat = media.chat;
  const userId = req.user.sub;
  const acceptedChat = await findAcceptedChat(chat._id, userId);
  if (!acceptedChat) return res.status(404).json({ error: { code: 'MEDIA_NOT_FOUND', message: 'Media not found.' } });

  const blob = await Media.findById(req.params.mediaId).select('+data');
  res.setHeader('Content-Type', blob.contentType || 'application/octet-stream');
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.send(blob.data);
}));

export default router;
