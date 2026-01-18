import express, { Express } from 'express';
import request from 'supertest';

// Mock the database and auth middleware
jest.mock('../db/index.js', () => ({
  getSubscription: jest.fn(),
}));

jest.mock('../middleware/auth.js', () => ({
  authMiddleware: (req: any, res: any, next: any) => {
    req.userId = 'user-123';
    next();
  },
  AuthRequest: {},
}));

import { getSubscription } from '../db/index.js';
import subscriptionsRouter from '../routes/subscriptions.js';

describe('Subscriptions Routes', () => {
  let app: Express;

  beforeEach(() => {
    app = express();
    app.use(express.json());
    app.use('/subscriptions', subscriptionsRouter);
    jest.clearAllMocks();
  });

  describe('GET /subscriptions/me', () => {
    it('should return free plan when no subscription exists', async () => {
      (getSubscription as jest.Mock).mockResolvedValue(null);

      const response = await request(app)
        .get('/subscriptions/me')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.subscription.plan).toBe('free');
      expect(response.body.subscription.status).toBe('active');
      expect(response.body.limits).toEqual({
        maxCircleMembers: 2,
        maxCheckInsPerDay: 3,
        selfieEnabled: false,
        locationSharingEnabled: false,
        dataExportEnabled: false,
        customScheduleEnabled: false,
        prioritySupport: false,
      });
    });

    it('should return plus plan with correct limits', async () => {
      (getSubscription as jest.Mock).mockResolvedValue({
        plan: 'plus',
        status: 'active',
        product_id: 'com.howru.plus.monthly',
        expires_at: '2025-12-31T00:00:00Z',
        revenue_cat_id: 'rc-123',
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-15T00:00:00Z',
      });

      const response = await request(app)
        .get('/subscriptions/me')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.subscription).toEqual({
        plan: 'plus',
        status: 'active',
        productId: 'com.howru.plus.monthly',
        expiresAt: '2025-12-31T00:00:00Z',
        revenueCatId: 'rc-123',
        createdAt: '2024-01-01T00:00:00Z',
        updatedAt: '2024-01-15T00:00:00Z',
      });
      expect(response.body.limits).toEqual({
        maxCircleMembers: 5,
        maxCheckInsPerDay: 10,
        selfieEnabled: true,
        locationSharingEnabled: true,
        dataExportEnabled: true,
        customScheduleEnabled: true,
        prioritySupport: false,
      });
    });

    it('should return family plan with correct limits', async () => {
      (getSubscription as jest.Mock).mockResolvedValue({
        plan: 'family',
        status: 'active',
        product_id: 'com.howru.family.yearly',
        expires_at: null,
        revenue_cat_id: null,
        created_at: null,
        updated_at: null,
      });

      const response = await request(app)
        .get('/subscriptions/me')
        .expect(200);

      expect(response.body.subscription.plan).toBe('family');
      expect(response.body.limits).toEqual({
        maxCircleMembers: 15,
        maxCheckInsPerDay: -1, // unlimited
        selfieEnabled: true,
        locationSharingEnabled: true,
        dataExportEnabled: true,
        customScheduleEnabled: true,
        prioritySupport: true,
      });
    });

    it('should handle database errors gracefully', async () => {
      (getSubscription as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .get('/subscriptions/me')
        .expect(500);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Failed to get subscription');
    });

    it('should default to free plan for unknown plan types', async () => {
      (getSubscription as jest.Mock).mockResolvedValue({
        plan: 'unknown-plan',
        status: 'active',
      });

      const response = await request(app)
        .get('/subscriptions/me')
        .expect(200);

      // Should fall back to free limits
      expect(response.body.limits.maxCircleMembers).toBe(2);
    });
  });

  describe('GET /subscriptions/offerings', () => {
    it('should return all plan offerings', async () => {
      const response = await request(app)
        .get('/subscriptions/offerings')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.offerings).toHaveLength(2);
    });

    it('should include plus offering with correct details', async () => {
      const response = await request(app)
        .get('/subscriptions/offerings')
        .expect(200);

      const plusOffering = response.body.offerings.find(
        (o: any) => o.id === 'plus'
      );
      expect(plusOffering).toBeDefined();
      expect(plusOffering.name).toBe('Plus');
      expect(plusOffering.monthlyProductId).toBe('com.howru.plus.monthly');
      expect(plusOffering.yearlyProductId).toBe('com.howru.plus.yearly');
      expect(plusOffering.features).toContain('Up to 5 circle members');
      expect(plusOffering.highlighted).toBe(true);
    });

    it('should include family offering with correct details', async () => {
      const response = await request(app)
        .get('/subscriptions/offerings')
        .expect(200);

      const familyOffering = response.body.offerings.find(
        (o: any) => o.id === 'family'
      );
      expect(familyOffering).toBeDefined();
      expect(familyOffering.name).toBe('Family');
      expect(familyOffering.features).toContain('Up to 15 circle members');
      expect(familyOffering.features).toContain('Priority support');
      expect(familyOffering.highlighted).toBe(false);
    });

    it('should include plan limits for comparison', async () => {
      const response = await request(app)
        .get('/subscriptions/offerings')
        .expect(200);

      expect(response.body.currentPlanLimits).toBeDefined();
      expect(response.body.currentPlanLimits.free).toBeDefined();
      expect(response.body.currentPlanLimits.plus).toBeDefined();
      expect(response.body.currentPlanLimits.family).toBeDefined();
    });
  });

  describe('GET /subscriptions/check-feature/:feature', () => {
    beforeEach(() => {
      (getSubscription as jest.Mock).mockResolvedValue(null); // Free plan
    });

    it('should return not allowed for selfie on free plan', async () => {
      const response = await request(app)
        .get('/subscriptions/check-feature/selfie')
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.feature).toBe('selfie');
      expect(response.body.allowed).toBe(false);
      expect(response.body.plan).toBe('free');
      expect(response.body.upgradePath).toBe('plus');
    });

    it('should return allowed for selfie on plus plan', async () => {
      (getSubscription as jest.Mock).mockResolvedValue({
        plan: 'plus',
        status: 'active',
      });

      const response = await request(app)
        .get('/subscriptions/check-feature/selfie')
        .expect(200);

      expect(response.body.allowed).toBe(true);
      expect(response.body.plan).toBe('plus');
      expect(response.body.upgradePath).toBeNull();
    });

    it('should return not allowed for location on free plan', async () => {
      const response = await request(app)
        .get('/subscriptions/check-feature/location')
        .expect(200);

      expect(response.body.allowed).toBe(false);
      expect(response.body.upgradePath).toBe('plus');
    });

    it('should return not allowed for export on free plan', async () => {
      const response = await request(app)
        .get('/subscriptions/check-feature/export')
        .expect(200);

      expect(response.body.allowed).toBe(false);
    });

    it('should return not allowed for custom-schedule on free plan', async () => {
      const response = await request(app)
        .get('/subscriptions/check-feature/custom-schedule')
        .expect(200);

      expect(response.body.allowed).toBe(false);
    });

    it('should return limit for circle-members feature', async () => {
      const response = await request(app)
        .get('/subscriptions/check-feature/circle-members')
        .expect(200);

      expect(response.body.allowed).toBe(true);
      expect(response.body.limit).toBe(2); // Free plan limit
    });

    it('should return limit and allowed=true for checkins feature on free plan', async () => {
      const response = await request(app)
        .get('/subscriptions/check-feature/checkins')
        .expect(200);

      expect(response.body.allowed).toBe(true);
      expect(response.body.limit).toBe(3); // Free plan limit
      expect(response.body.upgradePath).toBe('plus');
    });

    it('should return limit and upgradePath for checkins on plus plan', async () => {
      (getSubscription as jest.Mock).mockResolvedValue({
        plan: 'plus',
        status: 'active',
      });

      const response = await request(app)
        .get('/subscriptions/check-feature/checkins')
        .expect(200);

      expect(response.body.allowed).toBe(true);
      expect(response.body.limit).toBe(10); // Plus plan limit
      expect(response.body.upgradePath).toBe('family');
    });

    it('should return unlimited (-1) and no upgradePath for checkins on family plan', async () => {
      (getSubscription as jest.Mock).mockResolvedValue({
        plan: 'family',
        status: 'active',
      });

      const response = await request(app)
        .get('/subscriptions/check-feature/checkins')
        .expect(200);

      expect(response.body.limit).toBe(-1);
      expect(response.body.allowed).toBe(true);
      expect(response.body.upgradePath).toBeNull();
    });

    it('should return allowed=false for unlimited-checkins on free/plus plans', async () => {
      const response = await request(app)
        .get('/subscriptions/check-feature/unlimited-checkins')
        .expect(200);

      expect(response.body.allowed).toBe(false);
      expect(response.body.upgradePath).toBe('family');
    });

    it('should return allowed=true for unlimited-checkins on family plan', async () => {
      (getSubscription as jest.Mock).mockResolvedValue({
        plan: 'family',
        status: 'active',
      });

      const response = await request(app)
        .get('/subscriptions/check-feature/unlimited-checkins')
        .expect(200);

      expect(response.body.allowed).toBe(true);
      expect(response.body.upgradePath).toBeNull();
    });

    it('should return allowed=false for unlimited-circle on free/plus plans', async () => {
      const response = await request(app)
        .get('/subscriptions/check-feature/unlimited-circle')
        .expect(200);

      expect(response.body.allowed).toBe(false);
      expect(response.body.upgradePath).toBe('family');
    });

    it('should return allowed=true for unlimited-circle on family plan', async () => {
      (getSubscription as jest.Mock).mockResolvedValue({
        plan: 'family',
        status: 'active',
      });

      const response = await request(app)
        .get('/subscriptions/check-feature/unlimited-circle')
        .expect(200);

      expect(response.body.allowed).toBe(true);
      expect(response.body.upgradePath).toBeNull();
    });

    it('should return correct upgradePath for circle-members based on plan', async () => {
      // Free plan -> suggest plus
      let response = await request(app)
        .get('/subscriptions/check-feature/circle-members')
        .expect(200);
      expect(response.body.upgradePath).toBe('plus');

      // Plus plan -> suggest family
      (getSubscription as jest.Mock).mockResolvedValue({
        plan: 'plus',
        status: 'active',
      });
      response = await request(app)
        .get('/subscriptions/check-feature/circle-members')
        .expect(200);
      expect(response.body.upgradePath).toBe('family');

      // Family plan -> no upgrade path
      (getSubscription as jest.Mock).mockResolvedValue({
        plan: 'family',
        status: 'active',
      });
      response = await request(app)
        .get('/subscriptions/check-feature/circle-members')
        .expect(200);
      expect(response.body.upgradePath).toBeNull();
    });

    it('should return error for unknown feature', async () => {
      const response = await request(app)
        .get('/subscriptions/check-feature/unknown-feature')
        .expect(400);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Unknown feature');
    });

    it('should handle database errors gracefully', async () => {
      (getSubscription as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .get('/subscriptions/check-feature/selfie')
        .expect(500);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Failed to check feature');
    });
  });
});
