import express, { Express, NextFunction, Response } from 'express';
import request from 'supertest';

// Mock the database
jest.mock('../db/index.js', () => ({
  getUserById: jest.fn(),
  updateUser: jest.fn(),
  getActiveSchedule: jest.fn(),
  updateSchedule: jest.fn(),
  getSubscription: jest.fn(),
  savePushToken: jest.fn(),
  deletePushToken: jest.fn(),
  deleteUserRefreshTokens: jest.fn(),
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
  getUserById,
  updateUser,
  getActiveSchedule,
  updateSchedule,
  getSubscription,
  savePushToken,
  deletePushToken,
  deleteUserRefreshTokens,
} from '../db/index.js';
import usersRouter from '../routes/users.js';

describe('Users Routes', () => {
  let app: Express;

  const mockUser = {
    id: 'test-user-id',
    name: 'Test User',
    phone_number: '+15551234567',
    email: 'test@example.com',
    profile_image_url: 'https://cdn.example.com/avatar.jpg',
    address: '123 Test St',
    is_checker: true,
    last_known_address: '456 Last St',
    last_known_location_at: '2024-01-15T10:00:00Z',
    created_at: '2024-01-01T00:00:00Z',
  };

  const mockSchedule = {
    id: 'schedule-1',
    window_start_hour: 8,
    window_start_minute: 0,
    window_end_hour: 22,
    window_end_minute: 0,
    timezone_identifier: 'America/New_York',
    active_days: [1, 2, 3, 4, 5],
    grace_period_minutes: 30,
    reminder_enabled: true,
    reminder_minutes_before: 15,
    is_active: true,
  };

  const mockSubscription = {
    plan: 'premium',
    status: 'active',
    expires_at: '2025-01-01T00:00:00Z',
  };

  beforeEach(() => {
    app = express();
    app.use(express.json());
    app.use('/users', usersRouter);
    jest.clearAllMocks();
  });

  // ===========================================================================
  // GET /users/me - Get My Profile
  // ===========================================================================
  describe('GET /users/me', () => {
    it('should return user profile with schedule and subscription', async () => {
      (getUserById as jest.Mock).mockResolvedValue(mockUser);
      (getActiveSchedule as jest.Mock).mockResolvedValue(mockSchedule);
      (getSubscription as jest.Mock).mockResolvedValue(mockSubscription);

      const response = await request(app)
        .get('/users/me')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.user.id).toBe('test-user-id');
      expect(response.body.user.name).toBe('Test User');
      expect(response.body.user.email).toBe('test@example.com');
      expect(response.body.schedule.windowStartHour).toBe(8);
      expect(response.body.subscription.plan).toBe('premium');
    });

    it('should return null schedule when none exists', async () => {
      (getUserById as jest.Mock).mockResolvedValue(mockUser);
      (getActiveSchedule as jest.Mock).mockResolvedValue(null);
      (getSubscription as jest.Mock).mockResolvedValue(null);

      const response = await request(app)
        .get('/users/me')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.schedule).toBeNull();
      expect(response.body.subscription.plan).toBe('free');
    });

    it('should return 404 when user not found', async () => {
      (getUserById as jest.Mock).mockResolvedValue(null);

      const response = await request(app)
        .get('/users/me')
        .expect(404);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('User not found');
    });

    it('should return 500 on database error', async () => {
      (getUserById as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .get('/users/me')
        .expect(500);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Failed to get profile');
    });
  });

  // ===========================================================================
  // PATCH /users/me - Update My Profile
  // ===========================================================================
  describe('PATCH /users/me', () => {
    it('should update user name successfully', async () => {
      const updatedUser = { ...mockUser, name: 'Updated Name' };
      (updateUser as jest.Mock).mockResolvedValue(updatedUser);

      const response = await request(app)
        .patch('/users/me')
        .send({ name: 'Updated Name' })
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.user.name).toBe('Updated Name');
      expect(updateUser).toHaveBeenCalledWith('test-user-id', { name: 'Updated Name' });
    });

    it('should update user email successfully', async () => {
      const updatedUser = { ...mockUser, email: 'new@example.com' };
      (updateUser as jest.Mock).mockResolvedValue(updatedUser);

      const response = await request(app)
        .patch('/users/me')
        .send({ email: 'new@example.com' })
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.user.email).toBe('new@example.com');
    });

    it('should update profile image URL', async () => {
      const updatedUser = { ...mockUser, profile_image_url: 'https://new.url/image.jpg' };
      (updateUser as jest.Mock).mockResolvedValue(updatedUser);

      const response = await request(app)
        .patch('/users/me')
        .send({ profileImageUrl: 'https://new.url/image.jpg' })
        .expect(200);

      expect(response.body.success).toBe(true);
    });

    it('should return 400 for invalid email format', async () => {
      const response = await request(app)
        .patch('/users/me')
        .send({ email: 'not-an-email' })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for name too long', async () => {
      const response = await request(app)
        .patch('/users/me')
        .send({ name: 'a'.repeat(101) })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for empty name', async () => {
      const response = await request(app)
        .patch('/users/me')
        .send({ name: '' })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for address too long', async () => {
      const response = await request(app)
        .patch('/users/me')
        .send({ address: 'a'.repeat(501) })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for invalid profile image URL', async () => {
      const response = await request(app)
        .patch('/users/me')
        .send({ profileImageUrl: 'not-a-url' })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 404 when user not found', async () => {
      (updateUser as jest.Mock).mockResolvedValue(null);

      const response = await request(app)
        .patch('/users/me')
        .send({ name: 'New Name' })
        .expect(404);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('User not found');
    });
  });

  // ===========================================================================
  // GET /users/me/schedule - Get My Schedule
  // ===========================================================================
  describe('GET /users/me/schedule', () => {
    it('should return user schedule', async () => {
      (getActiveSchedule as jest.Mock).mockResolvedValue(mockSchedule);

      const response = await request(app)
        .get('/users/me/schedule')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.schedule.windowStartHour).toBe(8);
      expect(response.body.schedule.windowEndHour).toBe(22);
      expect(response.body.schedule.timezone).toBe('America/New_York');
      expect(response.body.schedule.activeDays).toEqual([1, 2, 3, 4, 5]);
    });

    it('should return null when no schedule exists', async () => {
      (getActiveSchedule as jest.Mock).mockResolvedValue(null);

      const response = await request(app)
        .get('/users/me/schedule')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.schedule).toBeNull();
    });

    it('should return 500 on database error', async () => {
      (getActiveSchedule as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .get('/users/me/schedule')
        .expect(500);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Failed to get schedule');
    });
  });

  // ===========================================================================
  // PUT /users/me/schedule - Update My Schedule
  // ===========================================================================
  describe('PUT /users/me/schedule', () => {
    it('should update schedule successfully', async () => {
      const updatedSchedule = { ...mockSchedule, window_start_hour: 9 };
      (updateSchedule as jest.Mock).mockResolvedValue(updatedSchedule);

      const response = await request(app)
        .put('/users/me/schedule')
        .send({ windowStartHour: 9 })
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.schedule.windowStartHour).toBe(9);
    });

    it('should update multiple schedule fields', async () => {
      const updatedSchedule = {
        ...mockSchedule,
        window_start_hour: 7,
        window_end_hour: 21,
        grace_period_minutes: 45,
      };
      (updateSchedule as jest.Mock).mockResolvedValue(updatedSchedule);

      const response = await request(app)
        .put('/users/me/schedule')
        .send({
          windowStartHour: 7,
          windowEndHour: 21,
          gracePeriodMinutes: 45,
        })
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.schedule.windowStartHour).toBe(7);
      expect(response.body.schedule.windowEndHour).toBe(21);
      expect(response.body.schedule.gracePeriodMinutes).toBe(45);
    });

    it('should update active days', async () => {
      const updatedSchedule = { ...mockSchedule, active_days: [0, 1, 2, 3, 4, 5, 6] };
      (updateSchedule as jest.Mock).mockResolvedValue(updatedSchedule);

      const response = await request(app)
        .put('/users/me/schedule')
        .send({ activeDays: [0, 1, 2, 3, 4, 5, 6] })
        .expect(200);

      expect(response.body.success).toBe(true);
    });

    it('should return 400 for invalid hour (> 23)', async () => {
      const response = await request(app)
        .put('/users/me/schedule')
        .send({ windowStartHour: 24 })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for invalid hour (< 0)', async () => {
      const response = await request(app)
        .put('/users/me/schedule')
        .send({ windowStartHour: -1 })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for invalid minute (> 59)', async () => {
      const response = await request(app)
        .put('/users/me/schedule')
        .send({ windowStartMinute: 60 })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for invalid active days (> 6)', async () => {
      const response = await request(app)
        .put('/users/me/schedule')
        .send({ activeDays: [0, 1, 7] })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for grace period too large (> 240)', async () => {
      const response = await request(app)
        .put('/users/me/schedule')
        .send({ gracePeriodMinutes: 241 })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for reminder minutes too small (< 5)', async () => {
      const response = await request(app)
        .put('/users/me/schedule')
        .send({ reminderMinutesBefore: 4 })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for reminder minutes too large (> 120)', async () => {
      const response = await request(app)
        .put('/users/me/schedule')
        .send({ reminderMinutesBefore: 121 })
        .expect(400);

      expect(response.body.success).toBe(false);
    });
  });

  // ===========================================================================
  // POST /users/me/push-token - Register Push Token
  // ===========================================================================
  describe('POST /users/me/push-token', () => {
    it('should register iOS push token successfully', async () => {
      (savePushToken as jest.Mock).mockResolvedValue(undefined);

      const response = await request(app)
        .post('/users/me/push-token')
        .send({
          token: 'apns-token-123456',
          platform: 'ios',
          deviceId: 'device-uuid',
        })
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(savePushToken).toHaveBeenCalledWith(
        'test-user-id',
        'apns-token-123456',
        'ios',
        'device-uuid'
      );
    });

    it('should register Android push token successfully', async () => {
      (savePushToken as jest.Mock).mockResolvedValue(undefined);

      const response = await request(app)
        .post('/users/me/push-token')
        .send({
          token: 'fcm-token-123456',
          platform: 'android',
        })
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(savePushToken).toHaveBeenCalledWith(
        'test-user-id',
        'fcm-token-123456',
        'android',
        undefined
      );
    });

    it('should return 400 for missing token', async () => {
      const response = await request(app)
        .post('/users/me/push-token')
        .send({ platform: 'ios' })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for empty token', async () => {
      const response = await request(app)
        .post('/users/me/push-token')
        .send({ token: '', platform: 'ios' })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for missing platform', async () => {
      const response = await request(app)
        .post('/users/me/push-token')
        .send({ token: 'some-token' })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for invalid platform', async () => {
      const response = await request(app)
        .post('/users/me/push-token')
        .send({ token: 'some-token', platform: 'windows' })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 on database error', async () => {
      (savePushToken as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .post('/users/me/push-token')
        .send({ token: 'some-token', platform: 'ios' })
        .expect(400);

      expect(response.body.success).toBe(false);
    });
  });

  // ===========================================================================
  // DELETE /users/me/push-token - Remove Push Token
  // ===========================================================================
  describe('DELETE /users/me/push-token', () => {
    it('should delete push token successfully', async () => {
      (deletePushToken as jest.Mock).mockResolvedValue(undefined);

      const response = await request(app)
        .delete('/users/me/push-token')
        .send({ token: 'apns-token-123456' })
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(deletePushToken).toHaveBeenCalledWith('test-user-id', 'apns-token-123456');
    });

    it('should return 400 for missing token', async () => {
      const response = await request(app)
        .delete('/users/me/push-token')
        .send({})
        .expect(400);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Token is required');
    });

    it('should return 500 on database error', async () => {
      (deletePushToken as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .delete('/users/me/push-token')
        .send({ token: 'some-token' })
        .expect(500);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Failed to delete push token');
    });
  });

  // ===========================================================================
  // DELETE /users/me - Delete Account
  // ===========================================================================
  describe('DELETE /users/me', () => {
    it('should schedule account deletion successfully', async () => {
      (deleteUserRefreshTokens as jest.Mock).mockResolvedValue(undefined);

      const response = await request(app)
        .delete('/users/me')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.message).toContain('scheduled for deletion');
      expect(deleteUserRefreshTokens).toHaveBeenCalledWith('test-user-id');
    });

    it('should return 500 on database error', async () => {
      (deleteUserRefreshTokens as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .delete('/users/me')
        .expect(500);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Failed to delete account');
    });
  });

  // ===========================================================================
  // GET /users/:userId - Get User By ID (public profile)
  // ===========================================================================
  describe('GET /users/:userId', () => {
    it('should return public user profile', async () => {
      (getUserById as jest.Mock).mockResolvedValue(mockUser);

      const response = await request(app)
        .get('/users/other-user-id')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.user.id).toBe('test-user-id');
      expect(response.body.user.name).toBe('Test User');
      expect(response.body.user.profileImageUrl).toBe('https://cdn.example.com/avatar.jpg');
      // Should not include private fields
      expect(response.body.user.email).toBeUndefined();
      expect(response.body.user.phone).toBeUndefined();
      expect(response.body.user.address).toBeUndefined();
    });

    it('should return 404 for non-existent user', async () => {
      (getUserById as jest.Mock).mockResolvedValue(null);

      const response = await request(app)
        .get('/users/non-existent-id')
        .expect(404);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('User not found');
    });

    it('should return 500 on database error', async () => {
      (getUserById as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .get('/users/some-user-id')
        .expect(500);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Failed to get user');
    });
  });
});
