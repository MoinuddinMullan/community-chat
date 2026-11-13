import crypto from 'node:crypto';
import bcrypt from 'bcryptjs';
import dotenv from 'dotenv';
import mongoose from 'mongoose';
import User from '../src/models/User.js';
import Session from '../src/models/Session.js';
import { env } from '../src/config/env.js';

dotenv.config();

const [, , userId, newPin] = process.argv;
if (!userId || !newPin || !/^\d{4}$/.test(newPin)) {
  console.error('Usage: node scripts/reset-password.js <userId> <new-four-digit-PIN>');
  process.exit(1);
}

async function main() {
  await mongoose.connect(env.MONGODB_URI, { dbName: env.MONGODB_DB, serverSelectionTimeoutMS: 5000 });
  const user = await User.findOne({ userId: userId.toLowerCase() });
  if (!user) {
    console.error('User not found.');
    process.exit(1);
  }

  user.passwordHash = await bcrypt.hash(newPin, 12);
  user.pinConfigured = true;
  user.displayName = user.userId;
  user.failedLogins = 0;
  user.lockUntil = null;
  await user.save();
  await Session.deleteMany({ user: user._id });
  console.log(`PIN reset for ${user.userId}. Sessions cleared.`);
  await mongoose.disconnect();
}

main().catch((error) => {
  console.error('Password reset failed.', error.message);
  process.exit(1);
});
