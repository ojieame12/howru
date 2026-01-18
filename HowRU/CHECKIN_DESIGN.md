# Check-in Experience - Design System Spec

## Overview

The check-in is the core daily ritual. It should feel like a brief, pleasant moment of self-reflection - **10-15 seconds max**.

> **Note**: Font tokens reference `HowRUFont` from Theme.swift. See bottom of doc for mapping.

---

## Font Token Reference (from Theme.swift)

| Token in this doc | Actual Token | Font | Size |
|-------------------|--------------|------|------|
| `HowRUFont.headline()` | `HowRUFont.headline1()` | Recoleta-Regular | 32pt |
| `HowRUFont.title()` | `HowRUFont.headline2()` | Recoleta-Medium | 24pt |
| `HowRUFont.body()` | `HowRUFont.body()` | Geist-Regular | 16pt |
| `HowRUFont.bodyMedium()` | `HowRUFont.bodyMedium()` | Geist-Medium | 16pt |
| `HowRUFont.caption()` | `HowRUFont.caption()` | Geist-Regular | 14pt |
| `HowRUFont.button()` | `HowRUFont.button()` | Geist-Medium | 18pt |

---

## Components Needed

### 1. `CheckInSlider`

A custom slider with emoji endpoints and haptic feedback.

**Props:**
```swift
struct CheckInSlider: View {
    let category: CheckInCategory  // .mind, .body, .mood
    @Binding var value: Int        // 1-5
}

enum CheckInCategory {
    case mind   // 🧠
    case body   // 💪
    case mood   // 💛

    var icon: String
    var label: String
    var lowEmoji: String
    var highEmoji: String
    var color: (ColorScheme) -> Color  // uses HowRUColors.moodMental/Body/Emotional
}
```

**Visual Spec:**
```
┌─────────────────────────────────────────────────────┐
│                                                     │
│  🧠 Mind                                            │
│                                                     │
│  😵‍💫  ○─────●─────○─────○─────○  😌                  │
│       1     2     3     4     5                     │
│                                                     │
└─────────────────────────────────────────────────────┘
```

**Design tokens:**
- Track: `HowRUColors.divider(scheme)` - 4pt height, full rounded
- Thumb: 28pt circle, `HowRUColors.surface(scheme)` with shadow
- Active track: `category.color(scheme)` - fills from left to thumb
- Emoji size: 24pt
- Label: `HowRUFont.bodyMedium()` (Geist-Medium 16pt), `HowRUColors.textPrimary`
- Spacing: `HowRUSpacing.md` between elements

**Behavior:**
- Haptic: `HowRUHaptics.selection()` on each value change
- Emoji pulse: Scale 1.0 → 1.2 → 1.0 when reaching endpoint (1 or 5)
- Default value: 3 (middle)
- Snap to integers only (1, 2, 3, 4, 5)

---

### 2. `CheckInPromptView`

The "not yet checked in" state of the Check-in tab.

**Visual Spec:**
```
┌─────────────────────────────────────────────────────┐
│                                                     │
│                                                     │
│                                                     │
│              Good morning ☀️                        │
│                                                     │
│              [Streak badge: 🔥 7]                   │
│              (only if streak > 1)                   │
│                                                     │
│                                                     │
│                                                     │
│                                                     │
│              ┌─────────────────┐                    │
│              │    Check In     │                    │
│              └─────────────────┘                    │
│                                                     │
└─────────────────────────────────────────────────────┘
```

**Design tokens:**
- Background: `AnimatedGradientBackground` (liquid blobs)
- Greeting: `HowRUFont.headline1()` (Recoleta-Regular 32pt), `HowRUColors.textPrimary`
- Streak badge: Pill shape, `HowRUColors.coralGlow` bg, coral text
- Button: `HowRUCoralButtonStyle` (gradient)

**Greeting logic:**
```swift
var greeting: String {
    let hour = Calendar.current.component(.hour, from: Date())
    switch hour {
    case 5..<12: return "Good morning"
    case 12..<17: return "Good afternoon"
    case 17..<22: return "Good evening"
    default: return "Hey there"
    }
}
```

---

