# HowRU Backend Architecture Plan

> **Note:** This document has been superseded by the detailed planning documents.
>
> For the current canonical specification, see:
> - `END_TO_END_SPEC.md` - Complete end-to-end specification
> - `01_AUTH_PLAN.md` - Authentication details
> - `02_API_SERVICES_PLAN.md` - API endpoints
> - `03_PAYMENTS_PLAN.md` - Billing and subscriptions
> - `04_EMERGENCY_SERVICES_PLAN.md` - Alert escalation
> - `05_INFRASTRUCTURE_PLAN.md` - Infrastructure and deployment

## Overview

This document outlines the backend services, APIs, authentication, payments, and emergency alert integrations needed to make HowRU a production-ready wellness check-in app.

---

## 1. Authentication

### Options

| Method | Pros | Cons | Recommendation |
|--------|------|------|----------------|
| **Phone + SMS OTP** | Simple for elderly users, no password to remember | SMS costs, carrier issues | **Primary method** |
| **Apple Sign-In** | Required for App Store if other social logins used, secure | Requires Apple device | Secondary option |
| **Magic Link (Email)** | No password, simple | Requires email access | Fallback option |
| **Passkeys** | Most secure, no password | New tech, may confuse elderly | Future enhancement |

### Recommended Flow

```
1. User enters phone number
2. Backend sends SMS OTP via Twilio/AWS SNS
3. User enters 6-digit code
4. Backend verifies, returns JWT + refresh token
5. Store tokens in Keychain
6. Refresh token rotation on each use
```

### Auth Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/auth/otp/request` | POST | Send OTP to phone number |
| `/auth/otp/verify` | POST | Verify OTP, return tokens |
| `/auth/refresh` | POST | Refresh access token |
| `/auth/logout` | POST | Invalidate refresh token |
| `/users/me` | DELETE | GDPR-compliant account deletion |

---

## 2. Core API Services

### 2.1 User Service

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/users/me` | GET | Get current user profile |
| `/users/me` | PATCH | Update profile (name, email, profileImageUrl) |
| `/users/me/schedule` | GET/PUT | Check-in schedule |
| `/users/me/push-token` | POST | Register push token (APNS) |
| `/users/me/push-token` | DELETE | Remove push token |
| `/users/:userId` | GET | Limited profile for circle use |

### 2.2 Check-In Service

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/checkins` | POST | Create new check-in |
| `/checkins` | GET | List recent check-ins (limit query) |
| `/checkins/today` | GET | Get today's check-in if exists |
| `/checkins/stats` | GET | Aggregated stats for trends (days query) |

### 2.3 Circle Service

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/circle` | GET | Get circle links for checkers |
| `/circle/supporting` | GET | Get circle links for supporters |
| `/circle/members` | POST | Create circle link |
| `/circle/members/:memberId` | PATCH | Update link permissions |
| `/circle/members/:memberId` | DELETE | Remove circle link |
| `/circle/invites` | POST | Create invite code |
| `/circle/invites/send` | POST | Send invite via email |
| `/circle/invites/:code` | GET | Get invite details |
| `/circle/invites/:code/accept` | POST | Accept invite |
| `/circle/invites` | GET | List invites for user |

### 2.4 Poke Service

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/pokes` | POST | Send poke to checker |
| `/pokes` | GET | List received pokes |
| `/pokes/unseen/count` | GET | Count unseen pokes |
| `/pokes/:pokeId/seen` | POST | Mark poke as seen |
| `/pokes/:pokeId/responded` | POST | Mark poke as responded |
| `/pokes/seen/all` | POST | Mark all pokes as seen |

### 2.5 Alert Service

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/alerts` | GET | List alerts for supporter |
| `/alerts/mine` | GET | List alerts for checker |
| `/alerts/:alertId/acknowledge` | POST | Supporter acknowledges alert |
| `/alerts/:alertId/resolve` | POST | Mark alert resolved |
| `/alerts/trigger` | POST | Trigger alert (admin/test) |

### 2.6 Uploads Service

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/uploads/url` | POST | Request presigned upload URL |
| `/uploads/selfie` | POST | Upload selfie via base64 |
| `/uploads/selfie/confirm` | POST | Confirm direct selfie upload |
| `/uploads/avatar` | POST | Upload avatar via base64 |
| `/uploads/avatar/confirm` | POST | Confirm direct avatar upload |
| `/uploads/avatar` | DELETE | Remove avatar |

---

## 3. Background Services (Server-Side)

