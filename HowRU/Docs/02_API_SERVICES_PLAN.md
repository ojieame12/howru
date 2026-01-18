# HowRU API Services Plan

## Overview

RESTful API services powering the HowRU mobile app.

**Related Docs:**
- Authentication: See `01_AUTH_PLAN.md` for detailed auth endpoints
- Infrastructure: See `05_INFRASTRUCTURE_PLAN.md` for deployment

---

## 1. Auth Service (Summary)

Full details in `01_AUTH_PLAN.md`. Key endpoints:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/auth/otp/request` | POST | Request SMS OTP |
| `/auth/otp/verify` | POST | Verify OTP, get tokens |
| `/auth/apple` | POST | Sign in with Apple |
| `/auth/refresh` | POST | Refresh access token |
| `/auth/logout` | POST | Invalidate refresh token |
| `/users/me` | DELETE | Delete account (GDPR) |

### Apple Sign-In

```
POST /auth/apple

Request:
{
  "identityToken": "eyJ...",
  "fullName": {
    "givenName": "Betty",
    "familyName": "Smith"
  },
  "email": "betty@privaterelay.appleid.com"
}

Response (200):
{
  "accessToken": "eyJ...",
  "refreshToken": "rt_...",
  "expiresIn": 3600,
  "user": {
    "id": "usr_abc123",
    "phone": null,
    "name": "Betty Smith",
    "email": "betty@privaterelay.appleid.com",
    "isNewUser": true
  }
}
```

---

## 2. Service Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      API Gateway                             │
│                   (Rate Limiting, Auth)                      │
└─────────────────────┬───────────────────────────────────────┘
                      │
    ┌─────────────────┼─────────────────┐
    │                 │                 │
    ▼                 ▼                 ▼
┌────────┐      ┌──────────┐      ┌──────────┐
│  User  │      │ Check-In │      │  Circle  │
│Service │      │ Service  │      │ Service  │
└────────┘      └──────────┘      └──────────┘
    │                 │                 │
    └─────────────────┼─────────────────┘
                      │
              ┌───────┴───────┐
              │   PostgreSQL  │
              └───────────────┘
```

---

## 2. User Service

### Endpoints

#### Get Current User

```
GET /users/me

Headers:
  Authorization: Bearer {token}

Response (200):
{
  "success": true,
  "user": {
    "id": "usr_abc123",
    "name": "Betty Smith",
    "phone": "+15551234567",
    "email": "betty@example.com",
    "profileImageUrl": "https://cdn.howru.app/avatars/abc123.jpg",
    "address": "123 Main St, Springfield, IL",
    "isChecker": true,
    "lastKnownLocation": "123 Main St, Springfield, IL",
    "lastKnownLocationAt": "2024-01-20T09:15:00Z",
    "createdAt": "2024-01-15T10:00:00Z"
  },
  "schedule": {
    "id": "sch_abc123",
    "windowStartHour": 8,
    "windowStartMinute": 0,
    "windowEndHour": 10,
    "windowEndMinute": 0,
    "timezone": "America/Chicago",
    "activeDays": [0, 1, 2, 3, 4, 5, 6],
    "gracePeriodMinutes": 30,
    "reminderEnabled": true,
    "reminderMinutesBefore": 30
  },
  "subscription": {
    "plan": "free",
    "status": "active",
    "expiresAt": null
  }
}
```

#### Update User Profile

```
PATCH /users/me

Headers:
  Authorization: Bearer {token}

Request:
{
  "name": "Betty Johnson",
  "email": "betty.johnson@example.com",
  "address": "456 Oak Ave, Springfield, IL"
}

Response (200):
{
  "success": true,
  "user": {
    "id": "usr_abc123",
    "name": "Betty Johnson",
    "email": "betty.johnson@example.com",
    "profileImageUrl": "https://cdn.howru.app/avatars/abc123.jpg",
    "address": "456 Oak Ave, Springfield, IL"
  }
}
```

#### Upload Avatar

