# HowRU Infrastructure Plan

## Overview

Modern serverless-first stack using Railway, Vercel, and Neon with Twilio for SMS/Voice and Resend for email.

---

## 1. Stack Overview

```
┌─────────────────────────────────────────────────────────────┐
│                         Vercel                               │
│                    (Edge Functions)                          │
│              - API Routes (optional)                         │
│              - Static Assets                                 │
│              - Marketing Site                                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                        Railway                               │
│                    (Backend Services)                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │   API        │  │   Workers    │  │   Cron       │       │
│  │   Server     │  │   (Queue)    │  │   Jobs       │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
└─────────────────────────────────────────────────────────────┘
          │                   │                   │
          ▼                   ▼                   ▼
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│    Neon     │    │   Upstash   │    │   Twilio    │
│ PostgreSQL  │    │   Redis     │    │  SMS/Voice  │
└─────────────┘    └─────────────┘    └─────────────┘
                                              │
                                      ┌───────┴───────┐
                                      │    Resend     │
                                      │    Email      │
                                      └───────────────┘
```

---

## 2. Railway Setup

### Why Railway?

- Easy deployment from GitHub
- Built-in cron jobs
- Private networking between services
- Automatic SSL
- $5/month hobby plan, usage-based pro

### Services to Deploy

#### 1. API Server

```yaml
# railway.toml
[build]
builder = "nixpacks"

[deploy]
startCommand = "node dist/server.js"
healthcheckPath = "/health"
healthcheckTimeout = 100
restartPolicyType = "on_failure"
restartPolicyMaxRetries = 3

[[services]]
name = "api"
internalPort = 3000
```

#### 2. Worker Service (Queue Processing)

```yaml
[[services]]
name = "worker"
internalPort = 3001

[deploy]
startCommand = "node dist/worker.js"
```

#### 3. Cron Service

Railway supports cron jobs natively:

```yaml
[[services]]
name = "cron"

[[services.cron]]
schedule = "*/15 * * * *"  # Every 15 minutes
command = "node dist/jobs/check-missed-checkins.js"

[[services.cron]]
schedule = "0 * * * *"  # Every hour
command = "node dist/jobs/cleanup-expired-selfies.js"

[[services.cron]]
schedule = "0 0 * * *"  # Daily at midnight
command = "node dist/jobs/daily-stats.js"
```

### Environment Variables

```bash
# Database
DATABASE_URL=postgresql://user:pass@neon-host/howru?sslmode=require

# Redis
REDIS_URL=redis://default:pass@upstash-host:6379

# Auth (RS256 asymmetric keys)
JWT_PRIVATE_KEY_BASE64=<base64-encoded-private-key>
JWT_PUBLIC_KEY_BASE64=<base64-encoded-public-key>
JWT_ISSUER=howru.app
JWT_AUDIENCE=howru-api

# Twilio
TWILIO_ACCOUNT_SID=AC...
TWILIO_AUTH_TOKEN=...
TWILIO_VERIFY_SID=VA...
TWILIO_PHONE_NUMBER=+1...

# Resend
RESEND_API_KEY=re_...

# RevenueCat
REVENUECAT_API_KEY=...
REVENUECAT_WEBHOOK_SECRET=...

# Google Maps (for static map images in email alerts)
GOOGLE_MAPS_API_KEY=...

# APNs (Apple Push Notifications)
APNS_KEY_ID=...
APNS_TEAM_ID=...
APNS_KEY_BASE64=<base64-encoded-p8-key>
APNS_BUNDLE_ID=com.howru.app

# App
NODE_ENV=production
API_URL=https://api.howru.app
```

---

## 3. Neon PostgreSQL

### Why Neon?

- Serverless PostgreSQL
- Auto-scaling
- Branching for dev/staging
- Generous free tier
- Connection pooling built-in

### Setup

```bash
# Install Neon CLI
npm install -g neonctl

# Create project
neonctl projects create --name howru

# Get connection string
neonctl connection-string --project-id <id>
```

### Database Schema

