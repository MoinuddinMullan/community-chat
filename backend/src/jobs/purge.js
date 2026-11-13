import mongoose from 'mongoose';
import cron from 'node-cron';
import Message from '../models/Message.js';
import Media from '../models/Media.js';
import Session from '../models/Session.js';

export async function purgeExpiredRecords(now = new Date()) {
  await Message.deleteMany({ purgeAt: mongoose.trusted({ $lte: now }) });
  await Media.deleteMany({ purgeAt: mongoose.trusted({ $lte: now }) });
  await Session.deleteMany({ expiresAt: mongoose.trusted({ $lte: now }) });
}

export function schedulePurgeJobs() {
  const purgeNow = () => purgeExpiredRecords().catch((error) => {
    console.error('Failed to purge expired records.', error);
  });

  void purgeNow();
  cron.schedule('0 * * * *', purgeNow);
}
