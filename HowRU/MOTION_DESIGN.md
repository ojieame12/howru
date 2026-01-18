# HowRU Motion & Animation Design System

## Philosophy

Motion in HowRU should feel like **water** - continuous, fluid, responsive. Never mechanical or linear. The app should feel **alive** but **calm**, matching the warm, caring brand.

### Core Principles

1. **Purposeful** - Motion communicates hierarchy and state changes, not decoration
2. **Subtle** - Users shouldn't notice animations, they should feel them
3. **Accessible** - Respect `accessibilityReduceMotion` for all non-essential animation
4. **Consistent** - Same motion language across the entire app

---

## Animation Tokens

### Timing

| Token | Duration | Use Case |
|-------|----------|----------|
| `micro` | 120-180ms | Button press, toggle, small state changes |
| `standard` | 250-350ms | Screen transitions, card expansions |
| `ambient` | 1500-3000ms | Background blobs, breathing cards |

### Springs

```swift
// MARK: - Animation Springs

extension Animation {
    /// Snappy interaction spring - buttons, toggles, taps
    static let howruSnappy = Animation.spring(response: 0.35, dampingFraction: 0.7)

    /// Smooth transition spring - screen changes, expansions
    static let howruSmooth = Animation.spring(response: 0.5, dampingFraction: 0.8)

    /// Bouncy spring - success states, celebrations
    static let howruBouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)

    /// Interactive spring - drag gestures, sliders
    static let howruInteractive = Animation.interactiveSpring(response: 0.3, dampingFraction: 0.7)
}
```

### Easing Rules

| Type | Easing | When |
|------|--------|------|
| Taps/Controls | `.howruSnappy` (spring) | All interactive elements |
| View transitions | `.howruSmooth` (spring) | Navigation, sheets |
| Progress | `.linear` | Loading indicators |
| Numbers | `.easeInOut(duration: 0.25)` | Stat counters |
| Ambient | `.linear` | Background blobs |

---

## Accessibility

**Always gate non-essential animations:**

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

// Usage
withAnimation(reduceMotion ? .none : .howruSnappy) {
    showConfirmation = true
}

// For ambient motion
if !reduceMotion {
    AnimatedGradientBackground()
} else {
    StaticGradientBackground()
}
```

**Essential animations (always keep):**
- Button press feedback (scale)
- Navigation transitions (system default)
- Loading states

**Non-essential (disable with reduceMotion):**
- Background blob movement
- Card breathing
- Decorative pulses
- Parallax effects

---

## Microinteractions

### 1. The "Squish" (Button Press)

All tappable elements compress slightly on press.

```swift
// Already implemented in HowRUPrimaryButtonStyle
.scaleEffect(configuration.isPressed ? 0.98 : 1.0)
.animation(.howruSnappy, value: configuration.isPressed)
```

**Enhancement - Add sensory feedback (iOS 17+):**
```swift
.sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed)
```

### 2. Slider Interaction

Custom fluid slider with inertia and haptic ticks.

```swift
struct CheckInSlider: View {
    @Binding var value: Int
    @State private var dragOffset: CGFloat = 0
    @GestureState private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            // Track
            Capsule()
                .fill(trackColor)

            // Thumb with fluid motion
            Circle()
                .fill(.white)
                .shadow(...)
                .offset(x: thumbPosition(in: geo.size.width))
                .animation(.howruInteractive, value: value)
                .gesture(
                    DragGesture()
                        .updating($isDragging) { _, state, _ in state = true }
                        .onChanged { drag in
                            let newValue = valueFromPosition(drag.location.x, width: geo.size.width)
                            if newValue != value {
                                value = newValue
                                HowRUHaptics.selection() // Tick on each value
                            }
                        }
                )
        }
    }
}
```

### 3. Emoji Endpoint Pulse

When slider reaches 1 or 5, the endpoint emoji pulses.

```swift
@State private var pulseScale: CGFloat = 1.0

