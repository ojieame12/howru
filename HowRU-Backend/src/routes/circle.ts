import { Router, Response } from 'express';
import { z } from 'zod';
import crypto from 'crypto';
import { authMiddleware, AuthRequest } from '../middleware/auth.js';
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

const router = Router();

// ============================================================================
// PUBLIC ROUTES (no auth required)
// ============================================================================

// GET INVITE PREVIEW (public - for deep links before login)
router.get('/invites/:code/public', async (req, res: Response) => {
  try {
    const { code } = req.params;

    const invite = await getInviteByCode(code);

    if (!invite) {
      return res.status(404).json({
        success: false,
        error: 'Invite not found or expired',
      });
    }

    // Return limited info for unauthenticated users
    res.json({
      success: true,
      invite: {
        inviterName: invite.inviter_name,
        role: invite.role,
        expiresAt: invite.expires_at,
        permissions: {
          canSeeMood: invite.can_see_mood,
          canSeeLocation: invite.can_see_location,
          canSeeSelfie: invite.can_see_selfie,
          canPoke: invite.can_poke,
        },
      },
    });
  } catch (error: any) {
    console.error('Get public invite error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get invite',
    });
  }
});

// ============================================================================
// AUTHENTICATED ROUTES
// ============================================================================

// All routes below require authentication
router.use(authMiddleware);

// ============================================================================
// GET MY CIRCLE (people I'm checking on me)
// ============================================================================

router.get('/', async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!;

    const supporters = await getCircleLinks(userId);

    res.json({
      success: true,
      circle: supporters.map((s: any) => ({
        id: s.id,
        supporterId: s.supporter_id,
        name: s.supporter_display_name || s.supporter_name,
        phone: s.supporter_phone,
        email: s.supporter_email,
        isAppUser: !!s.supporter_id,
        permissions: {
          canSeeMood: s.can_see_mood,
          canSeeLocation: s.can_see_location,
          canSeeSelfie: s.can_see_selfie,
          canPoke: s.can_poke,
        },
        alertPriority: s.alert_priority,
        alertPreferences: {
          push: s.alert_via_push,
          sms: s.alert_via_sms,
          email: s.alert_via_email,
        },
        invitedAt: s.invited_at,
        acceptedAt: s.accepted_at,
      })),
    });
  } catch (error: any) {
    console.error('Get circle error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get circle',
    });
  }
});

// ============================================================================
// GET PEOPLE I'M SUPPORTING (checking on)
// ============================================================================

router.get('/supporting', async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!;

    const checkers = await getSupportedUsers(userId);

    res.json({
      success: true,
      supporting: checkers.map((c: any) => ({
        id: c.id,
        checkerId: c.checker_id,
        name: c.checker_name,
        phone: c.checker_phone,
        lastKnownLocation: c.last_known_address,
        lastLocationAt: c.last_known_location_at,
        permissions: {
          canSeeMood: c.can_see_mood,
          canSeeLocation: c.can_see_location,
          canSeeSelfie: c.can_see_selfie,
          canPoke: c.can_poke,
        },
      })),
    });
  } catch (error: any) {
    console.error('Get supporting error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get supported users',
    });
  }
});

// ============================================================================
// ADD MEMBER TO CIRCLE (directly, for non-app users)
// ============================================================================

const addMemberSchema = z.object({
  name: z.string().min(1).max(100),
  phone: z.string().min(10).max(20).optional(),
  email: z.string().email().optional(),
  canSeeMood: z.boolean().default(true),
  canSeeLocation: z.boolean().default(false),
  canSeeSelfie: z.boolean().default(false),
  canPoke: z.boolean().default(true),
  alertPriority: z.number().int().min(1).max(10).default(1),
  alertViaSms: z.boolean().default(false),
  alertViaEmail: z.boolean().default(false),
});