### 3. `CheckInFormView`

The main check-in screen with all three sliders.

**Visual Spec:**
```
┌─────────────────────────────────────────────────────┐
│  ←                                                  │
│                                                     │
│                                                     │
│              How are you today?                     │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  🧠 Mind                                      │  │
│  │  😵‍💫  ○───────●───────○  😌                    │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  💪 Body                                      │  │
│  │  🥱  ○───────●───────○  ⚡                    │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  💛 Mood                                      │  │
│  │  😔  ○───────●───────○  😊                    │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│                                                     │
│              ┌─────────────────┐                    │
│              │      Done       │                    │
│              └─────────────────┘                    │
│                                                     │
└─────────────────────────────────────────────────────┘
```

**Design tokens:**
- Background: `HowRUColors.background(scheme)` (solid, not animated)
- Title: `HowRUFont.headline2()` (Recoleta-Medium 24pt), `HowRUColors.textPrimary`
- Slider cards: `HowRUColors.surface(scheme)`, `HowRURadius.lg`, subtle shadow
- Card spacing: `HowRUSpacing.md`
- Button: `HowRUPrimaryButtonStyle`
- Back button: `HowRUIconButtonStyle`

**Behavior:**
- Sliders start at 3 (neutral)
- Back button: Confirms if values changed, then dismisses
- Done button: Always enabled (all values have defaults)

---

### 4. `CheckInCompleteView`

Success state after submitting.

**Visual Spec:**
```
┌─────────────────────────────────────────────────────┐
│                                                     │
│                                                     │
│                                                     │
│                      ✓                              │
│                  All done                           │
│                                                     │
│           ┌─────────────────────────┐               │
│           │  🧠 4    💪 3    💛 5   │               │
│           └─────────────────────────┘               │
│                                                     │
│                                                     │
│           ┌─────────────────────────┐               │
│           │  📷 Add a snapshot?     │               │
│           └─────────────────────────┘               │
│                                                     │
│                                                     │
│              ┌─────────────────┐                    │
│              │     Finish      │                    │
│              └─────────────────┘                    │
│                                                     │
└─────────────────────────────────────────────────────┘
```

**Design tokens:**
- Background: `AnimatedGradientBackground`
- Checkmark: 48pt, `HowRUColors.success(scheme)`
- Title: `HowRUFont.headline1()` (Recoleta-Regular 32pt), `HowRUColors.textPrimary`
- Score summary: `HowRUSummaryBadge` component, inline
- Snapshot button: `HowRUSecondaryButtonStyle` with camera icon
- Finish button: `HowRUPrimaryButtonStyle`

**Animation:**
- Checkmark: Scale from 0 → 1.2 → 1.0 with spring
- Scores: Fade in with 0.2s delay
- Haptic: `HowRUHaptics.success()` on appear

---

### 5. `CheckInDoneView`

The "already checked in" state of the Check-in tab.

**Visual Spec:**
```
┌─────────────────────────────────────────────────────┐
│                                                     │
│              ✓ Checked in                           │
│              9:32 AM                                │
│                                                     │
│           ┌─────────────────────────┐               │
│           │                         │               │
│           │  🧠 4    💪 3    💛 5   │  ← Tap to     │
│           │                         │    edit       │
│           └─────────────────────────┘               │
│                                                     │
│           ┌─────────────────────────┐               │
│           │  📷 Snapshot added      │               │
│           │  ⏱ Expires in 18h       │               │
│           └─────────────────────────┘               │
│                                                     │
│           ┌─────────────────────────┐               │
│           │  [7-day sparkline]      │               │
│           │  View Trends →          │               │
│           └─────────────────────────┘               │
│                                                     │
└─────────────────────────────────────────────────────┘
```

**Design tokens:**
- Background: `AnimatedGradientBackground`
- Checkmark + title: `HowRUColors.success(scheme)`
- Time: `HowRUFont.caption()` (Geist-Regular 14pt), `HowRUColors.textSecondary`
- Score card: `HowRUColors.surface(scheme)`, tappable
- Snapshot card: Same styling, shows thumbnail if exists
- Trend card: Same styling, mini sparkline chart

