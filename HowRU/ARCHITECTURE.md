# HowRU - Complete System Architecture

## Overview

HowRU is a daily wellness check-in app designed to help loved ones stay connected and ensure the safety of people who live alone or may be isolated. The app serves two distinct user types with different but interconnected experiences.

---

## User Types

### 1. Checker (Primary User)
The person who checks in daily. Typically:
- Elderly individuals living alone
- People with chronic health conditions
- Solo travelers or expats
- Anyone who wants peace of mind for their loved ones

### 2. Supporter (Circle Member)
The person who monitors checkers. Typically:
- Adult children of elderly parents
- Close friends or family members
- Caregivers (professional or informal)

**Key Insight**: A person can be BOTH a checker AND a supporter simultaneously.

---

## Core Data Models

> **Note**: These models reflect the actual SwiftData implementations in `Sources/Models/`.

```
User (Sources/Models/User.swift)
├── id: UUID
├── phoneNumber: String?
├── email: String?
├── name: String
├── isChecker: Bool (true = checks in, false = supporter only)
├── createdAt: Date
├── lastActiveAt: Date
├── profileImageData: Data?
├── address: String?
│
│  // Cached location (from most recent check-in, for quick alert lookup)
├── lastKnownLatitude: Double?
├── lastKnownLongitude: Double?
├── lastKnownAddress: String?
├── lastKnownLocationAt: Date?
│
├── checkIns: [CheckIn] (inverse: CheckIn.user)
├── supportersLinks: [CircleLink] (people watching this user, inverse: CircleLink.checker)
├── watchingLinks: [CircleLink] (people this user watches, inverse: CircleLink.supporter)
└── schedules: [Schedule] (inverse: Schedule.user)

CheckIn (Sources/Models/CheckIn.swift)
├── id: UUID
├── user: User?
├── timestamp: Date
├── mentalScore: Int (1-5, default: 3)
├── bodyScore: Int (1-5, default: 3)
├── moodScore: Int (1-5, default: 3)
├── selfieData: Data? (@externalStorage, ephemeral)
├── selfieExpiresAt: Date?
├── latitude: Double?
├── longitude: Double?
├── locationName: String? ("Near Cape Town" - city level)
└── isManualCheckIn: Bool (true = user initiated, false = poke response)
│
├── computed: hasLocation, hasSelfie, averageScore

CircleLink (Sources/Models/CircleLink.swift)
├── id: UUID
├── checker: User? (the person being monitored)
├── supporter: User? (the person monitoring)
│
│  // Supporter contact info (for non-app users)
├── supporterPhone: String?
├── supporterEmail: String?
├── supporterName: String
│
│  // Granular permissions
├── canSeeMood: Bool (default: true)
├── canSeeLocation: Bool (default: false)
├── canSeeSelfie: Bool (default: true)
├── canPoke: Bool (default: true)
│
│  // Alert delivery preferences
├── alertViaPush: Bool (default: true)
├── alertViaSMS: Bool (default: false)
├── alertViaEmail: Bool (default: false)
│
│  // Status
├── isActive: Bool
├── invitedAt: Date
└── acceptedAt: Date?
│
├── computed: isPending, hasAppUser

Schedule (Sources/Models/Schedule.swift)
├── id: UUID
├── user: User?
│
│  // Check-in window (not a single time)
├── windowStartHour: Int (0-23, default: 7)
├── windowStartMinute: Int (0-59, default: 0)
├── windowEndHour: Int (default: 10)
├── windowEndMinute: Int (default: 0)
├── timezoneIdentifier: String
├── activeDays: [Int] (0=Sun...6=Sat, default: all)
│
│  // Grace period before alerts
├── gracePeriodMinutes: Int (default: 30)
│
│  // Reminder settings
├── reminderEnabled: Bool (default: true)
├── reminderMinutesBefore: Int (minutes before window ends, default: 30)
│
├── isActive: Bool
└── createdAt: Date
│
├── computed: timezone, windowStartTime, windowEndTime, isWithinWindow()

AlertEvent (Sources/Models/AlertEvent.swift)
├── id: UUID
├── checkerId: UUID
├── checkerName: String
├── level: AlertLevel (enum)
├── status: AlertStatus (enum)
├── triggeredAt: Date
├── resolvedAt: Date?
├── lastCheckInAt: Date? (context when alert triggered)
├── lastKnownLocation: String?
└── notifiedSupporterIds: [UUID]
│
├── computed: isActive, timeSinceLastCheckIn

Poke (Sources/Models/Poke.swift)
├── id: UUID
├── fromSupporterId: UUID
├── fromName: String
├── toCheckerId: UUID
├── sentAt: Date
├── seenAt: Date?
├── respondedAt: Date? (when they checked in after poke)
└── message: String?
│
├── computed: isPending, wasAcknowledged

// Enums (in AlertEvent.swift)
AlertLevel: reminder | softAlert | hardAlert | escalation
AlertStatus: pending | sent | acknowledged | resolved | cancelled
```