```sql
-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone VARCHAR(20) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255),
    avatar_url TEXT,
    address_encrypted BYTEA,  -- AES encrypted
    timezone VARCHAR(50) DEFAULT 'America/New_York',
    -- Last known location (cached from most recent check-in for quick alert lookup)
    last_known_latitude DOUBLE PRECISION,
    last_known_longitude DOUBLE PRECISION,
    last_known_address TEXT,
    last_known_location_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_users_phone ON users(phone);
CREATE INDEX idx_users_email ON users(email) WHERE email IS NOT NULL;

-- Schedules table
CREATE TABLE schedules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE UNIQUE,
    window_start_hour SMALLINT NOT NULL CHECK (window_start_hour BETWEEN 0 AND 23),
    window_start_minute SMALLINT NOT NULL DEFAULT 0 CHECK (window_start_minute BETWEEN 0 AND 59),
    window_end_hour SMALLINT NOT NULL CHECK (window_end_hour BETWEEN 0 AND 23),
    window_end_minute SMALLINT NOT NULL DEFAULT 0 CHECK (window_end_minute BETWEEN 0 AND 59),
    grace_period_minutes SMALLINT DEFAULT 30,
    active_days SMALLINT[] DEFAULT ARRAY[0,1,2,3,4,5,6],
    reminder_enabled BOOLEAN DEFAULT true,
    reminder_minutes_before SMALLINT DEFAULT 30,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Check-ins table
CREATE TABLE checkins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    mental_score SMALLINT NOT NULL CHECK (mental_score BETWEEN 1 AND 5),
    body_score SMALLINT NOT NULL CHECK (body_score BETWEEN 1 AND 5),
    mood_score SMALLINT NOT NULL CHECK (mood_score BETWEEN 1 AND 5),
    -- Location data
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    location_name VARCHAR(255),  -- City level: "Near Cape Town"
    address TEXT,                -- Full street address for alerts
    -- Selfie (ephemeral)
    selfie_url TEXT,
    selfie_expires_at TIMESTAMPTZ,
    is_manual BOOLEAN DEFAULT true,  -- true = user initiated, false = poke response
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_checkins_user_timestamp ON checkins(user_id, timestamp DESC);
CREATE INDEX idx_checkins_selfie_expires ON checkins(selfie_expires_at) WHERE selfie_expires_at IS NOT NULL;

-- Circle links table
CREATE TABLE circle_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    checker_id UUID REFERENCES users(id) ON DELETE CASCADE,
    supporter_id UUID REFERENCES users(id) ON DELETE CASCADE,
    supporter_display_name VARCHAR(100),
    -- Supporter contact info (for non-app users)
    supporter_phone VARCHAR(20),
    supporter_email VARCHAR(255),
    -- Permissions (match SwiftData CircleLink model)
    can_see_mood BOOLEAN DEFAULT true,
    can_see_location BOOLEAN DEFAULT false,
    can_see_selfie BOOLEAN DEFAULT false,
    can_poke BOOLEAN DEFAULT true,
    alert_priority SMALLINT DEFAULT 1,
    -- Alert delivery preferences (individual booleans, not enum)
    alert_via_push BOOLEAN DEFAULT true,
    alert_via_sms BOOLEAN DEFAULT false,
    alert_via_email BOOLEAN DEFAULT false,
    -- Status
    is_active BOOLEAN DEFAULT true,
    invited_at TIMESTAMPTZ DEFAULT NOW(),
    accepted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(checker_id, supporter_id)
);

CREATE INDEX idx_circle_links_checker ON circle_links(checker_id);
CREATE INDEX idx_circle_links_supporter ON circle_links(supporter_id);

-- Invites table
CREATE TABLE invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(20) UNIQUE NOT NULL,
    inviter_id UUID REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL,  -- 'supporter' or 'checker'
    can_see_mood BOOLEAN DEFAULT true,
    can_see_selfie BOOLEAN DEFAULT false,
    can_poke BOOLEAN DEFAULT true,
    expires_at TIMESTAMPTZ NOT NULL,
    accepted_at TIMESTAMPTZ,
    accepted_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_invites_code ON invites(code);

-- Pokes table
CREATE TABLE pokes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    to_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    message TEXT,
    sent_at TIMESTAMPTZ DEFAULT NOW(),
    read_at TIMESTAMPTZ
);

CREATE INDEX idx_pokes_to_user ON pokes(to_user_id, sent_at DESC);

-- Alerts table
CREATE TABLE alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    checker_id UUID REFERENCES users(id) ON DELETE CASCADE,
    checker_name VARCHAR(100) NOT NULL,
    type VARCHAR(20) NOT NULL,  -- 'reminder', 'soft', 'hard', 'escalation'
    status VARCHAR(20) DEFAULT 'pending',  -- 'pending', 'sent', 'acknowledged', 'resolved', 'cancelled'
    triggered_at TIMESTAMPTZ NOT NULL,
    missed_window_at TIMESTAMPTZ NOT NULL,
    -- Context when alert triggered
    last_checkin_at TIMESTAMPTZ,
    last_known_location VARCHAR(255),
    -- Resolution
    acknowledged_at TIMESTAMPTZ,
    acknowledged_by UUID REFERENCES users(id),
    resolved_at TIMESTAMPTZ,
    resolved_by UUID REFERENCES users(id),
    resolution VARCHAR(50),
    resolution_notes TEXT,
    -- Track which supporters were notified
    notified_supporter_ids UUID[] DEFAULT '{}'
);

CREATE INDEX idx_alerts_checker_status ON alerts(checker_id, status);
CREATE INDEX idx_alerts_status ON alerts(status) WHERE status = 'pending';

-- Push tokens table
CREATE TABLE push_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    platform VARCHAR(10) NOT NULL,  -- 'ios', 'android'
    device_id VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, token)
);

-- Subscriptions table (synced from RevenueCat)
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE UNIQUE,
    plan VARCHAR(20) DEFAULT 'free',
    status VARCHAR(20) DEFAULT 'active',
    product_id VARCHAR(100),
    expires_at TIMESTAMPTZ,
    revenue_cat_id VARCHAR(255),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Emergency contacts table
CREATE TABLE emergency_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    relationship VARCHAR(50),
    priority SMALLINT DEFAULT 1,
    notify_on_escalation BOOLEAN DEFAULT true,
    notes_encrypted BYTEA,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Audit log table
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    resource_type VARCHAR(50),
    resource_id UUID,
    metadata JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_audit_logs_user ON audit_logs(user_id, created_at DESC);
CREATE INDEX idx_audit_logs_action ON audit_logs(action, created_at DESC);

-- Call logs table (for Twilio voice calls)
CREATE TABLE call_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    alert_id UUID REFERENCES alerts(id) ON DELETE CASCADE,
    supporter_id UUID REFERENCES users(id) ON DELETE SET NULL,
    call_sid VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL,  -- 'initiated', 'ringing', 'answered', 'completed', 'failed'
    duration_seconds INT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_call_logs_alert ON call_logs(alert_id);
CREATE INDEX idx_call_logs_supporter ON call_logs(supporter_id);

-- Daily stats table (for analytics)
CREATE TABLE daily_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    date DATE UNIQUE NOT NULL,
    active_users INT DEFAULT 0,
    total_checkins INT DEFAULT 0,
    avg_mental NUMERIC(3,2),
    avg_body NUMERIC(3,2),
    avg_mood NUMERIC(3,2),
    missed_checkins INT DEFAULT 0,
    alerts_triggered INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_daily_stats_date ON daily_stats(date DESC);

-- Data exports table (for async export jobs)
CREATE TABLE data_exports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'queued',  -- 'queued', 'processing', 'ready', 'failed'
    format VARCHAR(10) NOT NULL,  -- 'json', 'csv'
    file_url TEXT,
    file_size_bytes BIGINT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

CREATE INDEX idx_data_exports_user ON data_exports(user_id, created_at DESC);

-- Notification logs table (track all notification delivery)
CREATE TABLE notification_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    alert_id UUID REFERENCES alerts(id) ON DELETE SET NULL,
    channel VARCHAR(10) NOT NULL,  -- 'push', 'sms', 'email', 'voice'
    status VARCHAR(20) NOT NULL,   -- 'sent', 'delivered', 'failed', 'bounced'
    provider_id VARCHAR(100),      -- Twilio SID, APNs ID, Resend ID
    error_code VARCHAR(50),
    is_fallback BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_notification_logs_user ON notification_logs(user_id, created_at DESC);
CREATE INDEX idx_notification_logs_alert ON notification_logs(alert_id);

-- Updated at trigger
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER schedules_updated_at BEFORE UPDATE ON schedules
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER subscriptions_updated_at BEFORE UPDATE ON subscriptions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

---

## 4. Upstash Redis

### Why Upstash?

- Serverless Redis
- Pay per request
- Global replication
- REST API (works in edge)

### Use Cases

```typescript
// Rate limiting
await redis.incr(`rate:${userId}:${action}`);
await redis.expire(`rate:${userId}:${action}`, 60);

