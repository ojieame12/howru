"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const index_js_1 = require("../db/index.js");
const router = (0, express_1.Router)();
const REVENUECAT_WEBHOOK_SECRET = process.env.REVENUECAT_WEBHOOK_SECRET;
router.post('/revenuecat', async (req, res) => {
    try {
        // Verify webhook signature (optional but recommended)
        if (REVENUECAT_WEBHOOK_SECRET) {
            const signature = req.headers['x-revenuecat-signature'];
            // RevenueCat uses HMAC-SHA256 for webhook signatures
            // Verify if signature header is present
        }
        const payload = req.body;
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
    }
    catch (error) {
        console.error('RevenueCat webhook error:', error);
        // Always return 200 to acknowledge receipt (prevents retries)
        res.json({ received: true, error: error.message });
    }
});
// ============================================================================
// HELPERS
// ============================================================================
function getPlanFromProduct(productId) {
    // Map App Store / Play Store product IDs to plan names
    const productToPlan = {
        'com.howru.plus.monthly': 'plus',
        'com.howru.plus.yearly': 'plus',
        'com.howru.family.monthly': 'family',
        'com.howru.family.yearly': 'family',
        // Add your actual product IDs here
    };
    return productToPlan[productId] || 'plus';
}
async function updateSubscription(appUserId, data) {
    // RevenueCat app_user_id should match your user ID
    const userId = appUserId;
    // Check if subscription record exists
    const existing = await (0, index_js_1.sql) `
    SELECT id FROM subscriptions WHERE user_id = ${userId}
  `;
    if (existing.length > 0) {
        // Update existing subscription
        await (0, index_js_1.sql) `
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
    }
    else {
        // Create new subscription record
        await (0, index_js_1.sql) `
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
exports.default = router;
//# sourceMappingURL=webhooks.js.map