```
POST /uploads/avatar

Headers:
  Authorization: Bearer {token}

Request:
{
  "imageData": "<base64>",
  "contentType": "image/jpeg"
}

Response (200):
{
  "success": true,
  "url": "https://cdn.howru.app/avatars/abc123.jpg"
}
```

#### Register Push Token

```
POST /users/me/push-token

Request:
{
  "token": "abc123...",
  "platform": "ios",
  "deviceId": "device_xyz"
}

Response (200):
{
  "success": true
}
```

#### Remove Push Token

```
DELETE /users/me/push-token

Request:
{
  "token": "abc123..."
}

Response (200):
{
  "success": true
}
```

#### Delete Account

```
DELETE /users/me

Response (200):
{
  "success": true,
  "message": "Account scheduled for deletion. All sessions have been logged out."
}
```

---

## 3. Check-In Service

### Endpoints

#### Create Check-In

```
POST /checkins

Headers:
  Authorization: Bearer {token}

Request:
{
  "mentalScore": 4,
  "bodyScore": 3,
  "moodScore": 5,
  "latitude": -33.9249,              // optional
  "longitude": 18.4241,              // optional
  "locationName": "Near Cape Town",  // optional, city-level for privacy
  "address": "123 Main St, Cape Town", // optional, full address for alerts
  "isManual": true                   // true = user initiated, false = poke response
}

Response (201):
{
  "id": "chk_xyz789",
  "userId": "usr_abc123",
  "timestamp": "2024-01-20T09:15:00Z",
  "mentalScore": 4,
  "bodyScore": 3,
  "moodScore": 5,
  "averageScore": 4.0,
  "latitude": -33.9249,
  "longitude": 18.4241,
  "locationName": "Near Cape Town",
  "address": "123 Main St, Cape Town",
  "isManual": true
}
```

#### Get Today's Check-In

```
GET /checkins/today

Headers:
  Authorization: Bearer {token}

Response (200):
{
  "success": true,
  "hasCheckedInToday": true,
  "checkIn": {
    "id": "chk_xyz789",
    "timestamp": "2024-01-20T09:15:00Z",
    "mentalScore": 4,
    "bodyScore": 3,
    "moodScore": 5,
    "averageScore": 4.0,
    "latitude": -33.9249,
    "longitude": 18.4241,
    "locationName": "Near Cape Town",
    "hasSelfie": false
  }
}

Response (200 - no check-in):
{
  "success": true,
  "hasCheckedInToday": false,
  "checkIn": null
}
```

#### List Check-Ins

```
GET /checkins?limit=30

Headers:
  Authorization: Bearer {token}

Query Params:
  limit: number (default 30, max 100)

Response (200):
{
  "success": true,
  "checkIns": [
    {
      "id": "chk_xyz789",
      "timestamp": "2024-01-20T09:15:00Z",
      "mentalScore": 4,
      "bodyScore": 3,
      "moodScore": 5,
      "averageScore": 4.0,
      "locationName": "Home",
      "isManual": true
    }
  ]
}
```

#### Get Check-In Stats

```
GET /checkins/stats?days=30

Query Params:
  days: number (default 30, max 365)

Response (200):
{
  "success": true,
  "stats": {
    "totalCheckIns": 28,
    "averageMental": 3.8,
    "averageBody": 3.5,
    "averageMood": 4.1,
    "averageOverall": 3.8,
    "currentStreak": 12
  }
}
```

---

## 4. Schedule Service

### Endpoints

#### Get Schedule

```
GET /users/me/schedule

Response (200):
{
  "success": true,
  "schedule": {
    "id": "sch_abc123",
    "windowStartHour": 8,
    "windowStartMinute": 0,
    "windowEndHour": 10,
    "windowEndMinute": 0,
    "gracePeriodMinutes": 30,
    "activeDays": [0, 1, 2, 3, 4, 5, 6],
    "timezone": "America/Chicago",
    "reminderEnabled": true,
    "reminderMinutesBefore": 30,
    "isActive": true
  }
}
```

#### Create/Update Schedule