// Session cache
await redis.setex(`session:${token}`, 3600, JSON.stringify(user));

// Token blacklist
await redis.sadd('blacklist:tokens', token);

// Job queue (BullMQ)
const queue = new Queue('alerts', { connection: redis });
```

---

## 5. Cron Jobs

### Job 1: Check Missed Check-ins (Every 15 min)

```typescript
// jobs/check-missed-checkins.ts
import { db } from '../db';
import { alertQueue } from '../queues';

async function checkMissedCheckins() {
  const now = new Date();

  // Find users who should have checked in but haven't
  const missedUsers = await db.query(`
    SELECT u.id, u.name, s.window_end_hour, s.window_end_minute, s.grace_period_minutes
    FROM users u
    JOIN schedules s ON s.user_id = u.id
    WHERE
      -- Window + grace has passed
      (s.window_end_hour * 60 + s.window_end_minute + s.grace_period_minutes) < (
        EXTRACT(HOUR FROM NOW() AT TIME ZONE s.timezone) * 60 +
        EXTRACT(MINUTE FROM NOW() AT TIME ZONE s.timezone)
      )
      -- Today is an active day
      AND EXTRACT(DOW FROM NOW() AT TIME ZONE s.timezone)::int = ANY(s.active_days)
      -- No check-in today
      AND NOT EXISTS (
        SELECT 1 FROM checkins c
        WHERE c.user_id = u.id
        AND DATE(c.timestamp AT TIME ZONE s.timezone) = DATE(NOW() AT TIME ZONE s.timezone)
      )
      -- No pending alert
      AND NOT EXISTS (
        SELECT 1 FROM alerts a
        WHERE a.checker_id = u.id
        AND a.status = 'pending'
        AND DATE(a.missed_window_at) = DATE(NOW())
      )
  `);

  for (const user of missedUsers) {
    await alertQueue.add('create-alert', {
      userId: user.id,
      type: 'soft',
      missedAt: now
    });
  }

  console.log(`Processed ${missedUsers.length} missed check-ins`);
}

checkMissedCheckins().catch(console.error);
```

### Job 2: Escalate Alerts (Every 15 min)

```typescript
// jobs/escalate-alerts.ts
async function escalateAlerts() {
  const now = new Date();

  // Find alerts that need escalation
  const alerts = await db.query(`
    SELECT a.*, u.name as checker_name
    FROM alerts a
    JOIN users u ON u.id = a.checker_id
    WHERE a.status = 'pending'
  `);

  for (const alert of alerts) {
    const hoursSinceMissed = (now.getTime() - new Date(alert.missed_window_at).getTime()) / (1000 * 60 * 60);

    if (hoursSinceMissed >= 48 && alert.type !== 'escalation') {
      await escalateToEmergency(alert);
    } else if (hoursSinceMissed >= 36 && alert.type === 'soft') {
      await escalateToHard(alert);
    } else if (hoursSinceMissed >= 24 && alert.type === 'soft') {
      await notifyMoreSupporters(alert);
    }
  }
}
```

### Job 3: Cleanup Expired Selfies (Hourly)

```typescript
// jobs/cleanup-selfies.ts
import { s3 } from '../storage';

async function cleanupExpiredSelfies() {
  const expired = await db.query(`
    SELECT id, selfie_url
    FROM checkins
    WHERE selfie_expires_at < NOW()
    AND selfie_url IS NOT NULL
  `);

  for (const checkin of expired) {
    // Delete from S3
    const key = extractS3Key(checkin.selfie_url);
    await s3.deleteObject({ Bucket: 'howru-selfies', Key: key });

    // Update database
    await db.query(`
      UPDATE checkins
      SET selfie_url = NULL, selfie_expires_at = NULL
      WHERE id = $1
    `, [checkin.id]);
  }

  console.log(`Cleaned up ${expired.length} expired selfies`);
}
```

### Job 4: Daily Stats (Midnight UTC)

```typescript
// jobs/daily-stats.ts
async function generateDailyStats() {
  const yesterday = new Date();
  yesterday.setDate(yesterday.getDate() - 1);

  const stats = await db.query(`
    SELECT
      COUNT(DISTINCT user_id) as active_users,
      COUNT(*) as total_checkins,
      AVG(mental_score) as avg_mental,
      AVG(body_score) as avg_body,
      AVG(mood_score) as avg_mood
    FROM checkins
    WHERE DATE(timestamp) = $1
  `, [yesterday.toISOString().split('T')[0]]);

  // Store in analytics table or send to analytics service
  await db.query(`
    INSERT INTO daily_stats (date, active_users, total_checkins, avg_mental, avg_body, avg_mood)
    VALUES ($1, $2, $3, $4, $5, $6)
  `, [yesterday, stats.active_users, stats.total_checkins, stats.avg_mental, stats.avg_body, stats.avg_mood]);
}
```

---

## 6. Twilio Integration

### SMS via Twilio

```typescript
// services/sms.ts
import twilio from 'twilio';

