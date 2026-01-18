import { Router, Request, Response } from 'express';
import crypto from 'crypto';
import { sql } from '../db/index.js';

const router = Router();

const REVENUECAT_WEBHOOK_SECRET = process.env.REVENUECAT_WEBHOOK_SECRET;

// ============================================================================
// REVENUECAT WEBHOOK
// Handles subscription events from RevenueCat
// Docs: https://www.revenuecat.com/docs/webhooks
// ============================================================================

interface RevenueCatEvent {
  event: {
    type: string;
    app_user_id: string;
    product_id: string;
    entitlement_ids?: string[];
    expiration_at_ms?: number;
    environment: 'SANDBOX' | 'PRODUCTION';
  };
  api_version: string;
}

router.post('/revenuecat', async (req: Request, res: Response) => {
  try {
    // Verify webhook signature (recommended for production)
    if (REVENUECAT_WEBHOOK_SECRET) {
      const signature = req.headers['x-revenuecat-signature'] as string | undefined;

      if (!signature) {
        console.warn('RevenueCat webhook received without signature');
        return res.status(401).json({ error: 'Missing signature' });
      }

      // RevenueCat uses HMAC-SHA256 for webhook signatures
      // The signature is computed over the raw request body (captured by express.json verify)
      const rawBody = (req as any).rawBody as Buffer | undefined;

      if (!rawBody) {
        console.error('Raw body not available for signature verification');
        return res.status(500).json({ error: 'Server configuration error' });
      }

      const expectedSignature = crypto
        .createHmac('sha256', REVENUECAT_WEBHOOK_SECRET)
        .update(rawBody)
        .digest('hex');

      // Constant-time comparison to prevent timing attacks
      const signatureBuffer = Buffer.from(signature, 'hex');
      const expectedBuffer = Buffer.from(expectedSignature, 'hex');

      if (
        signatureBuffer.length !== expectedBuffer.length ||
        !crypto.timingSafeEqual(signatureBuffer, expectedBuffer)
      ) {
        console.warn('RevenueCat webhook signature mismatch');
        return res.status(401).json({ error: 'Invalid signature' });
      }
    }

    const payload: RevenueCatEvent = req.body;
    const { event } = payload;

    console.log(`RevenueCat webhook: ${event.type} for user ${event.app_user_id}`);

    // Map RevenueCat events to subscription updates
    switch (event.type) {
      case 'INITIAL_PURCHASE':
      case 'RENEWAL':
      case 'PRODUCT_CHANGE':
        await updateSubscription(event.app_user_id, {
          plan: getPlanFromProduct(event.product_id),
          status: 'active',
          productId: event.product_id,
          expiresAt: event.expiration_at_ms ? new Date(event.expiration_at_ms) : null,
          revenueCatId: event.app_user_id,
        });
        break;

      case 'CANCELLATION':
        // User cancelled but may still have access until expiry
        await updateSubscription(event.app_user_id, {
          status: 'cancelled',
        });
        break;

      case 'EXPIRATION':
        // Subscription has expired
        await updateSubscription(event.app_user_id, {
          plan: 'free',
          status: 'expired',
        });
        break;

      case 'BILLING_ISSUE':
        await updateSubscription(event.app_user_id, {
          status: 'billing_issue',
        });
        break;

      case 'SUBSCRIBER_ALIAS':
        // User identity linked - may need to merge accounts
        console.log(`Subscriber alias event for ${event.app_user_id}`);
        break;

      default:
        console.log(`Unhandled RevenueCat event: ${event.type}`);
    }

    res.json({ received: true });
  } catch (error: any) {
    console.error('RevenueCat webhook error:', error);
    // Always return 200 to acknowledge receipt (prevents retries)
    res.json({ received: true, error: error.message });
  }
});

// ============================================================================
// HELPERS
// ============================================================================

function getPlanFromProduct(productId: string): string {
  // Map App Store / Play Store product IDs to plan names
  const productToPlan: Record<string, string> = {
    'com.howru.plus.monthly': 'plus',
    'com.howru.plus.yearly': 'plus',
    'com.howru.family.monthly': 'family',
    'com.howru.family.yearly': 'family',
    // Add your actual product IDs here
  };

  return productToPlan[productId] || 'plus';
}

async function updateSubscription(
  appUserId: string,
  data: {
    plan?: string;
    status?: string;
    productId?: string;
    expiresAt?: Date | null;
    revenueCatId?: string;
  }
) {
  // RevenueCat app_user_id should match your user ID
  const userId = appUserId;

  // Check if subscription record exists
  const existing = await sql`
    SELECT id FROM subscriptions WHERE user_id = ${userId}
  `;

  if (existing.length > 0) {
    // Update existing subscription
    await sql`
      UPDATE subscriptions
      SET
        plan = COALESCE(${data.plan ?? null}, plan),
        status = COALESCE(${data.status ?? null}, status),
        product_id = COALESCE(${data.productId ?? null}, product_id),
        expires_at = COALESCE(${data.expiresAt?.toISOString() ?? null}, expires_at),
        revenue_cat_id = COALESCE(${data.revenueCatId ?? null}, revenue_cat_id),
        updated_at = NOW()
      WHERE user_id = ${userId}
    `;
  } else {
    // Create new subscription record
    await sql`
      INSERT INTO subscriptions (user_id, plan, status, product_id, expires_at, revenue_cat_id)
      VALUES (
        ${userId},
        ${data.plan ?? 'plus'},
        ${data.status ?? 'active'},
        ${data.productId ?? null},
        ${data.expiresAt?.toISOString() ?? null},
        ${data.revenueCatId ?? null}
      )
    `;
  }
}

export default router;
