import mongoose from 'mongoose';

const userSchema = new mongoose.Schema({
  userId: {
    type: String,
    required: true,
    unique: true,
    lowercase: true,
    trim: true,
    index: true,
  },
  displayName: { type: String, required: true, trim: true },
  passwordHash: { type: String, required: true },
  pinConfigured: { type: Boolean, default: false },
  publicKey: { type: String, default: null },
  publicKeyUpdatedAt: { type: Date, default: null },
  failedLogins: { type: Number, default: 0 },
  lockUntil: { type: Date, default: null },
  createdAt: { type: Date, default: Date.now },
}, { timestamps: true });

export default mongoose.models.User || mongoose.model('User', userSchema);
