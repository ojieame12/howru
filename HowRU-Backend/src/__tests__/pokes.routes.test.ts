import express, { Express, NextFunction, Response } from 'express';
import request from 'supertest';

// Mock the database
jest.mock('../db/index.js', () => ({
  createPoke: jest.fn(),
  getPokesForUser: jest.fn(),
  getUnseenPokesCount: jest.fn(),
  markPokeSeen: jest.fn(),
  markPokeResponded: jest.fn(),
  getSupportedUsers: jest.fn(),
  getCircleLinks: jest.fn(),
  getUserById: jest.fn(),
}));

// Mock Resend service
jest.mock('../services/resend.js', () => ({
  sendPokeEmail: jest.fn(),
}));

// Mock Twilio service
jest.mock('../services/twilio.js', () => ({
  sendPokeSMS: jest.fn(),
}));

// Mock auth middleware
jest.mock('../middleware/auth.js', () => ({
  authMiddleware: (req: any, _res: Response, next: NextFunction) => {
    req.userId = 'sender-user-id';
    next();
  },
  AuthRequest: {},
}));

import {
  createPoke,
  getPokesForUser,
  getUnseenPokesCount,
  markPokeSeen,
  markPokeResponded,
  getSupportedUsers,
  getCircleLinks,
  getUserById,
} from '../db/index.js';
import { sendPokeEmail } from '../services/resend.js';
import { sendPokeSMS } from '../services/twilio.js';
import pokesRouter from '../routes/pokes.js';

