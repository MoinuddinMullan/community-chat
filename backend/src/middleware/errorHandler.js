export function notFoundHandler(req, res) {
  res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Resource not found.' } });
}

export function errorHandler(error, req, res, next) {
  if (res.headersSent) {
    return next(error);
  }

  const code = error.code || 'INTERNAL_ERROR';
  const message = error.statusCode === 400 || error.statusCode === 401 || error.statusCode === 404 || error.statusCode === 409
    ? error.message || 'Request failed.'
    : 'Something went wrong.';

  res.status(error.statusCode || 500).json({
    error: {
      code,
      message,
    },
  });
}
