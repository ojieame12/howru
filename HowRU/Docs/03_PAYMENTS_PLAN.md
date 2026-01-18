# HowRU Payments & Billing Plan

## Overview

Freemium model with StoreKit 2 + RevenueCat for subscription management.

---

## 1. Pricing Tiers

### Free Tier

| Feature | Limit |
|---------|-------|
| Check-ins | Unlimited |
| Supporters | 2 max |
| History | 7 days |
| Notifications | Push only |
| Selfie snapshots | No |
| Data export | No |

### Premium - $4.99/month or $39.99/year

| Feature | Limit |
|---------|-------|
| Check-ins | Unlimited |
| Supporters | 10 max |
| History | 365 days |
| Notifications | Push + SMS |
| Selfie snapshots | Yes (24h expiry) |
| Data export | Yes |
| Priority support | Yes |

### Family - $9.99/month or $79.99/year

| Feature | Limit |
|---------|-------|
| Checkers | Up to 5 (family members being monitored) |
| Supporters per checker | Unlimited |
| All Premium features | Yes |
| Shared dashboard | Yes |
| Family admin controls | Yes |

**Family Plan Clarification:**
- Family plan allows one account to monitor up to 5 "checkers" (elderly family members)
- Each checker can have unlimited supporters
- The primary account holder is the "family admin"

---

## 2. RevenueCat Integration

### Why RevenueCat?

- Handles App Store receipt validation
- Webhooks for subscription events
- Cross-platform ready (if Android later)
- Analytics dashboard
- Free under $2,500 MTR

### Products to Create in App Store Connect

| Product ID | Type | Price |
|------------|------|-------|
| `howru_premium_monthly` | Auto-renewable | $4.99 |
| `howru_premium_yearly` | Auto-renewable | $39.99 |
| `howru_family_monthly` | Auto-renewable | $9.99 |
| `howru_family_yearly` | Auto-renewable | $79.99 |

### RevenueCat Entitlements

| Entitlement | Products |
|-------------|----------|
| `premium` | premium_monthly, premium_yearly |
| `family` | family_monthly, family_yearly |

---

## 3. iOS Implementation

### StoreKit 2 + RevenueCat

```swift
import RevenueCat
import StoreKit

@Observable
final class SubscriptionService {
    private(set) var customerInfo: CustomerInfo?
    private(set) var offerings: Offerings?

    var isPremium: Bool {
        customerInfo?.entitlements["premium"]?.isActive == true
    }

    var isFamily: Bool {
        customerInfo?.entitlements["family"]?.isActive == true
    }

    var hasActiveSubscription: Bool {
        isPremium || isFamily
    }

    // MARK: - Initialize

    func configure() {
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: "appl_YOUR_KEY")
    }

    // MARK: - Fetch Customer Info

    func fetchCustomerInfo() async throws {
        customerInfo = try await Purchases.shared.customerInfo()
    }

    // MARK: - Fetch Offerings

    func fetchOfferings() async throws {
        offerings = try await Purchases.shared.offerings()
    }

    // MARK: - Purchase

    func purchase(_ package: Package) async throws {
        let result = try await Purchases.shared.purchase(package: package)
        customerInfo = result.customerInfo
    }

    // MARK: - Restore

    func restorePurchases() async throws {
        customerInfo = try await Purchases.shared.restorePurchases()
    }
}
```

### Paywall UI

```swift
struct PaywallView: View {
    @Environment(SubscriptionService.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: HowRUSpacing.xl) {
                    // Hero
                    heroSection

                    // Features comparison
                    featuresSection

                    // Pricing options
                    if let offerings = subscriptions.offerings?.current {
                        pricingSection(offerings: offerings)
                    }

                    // Terms
                    termsSection
                }
                .padding()
            }
            .navigationTitle("Upgrade to Premium")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func pricingSection(offerings: Offering) -> some View {
        VStack(spacing: HowRUSpacing.md) {
            ForEach(offerings.availablePackages) { package in
                PricingCard(
                    package: package,
                    isSelected: selectedPackage == package
                ) {
                    selectedPackage = package
                }
            }

            Button("Subscribe") {
                Task {
                    try await subscriptions.purchase(selectedPackage)
                    dismiss()
                }
            }
            .buttonStyle(HowRUPrimaryButtonStyle())
            .disabled(selectedPackage == nil)

            Button("Restore Purchases") {
                Task {
                    try await subscriptions.restorePurchases()
                }
            }
            .font(HowRUFont.caption())
        }
    }
}
```

---

## 4. Backend Integration

### Webhook Endpoint

```
POST /billing/webhook

Headers:
  Authorization: Bearer {revenueCat_webhook_secret}

Body (from RevenueCat):
{
  "event": {
    "type": "INITIAL_PURCHASE",
    "app_user_id": "usr_abc123",
    "product_id": "howru_premium_monthly",
    "purchased_at_ms": 1705766400000,
    "expiration_at_ms": 1708444800000,
    "store": "APP_STORE"
  }
}
```

### Webhook Event Types

