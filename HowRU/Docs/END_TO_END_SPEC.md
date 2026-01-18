# HowRU End-to-End Spec

Status: Draft
Owner: Product + Engineering
Last updated: 2025-01-18

## 1. Goals and Scope
- Deliver a production backend and integrations for the HowRU iOS app.
- Support phone OTP auth, check-ins, circle management, alerts, payments, and emergency escalation.
- Enable offline-friendly client behavior with server as the system of record.

Non-goals for this spec:
- Android app.
- Web admin console (tracked separately).
- Real-time chat or telehealth.

## 2. Canonical Stack
- Hosting: Railway (API service, worker service, cron jobs).
- Database: Neon Postgres.
- Cache/Queues: Upstash Redis (rate limiting, token blacklist, BullMQ).
- SMS/Voice: Twilio Verify + Programmable SMS + Voice.
- Email: Resend.
- Payments: RevenueCat + StoreKit 2.
- File storage: Cloudflare R2 (S3-compatible) + CDN.
- Push: APNs HTTP/2.

## 3. Architecture Overview
```
                    iOS App
                      |
                      v
               API Gateway (Railway)
                      |
          +-----------+-----------+
          |                       |
     API Service              Worker Service
          |                       |
          +-----------+-----------+
                      |
                 Neon Postgres
                      |
                 Upstash Redis
                      |
   +--------+---------+--------+---------+--------+
   |        |                  |         |        |
 Twilio   Resend             RevenueCat  APNs     R2
```

## 4. Environments
- Local: mock providers and local DB/Redis where possible.
- Staging: real integrations with sandbox keys.
- Production: real integrations, hardened rate limits, and alerting.

## 5. Auth and Identity
### OTP Flow
1. Client -> POST `/auth/otp/request` with phone (E.164).
2. API -> Twilio Verify sends OTP.
3. Client -> POST `/auth/otp/verify` with phone + code.
4. API verifies with Twilio, creates or fetches user, issues tokens.

### Token Strategy
- Access token: JWT RS256, 1 hour TTL.
- Refresh token: 30 days TTL, rotation on each refresh.
- Refresh token storage: store SHA-256 hash in `refresh_tokens`.
- Revocation: mark token revoked; also maintain a short-lived Redis blacklist.

### Rate Limiting
- `/auth/otp/request`: 3 requests per phone per hour.
- `/auth/otp/verify`: 5 attempts per phone per hour.
- `/auth/refresh`: 10 requests per user per minute.
- Global API: 100 requests per user per minute.

## 6. Data Model (Canonical)
### 6.1 users
- id (uuid, pk)
- phone_e164 (unique, not null)
- phone_verified_at (timestamptz)
- name (varchar)
- email (varchar)
- avatar_url (text)
- address_encrypted (bytea)
- is_checker (boolean, default true)
- created_at, updated_at, deleted_at
Indexes: phone_e164, email (partial), deleted_at.

### 6.2 schedules
- id (uuid, pk)
- user_id (uuid, unique, fk users)
- window_start_hour, window_start_minute
- window_end_hour, window_end_minute
- timezone (varchar)
- active_days (smallint array)
- grace_period_minutes (smallint)
- reminder_enabled (boolean)
- reminder_minutes_before (smallint)
- is_active (boolean)
- created_at, updated_at
Indexes: user_id.

### 6.3 checkins
- id (uuid, pk)
- user_id (uuid, fk users)
- timestamp (timestamptz)
- mental_score, body_score, mood_score (smallint)
- location_name (varchar)
- latitude, longitude (double precision)
- selfie_url (text)
- selfie_expires_at (timestamptz)
- is_manual_checkin (boolean)
- created_at
Indexes: (user_id, timestamp desc), selfie_expires_at (partial).

### 6.4 circle_links
- id (uuid, pk)
- checker_id (uuid, fk users)
- supporter_user_id (uuid, fk users, nullable)
- supporter_name (varchar)
- supporter_phone (varchar)
- supporter_email (varchar)
- can_see_mood, can_see_location, can_see_selfie, can_poke (boolean)
- alert_via_push, alert_via_sms, alert_via_email (boolean)
- alert_priority (smallint)
- invited_at, accepted_at
- is_active (boolean)
Indexes: checker_id, supporter_user_id.

### 6.5 invites
- id (uuid, pk)
- code (varchar, unique)
- inviter_id (uuid, fk users)
- role (varchar)  // supporter or checker
- permissions (jsonb)
- expires_at, accepted_at
- accepted_by (uuid, fk users)
- created_at
Indexes: code.

### 6.6 pokes
- id (uuid, pk)
- from_user_id (uuid, fk users)
- to_user_id (uuid, fk users)
- message (text)
- sent_at, read_at, responded_at
Indexes: (to_user_id, sent_at desc).