### Model Design Decisions

| Item | Decision | Rationale |
|------|----------|-----------|
| **Poke emoji** | Not implemented | Keep simple - message is optional, emoji adds complexity |
| **CheckIn note** | Not implemented | Private notes add scope - can add later if needed |
| **Alert priority** | Not in CircleLink | Alert order determined by supporter list order or separate policy |
| **Invite system** | Via CircleLink | `acceptedAt: nil` = pending invite, no separate Invite model |
| **Non-app supporters** | Supported | `supporterPhone`/`supporterEmail` allow SMS/email alerts without app |

---

## App Flows

### Flow A: Checker Experience

#### A1. Onboarding (New Checker)
```
[Welcome Screen]
    ↓
[Phone/Email Entry] → OTP Verification
    ↓
[Name & Avatar Setup]
    ↓
[Set Check-in Time] → "When should we remind you?"
    ↓
[Invite Supporters] → "Who should know if you miss a day?"
    │
    ├── Share invite link (SMS/Email/Copy)
    ├── Search by phone number
    └── Skip for now
    ↓
[Success Screen] → "You're all set!"
    ↓
[Main App → Check-in Tab]
```

#### A2. Daily Check-in Flow

**Design Goal:** 10-15 seconds. Pleasant moment of self-reflection, not a chore.

```
[Check-in Tab - Not yet checked in today]
    │
    ├── Greeting based on time (morning/afternoon/evening)
    ├── Streak count (only if > 1 day)
    └── "Check In" button (coral, prominent)
    ↓
[Check-in Screen - All-in-one]
    │
    │  ┌─────────────────────────────────┐
    │  │                                 │
    │  │  How are you today?             │
    │  │                                 │
    │  │  🧠 Mind                        │
    │  │  😵‍💫 ○───────────○ 😌            │
    │  │                                 │
    │  │  💪 Body                        │
    │  │  🥱 ○───────────○ ⚡            │
    │  │                                 │
    │  │  💛 Mood                        │
    │  │  😔 ○───────────○ 😊            │
    │  │                                 │
    │  │       [Done]                    │
    │  │                                 │
    │  └─────────────────────────────────┘
    │
    ├── Sliders: Neutral colors (no red/green judgment)
    ├── Haptic: Selection tick on each value (1-5)
    └── Emoji endpoints: subtle pulse when reached
    ↓
[Submit - Haptic success]
    ↓
[Check-in Complete]
    │
    │  ┌─────────────────────────────────┐
    │  │                                 │
    │  │         ✓ All done              │
    │  │                                 │
    │  │    🧠 4    💪 3    💛 5         │
    │  │                                 │
    │  │    [📷 Add a snapshot?]         │  ← subtle, optional
    │  │                                 │
    │  │         [Finish]                │
    │  │                                 │
    │  └─────────────────────────────────┘
    ↓
[Check-in Tab - Already checked in]
    │
    ├── "Checked in ✓" with time
    ├── Today's scores (tap to edit until midnight)
    └── Mini 7-day trend sparkline
```

#### A2.1. Snapshot Feature (Optional Ephemeral Selfie)

**Philosophy:** Quick glimpse for supporters - proof of life with human touch. Not about looking good.

**Key Principles:**
- Ephemeral: Auto-deletes after 24 hours
- No filters: Raw, authentic
- Low pressure: One retake allowed, easy to skip
- Private: Only visible to circle members

```
[Tap "Add a snapshot?"]
    ↓
[Camera Screen]
    │
    │  ┌─────────────────────────────────┐
    │  │                                 │
    │  │   ┌───────────────────────┐     │
    │  │   │                       │     │
    │  │   │    [Camera Preview]   │     │
    │  │   │                       │     │
    │  │   └───────────────────────┘     │
    │  │                                 │
    │  │   "Quick snap for your circle"  │
    │  │                                 │
    │  │      [📸 Capture]               │
    │  │      [Skip]                     │
    │  │                                 │
    │  └─────────────────────────────────┘
    ↓
[Preview Screen]
    │
    │  ┌─────────────────────────────────┐
    │  │                                 │
    │  │   [Photo Preview]               │
    │  │                                 │
    │  │   ⏱ Visible for 24 hours        │
    │  │   👁 Only your circle can see   │
    │  │                                 │
    │  │   [Send]  [Retake]  [Skip]      │
    │  │                                 │
    │  └─────────────────────────────────┘
```

