import express from 'express';
import mongoose from 'mongoose';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import User from '../models/User.js';
import Session from '../models/Session.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { validateBody } from '../middleware/validate.js';
import { requireAuth } from '../middleware/auth.js';
import { loginLimiter, registerLimiter } from '../middleware/rateLimits.js';
import { env } from '../config/env.js';
import { generateAccessToken, generateRefreshToken, hashToken } from '../utils/tokens.js';

const router = express.Router();

const registerSchema = z.object({
  userId: z.string().trim()
    .regex(/^[a-z0-9_.]{3,20}$/i, 'User ID must be 3-20 characters using letters, numbers, periods, or underscores.')
    .transform((value) => value.toLowerCase()),
  password: z.string().regex(/^\d{4}$/, 'PIN must contain exactly four digits.'),
  publicKey: z.string().min(10).max(500).optional(),
}).strict();

const loginSchema = z.object({
  userId: z.string().trim().min(3).max(20),
  password: z.string().max(128).refine(
    (value) => /^\d{4}$/.test(value) || value.length >= 8,
    'Enter a four-digit PIN.',
  ),
}).strict();

const pinSchema = z.object({
  pin: z.string().regex(/^\d{4}$/, 'PIN must contain exactly four digits.'),
}).strict();

const refreshSchema = z.object({ refreshToken: z.string().min(16) }).strict();

router.post('/register', registerLimiter, validateBody(registerSchema), asyncHandler(async (req, res) => {
  const { userId, password, publicKey } = req.body;
  const normalizedUserId = userId.toLowerCase();
  const existing = await User.findOne({ userId: normalizedUserId });
  if (existing) {
    return res.status(409).json({ error: { code: 'USER_EXISTS', message: 'That user ID is already in use.' } });
  }

  const passwordHash = await bcrypt.hash(password, 12);
  const user = await User.create({
    userId: normalizedUserId,
    displayName: normalizedUserId,
    passwordHash,
    pinConfigured: true,
    publicKey: publicKey || null,
    publicKeyUpdatedAt: publicKey ? new Date() : null,
  });

  const accessToken = generateAccessToken({ sub: user._id.toString(), userId: user.userId, displayName: user.userId });
  const refreshToken = generateRefreshToken();
  const expiry = new Date(Date.now() + env.REFRESH_TOKEN_DAYS * 24 * 60 * 60 * 1000);
  await Session.create({ user: user._id, tokenHash: hashToken(refreshToken), expiresAt: expiry });

  return res.status(201).json({
    accessToken,
    refreshToken,
    me: { userId: user.userId, displayName: user.userId, publicKey: user.publicKey },
  });
}));

router.post('/login', loginLimiter, validateBody(loginSchema), asyncHandler(async (req, res) => {
  const { userId, password } = req.body;
  const normalizedUserId = userId.toLowerCase();
  const dummyHash = await bcrypt.hash('dummy-account-check', 12);
  const user = await User.findOne({ userId: normalizedUserId });

  if (!user) {
    const passwordCheck = await bcrypt.compare(password, dummyHash);
    if (!passwordCheck) {
      return res.status(401).json({ error: { code: 'INVALID_CREDENTIALS', message: 'Incorrect user ID or password.' } });
    }
  }

  if (user?.lockUntil && new Date(user.lockUntil) > new Date()) {
    return res.status(401).json({ error: { code: 'LOCKED', message: 'This account is temporarily locked.' } });
  }

  const valid = user ? await bcrypt.compare(password, user.passwordHash) : false;
  if (!user || !valid) {
    if (user) {
      user.failedLogins = (user.failedLogins || 0) + 1;
      if (user.failedLogins >= 5) {
        user.lockUntil = new Date(Date.now() + 15 * 60 * 1000);
      }
      await user.save();
    }
    return res.status(401).json({ error: { code: 'INVALID_CREDENTIALS', message: 'Incorrect user ID or password.' } });
  }

  user.failedLogins = 0;
  user.lockUntil = null;
  user.displayName = user.userId;
  await user.save();

  const accessToken = generateAccessToken({ sub: user._id.toString(), userId: user.userId, displayName: user.userId });
  const refreshToken = generateRefreshToken();
  await Session.create({ user: user._id, tokenHash: hashToken(refreshToken), expiresAt: new Date(Date.now() + env.REFRESH_TOKEN_DAYS * 24 * 60 * 60 * 1000) });

  return res.json({
    accessToken,
    refreshToken,
    requiresPinSetup: user.pinConfigured !== true,
    me: { userId: user.userId, displayName: user.userId, publicKey: user.publicKey },
  });
}));

router.post('/pin', requireAuth, validateBody(pinSchema), asyncHandler(async (req, res) => {
  const user = await User.findById(req.user.sub);
  if (!user) {
    return res.status(404).json({ error: { code: 'USER_NOT_FOUND', message: 'This account could not be found.' } });
  }
  if (user.pinConfigured === true) {
    return res.status(409).json({ error: { code: 'PIN_ALREADY_CONFIGURED', message: 'This account already has a PIN.' } });
  }

  user.passwordHash = await bcrypt.hash(req.body.pin, 12);
  user.pinConfigured = true;
  await user.save();
  return res.json({ ok: true });
}));

router.post('/refresh', validateBody(refreshSchema), asyncHandler(async (req, res) => {
  const { refreshToken } = req.body;
  const hashed = hashToken(refreshToken);
  const session = await Session.findOne({ tokenHash: hashed }).populate('user');
  if (!session || session.used || session.expiresAt < new Date()) {
    return res.status(401).json({ error: { code: 'INVALID_REFRESH', message: 'Your refresh token has expired or been revoked.' } });
  }

  session.used = true;
  await session.save();

  const user = session.user;
  const newRefreshToken = generateRefreshToken();
  await Session.deleteMany({ user: user._id, tokenHash: mongoose.trusted({ $ne: hashed }) });
  await Session.create({ user: user._id, tokenHash: hashToken(newRefreshToken), expiresAt: new Date(Date.now() + env.REFRESH_TOKEN_DAYS * 24 * 60 * 60 * 1000) });

  const accessToken = generateAccessToken({ sub: user._id.toString(), userId: user.userId, displayName: user.displayName });

  return res.json({ accessToken, refreshToken: newRefreshToken, me: { userId: user.userId, displayName: user.displayName, publicKey: user.publicKey } });
}));

router.post('/logout', validateBody(refreshSchema), asyncHandler(async (req, res) => {
  const { refreshToken } = req.body;
  await Session.deleteMany({ tokenHash: hashToken(refreshToken) });
  res.json({ ok: true });
}));

export default router;