### 6.7 alerts
- id (uuid, pk)
- checker_id (uuid, fk users)
- level (varchar)  // reminder, soft, hard, escalation
- status (varchar) // pending, sent, acknowledged, resolved, cancelled
- triggered_at, missed_window_at
- acknowledged_at, acknowledged_by
- resolved_at, resolved_by
- resolution (varchar)
- resolution_notes (text)
- last_checkin_at (timestamptz)
- last_known_location (text)
Indexes: (checker_id, status), status (partial for pending).

### 6.8 alert_notifications
- id (uuid, pk)
- alert_id (uuid, fk alerts)
- supporter_id (uuid, fk users)
- channel (varchar) // push, sms, voice, email
- status (varchar)  // queued, sent, delivered, failed
- provider_id (varchar) // Twilio SID, APNs ID, etc
- sent_at
Indexes: (alert_id, supporter_id).

### 6.9 emergency_contacts
- id (uuid, pk)
- user_id (uuid, fk users)
- name, phone, relationship (varchar)
- priority (smallint)
- notify_on_escalation (boolean)
- notes_encrypted (bytea)
- created_at
Indexes: user_id.

### 6.10 subscriptions
- id (uuid, pk)
- user_id (uuid, fk users, unique)
- plan (varchar)  // free, premium, family
- status (varchar) // active, canceled, expired
- product_id (varchar)
- store (varchar)
- expires_at (timestamptz)
- is_sandbox (boolean)
- revenue_cat_id (varchar)
- created_at, updated_at
Indexes: user_id, status.

### 6.11 push_tokens
- id (uuid, pk)
- user_id (uuid, fk users)
- token (text, unique per user)
- platform (varchar) // ios
- environment (varchar) // sandbox, prod
- device_id (varchar)
- last_seen_at, created_at, updated_at
Indexes: user_id.

### 6.12 refresh_tokens
- id (uuid, pk)
- user_id (uuid, fk users)
- token_hash (text)
- issued_at, expires_at
- revoked_at
- replaced_by (uuid, fk refresh_tokens)
Indexes: user_id, token_hash.

### 6.13 audit_logs
- id (uuid, pk)
- user_id (uuid, fk users, nullable)
- action (varchar)
- resource_type (varchar)
- resource_id (uuid)
- metadata (jsonb)
- ip_address (inet)
- user_agent (text)
- created_at
Indexes: user_id, action.

### 6.14 call_logs
- id (uuid, pk)
- alert_id (uuid, fk alerts)
- supporter_id (uuid, fk users)
- call_sid (varchar)
- status (varchar)
- created_at
Indexes: alert_id, supporter_id.

### 6.15 daily_stats
- id (uuid, pk)
- date (date, unique)
- active_users, total_checkins (int)
- avg_mental, avg_body, avg_mood (numeric)

### 6.16 data_exports
- id (uuid, pk)
- user_id (uuid, fk users)
- status (varchar) // queued, ready, failed
- format (varchar) // csv, json
- file_url (text)
- created_at, completed_at

### 6.17 sms_credits (optional)
- id (uuid, pk)
- user_id (uuid, fk users)
- balance (int)
- updated_at

## 7. API Surface (v1)
### Conventions
- Base URL: `https://api.howru.app/v1`
- Auth header: `Authorization: Bearer <access_token>`
- JSON request/response, ISO 8601 timestamps in UTC.
- Error format:
```
{
  "success": false,
  "error": "Human readable error message"
}
```
- Pagination: current list endpoints support `?limit=30` only.

### Auth
- POST `/auth/otp/request`
- POST `/auth/otp/verify`
- POST `/auth/refresh`
- POST `/auth/logout`

### Users
- GET `/users/me`
- PATCH `/users/me`
- DELETE `/users/me`
- POST `/users/me/push-token`
- DELETE `/users/me/push-token`

### Schedules
- GET `/users/me/schedule`
- PUT `/users/me/schedule`

### Check-ins
- POST `/checkins`
- GET `/checkins`
- GET `/checkins/today`
- GET `/checkins/stats`

### Uploads
- POST `/uploads/url`
- POST `/uploads/selfie`
- POST `/uploads/selfie/confirm`
- POST `/uploads/avatar`
- POST `/uploads/avatar/confirm`
- DELETE `/uploads/avatar`

### Circles
- GET `/circle`
- GET `/circle/supporting`
- POST `/circle/members`
- PATCH `/circle/members/:memberId`
- DELETE `/circle/members/:memberId`
- POST `/circle/invites`
- POST `/circle/invites/send`
- GET `/circle/invites/:code`
- POST `/circle/invites/:code/accept`
- GET `/circle/invites`

### Pokes
- POST `/pokes`
- GET `/pokes`
- GET `/pokes/unseen/count`
- POST `/pokes/:pokeId/seen`
- POST `/pokes/:pokeId/responded`
- POST `/pokes/seen/all`