### 3.1 Check-In Monitor Service

**Purpose:** Detect missed check-ins and trigger alerts

```
Schedule: Every 15 minutes (cron)

Logic:
1. Query all users with active schedules
2. For each user:
   - Is today an active day?
   - Has window + grace period passed?
   - Did they check in today?
3. If missed:
   - Create AlertEvent
   - Schedule escalation timeline
   - Notify first-tier supporters
```

### 3.2 Alert Escalation Service

**Purpose:** Progressive alert escalation

```
Timeline from missed window:
+0h    → AlertEvent created, status: .pending
+1h    → Reminder to checker (push + SMS)
+24h   → .softAlert - First supporter notified
+36h   → .hardAlert - All supporters notified
+48h   → .escalation - Emergency contacts, optional 911
```

### 3.3 Snapshot Cleanup Service

**Purpose:** Delete expired selfies for privacy

```
Schedule: Every hour

Logic:
1. Query CheckIns where selfieExpiresAt < now
2. Delete selfieData, set hasSelfie = false
3. Log for audit trail
```

### 3.4 Analytics Service

**Purpose:** Anonymized usage metrics

```
- Daily active users
- Check-in completion rates
- Average response time to alerts
- Feature usage (selfies, pokes)
```

---

## 4. External Integrations

### 4.1 SMS/Voice Provider (Twilio)

| Feature | Twilio Product | Use Case |
|---------|---------------|----------|
| OTP SMS | Verify API | Authentication |
| Alert SMS | Programmable SMS | Supporter alerts |
| Voice Calls | Programmable Voice | Emergency auto-calls |
| Status Callbacks | Webhooks | Delivery tracking |

**Endpoints we need to call:**

```
Twilio Verify:
- POST /v2/Services/{sid}/Verifications
- POST /v2/Services/{sid}/VerificationCheck

Twilio SMS:
- POST /2010-04-01/Accounts/{sid}/Messages

Twilio Voice:
- POST /2010-04-01/Accounts/{sid}/Calls
```

### 4.2 Push Notifications (APNS)

```
- Use APNs HTTP/2 provider API
- Support for:
  - Standard alerts
  - Critical alerts (bypass DND) - requires entitlement
  - Background refresh
  - Rich notifications with images
```

### 4.3 Email Provider (Resend)

| Template | Trigger |
|----------|---------|
| Welcome | Account created |
| Invite | Circle invite sent |
| Alert | Missed check-in (if email enabled) |
| Export | Data export ready |
| Account Deletion | Confirmation |

---

## 5. Payment & Billing

### 5.1 Pricing Model Options

| Model | Description | Recommendation |
|-------|-------------|----------------|
| **Freemium** | Free basic, paid for advanced | Best for growth |
| **Subscription** | Monthly/yearly fee | Predictable revenue |
| **Pay-per-alert** | Pay for SMS/calls used | Complex, unpredictable |

### Recommended: Freemium + Subscription

**Free Tier:**
- 1 checker + 2 supporters
- Push notifications only
- 7-day history
- Basic check-in

**Premium ($4.99/month or $39.99/year):**
- Unlimited supporters
- SMS + Voice alerts
- 365-day history
- Selfie snapshots
- Data export
- Priority support

**Family Plan ($9.99/month):**
- Up to 5 checkers
- All premium features
- Shared dashboard for supporters

### 5.2 Payment Integration (RevenueCat + StoreKit 2)

**Why RevenueCat:**
- Handles App Store + server validation
- Webhooks for subscription events
- Analytics dashboard
- Cross-platform if needed later

**Endpoints:**

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/billing/entitlements` | GET | Check user's active entitlements |
| `/billing/webhook` | POST | RevenueCat webhook receiver |

**RevenueCat Webhook Events:**
- `INITIAL_PURCHASE`
- `RENEWAL`
- `CANCELLATION`
- `BILLING_ISSUE`
- `EXPIRATION`

### 5.3 SMS/Voice Billing

For users on Free tier who want SMS alerts:
- Option A: Upgrade to Premium
- Option B: Pay-as-you-go credits ($5 = 50 SMS or 10 voice minutes)

---

## 6. Emergency Alert Services

### 6.1 Alert Escalation Ladder

```
Level 1: Push Notification (free)
   ↓ no response in 1h
Level 2: SMS to Checker (premium)
   ↓ no response in 24h
Level 3: SMS to Supporters (premium)
   ↓ no response in 36h
Level 4: Voice Call to Supporters (premium)
   ↓ no response in 48h
