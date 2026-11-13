# PROJECT: "Community Chat" — a private, end-to-end encrypted, WhatsApp-style chat app for a housing community

## 0. HOW TO WORK
You are a senior full-stack engineer and security-focused mobile architect. Build this project completely from scratch inside the currently open, empty workspace folder (the project root). Create every folder and every file, install every dependency, and verify everything works, so that afterwards I only have to: (1) paste my MongoDB Atlas connection string into `backend/.env`, (2) start the backend, (3) run the Flutter app.

- First save this entire specification verbatim as `SPEC.md` in the project root, and re-read it at the start of every phase.
- Write a short implementation plan, then execute it phase by phase: backend → backend tests → Flutter core (crypto, API, auth) → Flutter UI → platform config → verification → README. Do not stop to ask me questions; when something is ambiguous, choose the safest and simplest option and record the decision in README.md.
- Deliver complete, working, production-quality code. No TODOs, placeholders, pseudo-code or "implement later" stubs.
- First check that `node -v` (20+) and `flutter --version` work. If a tool is missing, tell me exactly what to install and keep building whatever is still possible.
- Never hard-code package versions. Add dependencies with `npm install <pkg>` and `flutter pub add <pkg>` so the latest compatible versions resolve. Keep dependencies minimal (small APK, quick install). No analytics, ads, crash reporters or trackers, and no network calls except to our own backend.
- Never leave a long-running process (dev server, `flutter run`) blocking the terminal. Start servers only briefly for checks and stop them afterwards. Do not run `flutter run`.
- The look and layout should feel like WhatsApp, but do not use WhatsApp's name, logo or assets. The app is called "Community Chat" (keep the name in one constant so it is easy to rename).
- Out of scope for v1: push notifications, groups, voice/video calls, stickers/status, multi-device sync.

## 1. ARCHITECTURE (fixed, do not substitute)
Flutter app  <-- HTTPS REST + WebSocket (Socket.IO) -->  Node.js backend  <-->  MongoDB Atlas

- The Flutter app must NEVER connect to MongoDB directly and must never contain the MongoDB URI or any server secret (anything inside an APK can be extracted). The URI lives only in `backend/.env`.
- No Firebase and no Google Cloud services anywhere.
- Backend: Node.js 20+, plain JavaScript with ES modules (no TypeScript, no build step), Express 4 (`express@4`), Mongoose, Socket.IO, zod, helmet, express-rate-limit, bcryptjs (pure JS, installs everywhere), jsonwebtoken, dotenv, node-cron. Dev dependencies: supertest, mongodb-memory-server. Scripts: `npm start`, `npm run dev` (uses `node --watch`), `npm test`.
- Mobile: Flutter (latest stable). Android is the primary target; iOS must also compile. Packages: provider (ChangeNotifier state), dio, socket_io_client, cryptography, cryptography_flutter, flutter_secure_storage, image_picker, flutter_image_compress, intl, uuid. Plain Navigator, no code generation (no build_runner).

## 2. REPOSITORY LAYOUT (create exactly this)
<project root>/
  SPEC.md
  README.md
  .gitignore
  backend/
    package.json                 (type: module)
    .env                         (create now, see 5.1; I will paste MONGODB_URI later)
    .env.example
    .gitignore                   (must ignore .env and node_modules)
    scripts/reset-password.js
    src/
      server.js  app.js
      config/      env.js  db.js
      models/      User.js  Session.js  Connection.js  Chat.js  Message.js  Media.js
      middleware/  auth.js  validate.js  rateLimits.js  errorHandler.js  asyncHandler.js
      routes/      auth.js  users.js  requests.js  contacts.js  chats.js  media.js
      sockets/     index.js
      jobs/        purge.js
      utils/       tokens.js  dto.js
    test/          smoke.test.js
  mobile/          (create with: flutter create --org com.community --project-name community_chat --platforms=android,ios mobile)
    lib/
      main.dart  app.dart
      core/        config.dart  theme.dart  strings.dart  format.dart
      models/      (user, contact, chat_summary, message, connection_request)
      services/    api_client.dart  auth_service.dart  crypto_service.dart  secure_store.dart  socket_service.dart  image_pipeline.dart  media_cache.dart
      providers/   auth_provider.dart  chats_provider.dart  requests_provider.dart  chat_room_provider.dart
      screens/     auth/  home/  find_person/  chat/  settings/
      widgets/     (avatar, message_bubble, empty_state, big_button, ...)
    test/          crypto_test.dart

