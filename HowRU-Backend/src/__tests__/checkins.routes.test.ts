import express, { Express } from 'express';
import request from 'supertest';

// Mock the database
jest.mock('../db/index.js', () => ({
  createCheckIn: jest.fn(),
  getTodayCheckIn: jest.fn(),
  getRecentCheckIns: jest.fn(),
  resolveAlerts: jest.fn(),
  getActiveSchedule: jest.fn(),
}));

// Mock auth middleware
jest.mock('../middleware/auth.js', () => ({
  authMiddleware: (req: any, res: any, next: any) => {
    req.userId = 'user-123';
    next();
  },
  AuthRequest: {},
}));

import {
  createCheckIn,
  getTodayCheckIn,
  getRecentCheckIns,
  resolveAlerts,
  getActiveSchedule,
} from '../db/index.js';
import checkinsRouter from '../routes/checkins.js';

describe('Check-Ins Routes', () => {
  let app: Express;

  beforeEach(() => {
    app = express();
    app.use(express.json());
    app.use('/checkins', checkinsRouter);
    jest.clearAllMocks();
  });

  // ===========================================================================
  // POST /checkins - Create Check-In
  // ===========================================================================
  describe('POST /checkins', () => {
    const validCheckInData = {
      mentalScore: 4,
      bodyScore: 3,
      moodScore: 5,
    };

    const mockCreatedCheckIn = {
      id: 'checkin-123',
      timestamp: new Date().toISOString(),
      mental_score: 4,
      body_score: 3,
      mood_score: 5,
      latitude: null,
      longitude: null,
      location_name: null,
      address: null,
      is_manual: true,
    };

    it('should create a check-in successfully', async () => {
      (createCheckIn as jest.Mock).mockResolvedValue(mockCreatedCheckIn);
      (resolveAlerts as jest.Mock).mockResolvedValue(undefined);

      const response = await request(app)
        .post('/checkins')
        .send(validCheckInData)
        .expect(201);

      expect(response.body.success).toBe(true);
      expect(response.body.checkIn.id).toBe('checkin-123');
      expect(response.body.checkIn.mentalScore).toBe(4);
      expect(response.body.checkIn.bodyScore).toBe(3);
      expect(response.body.checkIn.moodScore).toBe(5);
      expect(response.body.checkIn.averageScore).toBe(4);
      expect(createCheckIn).toHaveBeenCalledWith({
        userId: 'user-123',
        mentalScore: 4,
        bodyScore: 3,
        moodScore: 5,
        isManual: true,
      });
    });

    it('should create check-in with location data', async () => {
      const checkInWithLocation = {
        ...validCheckInData,
        latitude: 40.7128,
        longitude: -74.006,
        locationName: 'New York',
        address: '123 Main St, NY',
      };

      const mockCheckInWithLocation = {
        ...mockCreatedCheckIn,
        latitude: 40.7128,
        longitude: -74.006,
        location_name: 'New York',
        address: '123 Main St, NY',
      };

      (createCheckIn as jest.Mock).mockResolvedValue(mockCheckInWithLocation);
      (resolveAlerts as jest.Mock).mockResolvedValue(undefined);

      const response = await request(app)
        .post('/checkins')
        .send(checkInWithLocation)
        .expect(201);

      expect(response.body.checkIn.latitude).toBe(40.7128);
      expect(response.body.checkIn.longitude).toBe(-74.006);
      expect(response.body.checkIn.locationName).toBe('New York');
    });

    it('should resolve alerts after creating check-in', async () => {
      (createCheckIn as jest.Mock).mockResolvedValue(mockCreatedCheckIn);
      (resolveAlerts as jest.Mock).mockResolvedValue(undefined);

      await request(app)
        .post('/checkins')
        .send(validCheckInData)
        .expect(201);

      expect(resolveAlerts).toHaveBeenCalledWith('user-123');
    });

    it('should return 400 for missing mentalScore', async () => {
      const response = await request(app)
        .post('/checkins')
        .send({ bodyScore: 3, moodScore: 5 })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for invalid score (below 1)', async () => {
      const response = await request(app)
        .post('/checkins')
        .send({ mentalScore: 0, bodyScore: 3, moodScore: 5 })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for invalid score (above 5)', async () => {
      const response = await request(app)
        .post('/checkins')
        .send({ mentalScore: 6, bodyScore: 3, moodScore: 5 })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for non-integer score', async () => {
      const response = await request(app)
        .post('/checkins')
        .send({ mentalScore: 3.5, bodyScore: 3, moodScore: 5 })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should default isManual to true', async () => {
      (createCheckIn as jest.Mock).mockResolvedValue(mockCreatedCheckIn);
      (resolveAlerts as jest.Mock).mockResolvedValue(undefined);

      await request(app)
        .post('/checkins')
        .send(validCheckInData)
        .expect(201);

      expect(createCheckIn).toHaveBeenCalledWith(
        expect.objectContaining({ isManual: true })
      );
    });

    it('should allow setting isManual to false', async () => {
      (createCheckIn as jest.Mock).mockResolvedValue({
        ...mockCreatedCheckIn,
        is_manual: false,
      });
      (resolveAlerts as jest.Mock).mockResolvedValue(undefined);

      await request(app)
        .post('/checkins')
        .send({ ...validCheckInData, isManual: false })
        .expect(201);

      expect(createCheckIn).toHaveBeenCalledWith(
        expect.objectContaining({ isManual: false })
      );
    });

    it('should handle database errors gracefully', async () => {
      (createCheckIn as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .post('/checkins')
        .send(validCheckInData)
        .expect(400);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('DB error');
    });

    it('should return 400 for location name exceeding max length', async () => {
      const response = await request(app)
        .post('/checkins')
        .send({
          ...validCheckInData,
          locationName: 'A'.repeat(256),
        })
        .expect(400);

      expect(response.body.success).toBe(false);
    });
  });

  // ===========================================================================
  // GET /checkins/today - Get Today's Check-In
  // ===========================================================================
  describe('GET /checkins/today', () => {
    it('should return today\'s check-in when exists', async () => {
      const todayCheckIn = {
        id: 'checkin-today',
        timestamp: new Date().toISOString(),
        mental_score: 4,
        body_score: 3,
        mood_score: 5,
        latitude: 40.7128,
        longitude: -74.006,
        location_name: 'New York',
        selfie_url: null,
        selfie_expires_at: null,
      };

      (getActiveSchedule as jest.Mock).mockResolvedValue({
        timezone_identifier: 'America/New_York',
      });
      (getTodayCheckIn as jest.Mock).mockResolvedValue(todayCheckIn);

      const response = await request(app)
        .get('/checkins/today')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.hasCheckedInToday).toBe(true);
      expect(response.body.checkIn.id).toBe('checkin-today');
      expect(response.body.checkIn.mentalScore).toBe(4);
      expect(response.body.checkIn.averageScore).toBe(4);
    });

    it('should return null when no check-in today', async () => {
      (getActiveSchedule as jest.Mock).mockResolvedValue(null);
      (getTodayCheckIn as jest.Mock).mockResolvedValue(null);

      const response = await request(app)
        .get('/checkins/today')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.hasCheckedInToday).toBe(false);
      expect(response.body.checkIn).toBeNull();
    });

    it('should use UTC when no schedule exists', async () => {
      (getActiveSchedule as jest.Mock).mockResolvedValue(null);
      (getTodayCheckIn as jest.Mock).mockResolvedValue(null);

      await request(app)
        .get('/checkins/today')
        .expect(200);

      expect(getTodayCheckIn).toHaveBeenCalledWith('user-123', 'UTC');
    });

    it('should use user\'s timezone from schedule', async () => {
      (getActiveSchedule as jest.Mock).mockResolvedValue({
        timezone_identifier: 'America/Los_Angeles',
      });
      (getTodayCheckIn as jest.Mock).mockResolvedValue(null);

      await request(app)
        .get('/checkins/today')
        .expect(200);

      expect(getTodayCheckIn).toHaveBeenCalledWith('user-123', 'America/Los_Angeles');
    });

    it('should indicate hasSelfie correctly when selfie exists and not expired', async () => {
      const futureDate = new Date(Date.now() + 3600000).toISOString(); // 1 hour from now
      const checkInWithSelfie = {
        id: 'checkin-selfie',
        timestamp: new Date().toISOString(),
        mental_score: 4,
        body_score: 3,
        mood_score: 5,
        selfie_url: 'https://example.com/selfie.jpg',
        selfie_expires_at: futureDate,
      };

      (getActiveSchedule as jest.Mock).mockResolvedValue(null);
      (getTodayCheckIn as jest.Mock).mockResolvedValue(checkInWithSelfie);

      const response = await request(app)
        .get('/checkins/today')
        .expect(200);

      expect(response.body.checkIn.hasSelfie).toBe(true);
    });

    it('should indicate hasSelfie false when selfie is expired', async () => {
      const pastDate = new Date(Date.now() - 3600000).toISOString(); // 1 hour ago
      const checkInWithExpiredSelfie = {
        id: 'checkin-selfie',
        timestamp: new Date().toISOString(),
        mental_score: 4,
        body_score: 3,
        mood_score: 5,
        selfie_url: 'https://example.com/selfie.jpg',
        selfie_expires_at: pastDate,
      };

      (getActiveSchedule as jest.Mock).mockResolvedValue(null);
      (getTodayCheckIn as jest.Mock).mockResolvedValue(checkInWithExpiredSelfie);

      const response = await request(app)
        .get('/checkins/today')
        .expect(200);

      expect(response.body.checkIn.hasSelfie).toBe(false);
    });

    it('should handle database errors gracefully', async () => {
      (getActiveSchedule as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .get('/checkins/today')
        .expect(500);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Failed to get check-in');
    });
  });

  // ===========================================================================
  // GET /checkins - Get Check-In History
  // ===========================================================================
  describe('GET /checkins', () => {
    const mockCheckIns = [
      {
        id: 'checkin-1',
        timestamp: new Date().toISOString(),
        mental_score: 4,
        body_score: 3,
        mood_score: 5,
        location_name: 'New York',
        is_manual: true,
      },
      {
        id: 'checkin-2',
        timestamp: new Date(Date.now() - 86400000).toISOString(),
        mental_score: 3,
        body_score: 3,
        mood_score: 3,
        location_name: null,
        is_manual: false,
      },
    ];

    it('should return check-in history', async () => {
      (getRecentCheckIns as jest.Mock).mockResolvedValue(mockCheckIns);

      const response = await request(app)
        .get('/checkins')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.checkIns).toHaveLength(2);
      expect(response.body.checkIns[0].id).toBe('checkin-1');
      expect(response.body.checkIns[0].averageScore).toBe(4);
      expect(response.body.checkIns[1].averageScore).toBe(3);
    });

    it('should return empty array when no check-ins', async () => {
      (getRecentCheckIns as jest.Mock).mockResolvedValue([]);

      const response = await request(app)
        .get('/checkins')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.checkIns).toHaveLength(0);
    });

    it('should use default limit of 30', async () => {
      (getRecentCheckIns as jest.Mock).mockResolvedValue([]);

      await request(app)
        .get('/checkins')
        .expect(200);

      expect(getRecentCheckIns).toHaveBeenCalledWith('user-123', 30);
    });

    it('should respect custom limit', async () => {
      (getRecentCheckIns as jest.Mock).mockResolvedValue([]);

      await request(app)
        .get('/checkins?limit=50')
        .expect(200);

      expect(getRecentCheckIns).toHaveBeenCalledWith('user-123', 50);
    });

    it('should cap limit at 100', async () => {
      (getRecentCheckIns as jest.Mock).mockResolvedValue([]);

      await request(app)
        .get('/checkins?limit=500')
        .expect(200);

      expect(getRecentCheckIns).toHaveBeenCalledWith('user-123', 100);
    });

    it('should handle invalid limit gracefully', async () => {
      (getRecentCheckIns as jest.Mock).mockResolvedValue([]);

      await request(app)
        .get('/checkins?limit=invalid')
        .expect(200);

      // NaN becomes default
      expect(getRecentCheckIns).toHaveBeenCalledWith('user-123', 30);
    });

    it('should handle database errors gracefully', async () => {
      (getRecentCheckIns as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .get('/checkins')
        .expect(500);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Failed to get check-ins');
    });
  });

  // ===========================================================================
  // GET /checkins/stats - Get Check-In Stats
  // ===========================================================================
  describe('GET /checkins/stats', () => {
    it('should return stats for check-ins', async () => {
      const checkIns = [
        { mental_score: 4, body_score: 4, mood_score: 4, timestamp: new Date().toISOString() },
        { mental_score: 3, body_score: 3, mood_score: 3, timestamp: new Date(Date.now() - 86400000).toISOString() },
      ];
      (getRecentCheckIns as jest.Mock).mockResolvedValue(checkIns);

      const response = await request(app)
        .get('/checkins/stats')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.stats.totalCheckIns).toBe(2);
      expect(response.body.stats.averageMental).toBe(3.5);
      expect(response.body.stats.averageBody).toBe(3.5);
      expect(response.body.stats.averageMood).toBe(3.5);
      expect(response.body.stats.averageOverall).toBe(3.5);
    });

    it('should return zero stats when no check-ins', async () => {
      (getRecentCheckIns as jest.Mock).mockResolvedValue([]);

      const response = await request(app)
        .get('/checkins/stats')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.stats.totalCheckIns).toBe(0);
      expect(response.body.stats.averageMental).toBe(0);
      expect(response.body.stats.currentStreak).toBe(0);
    });

    it('should calculate current streak correctly', async () => {
      const today = new Date();
      today.setHours(12, 0, 0, 0);
      const yesterday = new Date(today);
      yesterday.setDate(yesterday.getDate() - 1);
      const twoDaysAgo = new Date(today);
      twoDaysAgo.setDate(twoDaysAgo.getDate() - 2);

      const checkIns = [
        { mental_score: 4, body_score: 4, mood_score: 4, timestamp: today.toISOString() },
        { mental_score: 3, body_score: 3, mood_score: 3, timestamp: yesterday.toISOString() },
        { mental_score: 5, body_score: 5, mood_score: 5, timestamp: twoDaysAgo.toISOString() },
      ];
      (getRecentCheckIns as jest.Mock).mockResolvedValue(checkIns);

      const response = await request(app)
        .get('/checkins/stats')
        .expect(200);

      expect(response.body.stats.currentStreak).toBe(3);
    });

    it('should break streak when a day is missed', async () => {
      const today = new Date();
      today.setHours(12, 0, 0, 0);
      // Skip yesterday
      const twoDaysAgo = new Date(today);
      twoDaysAgo.setDate(twoDaysAgo.getDate() - 2);

      const checkIns = [
        { mental_score: 4, body_score: 4, mood_score: 4, timestamp: today.toISOString() },
        // No check-in yesterday
        { mental_score: 5, body_score: 5, mood_score: 5, timestamp: twoDaysAgo.toISOString() },
      ];
      (getRecentCheckIns as jest.Mock).mockResolvedValue(checkIns);

      const response = await request(app)
        .get('/checkins/stats')
        .expect(200);

      expect(response.body.stats.currentStreak).toBe(1);
    });

    it('should use default days of 30', async () => {
      (getRecentCheckIns as jest.Mock).mockResolvedValue([]);

      await request(app)
        .get('/checkins/stats')
        .expect(200);

      expect(getRecentCheckIns).toHaveBeenCalledWith('user-123', 30);
    });

    it('should respect custom days parameter', async () => {
      (getRecentCheckIns as jest.Mock).mockResolvedValue([]);

      await request(app)
        .get('/checkins/stats?days=90')
        .expect(200);

      expect(getRecentCheckIns).toHaveBeenCalledWith('user-123', 90);
    });

    it('should cap days at 365', async () => {
      (getRecentCheckIns as jest.Mock).mockResolvedValue([]);

      await request(app)
        .get('/checkins/stats?days=1000')
        .expect(200);

      expect(getRecentCheckIns).toHaveBeenCalledWith('user-123', 365);
    });

    it('should round averages to one decimal place', async () => {
      const checkIns = [
        { mental_score: 4, body_score: 3, mood_score: 5, timestamp: new Date().toISOString() },
        { mental_score: 3, body_score: 4, mood_score: 2, timestamp: new Date().toISOString() },
        { mental_score: 5, body_score: 2, mood_score: 4, timestamp: new Date().toISOString() },
      ];
      (getRecentCheckIns as jest.Mock).mockResolvedValue(checkIns);

      const response = await request(app)
        .get('/checkins/stats')
        .expect(200);

      // (4+3+5)/3 = 4, (3+4+2)/3 = 3, (5+2+4)/3 = 3.67
      expect(response.body.stats.averageMental).toBe(4);
      expect(response.body.stats.averageBody).toBe(3);
      expect(response.body.stats.averageMood).toBe(3.7);
    });

    it('should handle database errors gracefully', async () => {
      (getRecentCheckIns as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .get('/checkins/stats')
        .expect(500);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Failed to get stats');
    });
  });
});