Text(lowEmoji)
    .scaleEffect(value == 1 ? pulseScale : 1.0)
    .onChange(of: value) { old, new in
        if new == 1 || new == 5 {
            withAnimation(.howruBouncy) {
                pulseScale = 1.3
            }
            withAnimation(.howruBouncy.delay(0.1)) {
                pulseScale = 1.0
            }
        }
    }
```

### 4. Toggle Haptics

Add premium feel to all toggles in Settings.

```swift
Toggle("Notifications", isOn: $notificationsEnabled)
    .sensoryFeedback(.impact(weight: .medium), trigger: notificationsEnabled)
```

---

## Screen Transitions

### Onboarding Steps

**Current:** Basic crossfade between steps
**Enhanced:** Shared element transition for continuity

```swift
@Namespace private var onboardingNamespace

// Logo travels between screens
LogoWithGlow()
    .matchedGeometryEffect(id: "logo", in: onboardingNamespace)

// Progress indicator persists
HowRUProgressIndicator(current: step, total: 5)
    .matchedGeometryEffect(id: "progress", in: onboardingNamespace)
```

**Step transition with blur:**
```swift
.transition(
    .asymmetric(
        insertion: .opacity.combined(with: .blur),
        removal: .opacity.combined(with: .blur)
    )
)
```

### Check-in Flow

**Prompt → Form:**
- Button morphs into form card (matchedGeometryEffect)
- Or: Simple push with system navigation

**Form → Complete:**
- Form fades out
- Checkmark scales in with bounce
- Scores fade in with stagger

```swift
// Success checkmark
Image(systemName: "checkmark.circle.fill")
    .font(.system(size: 64))
    .foregroundStyle(HowRUColors.success(colorScheme))
    .symbolEffect(.bounce, value: showComplete)
    .sensoryFeedback(.success, trigger: showComplete)
    .scaleEffect(showComplete ? 1 : 0)
    .animation(.howruBouncy, value: showComplete)
```

### Sheet Presentations

Keep system default sheet transitions. Add glass morphism to content.

```swift
.sheet(isPresented: $showSheet) {
    SheetContent()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial) // Glass effect
}
```

---

## Ambient Motion

### Background Blobs

**Already implemented** in `AnimatedGradientBackground` with Canvas + TimelineView.

**Refinements:**
- Slow down movement speed (currently good)
- Ensure smooth 60fps
- Gate behind `reduceMotion`

```swift
struct AnimatedGradientBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            StaticGradientBackground()
        } else {
            // Existing TimelineView implementation
        }
    }
}
```

### Breathing Cards (Subtle)

Cards have imperceptible vertical float.

```swift
struct BreathingCard<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breatheOffset: CGFloat = 0
    let content: Content

    var body: some View {
        content
            .offset(y: reduceMotion ? 0 : breatheOffset)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    .easeInOut(duration: Double.random(in: 2.5...3.5))
                    .repeatForever(autoreverses: true)
                ) {
                    breatheOffset = CGFloat.random(in: -1.5...1.5)
                }
            }
    }
}
```

**Use sparingly** - only on prominent cards like the check-in prompt or supporter status.

---

## Component-Specific Motion

### Trends View

**Time range picker:**
```swift
Picker("Time Range", selection: $selectedTimeRange)
    .onChange(of: selectedTimeRange) { _, _ in
        withAnimation(.howruSmooth) {
            // Data refresh triggers layout change
        }
    }
```

**Numeric stats with contentTransition:**
```swift
Text("\(currentStreak)")
    .contentTransition(.numericText())
    .animation(.easeInOut(duration: 0.25), value: currentStreak)

Text(String(format: "%.1f", averageMood))
    .contentTransition(.numericText())
    .animation(.easeInOut(duration: 0.25), value: averageMood)
```

**Chart animation:**
```swift
Chart(filteredCheckIns) { checkIn in
    LineMark(...)
}
.animation(.howruSmooth, value: selectedTimeRange)
```

### Circle View

**New supporter row insert:**
```swift
ForEach(supporters) { supporter in
    SupporterRow(supporter: supporter)
        .transition(.move(edge: .trailing).combined(with: .opacity))
}
.animation(.howruSmooth, value: supporters)
```

**Pending badge pulse (once on appear, not continuous):**
```swift
struct PendingBadge: View {
    @State private var hasAppeared = false