**Supporter sees snapshot:**
```
┌─────────────────────────────────┐
│  Mom                       🟢   │
│  Checked in 2h ago              │
│                                 │
│  ┌─────────────┐                │
│  │ [Thumbnail] │  ← Tap to view │
│  └─────────────┘                │
│  ⏱ Expires in 18h               │
│                                 │
│  🧠 4    💪 3    💛 5           │
└─────────────────────────────────┘
```

#### A3. Receiving a Poke
```
[Push Notification]
    "👋 [Name] is thinking of you"
    ↓
[Open App → Poke received modal]
    │
    ├── Shows: Supporter's avatar and name
    ├── Shows: Optional message
    ├── Shows: Emoji they sent
    │
    ├── Button: "Send Thanks" → Quick response
    ├── Button: "Check In Now" → Goes to check-in
    └── Button: "Dismiss"
```

#### A4. SOS / Emergency
```
[Settings → Safety]
    │
    └── "Emergency Alert" button
    ↓
[Confirmation Dialog]
    "This will immediately alert all your supporters.
     Are you sure?"
    │
    ├── [Cancel]
    └── [Send Alert] → Triggers immediate escalation
```

---

### Flow B: Supporter Experience

#### B1. Onboarding (New Supporter via Invite)
```
[Invite Link Clicked]
    │
    ├── If app installed → Deep link to accept flow
    └── If not installed → App Store → then accept flow
    ↓
[Accept Invitation Screen]
    │
    ├── Shows: "[Checker Name] wants you in their circle"
    ├── Shows: Checker's avatar
    ├── Shows: What this means (brief explanation)
    │
    ├── Button: "Accept" → Phone/OTP verification (if new user)
    └── Button: "Decline"
    ↓
[Supporter Setup]
    │
    ├── Name & Avatar (if new user)
    ├── Notification preferences
    └── Alert timing preferences
    ↓
[Success Screen]
    "You're now watching over [Checker Name]"
    ↓
[Main App → Circle Tab]
```

#### B2. Supporter Dashboard (Circle Tab)
```
[Circle Tab]
    │
    ├── Header: "Your Circle"
    │
    ├── Section: "People You Support" (if any)
    │   │
    │   └── [Checker Card]
    │       ├── Avatar + Name
    │       ├── Status indicator:
    │       │   ├── 🟢 "Checked in 2h ago"
    │       │   ├── 🟡 "Hasn't checked in today"
    │       │   └── 🔴 "Missed check-in (24h+)"
    │       ├── Mini mood indicators (3 dots: mental/body/mood)
    │       ├── Selfie thumbnail (if shared, ephemeral)
    │       └── [Poke] button
    │
    ├── Section: "Your Supporters" (people watching you)
    │   │
    │   └── [Supporter Card]
    │       ├── Avatar + Name
    │       ├── Role badge ("Family", "Friend")
    │       └── Status: Active ✓
    │
    └── [+] Add to Circle button
```

#### B3. Viewing a Checker's Details
```
[Tap Checker Card]
    ↓
[Checker Detail View]
    │
    ├── Header: Avatar + Name + Last seen
    │
    ├── Today's Check-in (if exists)
    │   ├── Scores: Mental 4/5, Body 3/5, Mood 5/5
    │   ├── Selfie (if shared)
    │   └── Time: "Checked in at 9:32 AM"
    │
    ├── Trends (if canSeeTrends permission)
    │   ├── 7-day mini chart
    │   └── "View Full Trends" button
    │
    ├── Actions
    │   ├── [Send Poke] button
    │   ├── [Call] button (opens phone)
    │   └── [Message] button (opens SMS)
    │
    └── Settings
        ├── Alert preferences for this person
        ├── Relationship label
        └── Remove from circle
```

