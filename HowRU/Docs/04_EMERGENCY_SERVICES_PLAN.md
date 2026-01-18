# HowRU Emergency Services Plan

## Overview

Multi-tier alert escalation system with automated voice calls and optional emergency dispatch integration.

---

## 1. Alert Escalation Timeline

```
Check-in Window Closes
         │
         ▼
    [Grace Period: 30min]
         │
         ▼ (No check-in)
┌────────────────────────┐
│  LEVEL 1: Reminder     │  +0h
│  Push to Checker       │
└────────────────────────┘
         │
         ▼ (No response 1h)
┌────────────────────────┐
│  LEVEL 2: SMS Reminder │  +1h
│  SMS to Checker        │
└────────────────────────┘
         │
         ▼ (No response 24h)
┌────────────────────────┐
│  LEVEL 3: Soft Alert   │  +24h
│  Push + SMS to         │
│  Priority 1 Supporters │
└────────────────────────┘
         │
         ▼ (No response 36h)
┌────────────────────────┐
│  LEVEL 4: Hard Alert   │  +36h
│  Push + SMS + Voice    │
│  to ALL Supporters     │
└────────────────────────┘
         │
         ▼ (No response 48h)
┌────────────────────────┐
│  LEVEL 5: Escalation   │  +48h
│  Emergency Contacts    │
│  Optional: Wellness    │
│  Check Dispatch        │
└────────────────────────┘
```

---

## 2. Notification Channels

### Push Notification (Free)

```json
{
  "title": "Check-in Reminder",
  "body": "Don't forget to check in today!",
  "sound": "default",
  "badge": 1,
  "data": {
    "type": "reminder",
    "action": "open_checkin"
  }
}
```

### SMS (Premium)

```
HowRU Alert: Betty hasn't checked in for 24 hours.
Please check on her or tap to call: https://howru.app/call/betty

Reply STOP to opt out.
```

### Voice Call (Premium - Hard Alert)

```xml
<Response>
  <Say voice="alice">
    This is an urgent alert from How Are You.
    Betty has not checked in for 36 hours.
    Please check on her immediately.
    Press 1 to acknowledge this alert.
    Press 2 to hear her contact information.
  </Say>
  <Gather numDigits="1" action="/voice/gather">
    <Say>Press 1 to acknowledge, or press 2 for contact info.</Say>
  </Gather>
</Response>
```

### Critical Alert (iOS - Bypass DND)

Requires Apple entitlement. Use for Level 4+.

```swift
let content = UNMutableNotificationContent()
content.title = "URGENT: Missed Check-in"
content.body = "Betty hasn't checked in for 36 hours"
content.sound = .defaultCritical  // Bypasses DND
content.interruptionLevel = .critical
```

---

## 3. Voice Call Implementation

### Option A: Server-Initiated Call (Twilio)

**Pros:** Reliable, works even if checker's phone is off
**Cons:** Costs ~$0.02/min, feels impersonal

```javascript
// Server (Node.js)
import twilio from 'twilio';

const client = twilio(ACCOUNT_SID, AUTH_TOKEN);

async function initiateAlertCall(supporter, checker, alertId) {
  const call = await client.calls.create({
    to: supporter.phone,
    from: TWILIO_PHONE_NUMBER,
    url: `https://api.howru.app/voice/alert/${alertId}`,
    statusCallback: `https://api.howru.app/voice/status/${alertId}`,
    statusCallbackEvent: ['completed', 'answered', 'no-answer']
  });

  return call.sid;
}
```

**TwiML Handler:**

```javascript
app.post('/voice/alert/:alertId', async (req, res) => {
  const alert = await getAlert(req.params.alertId);
  const checker = await getUser(alert.checkerId);

  const twiml = new VoiceResponse();

  twiml.say({
    voice: 'alice'
  }, `This is an urgent wellness alert from How Are You. ${checker.name} has not checked in for ${alert.hoursSinceMissed} hours. Please check on them immediately.`);

  const gather = twiml.gather({
    numDigits: 1,
    action: `/voice/gather/${req.params.alertId}`,
    timeout: 10
  });

  gather.say('Press 1 to acknowledge this alert. Press 2 to repeat.');

  // If no input, repeat
  twiml.redirect(`/voice/alert/${req.params.alertId}`);

  res.type('text/xml');
  res.send(twiml.toString());
});