```
PUT /users/me/schedule

Request:
{
  "windowStartHour": 9,
  "windowStartMinute": 0,
  "windowEndHour": 11,
  "windowEndMinute": 0,
  "gracePeriodMinutes": 30,
  "activeDays": [1, 2, 3, 4, 5],
  "timezone": "America/Chicago",
  "reminderEnabled": true,
  "reminderMinutesBefore": 15
}

Response (200):
{
  "success": true,
  "schedule": {
    "id": "sch_abc123",
    "windowStartHour": 9,
    "windowStartMinute": 0,
    "windowEndHour": 11,
    "windowEndMinute": 0,
    "gracePeriodMinutes": 30,
    "activeDays": [1, 2, 3, 4, 5],
    "timezone": "America/Chicago",
    "reminderEnabled": true,
    "reminderMinutesBefore": 15
  }
}
```

---

## 5. Circle Service

### Endpoints

#### List My Supporters (Circle)

```
GET /circle

Response (200):
{
  "success": true,
  "circle": [
    {
      "id": "link_abc123",
      "supporterId": "usr_def456",
      "name": "Sarah",
      "phone": "+15559876543",
      "email": "sarah@example.com",
      "isAppUser": true,
      "permissions": {
        "canSeeMood": true,
        "canSeeLocation": false,
        "canSeeSelfie": true,
        "canPoke": true
      },
      "alertPriority": 1,
      "alertPreferences": {
        "push": true,
        "sms": false,
        "email": false
      },
      "invitedAt": "2024-01-10T12:00:00Z",
      "acceptedAt": "2024-01-10T12:05:00Z"
    }
  ]
}
```

#### List People I'm Supporting

```
GET /circle/supporting

Response (200):
{
  "success": true,
  "supporting": [
    {
      "id": "link_xyz789",
      "checkerId": "usr_ghi789",
      "name": "Grandma Betty",
      "phone": "+15551234567",
      "lastKnownLocation": "123 Main St, Springfield, IL",
      "lastLocationAt": "2024-01-20T09:15:00Z",
      "permissions": {
        "canSeeMood": true,
        "canSeeLocation": false,
        "canSeeSelfie": true,
        "canPoke": true
      }
    }
  ]
}
```

#### Add Circle Member (Direct)

```
POST /circle/members

Request:
{
  "name": "Sarah",
  "phone": "+15559876543",
  "email": "sarah@example.com",
  "canSeeMood": true,
  "canSeeLocation": false,
  "canSeeSelfie": false,
  "canPoke": true,
  "alertPriority": 1,
  "alertViaSms": false,
  "alertViaEmail": false
}

Response (201):
{
  "success": true,
  "member": {
    "id": "link_abc123",
    "name": "Sarah",
    "phone": "+15559876543",
    "email": "sarah@example.com",
    "isAppUser": true
  }
}
```

#### Create Invite

```
POST /circle/invites

Request:
{
  "role": "supporter",
  "canSeeMood": true,
  "canSeeLocation": false,
  "canSeeSelfie": false,
  "canPoke": true,
  "expiresInHours": 48
}

Response (201):
{
  "success": true,
  "invite": {
    "id": "inv_abc123",
    "code": "HOWRU-1234",
    "role": "supporter",
    "expiresAt": "2024-01-21T12:00:00Z",
    "link": "https://howru.app/invite?code=HOWRU-1234"
  }
}
```

#### Send Invite via SMS/Email

```
POST /circle/invites/send

Request:
{
  "email": "sarah@example.com",
  "role": "supporter",
  "canSeeMood": true,
  "canSeeLocation": false,
  "canSeeSelfie": false,
  "canPoke": true
}

Response (200):
{
  "success": true,
  "invite": {
    "id": "inv_abc123",
    "code": "HOWRU-1234",
    "sentTo": "sarah@example.com"
  }
}
```

#### Get Invite Details

```
GET /circle/invites/:code

Response (200):
{
  "success": true,
  "invite": {
    "inviterName": "Betty",
    "role": "supporter",
    "expiresAt": "2024-01-21T12:00:00Z",
    "permissions": {
      "canSeeMood": true,
      "canSeeLocation": false,
      "canSeeSelfie": false,
      "canPoke": true
    }
  }
}
```