Level 5: Emergency Escalation (opt-in)
   - Auto-call to emergency contacts
   - Optional: Wellness check request
```

### 6.2 Automated Voice Calls

**From User's Phone (CallKit):**
```swift
// Trigger outbound call from user's device
// Pros: Free, uses their minutes
// Cons: Requires app to be running, iOS limitations

import CallKit
let callController = CXCallController()
let transaction = CXTransaction(action: CXStartCallAction(call: uuid, handle: handle))
callController.request(transaction)
```

**From Server (Twilio Voice):**
```python
# Server-initiated call
# Pros: Reliable, works even if phone is off
# Cons: Costs money, feels less personal

from twilio.rest import Client
client.calls.create(
    to="+1234567890",
    from_="+1987654321",
    twiml="<Response><Say>This is an emergency wellness alert for John. Please check on them immediately.</Say></Response>"
)
```

### 6.3 Emergency Services Integration

**Important Legal Considerations:**
- Cannot directly call 911 programmatically in most jurisdictions
- False alarms can result in legal liability
- Must have explicit user consent

**Options:**

| Service | Integration | Use Case |
|---------|-------------|----------|
| **Non-Emergency Police Line** | Manual list per jurisdiction | Wellness check request |
| **Private Response Services** | API partners | ADT, Guardian, etc. |
| **Community Responders** | Custom integration | Local volunteers |

**Wellness Check Flow:**

```
1. User opts in during onboarding
2. User provides:
   - Address
   - Emergency contact
   - Local non-emergency number
   - Medical conditions (optional)
3. At Level 5 escalation:
   - Call emergency contact first
   - If no answer: Prompt supporter to call non-emergency line
   - Provide pre-written script with user's info
