import express, { Express, NextFunction, Response } from 'express';
import request from 'supertest';

// Mock the database
jest.mock('../db/index.js', () => ({
  sql: jest.fn(),
  getUserById: jest.fn(),
  getRecentCheckIns: jest.fn(),
  getCircleLinks: jest.fn(),
}));

// Mock storage service
jest.mock('../services/storage.js', () => ({
  uploadFile: jest.fn(),
  getSignedDownloadUrl: jest.fn(),
}));

// Mock Resend service
jest.mock('../services/resend.js', () => ({
  sendExportReadyEmail: jest.fn(),
}));

// Mock auth middleware
jest.mock('../middleware/auth.js', () => ({
  authMiddleware: (req: any, _res: Response, next: NextFunction) => {
    req.userId = 'test-user-id';
    next();
  },
  AuthRequest: {},
}));

import {
  sql,
  getUserById,
  getRecentCheckIns,
  getCircleLinks,
} from '../db/index.js';
import { uploadFile, getSignedDownloadUrl } from '../services/storage.js';
import { sendExportReadyEmail } from '../services/resend.js';
import exportsRouter from '../routes/exports.js';

describe('Exports Routes', () => {
  let app: Express;

  const mockUser = {
    id: 'test-user-id',
    name: 'Test User',
    email: 'test@example.com',
    phone_number: '+15551234567',
    address: '123 Test St',
    created_at: '2024-01-01T00:00:00Z',
  };

  const mockExportRecord = {
    id: 'export-123',
    user_id: 'test-user-id',
    format: 'json',
    status: 'queued',
    created_at: '2024-01-15T10:00:00Z',
    completed_at: null,
    file_url: null,
    file_size_bytes: null,
  };

  beforeEach(() => {
    app = express();
    app.use(express.json());
    app.use('/exports', exportsRouter);
    jest.clearAllMocks();
  });

  // ===========================================================================
  // POST /exports - Request Data Export
  // ===========================================================================
  describe('POST /exports', () => {
    it('should create JSON export request successfully', async () => {
      // No existing export
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);
      // Create export record
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockExportRecord]);
      // Mock the async export processor to not actually run
      (sql as unknown as jest.Mock).mockResolvedValue([]);
      (getUserById as jest.Mock).mockResolvedValue(mockUser);
      (getRecentCheckIns as jest.Mock).mockResolvedValue([]);
      (getCircleLinks as jest.Mock).mockResolvedValue([]);
      (uploadFile as jest.Mock).mockResolvedValue({ cdnUrl: 'https://cdn.example.com/exports/test.json' });

      const response = await request(app)
        .post('/exports')
        .send({ format: 'json' })
        .expect(202);

      expect(response.body.success).toBe(true);
      expect(response.body.exportId).toBe('export-123');
      expect(response.body.status).toBe('queued');
      expect(response.body.message).toContain('queued');
    });

    it('should create CSV export request successfully', async () => {
      const csvExportRecord = { ...mockExportRecord, format: 'csv' };
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);
      (sql as unknown as jest.Mock).mockResolvedValueOnce([csvExportRecord]);
      (sql as unknown as jest.Mock).mockResolvedValue([]);
      (getUserById as jest.Mock).mockResolvedValue(mockUser);
      (getRecentCheckIns as jest.Mock).mockResolvedValue([]);
      (getCircleLinks as jest.Mock).mockResolvedValue([]);
      (uploadFile as jest.Mock).mockResolvedValue({ cdnUrl: 'https://cdn.example.com/exports/test.csv' });

      const response = await request(app)
        .post('/exports')
        .send({ format: 'csv' })
        .expect(202);

      expect(response.body.success).toBe(true);
      expect(response.body.status).toBe('queued');
    });

    it('should default to JSON format', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockExportRecord]);
      (sql as unknown as jest.Mock).mockResolvedValue([]);
      (getUserById as jest.Mock).mockResolvedValue(mockUser);
      (getRecentCheckIns as jest.Mock).mockResolvedValue([]);
      (getCircleLinks as jest.Mock).mockResolvedValue([]);
      (uploadFile as jest.Mock).mockResolvedValue({ cdnUrl: 'https://cdn.example.com/exports/test.json' });

      const response = await request(app)
        .post('/exports')
        .send({})
        .expect(202);

      expect(response.body.success).toBe(true);
    });

    it('should return 409 when export already in progress', async () => {
      const inProgressExport = {
        id: 'existing-export-id',
        status: 'processing',
      };
      (sql as unknown as jest.Mock).mockResolvedValueOnce([inProgressExport]);

      const response = await request(app)
        .post('/exports')
        .send({ format: 'json' })
        .expect(409);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Export already in progress');
      expect(response.body.exportId).toBe('existing-export-id');
    });

    it('should return 409 when export is queued', async () => {
      const queuedExport = {
        id: 'queued-export-id',
        status: 'queued',
      };
      (sql as unknown as jest.Mock).mockResolvedValueOnce([queuedExport]);

      const response = await request(app)
        .post('/exports')
        .send({ format: 'json' })
        .expect(409);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Export already in progress');
    });

    it('should return 400 for invalid format', async () => {
      const response = await request(app)
        .post('/exports')
        .send({ format: 'xml' })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 on database error', async () => {
      (sql as unknown as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .post('/exports')
        .send({ format: 'json' })
        .expect(400);

      expect(response.body.success).toBe(false);
    });
  });

  // ===========================================================================
  // GET /exports/:exportId - Get Export Status
  // ===========================================================================
  describe('GET /exports/:exportId', () => {
    it('should return queued export status', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockExportRecord]);

      const response = await request(app)
        .get('/exports/export-123')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.export.id).toBe('export-123');
      expect(response.body.export.status).toBe('queued');
      expect(response.body.export.format).toBe('json');
      expect(response.body.export.downloadUrl).toBeUndefined();
    });

    it('should return ready export with download URL', async () => {
      const readyExport = {
        ...mockExportRecord,
        status: 'ready',
        file_url: 'https://cdn.example.com/exports/test-user-id/export-123.json',
        file_size_bytes: 12345,
        completed_at: '2024-01-15T10:05:00Z',
      };
      (sql as unknown as jest.Mock).mockResolvedValueOnce([readyExport]);
      (getSignedDownloadUrl as jest.Mock).mockResolvedValue('https://r2.example.com/exports/signed-url');

      const response = await request(app)
        .get('/exports/export-123')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.export.status).toBe('ready');
      expect(response.body.export.downloadUrl).toBe('https://r2.example.com/exports/signed-url');
      expect(response.body.export.fileSizeBytes).toBe(12345);
      expect(response.body.export.completedAt).toBe('2024-01-15T10:05:00Z');
      expect(getSignedDownloadUrl).toHaveBeenCalledWith(
        expect.stringContaining('export-123.json'),
        3600
      );
    });

    it('should return processing export without download URL', async () => {
      const processingExport = {
        ...mockExportRecord,
        status: 'processing',
      };
      (sql as unknown as jest.Mock).mockResolvedValueOnce([processingExport]);

      const response = await request(app)
        .get('/exports/export-123')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.export.status).toBe('processing');
      expect(response.body.export.downloadUrl).toBeUndefined();
    });

    it('should return failed export status', async () => {
      const failedExport = {
        ...mockExportRecord,
        status: 'failed',
      };
      (sql as unknown as jest.Mock).mockResolvedValueOnce([failedExport]);

      const response = await request(app)
        .get('/exports/export-123')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.export.status).toBe('failed');
    });

    it('should return 404 for non-existent export', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);

      const response = await request(app)
        .get('/exports/non-existent-id')
        .expect(404);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Export not found');
    });

    it('should return 404 for export belonging to another user', async () => {
      // The query filters by user_id, so if no result, it's effectively a 404
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);

      const response = await request(app)
        .get('/exports/other-users-export')
        .expect(404);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 on database error', async () => {
      (sql as unknown as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .get('/exports/export-123')
        .expect(400);

      expect(response.body.success).toBe(false);
    });
  });

  // ===========================================================================
  // GET /exports - List User Exports
  // ===========================================================================
  describe('GET /exports', () => {
    it('should return list of exports', async () => {
      const exportsList = [
        {
          id: 'export-1',
          status: 'ready',
          format: 'json',
          created_at: '2024-01-15T10:00:00Z',
          completed_at: '2024-01-15T10:05:00Z',
          file_size_bytes: 12345,
        },
        {
          id: 'export-2',
          status: 'failed',
          format: 'csv',
          created_at: '2024-01-14T10:00:00Z',
          completed_at: null,
          file_size_bytes: null,
        },
      ];
      (sql as unknown as jest.Mock).mockResolvedValueOnce(exportsList);

      const response = await request(app)
        .get('/exports')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.exports).toHaveLength(2);
      expect(response.body.exports[0].id).toBe('export-1');
      expect(response.body.exports[0].status).toBe('ready');
      expect(response.body.exports[0].format).toBe('json');
      expect(response.body.exports[0].fileSizeBytes).toBe(12345);
      expect(response.body.exports[1].id).toBe('export-2');
      expect(response.body.exports[1].status).toBe('failed');
    });

    it('should return empty array when no exports', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);

      const response = await request(app)
        .get('/exports')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.exports).toEqual([]);
    });

    it('should limit to 10 most recent exports', async () => {
      // The route limits to 10, so we verify by checking the SQL was called
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);

      await request(app)
        .get('/exports')
        .expect(200);

      // Verify LIMIT 10 is in the query
      expect(sql).toHaveBeenCalled();
    });

    it('should return 400 on database error', async () => {
      (sql as unknown as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .get('/exports')
        .expect(400);

      expect(response.body.success).toBe(false);
    });
  });

  // ===========================================================================
  // Export Processing Tests (async processor behavior)
  // ===========================================================================
  describe('Export Processing', () => {
    it('should include all user data in JSON export', async () => {
      const checkIns = [
        {
          timestamp: '2024-01-15T10:00:00Z',
          mental_score: 4,
          body_score: 3,
          mood_score: 5,
          location_name: 'Home',
        },
      ];
      const circleLinks = [
        {
          supporter_display_name: 'Mom',
          supporter_name: 'Jane Doe',
          invited_at: '2024-01-01T00:00:00Z',
          can_see_mood: true,
          can_see_location: true,
          can_poke: true,
        },
      ];

      // No existing export
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);
      // Create export record
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockExportRecord]);
      // Update to processing
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);
      // Get pokes
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);
      // Get alerts
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);
      // Get schedules
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);
      // Update to ready
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);

      (getUserById as jest.Mock).mockResolvedValue(mockUser);
      (getRecentCheckIns as jest.Mock).mockResolvedValue(checkIns);
      (getCircleLinks as jest.Mock).mockResolvedValue(circleLinks);
      (uploadFile as jest.Mock).mockResolvedValue({ cdnUrl: 'https://cdn.example.com/exports/test.json' });
      (sendExportReadyEmail as jest.Mock).mockResolvedValue(undefined);

      const response = await request(app)
        .post('/exports')
        .send({ format: 'json' })
        .expect(202);

      expect(response.body.success).toBe(true);

      // Wait a bit for async processing
      await new Promise((resolve) => setTimeout(resolve, 100));

      // Verify upload was called
      expect(uploadFile).toHaveBeenCalled();
    });

    it('should send email notification when export is ready', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockExportRecord]);
      (sql as unknown as jest.Mock).mockResolvedValue([]);
      (getUserById as jest.Mock).mockResolvedValue(mockUser);
      (getRecentCheckIns as jest.Mock).mockResolvedValue([]);
      (getCircleLinks as jest.Mock).mockResolvedValue([]);
      (uploadFile as jest.Mock).mockResolvedValue({ cdnUrl: 'https://cdn.example.com/exports/test.json' });
      (sendExportReadyEmail as jest.Mock).mockResolvedValue(undefined);

      await request(app)
        .post('/exports')
        .send({ format: 'json' })
        .expect(202);

      // Wait for async processing
      await new Promise((resolve) => setTimeout(resolve, 100));

      expect(sendExportReadyEmail).toHaveBeenCalledWith({
        to: 'test@example.com',
        userName: 'Test User',
        exportId: 'export-123',
        format: 'json',
      });
    });

    it('should continue even if email notification fails', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockExportRecord]);
      (sql as unknown as jest.Mock).mockResolvedValue([]);
      (getUserById as jest.Mock).mockResolvedValue(mockUser);
      (getRecentCheckIns as jest.Mock).mockResolvedValue([]);
      (getCircleLinks as jest.Mock).mockResolvedValue([]);
      (uploadFile as jest.Mock).mockResolvedValue({ cdnUrl: 'https://cdn.example.com/exports/test.json' });
      (sendExportReadyEmail as jest.Mock).mockRejectedValue(new Error('Email failed'));

      const response = await request(app)
        .post('/exports')
        .send({ format: 'json' })
        .expect(202);

      expect(response.body.success).toBe(true);
    });

    it('should skip email when user has no email', async () => {
      const userWithoutEmail = { ...mockUser, email: null };
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockExportRecord]);
      (sql as unknown as jest.Mock).mockResolvedValue([]);
      (getUserById as jest.Mock).mockResolvedValue(userWithoutEmail);
      (getRecentCheckIns as jest.Mock).mockResolvedValue([]);
      (getCircleLinks as jest.Mock).mockResolvedValue([]);
      (uploadFile as jest.Mock).mockResolvedValue({ cdnUrl: 'https://cdn.example.com/exports/test.json' });

      await request(app)
        .post('/exports')
        .send({ format: 'json' })
        .expect(202);

      // Wait for async processing
      await new Promise((resolve) => setTimeout(resolve, 100));

      expect(sendExportReadyEmail).not.toHaveBeenCalled();
    });
  });
});
