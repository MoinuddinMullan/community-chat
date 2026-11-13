import http from 'node:http';
import { Server } from 'socket.io';
import app from './app.js';
import { env } from './config/env.js';
import { connectDB } from './config/db.js';
import { attachSocketHandlers } from './sockets/index.js';
import { schedulePurgeJobs } from './jobs/purge.js';

const server = http.createServer(app);
const PORT = Number(process.env.PORT || env.PORT || 5000);
const HOST = '0.0.0.0';
const io = new Server(server, {
  transports: ['websocket'],
  allowEIO3: false,
  maxHttpBufferSize: 64 * 1024,
  cors: false,
});

app.set('io', io);
attachSocketHandlers(io);

server.on('error', (error) => {
  console.error('HTTP server failed to start:', error);
  process.exit(1);
});

async function start() {
  await connectDB();
  schedulePurgeJobs();
  server.listen(PORT, HOST, () => {
    console.log(`Server is running on port ${PORT}`);
  });
}

start().catch((error) => {
  console.error('Backend startup failed; shutting down.', error);
  process.exit(1);
});

export { app, io, server };
