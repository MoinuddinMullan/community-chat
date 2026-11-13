import dns from 'node:dns';
import mongoose from 'mongoose';
import { env } from './env.js';

mongoose.set('sanitizeFilter', true);

export async function connectDB() {
  try {
    if (env.MONGODB_DNS_SERVERS.length > 0) {
      dns.setServers(env.MONGODB_DNS_SERVERS);
    }

    await mongoose.connect(env.MONGODB_URI, {
      dbName: env.MONGODB_DB,
      serverSelectionTimeoutMS: 5000,
    });
    console.log(`MongoDB connected to ${env.MONGODB_DB}`);
    return mongoose.connection;
  } catch (error) {
    console.error('MongoDB connection failed. Check DNS resolution, Atlas Network Access, and URL-encode special characters in the DB password.');
    console.error(error.message);
    throw error;
  }
}