const client = twilio(
  process.env.TWILIO_ACCOUNT_SID,
  process.env.TWILIO_AUTH_TOKEN
);

export async function sendSMS(to: string, body: string) {
  const message = await client.messages.create({
    to,
    from: process.env.TWILIO_PHONE_NUMBER,
    body,
    statusCallback: `${process.env.API_URL}/webhooks/twilio/sms-status`
  });

  return message.sid;
}

export async function sendAlertSMS(supporter: User, checker: User, alert: Alert) {
  const body = `HowRU Alert: ${checker.name} hasn't checked in for ${alert.hoursSinceMissed} hours. Please check on them. Tap to call: tel:${checker.phone}`;

  return sendSMS(supporter.phone, body);
}
```

### Voice Calls via Twilio

```typescript
// services/voice.ts
export async function initiateAlertCall(
  supporter: User,
  checker: User,
  alert: Alert
) {
  const call = await client.calls.create({
    to: supporter.phone,
    from: process.env.TWILIO_PHONE_NUMBER,
    url: `${process.env.API_URL}/voice/alert/${alert.id}`,
    statusCallback: `${process.env.API_URL}/webhooks/twilio/call-status`,
    statusCallbackEvent: ['initiated', 'ringing', 'answered', 'completed']
  });

  // Log call attempt
  await db.query(`
    INSERT INTO call_logs (alert_id, supporter_id, call_sid, status)
    VALUES ($1, $2, $3, 'initiated')
  `, [alert.id, supporter.id, call.sid]);

  return call.sid;
}

// TwiML endpoint
app.post('/voice/alert/:alertId', async (req, res) => {
  const alert = await getAlert(req.params.alertId);
  const checker = await getUser(alert.checker_id);

  const twiml = new VoiceResponse();

  // Use neural voice for natural sound
  twiml.say({
    voice: 'Polly.Joanna',  // Or 'Polly.Matthew' for male
    language: 'en-US'
  }, `This is an urgent wellness alert from How Are You. ${checker.name} has not checked in for ${Math.round(alert.hoursSinceMissed)} hours. Please check on them immediately.`);

  // Gather response
  const gather = twiml.gather({
    numDigits: 1,
    action: `/voice/response/${req.params.alertId}`,
    timeout: 10
  });

  gather.say({
    voice: 'Polly.Joanna'
  }, 'Press 1 to acknowledge this alert. Press 2 to hear contact information. Press 9 to repeat this message.');

  // No response - repeat
  twiml.redirect(`/voice/alert/${req.params.alertId}`);

  res.type('text/xml');
  res.send(twiml.toString());
});

// Handle response
app.post('/voice/response/:alertId', async (req, res) => {
  const digit = req.body.Digits;
  const twiml = new VoiceResponse();

  switch (digit) {
    case '1':
      await acknowledgeAlert(req.params.alertId, req.body.Called);
      twiml.say({ voice: 'Polly.Joanna' },
        'Thank you. The alert has been acknowledged. Please check on them as soon as possible. Goodbye.');
      twiml.hangup();
      break;

    case '2':
      const alert = await getAlert(req.params.alertId);
      const checker = await getUser(alert.checker_id);
      twiml.say({ voice: 'Polly.Joanna' },
        `${checker.name}'s phone number is ${formatPhoneForSpeech(checker.phone)}. I repeat, ${formatPhoneForSpeech(checker.phone)}.`);
      twiml.redirect(`/voice/alert/${req.params.alertId}`);
      break;

    case '9':
    default:
      twiml.redirect(`/voice/alert/${req.params.alertId}`);
  }

  res.type('text/xml');
  res.send(twiml.toString());
});

function formatPhoneForSpeech(phone: string): string {
  // "+15551234567" -> "5 5 5, 1 2 3, 4 5 6 7"
  const digits = phone.replace(/\D/g, '').slice(-10);
  return `${digits.slice(0,3).split('').join(' ')}, ${digits.slice(3,6).split('').join(' ')}, ${digits.slice(6).split('').join(' ')}`;
}
```

### Alert Message Templates (SMS)

SMS messages are tiered by severity level, progressively adding more context as urgency increases.

> **SMS Segment Guidelines:**
> - Standard SMS segment = 160 chars (GSM-7) or 70 chars (Unicode/emoji)
> - Variable fields MUST be truncated to prevent overflow:
>   - `{name}`: max 15 chars, truncate with "…"
>   - `{locationName}`: max 25 chars
>   - `{address}`: max 40 chars
>   - `{mapURL}`: use short link `howru.app/m/{id}` (~20 chars)
>   - `{ackURL}`: use short link `howru.app/a/{id}` (~20 chars)
> - Always calculate final message length before sending
> - Log segment count for cost monitoring

```typescript
// SMS truncation helpers
const truncate = (s: string, max: number) => s.length > max ? s.slice(0, max - 1) + '…' : s;
const smsName = (name: string) => truncate(name, 15);
const smsLocation = (loc: string) => truncate(loc, 25);
const smsAddress = (addr: string) => truncate(addr, 40);
const countSegments = (msg: string) => msg.match(/[^\x00-\x7F]/) ? Math.ceil(msg.length / 70) : Math.ceil(msg.length / 160);
```

#### Soft Alert (+24h) - 160 chars max

```
HowRU: {name} hasn't checked in for 24h. Last seen: {locationName}. Call: {phone}
```

Example:
```
HowRU: Mom hasn't checked in for 24h. Last seen: Near Cape Town. Call: +27123456789
```

#### Hard Alert (+36h) - 320 chars (2 segments)

```
URGENT HowRU Alert: {name} hasn't checked in for 36 hours.

