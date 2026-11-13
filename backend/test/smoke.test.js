import test from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { MongoMemoryServer } from 'mongodb-memory-server';
import mongoose from 'mongoose';
import bcrypt from 'bcryptjs';

const testEnv = {
  PORT: '4001',
  NODE_ENV: 'test',
  MONGODB_URI: 'mongodb://localhost:27017/community_chat_test',
  MONGODB_DB: 'community_chat_test',
  CORS_ALLOWED_ORIGINS: 'http://localhost:5000',
  JWT_ACCESS_SECRET: 'a'.repeat(64),
  JWT_REFRESH_SECRET: 'b'.repeat(64),
  ACCESS_TOKEN_MINUTES: '15',
  REFRESH_TOKEN_DAYS: '30',
  CHAT_VISIBLE_DAYS: '7',
  DB_PURGE_DAYS: '10.5',
  MAX_IMAGE_BYTES: '5242880',
  TRUST_PROXY: '0',
};

Object.assign(process.env, testEnv);

await import('../src/config/db.js');
const { default: app } = await import('../src/app.js');
const Message = (await import('../src/models/Message.js')).default;
const Media = (await import('../src/models/Media.js')).default;
const Session = (await import('../src/models/Session.js')).default;
const User = (await import('../src/models/User.js')).default;
const { purgeExpiredRecords } = await import('../src/jobs/purge.js');

let mongoServer;

test.before(async () => {
  mongoServer = await MongoMemoryServer.create();
  await mongoose.connect(mongoServer.getUri(), { dbName: 'community_chat_test' });
});

test.after(async () => {
  await mongoose.disconnect();
  await mongoServer.stop();
});

test('health endpoint returns ok', async () => {
  const res = await request(app).get('/health');
  assert.equal(res.status, 200);
  assert.equal(res.body.ok, true);
});

test('root endpoint returns an API status message', async () => {
  const res = await request(app).get('/');
  assert.equal(res.status, 200);
  assert.deepEqual(res.body, {
    status: 'active',
    message: 'Community Chat API is running',
  });
});

test('allows configured web origins to preflight API requests', async () => {
  const res = await request(app)
    .options('/api/auth/login')
    .set('Origin', 'http://localhost:5000')
    .set('Access-Control-Request-Method', 'POST')
    .set('Access-Control-Request-Headers', 'content-type,authorization');

  assert.equal(res.status, 204);
  assert.equal(res.headers['access-control-allow-origin'], 'http://localhost:5000');
});

test('register + login works', async () => {
  const registerPayload = {
    userId: 'flat402_aisha',
    password: '1234',
    publicKey: 'test-public-key-1234567890',
  };

  const registerRes = await request(app).post('/api/auth/register').send(registerPayload);
  assert.equal(registerRes.status, 201);
  assert.ok(registerRes.body.accessToken);
  assert.equal(registerRes.body.me.displayName, 'flat402_aisha');

  const loginRes = await request(app).post('/api/auth/login').send({ userId: 'flat402_aisha', password: '1234' });
  assert.equal(loginRes.status, 200);
  assert.ok(loginRes.body.accessToken);
  assert.equal(loginRes.body.requiresPinSetup, false);
});

test('registration normalizes mixed-case user IDs to lowercase', async () => {
  const res = await request(app).post('/api/auth/register').send({
    userId: 'Moin',
    password: '5678',
  });

  assert.equal(res.status, 201);
  assert.equal(res.body.me.userId, 'moin');
  assert.equal(res.body.me.displayName, 'moin');
});

test('registration requires a four-digit PIN and legacy users can upgrade after login', async () => {
  const invalidRegistration = await request(app)
    .post('/api/auth/register')
    .send({ userId: 'invalid_pin', password: 'Password123' });
  assert.equal(invalidRegistration.status, 400);

  const legacyUser = await User.create({
    userId: 'legacy_user',
    displayName: 'Old display name',
    passwordHash: await bcrypt.hash('OldPassword123', 12),
  });
  const legacyLogin = await request(app)
    .post('/api/auth/login')
    .send({ userId: legacyUser.userId, password: 'OldPassword123' });
  assert.equal(legacyLogin.status, 200);
  assert.equal(legacyLogin.body.requiresPinSetup, true);
  assert.equal(legacyLogin.body.me.displayName, legacyUser.userId);

  const setPin = await request(app)
    .post('/api/auth/pin')
    .set('Authorization', `Bearer ${legacyLogin.body.accessToken}`)
    .send({ pin: '2468' });
  assert.equal(setPin.status, 200);

  const upgradedLogin = await request(app)
    .post('/api/auth/login')
    .send({ userId: legacyUser.userId, password: '2468' });
  assert.equal(upgradedLogin.status, 200);
  assert.equal(upgradedLogin.body.requiresPinSetup, false);
});