app.post('/voice/gather/:alertId', async (req, res) => {
  const digit = req.body.Digits;
  const twiml = new VoiceResponse();

  if (digit === '1') {
    await acknowledgeAlert(req.params.alertId, req.body.Called);
    twiml.say('Thank you. The alert has been acknowledged. Goodbye.');
    twiml.hangup();
  } else if (digit === '2') {
    twiml.redirect(`/voice/alert/${req.params.alertId}`);
  }

  res.type('text/xml');
  res.send(twiml.toString());
});
```

### Option B: Device-Initiated Call (CallKit)

**Pros:** Free (uses user's minutes), feels personal
**Cons:** Requires app running, iOS limitations

```swift
import CallKit

class CallService {
    private let callController = CXCallController()

    func initiateCall(to phoneNumber: String) {
        guard let url = URL(string: "tel://\(phoneNumber)") else { return }

        // This opens the Phone app - simplest approach
        UIApplication.shared.open(url)
    }

    // Alternative: Use CallKit for more control
    func startCallWithKit(to handle: String) {
        let uuid = UUID()
        let handle = CXHandle(type: .phoneNumber, value: handle)
        let action = CXStartCallAction(call: uuid, handle: handle)

        let transaction = CXTransaction(action: action)
        callController.request(transaction) { error in
            if let error = error {
                print("Call failed: \(error)")
            }
        }
    }
}
```

### Hybrid Approach (Recommended)

1. **First attempt:** Push notification + SMS
2. **If no response (1h):** Prompt supporter to call via app (free)
3. **If still no response (2h):** Server-initiated Twilio call

---

## 4. Emergency Contact Management

### Data Model

```sql
CREATE TABLE emergency_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    relationship VARCHAR(50),  -- 'spouse', 'child', 'neighbor', 'doctor', 'other'
    priority INT DEFAULT 1,
    notify_on_escalation BOOLEAN DEFAULT true,
    notes TEXT,  -- Medical conditions, door code, etc.
    created_at TIMESTAMP DEFAULT NOW()
);
```

### API Endpoints

```
GET /emergency-contacts
POST /emergency-contacts
PUT /emergency-contacts/:id
DELETE /emergency-contacts/:id
```

---

## 5. Wellness Check Dispatch

### Legal Considerations

- **Cannot auto-dial 911** in most jurisdictions
- False alarms can result in fees/liability
- Requires explicit user consent
- Must store accurate address

### Option A: Prompt Human to Call

At Level 5, display to supporter:

```
┌─────────────────────────────────┐
│  ⚠️ ESCALATION REQUIRED         │
├─────────────────────────────────┤
│  Betty hasn't responded for     │
│  48 hours.                      │
│                                 │
│  Consider requesting a          │
│  wellness check:                │
│                                 │
│  📍 123 Main St, Springfield    │
│  📞 Non-emergency: 555-0100     │
│                                 │
│  [Copy Script]  [Call Now]      │
└─────────────────────────────────┘
```

**Pre-written script:**

> "Hello, I'd like to request a wellness check. My [grandmother] lives at [123 Main St] and hasn't responded to calls for 48 hours. Her name is [Betty Smith], she's [82 years old]. She [has diabetes and limited mobility]. Can you please send someone to check on her?"

### Option B: Noonlight Integration

[Noonlight](https://www.noonlight.com/) is a certified emergency dispatch service with an API.

**Features:**
- Certified 911 dispatch
- Handles liability/compliance
- Provides dispatcher with context
- ~$0.25-$1.00 per dispatch

**Integration:**

```javascript
// Noonlight API (simplified)
async function createNoonlightAlarm(user, alert) {
  const response = await fetch('https://api.noonlight.com/v1/alarms', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${NOONLIGHT_API_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      location: {
        address: {
          line1: user.address,
          city: user.city,
          state: user.state,
          zip: user.zip
        }
      },
      person: {
        name: user.name,
        phone: user.phone
      },
      services: {
        police: true,  // Wellness check
        fire: false,
        medical: user.medicalConditions ? true : false
      },
      context: `Elderly wellness check. ${user.name} has not responded for ${alert.hoursSinceMissed} hours. ${user.medicalNotes || ''}`
    })
  });

  return response.json();
}
```

### Option C: Local Emergency Services Database

Build database of non-emergency numbers:

```sql
CREATE TABLE emergency_services (
    id UUID PRIMARY KEY,
    zip_code VARCHAR(10),
    city VARCHAR(100),
    state VARCHAR(2),
    non_emergency_police VARCHAR(20),
    non_emergency_fire VARCHAR(20),
    adult_protective_services VARCHAR(20),
    updated_at TIMESTAMP
);
```

Populate via:
- Manual research
- Community contributions
- APIs (limited availability)

---

## 6. User Consent Flow

### During Onboarding

```
┌─────────────────────────────────┐
│  Emergency Escalation           │
├─────────────────────────────────┤
│  If you don't check in for      │
│  48+ hours and no one can       │
│  reach you, would you like us   │
│  to help request a wellness     │
│  check?                         │
│                                 │
│  This requires:                 │
│  • Your address                 │
│  • Emergency contact info       │
│                                 │
│  [Yes, Set Up]  [Maybe Later]   │
└─────────────────────────────────┘
```

### Address Verification

```
┌─────────────────────────────────┐
│  Verify Your Address            │
├─────────────────────────────────┤
│  This address will be shared    │
│  with emergency services only   │
│  if escalation is needed.       │
│                                 │
│  ┌───────────────────────────┐  │
│  │ 123 Main Street           │  │
│  │ Apt 4B                    │  │
│  │ Springfield, IL 62701     │  │
│  └───────────────────────────┘  │
│                                 │
│  Access notes (optional):       │
│  ┌───────────────────────────┐  │
│  │ Door code: 1234           │  │
│  │ Key under mat             │  │
│  └───────────────────────────┘  │
│                                 │
│  [Confirm Address]              │
└─────────────────────────────────┘
```

---

## 7. Alert Resolution Tracking

### Status Flow

```
PENDING → ACKNOWLEDGED → RESOLVED
    ↓
