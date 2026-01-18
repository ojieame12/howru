import express, { Express } from 'express';
import request from 'supertest';

// Mock the database
jest.mock('../db/index.js', () => ({
  getCircleLinks: jest.fn(),
  getSupportedUsers: jest.fn(),
  createCircleLink: jest.fn(),
  updateCircleLink: jest.fn(),
  removeCircleLink: jest.fn(),
  createInvite: jest.fn(),
  getInviteByCode: jest.fn(),
  acceptInvite: jest.fn(),
  getInvitesByUser: jest.fn(),
  getUserById: jest.fn(),
  getUserByPhone: jest.fn(),
}));

// Mock Resend email service
jest.mock('../services/resend.js', () => ({
  sendCircleInviteEmail: jest.fn().mockResolvedValue(true),
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
  getCircleLinks,
  getSupportedUsers,
  createCircleLink,
  updateCircleLink,
  removeCircleLink,
  createInvite,
  getInviteByCode,
  acceptInvite,
  getInvitesByUser,
  getUserById,
  getUserByPhone,
} from '../db/index.js';
import { sendCircleInviteEmail } from '../services/resend.js';
import circleRouter from '../routes/circle.js';

describe('Circle Routes', () => {
  let app: Express;

  beforeEach(() => {
    app = express();
    app.use(express.json());
    app.use('/circle', circleRouter);
    jest.clearAllMocks();
  });

  // ===========================================================================
  // GET /circle/invites/:code/public - Public Invite Preview
  // ===========================================================================
  describe('GET /circle/invites/:code/public', () => {
    const mockInvite = {
      inviter_name: 'John Doe',
      role: 'supporter',
      expires_at: '2025-12-31T00:00:00Z',
      can_see_mood: true,
      can_see_location: false,
      can_see_selfie: false,
      can_poke: true,
    };

    it('should return public invite preview', async () => {
      (getInviteByCode as jest.Mock).mockResolvedValue(mockInvite);

      const response = await request(app)
        .get('/circle/invites/ABC123/public')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.invite.inviterName).toBe('John Doe');
      expect(response.body.invite.role).toBe('supporter');
      expect(response.body.invite.permissions.canSeeMood).toBe(true);
    });

    it('should return 404 for expired/invalid invite', async () => {
      (getInviteByCode as jest.Mock).mockResolvedValue(null);

      const response = await request(app)
        .get('/circle/invites/INVALID/public')
        .expect(404);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Invite not found or expired');
    });

    it('should handle database errors gracefully', async () => {
      (getInviteByCode as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .get('/circle/invites/ABC123/public')
        .expect(500);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Failed to get invite');
    });
  });

  // ===========================================================================
  // GET /circle - Get My Circle
  // ===========================================================================
  describe('GET /circle', () => {
    const mockSupporters = [
      {
        id: 'link-1',
        supporter_id: 'supporter-1',
        supporter_display_name: 'Alice',
        supporter_name: 'Alice Smith',
        supporter_phone: '+15551234567',
        supporter_email: 'alice@example.com',
        can_see_mood: true,
        can_see_location: true,
        can_see_selfie: false,
        can_poke: true,
        alert_priority: 1,
        alert_via_push: true,
        alert_via_sms: false,
        alert_via_email: true,
        invited_at: '2024-01-01T00:00:00Z',
        accepted_at: '2024-01-02T00:00:00Z',
      },
    ];

    it('should return user\'s circle members', async () => {
      (getCircleLinks as jest.Mock).mockResolvedValue(mockSupporters);

      const response = await request(app)
        .get('/circle')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.circle).toHaveLength(1);
      expect(response.body.circle[0].name).toBe('Alice');
      expect(response.body.circle[0].supporterId).toBe('supporter-1');
      expect(response.body.circle[0].isAppUser).toBe(true);
      expect(response.body.circle[0].permissions.canSeeMood).toBe(true);
    });

    it('should return empty array when no supporters', async () => {
      (getCircleLinks as jest.Mock).mockResolvedValue([]);

      const response = await request(app)
        .get('/circle')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.circle).toHaveLength(0);
    });

    it('should mark non-app users correctly', async () => {
      const nonAppSupporter = {
        ...mockSupporters[0],
        supporter_id: null, // Not an app user
      };
      (getCircleLinks as jest.Mock).mockResolvedValue([nonAppSupporter]);

      const response = await request(app)
        .get('/circle')
        .expect(200);

      expect(response.body.circle[0].isAppUser).toBe(false);
    });

    it('should handle database errors gracefully', async () => {
      (getCircleLinks as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .get('/circle')
        .expect(500);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Failed to get circle');
    });
  });

  // ===========================================================================
  // GET /circle/supporting - Get People I'm Supporting
  // ===========================================================================
  describe('GET /circle/supporting', () => {
    const mockCheckers = [
      {
        id: 'link-1',
        checker_id: 'checker-1',
        checker_name: 'Bob',
        checker_phone: '+15559876543',
        last_known_address: 'New York',
        last_known_location_at: '2024-01-15T10:00:00Z',
        can_see_mood: true,
        can_see_location: true,
        can_see_selfie: false,
        can_poke: true,
      },
    ];

    it('should return people user is supporting', async () => {
      (getSupportedUsers as jest.Mock).mockResolvedValue(mockCheckers);

      const response = await request(app)
        .get('/circle/supporting')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.supporting).toHaveLength(1);
      expect(response.body.supporting[0].name).toBe('Bob');
      expect(response.body.supporting[0].checkerId).toBe('checker-1');
    });

    it('should return empty array when not supporting anyone', async () => {
      (getSupportedUsers as jest.Mock).mockResolvedValue([]);

      const response = await request(app)
        .get('/circle/supporting')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.supporting).toHaveLength(0);
    });

    it('should handle database errors gracefully', async () => {
      (getSupportedUsers as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .get('/circle/supporting')
        .expect(500);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Failed to get supported users');
    });
  });

  // ===========================================================================
  // POST /circle/members - Add Circle Member
  // ===========================================================================
  describe('POST /circle/members', () => {
    const validMemberData = {
      name: 'New Member',
      phone: '+15551234567',
      email: 'member@example.com',
    };

    it('should add a new circle member', async () => {
      (getUserByPhone as jest.Mock).mockResolvedValue(null);
      (createCircleLink as jest.Mock).mockResolvedValue({ id: 'new-link-id' });

      const response = await request(app)
        .post('/circle/members')
        .send(validMemberData)
        .expect(201);

      expect(response.body.success).toBe(true);
      expect(response.body.member.id).toBe('new-link-id');
      expect(response.body.member.name).toBe('New Member');
      expect(response.body.member.isAppUser).toBe(false);
    });

    it('should link to existing user when phone matches', async () => {
      (getUserByPhone as jest.Mock).mockResolvedValue({ id: 'existing-user-id' });
      (createCircleLink as jest.Mock).mockResolvedValue({ id: 'new-link-id' });

      const response = await request(app)
        .post('/circle/members')
        .send(validMemberData)
        .expect(201);

      expect(response.body.member.isAppUser).toBe(true);
      expect(createCircleLink).toHaveBeenCalledWith(
        expect.objectContaining({ supporterId: 'existing-user-id' })
      );
    });

    it('should use default permission values', async () => {
      (getUserByPhone as jest.Mock).mockResolvedValue(null);
      (createCircleLink as jest.Mock).mockResolvedValue({ id: 'new-link-id' });

      await request(app)
        .post('/circle/members')
        .send({ name: 'Member' })
        .expect(201);

      expect(createCircleLink).toHaveBeenCalledWith(
        expect.objectContaining({
          canSeeMood: true,
          canSeeLocation: false,
          canSeeSelfie: false,
          canPoke: true,
          alertPriority: 1,
        })
      );
    });

    it('should return 400 for missing name', async () => {
      const response = await request(app)
        .post('/circle/members')
        .send({ phone: '+15551234567' })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for name exceeding max length', async () => {
      const response = await request(app)
        .post('/circle/members')
        .send({ name: 'A'.repeat(101) })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for invalid email format', async () => {
      const response = await request(app)
        .post('/circle/members')
        .send({ name: 'Member', email: 'invalid-email' })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for invalid alert priority', async () => {
      const response = await request(app)
        .post('/circle/members')
        .send({ name: 'Member', alertPriority: 11 })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should handle database errors gracefully', async () => {
      (getUserByPhone as jest.Mock).mockResolvedValue(null);
      (createCircleLink as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .post('/circle/members')
        .send(validMemberData)
        .expect(400);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('DB error');
    });
  });

  // ===========================================================================
  // PATCH /circle/members/:memberId - Update Circle Member
  // ===========================================================================
  describe('PATCH /circle/members/:memberId', () => {
    it('should update a circle member', async () => {
      (updateCircleLink as jest.Mock).mockResolvedValue({
        id: 'member-1',
        supporter_display_name: 'Updated Name',
      });

      const response = await request(app)
        .patch('/circle/members/member-1')
        .send({ name: 'Updated Name', canSeeMood: false })
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.member.name).toBe('Updated Name');
    });

    it('should return 404 when member not found', async () => {
      (updateCircleLink as jest.Mock).mockResolvedValue(null);

      const response = await request(app)
        .patch('/circle/members/nonexistent')
        .send({ name: 'New Name' })
        .expect(404);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Member not found');
    });

    it('should pass userId to verify ownership', async () => {
      (updateCircleLink as jest.Mock).mockResolvedValue({ id: 'member-1' });

      await request(app)
        .patch('/circle/members/member-1')
        .send({ canSeeMood: true })
        .expect(200);

      expect(updateCircleLink).toHaveBeenCalledWith('member-1', 'user-123', expect.any(Object));
    });

    it('should handle database errors gracefully', async () => {
      (updateCircleLink as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .patch('/circle/members/member-1')
        .send({ name: 'New Name' })
        .expect(400);

      expect(response.body.success).toBe(false);
    });
  });

  // ===========================================================================
  // DELETE /circle/members/:memberId - Remove Circle Member
  // ===========================================================================
  describe('DELETE /circle/members/:memberId', () => {
    it('should remove a circle member', async () => {
      (removeCircleLink as jest.Mock).mockResolvedValue(true);

      const response = await request(app)
        .delete('/circle/members/member-1')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(removeCircleLink).toHaveBeenCalledWith('member-1', 'user-123');
    });

    it('should handle database errors gracefully', async () => {
      (removeCircleLink as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .delete('/circle/members/member-1')
        .expect(500);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Failed to remove member');
    });
  });

  // ===========================================================================
  // POST /circle/invites - Create Invite
  // ===========================================================================
  describe('POST /circle/invites', () => {
    it('should create an invite', async () => {
      (createInvite as jest.Mock).mockResolvedValue({
        id: 'invite-1',
        code: 'ABC123',
        role: 'supporter',
        expires_at: '2025-12-31T00:00:00Z',
      });

      const response = await request(app)
        .post('/circle/invites')
        .send({ role: 'supporter' })
        .expect(201);

      expect(response.body.success).toBe(true);
      expect(response.body.invite.code).toBeDefined();
      expect(response.body.invite.role).toBe('supporter');
      expect(response.body.invite.link).toContain('https://howru.app/invite?code=');
    });

    it('should use default expiration of 48 hours', async () => {
      (createInvite as jest.Mock).mockResolvedValue({
        id: 'invite-1',
        code: 'ABC123',
        role: 'checker',
        expires_at: new Date().toISOString(),
      });

      await request(app)
        .post('/circle/invites')
        .send({ role: 'checker' })
        .expect(201);

      expect(createInvite).toHaveBeenCalledWith(
        expect.objectContaining({
          expiresAt: expect.any(Date),
        })
      );
    });

    it('should allow custom expiration time', async () => {
      (createInvite as jest.Mock).mockResolvedValue({
        id: 'invite-1',
        code: 'ABC123',
        role: 'supporter',
        expires_at: new Date().toISOString(),
      });

      await request(app)
        .post('/circle/invites')
        .send({ role: 'supporter', expiresInHours: 72 })
        .expect(201);
    });

    it('should return 400 for invalid role', async () => {
      const response = await request(app)
        .post('/circle/invites')
        .send({ role: 'invalid' })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for expiration less than 1 hour', async () => {
      const response = await request(app)
        .post('/circle/invites')
        .send({ role: 'supporter', expiresInHours: 0 })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for expiration more than 168 hours', async () => {
      const response = await request(app)
        .post('/circle/invites')
        .send({ role: 'supporter', expiresInHours: 200 })
        .expect(400);

      expect(response.body.success).toBe(false);
    });
  });

  // ===========================================================================
  // POST /circle/invites/send - Send Invite via Email
  // ===========================================================================
  describe('POST /circle/invites/send', () => {
    it('should send invite email', async () => {
      (getUserById as jest.Mock).mockResolvedValue({ id: 'user-123', name: 'John Doe' });
      (createInvite as jest.Mock).mockResolvedValue({
        id: 'invite-1',
        code: 'ABC123',
      });

      const response = await request(app)
        .post('/circle/invites/send')
        .send({ email: 'friend@example.com', role: 'supporter' })
        .expect(201);

      expect(response.body.success).toBe(true);
      expect(response.body.invite.sentTo).toBe('friend@example.com');
      expect(sendCircleInviteEmail).toHaveBeenCalledWith(
        'friend@example.com',
        'John Doe',
        'supporter',
        expect.any(String)
      );
    });

    it('should return 404 when user not found', async () => {
      (getUserById as jest.Mock).mockResolvedValue(null);

      const response = await request(app)
        .post('/circle/invites/send')
        .send({ email: 'friend@example.com', role: 'supporter' })
        .expect(404);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('User not found');
    });

    it('should return 400 for invalid email', async () => {
      const response = await request(app)
        .post('/circle/invites/send')
        .send({ email: 'invalid-email', role: 'supporter' })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for missing role', async () => {
      const response = await request(app)
        .post('/circle/invites/send')
        .send({ email: 'friend@example.com' })
        .expect(400);

      expect(response.body.success).toBe(false);
    });
  });

  // ===========================================================================
  // GET /circle/invites/:code - Get Invite Details
  // ===========================================================================
  describe('GET /circle/invites/:code', () => {
    const mockInvite = {
      inviter_name: 'John Doe',
      role: 'supporter',
      expires_at: '2025-12-31T00:00:00Z',
      can_see_mood: true,
      can_see_location: false,
      can_see_selfie: false,
      can_poke: true,
    };

    it('should return invite details', async () => {
      (getInviteByCode as jest.Mock).mockResolvedValue(mockInvite);

      const response = await request(app)
        .get('/circle/invites/ABC123')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.invite.inviterName).toBe('John Doe');
    });

    it('should return 404 for invalid invite', async () => {
      (getInviteByCode as jest.Mock).mockResolvedValue(null);

      const response = await request(app)
        .get('/circle/invites/INVALID')
        .expect(404);

      expect(response.body.success).toBe(false);
    });
  });

  // ===========================================================================
  // POST /circle/invites/:code/accept - Accept Invite
  // ===========================================================================
  describe('POST /circle/invites/:code/accept', () => {
    const mockInvite = {
      inviter_id: 'inviter-123',
      inviter_name: 'John Doe',
      role: 'supporter',
      can_see_mood: true,
      can_see_location: false,
      can_see_selfie: false,
      can_poke: true,
    };

    it('should accept supporter invite', async () => {
      (getInviteByCode as jest.Mock).mockResolvedValue(mockInvite);
      (acceptInvite as jest.Mock).mockResolvedValue(true);
      (getUserById as jest.Mock).mockResolvedValue({ name: 'Current User' });
      (createCircleLink as jest.Mock).mockResolvedValue({ id: 'new-link' });

      const response = await request(app)
        .post('/circle/invites/ABC123/accept')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.role).toBe('supporter');
      expect(createCircleLink).toHaveBeenCalledWith(
        expect.objectContaining({
          checkerId: 'inviter-123',
          supporterId: 'user-123',
        })
      );
    });

    it('should accept checker invite', async () => {
      const checkerInvite = { ...mockInvite, role: 'checker' };
      (getInviteByCode as jest.Mock).mockResolvedValue(checkerInvite);
      (acceptInvite as jest.Mock).mockResolvedValue(true);
      (createCircleLink as jest.Mock).mockResolvedValue({ id: 'new-link' });

      const response = await request(app)
        .post('/circle/invites/ABC123/accept')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(createCircleLink).toHaveBeenCalledWith(
        expect.objectContaining({
          checkerId: 'user-123',
          supporterId: 'inviter-123',
        })
      );
    });

    it('should return 404 for invalid invite', async () => {
      (getInviteByCode as jest.Mock).mockResolvedValue(null);

      const response = await request(app)
        .post('/circle/invites/INVALID/accept')
        .expect(404);

      expect(response.body.success).toBe(false);
    });

    it('should handle errors gracefully', async () => {
      (getInviteByCode as jest.Mock).mockResolvedValue(mockInvite);
      (acceptInvite as jest.Mock).mockRejectedValue(new Error('Already accepted'));

      const response = await request(app)
        .post('/circle/invites/ABC123/accept')
        .expect(400);

      expect(response.body.success).toBe(false);
    });
  });

  // ===========================================================================
  // GET /circle/invites - Get My Sent Invites
  // ===========================================================================
  describe('GET /circle/invites', () => {
    const mockInvites = [
      {
        id: 'invite-1',
        code: 'ABC123',
        role: 'supporter',
        expires_at: '2025-12-31T00:00:00Z',
        accepted_at: null,
        created_at: '2024-01-01T00:00:00Z',
      },
      {
        id: 'invite-2',
        code: 'DEF456',
        role: 'checker',
        expires_at: '2025-12-31T00:00:00Z',
        accepted_at: '2024-01-02T00:00:00Z',
        created_at: '2024-01-01T00:00:00Z',
      },
    ];

    it('should return user\'s sent invites', async () => {
      (getInvitesByUser as jest.Mock).mockResolvedValue(mockInvites);

      const response = await request(app)
        .get('/circle/invites')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.invites).toHaveLength(2);
      expect(response.body.invites[0].code).toBe('ABC123');
      expect(response.body.invites[1].acceptedAt).toBe('2024-01-02T00:00:00Z');
    });

    it('should return empty array when no invites', async () => {
      (getInvitesByUser as jest.Mock).mockResolvedValue([]);

      const response = await request(app)
        .get('/circle/invites')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.invites).toHaveLength(0);
    });

    it('should handle database errors gracefully', async () => {
      (getInvitesByUser as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .get('/circle/invites')
        .expect(500);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Failed to get invites');
    });
  });
});
