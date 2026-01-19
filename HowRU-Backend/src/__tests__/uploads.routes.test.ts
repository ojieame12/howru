import express, { Express, NextFunction, Response } from 'express';
import request from 'supertest';

// Mock the database
jest.mock('../db/index.js', () => ({
  sql: jest.fn(),
}));

// Mock storage service
jest.mock('../services/storage.js', () => ({
  uploadSelfie: jest.fn(),
  uploadAvatar: jest.fn(),
  deleteFileByUrl: jest.fn(),
  getSignedUploadUrl: jest.fn(),
  isStorageConfigured: jest.fn(),
}));

// Mock auth middleware
jest.mock('../middleware/auth.js', () => ({
  authMiddleware: (req: any, _res: Response, next: NextFunction) => {
    req.userId = 'test-user-id';
    next();
  },
  AuthRequest: {},
}));

import { sql } from '../db/index.js';
import {
  uploadSelfie,
  uploadAvatar,
  deleteFileByUrl,
  getSignedUploadUrl,
  isStorageConfigured,
} from '../services/storage.js';
import uploadsRouter from '../routes/uploads.js';

describe('Uploads Routes', () => {
  let app: Express;

  beforeEach(() => {
    app = express();
    app.use(express.json({ limit: '10mb' }));
    app.use('/uploads', uploadsRouter);
    jest.clearAllMocks();
    (isStorageConfigured as jest.Mock).mockReturnValue(true);
  });

  // ===========================================================================
  // POST /uploads/url - Get Pre-signed Upload URL
  // ===========================================================================
  describe('POST /uploads/url', () => {
    it('should return pre-signed URL for selfie upload', async () => {
      (getSignedUploadUrl as jest.Mock).mockResolvedValue({
        uploadUrl: 'https://r2.example.com/upload?signature=xyz',
        key: 'selfies/test-user-id/2024-01-15.jpg',
        cdnUrl: 'https://cdn.example.com/selfies/test-user-id/2024-01-15.jpg',
      });

      const response = await request(app)
        .post('/uploads/url')
        .send({ category: 'selfie', contentType: 'image/jpeg' })
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.uploadUrl).toContain('https://r2.example.com');
      expect(response.body.key).toContain('selfies');
      expect(response.body.cdnUrl).toContain('cdn.example.com');
      expect(response.body.expiresIn).toBe(300);
      expect(getSignedUploadUrl).toHaveBeenCalledWith('selfies', 'test-user-id', 'image/jpeg');
    });

    it('should return pre-signed URL for avatar upload', async () => {
      (getSignedUploadUrl as jest.Mock).mockResolvedValue({
        uploadUrl: 'https://r2.example.com/upload?signature=abc',
        key: 'avatars/test-user-id/avatar.jpg',
        cdnUrl: 'https://cdn.example.com/avatars/test-user-id/avatar.jpg',
      });

      const response = await request(app)
        .post('/uploads/url')
        .send({ category: 'avatar' })
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(getSignedUploadUrl).toHaveBeenCalledWith('avatars', 'test-user-id', 'image/jpeg');
    });

    it('should default contentType to image/jpeg', async () => {
      (getSignedUploadUrl as jest.Mock).mockResolvedValue({
        uploadUrl: 'https://r2.example.com/upload',
        key: 'selfies/test.jpg',
        cdnUrl: 'https://cdn.example.com/selfies/test.jpg',
      });

      await request(app)
        .post('/uploads/url')
        .send({ category: 'selfie' })
        .expect(200);

      expect(getSignedUploadUrl).toHaveBeenCalledWith('selfies', 'test-user-id', 'image/jpeg');
    });

    it('should return 503 when storage not configured', async () => {
      (isStorageConfigured as jest.Mock).mockReturnValue(false);

      const response = await request(app)
        .post('/uploads/url')
        .send({ category: 'selfie' })
        .expect(503);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Storage service not configured');
    });

    it('should return 400 for invalid category', async () => {
      const response = await request(app)
        .post('/uploads/url')
        .send({ category: 'invalid' })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for missing category', async () => {
      const response = await request(app)
        .post('/uploads/url')
        .send({})
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 on storage error', async () => {
      (getSignedUploadUrl as jest.Mock).mockRejectedValue(new Error('Storage error'));

      const response = await request(app)
        .post('/uploads/url')
        .send({ category: 'selfie' })
        .expect(400);

      expect(response.body.success).toBe(false);
    });
  });

  // ===========================================================================
  // POST /uploads/selfie - Direct Selfie Upload
  // ===========================================================================
  describe('POST /uploads/selfie', () => {
    const mockImageData = Buffer.from('fake-image-data').toString('base64');

    it('should upload selfie successfully', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([{ id: 'checkin-123' }]); // Check-in exists
      (uploadSelfie as jest.Mock).mockResolvedValue({
        cdnUrl: 'https://cdn.example.com/selfies/test.jpg',
        expiresAt: new Date('2024-01-16T10:00:00Z'),
      });
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]); // Update check-in

      const response = await request(app)
        .post('/uploads/selfie')
        .send({
          checkinId: '11111111-1111-1111-1111-111111111111',
          imageData: mockImageData,
          contentType: 'image/jpeg',
        })
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.url).toBe('https://cdn.example.com/selfies/test.jpg');
      expect(response.body.expiresAt).toBeDefined();
      expect(uploadSelfie).toHaveBeenCalled();
    });

    it('should use default contentType of image/jpeg', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([{ id: 'checkin-123' }]);
      (uploadSelfie as jest.Mock).mockResolvedValue({
        cdnUrl: 'https://cdn.example.com/selfies/test.jpg',
        expiresAt: new Date(),
      });
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);

      await request(app)
        .post('/uploads/selfie')
        .send({
          checkinId: '11111111-1111-1111-1111-111111111111',
          imageData: mockImageData,
        })
        .expect(200);

      expect(uploadSelfie).toHaveBeenCalledWith(
        'test-user-id',
        '11111111-1111-1111-1111-111111111111',
        expect.any(Buffer),
        'image/jpeg'
      );
    });

    it('should return 503 when storage not configured', async () => {
      (isStorageConfigured as jest.Mock).mockReturnValue(false);

      const response = await request(app)
        .post('/uploads/selfie')
        .send({
          checkinId: '11111111-1111-1111-1111-111111111111',
          imageData: mockImageData,
        })
        .expect(503);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Storage service not configured');
    });

    it('should return 404 when check-in not found', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);

      const response = await request(app)
        .post('/uploads/selfie')
        .send({
          checkinId: '11111111-1111-1111-1111-111111111111',
          imageData: mockImageData,
        })
        .expect(404);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Check-in not found');
    });

    it('should return 400 for invalid checkinId UUID', async () => {
      const response = await request(app)
        .post('/uploads/selfie')
        .send({
          checkinId: 'not-a-uuid',
          imageData: mockImageData,
        })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for missing imageData', async () => {
      const response = await request(app)
        .post('/uploads/selfie')
        .send({
          checkinId: '11111111-1111-1111-1111-111111111111',
        })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for empty imageData', async () => {
      const response = await request(app)
        .post('/uploads/selfie')
        .send({
          checkinId: '11111111-1111-1111-1111-111111111111',
          imageData: '',
        })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 on upload error', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([{ id: 'checkin-123' }]);
      (uploadSelfie as jest.Mock).mockRejectedValue(new Error('Upload failed'));

      const response = await request(app)
        .post('/uploads/selfie')
        .send({
          checkinId: '11111111-1111-1111-1111-111111111111',
          imageData: mockImageData,
        })
        .expect(400);

      expect(response.body.success).toBe(false);
    });
  });

  // ===========================================================================
  // POST /uploads/selfie/confirm - Confirm Pre-signed Selfie Upload
  // ===========================================================================
  describe('POST /uploads/selfie/confirm', () => {
    it('should confirm selfie upload successfully', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([{ id: 'checkin-123' }]);
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);

      const response = await request(app)
        .post('/uploads/selfie/confirm')
        .send({
          checkinId: '11111111-1111-1111-1111-111111111111',
          key: 'selfies/test-user-id/test.jpg',
          cdnUrl: 'https://cdn.example.com/selfies/test.jpg',
        })
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.url).toBe('https://cdn.example.com/selfies/test.jpg');
      expect(response.body.expiresAt).toBeDefined();
    });

    it('should return 404 when check-in not found', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);

      const response = await request(app)
        .post('/uploads/selfie/confirm')
        .send({
          checkinId: '11111111-1111-1111-1111-111111111111',
          key: 'selfies/test.jpg',
          cdnUrl: 'https://cdn.example.com/selfies/test.jpg',
        })
        .expect(404);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Check-in not found');
    });

    it('should return 400 for invalid cdnUrl', async () => {
      const response = await request(app)
        .post('/uploads/selfie/confirm')
        .send({
          checkinId: '11111111-1111-1111-1111-111111111111',
          key: 'selfies/test.jpg',
          cdnUrl: 'not-a-url',
        })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for missing key', async () => {
      const response = await request(app)
        .post('/uploads/selfie/confirm')
        .send({
          checkinId: '11111111-1111-1111-1111-111111111111',
          cdnUrl: 'https://cdn.example.com/selfies/test.jpg',
        })
        .expect(400);

      expect(response.body.success).toBe(false);
    });
  });

  // ===========================================================================
  // POST /uploads/avatar - Direct Avatar Upload
  // ===========================================================================
  describe('POST /uploads/avatar', () => {
    const mockImageData = Buffer.from('fake-avatar-data').toString('base64');

    it('should upload avatar successfully', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([{ profile_image_url: null }]); // Get user
      (uploadAvatar as jest.Mock).mockResolvedValue({
        cdnUrl: 'https://cdn.example.com/avatars/test.jpg',
      });
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]); // Update user

      const response = await request(app)
        .post('/uploads/avatar')
        .send({
          imageData: mockImageData,
          contentType: 'image/png',
        })
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.url).toBe('https://cdn.example.com/avatars/test.jpg');
      expect(uploadAvatar).toHaveBeenCalledWith(
        'test-user-id',
        expect.any(Buffer),
        'image/png'
      );
    });

    it('should delete old avatar before uploading new one', async () => {
      const oldAvatarUrl = 'https://cdn.example.com/avatars/old.jpg';
      (sql as unknown as jest.Mock).mockResolvedValueOnce([{ profile_image_url: oldAvatarUrl }]);
      (deleteFileByUrl as jest.Mock).mockResolvedValue(undefined);
      (uploadAvatar as jest.Mock).mockResolvedValue({
        cdnUrl: 'https://cdn.example.com/avatars/new.jpg',
      });
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);

      await request(app)
        .post('/uploads/avatar')
        .send({ imageData: mockImageData })
        .expect(200);

      expect(deleteFileByUrl).toHaveBeenCalledWith(oldAvatarUrl);
    });

    it('should continue even if deleting old avatar fails', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([{ profile_image_url: 'https://old.jpg' }]);
      (deleteFileByUrl as jest.Mock).mockRejectedValue(new Error('Delete failed'));
      (uploadAvatar as jest.Mock).mockResolvedValue({
        cdnUrl: 'https://cdn.example.com/avatars/new.jpg',
      });
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);

      const response = await request(app)
        .post('/uploads/avatar')
        .send({ imageData: mockImageData })
        .expect(200);

      expect(response.body.success).toBe(true);
    });

    it('should return 503 when storage not configured', async () => {
      (isStorageConfigured as jest.Mock).mockReturnValue(false);

      const response = await request(app)
        .post('/uploads/avatar')
        .send({ imageData: mockImageData })
        .expect(503);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Storage service not configured');
    });

    it('should return 400 for missing imageData', async () => {
      const response = await request(app)
        .post('/uploads/avatar')
        .send({})
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 on upload error', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([{ profile_image_url: null }]);
      (uploadAvatar as jest.Mock).mockRejectedValue(new Error('Upload failed'));

      const response = await request(app)
        .post('/uploads/avatar')
        .send({ imageData: mockImageData })
        .expect(400);

      expect(response.body.success).toBe(false);
    });
  });

  // ===========================================================================
  // POST /uploads/avatar/confirm - Confirm Pre-signed Avatar Upload
  // ===========================================================================
  describe('POST /uploads/avatar/confirm', () => {
    it('should confirm avatar upload successfully', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([{ profile_image_url: null }]);
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);

      const response = await request(app)
        .post('/uploads/avatar/confirm')
        .send({
          key: 'avatars/test-user-id/avatar.jpg',
          cdnUrl: 'https://cdn.example.com/avatars/avatar.jpg',
        })
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.url).toBe('https://cdn.example.com/avatars/avatar.jpg');
    });

    it('should delete old avatar when confirming new one', async () => {
      const oldUrl = 'https://cdn.example.com/avatars/old.jpg';
      (sql as unknown as jest.Mock).mockResolvedValueOnce([{ profile_image_url: oldUrl }]);
      (deleteFileByUrl as jest.Mock).mockResolvedValue(undefined);
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);

      await request(app)
        .post('/uploads/avatar/confirm')
        .send({
          key: 'avatars/new.jpg',
          cdnUrl: 'https://cdn.example.com/avatars/new.jpg',
        })
        .expect(200);

      expect(deleteFileByUrl).toHaveBeenCalledWith(oldUrl);
    });

    it('should return 400 for invalid cdnUrl', async () => {
      const response = await request(app)
        .post('/uploads/avatar/confirm')
        .send({
          key: 'avatars/test.jpg',
          cdnUrl: 'not-a-url',
        })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for missing key', async () => {
      const response = await request(app)
        .post('/uploads/avatar/confirm')
        .send({
          cdnUrl: 'https://cdn.example.com/avatars/test.jpg',
        })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for empty key', async () => {
      const response = await request(app)
        .post('/uploads/avatar/confirm')
        .send({
          key: '',
          cdnUrl: 'https://cdn.example.com/avatars/test.jpg',
        })
        .expect(400);

      expect(response.body.success).toBe(false);
    });
  });

  // ===========================================================================
  // DELETE /uploads/avatar - Delete Avatar
  // ===========================================================================
  describe('DELETE /uploads/avatar', () => {
    it('should delete avatar successfully', async () => {
      const avatarUrl = 'https://cdn.example.com/avatars/test.jpg';
      (sql as unknown as jest.Mock).mockResolvedValueOnce([{ profile_image_url: avatarUrl }]);
      (deleteFileByUrl as jest.Mock).mockResolvedValue(undefined);
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);

      const response = await request(app)
        .delete('/uploads/avatar')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(deleteFileByUrl).toHaveBeenCalledWith(avatarUrl);
    });

    it('should succeed even when no avatar exists', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([{ profile_image_url: null }]);

      const response = await request(app)
        .delete('/uploads/avatar')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(deleteFileByUrl).not.toHaveBeenCalled();
    });

    it('should continue even if storage deletion fails', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([{ profile_image_url: 'https://test.jpg' }]);
      (deleteFileByUrl as jest.Mock).mockRejectedValue(new Error('Delete failed'));
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);

      const response = await request(app)
        .delete('/uploads/avatar')
        .expect(200);

      expect(response.body.success).toBe(true);
    });

    it('should return 400 on database error', async () => {
      (sql as unknown as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .delete('/uploads/avatar')
        .expect(400);

      expect(response.body.success).toBe(false);
    });
  });
});
