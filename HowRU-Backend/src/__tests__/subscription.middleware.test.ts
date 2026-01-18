import { Request, Response, NextFunction } from 'express';
import {
  subscriptionMiddleware,
  requireSubscription,
  requireFeature,
  planHasFeature,
  getPlanFeatures,
  SubscriptionRequest,
  SubscriptionPlan,
  Feature,
} from '../middleware/subscription.js';

// Mock the database
jest.mock('../db/index.js', () => ({
  getSubscription: jest.fn(),
}));

import { getSubscription } from '../db/index.js';

describe('Subscription Middleware', () => {
  let mockReq: Partial<SubscriptionRequest>;
  let mockRes: Partial<Response>;
  let mockNext: NextFunction;

  beforeEach(() => {
    mockReq = {
      userId: 'user-123',
    };
    mockRes = {
      status: jest.fn().mockReturnThis(),
      json: jest.fn().mockReturnThis(),
    };
    mockNext = jest.fn();
    jest.clearAllMocks();
  });

  describe('subscriptionMiddleware', () => {
    it('should attach subscription info for subscribed user', async () => {
      (getSubscription as jest.Mock).mockResolvedValue({
        plan: 'plus',
        status: 'active',
        expires_at: '2025-12-31T00:00:00Z',
      });

      await subscriptionMiddleware(
        mockReq as SubscriptionRequest,
        mockRes as Response,
        mockNext
      );

      expect(mockReq.subscription).toEqual({
        plan: 'plus',
        status: 'active',
        expiresAt: new Date('2025-12-31T00:00:00Z'),
      });
      expect(mockNext).toHaveBeenCalled();
    });

    it('should default to free plan when no subscription exists', async () => {
      (getSubscription as jest.Mock).mockResolvedValue(null);

      await subscriptionMiddleware(
        mockReq as SubscriptionRequest,
        mockRes as Response,
        mockNext
      );

      expect(mockReq.subscription).toEqual({
        plan: 'free',
        status: 'active',
        expiresAt: null,
      });
      expect(mockNext).toHaveBeenCalled();
    });

    it('should default to free plan on database error', async () => {
      (getSubscription as jest.Mock).mockRejectedValue(new Error('DB error'));

      await subscriptionMiddleware(
        mockReq as SubscriptionRequest,
        mockRes as Response,
        mockNext
      );

      expect(mockReq.subscription).toEqual({
        plan: 'free',
        status: 'active',
        expiresAt: null,
      });
      expect(mockNext).toHaveBeenCalled();
    });

    it('should skip if no userId present', async () => {
      mockReq.userId = undefined;

      await subscriptionMiddleware(
        mockReq as SubscriptionRequest,
        mockRes as Response,
        mockNext
      );

      expect(getSubscription).not.toHaveBeenCalled();
      expect(mockNext).toHaveBeenCalled();
    });

    it('should handle family plan subscription', async () => {
      (getSubscription as jest.Mock).mockResolvedValue({
        plan: 'family',
        status: 'active',
        expires_at: null,
      });

      await subscriptionMiddleware(
        mockReq as SubscriptionRequest,
        mockRes as Response,
        mockNext
      );

      expect(mockReq.subscription?.plan).toBe('family');
    });
  });

  describe('requireSubscription', () => {
    const middleware = requireSubscription(['plus', 'family']);

    it('should allow matching plan', () => {
      mockReq.subscription = {
        plan: 'plus',
        status: 'active',
        expiresAt: null,
      };

      middleware(mockReq as SubscriptionRequest, mockRes as Response, mockNext);

      expect(mockNext).toHaveBeenCalled();
      expect(mockRes.status).not.toHaveBeenCalled();
    });

    it('should allow family plan when plus or family required', () => {
      mockReq.subscription = {
        plan: 'family',
        status: 'active',
        expiresAt: null,
      };

      middleware(mockReq as SubscriptionRequest, mockRes as Response, mockNext);

      expect(mockNext).toHaveBeenCalled();
    });

    it('should reject when no subscription attached', () => {
      mockReq.subscription = undefined;

      middleware(mockReq as SubscriptionRequest, mockRes as Response, mockNext);

      expect(mockRes.status).toHaveBeenCalledWith(403);
      expect(mockRes.json).toHaveBeenCalledWith(
        expect.objectContaining({
          success: false,
          code: 'SUBSCRIPTION_REQUIRED',
        })
      );
      expect(mockNext).not.toHaveBeenCalled();
    });

    it('should reject non-matching plan', () => {
      mockReq.subscription = {
        plan: 'free',
        status: 'active',
        expiresAt: null,
      };

      middleware(mockReq as SubscriptionRequest, mockRes as Response, mockNext);

      expect(mockRes.status).toHaveBeenCalledWith(403);
      expect(mockRes.json).toHaveBeenCalledWith(
        expect.objectContaining({
          success: false,
          code: 'UPGRADE_REQUIRED',
          currentPlan: 'free',
          requiredPlans: ['plus', 'family'],
        })
      );
    });

    it('should reject inactive subscription', () => {
      mockReq.subscription = {
        plan: 'plus',
        status: 'cancelled',
        expiresAt: null,
      };

      middleware(mockReq as SubscriptionRequest, mockRes as Response, mockNext);

      expect(mockRes.status).toHaveBeenCalledWith(403);
      expect(mockRes.json).toHaveBeenCalledWith(
        expect.objectContaining({
          success: false,
          code: 'SUBSCRIPTION_INACTIVE',
          subscriptionStatus: 'cancelled',
        })
      );
    });

    it('should reject expired subscription', () => {
      mockReq.subscription = {
        plan: 'plus',
        status: 'expired',
        expiresAt: new Date('2020-01-01'),
      };

      middleware(mockReq as SubscriptionRequest, mockRes as Response, mockNext);

      expect(mockRes.status).toHaveBeenCalledWith(403);
      expect(mockRes.json).toHaveBeenCalledWith(
        expect.objectContaining({
          code: 'SUBSCRIPTION_INACTIVE',
        })
      );
    });

    it('should reject billing_issue status', () => {
      mockReq.subscription = {
        plan: 'plus',
        status: 'billing_issue',
        expiresAt: null,
      };

      middleware(mockReq as SubscriptionRequest, mockRes as Response, mockNext);

      expect(mockRes.status).toHaveBeenCalledWith(403);
    });

    it('should reject paid plan with expired expiresAt date', () => {
      const pastDate = new Date();
      pastDate.setDate(pastDate.getDate() - 1); // Yesterday

      mockReq.subscription = {
        plan: 'plus',
        status: 'active',
        expiresAt: pastDate,
      };

      middleware(mockReq as SubscriptionRequest, mockRes as Response, mockNext);

      expect(mockRes.status).toHaveBeenCalledWith(403);
      expect(mockRes.json).toHaveBeenCalledWith(
        expect.objectContaining({
          success: false,
          code: 'SUBSCRIPTION_EXPIRED',
          expiredAt: pastDate,
        })
      );
      expect(mockNext).not.toHaveBeenCalled();
    });

    it('should allow paid plan with future expiresAt date', () => {
      const futureDate = new Date();
      futureDate.setDate(futureDate.getDate() + 30); // 30 days from now

      mockReq.subscription = {
        plan: 'plus',
        status: 'active',
        expiresAt: futureDate,
      };

      middleware(mockReq as SubscriptionRequest, mockRes as Response, mockNext);

      expect(mockNext).toHaveBeenCalled();
      expect(mockRes.status).not.toHaveBeenCalled();
    });

    it('should allow paid plan with null expiresAt (lifetime)', () => {
      mockReq.subscription = {
        plan: 'plus',
        status: 'active',
        expiresAt: null,
      };

      middleware(mockReq as SubscriptionRequest, mockRes as Response, mockNext);

      expect(mockNext).toHaveBeenCalled();
    });

    it('should not check expiresAt for free plan', () => {
      const pastDate = new Date();
      pastDate.setDate(pastDate.getDate() - 1); // Yesterday

      // Free plan with past expiresAt shouldn't matter
      const freeMiddleware = requireSubscription(['free', 'plus', 'family']);
      mockReq.subscription = {
        plan: 'free',
        status: 'active',
        expiresAt: pastDate,
      };

      freeMiddleware(mockReq as SubscriptionRequest, mockRes as Response, mockNext);

      expect(mockNext).toHaveBeenCalled();
    });
  });

  describe('requireFeature', () => {
    it('should allow feature available in plan', () => {
      mockReq.subscription = {
        plan: 'plus',
        status: 'active',
        expiresAt: null,
      };

      const middleware = requireFeature('selfie');
      middleware(mockReq as SubscriptionRequest, mockRes as Response, mockNext);

      expect(mockNext).toHaveBeenCalled();
    });

    it('should reject feature not available in free plan', () => {
      mockReq.subscription = {
        plan: 'free',
        status: 'active',
        expiresAt: null,
      };

      const middleware = requireFeature('selfie');
      middleware(mockReq as SubscriptionRequest, mockRes as Response, mockNext);

      expect(mockRes.status).toHaveBeenCalledWith(403);
      expect(mockRes.json).toHaveBeenCalledWith(
        expect.objectContaining({
          success: false,
          code: 'FEATURE_UNAVAILABLE',
          feature: 'selfie',
          currentPlan: 'free',
        })
      );
    });

    it('should include upgrade hint for plus features', () => {
      mockReq.subscription = {
        plan: 'free',
        status: 'active',
        expiresAt: null,
      };

      const middleware = requireFeature('location');
      middleware(mockReq as SubscriptionRequest, mockRes as Response, mockNext);

      expect(mockRes.json).toHaveBeenCalledWith(
        expect.objectContaining({
          upgradeHint: 'Upgrade to Plus to unlock this feature',
        })
      );
    });

    it('should include upgrade hint for family-only features', () => {
      mockReq.subscription = {
        plan: 'plus',
        status: 'active',
        expiresAt: null,
      };

      const middleware = requireFeature('unlimited-circle');
      middleware(mockReq as SubscriptionRequest, mockRes as Response, mockNext);

      expect(mockRes.json).toHaveBeenCalledWith(
        expect.objectContaining({
          upgradeHint: 'Upgrade to Family to unlock this feature',
        })
      );
    });

    it('should allow family features for family plan', () => {
      mockReq.subscription = {
        plan: 'family',
        status: 'active',
        expiresAt: null,
      };

      const middleware = requireFeature('unlimited-circle');
      middleware(mockReq as SubscriptionRequest, mockRes as Response, mockNext);

      expect(mockNext).toHaveBeenCalled();
    });

    it('should reject when subscription is missing', () => {
      mockReq.subscription = undefined;

      const middleware = requireFeature('export');
      middleware(mockReq as SubscriptionRequest, mockRes as Response, mockNext);

      expect(mockRes.status).toHaveBeenCalledWith(403);
      expect(mockRes.json).toHaveBeenCalledWith(
        expect.objectContaining({
          code: 'SUBSCRIPTION_REQUIRED',
        })
      );
    });

    it('should reject when subscription is inactive', () => {
      mockReq.subscription = {
        plan: 'plus',
        status: 'cancelled',
        expiresAt: null,
      };

      const middleware = requireFeature('selfie');
      middleware(mockReq as SubscriptionRequest, mockRes as Response, mockNext);

      expect(mockRes.status).toHaveBeenCalledWith(403);
      expect(mockRes.json).toHaveBeenCalledWith(
        expect.objectContaining({
          code: 'SUBSCRIPTION_INACTIVE',
        })
      );
    });

    it('should reject feature when subscription expiresAt is past', () => {
      const pastDate = new Date();
      pastDate.setDate(pastDate.getDate() - 1); // Yesterday

      mockReq.subscription = {
        plan: 'plus',
        status: 'active',
        expiresAt: pastDate,
      };

      const middleware = requireFeature('selfie');
      middleware(mockReq as SubscriptionRequest, mockRes as Response, mockNext);

      expect(mockRes.status).toHaveBeenCalledWith(403);
      expect(mockRes.json).toHaveBeenCalledWith(
        expect.objectContaining({
          code: 'SUBSCRIPTION_EXPIRED',
        })
      );
    });

    it('should allow feature when subscription expiresAt is future', () => {
      const futureDate = new Date();
      futureDate.setDate(futureDate.getDate() + 30); // 30 days from now

      mockReq.subscription = {
        plan: 'plus',
        status: 'active',
        expiresAt: futureDate,
      };

      const middleware = requireFeature('selfie');
      middleware(mockReq as SubscriptionRequest, mockRes as Response, mockNext);

      expect(mockNext).toHaveBeenCalled();
    });
  });

  describe('Utility Functions', () => {
    describe('planHasFeature', () => {
      it('should return false for free plan features', () => {
        expect(planHasFeature('free', 'selfie')).toBe(false);
        expect(planHasFeature('free', 'location')).toBe(false);
        expect(planHasFeature('free', 'export')).toBe(false);
      });

      it('should return true for plus plan features', () => {
        expect(planHasFeature('plus', 'selfie')).toBe(true);
        expect(planHasFeature('plus', 'location')).toBe(true);
        expect(planHasFeature('plus', 'export')).toBe(true);
        expect(planHasFeature('plus', 'custom-schedule')).toBe(true);
      });

      it('should return false for family-only features on plus', () => {
        expect(planHasFeature('plus', 'unlimited-circle')).toBe(false);
        expect(planHasFeature('plus', 'unlimited-checkins')).toBe(false);
        expect(planHasFeature('plus', 'priority-support')).toBe(false);
      });

      it('should return true for all features on family plan', () => {
        expect(planHasFeature('family', 'selfie')).toBe(true);
        expect(planHasFeature('family', 'unlimited-circle')).toBe(true);
        expect(planHasFeature('family', 'priority-support')).toBe(true);
      });
    });

    describe('getPlanFeatures', () => {
      it('should return empty array for free plan', () => {
        expect(getPlanFeatures('free')).toEqual([]);
      });

      it('should return plus features for plus plan', () => {
        const features = getPlanFeatures('plus');
        expect(features).toContain('selfie');
        expect(features).toContain('location');
        expect(features).toContain('export');
        expect(features).toContain('custom-schedule');
        expect(features).not.toContain('unlimited-circle');
      });

      it('should return all features for family plan', () => {
        const features = getPlanFeatures('family');
        expect(features).toContain('selfie');
        expect(features).toContain('unlimited-circle');
        expect(features).toContain('priority-support');
      });
    });
  });
});