Last known location: {address}
Map: {mapURL}

Call them: {phone}

Tap to acknowledge: {ackURL}
```

Example:
```
URGENT HowRU Alert: Mom hasn't checked in for 36 hours.

Last known location: 123 Main St, Cape Town
Map: howru.app/m/x7k

Call them: +27123456789

Tap to acknowledge: howru.app/a/abc123
```

#### Escalation Alert (+48h) - 480 chars (3 segments)

```
🚨 EMERGENCY HowRU Alert 🚨

{name} hasn't checked in for 48 HOURS.

Last check-in: {lastCheckInTime}
Mood: 🧠{mental} 💪{body} 💛{mood}
Location: {address}
Map: {mapURL}

IMMEDIATE ACTION REQUIRED:
📞 Call: {phone}
🏠 Home: {homeAddress}

Other supporters have been notified.

Acknowledge: {ackURL}
```

### Alert Message Templates (Email)

Email provides the richest context with embedded maps and action buttons.

```typescript
// templates/alert-email.ts
interface AlertEmailData {
  supporter: { name: string; email: string };
  checker: {
    name: string;
    phone: string;
    homeAddress?: string;
    lastKnownLatitude?: number;
    lastKnownLongitude?: number;
    lastKnownAddress?: string;
    lastKnownLocationAt?: Date;
  };
  alert: {
    id: string;
    type: 'soft' | 'hard' | 'escalation';
    hoursSinceMissed: number;
    missedWindowAt: Date;
  };
  lastCheckIn?: {
    timestamp: Date;
    mentalScore: number;
    bodyScore: number;
    moodScore: number;
  };
}

