import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';

export function attachSocketHandlers(io) {
  io.use((socket, next) => {
    const token = socket.handshake.auth?.token;
    if (!token) return next(new Error('Authentication required.'));

    try {
      const decoded = jwt.verify(token, env.JWT_ACCESS_SECRET, { algorithms: ['HS256'] });
      socket.user = decoded;
      next();
    } catch (error) {
      next(new Error('Unauthorized socket connection.'));
    }
  });

  io.on('connection', (socket) => {
    socket.join(`user:${socket.user.sub}`);
    socket.on('disconnect', () => {});
  });
}
