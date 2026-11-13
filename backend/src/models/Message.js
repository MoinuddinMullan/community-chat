import mongoose from 'mongoose';

const messageSchema = new mongoose.Schema({
  chat: { type: mongoose.Schema.Types.ObjectId, ref: 'Chat', required: true, index: true },
  sender: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  type: { type: String, enum: ['text', 'image'], default: 'text' },
  payload: { type: String, default: null },
  imageUrl: { type: String, default: null },
  caption: { type: String, default: null, maxlength: 4000 },
  media: { type: mongoose.Schema.Types.ObjectId, ref: 'Media', default: null },
  clientId: { type: String, default: null },
  readAt: { type: Date, default: null },
  createdAt: { type: Date, default: Date.now },
  expiresAt: { type: Date, required: true },
  purgeAt: { type: Date, required: true, expires: 0 },
}, {
  indexes: [
    { key: { chat: 1, createdAt: -1 } },
    { key: { chat: 1, sender: 1, clientId: 1 }, unique: true, partialFilterExpression: { clientId: { $type: 'string' } } },
  ],
});

export default mongoose.models.Message || mongoose.model('Message', messageSchema);
