import mongoose from 'mongoose';

const mediaSchema = new mongoose.Schema({
  chat: { type: mongoose.Schema.Types.ObjectId, ref: 'Chat', required: true, index: true },
  uploader: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  data: { type: Buffer, select: false },
  size: { type: Number, default: 0 },
  contentType: { type: String, default: 'application/octet-stream' },
  createdAt: { type: Date, default: Date.now },
  expiresAt: { type: Date, required: true },
  purgeAt: { type: Date, required: true, expires: 0 },
});

export default mongoose.models.Media || mongoose.model('Media', mediaSchema);