describe('Pokes Routes', () => {
  let app: Express;

  const mockSender = {
    id: 'sender-user-id',
    name: 'Sender User',
    phone_number: '+15551111111',
    email: 'sender@example.com',
  };

  const mockRecipient = {
    id: 'recipient-user-id',
    name: 'Recipient User',
    phone_number: '+15552222222',
    email: 'recipient@example.com',
  };

  const mockPoke = {
    id: 'poke-1',
    from_user_id: 'sender-user-id',
    to_user_id: 'recipient-user-id',
    message: 'Hey, checking on you!',
    sent_at: '2024-01-15T10:00:00Z',
    seen_at: null,
    responded_at: null,
  };

  const mockSupportedUsers = [
    {
      checker_id: 'recipient-user-id',
      can_poke: true,
    },
  ];

  const mockCircleLinks = [
    {
      supporter_id: 'sender-user-id',
      alert_via_email: true,
      alert_via_sms: true,
    },
  ];

  beforeEach(() => {
    app = express();
    app.use(express.json());
    app.use('/pokes', pokesRouter);
    jest.clearAllMocks();
  });

  // ===========================================================================
  // POST /pokes - Send Poke
  // ===========================================================================
  describe('POST /pokes', () => {
    it('should send poke successfully', async () => {
      (getSupportedUsers as jest.Mock).mockResolvedValue(mockSupportedUsers);
      (createPoke as jest.Mock).mockResolvedValue(mockPoke);
      (getUserById as jest.Mock)
        .mockResolvedValueOnce(mockSender)
        .mockResolvedValueOnce(mockRecipient);
      (getCircleLinks as jest.Mock).mockResolvedValue(mockCircleLinks);
      (sendPokeEmail as jest.Mock).mockResolvedValue(undefined);
      (sendPokeSMS as jest.Mock).mockResolvedValue(undefined);

      const response = await request(app)
        .post('/pokes')
        .send({
          toUserId: 'recipient-user-id',
          message: 'Hey, checking on you!',
        })
        .expect(201);

      expect(response.body.success).toBe(true);
      expect(response.body.poke.id).toBe('poke-1');
      expect(response.body.poke.toUserId).toBe('recipient-user-id');
      expect(response.body.poke.message).toBe('Hey, checking on you!');
      expect(createPoke).toHaveBeenCalledWith({
        fromUserId: 'sender-user-id',
        toUserId: 'recipient-user-id',
        message: 'Hey, checking on you!',
      });
    });

    it('should send poke without message', async () => {
      (getSupportedUsers as jest.Mock).mockResolvedValue(mockSupportedUsers);
      (createPoke as jest.Mock).mockResolvedValue({ ...mockPoke, message: null });
      (getUserById as jest.Mock)
        .mockResolvedValueOnce(mockSender)
        .mockResolvedValueOnce(mockRecipient);
      (getCircleLinks as jest.Mock).mockResolvedValue(mockCircleLinks);

      const response = await request(app)
        .post('/pokes')
        .send({ toUserId: 'recipient-user-id' })
        .expect(201);

      expect(response.body.success).toBe(true);
    });

    it('should send email notification when enabled', async () => {
      (getSupportedUsers as jest.Mock).mockResolvedValue(mockSupportedUsers);
      (createPoke as jest.Mock).mockResolvedValue(mockPoke);
      (getUserById as jest.Mock)
        .mockResolvedValueOnce(mockSender)
        .mockResolvedValueOnce(mockRecipient);
      (getCircleLinks as jest.Mock).mockResolvedValue([
        { supporter_id: 'sender-user-id', alert_via_email: true, alert_via_sms: false },
      ]);
      (sendPokeEmail as jest.Mock).mockResolvedValue(undefined);

      await request(app)
        .post('/pokes')
        .send({ toUserId: 'recipient-user-id', message: 'Hello!' })
        .expect(201);

      expect(sendPokeEmail).toHaveBeenCalledWith(
        'recipient@example.com',
        'Recipient User',
        'Sender User',
        'Hello!'
      );
      expect(sendPokeSMS).not.toHaveBeenCalled();
    });

    it('should send SMS notification when enabled', async () => {
      (getSupportedUsers as jest.Mock).mockResolvedValue(mockSupportedUsers);
      (createPoke as jest.Mock).mockResolvedValue(mockPoke);
      (getUserById as jest.Mock)
        .mockResolvedValueOnce(mockSender)
        .mockResolvedValueOnce(mockRecipient);
      (getCircleLinks as jest.Mock).mockResolvedValue([
        { supporter_id: 'sender-user-id', alert_via_email: false, alert_via_sms: true },
      ]);
      (sendPokeSMS as jest.Mock).mockResolvedValue(undefined);

      await request(app)
        .post('/pokes')
        .send({ toUserId: 'recipient-user-id', message: 'Hello!' })
        .expect(201);

      expect(sendPokeSMS).toHaveBeenCalledWith({
        to: '+15552222222',
        fromName: 'Sender User',
        message: 'Hello!',
      });
      expect(sendPokeEmail).not.toHaveBeenCalled();
    });

    it('should continue even if email notification fails', async () => {
      (getSupportedUsers as jest.Mock).mockResolvedValue(mockSupportedUsers);
      (createPoke as jest.Mock).mockResolvedValue(mockPoke);
      (getUserById as jest.Mock)
        .mockResolvedValueOnce(mockSender)
        .mockResolvedValueOnce(mockRecipient);
      (getCircleLinks as jest.Mock).mockResolvedValue(mockCircleLinks);
      (sendPokeEmail as jest.Mock).mockRejectedValue(new Error('Email failed'));

      const response = await request(app)
        .post('/pokes')
        .send({ toUserId: 'recipient-user-id' })
        .expect(201);

      expect(response.body.success).toBe(true);
    });

    it('should continue even if SMS notification fails', async () => {
      (getSupportedUsers as jest.Mock).mockResolvedValue(mockSupportedUsers);
      (createPoke as jest.Mock).mockResolvedValue(mockPoke);
      (getUserById as jest.Mock)
        .mockResolvedValueOnce(mockSender)
        .mockResolvedValueOnce(mockRecipient);
      (getCircleLinks as jest.Mock).mockResolvedValue(mockCircleLinks);
      (sendPokeSMS as jest.Mock).mockRejectedValue(new Error('SMS failed'));

      const response = await request(app)
        .post('/pokes')
        .send({ toUserId: 'recipient-user-id' })
        .expect(201);

      expect(response.body.success).toBe(true);
    });

    it('should return 403 when user cannot poke target', async () => {
      (getSupportedUsers as jest.Mock).mockResolvedValue([
        { checker_id: 'recipient-user-id', can_poke: false },
      ]);

      const response = await request(app)
        .post('/pokes')
        .send({ toUserId: 'recipient-user-id' })
        .expect(403);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('You cannot poke this user');
    });

    it('should return 403 when user not in circle', async () => {
      (getSupportedUsers as jest.Mock).mockResolvedValue([]);

      const response = await request(app)
        .post('/pokes')
        .send({ toUserId: 'stranger-user-id' })
        .expect(403);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('You cannot poke this user');
    });

    it('should return 400 for invalid UUID', async () => {
      const response = await request(app)
        .post('/pokes')
        .send({ toUserId: 'not-a-uuid' })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for missing toUserId', async () => {
      const response = await request(app)
        .post('/pokes')
        .send({})
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for message too long', async () => {
      const response = await request(app)
        .post('/pokes')
        .send({
          toUserId: 'recipient-user-id',
          message: 'a'.repeat(501),
        })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 on database error', async () => {
      (getSupportedUsers as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .post('/pokes')
        .send({ toUserId: 'recipient-user-id' })
        .expect(400);

      expect(response.body.success).toBe(false);
    });
  });

  // ===========================================================================
  // GET /pokes - Get My Pokes
  // ===========================================================================
  describe('GET /pokes', () => {
    const mockPokes = [
      {
        id: 'poke-1',
        from_user_id: 'other-user-id',
        from_name: 'Other User',
        message: 'Hello!',
        sent_at: '2024-01-15T10:00:00Z',
        seen_at: null,
        responded_at: null,
      },
      {
        id: 'poke-2',
        from_user_id: 'another-user-id',
        from_name: 'Another User',
        message: null,
        sent_at: '2024-01-14T10:00:00Z',
        seen_at: '2024-01-14T11:00:00Z',
        responded_at: '2024-01-14T12:00:00Z',
      },
    ];

    it('should return list of pokes', async () => {
      (getPokesForUser as jest.Mock).mockResolvedValue(mockPokes);

      const response = await request(app)
        .get('/pokes')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.pokes).toHaveLength(2);
      expect(response.body.pokes[0].id).toBe('poke-1');
      expect(response.body.pokes[0].fromUserId).toBe('other-user-id');
      expect(response.body.pokes[0].fromName).toBe('Other User');
    });

    it('should use default limit of 20', async () => {
      (getPokesForUser as jest.Mock).mockResolvedValue([]);

      await request(app)
        .get('/pokes')
        .expect(200);

      expect(getPokesForUser).toHaveBeenCalledWith('sender-user-id', 20);
    });

    it('should respect custom limit parameter', async () => {
      (getPokesForUser as jest.Mock).mockResolvedValue([]);

      await request(app)
        .get('/pokes?limit=10')
        .expect(200);

      expect(getPokesForUser).toHaveBeenCalledWith('sender-user-id', 10);
    });

    it('should cap limit at 50', async () => {
      (getPokesForUser as jest.Mock).mockResolvedValue([]);

      await request(app)
        .get('/pokes?limit=100')
        .expect(200);

      expect(getPokesForUser).toHaveBeenCalledWith('sender-user-id', 50);
    });

    it('should return empty array when no pokes', async () => {
      (getPokesForUser as jest.Mock).mockResolvedValue([]);

      const response = await request(app)
        .get('/pokes')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.pokes).toEqual([]);
    });

    it('should return 500 on database error', async () => {
      (getPokesForUser as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .get('/pokes')
        .expect(500);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Failed to get pokes');
    });
  });

  // ===========================================================================
  // GET /pokes/unseen/count - Get Unseen Pokes Count
  // ===========================================================================
  describe('GET /pokes/unseen/count', () => {
    it('should return unseen pokes count', async () => {
      (getUnseenPokesCount as jest.Mock).mockResolvedValue(5);

      const response = await request(app)
        .get('/pokes/unseen/count')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.count).toBe(5);
    });

    it('should return zero when no unseen pokes', async () => {
      (getUnseenPokesCount as jest.Mock).mockResolvedValue(0);

      const response = await request(app)
        .get('/pokes/unseen/count')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.count).toBe(0);
    });

    it('should return 500 on database error', async () => {
      (getUnseenPokesCount as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .get('/pokes/unseen/count')
        .expect(500);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Failed to get unseen count');
    });
  });

  // ===========================================================================
  // POST /pokes/:pokeId/seen - Mark Poke as Seen
  // ===========================================================================
  describe('POST /pokes/:pokeId/seen', () => {
    it('should mark poke as seen successfully', async () => {
      (markPokeSeen as jest.Mock).mockResolvedValue(undefined);

      const response = await request(app)
        .post('/pokes/poke-123/seen')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(markPokeSeen).toHaveBeenCalledWith('poke-123', 'sender-user-id');
    });

    it('should return 500 on database error', async () => {
      (markPokeSeen as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .post('/pokes/poke-123/seen')
        .expect(500);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Failed to mark as seen');
    });
  });

  // ===========================================================================
  // POST /pokes/:pokeId/responded - Mark Poke as Responded
  // ===========================================================================
  describe('POST /pokes/:pokeId/responded', () => {
    it('should mark poke as responded successfully', async () => {
      (markPokeResponded as jest.Mock).mockResolvedValue(undefined);

      const response = await request(app)
        .post('/pokes/poke-123/responded')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(markPokeResponded).toHaveBeenCalledWith('poke-123', 'sender-user-id');
    });

    it('should return 500 on database error', async () => {
      (markPokeResponded as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .post('/pokes/poke-123/responded')
        .expect(500);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Failed to mark as responded');
    });
  });

  // ===========================================================================
  // POST /pokes/seen/all - Mark All Pokes as Seen
  // ===========================================================================
  describe('POST /pokes/seen/all', () => {
    it('should mark all unseen pokes as seen', async () => {
      const unseenPokes = [
        { id: 'poke-1', seen_at: null },
        { id: 'poke-2', seen_at: null },
        { id: 'poke-3', seen_at: '2024-01-15T10:00:00Z' }, // Already seen
      ];
      (getPokesForUser as jest.Mock).mockResolvedValue(unseenPokes);
      (markPokeSeen as jest.Mock).mockResolvedValue(undefined);

      const response = await request(app)
        .post('/pokes/seen/all')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(markPokeSeen).toHaveBeenCalledTimes(2);
      expect(markPokeSeen).toHaveBeenCalledWith('poke-1', 'sender-user-id');
      expect(markPokeSeen).toHaveBeenCalledWith('poke-2', 'sender-user-id');
    });

    it('should handle empty pokes list', async () => {
      (getPokesForUser as jest.Mock).mockResolvedValue([]);

      const response = await request(app)
        .post('/pokes/seen/all')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(markPokeSeen).not.toHaveBeenCalled();
    });

    it('should return 500 on database error', async () => {
      (getPokesForUser as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .post('/pokes/seen/all')
        .expect(500);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Failed to mark all as seen');
    });
  });
});