    var body: some View {
        Text("Pending")
            .scaleEffect(hasAppeared ? 1 : 0.8)
            .opacity(hasAppeared ? 1 : 0)
            .onAppear {
                withAnimation(.howruBouncy.delay(0.2)) {
                    hasAppeared = true
                }
            }
    }
}
```

### Check-in Slider

**Submit button morph:**
```swift
// Before submit
Button("Done") { ... }
    .matchedGeometryEffect(id: "submitButton", in: namespace)

// During submit (loading)
ProgressView()
    .matchedGeometryEffect(id: "submitButton", in: namespace)

// After submit (success)
Image(systemName: "checkmark.circle.fill")
    .matchedGeometryEffect(id: "submitButton", in: namespace)
    .symbolEffect(.bounce)
```

---

## Haptic Pairing

| Action | Haptic | Animation |
|--------|--------|-----------|
| Button press | `.light` | Scale 0.98 |
| Button release | - | Scale 1.0 |
| Slider tick | `.selection` | - |
| Slider endpoint | `.medium` | Emoji pulse |
| Submit success | `.success` | Checkmark bounce |
| Error | `.error` | Shake + red flash |
| Toggle | `.medium` | System default |
| Pull to refresh | `.light` | System default |

---

## Implementation Priority

### Phase 1: Foundation (Low Risk)
1. Add `Animation` extension with spring tokens
2. Add `reduceMotion` checks to `AnimatedGradientBackground`
3. Add `sensoryFeedback` to button styles (iOS 17+)
4. Add `contentTransition(.numericText())` to TrendsView stats

### Phase 2: Polish
1. Implement `CheckInSlider` with fluid motion
2. Add endpoint emoji pulse
3. Add sheet glass morphism
4. Add supporter row insert animation

### Phase 3: Delight
1. Add breathing cards (very subtle)
2. Add onboarding matchedGeometryEffect
3. Add submit button morph sequence
4. Refine background blob movement

---

## Code to Add to Theme.swift

```swift
// MARK: - Animation Tokens

extension Animation {
    /// Snappy interaction spring - buttons, toggles, taps
    static let howruSnappy = Animation.spring(response: 0.35, dampingFraction: 0.7)

    /// Smooth transition spring - screen changes, expansions
    static let howruSmooth = Animation.spring(response: 0.5, dampingFraction: 0.8)

    /// Bouncy spring - success states, celebrations
    static let howruBouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)

    /// Interactive spring - drag gestures, sliders
    static let howruInteractive = Animation.interactiveSpring(response: 0.3, dampingFraction: 0.7)
}

// MARK: - Transition Helpers

extension AnyTransition {
    /// Fade with blur for onboarding steps
    static let howruBlurFade = AnyTransition.opacity.combined(with: .blur)

    /// Slide from trailing with fade for list inserts
    static let howruSlideIn = AnyTransition.move(edge: .trailing).combined(with: .opacity)
}
```

---

## Testing Checklist

- [ ] Test all animations with Reduce Motion ON
- [ ] Verify 60fps on oldest supported device
- [ ] Check haptics feel appropriate (not too strong)
- [ ] Ensure no animation blocks user interaction
- [ ] Verify springs don't overshoot causing layout jumps
- [ ] Test sheet dismiss gesture feels natural
- [ ] Verify contentTransition doesn't cause text flicker

---

## References

- [Apple HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion)
- [SwiftUI contentTransition](https://developer.apple.com/documentation/swiftui/view/contenttransition)
- [SwiftUI symbolEffect](https://developer.apple.com/documentation/swiftui/view/symboleffect)
- [SwiftUI sensoryFeedback](https://developer.apple.com/documentation/swiftui/view/sensoryfeedback)
- [SwiftUI matchedGeometryEffect](https://developer.apple.com/documentation/swiftui/view/matchedgeometryeffect)