---

### 6. `SnapshotCaptureView`

Camera view for taking the ephemeral selfie.

**Visual Spec:**
```
┌─────────────────────────────────────────────────────┐
│  ✕                                                  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │                                               │  │
│  │                                               │  │
│  │                                               │  │
│  │            [Camera Preview]                   │  │
│  │                                               │  │
│  │                                               │  │
│  │                                               │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│         Quick snap for your circle                  │
│                                                     │
│                   ┌───┐                             │
│                   │ ○ │  ← Shutter button           │
│                   └───┘                             │
│                                                     │
│                  [Skip]                             │
│                                                     │
└─────────────────────────────────────────────────────┘
```

**Design tokens:**
- Background: Black
- Camera preview: Full width, 4:3 or square aspect
- Text: `HowRUFont.body()` (Geist-Regular 16pt), white
- Shutter: 64pt circle, white stroke, tap to capture
- Skip: `HowRUGhostButtonStyle`, white text
- Close: `HowRUIconButtonStyle`, white

**Behavior:**
- Front camera by default
- No filters, no effects
- Haptic: `HowRUHaptics.medium()` on capture

---

### 7. `SnapshotPreviewView`

Preview after capturing, before sending.

**Visual Spec:**
```
┌─────────────────────────────────────────────────────┐
│  ✕                                                  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │                                               │  │
│  │                                               │  │
│  │            [Captured Photo]                   │  │
│  │                                               │  │
│  │                                               │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│         ⏱ Visible for 24 hours                      │
│         👁 Only your circle can see                 │
│                                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │   Send   │  │  Retake  │  │   Skip   │          │
│  └──────────┘  └──────────┘  └──────────┘          │
│                                                     │
└─────────────────────────────────────────────────────┘
```

**Design tokens:**
- Background: Black
- Photo: Full width with rounded corners
- Info text: `HowRUFont.caption()` (Geist-Regular 14pt), `HowRUColors.textSecondary`
- Send: `HowRUCoralButtonStyle` (primary action)
- Retake/Skip: `HowRUSecondaryButtonStyle` or ghost

---

## Emoji Mapping

| Category | Icon | Low (1) | High (5) | Color Token |
|----------|------|---------|----------|-------------|
| Mind | 🧠 | 😵‍💫 | 😌 | `moodMental` |
| Body | 💪 | 🥱 | ⚡ | `moodBody` |
| Mood | 💛 | 😔 | 😊 | `moodEmotional` |

**Note:** Using neutral colors on the slider track itself - no red-to-green gradient. The category color is used subtly (active track fill, icon tint) but doesn't imply judgment.

---

## State Machine

```
CheckInState
├── .notCheckedIn     → CheckInPromptView
├── .inProgress       → CheckInFormView
├── .complete         → CheckInCompleteView (brief)
├── .addingSnapshot   → SnapshotCaptureView
├── .previewSnapshot  → SnapshotPreviewView
└── .done             → CheckInDoneView
```

---

## Data Flow

```swift
// After submit:
1. Create CheckIn in SwiftData
2. Trigger haptic success
3. Show CheckInCompleteView
4. If user adds snapshot:
   a. Capture photo
   b. Store locally (encrypted)
   c. Set expiry = now + 24h
   d. Attach to CheckIn
5. Navigate to CheckInDoneView
6. Background: Notify supporters (silent push)
```

---

## Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `Theme.swift` | Add | `CheckInSlider` component |
| `CheckInView.swift` | Rewrite | Implement state machine + all views |
| `SnapshotView.swift` | Create | Camera capture + preview |
| `Models/CheckIn.swift` | Modify | Add `selfieData: Data?`, `selfieExpiresAt: Date?` |

---

## Implementation Order

1. **`CheckInSlider`** - Core interaction component
2. **`CheckInPromptView`** - Entry point
3. **`CheckInFormView`** - Main form
4. **`CheckInCompleteView`** - Success state
5. **`CheckInDoneView`** - Already done state
6. **`SnapshotCaptureView`** - Camera (can defer)
7. **`SnapshotPreviewView`** - Preview (can defer)