test('users can search for a neighbour, send a request, and accept it to create a chat', async () => {
  const aishaLogin = await request(app)
    .post('/api/auth/login')
    .send({ userId: 'flat402_aisha', password: '1234' });
  const moinLogin = await request(app)
    .post('/api/auth/login')
    .send({ userId: 'moin', password: '5678' });
  const aishaAuth = { Authorization: `Bearer ${aishaLogin.body.accessToken}` };
  const moinAuth = { Authorization: `Bearer ${moinLogin.body.accessToken}` };
  const aishaPublicKey = Buffer.alloc(32, 0x11).toString('base64');
  const moinPublicKey = Buffer.alloc(32, 0x22).toString('base64');
  const aishaKeyUpdate = await request(app)
    .put('/api/users/me/public-key')
    .set(aishaAuth)
    .send({ publicKey: aishaPublicKey });
  assert.equal(aishaKeyUpdate.status, 200);
  const moinKeyUpdate = await request(app)
    .put('/api/users/me/public-key')
    .set(moinAuth)
    .send({ publicKey: moinPublicKey });
  assert.equal(moinKeyUpdate.status, 200);

  const search = await request(app)
    .get('/api/users/search')
    .set(aishaAuth)
    .query({ userId: 'MOIN' });
  assert.equal(search.status, 200);
  assert.equal(search.body.userId, 'moin');

  const sentRequest = await request(app)
    .post('/api/requests')
    .set(aishaAuth)
    .send({ toUserId: search.body.userId });
  assert.equal(sentRequest.status, 201);

  const requests = await request(app).get('/api/requests').set(moinAuth);
  assert.equal(requests.body.incoming[0].id, sentRequest.body.id);

  const accepted = await request(app)
    .post(`/api/requests/${sentRequest.body.id}/accept`)
    .set(moinAuth);
  assert.equal(accepted.status, 200);

  const chats = await request(app).get('/api/chats').set(aishaAuth);
  assert.equal(chats.status, 200);
  assert.equal(chats.body[0].peer.userId, 'moin');
  assert.equal(chats.body[0].peer.publicKey, moinPublicKey);

  const emitted = [];
  const aishaUserId = JSON.parse(
    Buffer.from(aishaLogin.body.accessToken.split('.')[1], 'base64url'),
  ).sub;
  app.set('io', {
    to(room) {
      return {
        emit(event, payload) {
          emitted.push({ room, event, payload });
        },
      };
    },
  });
  const sentMessage = await request(app)
    .post(`/api/chats/${chats.body[0].chatId}/messages`)
    .set(aishaAuth)
    .send({ type: 'text', payload: 'enc1:ZW5jcnlwdGVk', clientId: 'test-message-1' });

  assert.equal(sentMessage.status, 201);
  assert.equal(sentMessage.body.message.payload, 'enc1:ZW5jcnlwdGVk');
  assert.equal(sentMessage.body.message.sender, aishaUserId);
  assert.equal(sentMessage.body.message.senderId, sentMessage.body.message.sender);
  assert.equal(sentMessage.body.message.clientId, 'test-message-1');
  assert.equal(emitted.length, 2);
  assert.equal(new Set(emitted.map(({ room }) => room)).size, 2);
  assert.ok(emitted.every(({ event, payload }) =>
    event === 'chat:message'
      && payload.message.id === sentMessage.body.message.id
      && payload.message.senderId === sentMessage.body.message.senderId));

  const imageBytes = Buffer.alloc(64, 0x5a);
  const uploaded = await request(app)
    .post(`/api/media/${chats.body[0].chatId}/upload`)
    .set(aishaAuth)
    .set('Content-Type', 'application/octet-stream')
    .set('X-Image-Content-Type', 'application/octet-stream')
    .send(imageBytes);
  assert.equal(uploaded.status, 201);
  assert.equal(uploaded.body.imageUrl, `/api/media/${uploaded.body.mediaId}`);

  const plaintextTextRejected = await request(app)
    .post(`/api/chats/${chats.body[0].chatId}/messages`)
    .set(aishaAuth)
    .send({ type: 'text', payload: 'plain text', clientId: 'plain-text-test' });
  assert.equal(plaintextTextRejected.status, 400);
  const plaintextCaptionRejected = await request(app)
    .post(`/api/chats/${chats.body[0].chatId}/messages`)
    .set(aishaAuth)
    .send({
      type: 'image',
      imageUrl: uploaded.body.imageUrl,
      caption: 'plain caption',
      clientId: 'plain-caption-test',
    });
  assert.equal(plaintextCaptionRejected.status, 400);

  const imageMessage = await request(app)
    .post(`/api/chats/${chats.body[0].chatId}/messages`)
    .set(aishaAuth)
    .send({
      type: 'image',
      imageUrl: uploaded.body.imageUrl,
      caption: 'enc1:Q29tbXVuaXR5IHBob3Rv',
      clientId: 'test-image-1',
    });
  assert.equal(imageMessage.status, 201);
  assert.equal(imageMessage.body.message.type, 'image');
  assert.equal(imageMessage.body.message.caption, 'enc1:Q29tbXVuaXR5IHBob3Rv');

  const retriedImageMessage = await request(app)
    .post(`/api/chats/${chats.body[0].chatId}/messages`)
    .set(aishaAuth)
    .send({
      type: 'image',
      imageUrl: uploaded.body.imageUrl,
      caption: 'enc1:Q29tbXVuaXR5IHBob3Rv',
      clientId: 'test-image-1',
    });
  assert.equal(retriedImageMessage.status, 200);
  assert.equal(retriedImageMessage.body.message.id, imageMessage.body.message.id);

  const conflictingRetry = await request(app)
    .post(`/api/chats/${chats.body[0].chatId}/messages`)
    .set(aishaAuth)
    .send({
      type: 'image',
      imageUrl: uploaded.body.imageUrl,
      caption: 'enc1:RGlmZmVyZW50IGNhcHRpb24',
      clientId: 'test-image-1',
    });
  assert.equal(conflictingRetry.status, 409);

  const history = await request(app)
    .get(`/api/chats/${chats.body[0].chatId}/messages`)
    .set(moinAuth);
  assert.equal(history.body.filter((message) => message.clientId === 'test-image-1').length, 1);
  const deliveredImage = history.body.find((message) => message.clientId === 'test-image-1');
  assert.equal(deliveredImage.imageUrl, uploaded.body.imageUrl);
  assert.equal(deliveredImage.senderId, sentMessage.body.message.senderId);

  const downloaded = await request(app)
    .get(uploaded.body.imageUrl)
    .set(moinAuth);
  assert.equal(downloaded.status, 200);
  assert.equal(downloaded.headers['content-type'], 'application/octet-stream');
  assert.deepEqual(downloaded.body, imageBytes);
  assert.equal(emitted.length, 6);
  assert.ok(emitted.some(({ payload }) => payload.message.type === 'image'));

  const expiredAt = new Date(Date.now() - 1000);
  const purgeAt = new Date(Date.now() + 86400000);
  const expiredMedia = await Media.create({
    chat: chats.body[0].chatId,
    uploader: aishaUserId,
    data: imageBytes,
    size: imageBytes.length,
    contentType: 'image/jpeg',
    expiresAt: expiredAt,
    purgeAt,
  });
  await Message.create({
    chat: chats.body[0].chatId,
    sender: aishaUserId,
    type: 'image',
    media: expiredMedia._id,
    expiresAt: expiredAt,
    purgeAt,
  });
  const visibleHistory = await request(app)
    .get(`/api/chats/${chats.body[0].chatId}/messages`)
    .set(moinAuth);
  assert.ok(visibleHistory.body.every((message) => message.id !== expiredMedia._id.toString()));
  const expiredDownload = await request(app)
    .get(`/api/media/${expiredMedia._id}`)
    .set(moinAuth);
  assert.equal(expiredDownload.status, 404);

  const futureExpiry = new Date(Date.now() + 86400000);
  const laterPurge = new Date(Date.now() + 2 * 86400000);
  await Message.insertMany(
    Array.from({ length: 35 }, (_, index) => ({
      chat: chats.body[0].chatId,
      sender: aishaUserId,
      type: 'text',
      payload: `history-${index}`,
      createdAt: new Date(Date.now() - 60000 + index),
      expiresAt: futureExpiry,
      purgeAt: laterPurge,
    })),
  );
  const firstPage = await request(app)
    .get(`/api/chats/${chats.body[0].chatId}/messages`)
    .set(moinAuth)
    .query({ limit: 30 });
  assert.equal(firstPage.body.length, 30);
  const secondPage = await request(app)
    .get(`/api/chats/${chats.body[0].chatId}/messages`)
    .set(moinAuth)
    .query({ limit: 30, before: firstPage.body[0].id });
  assert.equal(secondPage.body.length, 7);
  assert.ok(
    firstPage.body.every(
      (message) => !secondPage.body.some((older) => older.id === message.id),
    ),
  );

  const invalidImage = await request(app)
    .post(`/api/media/${chats.body[0].chatId}/upload`)
    .set(aishaAuth)
    .set('Content-Type', 'application/octet-stream')
    .set('X-Image-Content-Type', 'application/octet-stream')
    .send(Buffer.from('not an image'));
  assert.equal(invalidImage.status, 400);

  const forbiddenDownload = await request(app).get(uploaded.body.imageUrl);
  assert.equal(forbiddenDownload.status, 401);

  const deniedDelete = await request(app)
    .delete(`/api/chats/${chats.body[0].chatId}/messages/${sentMessage.body.message.id}`)
    .set(moinAuth);
  assert.equal(deniedDelete.status, 404);

  const deletedText = await request(app)
    .delete(`/api/chats/${chats.body[0].chatId}/messages/${sentMessage.body.message.id}`)
    .set(aishaAuth);
  assert.equal(deletedText.status, 200);

  const deletedImage = await request(app)
    .delete(`/api/chats/${chats.body[0].chatId}/messages/${imageMessage.body.message.id}`)
    .set(aishaAuth);
  assert.equal(deletedImage.status, 200);
  const deletedImageDownload = await request(app)
    .get(uploaded.body.imageUrl)
    .set(moinAuth);
  assert.equal(deletedImageDownload.status, 404);

  const clearUpload = await request(app)
    .post(`/api/media/${chats.body[0].chatId}/upload`)
    .set(aishaAuth)
    .set('Content-Type', 'application/octet-stream')
    .set('X-Image-Content-Type', 'application/octet-stream')
    .send(imageBytes);
  assert.equal(clearUpload.status, 201);
  const clearImageMessage = await request(app)
    .post(`/api/chats/${chats.body[0].chatId}/messages`)
    .set(aishaAuth)
    .send({
      type: 'image',
      imageUrl: clearUpload.body.imageUrl,
      caption: 'enc1:UmVtb3ZlIGFsbA',
      clientId: 'test-clear-image',
    });
  assert.equal(clearImageMessage.status, 201);
  const clearChat = await request(app)
    .delete(`/api/chats/${chats.body[0].chatId}/messages`)
    .set(moinAuth);
  assert.equal(clearChat.status, 200);
  const clearedHistory = await request(app)
    .get(`/api/chats/${chats.body[0].chatId}/messages`)
    .set(aishaAuth);
  assert.deepEqual(clearedHistory.body, []);
  const clearedImageDownload = await request(app)
    .get(clearUpload.body.imageUrl)
    .set(moinAuth);
  assert.equal(clearedImageDownload.status, 404);
  assert.ok(emitted.some(({ event }) => event === 'chat:message_deleted'));
  assert.ok(emitted.some(({ event }) => event === 'chat:cleared'));
  assert.equal(emitted.length, 14);
  app.set('io', undefined);
});

test('purges expired messages, media, and sessions with filter sanitization enabled', async () => {
  const now = new Date();
  const expiredAt = new Date(now.getTime() - 1000);
  const futureAt = new Date(now.getTime() + 86400000);
  const user = new mongoose.Types.ObjectId();
  const chat = new mongoose.Types.ObjectId();

  await Promise.all([
    Message.create([
      { chat, sender: user, expiresAt: expiredAt, purgeAt: expiredAt },
      { chat, sender: user, expiresAt: futureAt, purgeAt: futureAt },
    ]),
    Media.create([
      { chat, uploader: user, expiresAt: expiredAt, purgeAt: expiredAt },
      { chat, uploader: user, expiresAt: futureAt, purgeAt: futureAt },
    ]),
    Session.create([
      { user, tokenHash: 'expired', expiresAt: expiredAt },
      { user, tokenHash: 'future', expiresAt: futureAt },
    ]),
  ]);

  await purgeExpiredRecords(now);

  assert.equal(await Message.countDocuments({ chat }), 1);
  assert.equal(await Media.countDocuments({ chat }), 1);
  assert.equal(await Session.countDocuments({ user }), 1);
});
