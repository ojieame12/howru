import { Router, Response } from 'express';
import { z } from 'zod';
import { authMiddleware, AuthRequest } from '../middleware/auth.js';
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

const router = Router();

// All routes require authentication
router.use(authMiddleware);

// ============================================================================
// SEND POKE
// ============================================================================

const sendPokeSchema = z.object({
  toUserId: z.string().uuid(),
  message: z.string().max(500).optional(),
});

router.post('/', async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!;
    const data = sendPokeSchema.parse(req.body);

    // Verify the sender can poke this user (must be in their circle)
    const supportedUsers = await getSupportedUsers(userId);
    const canPoke = supportedUsers.some(
      (u: any) => u.checker_id === data.toUserId && u.can_poke
    );

    if (!canPoke) {
      return res.status(403).json({
        success: false,
        error: 'You cannot poke this user',
      });
    }

    // Create the poke
    const poke = await createPoke({
      fromUserId: userId,
      toUserId: data.toUserId,
      message: data.message,
    });

    // Get sender info for notifications
    const sender = await getUserById(userId);
    const recipient = await getUserById(data.toUserId);

    // Send notifications (email/SMS based on preferences)
    // Get recipient's circle link to check notification preferences
    const recipientCircle = await getCircleLinks(data.toUserId);
    const linkToSender = recipientCircle.find((l: any) => l.supporter_id === userId);

    if (linkToSender && recipient) {
      // Send email notification
      if (linkToSender.alert_via_email && recipient.email) {
        try {
          await sendPokeEmail(recipient.email, recipient.name, sender?.name || 'Someone', data.message);
        } catch (e) {
          console.error('Failed to send poke email:', e);
        }
      }

      // Send SMS notification
      if (linkToSender.alert_via_sms && recipient.phone_number) {
        try {
          await sendPokeSMS({
            to: recipient.phone_number,
            fromName: sender?.name || 'Someone',
            message: data.message,
          });
        } catch (e) {
          console.error('Failed to send poke SMS:', e);
        }
      }
    }

    res.status(201).json({
      success: true,
      poke: {
        id: poke.id,
        toUserId: poke.to_user_id,
        message: poke.message,
        sentAt: poke.sent_at,
      },
    });
  } catch (error: any) {
    console.error('Send poke error:', error);
    res.status(400).json({
      success: false,
      error: error.message || 'Failed to send poke',
    });
  }
});

// ============================================================================
// GET MY POKES (received)
// ============================================================================

router.get('/', async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!;
    const limit = Math.min(parseInt(req.query.limit as string) || 20, 50);

    const pokes = await getPokesForUser(userId, limit);

    res.json({
      success: true,
      pokes: pokes.map((p: any) => ({
        id: p.id,
        fromUserId: p.from_user_id,
        fromName: p.from_name,
        message: p.message,
        sentAt: p.sent_at,
        seenAt: p.seen_at,
        respondedAt: p.responded_at,
      })),
    });
  } catch (error: any) {
    console.error('Get pokes error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get pokes',
    });
  }
});

// ============================================================================
// GET UNSEEN POKES COUNT
// ============================================================================

router.get('/unseen/count', async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!;

    const count = await getUnseenPokesCount(userId);

    res.json({
      success: true,
      count,
    });
  } catch (error: any) {
    console.error('Get unseen count error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get unseen count',
    });
  }
});

// ============================================================================
// MARK POKE AS SEEN
// ============================================================================

router.post('/:pokeId/seen', async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!;
    const { pokeId } = req.params;

    await markPokeSeen(pokeId, userId);

    res.json({ success: true });
  } catch (error: any) {
    console.error('Mark seen error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to mark as seen',
    });
  }
});

// ============================================================================
// MARK POKE AS RESPONDED (e.g., user checked in after poke)
// ============================================================================

router.post('/:pokeId/responded', async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!;
    const { pokeId } = req.params;

    await markPokeResponded(pokeId, userId);

    res.json({ success: true });
  } catch (error: any) {
    console.error('Mark responded error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to mark as responded',
    });
  }
});

// ============================================================================
// MARK ALL POKES AS SEEN
// ============================================================================

router.post('/seen/all', async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!;

    const pokes = await getPokesForUser(userId, 100);

    for (const poke of pokes) {
      if (!poke.seen_at) {
        await markPokeSeen(poke.id, userId);
      }
    }

    res.json({ success: true });
  } catch (error: any) {
    console.error('Mark all seen error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to mark all as seen',
    });
  }
});

export default router;
