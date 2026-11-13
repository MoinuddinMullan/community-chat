import mongoose from 'mongoose';

const connectionSchema = new mongoose.Schema({
  pairKey: { type: String, required: true, unique: true, index: true },
  requester: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  recipient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  status: {
    type: String,
    enum: ['pending', 'accepted', 'declined', 'blocked'],
    default: 'pending',
  },
  blockedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', default: null },
  createdAt: { type: Date, default: Date.now },
  respondedAt: { type: Date, default: null },
});

export default mongoose.models.Connection || mongoose.model('Connection', connectionSchema);