#### Accept Invite

```
POST /circle/invites/:code/accept

Headers:
  Authorization: Bearer {token}

Response (200):
{
  "success": true,
  "message": "Invite accepted",
  "role": "supporter",
  "inviterName": "Betty"
}
```

#### Update Circle Member

```
PATCH /circle/members/:memberId

Request:
{
  "name": "Sarah (Daughter)",
  "canSeeMood": true,
  "canSeeLocation": false,
  "canSeeSelfie": true,
  "canPoke": true,
  "alertPriority": 2,
  "alertViaPush": true,
  "alertViaSms": false,
  "alertViaEmail": false
}

Response (200):
{
  "success": true,
  "member": {
    "id": "link_abc123",
    "name": "Sarah (Daughter)"
  }
}
```

#### Remove Circle Member

```
DELETE /circle/members/:memberId

Response (200):
{
  "success": true
}
```

---

## 6. Poke Service

### Endpoints

#### Send Poke

```
POST /pokes

Request:
{
  "toUserId": "usr_abc123",
  "message": "Hey grandma, just checking in!"
}

Response (201):
{
  "success": true,
  "poke": {
    "id": "poke_abc123",
    "toUserId": "usr_abc123",
    "message": "Hey grandma, just checking in!",
    "sentAt": "2024-01-20T14:30:00Z"
  }
}
```

#### List Received Pokes

```
GET /pokes?limit=20

Query Params:
  limit: number (default 20, max 50)

Response (200):
{
  "success": true,
  "pokes": [
    {
      "id": "poke_abc123",
      "fromUserId": "usr_def456",
      "fromName": "Sarah",
      "message": "Hey grandma!",
      "sentAt": "2024-01-20T14:30:00Z",
      "seenAt": null,
      "respondedAt": null
    }
  ]
}
```

#### Get Unseen Pokes Count

```
GET /pokes/unseen/count

Response (200):
{
  "success": true,
  "count": 2
}
```

#### Mark Poke as Seen

```
POST /pokes/:pokeId/seen

Response (200):
{
  "success": true
}
```

#### Mark Poke as Responded

```
POST /pokes/:pokeId/responded

Response (200):
{
  "success": true
}
```

#### Mark All Pokes as Seen

```
POST /pokes/seen/all

Response (200):
{
  "success": true
}
```

---

## 7. Alert Service

### Endpoints

#### List Alerts (For Supporters)

```
GET /alerts

Response (200):
{
  "success": true,
  "alerts": [
    {
      "id": "alert_abc123",
      "checkerId": "usr_abc123",
      "checkerName": "Grandma Betty",
      "type": "soft",  // "reminder" | "soft" | "hard" | "escalation"
      "status": "pending",
      "triggeredAt": "2024-01-20T11:30:00Z",
      "missedWindowAt": "2024-01-20T11:00:00Z",
      "lastCheckInAt": "2024-01-19T09:15:00Z",
      "lastKnownLocation": "123 Main St, Springfield, IL",
      "acknowledgedAt": null,
      "acknowledgedBy": null
    }
  ]
}
```

#### List My Alerts (As Checker)

```
GET /alerts/mine

Response (200):
{
  "success": true,
  "alerts": [
    {
      "id": "alert_abc123",
      "type": "reminder",
      "status": "pending",
      "triggeredAt": "2024-01-20T11:30:00Z",
      "missedWindowAt": "2024-01-20T11:00:00Z",
      "lastCheckInAt": "2024-01-19T09:15:00Z",
      "lastKnownLocation": "123 Main St, Springfield, IL",
      "acknowledgedAt": null
    }
  ]
}
```

#### Acknowledge Alert

```
POST /alerts/:alertId/acknowledge

Response (200):
{
  "success": true,
  "alert": {
    "id": "alert_abc123",
    "acknowledgedAt": "2024-01-20T11:45:00Z"
  }
}
```

#### Resolve Alert

