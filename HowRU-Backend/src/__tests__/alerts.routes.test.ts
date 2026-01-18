import express, { Express } from 'express';
import request from 'supertest';

// Mock the database
jest.mock('../db/index.js', () => ({
  getActiveAlerts: jest.fn(),
  getAlertsForSupporter: jest.fn(),
  acknowledgeAlert: jest.fn(),
  resolveAlert: jest.fn(),
  createAlert: jest.fn(),
  getUserById: jest.fn(),
  getCircleLinks: jest.fn(),
  getRecentCheckIns: jest.fn(),
}));

// Mock Resend email service
jest.mock('../services/resend.js', () => ({
  sendAlertEmail: jest.fn().mockResolvedValue(true),
}));

// Mock Twilio SMS service
jest.mock('../services/twilio.js', () => ({
  sendAlertSMS: jest.fn().mockResolvedValue(true),
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
  getActiveAlerts,
  getAlertsForSupporter,
  acknowledgeAlert,
  resolveAlert,
  createAlert,
  getUserById,
  getCircleLinks,
  getRecentCheckIns,
} from '../db/index.js';
import { sendAlertEmail } from '../services/resend.js';
import { sendAlertSMS } from '../services/twilio.js';
import alertsRouter from '../routes/alerts.js';

describe('Alerts Routes', () => {
  let app: Express;

  beforeEach(() => {
    app = express();
    app.use(express.json());
    app.use('/alerts', alertsRouter);
    jest.clearAllMocks();
  });

  // ===========================================================================
  // GET /alerts/mine - Get My Active Alerts
  // ===========================================================================
  describe('GET /alerts/mine', () => {
    const mockAlerts = [
      {
        id: 'alert-1',
        type: 'soft',
        status: 'active',
        triggered_at: '2024-01-15T10:00:00Z',
        missed_window_at: '2024-01-15T09:00:00Z',
        last_checkin_at: '2024-01-14T08:00:00Z',
        last_known_location: 'New York',
        acknowledged_at: null,
      },
    ];

    it('should return user\'s active alerts', async () => {
      (getActiveAlerts as jest.Mock).mockResolvedValue(mockAlerts);

      const response = await request(app)
        .get('/alerts/mine')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.alerts).toHaveLength(1);
      expect(response.body.alerts[0].id).toBe('alert-1');
      expect(response.body.alerts[0].type).toBe('soft');
      expect(response.body.alerts[0].status).toBe('active');
    });

    it('should return empty array when no alerts', async () => {
      (getActiveAlerts as jest.Mock).mockResolvedValue([]);

      const response = await request(app)
        .get('/alerts/mine')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.alerts).toHaveLength(0);
    });

    it('should handle database errors gracefully', async () => {
      (getActiveAlerts as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .get('/alerts/mine')
        .expect(500);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Failed to get alerts');
    });
  });

  // ===========================================================================
  // GET /alerts - Get Alerts for People I'm Supporting
  // ===========================================================================
  describe('GET /alerts', () => {
    const mockAlerts = [
      {
        id: 'alert-1',
        checker_id: 'checker-1',
        checker_name: 'John Doe',
        type: 'hard',
        status: 'active',
        triggered_at: '2024-01-15T10:00:00Z',
        missed_window_at: '2024-01-15T09:00:00Z',
        last_checkin_at: '2024-01-14T08:00:00Z',
        last_known_location: 'New York',
        last_known_address: null,
        acknowledged_at: null,
        acknowledged_by: null,
      },
    ];

    it('should return alerts for supported users', async () => {
      (getAlertsForSupporter as jest.Mock).mockResolvedValue(mockAlerts);

      const response = await request(app)
        .get('/alerts')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.alerts).toHaveLength(1);
      expect(response.body.alerts[0].checkerId).toBe('checker-1');
      expect(response.body.alerts[0].checkerName).toBe('John Doe');
    });

    it('should use last_known_address as fallback for location', async () => {
      const alertWithAddress = {
        ...mockAlerts[0],
        last_known_location: null,
        last_known_address: '123 Main St',
      };
      (getAlertsForSupporter as jest.Mock).mockResolvedValue([alertWithAddress]);

      const response = await request(app)
        .get('/alerts')
        .expect(200);

      expect(response.body.alerts[0].lastKnownLocation).toBe('123 Main St');
    });

    it('should return empty array when no alerts', async () => {
      (getAlertsForSupporter as jest.Mock).mockResolvedValue([]);

      const response = await request(app)
        .get('/alerts')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.alerts).toHaveLength(0);
    });

    it('should handle database errors gracefully', async () => {
      (getAlertsForSupporter as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .get('/alerts')
        .expect(500);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Failed to get alerts');
    });
  });

  // ===========================================================================
  // POST /alerts/:alertId/acknowledge - Acknowledge Alert
  // ===========================================================================
  describe('POST /alerts/:alertId/acknowledge', () => {
    it('should acknowledge an alert', async () => {
      (acknowledgeAlert as jest.Mock).mockResolvedValue({
        id: 'alert-1',
        acknowledged_at: '2024-01-15T12:00:00Z',
      });

      const response = await request(app)
        .post('/alerts/alert-1/acknowledge')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.alert.id).toBe('alert-1');
      expect(response.body.alert.acknowledgedAt).toBeDefined();
      expect(acknowledgeAlert).toHaveBeenCalledWith('alert-1', 'user-123');
    });

    it('should return 404 when alert not found', async () => {
      (acknowledgeAlert as jest.Mock).mockResolvedValue(null);

      const response = await request(app)
        .post('/alerts/nonexistent/acknowledge')
        .expect(404);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Alert not found or already acknowledged');
    });

    it('should handle database errors gracefully', async () => {
      (acknowledgeAlert as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .post('/alerts/alert-1/acknowledge')
        .expect(500);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Failed to acknowledge alert');
    });
  });

  // ===========================================================================
  // POST /alerts/:alertId/resolve - Resolve Alert
  // ===========================================================================
  describe('POST /alerts/:alertId/resolve', () => {
    const validResolveData = {
      resolution: 'checked_in',
      notes: 'Confirmed safe via call',
    };

    it('should resolve an alert', async () => {
      (resolveAlert as jest.Mock).mockResolvedValue({
        id: 'alert-1',
        status: 'resolved',
        resolved_at: '2024-01-15T12:00:00Z',
        resolution: 'checked_in',
      });

      const response = await request(app)
        .post('/alerts/alert-1/resolve')
        .send(validResolveData)
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.alert.status).toBe('resolved');
      expect(response.body.alert.resolution).toBe('checked_in');
      expect(resolveAlert).toHaveBeenCalledWith(
        'alert-1',
        'user-123',
        'checked_in',
        'Confirmed safe via call'
      );
    });

    it('should resolve alert without notes', async () => {
      (resolveAlert as jest.Mock).mockResolvedValue({
        id: 'alert-1',
        status: 'resolved',
        resolved_at: '2024-01-15T12:00:00Z',
        resolution: 'safe_confirmed',
      });

      const response = await request(app)
        .post('/alerts/alert-1/resolve')
        .send({ resolution: 'safe_confirmed' })
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(resolveAlert).toHaveBeenCalledWith(
        'alert-1',
        'user-123',
        'safe_confirmed',
        undefined
      );
    });

    it('should return 404 when alert not found', async () => {
      (resolveAlert as jest.Mock).mockResolvedValue(null);

      const response = await request(app)
        .post('/alerts/nonexistent/resolve')
        .send(validResolveData)
        .expect(404);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Alert not found');
    });

    it('should return 400 for invalid resolution type', async () => {
      const response = await request(app)
        .post('/alerts/alert-1/resolve')
        .send({ resolution: 'invalid_type' })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for notes exceeding max length', async () => {
      const response = await request(app)
        .post('/alerts/alert-1/resolve')
        .send({ resolution: 'other', notes: 'A'.repeat(501) })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should accept all valid resolution types', async () => {
      const resolutionTypes = ['checked_in', 'contacted', 'safe_confirmed', 'false_alarm', 'other'];

      for (const resolution of resolutionTypes) {
        (resolveAlert as jest.Mock).mockResolvedValue({
          id: 'alert-1',
          status: 'resolved',
          resolved_at: new Date().toISOString(),
          resolution,
        });

        const response = await request(app)
          .post('/alerts/alert-1/resolve')
          .send({ resolution })
          .expect(200);

        expect(response.body.success).toBe(true);
      }
    });
  });

  // ===========================================================================
  // POST /alerts/trigger - Trigger Alert
  // ===========================================================================
  describe('POST /alerts/trigger', () => {
    const validTriggerData = {
      checkerId: '11111111-1111-1111-1111-111111111111',
      type: 'soft',
    };

    const mockChecker = {
      id: '11111111-1111-1111-1111-111111111111',
      name: 'John Doe',
      last_known_address: 'New York',
      phone_number: '+15551234567',
    };

    const mockCheckIn = {
      timestamp: '2024-01-14T08:00:00Z',
      mental_score: 4,
      body_score: 3,
      mood_score: 5,
    };

    const mockCircle = [
      {
        supporter_id: 'supporter-1',
        supporter_display_name: 'Alice',
        is_active: true,
        alert_via_email: true,
        alert_via_sms: true,
        supporter_email: 'alice@example.com',
        supporter_phone: '+15559876543',
      },
    ];

    beforeEach(() => {
      (getUserById as jest.Mock).mockResolvedValue(mockChecker);
      (getRecentCheckIns as jest.Mock).mockResolvedValue([mockCheckIn]);
      (getCircleLinks as jest.Mock).mockResolvedValue(mockCircle);
      (createAlert as jest.Mock).mockResolvedValue({
        id: 'alert-1',
        type: 'soft',
        triggered_at: new Date().toISOString(),
      });
    });

    it('should trigger an alert', async () => {
      const response = await request(app)
        .post('/alerts/trigger')
        .send(validTriggerData)
        .expect(201);

      expect(response.body.success).toBe(true);
      expect(response.body.alert.id).toBe('alert-1');
      expect(response.body.alert.type).toBe('soft');
      expect(createAlert).toHaveBeenCalled();
    });

    it('should return 404 when checker not found', async () => {
      (getUserById as jest.Mock).mockResolvedValue(null);

      const response = await request(app)
        .post('/alerts/trigger')
        .send(validTriggerData)
        .expect(404);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Checker not found');
    });

    it('should send email notifications to supporters', async () => {
      const supporterWithEmail = {
        ...mockCircle[0],
        alert_via_email: true,
        alert_via_sms: false,
      };
      (getCircleLinks as jest.Mock).mockResolvedValue([supporterWithEmail]);
      (getUserById as jest.Mock)
        .mockResolvedValueOnce(mockChecker)
        .mockResolvedValueOnce({ email: 'supporter@example.com', name: 'Supporter' });

      await request(app)
        .post('/alerts/trigger')
        .send(validTriggerData)
        .expect(201);

      expect(sendAlertEmail).toHaveBeenCalled();
    });

    it('should send SMS notifications for non-reminder alerts', async () => {
      const supporterWithSMS = {
        ...mockCircle[0],
        alert_via_email: false,
        alert_via_sms: true,
      };
      (getCircleLinks as jest.Mock).mockResolvedValue([supporterWithSMS]);
      (getUserById as jest.Mock)
        .mockResolvedValueOnce(mockChecker)
        .mockResolvedValueOnce({ phone_number: '+15551111111' });

      await request(app)
        .post('/alerts/trigger')
        .send({ checkerId: validTriggerData.checkerId, type: 'hard' })
        .expect(201);

      expect(sendAlertSMS).toHaveBeenCalled();
    });

    it('should NOT send SMS for reminder alerts', async () => {
      const supporterWithSMS = {
        ...mockCircle[0],
        alert_via_sms: true,
      };
      (getCircleLinks as jest.Mock).mockResolvedValue([supporterWithSMS]);
      (getUserById as jest.Mock)
        .mockResolvedValueOnce(mockChecker)
        .mockResolvedValueOnce({ phone_number: '+15551111111' });

      await request(app)
        .post('/alerts/trigger')
        .send({ checkerId: validTriggerData.checkerId, type: 'reminder' })
        .expect(201);

      expect(sendAlertSMS).not.toHaveBeenCalled();
    });

    it('should skip inactive supporters', async () => {
      const inactiveSupporter = {
        ...mockCircle[0],
        is_active: false,
      };
      (getCircleLinks as jest.Mock).mockResolvedValue([inactiveSupporter]);

      await request(app)
        .post('/alerts/trigger')
        .send(validTriggerData)
        .expect(201);

      expect(sendAlertEmail).not.toHaveBeenCalled();
      expect(sendAlertSMS).not.toHaveBeenCalled();
    });

    it('should handle alert without previous check-in', async () => {
      (getRecentCheckIns as jest.Mock).mockResolvedValue([]);

      const response = await request(app)
        .post('/alerts/trigger')
        .send(validTriggerData)
        .expect(201);

      expect(response.body.success).toBe(true);
      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({ lastCheckinAt: undefined })
      );
    });

    it('should return 400 for invalid alert type', async () => {
      const response = await request(app)
        .post('/alerts/trigger')
        .send({ checkerId: validTriggerData.checkerId, type: 'invalid' })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for invalid checker ID format', async () => {
      const response = await request(app)
        .post('/alerts/trigger')
        .send({ checkerId: 'not-a-uuid', type: 'soft' })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should accept all valid alert types', async () => {
      const alertTypes = ['reminder', 'soft', 'hard', 'escalation'];

      for (const type of alertTypes) {
        jest.clearAllMocks();
        (getUserById as jest.Mock).mockResolvedValue(mockChecker);
        (getRecentCheckIns as jest.Mock).mockResolvedValue([mockCheckIn]);
        (getCircleLinks as jest.Mock).mockResolvedValue([]);
        (createAlert as jest.Mock).mockResolvedValue({
          id: 'alert-1',
          type,
          triggered_at: new Date().toISOString(),
        });

        const response = await request(app)
          .post('/alerts/trigger')
          .send({ checkerId: validTriggerData.checkerId, type })
          .expect(201);

        expect(response.body.success).toBe(true);
        expect(response.body.alert.type).toBe(type);
      }
    });

    it('should continue sending notifications even if one fails', async () => {
      const twoSupporters = [
        { ...mockCircle[0], supporter_id: 's1', alert_via_email: true },
        { ...mockCircle[0], supporter_id: 's2', alert_via_email: true },
      ];
      (getCircleLinks as jest.Mock).mockResolvedValue(twoSupporters);
      (getUserById as jest.Mock)
        .mockResolvedValueOnce(mockChecker)
        .mockResolvedValueOnce({ email: 'first@example.com' })
        .mockResolvedValueOnce({ email: 'second@example.com' });

      // First email fails, second succeeds
      (sendAlertEmail as jest.Mock)
        .mockRejectedValueOnce(new Error('Email failed'))
        .mockResolvedValueOnce(true);

      const response = await request(app)
        .post('/alerts/trigger')
        .send(validTriggerData)
        .expect(201);

      expect(response.body.success).toBe(true);
      expect(sendAlertEmail).toHaveBeenCalledTimes(2);
    });

    it('should use supporter email/phone when user not found', async () => {
      const supporterNoUserId = {
        ...mockCircle[0],
        supporter_id: null,
        supporter_email: 'fallback@example.com',
        supporter_phone: '+15550000000',
        alert_via_email: true,
        alert_via_sms: true,
      };
      (getCircleLinks as jest.Mock).mockResolvedValue([supporterNoUserId]);

      await request(app)
        .post('/alerts/trigger')
        .send({ checkerId: validTriggerData.checkerId, type: 'hard' })
        .expect(201);

      expect(sendAlertEmail).toHaveBeenCalledWith(
        expect.objectContaining({ to: 'fallback@example.com' })
      );
      expect(sendAlertSMS).toHaveBeenCalledWith(
        expect.objectContaining({ to: '+15550000000' })
      );
    });
  });
});
