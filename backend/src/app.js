import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { env } from './config/env.js';
import authRoutes from './routes/auth.js';
import userRoutes from './routes/users.js';
import requestRoutes from './routes/requests.js';
import contactRoutes from './routes/contacts.js';
import chatRoutes from './routes/chats.js';
import mediaRoutes from './routes/media.js';
import { notFoundHandler, errorHandler } from './middleware/errorHandler.js';
import { globalLimiter } from './middleware/rateLimits.js';

const app = express();
const localDevelopmentOrigin = /^http:\/\/(?:localhost|127\.0\.0\.1|\[::1\])(?::\d+)?$/;

app.set('trust proxy', Number(env.TRUST_PROXY || 0));
app.disable('x-powered-by');
app.use(helmet({ crossOriginResourcePolicy: false, contentSecurityPolicy: false }));
app.use(cors({
  origin(origin, callback) {
    if (!origin) return callback(null, false);
    const allowed = env.CORS_ALLOWED_ORIGINS.includes(origin)
      || (env.NODE_ENV === 'development' && localDevelopmentOrigin.test(origin));
    callback(null, allowed);
  },
  methods: ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Image-Content-Type'],
}));
app.use(globalLimiter);
app.use((req, res, next) => {
  res.setHeader('Cache-Control', 'no-store');
  next();
});

app.use(express.json({ limit: '16kb' }));
app.use(express.urlencoded({ extended: false }));
app.use('/api/chats', express.raw({ type: 'application/octet-stream', limit: '2mb' }));
app.use('/api/media', express.raw({ type: 'application/octet-stream', limit: env.MAX_IMAGE_BYTES }));
app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/requests', requestRoutes);
app.use('/api/contacts', contactRoutes);
app.use('/api/chats', chatRoutes);
app.use('/api/media', mediaRoutes);

app.get('/', (req, res) => {
  res.json({
    status: 'active',
    message: 'Community Chat API is running',
  });
});

app.get('/health', (req, res) => {
  res.json({ ok: true, status: 'healthy' });
});

app.use(notFoundHandler);
app.use(errorHandler);

export default app;
