import dns from 'node:dns';
import mongoose from 'mongoose';
import { env } from './env.js';

mongoose.set('sanitizeFilter', true);
mongoose.connection.on('error', (error) => {
  console.error('MongoDB connection error:', error);
});

export async function connectDB() {
  try {
    if (env.NODE_ENV !== 'production' && env.MONGODB_DNS_SERVERS.length > 0) {
      dns.setServers(env.MONGODB_DNS_SERVERS);
    } else if (env.NODE_ENV === 'production' && env.MONGODB_DNS_SERVERS.length > 0) {
      console.warn('Ignoring MONGODB_DNS_SERVERS in production; using the platform DNS resolver.');
    }

    await mongoose.connect(env.MONGODB_URI, {
      dbName: env.MONGODB_DB,
      serverSelectionTimeoutMS: 5000,
    });
    console.log(`MongoDB connected to ${env.MONGODB_DB}`);
    return mongoose.connection;
  } catch (error) {
    console.error('MongoDB connection failed. Check DNS resolution, Atlas Network Access, and URL-encode special characters in the DB password.');
    console.error(error);
    throw error;
  }
}
