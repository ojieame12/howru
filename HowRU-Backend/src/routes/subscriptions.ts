import { Router, Response } from 'express';
import { authMiddleware, AuthRequest } from '../middleware/auth.js';
import { getSubscription } from '../db/index.js';

const router = Router();

// All routes require authentication
router.use(authMiddleware);

// ============================================================================
// FEATURE LIMITS BY PLAN
// ============================================================================

interface FeatureLimits {
  maxCircleMembers: number;
  maxCheckInsPerDay: number;
  selfieEnabled: boolean;
  locationSharingEnabled: boolean;
  dataExportEnabled: boolean;
  customScheduleEnabled: boolean;
  prioritySupport: boolean;
}

const PLAN_LIMITS: Record<string, FeatureLimits> = {
  free: {
    maxCircleMembers: 2,
    maxCheckInsPerDay: 3,
    selfieEnabled: false,
    locationSharingEnabled: false,
    dataExportEnabled: false,
    customScheduleEnabled: false,
    prioritySupport: false,
  },
  plus: {
    maxCircleMembers: 5,
    maxCheckInsPerDay: 10,
    selfieEnabled: true,
    locationSharingEnabled: true,
    dataExportEnabled: true,
    customScheduleEnabled: true,
    prioritySupport: false,
  },
  family: {
    maxCircleMembers: 15,
    maxCheckInsPerDay: -1, // unlimited
    selfieEnabled: true,
    locationSharingEnabled: true,
    dataExportEnabled: true,
    customScheduleEnabled: true,
    prioritySupport: true,
  },
};

// ============================================================================
// GET MY SUBSCRIPTION
// Returns current subscription status and feature limits
// ============================================================================

router.get('/me', async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!;

    const subscription = await getSubscription(userId);

    const plan = subscription?.plan || 'free';
    const limits = PLAN_LIMITS[plan] || PLAN_LIMITS.free;

    res.json({
      success: true,
      subscription: {
        plan,
        status: subscription?.status || 'active',
        productId: subscription?.product_id || null,
        expiresAt: subscription?.expires_at || null,
        revenueCatId: subscription?.revenue_cat_id || null,
        createdAt: subscription?.created_at || null,
        updatedAt: subscription?.updated_at || null,
      },
      limits,
    });
  } catch (error: any) {
    console.error('Get subscription error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get subscription',
    });
  }
});

// ============================================================================
// GET AVAILABLE OFFERINGS
// Returns list of plans for paywall display
// ============================================================================

interface PlanOffering {
  id: string;
  name: string;
  description: string;
  monthlyProductId: string;
  yearlyProductId: string;
  features: string[];
  highlighted: boolean;
}

const OFFERINGS: PlanOffering[] = [
  {
    id: 'plus',
    name: 'Plus',
    description: 'For individuals who want more from HowRU',
    monthlyProductId: 'com.howru.plus.monthly',
    yearlyProductId: 'com.howru.plus.yearly',
    features: [
      'Up to 5 circle members',
      'Selfie check-ins',
      'Location sharing',
      'Data export',
      'Custom schedules',
    ],
    highlighted: true,
  },
  {
    id: 'family',
    name: 'Family',
    description: 'For families who want to stay connected',
    monthlyProductId: 'com.howru.family.monthly',
    yearlyProductId: 'com.howru.family.yearly',
    features: [
      'Up to 15 circle members',
      'Unlimited check-ins',
      'All Plus features',
      'Priority support',
      'Family sharing',
    ],
    highlighted: false,
  },
];

router.get('/offerings', async (req: AuthRequest, res: Response) => {
  try {
    res.json({
      success: true,
      offerings: OFFERINGS,
      currentPlanLimits: PLAN_LIMITS,
    });
  } catch (error: any) {
    console.error('Get offerings error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get offerings',
    });
  }
});

// ============================================================================
// GET FEATURE LIMIT CHECK
// Quick endpoint to check if user can perform an action
// ============================================================================

router.get('/check-feature/:feature', async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!;
    const { feature } = req.params;

    const subscription = await getSubscription(userId);
    const plan = subscription?.plan || 'free';
    const limits = PLAN_LIMITS[plan] || PLAN_LIMITS.free;

    let allowed = false;
    let limit: number | boolean | null = null;

    // Determine upgrade path based on feature
    let upgradePath: string | null = null;

    switch (feature) {
      case 'selfie':
        allowed = limits.selfieEnabled;
        if (!allowed) upgradePath = 'plus';
        break;
      case 'location':
        allowed = limits.locationSharingEnabled;
        if (!allowed) upgradePath = 'plus';
        break;
      case 'export':
        allowed = limits.dataExportEnabled;
        if (!allowed) upgradePath = 'plus';
        break;
      case 'custom-schedule':
        allowed = limits.customScheduleEnabled;
        if (!allowed) upgradePath = 'plus';
        break;
      case 'priority-support':
        allowed = limits.prioritySupport;
        if (!allowed) upgradePath = 'family';
        break;
      case 'circle-members':
        limit = limits.maxCircleMembers;
        // For limit-based features, allowed=true means the feature is available
        // The client should check current count against limit
        allowed = true;
        // Suggest upgrade if they're on a lower tier
        if (plan === 'free') upgradePath = 'plus';
        else if (plan === 'plus') upgradePath = 'family';
        break;
      case 'checkins':
        limit = limits.maxCheckInsPerDay;
        // For checkins: allowed=true means user can check in (has limit remaining)
        // -1 means unlimited, any positive number means they have a limit
        // Client should track usage; this endpoint returns the limit info
        allowed = true; // Feature is available, client checks against limit
        if (limit !== -1) {
          // Has a finite limit - suggest upgrade for unlimited
          if (plan === 'free') upgradePath = 'plus';
          else if (plan === 'plus') upgradePath = 'family';
        }
        break;
      case 'unlimited-checkins':
        // Explicit check for unlimited checkins
        allowed = limits.maxCheckInsPerDay === -1;
        if (!allowed) upgradePath = 'family';
        break;
      case 'unlimited-circle':
        // Explicit check for large circle (family tier)
        allowed = limits.maxCircleMembers >= 15;
        if (!allowed) upgradePath = 'family';
        break;
      default:
        return res.status(400).json({
          success: false,
          error: 'Unknown feature',
        });
    }

    res.json({
      success: true,
      feature,
      allowed,
      limit,
      plan,
      upgradePath,
    });
  } catch (error: any) {
    console.error('Check feature error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to check feature',
    });
  }
});

export default router;