#### B4. Sending a Poke
```
[Tap Poke Button]
    ↓
[Poke Composer Modal]
    │
    ├── Emoji picker (default: 👋)
    │   Quick options: 👋 ❤️ ☀️ 🤗 💪
    │
    ├── Optional message (40 char max)
    │   Placeholder: "Add a quick note..."
    │
    └── [Send Poke] button
    ↓
[Poke Sent Confirmation]
    │
    └── "[Name] will be notified"
```

#### B5. Receiving an Alert
```
[Push Notification - Escalation Level 1]
    "⚠️ [Checker Name] hasn't checked in for 24 hours"
    ↓
[Open App → Alert Screen]
    │
    ├── Alert banner (yellow/orange)
    ├── Shows: Last check-in time
    ├── Shows: Last known mood scores
    │
    ├── Actions:
    │   ├── [I've contacted them] → Resolves alert
    │   ├── [Send Poke] → Gentle nudge
    │   ├── [Call Now] → Opens phone
    │   └── [Escalate] → Notify next contact
    │
    └── Alert history for this person
```

---

## Views Architecture

### Tab Bar Structure
```
[Check In]     [Circle]     [Trends]     [Settings]
    │              │            │             │
    └──────────────┴────────────┴─────────────┘
                        │
                   MainTabView
```

### View Hierarchy

```
ContentView
├── OnboardingView (if no user)
│   ├── WelcomeScreen
│   ├── UserInfoScreen
│   ├── OTPVerificationScreen
│   ├── ScheduleSetupScreen
│   ├── InviteSupportersScreen
│   └── SuccessScreen
│
└── MainTabView (if user exists)
    │
    ├── CheckInView
    │   ├── CheckInPromptView (not yet checked in)
    │   ├── CheckInFormView (actively checking in)
    │   │   ├── MoodSlider (×3)
    │   │   ├── SelfieCapture
    │   │   └── SubmitButton
    │   └── CheckInCompleteView (already checked in)
    │
    ├── CircleView
    │   ├── SupportersSection
    │   │   └── SupporterCard
    │   ├── CheckersSection
    │   │   └── CheckerCard
    │   ├── PendingInvitesSection
    │   │   └── InviteCard
    │   ├── AddSupporterSheet (basic add-by-contact flow)
    │   ├── CheckerDetailView
    │   │   ├── TodayCheckInCard
    │   │   ├── MiniTrendsChart
    │   │   └── ActionButtons
    │   └── PokeComposerSheet
    │
    ├── TrendsView
    │   ├── TimeRangePicker (7d/30d/All)
    │   ├── SummaryCardsRow
    │   │   ├── CheckInsCard
    │   │   ├── AvgMoodCard
    │   │   └── StreakCard
    │   ├── MoodLineChart
    │   ├── ChartLegend
    │   └── RecentCheckInsList
    │       └── CheckInHistoryRow
    │
    └── SettingsView
        ├── ProfileSection
        │   ├── AvatarEditor
        │   └── NameEditor
        ├── NotificationsSection
        │   ├── ReminderTimeEditor
        │   └── AlertPreferences
        ├── CircleSection
        │   └── ManageCircleLink
        ├── PremiumSection
        │   └── PremiumView
        ├── SupportSection
        │   ├── HelpCenter
        │   ├── ContactSupport
        │   └── PrivacyPolicy
        └── AccountSection
            ├── ExportData
            └── DeleteAccount
```

---

## Alert Escalation System

### User-Defined Check-in Window
Users set their preferred check-in window via the `Schedule` model. The app is **not an alarm clock** - it's a gentle system that respects user autonomy.

### Schedule Configuration (from Schedule.swift)
```
Schedule
├── Window: windowStartHour:windowStartMinute to windowEndHour:windowEndMinute
│   Example: 7:00 AM to 10:00 AM
│
├── Active days: activeDays (0=Sun...6=Sat)
│   Example: [1,2,3,4,5] = weekdays only
│
├── Timezone: timezoneIdentifier
│   Example: "America/Los_Angeles"
│
├── Grace period: gracePeriodMinutes (default: 30)
│   Time after window closes before first alert
│
└── Reminder: reminderEnabled, reminderMinutesBefore
    Example: Remind 30 minutes before window ends
```

### Timing Flow
```
User's check-in window: 7:00 AM to 10:00 AM (example)

Within window:
├── User can check in anytime
├── Optional reminder at 9:30 AM (30 min before end, if enabled)
└── No pressure, no nagging

After window + grace period (missed):
├── T+0:    Window ends (10:00 AM) + grace period (30 min) = 10:30 AM
├── T+0:    AlertLevel.reminder → "Haven't heard from you today"
├── T+24h:  AlertLevel.softAlert → Notify first supporter
├── T+36h:  AlertLevel.hardAlert → Notify additional supporters
└── T+48h:  AlertLevel.escalation → Emergency contacts
```