```
POST /alerts/:alertId/resolve

Request:
{
  "resolution": "contacted",  // "checked_in" | "contacted" | "safe_confirmed" | "false_alarm" | "other"
  "notes": "Spoke with Betty, she's fine - just forgot to check in"
}

Response (200):
{
  "success": true,
  "alert": {
    "id": "alert_abc123",
    "status": "resolved",
    "resolvedAt": "2024-01-20T12:00:00Z",
    "resolution": "contacted"
  }
}
```

#### Trigger Alert (Internal)

```
POST /alerts/trigger

Request:
{
  "checkerId": "usr_abc123",
  "type": "reminder"
}

Response (200):
{
  "success": true,
  "alert": {
    "id": "alert_abc123",
    "type": "reminder",
    "triggeredAt": "2024-01-20T11:30:00Z"
  }
}
```

---

## 8. Uploads Service

### Endpoints

#### Get Pre-signed Upload URL

```
POST /uploads/url

Request:
{
  "category": "selfie",  // "selfie" | "avatar"
  "contentType": "image/jpeg"
}

Response (200):
{
  "success": true,
  "uploadUrl": "https://...",
  "key": "selfies/...",
  "cdnUrl": "https://cdn.howru.app/selfies/...",
  "expiresIn": 300
}
```

#### Upload Selfie (Direct)

```
POST /uploads/selfie

Request:
{
  "checkinId": "chk_xyz789",
  "imageData": "<base64>",
  "contentType": "image/jpeg"
}

Response (200):
{
  "success": true,
  "url": "https://cdn.howru.app/selfies/xyz789.jpg",
  "expiresAt": "2024-01-21T09:15:00Z"
}
```

#### Confirm Selfie Upload (Pre-signed Flow)

```
POST /uploads/selfie/confirm

Request:
{
  "checkinId": "chk_xyz789",
  "key": "selfies/...",
  "cdnUrl": "https://cdn.howru.app/selfies/xyz789.jpg"
}

Response (200):
{
  "success": true,
  "url": "https://cdn.howru.app/selfies/xyz789.jpg",
  "expiresAt": "2024-01-21T09:15:00Z"
}
```

#### Upload Avatar (Direct)

```
POST /uploads/avatar

Request:
{
  "imageData": "<base64>",
  "contentType": "image/jpeg"
}

Response (200):
{
  "success": true,
  "url": "https://cdn.howru.app/avatars/abc123.jpg"
}
```

#### Confirm Avatar Upload (Pre-signed Flow)

```
POST /uploads/avatar/confirm

Request:
{
  "key": "avatars/...",
  "cdnUrl": "https://cdn.howru.app/avatars/abc123.jpg"
}

Response (200):
{
  "success": true,
  "url": "https://cdn.howru.app/avatars/abc123.jpg"
}
```

#### Delete Avatar

```
DELETE /uploads/avatar

Response (200):
{
  "success": true
}
```

---

## 9. Error Response Format

Most errors follow this format:

```json
{
  "success": false,
  "error": "Human readable error message"
}
```

---

## 10. Pagination

Current list endpoints use a simple `limit` parameter only:

```
GET /resource?limit=30
```

---

## 11. Implementation Order

### Phase 1: Core - COMPLETE
- [x] User CRUD
- [x] Check-In CRUD
- [x] Schedule CRUD

### Phase 2: Social - COMPLETE
- [x] Circle links
- [x] Invites
- [x] Pokes

### Phase 3: Alerts - COMPLETE
- [x] Alert creation
- [x] Alert management
- [x] Notification registration

### Phase 4: Billing - COMPLETE
- [x] Subscription routes (GET /subscriptions/me, /offerings, /check-feature/:feature)
- [x] Subscription middleware (requireSubscription, requireFeature)
- [x] RevenueCat webhook signature verification (HMAC-SHA256)

### Phase 5: iOS Integration - TODO
- [ ] Wire iOS API client to backend endpoints
- [ ] Implement data sync service
- [ ] End-to-end auth flow testing

---

## Next Document

See `03_PAYMENTS_PLAN.md` for subscription and billing details.
