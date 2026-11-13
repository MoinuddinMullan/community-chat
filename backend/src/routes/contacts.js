import express from 'express';
import mongoose from 'mongoose';
import { z } from 'zod';
import Connection from '../models/Connection.js';
import User from '../models/User.js';
import Chat from '../models/Chat.js';
import Message from '../models/Message.js';
import Media from '../models/Media.js';
import { requireAuth } from '../middleware/auth.js';
import { asyncHandler } from '../middleware/asyncHandler.js';

const router = express.Router();

router.get('/', requireAuth, asyncHandler(async (req, res) => {
  const connections = await Connection.find({
    $or: [{ requester: req.user.sub }, { recipient: req.user.sub }],
    status: 'accepted',
  }).populate('requester recipient');

  const contacts = connections.map(async (connection) => {
    const peer = String(connection.requester._id) === req.user.sub ? connection.recipient : connection.requester;
    const chat = await Chat.findOne({ participants: mongoose.trusted({ $all: [req.user.sub, peer._id] }) });
    return {
      userId: peer.userId,
      displayName: peer.displayName,
      publicKey: peer.publicKey,
      publicKeyUpdatedAt: peer.publicKeyUpdatedAt,
      chatId: chat ? chat._id.toString() : null,
    };
  });

  res.json(await Promise.all(contacts));
}));

router.delete('/:userId', requireAuth, asyncHandler(async (req, res) => {
  const targetUser = await User.findOne({ userId: req.params.userId.toLowerCase() });
  if (!targetUser) return res.status(404).json({ error: { code: 'USER_NOT_FOUND', message: 'Contact not found.' } });

  const connection = await Connection.findOne({
    $or: [
      { requester: req.user.sub, recipient: targetUser._id },
      { requester: targetUser._id, recipient: req.user.sub },
    ],
    status: 'accepted',
  });
  if (!connection) return res.status(404).json({ error: { code: 'NOT_CONNECTED', message: 'Contact not found.' } });

  const chat = await Chat.findOne({ participants: mongoose.trusted({ $all: [req.user.sub, targetUser._id] }) });
  if (chat) {
    await Message.deleteMany({ chat: chat._id });
    await Media.deleteMany({ chat: chat._id });
    await chat.deleteOne();
  }

  connection.status = 'declined';
  connection.respondedAt = new Date();
  await connection.save();

  res.json({ ok: true });
}));

router.post('/:userId/block', requireAuth, asyncHandler(async (req, res) => {
  const targetUser = await User.findOne({ userId: req.params.userId.toLowerCase() });
  if (!targetUser) return res.status(404).json({ error: { code: 'USER_NOT_FOUND', message: 'User not found.' } });

  const pairKey = [req.user.sub, targetUser._id.toString()].sort().join(':');
  let connection = await Connection.findOne({ pairKey });
  if (!connection) {
    connection = await Connection.create({ pairKey, requester: req.user.sub, recipient: targetUser._id, status: 'blocked', blockedBy: req.user.sub });
  } else {
    connection.status = 'blocked';
    connection.blockedBy = req.user.sub;
    await connection.save();
  }

  res.json({ ok: true, status: 'blocked' });
}));

router.get('/blocked', requireAuth, asyncHandler(async (req, res) => {
  const blocked = await Connection.find({
    $or: [{ requester: req.user.sub }, { recipient: req.user.sub }],
    status: 'blocked',
  }).populate('requester recipient');

  res.json(blocked.map((item) => {
    const peer = String(item.requester._id) === req.user.sub ? item.recipient : item.requester;
    return { userId: peer.userId, displayName: peer.displayName };
  }));
}));

router.delete('/blocked/:userId', requireAuth, asyncHandler(async (req, res) => {
  const targetUser = await User.findOne({ userId: req.params.userId.toLowerCase() });
  if (!targetUser) return res.status(404).json({ error: { code: 'USER_NOT_FOUND', message: 'User not found.' } });

  const connection = await Connection.findOne({
    $or: [
      { requester: req.user.sub, recipient: targetUser._id },
      { requester: targetUser._id, recipient: req.user.sub },
    ],
    status: 'blocked',
  });
  if (!connection) return res.status(404).json({ error: { code: 'NOT_BLOCKED', message: 'This user is not blocked.' } });

  connection.status = 'declined';
  connection.blockedBy = null;
  await connection.save();
  res.json({ ok: true });
}));

export default router;
