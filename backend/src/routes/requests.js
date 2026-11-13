import express from 'express';
import { z } from 'zod';
import Connection from '../models/Connection.js';
import User from '../models/User.js';
import Chat from '../models/Chat.js';
import { requireAuth } from '../middleware/auth.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { validateBody } from '../middleware/validate.js';

const router = express.Router();
const requestSchema = z.object({ toUserId: z.string().trim().min(3).max(20) }).strict();

router.post('/', requireAuth, validateBody(requestSchema), asyncHandler(async (req, res) => {
  const target = await User.findOne({ userId: req.body.toUserId.toLowerCase() });
  if (!target) return res.status(404).json({ error: { code: 'USER_NOT_FOUND', message: 'Neighbour not found.' } });
  if (target._id.toString() === req.user.sub) return res.status(400).json({ error: { code: 'SELF_REQUEST', message: 'You cannot send a request to yourself.' } });

  const pairKey = [req.user.sub, target._id.toString()].sort().join(':');
  const existing = await Connection.findOne({ pairKey });
  if (existing) {
    if (existing.status === 'accepted') return res.status(409).json({ error: { code: 'ALREADY_CONNECTED', message: 'You are already connected.' } });
    if (existing.status === 'pending' && String(existing.requester) === req.user.sub) return res.status(409).json({ error: { code: 'REQUEST_PENDING', message: 'Your request is already pending.' } });
    if (existing.status === 'pending' && String(existing.recipient) === req.user.sub) return res.status(409).json({ error: { code: 'ACCEPT_REQUEST', message: 'This person already sent you a request. Accept it instead.' } });
  }

  const connection = await Connection.create({
    pairKey,
    requester: req.user.sub,
    recipient: target._id,
    status: 'pending',
  });

  res.status(201).json({ id: connection._id.toString(), status: 'pending' });
}));

router.get('/', requireAuth, asyncHandler(async (req, res) => {
  const incoming = await Connection.find({ recipient: req.user.sub, status: 'pending' }).populate('requester', 'userId displayName');
  const outgoing = await Connection.find({ requester: req.user.sub, status: 'pending' }).populate('recipient', 'userId displayName');

  res.json({
    incoming: incoming.map((item) => ({ id: item._id.toString(), userId: item.requester.userId, displayName: item.requester.displayName })),
    outgoing: outgoing.map((item) => ({ id: item._id.toString(), userId: item.recipient.userId, displayName: item.recipient.displayName })),
  });
}));

router.post('/:id/accept', requireAuth, asyncHandler(async (req, res) => {
  const connection = await Connection.findById(req.params.id);
  if (!connection) return res.status(404).json({ error: { code: 'REQUEST_NOT_FOUND', message: 'Request not found.' } });
  if (String(connection.recipient) !== req.user.sub) return res.status(404).json({ error: { code: 'NO_ACCESS', message: 'Request not found.' } });

  connection.status = 'accepted';
  connection.respondedAt = new Date();
  await connection.save();

  const chatPair = [connection.requester.toString(), connection.recipient.toString()].sort().join(':');
  await Chat.findOneAndUpdate({ pairKey: chatPair }, { $setOnInsert: { pairKey: chatPair, participants: [connection.requester, connection.recipient] } }, { upsert: true, new: true });

  res.json({ ok: true, status: 'accepted' });
}));

router.post('/:id/decline', requireAuth, asyncHandler(async (req, res) => {
  const connection = await Connection.findById(req.params.id);
  if (!connection) return res.status(404).json({ error: { code: 'REQUEST_NOT_FOUND', message: 'Request not found.' } });
  if (String(connection.recipient) !== req.user.sub && String(connection.requester) !== req.user.sub) return res.status(404).json({ error: { code: 'NO_ACCESS', message: 'Request not found.' } });

  connection.status = 'declined';
  connection.respondedAt = new Date();
  await connection.save();
  res.json({ ok: true, status: 'declined' });
}));

router.delete('/:id', requireAuth, asyncHandler(async (req, res) => {
  const connection = await Connection.findById(req.params.id);
  if (!connection) return res.status(404).json({ error: { code: 'REQUEST_NOT_FOUND', message: 'Request not found.' } });
  if (String(connection.requester) !== req.user.sub && String(connection.recipient) !== req.user.sub) return res.status(404).json({ error: { code: 'NO_ACCESS', message: 'Request not found.' } });
  await connection.deleteOne();
  res.json({ ok: true });
}));

export default router;