## 3. PRODUCT REQUIREMENTS

### 3.1 Look & feel: WhatsApp-style and elderly-friendly
- Structure like WhatsApp: teal app bar (#075E54, white text), tabs CHATS | REQUESTS, round green floating button (#25D366), chat list with round letter avatars, chat screen with beige wallpaper (#ECE5DD), green outgoing bubbles (#DCF8C6), white incoming bubbles, time + ticks inside bubbles, rounded input bar with a round green send button. Light theme only.
- Elderly-friendly: message text 18, list titles 18–20 bold, secondary text never below 14, tap targets at least 52 dp, high contrast, plain-language labels ("Find a neighbour", "Send photo", "Take photo"), icon + text on primary buttons, show/hide eye on password fields, large Yes/No dialogs before anything destructive, one clear primary action per screen, friendly empty states, human-readable error messages (never raw exceptions), a "No internet connection" banner when offline, and no overflow at 130% system font size. All UI strings live in `core/strings.dart`.

### 3.2 Accounts & discovery (no phone number, no email)
- Register with one unique User ID and a four-digit numeric PIN. The User ID is also the display name; no invite code is required.
- User ID: 3–20 characters, lowercase letters, digits, `_` and `.`; stored lowercase, case-insensitively unique. PIN: exactly four digits.
- Remember the last account locally, but require its PIN at every cold app launch. Keep access and refresh tokens in memory only; logging out forgets the remembered account.
- Existing accounts with an old password can use it once to migrate to a four-digit PIN. New registrations and subsequent sign-ins use the PIN.
- Search by EXACT User ID only. No partial search, no user lists or browsing anywhere. A result shows only display name, User ID and relationship status.

### 3.3 Contact requests (Instagram-style approval, no followers)
- Search → "Send request" → the other person sees it under REQUESTS → Accept or Decline. A chat exists, and messaging is allowed, only after Accept. Then both see each other under CHATS.
- The sender can cancel a pending request. A declined request cannot be re-sent for 24 hours. A pair of users has at most one Connection record; if the other person already sent me a request, tell me to accept it instead of creating a second one.
- Remove contact: deletes the chat and everything in it for both people. Block: blocked users can't send requests or messages; Settings → "Blocked people" allows unblocking.

### 3.4 Chat
- Real-time text chat: messages are sent over REST and delivered live to the other person over Socket.IO. Optimistic UI (clock icon while sending, ✓ once stored on the server, blue ✓✓ when read), retry on failure, unread badge, date separators ("Today", "Yesterday"), load older messages when scrolling up (30 per page), re-sync chats and requests on app resume and after socket reconnect. Max 2,000 characters per message. Sends are idempotent via a client-generated `clientId`.

### 3.5 Photos
- The chat input bar has a gallery button and a camera button → pick → preview screen with big "Send" / "Cancel" → send.
- Pipeline: pick → read bytes into memory → downscale so the longest side ≤ 1280 px, JPEG quality 80 (with picker metadata stripping) → keep the encrypted payload within the 5 MB `MAX_IMAGE_BYTES` cap → encrypt on the device → upload the encrypted bytes. The server never sees the picture.
- HARD RULES: photos sent or received MUST NEVER be saved to the phone's gallery/Photos or any shared/public storage, and decrypted image bytes MUST NEVER be written to disk (even temporarily) except in memory and only for the active viewer. The app must never leave unencrypted image data in any cache or file. If the process is killed, it is lost; this is acceptable. The server only stores encrypted bytes with TTL expiry.

### 3.6 Auto-expiry
- Each message and photo has `expiresAt = createdAt + 7 days` and `purgeAt = createdAt + 10.5 days`.
- After `expiresAt`: the server stops returning the message/photo from every endpoint (including media download) and the app removes it from the UI, including live while a chat is open (re-check every minute and on resume).
- At `purgeAt` (1.5 weeks): MongoDB physically deletes it via a TTL index on `purgeAt` (`expireAfterSeconds: 0`) on both `messages` and `media`. Safety net: a node-cron job at startup and every hour runs `deleteMany({ purgeAt: { $lte: now } })` on both collections and removes expired sessions.
- Durations come from `.env` (`CHAT_VISIBLE_DAYS=7`, `DB_PURGE_DAYS=10.5`). Only messages and photos are purged; accounts and contacts stay.

### 3.7 Manual deletion
- Chat menu → "Clear chat": a confirmation explains it permanently deletes all messages and photos for BOTH people, immediately and from the database; the other person's app updates live.
- Long-press my own message → "Delete for everyone" (hard delete including its media).
- Settings → "Delete all my chats" (same warning: it also clears them for the other people).

## 4. DATA MODEL (Mongoose; database name from MONGODB_DB, default `community_chat`)
- User: userId (unique, lowercase), displayName (same as userId for new/updated accounts), passwordHash (PIN hash), pinConfigured, publicKey (base64 X25519, 32 bytes), publicKeyUpdatedAt, failedLogins, lockUntil, createdAt.
- Session: user, tokenHash (SHA-256 of the refresh token), used (bool), expiresAt (TTL index), createdAt.
- Connection: pairKey (unique; the two user _ids sorted and joined), requester, recipient, status (pending | accepted | declined | blocked), blockedBy, createdAt, respondedAt.
- Chat: pairKey (unique), participants (2 user refs), createdAt.
- Message: chat, sender, type (text | image), payload (base64 ciphertext, text only), media (ref, image only), clientId, readAt, createdAt, expiresAt, purgeAt. Indexes: {chat, createdAt:-1}; unique partial {chat, sender, clientId}; TTL on purgeAt.
- Media: chat, uploader, data (Buffer, `select: false`), size, createdAt, expiresAt, purgeAt (TTL).
- On startup call `init()`/`syncIndexes()` on every model so the TTL indexes definitely exist, and log that they are active.

## 5. BACKEND

### 5.1 backend/.env (create it now with every key)
Generate JWT_ACCESS_SECRET and JWT_REFRESH_SECRET yourself (64 random bytes each, hex, via Node's crypto) and write the real values. Leave MONGODB_URI as an obvious placeholder:
  PORT=4000
  NODE_ENV=development
  MONGODB_URI=PASTE_YOUR_MONGODB_ATLAS_URI_HERE
  MONGODB_DB=community_chat
  JWT_ACCESS_SECRET=<generated>
  JWT_REFRESH_SECRET=<generated>
  ACCESS_TOKEN_MINUTES=15
  REFRESH_TOKEN_DAYS=30
  CHAT_VISIBLE_DAYS=7
  DB_PURGE_DAYS=10.5
  MAX_IMAGE_BYTES=2097152
  TRUST_PROXY=0
`config/env.js` validates everything with zod at startup. If MONGODB_URI is missing or still the placeholder, print a clear friendly message ("Open backend/.env and paste your MongoDB Atlas connection string") and exit. If the DB connection fails, print a friendly hint about Atlas → Network Access (IP allow-list) and URL-encoding special characters in the DB password (use a short serverSelectionTimeoutMS so errors appear quickly). Also create `.env.example` with no secrets.

### 5.2 API (all under /api; JSON; every route except register/login/refresh needs `Authorization: Bearer <accessToken>`)
Auth
- POST /auth/register {userId, password: four-digit PIN, publicKey}; displayName is set to userId
- POST /auth/login {userId, password} → {accessToken, refreshToken, requiresPinSetup, me:{userId, displayName, publicKey}}
- POST /auth/pin {pin} (authenticated; migrates an existing account's old password to a four-digit PIN)
- POST /auth/refresh {refreshToken} → new token pair (rotation; reuse of an already-used refresh token revokes ALL of that user's sessions)
- POST /auth/logout {refreshToken}
Users
- GET /users/me ; PATCH /users/me {displayName} ; PUT /users/me/public-key {publicKey} (sets publicKeyUpdatedAt, emits `contact:key-changed` to contacts)
- GET /users/search?userId=<exact>
Requests & contacts
- POST /requests {toUserId} ; GET /requests → {incoming, outgoing}
- POST /requests/:id/accept ; POST /requests/:id/decline ; DELETE /requests/:id (cancel)
- GET /contacts → [{userId, displayName, publicKey, publicKeyUpdatedAt, chatId}]
- DELETE /contacts/:userId (remove + delete all chat data) ; POST /contacts/:userId/block
- GET /blocked ; DELETE /blocked/:userId (unblock)
Chats
- GET /chats → [{chatId, peer:{userId, displayName, publicKey}, lastMessage|null (latest non-expired DTO), unreadCount}]
- GET /chats/:chatId/messages?limit=30&before=<messageId>
- POST /chats/:chatId/messages {type:"text", payload:"enc1:<base64 ciphertext>", clientId}; image captions use the same encrypted marker
- POST /media/:chatId/upload: raw body `application/octet-stream` (encrypted image bytes), header `X-Image-Content-Type: application/octet-stream`; returns a media URL for the image message
- POST /chats/:chatId/messages {type:"image", imageUrl, caption?, clientId}
- GET /media/:mediaId → raw encrypted bytes
- POST /chats/:chatId/read (marks the peer's messages read, emits `message:read`)
- DELETE /chats/:chatId/messages (clear chat for both) ; DELETE /chats/:chatId/messages/:messageId (own messages only)
- DELETE /me/messages (clear all my chats)
Message DTO: {id, chatId, sender, type, payload|null, imageUrl|null, encrypted caption|null, mediaId|null, createdAt, expiresAt, readAt|null}

Rules that apply everywhere:
- Identify users externally ONLY by their `userId` handle; never expose users' Mongo `_id`s.
- Every chat/message/media route must verify the caller is a participant of the chat AND that the Connection is `accepted`; otherwise answer 404 (not 403). A third user must never be able to read messages or download media of other people (prevent IDOR). The sender always comes from the JWT, never from the request body. Expired items are never returned or served. Public keys are returned only for accepted contacts.

### 5.3 Socket.IO
- `http.createServer(app)` + Socket.IO with `transports: ['websocket']`, `maxHttpBufferSize` 64 KB, no CORS. Verify the JWT in the handshake (`auth.token`) and reject otherwise; each socket joins room `user:<id>`.
- Server → client events only: `message:new`, `message:read`, `message:deleted`, `chat:cleared`, `request:new`, `request:accepted`, `contact:removed`, `contact:key-changed`. Ignore every client-emitted event. Image bytes never travel over sockets. When an access token expires, disconnect; the client reconnects with a refreshed token.

### 5.4 Hardening (all mandatory)
- helmet; `x-powered-by` disabled; NO CORS (a mobile app doesn't need it); `Cache-Control: no-store` on all API responses; in production enforce HTTPS (respect TRUST_PROXY) and HSTS.
- Rate limits: global per IP; login 10 per 15 min per IP; register 5 per hour per IP; search 20 per minute per user; send message 60 per minute per user; image upload 20 per minute per user.
- Body limits: JSON 16 KB; raw body only on the image route with MAX_IMAGE_BYTES; reject blobs smaller than 29 bytes (12-byte nonce + 16-byte tag + 1).
- Validate every input with strict zod schemas (reject unknown fields) and validate ObjectIds. Use `mongoose.set('sanitizeFilter', true)`. Never build queries from raw request objects.
- PINs: bcryptjs cost 12. Four-digit PINs have limited entropy, so apply the login limit of 10 attempts per IP per 15 minutes and lock an account for 15 minutes after 5 failed attempts. Return the same generic error for unknown user and wrong credential, and compare against a dummy hash when the user doesn't exist so timing doesn't reveal valid IDs.
- Access tokens: 15 minutes, HS256 with the algorithm pinned on verify. Refresh tokens: random 256-bit, stored only as SHA-256 hashes, rotated on every use, TTL-expiring.
- Central error handler: generic messages, no stack traces in production, consistent shape `{ error: { code, message } }`. Wrap async route handlers (Express 4).
- Never log request bodies, passwords, tokens or ciphertext. Minimal logging only.
- No endpoint lists users or returns other users' internal data.

### 5.5 scripts/reset-password.js
`node scripts/reset-password.js <userId> <newPin>`: an admin CLI (reads .env) that sets a new four-digit PIN hash, clears the lockout and deletes that user's sessions. There is no email/phone recovery, so this is how the admin helps residents who forget their PIN.

## 6. END-TO-END ENCRYPTION (client-side, `crypto_service.dart`)
- On registration (and on login if no local key exists for that User ID, or its public half differs from `me.publicKey`) generate an X25519 key pair. Store the private key ONLY in `flutter_secure_storage` (Android Keystore / iOS Keychain with a this-device-only accessibility option; no cloud backup), under a per-user key. Send only the public key (base64) to the server.
- Per-chat key: X25519 shared secret (my private, peer public) → HKDF-SHA256 (salt = utf8("community-chat-v1"), info = utf8(chatId), 32 bytes) → AES-256-GCM key.
- Every text message and every photo uses a fresh random 96-bit nonce. Layout: nonce ‖ ciphertext ‖ 16-byte tag (base64 for text, raw bytes for photos). AAD = utf8("<chatId>|<senderUserId>|<type>") so ciphertext cannot be replayed into another chat or reflected back as if it came from the other person.
- Enable `cryptography_flutter` (native implementations) so photo encryption doesn't freeze cheap phones.
- Plaintext messages, photos and private keys never leave the device and are never logged.
- If decryption fails (for example a contact changed phone), show a graceful "🔒 This message can't be opened" placeholder; never crash.
- Key-change warning: remember each contact's public-key fingerprint locally; if the server later returns a different one, show a yellow banner in that chat: "<Name>'s security code has changed (new phone or reinstall)".
- "Security code" screen (chat menu): show a fingerprint (SHA-256 of both public keys sorted by userId, first 16 bytes as 8 groups of 4 hex characters) so two neighbours can compare codes in person.
- One device per account: logging in on a new phone replaces the encryption key (older messages won't open on the old phone, acceptable because messages expire in 7 days). Document this in the README.

## 7. FLUTTER APP

### 7.1 Networking, state, storage
- `core/config.dart`: API base URL from `String.fromEnvironment('API_BASE_URL')`, defaulting to `http://10.0.2.2:4000` on Android and `http://localhost:4000` elsewhere.
- `api_client.dart`: dio; attaches the access token; on 401 refreshes once (single-flight) and retries; if refresh fails, log out to the Welcome screen.
- `socket_service.dart`: socket_io_client, websocket transport only, token in the handshake, auto-reconnect; on reconnect refresh the token if needed and re-sync.
- Storage: ONLY `flutter_secure_storage` (private key, remembered User ID, contact fingerprints). Require the PIN on every cold launch; keep access and refresh tokens in memory only. NO local database and NO file cache; chat data lives in memory, is re-fetched from the server and decrypted on screen.
- Lifecycle: when the app goes inactive/background show a plain cover so chat content doesn't appear in the app switcher; re-sync on resume.

### 7.2 Screens
1. Welcome: lock + chat icon, app name, two big buttons: "I'm new — Create account" and "I already have an account — Log in".
2. Create account: User name (hint "e.g. flat402_sharma", live validation) and four-digit numeric PIN. The user name is also the display name. Generate keys before the request.
3. Log in: User name + four-digit numeric PIN. For existing accounts, offer a one-time old-password migration to a new PIN. On later launches, show the remembered user name and request only the PIN, using the numeric keyboard. Provide "Use another account" on the PIN screen.
4. Home: app bar "Community Chat" with a find-person icon and a three-dot menu (Settings); tabs CHATS | REQUESTS (count badge); FAB opens Find a neighbour.
   - CHATS: tile = coloured letter avatar, bold name, decrypted last-message preview ("📷 Photo" for images), time, green unread badge; pull-to-refresh; empty state with a big "Find a neighbour" button.
   - REQUESTS: "Received" with big green Accept and grey Decline buttons; "Sent" showing Pending + Cancel; empty state.
5. Find a neighbour: one big field "Type your neighbour's User ID", Search button, result card (name, @userId) with one action by relationship: Send request / Request sent / Accept their request / Open chat / Unavailable.
6. Chat: app bar with avatar, name and "🔒 end-to-end encrypted"; menu: Clear chat, Security code, Remove contact, Block. Beige wallpaper; top notice "Messages and photos are end-to-end encrypted and disappear after 7 days"; date separators; bubbles with time + ticks; key-change banner; input bar [gallery] [camera] [rounded text field] [green send]. Photo bubbles show a thumbnail; tap opens the full-screen viewer. Long-press own message → Delete for everyone.
7. Photo preview (big Send / Cancel), Security code screen.
8. Settings: my name and User ID with a big "Copy my User ID" button (so neighbours can find me), Blocked people, Delete all my chats, Log out, About (explains encryption, the 7-day rule, and that no phone number is ever used).

### 7.3 Platform configuration (do these explicitly)
- Android: add the INTERNET permission to the MAIN manifest (Flutter's template only adds it for debug, so release builds would otherwise have no network); `android:allowBackup="false"`; allow cleartext HTTP ONLY in the debug manifest (so http://10.0.2.2 works in development), release must be HTTPS-only; set `WindowManager.LayoutParams.FLAG_SECURE` in `MainActivity` (blocks screenshots/screen recording and hides content in recent apps) with a one-line comment on how to disable it temporarily; set minSdk to whatever the dependencies require (flutter_secure_storage typically needs 23); app name is "Community Chat"; package ID `com.community.community_chat`.
- iOS: set `CFBundleDisplayName` = "Community Chat"; `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription` and `NSFaceIDUsageDescription` as required; allow HTTP in debug (localhost) if needed but release must be HTTPS-only; disable backup to iCloud (opt-out) for security; set `UIFileSharingEnabled` = NO; disable screenshots on app switcher if needed.

## 8. IMPLEMENTATION PLAN
1. Backend: scaffolding, env validation, MongoDB + models + security middleware; then auth/users/contacts/chats routes, Socket.IO events, purge job, reset-password CLI.
2. Backend tests: smoke test for health and auth; ensure nodemon-style watch and route validation work.
3. Flutter core: crypto, secure storage, base API client, auth state, socket service, screen-state models.
4. Flutter UI: welcome/auth, home tabs, find neighbour, chat screens, settings, photo pipeline.
5. Platform config: Android/iOS manifests and flags.
6. Verification: run backend tests; flutter analyze/test; fix issues; README finalization.

## 9. ACCEPTANCE CRITERIA
- `backend/.env` is present and the backend starts cleanly after the user pastes the Atlas URI, with friendly validation errors before DB connection if missing.
- No Firebase or other cloud services are used anywhere in the project.
- All API routes are strict, authenticated where required, and validate input.
- All critical security rules are implemented in code and documented.
- The Flutter app compiles to Android and iOS with a WhatsApp-style design and end-to-end encryption in the core.
- The codebase is organized exactly as specified and the README explains how to run it.

## 10. DECISIONS TO RECORD IN README
- If there is any ambiguity, choose the simplest, safest option and document it clearly in README.md.
- One device per account is the accepted design; logging in on a new phone replaces the local encryption key (old phone messages expire in 7 days).
- The app never stores message or image plaintext anywhere except the runtime memory of the active screen.
- Use explicit `userId` handles rather than phone numbers or emails in all user-facing flows.

## 11. FINAL NOTES
- The shortest path to a successful and verifiable result is a clean MVP that matches the architecture and security requirements, not a giant feature dump that cuts corners.
- The project root is the current workspace directory; create every file under it.
- Do not stop early or skip the verification step; if you find a problem, finish it before handing over the app.