```

### 6.4 Private Emergency Response Partners

Consider integrating with:

| Partner | Type | Integration |
|---------|------|-------------|
| **Noonlight** | API | Certified emergency dispatch |
| **ADT Health** | Partnership | Medical alert integration |
| **Medical Guardian** | Partnership | Senior alert network |
| **Ring/Neighbors** | API | Community alerts |

**Noonlight Integration:**
```
- Certified 911 dispatch service
- Handles liability/compliance
- $X per dispatch fee
- API available
```

---

## 7. Infrastructure

### 7.1 Recommended Stack

| Component | Technology | Rationale |
|-----------|------------|-----------|
| **API Server** | Node.js + Express (TypeScript) | Matches current backend |
| **Database** | PostgreSQL (Neon) | Managed Postgres |
| **Cache** | Redis (optional) | Rate limiting, queues |
| **Queue** | Railway cron + node-cron | Background jobs |
| **Storage** | Cloudflare R2 | Selfies, exports |
| **CDN** | Cloudflare | Static assets |
| **Hosting** | Railway | Managed deployment |

### 7.2 Database Schema (Key Tables)

```sql
-- Users
CREATE TABLE users (
    id UUID PRIMARY KEY,
    phone_number VARCHAR(20) UNIQUE,
    email VARCHAR(255) UNIQUE,
    name VARCHAR(100) NOT NULL,
    is_checker BOOLEAN DEFAULT true,
    profile_image_url TEXT,
    address TEXT,
    last_known_latitude DOUBLE PRECISION,
    last_known_longitude DOUBLE PRECISION,
    last_known_address TEXT,
    last_known_location_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Schedules
CREATE TABLE schedules (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    window_start_hour INT,
    window_start_minute INT,
    window_end_hour INT,
    window_end_minute INT,
    timezone_identifier VARCHAR(50) DEFAULT 'UTC',
    active_days SMALLINT[], -- [0,1,2,3,4,5,6]
    grace_period_minutes SMALLINT DEFAULT 30,
    reminder_enabled BOOLEAN DEFAULT true,
    reminder_minutes_before SMALLINT DEFAULT 30,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Check-ins
CREATE TABLE checkins (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    timestamp TIMESTAMP NOT NULL,
    mental_score INT CHECK (mental_score BETWEEN 1 AND 5),
    body_score INT CHECK (body_score BETWEEN 1 AND 5),
    mood_score INT CHECK (mood_score BETWEEN 1 AND 5),
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    location_name VARCHAR(255),
    address TEXT,
    selfie_url TEXT,
    selfie_expires_at TIMESTAMP,
    is_manual BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Circle Links
CREATE TABLE circle_links (
    id UUID PRIMARY KEY,
    checker_id UUID REFERENCES users(id),
    supporter_id UUID REFERENCES users(id),
    supporter_display_name VARCHAR(100),
    supporter_phone VARCHAR(20),
    supporter_email VARCHAR(255),
    can_see_mood BOOLEAN DEFAULT true,
    can_see_location BOOLEAN DEFAULT false,
    can_see_selfie BOOLEAN DEFAULT false,
    can_poke BOOLEAN DEFAULT true,
    alert_priority SMALLINT DEFAULT 1,
    alert_via_push BOOLEAN DEFAULT true,
    alert_via_sms BOOLEAN DEFAULT false,
    alert_via_email BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    invited_at TIMESTAMP DEFAULT NOW(),
    accepted_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Alerts
CREATE TABLE alerts (
    id UUID PRIMARY KEY,
    checker_id UUID REFERENCES users(id),
    checker_name VARCHAR(100) NOT NULL,
    type VARCHAR(20), -- 'soft', 'hard', 'escalation'
    status VARCHAR(20) DEFAULT 'pending',
    triggered_at TIMESTAMP NOT NULL,
    missed_window_at TIMESTAMP NOT NULL,
    last_checkin_at TIMESTAMP,
    last_known_location VARCHAR(255),
    acknowledged_at TIMESTAMP,
    acknowledged_by UUID REFERENCES users(id),
    resolved_at TIMESTAMP,
    resolved_by UUID REFERENCES users(id),
    resolution VARCHAR(50),
    resolution_notes TEXT
);

-- Subscriptions (synced from RevenueCat)
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    plan VARCHAR(20),
    status VARCHAR(20) DEFAULT 'active',
    product_id VARCHAR(100),
    expires_at TIMESTAMP,
    revenue_cat_id VARCHAR(255),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

---

## 8. API Security

### 8.1 Rate Limiting

| Endpoint | Limit |
|----------|-------|
| `/auth/otp/request` | 3/hour per phone |
| `/auth/otp/verify` | 5/hour per phone |
| General API | 100/minute per user |
| Webhooks | IP whitelist |

### 8.2 Data Privacy

- All selfies encrypted at rest (R2 SSE)
- Selfies auto-deleted after 24h
- GDPR-compliant data export
- Right to deletion implemented
- Audit logs for sensitive actions

---

## 9. Development Phases

### Phase 1: MVP Backend (4-6 weeks)
- [ ] Auth service (phone OTP)
- [ ] User CRUD
- [ ] Check-in CRUD
- [ ] Circle links
- [ ] Push notifications
- [ ] Basic alerting

### Phase 2: Premium Features (3-4 weeks)
- [ ] RevenueCat integration
- [ ] SMS alerts via Twilio
- [ ] Voice call alerts
- [ ] Data export

### Phase 3: Emergency Services (4-6 weeks)
- [ ] Noonlight integration research
- [ ] Emergency contact management
- [ ] Escalation automation
- [ ] Voice message customization

### Phase 4: Scale & Polish (ongoing)
- [ ] Performance optimization
- [ ] Analytics dashboard
- [ ] Admin panel
- [ ] Multi-region deployment

---

## 10. Cost Estimates (Monthly)

| Service | Free Tier | 1K Users | 10K Users |
|---------|-----------|----------|-----------|
| Hosting (AWS/Railway) | $0-20 | $50-100 | $200-500 |
| Database (RDS/Supabase) | $0-25 | $50-100 | $200-400 |
| Twilio SMS | $0 | $50-100 | $500-1000 |
| Twilio Voice | $0 | $20-50 | $200-500 |
| Push (APNS) | Free | Free | Free |
| SendGrid Email | Free | Free | $20-50 |
| S3 Storage | $1-5 | $10-20 | $50-100 |
| RevenueCat | Free<$2.5K | 1% rev | 1% rev |
| **Total** | **~$50** | **~$300** | **~$2500** |

---

## Open Questions

1. **Jurisdiction:** Which states/countries to launch first? (affects emergency services)
2. **Liability:** Legal review needed for emergency dispatch features
3. **Offline:** How to handle check-ins when user has no connectivity?
4. **Family Sharing:** How does iOS Family Sharing affect subscription model?
5. **HIPAA:** If storing health data, do we need HIPAA compliance?

---

## Next Steps

1. **Decide:** Finalize tech stack and hosting
2. **Design:** API schema + OpenAPI spec
3. **Build:** Auth + Core services MVP
4. **Test:** End-to-end with iOS app
5. **Launch:** TestFlight beta
