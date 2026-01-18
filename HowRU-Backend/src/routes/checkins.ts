import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { authMiddleware, AuthRequest } from '../middleware/auth.js';
import {
  createCheckIn,
  getTodayCheckIn,
  getRecentCheckIns,
  resolveAlerts,
  getActiveSchedule,
} from '../db/index.js';

const router = Router();

// All routes require authentication
router.use(authMiddleware);

// ============================================================================
// CREATE CHECK-IN
// ============================================================================

const createCheckInSchema = z.object({
  mentalScore: z.number().int().min(1).max(5),
  bodyScore: z.number().int().min(1).max(5),
  moodScore: z.number().int().min(1).max(5),
  latitude: z.number().optional(),
  longitude: z.number().optional(),
  locationName: z.string().max(255).optional(),
  address: z.string().optional(),
  isManual: z.boolean().default(true),
});

router.post('/', async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!;
    const data = createCheckInSchema.parse(req.body);

    // Create check-in
    const checkIn = await createCheckIn({
      userId,
      ...data,
    });

    // Resolve any active alerts (user checked in!)
    await resolveAlerts(userId);

    res.status(201).json({
      success: true,
      checkIn: {
        id: checkIn.id,
        timestamp: checkIn.timestamp,
        mentalScore: checkIn.mental_score,
        bodyScore: checkIn.body_score,
        moodScore: checkIn.mood_score,
        averageScore: (checkIn.mental_score + checkIn.body_score + checkIn.mood_score) / 3,
        latitude: checkIn.latitude,
        longitude: checkIn.longitude,
        locationName: checkIn.location_name,
        address: checkIn.address,
        isManual: checkIn.is_manual,
      },
    });
  } catch (error: any) {
    console.error('Create check-in error:', error);
    res.status(400).json({
      success: false,
      error: error.message || 'Failed to create check-in',
    });
  }
});

// ============================================================================
// GET TODAY'S CHECK-IN
// ============================================================================

router.get('/today', async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!;

    // Get user's timezone from schedule
    const schedule = await getActiveSchedule(userId);
    const timezone = schedule?.timezone_identifier || 'UTC';

    const checkIn = await getTodayCheckIn(userId, timezone);

    if (!checkIn) {
      return res.json({
        success: true,
        checkIn: null,
        hasCheckedInToday: false,
      });
    }

    res.json({
      success: true,
      hasCheckedInToday: true,
      checkIn: {
        id: checkIn.id,
        timestamp: checkIn.timestamp,
        mentalScore: checkIn.mental_score,
        bodyScore: checkIn.body_score,
        moodScore: checkIn.mood_score,
        averageScore: (checkIn.mental_score + checkIn.body_score + checkIn.mood_score) / 3,
        latitude: checkIn.latitude,
        longitude: checkIn.longitude,
        locationName: checkIn.location_name,
        hasSelfie: !!checkIn.selfie_url && new Date(checkIn.selfie_expires_at) > new Date(),
      },
    });
  } catch (error: any) {
    console.error('Get today check-in error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get check-in',
    });
  }
});

// ============================================================================
// GET CHECK-IN HISTORY
// ============================================================================

router.get('/', async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!;
    const limit = Math.min(parseInt(req.query.limit as string) || 30, 100);

    const checkIns = await getRecentCheckIns(userId, limit);

    res.json({
      success: true,
      checkIns: checkIns.map((c: any) => ({
        id: c.id,
        timestamp: c.timestamp,
        mentalScore: c.mental_score,
        bodyScore: c.body_score,
        moodScore: c.mood_score,
        averageScore: (c.mental_score + c.body_score + c.mood_score) / 3,
        locationName: c.location_name,
        isManual: c.is_manual,
      })),
    });
  } catch (error: any) {
    console.error('Get check-ins error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get check-ins',
    });
  }
});

// ============================================================================
// GET CHECK-IN STATS
// ============================================================================

router.get('/stats', async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!;
    const days = Math.min(parseInt(req.query.days as string) || 30, 365);

    const checkIns = await getRecentCheckIns(userId, days);

    if (checkIns.length === 0) {
      return res.json({
        success: true,
        stats: {
          totalCheckIns: 0,
          averageMental: 0,
          averageBody: 0,
          averageMood: 0,
          averageOverall: 0,
          currentStreak: 0,
        },
      });
    }

    const totalCheckIns = checkIns.length;
    const avgMental = checkIns.reduce((sum: number, c: any) => sum + c.mental_score, 0) / totalCheckIns;
    const avgBody = checkIns.reduce((sum: number, c: any) => sum + c.body_score, 0) / totalCheckIns;
    const avgMood = checkIns.reduce((sum: number, c: any) => sum + c.mood_score, 0) / totalCheckIns;

    // Calculate streak (consecutive days)
    let streak = 0;
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    for (let i = 0; i < checkIns.length; i++) {
      const checkInDate = new Date(checkIns[i].timestamp);
      checkInDate.setHours(0, 0, 0, 0);

      const expectedDate = new Date(today);
      expectedDate.setDate(expectedDate.getDate() - i);

      if (checkInDate.getTime() === expectedDate.getTime()) {
        streak++;
      } else {
        break;
      }
    }

    res.json({
      success: true,
      stats: {
        totalCheckIns,
        averageMental: Math.round(avgMental * 10) / 10,
        averageBody: Math.round(avgBody * 10) / 10,
        averageMood: Math.round(avgMood * 10) / 10,
        averageOverall: Math.round(((avgMental + avgBody + avgMood) / 3) * 10) / 10,
        currentStreak: streak,
      },
    });
  } catch (error: any) {
    console.error('Get stats error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get stats',
    });
  }
});

export default router;