### Alert Levels (from AlertEvent.swift)
```swift
enum AlertLevel {
    case reminder      // "Time to check in" - checker only
    case softAlert     // "Haven't heard from you" - first supporter
    case hardAlert     // "Missed check-in" - more supporters
    case escalation    // "No response - emergency" - all contacts
}
```

### Alert Status (from AlertEvent.swift)
```swift
enum AlertStatus {
    case pending       // Alert created, not yet sent
    case sent          // Notifications delivered
    case acknowledged  // Supporter saw the alert
    case resolved      // User checked in or contact made
    case cancelled     // Manually dismissed
}
```

### Key Principle
The app should feel like a **caring friend**, not a nagging parent.
- Minimal notifications
- User controls window, reminder, and grace period
- Supporters only alerted after window + grace period passes

---

## Notification Types

### For Checkers
```
1. Optional Reminder (if user enabled)
   "Ready when you are"
   [Check In]

2. Poke Received
   "👋 [Name] is thinking of you"
   [View]

3. New Supporter
   "[Name] joined your circle"
   [View Circle]
```

### For Supporters
```
1. Checker Completed Check-in
   "✓ [Name] checked in"
   (Silent notification, badge only)

2. Alert Level 1
   "⚠️ [Name] hasn't checked in for 24 hours"
   [View] [Call]

3. Alert Level 2
   "🚨 [Name] still hasn't checked in (36h)"
   [View] [Call]

4. Alert Resolved
   "✓ [Name] has checked in"
   [View]

5. Poke Response
   "[Name] sent thanks for your poke"
   [View]

6. SOS Alert
   "🆘 [Name] triggered an emergency alert!"
   [Call Now]
```

---

## Backend API Endpoints (Future)

```
Auth
├── POST   /auth/otp/request     → Send OTP to phone/email
├── POST   /auth/otp/verify      → Verify OTP, return token
└── POST   /auth/refresh         → Refresh auth token

Users
├── GET    /users/me             → Get current user profile
├── PATCH  /users/me             → Update profile
├── DELETE /users/me             → Delete account
└── GET    /users/:id            → Get public profile

Check-ins
├── POST   /checkins             → Create check-in
├── GET    /checkins             → Get user's check-ins (paginated)
├── GET    /checkins/today       → Get today's check-in
├── PATCH  /checkins/:id         → Update check-in (same day only)
└── GET    /checkins/stats       → Get aggregated stats

Circle
├── GET    /circle               → Get all circle links
├── POST   /circle/invite        → Create invite link
├── POST   /circle/accept/:code  → Accept invitation
├── DELETE /circle/:id           → Remove circle link
└── PATCH  /circle/:id           → Update link settings

Pokes
├── POST   /pokes                → Send poke
├── GET    /pokes                → Get received pokes
├── PATCH  /pokes/:id/read       → Mark as read
└── POST   /pokes/:id/respond    → Send response

Alerts
├── GET    /alerts               → Get active alerts
├── POST   /alerts/:id/resolve   → Resolve alert
├── POST   /alerts/sos           → Trigger manual SOS
└── GET    /alerts/history       → Alert history

Settings
├── GET    /settings             → Get notification settings
├── PATCH  /settings             → Update settings
└── GET    /settings/schedules   → Get reminder schedules
```

---

## Premium Features (HowRU Plus)

### Free Tier
- ✓ Daily check-ins
- ✓ 1 supporter
- ✓ Basic push notifications
- ✓ 7-day trends
- ✓ Receive unlimited pokes

### Plus Tier ($1.99/month)
- ✓ Everything in Free
- ✓ Unlimited supporters
- ✓ SMS alert fallback (if push fails)
- ✓ 90-day trends history
- ✓ Export check-in data
- ✓ Custom reminder messages
- ✓ Widget support
- ✓ Priority support

### Family Plan ($4.99/month)
- ✓ Everything in Plus
- ✓ Up to 5 family members as checkers
- ✓ Shared family dashboard
- ✓ Annual health report PDF

---

## Privacy & Data Handling

### Ephemeral Data
- Selfies: Auto-deleted after 24 hours
- Poke messages: Auto-deleted after 7 days
- Location data: Never stored on server (local only)