ESCALATED → DISPATCHED → RESOLVED
```

### Resolution Types

| Type | Description |
|------|-------------|
| `contacted` | Supporter reached checker |
| `checked_in` | Checker did a check-in |
| `false_alarm` | Checker was fine, just forgot |
| `hospitalized` | Checker is in hospital |
| `other` | Other resolution |

---

## 8. Privacy & Security

### Data Encryption

- Address encrypted at rest (AES-256)
- Medical notes encrypted at rest
- TLS for all transmission
- Access logged for audit

### Data Retention

- Alert history: 90 days
- Dispatch records: 7 years (legal)
- Call recordings: 30 days

### Access Control

- Only supporters see checker's address during escalation
- Emergency services only contacted with explicit consent
- Audit log of all data access

---

## 9. Cost Estimates

### Per-Alert Costs

| Channel | Cost |
|---------|------|
| Push notification | Free |
| SMS | $0.01-0.02 |
| Voice call (Twilio) | $0.02/min |
| Noonlight dispatch | $0.25-1.00 |

### Monthly Estimates (1K users, 5% alert rate)

| Item | Monthly |
|------|---------|
| SMS alerts (~50) | $0.50-1.00 |
| Voice calls (~10) | $2-5 |
| Noonlight (~1-2) | $0.50-2.00 |
| **Total** | **~$5-10** |

---

## 10. Implementation Phases

### Phase 1: Basic Alerts
- [ ] Push notifications
- [ ] SMS via Twilio
- [ ] Alert acknowledgment

### Phase 2: Voice Calls
- [ ] Twilio Voice integration
- [ ] TwiML handlers
- [ ] Call status tracking

### Phase 3: Emergency Contacts
- [ ] Contact management UI
- [ ] Address verification
- [ ] Pre-written scripts

### Phase 4: Dispatch Integration
- [ ] Noonlight research/contract
- [ ] Integration implementation
- [ ] Legal review

---

## 11. Open Questions

1. **Liability:** Need legal review for dispatch features
2. **Consent:** What's minimum consent for emergency dispatch?
3. **International:** How to handle non-US users?
4. **Medical info:** HIPAA implications for storing conditions?

---

## Next Document

See `05_INFRASTRUCTURE_PLAN.md` for Railway/Vercel/Neon setup.
