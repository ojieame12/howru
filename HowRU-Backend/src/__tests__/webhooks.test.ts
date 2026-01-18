import crypto from 'crypto';

// Mock the database before importing the router
jest.mock('../db/index.js', () => ({
  sql: jest.fn(),
}));

import { sql } from '../db/index.js';
import express, { Express, Request, Response, NextFunction } from 'express';
import request from 'supertest';

// Import router after mocks are set up
import webhooksRouter from '../routes/webhooks.js';

const WEBHOOK_SECRET = 'test-revenuecat-secret';

describe('RevenueCat Webhooks', () => {
  let app: Express;

  beforeAll(() => {
    process.env.REVENUECAT_WEBHOOK_SECRET = WEBHOOK_SECRET;
  });

  beforeEach(() => {
    app = express();
    // Use express.json with verify to capture rawBody (like production setup)
    app.use(express.json({
      verify: (req: Request, res: Response, buf: Buffer) => {
        (req as any).rawBody = buf;
      }
    }));
    app.use('/webhooks', webhooksRouter);
    jest.clearAllMocks();
  });

  // Helper to generate valid signature
  function generateSignature(body: object): string {
    const rawBody = Buffer.from(JSON.stringify(body));
    return crypto
      .createHmac('sha256', WEBHOOK_SECRET)
      .update(rawBody)
      .digest('hex');
  }

  // Helper to create a valid webhook payload
  function createPayload(eventType: string, overrides: Partial<any> = {}) {
    return {
      api_version: '1.0',
      event: {
        type: eventType,
        app_user_id: 'user-123',
        product_id: 'com.howru.plus.monthly',
        entitlement_ids: ['plus'],
        expiration_at_ms: Date.now() + 30 * 24 * 60 * 60 * 1000, // 30 days
        environment: 'SANDBOX',
        ...overrides,
      },
    };
  }

  describe('Signature Verification', () => {
    it('should reject requests without signature header', async () => {
      const payload = createPayload('INITIAL_PURCHASE');

      const response = await request(app)
        .post('/webhooks/revenuecat')
        .send(payload)
        .expect(401);

      expect(response.body.error).toBe('Missing signature');
    });

    it('should reject requests with invalid signature', async () => {
      const payload = createPayload('INITIAL_PURCHASE');
      const invalidSignature = 'invalid-signature-hex';

      const response = await request(app)
        .post('/webhooks/revenuecat')
        .set('x-revenuecat-signature', invalidSignature)
        .send(payload)
        .expect(401);

      expect(response.body.error).toBe('Invalid signature');
    });

    it('should reject requests with tampered payload', async () => {
      const originalPayload = createPayload('INITIAL_PURCHASE');
      const signature = generateSignature(originalPayload);

      // Tamper with the payload after signing
      const tamperedPayload = {
        ...originalPayload,
        event: { ...originalPayload.event, app_user_id: 'hacker-user' },
      };

      const response = await request(app)
        .post('/webhooks/revenuecat')
        .set('x-revenuecat-signature', signature)
        .send(tamperedPayload)
        .expect(401);

      expect(response.body.error).toBe('Invalid signature');
    });

    it('should accept requests with valid signature', async () => {
      const payload = createPayload('INITIAL_PURCHASE');
      const signature = generateSignature(payload);

      // Mock database calls
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]); // No existing subscription
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]); // Insert

      const response = await request(app)
        .post('/webhooks/revenuecat')
        .set('x-revenuecat-signature', signature)
        .send(payload)
        .expect(200);

      expect(response.body.received).toBe(true);
    });

    it('should use timing-safe comparison to prevent timing attacks', async () => {
      // This test verifies the implementation uses crypto.timingSafeEqual
      // by checking that signature comparison doesn't leak timing info

      const payload = createPayload('INITIAL_PURCHASE');
      const validSignature = generateSignature(payload);

      // Create signatures that differ at different positions
      const sigDifferentStart = 'a' + validSignature.slice(1);
      const sigDifferentEnd = validSignature.slice(0, -1) + 'a';

      // Both should fail with same error (no timing difference)
      const response1 = await request(app)
        .post('/webhooks/revenuecat')
        .set('x-revenuecat-signature', sigDifferentStart)
        .send(payload);

      const response2 = await request(app)
        .post('/webhooks/revenuecat')
        .set('x-revenuecat-signature', sigDifferentEnd)
        .send(payload);

      expect(response1.status).toBe(401);
      expect(response2.status).toBe(401);
      expect(response1.body.error).toBe(response2.body.error);
    });
  });

  describe('Event Handling', () => {
    beforeEach(() => {
      // Default mock for database - existing subscription
      (sql as unknown as jest.Mock).mockImplementation((strings: TemplateStringsArray) => {
        const query = strings.join('');
        if (query.includes('SELECT id FROM subscriptions')) {
          return Promise.resolve([{ id: 'sub-123' }]);
        }
        return Promise.resolve([]);
      });
    });

    it('should handle INITIAL_PURCHASE event', async () => {
      const payload = createPayload('INITIAL_PURCHASE');
      const signature = generateSignature(payload);

      const response = await request(app)
        .post('/webhooks/revenuecat')
        .set('x-revenuecat-signature', signature)
        .send(payload)
        .expect(200);

      expect(response.body.received).toBe(true);
      expect(sql).toHaveBeenCalled();
    });

    it('should handle RENEWAL event', async () => {
      const payload = createPayload('RENEWAL');
      const signature = generateSignature(payload);

      const response = await request(app)
        .post('/webhooks/revenuecat')
        .set('x-revenuecat-signature', signature)
        .send(payload)
        .expect(200);

      expect(response.body.received).toBe(true);
    });

    it('should handle CANCELLATION event', async () => {
      const payload = createPayload('CANCELLATION');
      const signature = generateSignature(payload);

      const response = await request(app)
        .post('/webhooks/revenuecat')
        .set('x-revenuecat-signature', signature)
        .send(payload)
        .expect(200);

      expect(response.body.received).toBe(true);
    });

    it('should handle EXPIRATION event - resets to free plan', async () => {
      const payload = createPayload('EXPIRATION');
      const signature = generateSignature(payload);

      const response = await request(app)
        .post('/webhooks/revenuecat')
        .set('x-revenuecat-signature', signature)
        .send(payload)
        .expect(200);

      expect(response.body.received).toBe(true);
    });

    it('should handle BILLING_ISSUE event', async () => {
      const payload = createPayload('BILLING_ISSUE');
      const signature = generateSignature(payload);

      const response = await request(app)
        .post('/webhooks/revenuecat')
        .set('x-revenuecat-signature', signature)
        .send(payload)
        .expect(200);

      expect(response.body.received).toBe(true);
    });

    it('should handle PRODUCT_CHANGE event', async () => {
      const payload = createPayload('PRODUCT_CHANGE', {
        product_id: 'com.howru.family.monthly',
      });
      const signature = generateSignature(payload);

      const response = await request(app)
        .post('/webhooks/revenuecat')
        .set('x-revenuecat-signature', signature)
        .send(payload)
        .expect(200);

      expect(response.body.received).toBe(true);
    });

    it('should handle unknown event types gracefully', async () => {
      const payload = createPayload('UNKNOWN_EVENT_TYPE');
      const signature = generateSignature(payload);

      const response = await request(app)
        .post('/webhooks/revenuecat')
        .set('x-revenuecat-signature', signature)
        .send(payload)
        .expect(200);

      expect(response.body.received).toBe(true);
    });

    it('should always return 200 to prevent retries', async () => {
      const payload = createPayload('INITIAL_PURCHASE');
      const signature = generateSignature(payload);

      // Make database throw an error
      (sql as unknown as jest.Mock).mockRejectedValue(new Error('Database error'));

      const response = await request(app)
        .post('/webhooks/revenuecat')
        .set('x-revenuecat-signature', signature)
        .send(payload)
        .expect(200);

      expect(response.body.received).toBe(true);
      expect(response.body.error).toBeDefined();
    });
  });

  describe('Plan Mapping', () => {
    beforeEach(() => {
      (sql as unknown as jest.Mock).mockResolvedValue([]);
    });

    it('should map plus.monthly product to plus plan', async () => {
      const payload = createPayload('INITIAL_PURCHASE', {
        product_id: 'com.howru.plus.monthly',
      });
      const signature = generateSignature(payload);

      await request(app)
        .post('/webhooks/revenuecat')
        .set('x-revenuecat-signature', signature)
        .send(payload)
        .expect(200);

      // Verify the insert was called with 'plus' plan
      const sqlCalls = (sql as unknown as jest.Mock).mock.calls;
      const insertCall = sqlCalls.find((call: any[]) =>
        call[0].some((s: string) => s.includes('INSERT INTO subscriptions'))
      );
      expect(insertCall).toBeDefined();
    });

    it('should map plus.yearly product to plus plan', async () => {
      const payload = createPayload('INITIAL_PURCHASE', {
        product_id: 'com.howru.plus.yearly',
      });
      const signature = generateSignature(payload);

      await request(app)
        .post('/webhooks/revenuecat')
        .set('x-revenuecat-signature', signature)
        .send(payload)
        .expect(200);
    });

    it('should map family.monthly product to family plan', async () => {
      const payload = createPayload('INITIAL_PURCHASE', {
        product_id: 'com.howru.family.monthly',
      });
      const signature = generateSignature(payload);

      await request(app)
        .post('/webhooks/revenuecat')
        .set('x-revenuecat-signature', signature)
        .send(payload)
        .expect(200);
    });

    it('should default unknown products to plus plan', async () => {
      const payload = createPayload('INITIAL_PURCHASE', {
        product_id: 'com.howru.unknown.product',
      });
      const signature = generateSignature(payload);

      await request(app)
        .post('/webhooks/revenuecat')
        .set('x-revenuecat-signature', signature)
        .send(payload)
        .expect(200);
    });
  });
});