| Event | Action |
|-------|--------|
| `INITIAL_PURCHASE` | Create subscription record |
| `RENEWAL` | Update expiry date |
| `CANCELLATION` | Mark as canceled (still active until expiry) |
| `BILLING_ISSUE` | Flag account, notify user |
| `EXPIRATION` | Downgrade to free |
| `PRODUCT_CHANGE` | Update plan |

### Database Schema

```sql
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    plan VARCHAR(50) NOT NULL,  -- 'free', 'premium', 'family'
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    product_id VARCHAR(100),
    store VARCHAR(20),  -- 'app_store', 'play_store'
    original_purchase_date TIMESTAMP,
    expiration_date TIMESTAMP,
    is_sandbox BOOLEAN DEFAULT false,
    revenue_cat_id VARCHAR(255),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_subscriptions_user ON subscriptions(user_id);
CREATE INDEX idx_subscriptions_status ON subscriptions(status);
```

### API Endpoints

#### Get Entitlements

```
GET /billing/entitlements

Response (200):
{
  "plan": "premium",
  "status": "active",
  "expiresAt": "2024-02-20T00:00:00Z",
  "features": {
    "maxSupporters": 10,
    "historyDays": 365,
    "smsAlerts": true,
    "selfieSnapshots": true,
    "dataExport": true
  }
}
```

---

## 5. Feature Gating

### iOS Side

```swift
extension SubscriptionService {
    /// Max supporters a checker can have in their circle
    var maxSupporters: Int {
        if isFamily { return .max }  // Unlimited for family
        if isPremium { return 10 }
        return 2
    }

    /// Max checkers a family admin can monitor (Family plan only)
    var maxCheckers: Int {
        if isFamily { return 5 }
        return 1  // Free/Premium: only yourself
    }

    var historyDays: Int {
        hasActiveSubscription ? 365 : 7
    }

    var canUseSMSAlerts: Bool {
        hasActiveSubscription
    }

    var canUseSelfieSnapshots: Bool {
        hasActiveSubscription
    }

    var canExportData: Bool {
        hasActiveSubscription
    }
}
```

### Backend Side

```typescript
function getFeatureLimits(subscription: Subscription) {
  const limits = {
    free: {
      maxSupporters: 2,
      historyDays: 7,
      smsAlerts: false,
      selfieSnapshots: false,
      dataExport: false
    },
    premium: {
      maxSupporters: 10,
      historyDays: 365,
      smsAlerts: true,
      selfieSnapshots: true,
      dataExport: true
    },
    family: {
      maxSupporters: 50,
      maxCheckers: 5,
      historyDays: 365,
      smsAlerts: true,
      selfieSnapshots: true,
      dataExport: true
    }
  };

  return limits[subscription.plan] || limits.free;
}
```

---

## 6. SMS Credits (Optional Add-on)

For free users who want SMS alerts without full subscription:

| Package | Credits | Price |
|---------|---------|-------|
| Starter | 20 SMS | $2.99 |
| Basic | 50 SMS | $4.99 |
| Plus | 100 SMS | $7.99 |

### Implementation

- Consumable IAP via StoreKit
- Track credits in database
- Deduct on each SMS sent
- Show low balance warnings

---

## 7. Promotional Offers

### Free Trial

- 7-day free trial for Premium
- Requires payment method upfront
- Auto-converts to paid

### Promotional Codes

- Generate codes in App Store Connect
- Use for marketing campaigns
- Track redemptions

### Referral Program (Future)

- Give month free, get month free
- Track via invite codes
- Cap at 6 months free

---

## 8. Revenue Projections

### Conservative Estimate (Year 1)

| Month | Users | Paid (5%) | MRR |
|-------|-------|-----------|-----|
| 1 | 100 | 5 | $25 |
| 3 | 500 | 25 | $125 |
| 6 | 2,000 | 100 | $500 |
| 12 | 10,000 | 500 | $2,500 |

### Costs at 10K Users

| Item | Monthly |
|------|---------|
| RevenueCat (1% > $2.5K) | ~$25 |
| Infrastructure | ~$200 |
| Twilio SMS | ~$500 |
| Apple (30% cut) | ~$750 |
| **Net Revenue** | **~$1,025** |

---

## 9. Implementation Checklist

### App Store Connect

- [ ] Create app record
- [ ] Set up In-App Purchases
- [ ] Configure subscription groups
- [ ] Set up pricing
- [ ] Configure free trial

### RevenueCat

- [ ] Create account
- [ ] Create project
- [ ] Add iOS app
- [ ] Configure products
- [ ] Set up entitlements
- [ ] Configure webhook URL
- [ ] Generate API key

### iOS App

- [ ] Install RevenueCat SDK
- [ ] Create SubscriptionService
- [ ] Build PaywallView
- [ ] Add feature gating
- [ ] Handle restore purchases
- [ ] Test in sandbox

### Backend

- [ ] Create subscriptions table
- [ ] Implement webhook endpoint
- [ ] Add entitlements endpoint
- [ ] Implement feature checks

---

## Next Document

See `04_EMERGENCY_SERVICES_PLAN.md` for alert escalation and 911 integration.