router.post('/members', async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!;
    const data = addMemberSchema.parse(req.body);

    // Check if this phone/email belongs to an existing user
    let supporterId: string | undefined;
    if (data.phone) {
      const existingUser = await getUserByPhone(data.phone);
      if (existingUser) {
        supporterId = existingUser.id;
      }
    }

    const link = await createCircleLink({
      checkerId: userId,
      supporterId,
      supporterDisplayName: data.name,
      supporterPhone: data.phone,
      supporterEmail: data.email,
      canSeeMood: data.canSeeMood,
      canSeeLocation: data.canSeeLocation,
      canSeeSelfie: data.canSeeSelfie,
      canPoke: data.canPoke,
      alertPriority: data.alertPriority,
      alertViaSms: data.alertViaSms,
      alertViaEmail: data.alertViaEmail,
    });

    res.status(201).json({
      success: true,
      member: {
        id: link.id,
        name: data.name,
        phone: data.phone,
        email: data.email,
        isAppUser: !!supporterId,
      },
    });
  } catch (error: any) {
    console.error('Add member error:', error);
    res.status(400).json({
      success: false,
      error: error.message || 'Failed to add member',
    });
  }
});

// ============================================================================
// UPDATE CIRCLE MEMBER
// ============================================================================

const updateMemberSchema = z.object({
  name: z.string().min(1).max(100).optional(),
  canSeeMood: z.boolean().optional(),
  canSeeLocation: z.boolean().optional(),
  canSeeSelfie: z.boolean().optional(),
  canPoke: z.boolean().optional(),
  alertPriority: z.number().int().min(1).max(10).optional(),
  alertViaPush: z.boolean().optional(),
  alertViaSms: z.boolean().optional(),
  alertViaEmail: z.boolean().optional(),
});

router.patch('/members/:memberId', async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!;
    const { memberId } = req.params;
    const data = updateMemberSchema.parse(req.body);

    const updated = await updateCircleLink(memberId, userId, {
      supporterDisplayName: data.name,
      canSeeMood: data.canSeeMood,
      canSeeLocation: data.canSeeLocation,
      canSeeSelfie: data.canSeeSelfie,
      canPoke: data.canPoke,
      alertPriority: data.alertPriority,
      alertViaPush: data.alertViaPush,
      alertViaSms: data.alertViaSms,
      alertViaEmail: data.alertViaEmail,
    });

    if (!updated) {
      return res.status(404).json({
        success: false,
        error: 'Member not found',
      });
    }

    res.json({
      success: true,
      member: {
        id: updated.id,
        name: updated.supporter_display_name,
      },
    });
  } catch (error: any) {
    console.error('Update member error:', error);
    res.status(400).json({
      success: false,
      error: error.message || 'Failed to update member',
    });
  }
});

// ============================================================================
// REMOVE CIRCLE MEMBER
// ============================================================================

router.delete('/members/:memberId', async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!;
    const { memberId } = req.params;

    await removeCircleLink(memberId, userId);

    res.json({ success: true });
  } catch (error: any) {
    console.error('Remove member error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to remove member',
    });
  }
});

// ============================================================================
// CREATE INVITE LINK
// ============================================================================

const createInviteSchema = z.object({
  role: z.enum(['checker', 'supporter']),
  canSeeMood: z.boolean().default(true),
  canSeeLocation: z.boolean().default(false),
  canSeeSelfie: z.boolean().default(false),
  canPoke: z.boolean().default(true),
  expiresInHours: z.number().int().min(1).max(168).default(48), // 1 hour to 7 days
});

router.post('/invites', async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!;
    const data = createInviteSchema.parse(req.body);

    // Generate unique invite code
    const code = crypto.randomBytes(4).toString('hex').toUpperCase();
    const expiresAt = new Date(Date.now() + data.expiresInHours * 60 * 60 * 1000);

    const invite = await createInvite({
      inviterId: userId,
      code,
      role: data.role,
      canSeeMood: data.canSeeMood,
      canSeeLocation: data.canSeeLocation,
      canSeeSelfie: data.canSeeSelfie,
      canPoke: data.canPoke,
      expiresAt,
    });

    res.status(201).json({
      success: true,
      invite: {
        id: invite.id,
        code: invite.code,
        role: invite.role,
        expiresAt: invite.expires_at,
        link: `https://howru.app/invite?code=${code}`,
      },
    });
  } catch (error: any) {
    console.error('Create invite error:', error);
    res.status(400).json({
      success: false,
      error: error.message || 'Failed to create invite',
    });
  }
});

// ============================================================================
// SEND INVITE VIA EMAIL
// ============================================================================

