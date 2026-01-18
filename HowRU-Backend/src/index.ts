import 'dotenv/config';
import express from 'express';
import cors from 'cors';

import authRoutes from './routes/auth.js';
import checkinsRoutes from './routes/checkins.js';
import webhooksRoutes from './routes/webhooks.js';
import circleRoutes from './routes/circle.js';
import pokesRoutes from './routes/pokes.js';
import alertsRoutes from './routes/alerts.js';
import usersRoutes from './routes/users.js';
import voiceRoutes from './routes/voice.js';
import uploadsRoutes from './routes/uploads.js';
import exportsRoutes from './routes/exports.js';
import subscriptionsRoutes from './routes/subscriptions.js';

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());

// JSON parser with raw body capture for webhook signature verification
app.use(
  express.json({
    verify: (req: express.Request, res, buf) => {
      // Store raw body for webhook signature verification
      (req as any).rawBody = buf;
    },
  })
);

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Routes
app.use('/auth', authRoutes);
app.use('/checkins', checkinsRoutes);
app.use('/webhooks', webhooksRoutes);
app.use('/circle', circleRoutes);
app.use('/pokes', pokesRoutes);
app.use('/alerts', alertsRoutes);
app.use('/users', usersRoutes);
app.use('/voice', voiceRoutes);
app.use('/uploads', uploadsRoutes);
app.use('/exports', exportsRoutes);
app.use('/subscriptions', subscriptionsRoutes);

// Error handler
app.use((err: Error, req: express.Request, res: express.Response, next: express.NextFunction) => {
  console.error('Unhandled error:', err);
  res.status(500).json({
    success: false,
    error: 'Internal server error',
  });
});

// Start server
app.listen(PORT, () => {
  console.log(`🚀 HowRU API server running on port ${PORT}`);
  console.log(`   Health check: http://localhost:${PORT}/health`);
});

export default app;