export function generateAlertEmailHTML(data: AlertEmailData): string {
  const { supporter, checker, alert, lastCheckIn } = data;

  const urgencyColor = {
    soft: '#FFC107',      // Yellow
    hard: '#FF9800',      // Orange
    escalation: '#DC3545' // Red
  }[alert.type];

  const mapImageUrl = checker.lastKnownLatitude && checker.lastKnownLongitude
    ? `https://maps.googleapis.com/maps/api/staticmap?center=${checker.lastKnownLatitude},${checker.lastKnownLongitude}&zoom=14&size=600x300&markers=color:red%7C${checker.lastKnownLatitude},${checker.lastKnownLongitude}&key=${process.env.GOOGLE_MAPS_API_KEY}`
    : null;

  const googleMapsUrl = checker.lastKnownLatitude && checker.lastKnownLongitude
    ? `https://maps.google.com/maps?q=${checker.lastKnownLatitude},${checker.lastKnownLongitude}`
    : null;

  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>HowRU Alert</title>
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 20px; background: #f5f5f5;">
  <div style="max-width: 600px; margin: 0 auto; background: white; border-radius: 12px; overflow: hidden; box-shadow: 0 2px 10px rgba(0,0,0,0.1);">

    <!-- Header -->
    <div style="background: ${urgencyColor}; padding: 20px; text-align: center;">
      <h1 style="margin: 0; color: white; font-size: 24px;">
        ${alert.type === 'escalation' ? '🚨 EMERGENCY ALERT 🚨' : alert.type === 'hard' ? '⚠️ URGENT ALERT' : '⚡ Wellness Alert'}
      </h1>
    </div>

    <!-- Main Content -->
    <div style="padding: 30px;">
      <h2 style="margin: 0 0 10px; color: #333;">
        ${checker.name} hasn't checked in
      </h2>
      <p style="font-size: 18px; color: #666; margin: 0 0 20px;">
        It's been <strong style="color: ${urgencyColor};">${alert.hoursSinceMissed} hours</strong> since their check-in window.
      </p>

      <!-- Last Check-in Info -->
      ${lastCheckIn ? `
      <div style="background: #f8f9fa; border-radius: 8px; padding: 15px; margin-bottom: 20px;">
        <h3 style="margin: 0 0 10px; font-size: 14px; color: #666; text-transform: uppercase;">Last Check-in</h3>
        <p style="margin: 0; color: #333;">
          <strong>${formatDateTime(lastCheckIn.timestamp)}</strong><br>
          Mind: ${'⭐'.repeat(lastCheckIn.mentalScore)} |
          Body: ${'⭐'.repeat(lastCheckIn.bodyScore)} |
          Mood: ${'⭐'.repeat(lastCheckIn.moodScore)}
        </p>
      </div>
      ` : ''}

      <!-- Location Section -->
      ${checker.lastKnownAddress || mapImageUrl ? `
      <div style="margin-bottom: 20px;">
        <h3 style="margin: 0 0 10px; font-size: 14px; color: #666; text-transform: uppercase;">Last Known Location</h3>
        ${checker.lastKnownAddress ? `
        <p style="margin: 0 0 10px; color: #333; font-size: 16px;">
          📍 ${checker.lastKnownAddress}
          ${checker.lastKnownLocationAt ? `<br><span style="color: #999; font-size: 12px;">as of ${formatDateTime(checker.lastKnownLocationAt)}</span>` : ''}
        </p>
        ` : ''}
        ${mapImageUrl ? `
        <a href="${googleMapsUrl}" target="_blank" style="display: block;">
          <img src="${mapImageUrl}" alt="Location map" style="width: 100%; border-radius: 8px; border: 1px solid #ddd;">
        </a>
        <p style="text-align: center; margin: 10px 0 0;">
          <a href="${googleMapsUrl}" style="color: #007AFF; text-decoration: none;">Open in Google Maps →</a>
        </p>
        ` : ''}
      </div>
      ` : ''}

      <!-- Action Buttons -->
      <div style="margin: 30px 0;">
        <a href="tel:${checker.phone}" style="display: inline-block; background: #FF6B6B; color: white; padding: 15px 30px; border-radius: 8px; text-decoration: none; font-weight: bold; font-size: 18px; margin-right: 10px; margin-bottom: 10px;">
          📞 Call ${checker.name}
        </a>
        <a href="https://howru.app/alert/${alert.id}/acknowledge" style="display: inline-block; background: #28a745; color: white; padding: 15px 30px; border-radius: 8px; text-decoration: none; font-weight: bold; font-size: 18px;">
          ✓ I've Checked On Them
        </a>
      </div>

      <!-- Contact Info -->
      <div style="background: #f8f9fa; border-radius: 8px; padding: 15px;">
        <h3 style="margin: 0 0 10px; font-size: 14px; color: #666; text-transform: uppercase;">Contact Information</h3>
        <p style="margin: 0; color: #333;">
          <strong>Phone:</strong> <a href="tel:${checker.phone}" style="color: #007AFF;">${formatPhone(checker.phone)}</a><br>
          ${checker.homeAddress ? `<strong>Home:</strong> ${checker.homeAddress}` : ''}
        </p>
      </div>

      ${alert.type === 'escalation' ? `
      <!-- Emergency Notice -->
      <div style="background: #fff3cd; border: 1px solid #ffc107; border-radius: 8px; padding: 15px; margin-top: 20px;">
        <p style="margin: 0; color: #856404;">
          <strong>⚠️ Other supporters have been notified.</strong><br>
          If you cannot reach ${checker.name}, consider contacting local emergency services.
        </p>
      </div>
      ` : ''}
    </div>

    <!-- Footer -->
    <div style="background: #f8f9fa; padding: 20px; text-align: center; border-top: 1px solid #eee;">
      <p style="margin: 0; color: #999; font-size: 12px;">
        You're receiving this because you're a supporter for ${checker.name} on HowRU.<br>
        <a href="https://howru.app/settings/notifications" style="color: #666;">Manage notification preferences</a>
      </p>
    </div>
  </div>
</body>
</html>
  `;
}

function formatDateTime(date: Date): string {
  return new Intl.DateTimeFormat('en-US', {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    hour12: true
  }).format(new Date(date));
}

function formatPhone(phone: string): string {
  const digits = phone.replace(/\D/g, '');
  if (digits.length === 10) {
    return `(${digits.slice(0,3)}) ${digits.slice(3,6)}-${digits.slice(6)}`;
  }
  return phone;
}
```

### Update User Location on Check-in

```typescript
// After saving a check-in, update user's last known location
async function saveCheckIn(userId: string, checkInData: CheckInInput) {
  const checkin = await db.query(`
    INSERT INTO checkins (user_id, mental_score, body_score, mood_score, latitude, longitude, location_name, address, is_manual, timestamp)
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
    RETURNING *
  `, [userId, checkInData.mentalScore, checkInData.bodyScore, checkInData.moodScore,
      checkInData.latitude, checkInData.longitude, checkInData.locationName, checkInData.address,
      checkInData.isManual ?? true, checkInData.timestamp ?? new Date()]);

  // Update user's cached location for quick alert lookup
  // IMPORTANT: Use the check-in timestamp, not NOW(), to avoid skew from delayed ingestion
  if (checkInData.latitude && checkInData.longitude) {
    const locationTimestamp = checkInData.timestamp ?? checkin.rows[0].timestamp;
    await db.query(`
      UPDATE users
      SET last_known_latitude = $2,
          last_known_longitude = $3,
          last_known_address = $4,
          last_known_location_at = $5,
          updated_at = NOW()
      WHERE id = $1
    `, [userId, checkInData.latitude, checkInData.longitude,
        checkInData.address || checkInData.locationName, locationTimestamp]);
  }

  return checkin.rows[0];
}
```

### Twilio Voice Options

| Voice | Type | Description |
|-------|------|-------------|
| `Polly.Joanna` | Neural | Female, US, natural |
| `Polly.Matthew` | Neural | Male, US, natural |
| `Polly.Amy` | Neural | Female, UK, natural |
| `alice` | Standard | Female, classic |
| `man` | Standard | Male, classic |

---

## 7. Resend Email Integration

### Why Resend?

- Modern API
- Great deliverability
- React Email support
- Generous free tier (3K/month)
- **Fallback for SMS** - critical redundancy when Twilio SMS fails

### SMS Fallback Strategy

When SMS fails (carrier issues, invalid number, international restrictions), Resend email serves as a reliable fallback:

```
SMS Attempt → Failed → Check if user has email → Send via Resend
                ↓
         Log failure for analytics
```

**Failure Scenarios Where Email Fallback Activates:**

| Twilio Error | Description | Email Fallback? |
|--------------|-------------|-----------------|
| `30003` | Unreachable destination | Yes |
| `30004` | Message blocked | Yes |
| `30005` | Unknown destination | Yes |
| `30006` | Landline or unreachable | Yes |
| `30007` | Carrier violation | Yes |
| `21211` | Invalid phone number | Yes |
| `21614` | Not a mobile number | Yes |

### Notification Service with Fallback

```typescript
// services/notification.ts
import { sendSMS, SMSError } from './sms';
import { sendEmail } from './email';
import { db } from '../db';

interface NotificationResult {
  channel: 'sms' | 'email' | 'push';
  success: boolean;
  messageId?: string;
  error?: string;
}

export async function sendAlertNotification(
  user: User,
  alert: Alert,
  checker: User
): Promise<NotificationResult[]> {
  const results: NotificationResult[] = [];

  // 1. Always try push first (free, instant)
  try {
    const pushResult = await sendPushNotification(user, {
      title: `Alert: ${checker.name} hasn't checked in`,
      body: `It's been ${alert.hoursSinceMissed} hours. Please check on them.`,
      data: { alertId: alert.id, type: 'alert' }
    });
    results.push({ channel: 'push', success: true, messageId: pushResult.id });
  } catch (error) {
    results.push({ channel: 'push', success: false, error: error.message });
  }

  // 2. Try SMS if user has premium
  if (user.subscription?.plan !== 'free' && user.phone) {
    try {
      const smsResult = await sendAlertSMS(user, checker, alert);
      results.push({ channel: 'sms', success: true, messageId: smsResult });

      // SMS succeeded, no need for email fallback
      return results;
    } catch (error) {
      const smsError = error as SMSError;
      results.push({ channel: 'sms', success: false, error: smsError.code });

      // Log SMS failure
      await db.query(`
        INSERT INTO notification_logs (user_id, alert_id, channel, status, error_code)
        VALUES ($1, $2, 'sms', 'failed', $3)
      `, [user.id, alert.id, smsError.code]);

      // Fall through to email
    }
  }

  // 3. Email fallback (or primary if no premium SMS)
  if (user.email) {
    try {
      const emailResult = await sendAlertEmail(user, checker, alert);
      results.push({ channel: 'email', success: true, messageId: emailResult.id });

      // Log that we used email as fallback
      await db.query(`
        INSERT INTO notification_logs (user_id, alert_id, channel, status, is_fallback)
        VALUES ($1, $2, 'email', 'sent', $3)
      `, [user.id, alert.id, results.some(r => r.channel === 'sms' && !r.success)]);
    } catch (error) {
      results.push({ channel: 'email', success: false, error: error.message });
    }
  }

  return results;
}

