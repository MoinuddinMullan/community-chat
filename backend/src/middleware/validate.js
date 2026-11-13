import mongoose from 'mongoose';
import { z } from 'zod';

export function validateBody(schema) {
  return (req, res, next) => {
    const result = schema.safeParse(req.body);
    if (!result.success) {
      return next({ statusCode: 400, code: 'VALIDATION_ERROR', message: result.error.issues[0]?.message || 'Invalid request parameters.' });
    }
    req.body = result.data;
    next();
  };
}

export function validateParams(schema) {
  return (req, res, next) => {
    const result = schema.safeParse(req.params);
    if (!result.success) {
      return next({ statusCode: 400, code: 'VALIDATION_ERROR', message: result.error.issues[0]?.message || 'Invalid params.' });
    }
    req.params = result.data;
    next();
  };
}

export function validateObjectId(field = 'id') {
  return (req, res, next) => {
    const value = req.params[field] || req.body[field];
    if (!value || !mongoose.Types.ObjectId.isValid(value)) {
      return next({ statusCode: 400, code: 'INVALID_OBJECT_ID', message: 'Invalid object id.' });
    }
    next();
  };
}

export const objectIdSchema = z.string().regex(/^[a-fA-F0-9]{24}$/);
