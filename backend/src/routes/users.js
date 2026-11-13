import express from 'express';
import { z } from 'zod';
import User from '../models/User.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { requireAuth } from '../middleware/auth.js';
import { validateBody } from '../middleware/validate.js';

const router = express.Router();

const updateMeSchema = z.object({ displayName: z.string().trim().min(2).max(80) }).strict();
const publicKeySchema = z.object({ publicKey: z.string().min(10).max(500) }).strict();

router.get('/me', requireAuth, asyncHandler(async (req, res) => {
  const user = await User.findById(req.user.sub);
  if (!user) return res.status(404).json({ error: { code: 'USER_NOT_FOUND', message: 'Account not found.' } });
  res.json({ userId: user.userId, displayName: user.displayName, publicKey: user.publicKey });
}));

router.patch('/me', requireAuth, validateBody(updateMeSchema), asyncHandler(async (req, res) => {
  const user = await User.findById(req.user.sub);
  if (!user) return res.status(404).json({ error: { code: 'USER_NOT_FOUND', message: 'Account not found.' } });
  user.displayName = req.body.displayName;
  await user.save();
  res.json({ userId: user.userId, displayName: user.displayName });
}));

router.put('/me/public-key', requireAuth, validateBody(publicKeySchema), asyncHandler(async (req, res) => {
  const user = await User.findById(req.user.sub);
  if (!user) return res.status(404).json({ error: { code: 'USER_NOT_FOUND', message: 'Account not found.' } });
  user.publicKey = req.body.publicKey;
  user.publicKeyUpdatedAt = new Date();
  await user.save();
  res.json({ ok: true, publicKey: user.publicKey });
}));

router.get('/search', requireAuth, asyncHandler(async (req, res) => {
  const userId = String(req.query.userId || '').trim().toLowerCase();
  if (!userId) {
    return res.status(400).json({ error: { code: 'INVALID_USER_ID', message: 'User ID is required.' } });
  }

  const user = await User.findOne({ userId }).select('userId displayName publicKey');
  if (!user) {
    return res.status(404).json({ error: { code: 'USER_NOT_FOUND', message: 'No neighbour matches that ID.' } });
  }

  res.json({ userId: user.userId, displayName: user.displayName, relationship: 'none' });
}));

export default router;