// SMS wrapper with error classification
export async function sendAlertSMS(
  supporter: User,
  checker: User,
  alert: Alert
): Promise<string> {
  try {
    return await sendSMS(
      supporter.phone,
      `HowRU Alert: ${checker.name} hasn't checked in for ${alert.hoursSinceMissed} hours. Please check on them.`
    );
  } catch (error: any) {
    // Classify Twilio error for fallback decision
    const twilioError: SMSError = {
      code: error.code?.toString() || 'UNKNOWN',
      message: error.message,
      shouldFallback: [
        '30003', '30004', '30005', '30006', '30007',
        '21211', '21614', '21408'
      ].includes(error.code?.toString())
    };
    throw twilioError;
  }
}

interface SMSError {
  code: string;
  message: string;
  shouldFallback: boolean;
}
```

### Alert Email Template (Fallback Version)

```typescript
// templates/alert-fallback-email.ts
export function alertFallbackEmailTemplate(
  supporter: User,
  checker: User,
  alert: Alert,
  isSMSFallback: boolean
): string {
  return `
<!DOCTYPE html>
<html>
<head>
  <style>
    .alert-box {
      background: #FFF3CD;
      border: 1px solid #FFC107;
      border-radius: 8px;
      padding: 20px;
      margin: 20px 0;
    }
    .urgent-box {
      background: #F8D7DA;
      border: 1px solid #DC3545;
    }
    .action-button {
      background: #FF6B6B;
      color: white;
      padding: 12px 24px;
      border-radius: 8px;
      text-decoration: none;
      display: inline-block;
      margin: 10px 5px 10px 0;
    }
    .phone-link {
      font-size: 24px;
      font-weight: bold;
      color: #007AFF;
    }
    ${isSMSFallback ? '.fallback-notice { background: #E7F3FF; padding: 10px; border-radius: 4px; font-size: 12px; color: #666; }' : ''}
  </style>
</head>
<body>
  <h1>Wellness Alert</h1>

  ${isSMSFallback ? `
  <div class="fallback-notice">
    This email was sent because we couldn't reach you via SMS.
    <a href="https://howru.app/settings/notifications">Update your phone number</a>
  </div>
  ` : ''}

  <div class="alert-box ${alert.type === 'escalation' ? 'urgent-box' : ''}">
    <h2>${checker.name} hasn't checked in</h2>
    <p>It's been <strong>${alert.hoursSinceMissed} hours</strong> since their last check-in.</p>
  </div>

  <h3>Take Action</h3>

  <p>Call ${checker.name}:</p>
  <a href="tel:${checker.phone}" class="phone-link">${formatPhone(checker.phone)}</a>

  <br><br>

  <a href="https://howru.app/alert/${alert.id}/acknowledge" class="action-button">
    I've Checked On Them
  </a>

  <a href="https://howru.app/alert/${alert.id}" class="action-button" style="background: #6C757D;">
    View Details
  </a>

  <hr>
  <p style="font-size: 12px; color: #666;">
    You're receiving this because you're a supporter for ${checker.name} on HowRU.
    <a href="https://howru.app/settings/notifications">Manage notifications</a>
  </p>
</body>
</html>
  `;
}
```

### Notification Preference Model

Allow users to set their preferred notification order:

```sql
-- Add to users table or create notification_preferences table
ALTER TABLE users ADD COLUMN notification_preference VARCHAR(20) DEFAULT 'sms_first';
-- Options: 'sms_first', 'email_first', 'sms_only', 'email_only', 'both'

-- Track notification delivery
CREATE TABLE notification_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    alert_id UUID REFERENCES alerts(id),
    channel VARCHAR(10) NOT NULL,  -- 'push', 'sms', 'email', 'voice'
    status VARCHAR(20) NOT NULL,   -- 'sent', 'delivered', 'failed', 'bounced'
    error_code VARCHAR(50),
    is_fallback BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_notification_logs_user ON notification_logs(user_id, created_at DESC);
