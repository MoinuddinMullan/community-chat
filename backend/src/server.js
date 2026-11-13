import http from 'node:http';
import { Server } from 'socket.io';
import app from './app.js';
import { env } from './config/env.js';
import { connectDB } from './config/db.js';
import { attachSocketHandlers } from './sockets/index.js';
import { schedulePurgeJobs } from './jobs/purge.js';

const server = http.createServer(app);
const io = new Server(server, {
  transports: ['websocket'],
  allowEIO3: false,
  maxHttpBufferSize: 64 * 1024,
  cors: false,
});

app.set('io', io);
attachSocketHandlers(io);

async function start() {
  await connectDB();
  schedulePurgeJobs();
  server.listen(env.PORT, () => {
    console.log(`Community Chat backend listening on http://localhost:${env.PORT}`);
  });
}

start().catch((error) => {
  console.error('Failed to start server.');
  console.error(error.message);
  process.exit(1);
});

export { app, io, server };