### User Data Rights
- Export: Users can export all their data (JSON/CSV)
- Delete: Full account deletion within 30 days
- Portability: Check-in history downloadable

### Encryption
- At rest: All sensitive data encrypted (AES-256)
- In transit: TLS 1.3 required
- Selfies: End-to-end encrypted (only checker + supporters can view)

---

## Technical Stack

### iOS App
- SwiftUI + SwiftData (local persistence)
- CloudKit (sync, if signed into iCloud)
- UserNotifications (local + push)
- HealthKit integration (optional, future)
- WidgetKit (iOS 17+)

### Backend (Planned)
- **Railway** - API server, workers, cron jobs
- **Neon PostgreSQL** - serverless database
- **Upstash Redis** - sessions, rate limiting, queues
- **Twilio** - SMS OTP, voice alerts
- **Resend** - transactional email (+ SMS fallback)
- **APNs** - push notifications
- **RevenueCat** - subscription management

### Infrastructure (Planned)
- Railway (backend services + cron)
- Cloudflare R2 (selfie storage, encrypted)
- Upstash (rate limiting, queues)

See detailed plans:
- `Docs/END_TO_END_SPEC.md` - **Comprehensive end-to-end specification**
- `Docs/01_AUTH_PLAN.md` - Phone OTP authentication
- `Docs/02_API_SERVICES_PLAN.md` - REST API endpoints
- `Docs/03_PAYMENTS_PLAN.md` - RevenueCat + StoreKit 2
- `Docs/04_EMERGENCY_SERVICES_PLAN.md` - Alert escalation, Twilio Voice
- `Docs/05_INFRASTRUCTURE_PLAN.md` - Railway, Neon, deployment

---

## Implementation Status

### iOS App - COMPLETE (Local)
1. ✓ Onboarding flow (6 screens)
2. ✓ Check-in flow (state machine, custom slider, haptics)
3. ✓ Local data persistence (SwiftData)
4. ✓ Circle management (CircleView, AddSupporterSheet, CheckerDetailView)
5. ✓ Schedule-aware status detection
6. ✓ Notification preferences (persisted to CircleLink; urgent vs all mapped to push only)
7. ✓ Trends view with charts
8. ✓ Settings (profile, notifications, premium)
9. ✓ Poke feature
10. ✓ Alert system (AlertService, AlertReceivedView)
11. ✓ Selfie capture (AVFoundation, 24h expiry)
12. ✓ Data export (JSON/CSV)

### iOS App - Networking (SCAFFOLDED)
1. ✓ API Client (URLSession wrapper with auth refresh)
2. ✓ Auth Manager (JWT Keychain storage, token refresh)
3. ✓ API Models (DTOs aligned with backend responses)
4. ✓ Environment Config (dev/staging/prod URLs)
5. ✓ Deep link handling (InviteManager, InviteAcceptSheet, URL scheme)

### iOS App - TODO (Integration)
1. ◯ Wire onboarding to OTP auth endpoints
2. ◯ Wire check-in flow to sync with backend
3. ◯ Wire circle management to backend
4. ◯ Wire pokes/alerts to backend
5. ◯ Add data sync service (local ↔ server)

### Backend - COMPLETE
1. ✓ Railway project setup
2. ✓ Neon database + migrations
3. ✓ Auth service (Phone OTP via Twilio Verify)
4. ✓ Core API endpoints (users, checkins, circle, pokes, alerts, uploads, exports)
5. ✓ Push notification service (APNs)
6. ✓ Alert escalation cron jobs
7. ✓ SMS/Voice alerts (Twilio)
8. ✓ Email fallback (Resend)
9. ✓ RevenueCat webhook (with signature verification)
10. ✓ Subscription routes (GET /subscriptions/me, /offerings)
11. ✓ Subscription middleware (feature gates - defined, not applied)
12. ✓ Public invite preview endpoint (for deep links)

### Backend - TODO
1. ◯ Apply subscription middleware to premium routes
2. ◯ Rate limiting on auth endpoints
3. ◯ Request validation middleware

### Polish - TODO
1. ◯ iOS Widgets
2. ◯ App Store submission

---

## Design Tokens Reference

See `Theme.swift` for complete design system:
- Colors: `HowRUColors.*`
- Typography: `HowRUFont.*`
- Spacing: `HowRUSpacing.*`
- Radius: `HowRURadius.*`
- Shadows: `HowRUShadow.*`
- Haptics: `HowRUHaptics.*`
- Gradients: `HowRUGradients.*`
