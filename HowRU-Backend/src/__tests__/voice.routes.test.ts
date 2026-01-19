import express, { Express } from 'express';
import request from 'supertest';

// Mock the database
jest.mock('../db/index.js', () => ({
  sql: jest.fn(),
  getUserById: jest.fn(),
}));

// Mock Twilio (for VoiceResponse)
const mockVoiceResponse = {
  say: jest.fn().mockReturnThis(),
  pause: jest.fn().mockReturnThis(),
  gather: jest.fn().mockReturnValue({
    say: jest.fn().mockReturnThis(),
  }),
  redirect: jest.fn().mockReturnThis(),
  hangup: jest.fn().mockReturnThis(),
  toString: jest.fn().mockReturnValue('<?xml version="1.0" encoding="UTF-8"?><Response></Response>'),
};

jest.mock('twilio', () => {
  return Object.assign(
    jest.fn().mockReturnValue({
      calls: {
        create: jest.fn(),
      },
    }),
    {
      twiml: {
        VoiceResponse: jest.fn().mockImplementation(() => mockVoiceResponse),
      },
    }
  );
});

import { sql, getUserById } from '../db/index.js';
import voiceRouter from '../routes/voice.js';

describe('Voice Routes', () => {
  let app: Express;

  const mockAlert = {
    id: 'alert-123',
    checker_id: 'checker-user-id',
    supporter_id: 'supporter-user-id',
    type: 'missed_checkin',
    status: 'triggered',
    missed_window_at: new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString(), // 2 hours ago
    triggered_at: new Date().toISOString(),
  };

  const mockChecker = {
    id: 'checker-user-id',
    name: 'John Doe',
    phone_number: '+15551234567',
    last_known_address: '123 Main St, City',
  };

  const mockSupporter = {
    id: 'supporter-user-id',
    phone_number: '+15559876543',
  };

  beforeEach(() => {
    app = express();
    app.use(express.json());
    app.use(express.urlencoded({ extended: true }));
    app.use('/voice', voiceRouter);
    jest.clearAllMocks();
    mockVoiceResponse.toString.mockReturnValue('<?xml version="1.0" encoding="UTF-8"?><Response></Response>');
  });

  // ===========================================================================
  // POST /voice/alert/:alertId - Alert Voice Call TwiML
  // ===========================================================================
  describe('POST /voice/alert/:alertId', () => {
    it('should return TwiML for valid alert', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockAlert]);
      (getUserById as jest.Mock).mockResolvedValue(mockChecker);

      const response = await request(app)
        .post('/voice/alert/alert-123')
        .expect('Content-Type', /xml/)
        .expect(200);

      expect(response.text).toContain('Response');
      expect(mockVoiceResponse.say).toHaveBeenCalledWith(
        { voice: 'Polly.Joanna' },
        'This is an urgent wellness alert from How Are You.'
      );
      expect(mockVoiceResponse.gather).toHaveBeenCalled();
    });

    it('should include checker name in alert message', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockAlert]);
      (getUserById as jest.Mock).mockResolvedValue(mockChecker);

      await request(app)
        .post('/voice/alert/alert-123')
        .expect(200);

      expect(mockVoiceResponse.say).toHaveBeenCalledWith(
        { voice: 'Polly.Joanna' },
        expect.stringContaining('John Doe')
      );
    });

    it('should calculate hours since missed check-in', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockAlert]);
      (getUserById as jest.Mock).mockResolvedValue(mockChecker);

      await request(app)
        .post('/voice/alert/alert-123')
        .expect(200);

      expect(mockVoiceResponse.say).toHaveBeenCalledWith(
        { voice: 'Polly.Joanna' },
        expect.stringContaining('2 hours')
      );
    });

    it('should provide DTMF options', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockAlert]);
      (getUserById as jest.Mock).mockResolvedValue(mockChecker);

      await request(app)
        .post('/voice/alert/alert-123')
        .expect(200);

      expect(mockVoiceResponse.gather).toHaveBeenCalledWith({
        numDigits: 1,
        action: '/voice/response/alert-123',
        timeout: 10,
      });
    });

    it('should redirect to repeat message on no input', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockAlert]);
      (getUserById as jest.Mock).mockResolvedValue(mockChecker);

      await request(app)
        .post('/voice/alert/alert-123')
        .expect(200);

      expect(mockVoiceResponse.redirect).toHaveBeenCalledWith('/voice/alert/alert-123');
    });

    it('should handle inactive/non-existent alert', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);

      await request(app)
        .post('/voice/alert/non-existent')
        .expect(200);

      expect(mockVoiceResponse.say).toHaveBeenCalledWith(
        { voice: 'Polly.Joanna' },
        'Sorry, this alert is no longer active. Goodbye.'
      );
      expect(mockVoiceResponse.hangup).toHaveBeenCalled();
    });

    it('should use fallback when checker name not available', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockAlert]);
      (getUserById as jest.Mock).mockResolvedValue(null);

      await request(app)
        .post('/voice/alert/alert-123')
        .expect(200);

      expect(mockVoiceResponse.say).toHaveBeenCalledWith(
        { voice: 'Polly.Joanna' },
        expect.stringContaining('Your loved one')
      );
    });

    it('should return TwiML on database error', async () => {
      (sql as unknown as jest.Mock).mockRejectedValue(new Error('DB error'));

      await request(app)
        .post('/voice/alert/alert-123')
        .expect(200);

      expect(mockVoiceResponse.say).toHaveBeenCalledWith(
        { voice: 'Polly.Joanna' },
        'An error occurred. Please try again later.'
      );
      expect(mockVoiceResponse.hangup).toHaveBeenCalled();
    });
  });

  // ===========================================================================
  // POST /voice/response/:alertId - DTMF Response Handler
  // ===========================================================================
  describe('POST /voice/response/:alertId', () => {
    it('should acknowledge alert on digit 1', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockAlert]); // Get alert
      (getUserById as jest.Mock).mockResolvedValue(mockChecker);
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockSupporter]); // Get supporter by phone
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]); // Update alert
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]); // Log call

      await request(app)
        .post('/voice/response/alert-123')
        .send({ Digits: '1', Called: '+15559876543', CallSid: 'call-sid-123' })
        .expect(200);

      expect(mockVoiceResponse.say).toHaveBeenCalledWith(
        { voice: 'Polly.Joanna' },
        expect.stringContaining('acknowledged')
      );
      expect(mockVoiceResponse.hangup).toHaveBeenCalled();
    });

    it('should log call when acknowledging', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockAlert]);
      (getUserById as jest.Mock).mockResolvedValue(mockChecker);
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockSupporter]);
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);

      await request(app)
        .post('/voice/response/alert-123')
        .send({ Digits: '1', Called: '+15559876543', CallSid: 'call-sid-123' })
        .expect(200);

      // Verify call log was inserted (4th SQL call)
      expect(sql).toHaveBeenCalled();
    });

    it('should read contact information on digit 2', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockAlert]);
      (getUserById as jest.Mock).mockResolvedValue(mockChecker);

      await request(app)
        .post('/voice/response/alert-123')
        .send({ Digits: '2', Called: '+15559876543' })
        .expect(200);

      // Should say phone number
      expect(mockVoiceResponse.say).toHaveBeenCalledWith(
        { voice: 'Polly.Joanna' },
        expect.stringContaining('phone number')
      );
      // Should redirect back to main menu
      expect(mockVoiceResponse.redirect).toHaveBeenCalledWith('/voice/alert/alert-123');
    });

    it('should include last known location when available', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockAlert]);
      (getUserById as jest.Mock).mockResolvedValue(mockChecker);

      await request(app)
        .post('/voice/response/alert-123')
        .send({ Digits: '2', Called: '+15559876543' })
        .expect(200);

      expect(mockVoiceResponse.say).toHaveBeenCalledWith(
        { voice: 'Polly.Joanna' },
        expect.stringContaining('last known location')
      );
    });

    it('should handle missing contact information', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockAlert]);
      (getUserById as jest.Mock).mockResolvedValue(null);

      await request(app)
        .post('/voice/response/alert-123')
        .send({ Digits: '2', Called: '+15559876543' })
        .expect(200);

      expect(mockVoiceResponse.say).toHaveBeenCalledWith(
        { voice: 'Polly.Joanna' },
        'Contact information is not available.'
      );
    });

    it('should repeat message on digit 9', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockAlert]);
      (getUserById as jest.Mock).mockResolvedValue(mockChecker);

      await request(app)
        .post('/voice/response/alert-123')
        .send({ Digits: '9', Called: '+15559876543' })
        .expect(200);

      expect(mockVoiceResponse.redirect).toHaveBeenCalledWith('/voice/alert/alert-123');
    });

    it('should repeat message on unknown digit', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockAlert]);
      (getUserById as jest.Mock).mockResolvedValue(mockChecker);

      await request(app)
        .post('/voice/response/alert-123')
        .send({ Digits: '5', Called: '+15559876543' })
        .expect(200);

      expect(mockVoiceResponse.redirect).toHaveBeenCalledWith('/voice/alert/alert-123');
    });

    it('should return error TwiML on database error', async () => {
      (sql as unknown as jest.Mock).mockRejectedValue(new Error('DB error'));

      await request(app)
        .post('/voice/response/alert-123')
        .send({ Digits: '1', Called: '+15559876543' })
        .expect(200);

      expect(mockVoiceResponse.say).toHaveBeenCalledWith(
        { voice: 'Polly.Joanna' },
        'An error occurred. Please try again later.'
      );
      expect(mockVoiceResponse.hangup).toHaveBeenCalled();
    });
  });

  // ===========================================================================
  // POST /voice/status/:alertId - Call Status Webhook
  // ===========================================================================
  describe('POST /voice/status/:alertId', () => {
    it('should log call status successfully', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockSupporter]); // Get supporter
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]); // Insert/update log

      const response = await request(app)
        .post('/voice/status/alert-123')
        .send({
          CallSid: 'call-sid-123',
          CallStatus: 'completed',
          CallDuration: '45',
          Called: '+15559876543',
        })
        .expect(200);

      expect(response.body.received).toBe(true);
    });

    it('should log ringing status', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockSupporter]);
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);

      const response = await request(app)
        .post('/voice/status/alert-123')
        .send({
          CallSid: 'call-sid-123',
          CallStatus: 'ringing',
          Called: '+15559876543',
        })
        .expect(200);

      expect(response.body.received).toBe(true);
    });

    it('should log answered status', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockSupporter]);
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);

      const response = await request(app)
        .post('/voice/status/alert-123')
        .send({
          CallSid: 'call-sid-123',
          CallStatus: 'answered',
          Called: '+15559876543',
        })
        .expect(200);

      expect(response.body.received).toBe(true);
    });

    it('should handle unknown phone number', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]); // No supporter found
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);

      const response = await request(app)
        .post('/voice/status/alert-123')
        .send({
          CallSid: 'call-sid-123',
          CallStatus: 'completed',
          Called: '+15550000000',
        })
        .expect(200);

      expect(response.body.received).toBe(true);
    });

    it('should handle missing duration', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockSupporter]);
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);

      const response = await request(app)
        .post('/voice/status/alert-123')
        .send({
          CallSid: 'call-sid-123',
          CallStatus: 'no-answer',
          Called: '+15559876543',
        })
        .expect(200);

      expect(response.body.received).toBe(true);
    });

    it('should return success even on database error', async () => {
      (sql as unknown as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .post('/voice/status/alert-123')
        .send({
          CallSid: 'call-sid-123',
          CallStatus: 'completed',
          Called: '+15559876543',
        })
        .expect(200);

      expect(response.body.received).toBe(true);
      expect(response.body.error).toBe('Failed to process status');
    });

    it('should log failed call status', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockSupporter]);
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);

      const response = await request(app)
        .post('/voice/status/alert-123')
        .send({
          CallSid: 'call-sid-123',
          CallStatus: 'failed',
          Called: '+15559876543',
        })
        .expect(200);

      expect(response.body.received).toBe(true);
    });

    it('should log busy call status', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockSupporter]);
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]);

      const response = await request(app)
        .post('/voice/status/alert-123')
        .send({
          CallSid: 'call-sid-123',
          CallStatus: 'busy',
          Called: '+15559876543',
        })
        .expect(200);

      expect(response.body.received).toBe(true);
    });
  });

  // ===========================================================================
  // Phone Number Formatting Tests
  // ===========================================================================
  describe('Phone Number Formatting for Speech', () => {
    it('should format phone number with spaces for speech', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockAlert]);
      (getUserById as jest.Mock).mockResolvedValue({
        ...mockChecker,
        phone_number: '+15551234567',
      });

      await request(app)
        .post('/voice/response/alert-123')
        .send({ Digits: '2', Called: '+15559876543' })
        .expect(200);

      // The say call should include formatted phone number
      expect(mockVoiceResponse.say).toHaveBeenCalled();
    });

    it('should handle phone without location gracefully', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([mockAlert]);
      (getUserById as jest.Mock).mockResolvedValue({
        ...mockChecker,
        last_known_address: null,
      });

      await request(app)
        .post('/voice/response/alert-123')
        .send({ Digits: '2', Called: '+15559876543' })
        .expect(200);

      // Should still provide phone number
      expect(mockVoiceResponse.say).toHaveBeenCalledWith(
        { voice: 'Polly.Joanna' },
        expect.stringContaining('phone number')
      );
    });
  });
});