### Alerts
- GET `/alerts`
- GET `/alerts/mine`
- POST `/alerts/:alertId/acknowledge`
- POST `/alerts/:alertId/resolve`
- POST `/alerts/trigger`

### Billing
- GET `/billing/entitlements`
- POST `/billing/webhook`

### Exports
- POST `/exports`
- GET `/exports/:id`

### Webhooks
- POST `/webhooks/twilio/sms-status`
- POST `/webhooks/twilio/call-status`

## 8. End-to-End Flows
### 8.1 Sign In with OTP
1. User enters phone -> `/auth/otp/request`.
2. Twilio Verify sends SMS OTP.
3. User submits code -> `/auth/otp/verify`.
4. API returns access/refresh tokens and user profile.
5. iOS stores tokens in Keychain.

### 8.2 Onboarding
1. Update name/email -> PATCH `/users/me`.
2. Set schedule -> PUT `/users/me/schedule`.
3. Create invite -> POST `/circle/invites`.
4. Send invite -> POST `/circle/invites/send`.

### 8.3 Daily Check-in
1. User submits scores -> POST `/checkins`.
2. If selfie: upload -> POST `/uploads/selfie` (or `/uploads/url` + `/uploads/selfie/confirm`).
3. API stores check-in, schedules follower notifications.
4. Supporters receive push updates.

### 8.4 Supporter Monitoring and Poke
1. Supporter loads circle -> GET `/circle/supporting`.
2. Supporter sends poke -> POST `/pokes`.
3. Checker receives push and can respond by checking in.

### 8.5 Missed Check-in Escalation
1. Cron job evaluates missed windows every 15 min.
2. API creates alert and queues escalation timeline.
3. Worker sends push to checker (reminder) then supporters.
4. Escalation triggers SMS and voice when thresholds pass.
5. Supporters acknowledge or resolve -> `POST /alerts/:alertId/acknowledge` or `POST /alerts/:alertId/resolve`.

### 8.6 Subscription Purchase and Entitlements
1. iOS purchase via RevenueCat.
2. RevenueCat webhook -> `/billing/webhook`.
3. API updates subscription and entitlements.
4. iOS reads `/billing/entitlements` and gates features.

### 8.7 Data Export
1. User requests export -> POST `/exports`.
2. Worker generates file, stores in R2, updates record.
3. User receives email or pulls download URL.

### 8.8 Account Deletion
1. User requests deletion -> DELETE `/users/me`.
2. API soft-deletes user and schedules cleanup job.
3. Background job deletes media and hard-deletes data.

## 9. Notifications
### Push (APNs)
- Token registration: `/users/me/push-token`.
- Critical/time-sensitive alerts only for urgent levels.
- Categories for check-in reminder, supporter alerts, and pokes.

### SMS (Twilio)
- OTP via Verify.
- Alerts via Programmable SMS.
- Opt-out handling (STOP) and compliance.

### Voice (Twilio)
- TwiML generated per alert with Polly neural voice.
- Gather 1-digit responses for acknowledge or repeat.

### Email (Resend)
- Welcome, invite, alert, export-ready, deletion confirmation.

## 10. Media Storage
- Selfies uploaded to R2 with server-side encryption.
- CDN URL stored in `checkins.selfie_url`.
- Expired selfies deleted hourly and URL nulled.

## 11. Background Jobs
- `check-missed-checkins` (every 15 min).
- `escalate-alerts` (every 15 min).
- `cleanup-expired-selfies` (hourly).
- `daily-stats` (daily at 00:00 UTC).

## 12. Feature Gating
- Free: limited supporters, push-only, 7-day history.
- Premium: more supporters, SMS/voice alerts, 365-day history, selfies.
- Family: multiple checkers, shared dashboard, same premium features.
Backend enforces limits; iOS mirrors via `/billing/entitlements`.

## 13. Security and Privacy
- TLS for all traffic.
- PII encryption at rest for address and notes.
- Webhook signature verification (Twilio and RevenueCat).
- Audit log for sensitive operations.
- Selfie retention: 24 hours max.

## 14. Observability
- Structured logs (JSON).
- Metrics: request latency, alert delivery rates, OTP success rate.
- Alerts on failed jobs, webhook errors, and queue backlogs.

## 15. Deployment
- Railway services: `api`, `worker`, `cron`.
- DB migrations run on deploy.
- Rollbacks via Railway deploy history.

## 16. Testing
- Unit tests for core services.
- Integration tests for Twilio, RevenueCat (sandbox).
- End-to-end tests for OTP login and check-in flows.

## 17. Open Questions
- Final plan limits for Family vs Premium (supporters and checkers).
- SMS credit add-on vs subscription-only.
- Retention window for poke messages.
- Critical alert entitlement scope and App Store approval.
