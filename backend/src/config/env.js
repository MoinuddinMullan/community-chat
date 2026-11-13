import 'dotenv/config';
import { z } from 'zod';

const envSchema = z.object({
  PORT: z.coerce.number().default(4000),
  NODE_ENV: z.enum(['development', 'production', 'test']).default(
    process.env.RENDER === 'true' ? 'production' : 'development',
  ),
  MONGODB_URI: z.string().min(1),
  MONGODB_DB: z.string().min(1).default('community_chat'),
  MONGODB_DNS_SERVERS: z.string().default('').transform((value) => value.split(',').map((server) => server.trim()).filter(Boolean)),
  CORS_ALLOWED_ORIGINS: z.string().default('').transform((value) => value.split(',').map((origin) => origin.trim()).filter(Boolean)),
  JWT_ACCESS_SECRET: z.string().min(32),
  JWT_REFRESH_SECRET: z.string().min(32),
  ACCESS_TOKEN_MINUTES: z.coerce.number().default(15),
  REFRESH_TOKEN_DAYS: z.coerce.number().default(30),
  CHAT_VISIBLE_DAYS: z.coerce.number().default(7),
  DB_PURGE_DAYS: z.coerce.number().default(10.5),
  MAX_IMAGE_BYTES: z.coerce.number().default(5_242_880),
  TRUST_PROXY: z.coerce.number().default(0),
});

let parsed;
try {
  parsed = envSchema.parse(process.env);
} catch (error) {
  console.error('Environment validation failed. Check backend/.env and fix the values.');
  console.error(error.issues?.map((issue) => `${issue.path.join('.') || 'value'}: ${issue.message}`).join('\n') ?? error.message);
  process.exit(1);
}

if (!parsed.MONGODB_URI || parsed.MONGODB_URI.includes('PASTE_YOUR_MONGODB_ATLAS_URI_HERE')) {
  console.error('Open backend/.env and paste your MongoDB Atlas connection string.');
  process.exit(1);
}

export const env = parsed;