CREATE INDEX idx_notification_logs_alert ON notification_logs(alert_id);
```

### Notification Priority Chain

```
┌─────────────────────────────────────────────────────────────────┐
│                    Alert Triggered                               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  1. Push Notification (always, free)                            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │ User has SMS?   │
                    │ (Premium)       │
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              │ Yes                         │ No
              ▼                             ▼
┌─────────────────────────┐    ┌─────────────────────────┐
│  2. Try SMS (Twilio)    │    │  Skip to Email          │
└───────────┬─────────────┘    └───────────┬─────────────┘
            │                              │
     ┌──────┴──────┐                       │
     │ Success?    │                       │
     └──────┬──────┘                       │
            │                              │
     ┌──────┴──────┐                       │
     │ Yes         │ No (failed)           │
     ▼             ▼                       │
  [Done]    ┌─────────────────┐            │
            │ User has email? │◄───────────┘
            └────────┬────────┘
                     │
              ┌──────┴──────┐
              │ Yes         │ No
              ▼             ▼
┌─────────────────────────┐  ┌─────────────────────────┐
│  3. Email (Resend)      │  │  Log: No contact method │
│     (fallback)          │  │  Escalate sooner        │
└─────────────────────────┘  └─────────────────────────┘
```

```typescript
// services/email.ts
import { Resend } from 'resend';

const resend = new Resend(process.env.RESEND_API_KEY);

export async function sendEmail(
  to: string,
  subject: string,
  html: string
) {
  const { data, error } = await resend.emails.send({
    from: 'HowRU <alerts@howru.app>',
    to,
    subject,
    html
  });

  if (error) throw error;
  return data;
}

// Email templates
export async function sendWelcomeEmail(user: User) {
  await sendEmail(
    user.email,
    'Welcome to HowRU!',
    `
    <h1>Welcome, ${user.name}!</h1>
    <p>Thank you for joining HowRU. Your wellness journey starts now.</p>
    <p>Set up your daily check-in schedule to get started.</p>
    `
  );
}

export async function sendAlertEmail(supporter: User, checker: User, alert: Alert) {
  await sendEmail(
    supporter.email,
    `⚠️ Alert: ${checker.name} hasn't checked in`,
    `
    <h1>Wellness Alert</h1>
    <p>${checker.name} hasn't checked in for ${alert.hoursSinceMissed} hours.</p>
    <p>Please check on them or call: ${checker.phone}</p>
    <a href="https://howru.app/alert/${alert.id}">View Alert</a>
    `
  );
}
```

---

## 8. File Storage (S3/R2)

### Cloudflare R2 (S3-compatible, cheaper)

```typescript
// services/storage.ts
import { S3Client, PutObjectCommand, DeleteObjectCommand } from '@aws-sdk/client-s3';

const s3 = new S3Client({
  region: 'auto',
  endpoint: process.env.R2_ENDPOINT,
  credentials: {
    accessKeyId: process.env.R2_ACCESS_KEY,
    secretAccessKey: process.env.R2_SECRET_KEY
  }
});

export async function uploadSelfie(
  userId: string,
  checkinId: string,
  imageBuffer: Buffer
): Promise<string> {
  const key = `selfies/${userId}/${checkinId}.jpg`;

  await s3.send(new PutObjectCommand({
    Bucket: 'howru-selfies',
    Key: key,
    Body: imageBuffer,
    ContentType: 'image/jpeg'
  }));

  return `${process.env.CDN_URL}/${key}`;
}

export async function deleteSelfie(url: string) {
  const key = url.replace(`${process.env.CDN_URL}/`, '');

  await s3.send(new DeleteObjectCommand({
    Bucket: 'howru-selfies',
    Key: key
  }));
}
```

---

## 9. Cost Estimates

### Monthly Costs (1K Users)

| Service | Tier | Cost |
|---------|------|------|
| Railway | Pro | ~$20-50 |
| Neon | Free/Launch | $0-19 |
| Upstash Redis | Free | $0 |
| Twilio SMS (~500) | Pay-as-you-go | ~$5-10 |
| Twilio Voice (~50 min) | Pay-as-you-go | ~$2-5 |
| Resend (~1000) | Free | $0 |
| Cloudflare R2 | Free tier | $0 |
| **Total** | | **~$30-80** |

### Monthly Costs (10K Users)

| Service | Tier | Cost |
|---------|------|------|
| Railway | Pro | ~$100-200 |
| Neon | Scale | ~$50-100 |
| Upstash Redis | Pro | ~$20 |
| Twilio SMS (~5000) | Pay-as-you-go | ~$50-100 |
| Twilio Voice (~500 min) | Pay-as-you-go | ~$20-50 |
| Resend (~10000) | Pro | ~$20 |
| Cloudflare R2 | Pay-as-you-go | ~$10 |
| **Total** | | **~$300-500** |

---

## 10. Deployment Checklist

### Initial Setup

- [ ] Create Railway project
- [ ] Create Neon database
- [ ] Create Upstash Redis
- [ ] Set up Twilio account
- [ ] Create Resend account
- [ ] Create Cloudflare R2 bucket
- [ ] Configure environment variables

### Deploy Services

- [ ] Deploy API server
- [ ] Deploy worker service
- [ ] Configure cron jobs
- [ ] Set up custom domain
- [ ] Configure SSL

### Monitoring

- [ ] Set up Railway logs
- [ ] Configure error alerting (Sentry)
- [ ] Set up uptime monitoring

---

## Next Steps

1. Create Railway project and link to GitHub repo
2. Set up Neon database and run migrations
3. Configure Twilio for SMS/Voice
4. Build and deploy API server
5. Test end-to-end flow
