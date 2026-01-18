import { Response, NextFunction } from 'express';
import { AuthRequest } from './auth.js';
import { getSubscription } from '../db/index.js';

// ============================================================================
// TYPES
// ============================================================================

export type SubscriptionPlan = 'free' | 'plus' | 'family';
export type SubscriptionStatus = 'active' | 'cancelled' | 'expired' | 'billing_issue';

export interface SubscriptionInfo {
  plan: SubscriptionPlan;
  status: SubscriptionStatus;
  expiresAt: Date | null;
}

export interface SubscriptionRequest extends AuthRequest {
  subscription?: SubscriptionInfo;
}

// Feature flags by plan
export type Feature =
  | 'selfie'
  | 'location'
  | 'export'
  | 'custom-schedule'
  | 'unlimited-circle'
  | 'unlimited-checkins'
  | 'priority-support';

const PLAN_FEATURES: Record<SubscriptionPlan, Feature[]> = {
  free: [],
  plus: ['selfie', 'location', 'export', 'custom-schedule'],
  family: [
    'selfie',
    'location',
    'export',
    'custom-schedule',
    'unlimited-circle',
    'unlimited-checkins',
    'priority-support',
  ],
};

// ============================================================================
// SUBSCRIPTION MIDDLEWARE
// Attaches subscription info to the request
// ============================================================================

export async function subscriptionMiddleware(
  req: SubscriptionRequest,
  res: Response,
  next: NextFunction
) {
  try {
    if (!req.userId) {
      return next();
    }

    const subscription = await getSubscription(req.userId);

    if (subscription) {
      req.subscription = {
        plan: subscription.plan as SubscriptionPlan,
        status: subscription.status as SubscriptionStatus,
        expiresAt: subscription.expires_at ? new Date(subscription.expires_at) : null,
      };
    } else {
      req.subscription = {
        plan: 'free',
        status: 'active',
        expiresAt: null,
      };
    }

    next();
  } catch (error) {
    console.error('Subscription middleware error:', error);
    // Don't fail the request, just default to free
    req.subscription = {
      plan: 'free',
      status: 'active',
      expiresAt: null,
    };
    next();
  }
}

// ============================================================================
// REQUIRE SUBSCRIPTION
// Guards routes to require specific plans
// ============================================================================

export function requireSubscription(allowedPlans: SubscriptionPlan[]) {
  return (req: SubscriptionRequest, res: Response, next: NextFunction) => {
    const subscription = req.subscription;

    if (!subscription) {
      return res.status(403).json({
        success: false,
        error: 'Subscription required',
        code: 'SUBSCRIPTION_REQUIRED',
      });
    }

    // Check if subscription is active
    if (subscription.status !== 'active') {
      return res.status(403).json({
        success: false,
        error: 'Active subscription required',
        code: 'SUBSCRIPTION_INACTIVE',
        subscriptionStatus: subscription.status,
      });
    }

    // Check if subscription has expired (for paid plans)
    if (subscription.plan !== 'free' && subscription.expiresAt) {
      if (new Date(subscription.expiresAt) < new Date()) {
        return res.status(403).json({
          success: false,
          error: 'Subscription has expired',
          code: 'SUBSCRIPTION_EXPIRED',
          expiredAt: subscription.expiresAt,
        });
      }
    }

    // Check if plan is allowed
    if (!allowedPlans.includes(subscription.plan)) {
      return res.status(403).json({
        success: false,
        error: 'Upgrade required for this feature',
        code: 'UPGRADE_REQUIRED',
        currentPlan: subscription.plan,
        requiredPlans: allowedPlans,
      });
    }

    next();
  };
}

// ============================================================================
// REQUIRE FEATURE
// Guards routes to require specific features
// ============================================================================

export function requireFeature(feature: Feature) {
  return (req: SubscriptionRequest, res: Response, next: NextFunction) => {
    const subscription = req.subscription;

    if (!subscription) {
      return res.status(403).json({
        success: false,
        error: 'Subscription required',
        code: 'SUBSCRIPTION_REQUIRED',
      });
    }

    // Check if subscription is active
    if (subscription.status !== 'active') {
      return res.status(403).json({
        success: false,
        error: 'Active subscription required',
        code: 'SUBSCRIPTION_INACTIVE',
        subscriptionStatus: subscription.status,
      });
    }

    // Check if subscription has expired (for paid plans)
    if (subscription.plan !== 'free' && subscription.expiresAt) {
      if (new Date(subscription.expiresAt) < new Date()) {
        return res.status(403).json({
          success: false,
          error: 'Subscription has expired',
          code: 'SUBSCRIPTION_EXPIRED',
          expiredAt: subscription.expiresAt,
        });
      }
    }

    // Check if plan has the feature
    const planFeatures = PLAN_FEATURES[subscription.plan];
    if (!planFeatures.includes(feature)) {
      return res.status(403).json({
        success: false,
        error: `Upgrade required to use ${feature}`,
        code: 'FEATURE_UNAVAILABLE',
        feature,
        currentPlan: subscription.plan,
        upgradeHint: getUpgradeHint(feature),
      });
    }

    next();
  };
}

// ============================================================================
// HELPERS
// ============================================================================

function getUpgradeHint(feature: Feature): string {
  switch (feature) {
    case 'selfie':
    case 'location':
    case 'export':
    case 'custom-schedule':
      return 'Upgrade to Plus to unlock this feature';
    case 'unlimited-circle':
    case 'unlimited-checkins':
    case 'priority-support':
      return 'Upgrade to Family to unlock this feature';
    default:
      return 'Upgrade your plan to unlock this feature';
  }
}

// Check if a plan has a specific feature (utility function)
export function planHasFeature(plan: SubscriptionPlan, feature: Feature): boolean {
  return PLAN_FEATURES[plan].includes(feature);
}

// Get all features for a plan (utility function)
export function getPlanFeatures(plan: SubscriptionPlan): Feature[] {
  return PLAN_FEATURES[plan];
}