const sendInviteSchema = z.object({
  email: z.string().email(),
  role: z.enum(['checker', 'supporter']),
  canSeeMood: z.boolean().default(true),
  canSeeLocation: z.boolean().default(false),
  canSeeSelfie: z.boolean().default(false),
  canPoke: z.boolean().default(true),
});

router.post('/invites/send', async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!;
    const data = sendInviteSchema.parse(req.body);

    const user = await getUserById(userId);
    if (!user) {
      return res.status(404).json({
        success: false,
        error: 'User not found',
      });
    }

    // Generate invite
    const code = crypto.randomBytes(4).toString('hex').toUpperCase();
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000); // 7 days

    const invite = await createInvite({
      inviterId: userId,
      code,
      role: data.role,
      canSeeMood: data.canSeeMood,
      canSeeLocation: data.canSeeLocation,
      canSeeSelfie: data.canSeeSelfie,
      canPoke: data.canPoke,
      expiresAt,
    });

    // Send email
    await sendCircleInviteEmail(data.email, user.name, data.role, code);

    res.status(201).json({
      success: true,
      invite: {
        id: invite.id,
        code: invite.code,
        sentTo: data.email,
      },
    });
  } catch (error: any) {
    console.error('Send invite error:', error);
    res.status(400).json({
      success: false,
      error: error.message || 'Failed to send invite',
    });
  }
});

// ============================================================================
// GET INVITE DETAILS (public-ish, for invite preview)
// ============================================================================

router.get('/invites/:code', async (req: AuthRequest, res: Response) => {
  try {
    const { code } = req.params;

    const invite = await getInviteByCode(code);

    if (!invite) {
      return res.status(404).json({
        success: false,
        error: 'Invite not found or expired',
      });
    }

    res.json({
      success: true,
      invite: {
        inviterName: invite.inviter_name,
        role: invite.role,
        expiresAt: invite.expires_at,
        permissions: {
          canSeeMood: invite.can_see_mood,
          canSeeLocation: invite.can_see_location,
          canSeeSelfie: invite.can_see_selfie,
          canPoke: invite.can_poke,
        },
      },
    });
  } catch (error: any) {
    console.error('Get invite error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get invite',
    });
  }
});

// ============================================================================
// ACCEPT INVITE
// ============================================================================

router.post('/invites/:code/accept', async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!;
    const { code } = req.params;

    const invite = await getInviteByCode(code);

    if (!invite) {
      return res.status(404).json({
        success: false,
        error: 'Invite not found or expired',
      });
    }

    // Accept the invite
    await acceptInvite(code, userId);

    // Create the circle link
    if (invite.role === 'supporter') {
      // Inviter wants this user to be their supporter
      await createCircleLink({
        checkerId: invite.inviter_id,
        supporterId: userId,
        supporterDisplayName: (await getUserById(userId))?.name || 'Unknown',
        canSeeMood: invite.can_see_mood,
        canSeeLocation: invite.can_see_location,
        canSeeSelfie: invite.can_see_selfie,
        canPoke: invite.can_poke,
      });
    } else {
      // Inviter wants to be this user's supporter (checker role)
      await createCircleLink({
        checkerId: userId,
        supporterId: invite.inviter_id,
        supporterDisplayName: invite.inviter_name,
        canSeeMood: invite.can_see_mood,
        canSeeLocation: invite.can_see_location,
        canSeeSelfie: invite.can_see_selfie,
        canPoke: invite.can_poke,
      });
    }

    res.json({
      success: true,
      message: 'Invite accepted',
      role: invite.role,
      inviterName: invite.inviter_name,
    });
  } catch (error: any) {
    console.error('Accept invite error:', error);
    res.status(400).json({
      success: false,
      error: error.message || 'Failed to accept invite',
    });
  }
});

// ============================================================================
// GET MY SENT INVITES
// ============================================================================

router.get('/invites', async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!;

    const invites = await getInvitesByUser(userId);

    res.json({
      success: true,
      invites: invites.map((i: any) => ({
        id: i.id,
        code: i.code,
        role: i.role,
        expiresAt: i.expires_at,
        acceptedAt: i.accepted_at,
        createdAt: i.created_at,
      })),
    });
  } catch (error: any) {
    console.error('Get invites error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get invites',
    });
  }
});

export default router;
