# HowRU UI Design Plan - Liquid iOS 18

## Overview

Premium wellness app with liquid glass aesthetics, fluid animations, and elderly-friendly interactions using your established HowRU theme system.

**Design Principles:**
- Liquid glass morphism with subtle depth
- Generous touch targets (minimum 44pt, prefer 56pt for primary actions)
- High contrast, elderly-friendly typography (Recoleta headlines, Geist body)
- Smooth spring animations with accessibility fallbacks
- Warm coral palette with adaptive light/dark themes

---

## 1. Design Language Summary

### Existing Theme Tokens (from Theme.swift)

| Category | Token | Value |
|----------|-------|-------|
| **Animation** | `.howruSnappy` | Spring 0.35s, 0.7 damping |
| **Animation** | `.howruSmooth` | Spring 0.5s, 0.8 damping |
| **Animation** | `.howruBouncy` | Spring 0.4s, 0.6 damping |
| **Animation** | `.howruInteractive` | Interactive spring 0.3s |
| **Spacing** | `screenEdge` | 24pt |
| **Spacing** | `xl` / `lg` / `md` | 32 / 24 / 16pt |
| **Radius** | `lg` / `xl` / `full` | 20 / 28 / 9999pt |
| **Typography** | Headline | Recoleta (serif) |
| **Typography** | Body | Geist (sans-serif) |
| **Brand** | Coral | #E85A3C |
| **Brand** | CoralLight | #F4A68E |

### iOS 18 Liquid Additions

| Component | Implementation |
|-----------|----------------|
| Glass cards | `.ultraThinMaterial` + white overlay |
| Depth shadows | Multi-layer soft shadows |
| Fluid corners | Continuous corner curves |
| Haptic sync | Tied to spring animation keyframes |
| Mesh gradients | Animated organic blobs |

---

## 2. New UI Components to Create

### 2.1 Glass Card Component

```swift
// Sources/Theme/Components/GlassCard.swift

struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var intensity: GlassIntensity = .medium
    @ViewBuilder let content: () -> Content

    enum GlassIntensity {
        case subtle   // Ultra thin, mostly transparent
        case medium   // Balanced blur + tint
        case frosted  // Heavy blur, more opaque
    }

    var body: some View {
        content()
            .background {
                GlassBackground(intensity: intensity, colorScheme: colorScheme)
            }
            .clipShape(RoundedRectangle(cornerRadius: HowRURadius.lg, style: .continuous))
            .shadow(
                color: HowRUColors.shadow(colorScheme).opacity(0.15),
                radius: 20, x: 0, y: 10
            )
            .shadow(
                color: HowRUColors.shadow(colorScheme).opacity(0.05),
                radius: 4, x: 0, y: 2
            )
    }
}

struct GlassBackground: View {
    let intensity: GlassCard<EmptyView>.GlassIntensity
    let colorScheme: ColorScheme

    var body: some View {
        ZStack {
            // Base material
            material

            // White/dark overlay for depth
            RoundedRectangle(cornerRadius: HowRURadius.lg, style: .continuous)
                .fill(overlayColor)

            // Subtle inner border
            RoundedRectangle(cornerRadius: HowRURadius.lg, style: .continuous)
                .stroke(borderGradient, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var material: some View {
        switch intensity {
        case .subtle:
            Rectangle().fill(.ultraThinMaterial)
        case .medium:
            Rectangle().fill(.thinMaterial)
        case .frosted:
            Rectangle().fill(.regularMaterial)
        }
    }

    private var overlayColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(intensity == .subtle ? 0.02 : 0.05)
            : Color.white.opacity(intensity == .subtle ? 0.3 : 0.5)
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.15 : 0.6),
                Color.white.opacity(colorScheme == .dark ? 0.05 : 0.2)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
```

### 2.2 Liquid Button Component

```swift
// Sources/Theme/Components/LiquidButton.swift

struct LiquidButton: View {
    let title: String
    var icon: String? = nil
    var style: LiquidButtonStyle = .primary
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false
    @State private var isHovered = false

    enum LiquidButtonStyle {
        case primary    // Solid coral gradient
        case secondary  // Glass with border
        case ghost      // Text only with subtle background on press
    }

    var body: some View {
        Button(action: {
            HowRUHaptics.medium()
            action()
        }) {
            HStack(spacing: HowRUSpacing.sm) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                }
                Text(title)
                    .font(HowRUFont.button())
            }
            .foregroundColor(foregroundColor)
            .frame(maxWidth: style == .ghost ? nil : .infinity)
            .frame(height: 56)
            .padding(.horizontal, HowRUSpacing.lg)
            .background(buttonBackground)
            .clipShape(RoundedRectangle(cornerRadius: HowRURadius.lg, style: .continuous))
            .overlay {
                if style == .secondary {
                    RoundedRectangle(cornerRadius: HowRURadius.lg, style: .continuous)
                        .stroke(HowRUColors.divider(colorScheme), lineWidth: 1)
                }
            }
            .shadow(color: shadowColor, radius: isPressed ? 4 : 12, x: 0, y: isPressed ? 2 : 6)
        }
        .buttonStyle(LiquidPressStyle(isPressed: $isPressed))
        .animation(.howruSnappy, value: isPressed)
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: return .white
        case .secondary: return HowRUColors.textPrimary(colorScheme)
        case .ghost: return HowRUColors.coral
        }
    }

    @ViewBuilder
    private var buttonBackground: some View {
        switch style {
        case .primary:
            LinearGradient(
                colors: [
                    HowRUColors.coral,
                    HowRUColors.coral.opacity(0.9)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .secondary:
            HowRUColors.surface(colorScheme)
        case .ghost:
            Color.clear
        }
    }

    private var shadowColor: Color {
        switch style {
        case .primary: return HowRUColors.coral.opacity(0.3)
        case .secondary, .ghost: return HowRUColors.shadow(colorScheme)
        }
    }
}

struct LiquidPressStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .onChange(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
            }
    }
}
```

### 2.3 Floating Action Button (FAB)

```swift
// Sources/Theme/Components/FloatingActionButton.swift

struct FloatingActionButton: View {
    let icon: String
    var size: CGFloat = 64
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            HowRUHaptics.heavy()
            action()
        }) {
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                HowRUColors.coral.opacity(0.4),
                                HowRUColors.coral.opacity(0)
                            ],
                            center: .center,
                            startRadius: size * 0.4,
                            endRadius: size * 0.8
                        )
                    )
                    .frame(width: size * 1.4, height: size * 1.4)
                    .blur(radius: 8)

                // Main button
                Circle()
                    .fill(HowRUGradients.coral)
                    .frame(width: size, height: size)
                    .shadow(
                        color: HowRUColors.coral.opacity(0.4),
                        radius: isPressed ? 8 : 16,
                        x: 0,
                        y: isPressed ? 4 : 8
                    )

                // Icon
                Image(systemName: icon)
                    .font(.system(size: size * 0.35, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(LiquidPressStyle(isPressed: $isPressed))
        .animation(.howruBouncy, value: isPressed)
    }
}
```

### 2.4 Liquid Slider (Enhanced Check-In Slider)

```swift
// Sources/Theme/Components/LiquidSlider.swift

struct LiquidSlider: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 1...5
    var category: SliderCategory = .mood
    var leftEmoji: String = "😢"
    var rightEmoji: String = "😊"

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isDragging = false
    @State private var emojiScale: CGFloat = 1.0

    enum SliderCategory {
        case mind, body, mood

        var color: (ColorScheme) -> Color {
            switch self {
            case .mind: return HowRUColors.moodMental
            case .body: return HowRUColors.moodBody
            case .mood: return { _ in HowRUColors.coral }
            }
        }
    }

    var body: some View {
        VStack(spacing: HowRUSpacing.md) {
            // Emoji row with pulsing effect at endpoints
            HStack {
                Text(leftEmoji)
                    .font(.system(size: 32))
                    .scaleEffect(value == range.lowerBound ? emojiScale : 1.0)

                Spacer()

                // Value indicator
                Text("\(value)")
                    .font(HowRUFont.headline2())
                    .foregroundColor(category.color(colorScheme))
                    .contentTransition(.numericText())
                    .animation(.howruSnappy, value: value)

                Spacer()

                Text(rightEmoji)
                    .font(.system(size: 32))
                    .scaleEffect(value == range.upperBound ? emojiScale : 1.0)
            }

            // Custom track
            GeometryReader { geometry in
                let trackWidth = geometry.size.width
                let thumbSize: CGFloat = 32
                let thumbPosition = thumbPosition(in: trackWidth, thumbSize: thumbSize)

                ZStack(alignment: .leading) {
                    // Track background
                    Capsule()
                        .fill(category.color(colorScheme).opacity(0.15))
                        .frame(height: 8)

                    // Active track
                    Capsule()
                        .fill(category.color(colorScheme))
                        .frame(width: thumbPosition + thumbSize / 2, height: 8)

                    // Tick marks
                    HStack {
                        ForEach(Array(range), id: \.self) { tick in
                            Circle()
                                .fill(
                                    tick <= value
                                        ? Color.white.opacity(0.8)
                                        : category.color(colorScheme).opacity(0.3)
                                )
                                .frame(width: 6, height: 6)
                            if tick < range.upperBound {
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, thumbSize / 2)

                    // Thumb with liquid effect
                    Circle()
                        .fill(Color.white)
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(
                            color: category.color(colorScheme).opacity(0.3),
                            radius: isDragging ? 16 : 8,
                            x: 0,
                            y: isDragging ? 4 : 2
                        )
                        .overlay {
                            Circle()
                                .fill(category.color(colorScheme))
                                .frame(width: 12, height: 12)
                        }
                        .scaleEffect(isDragging ? 1.15 : 1.0)
                        .offset(x: thumbPosition)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .updating($isDragging) { _, state, _ in
                                    state = true
                                }
                                .onChanged { gesture in
                                    let newValue = valueForPosition(
                                        gesture.location.x,
                                        in: trackWidth,
                                        thumbSize: thumbSize
                                    )
                                    if newValue != value {
                                        value = newValue
                                        HowRUHaptics.selection()
                                    }
                                }
                        )
                }
            }
            .frame(height: 32)
        }
        .padding(HowRUSpacing.md)
        .background {
            GlassCard(intensity: .subtle) { EmptyView() }
        }
        .onChange(of: value) { _, newValue in
            // Pulse emoji at endpoints
            if newValue == range.lowerBound || newValue == range.upperBound {
                if !reduceMotion {
                    withAnimation(.howruBouncy) {
                        emojiScale = 1.3
                    }
                    withAnimation(.howruBouncy.delay(0.1)) {
                        emojiScale = 1.0
                    }
                }
            }
        }
    }

    private func thumbPosition(in width: CGFloat, thumbSize: CGFloat) -> CGFloat {
        let usableWidth = width - thumbSize
        let percentage = CGFloat(value - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound)
        return usableWidth * percentage
    }

    private func valueForPosition(_ x: CGFloat, in width: CGFloat, thumbSize: CGFloat) -> Int {
        let usableWidth = width - thumbSize
        let percentage = max(0, min(1, (x - thumbSize / 2) / usableWidth))
        let exactValue = CGFloat(range.lowerBound) + percentage * CGFloat(range.upperBound - range.lowerBound)
        return Int(exactValue.rounded())
    }
}
```

### 2.5 Liquid Tab Bar

```swift
// Sources/Theme/Components/LiquidTabBar.swift

struct LiquidTabBar: View {
    @Binding var selectedTab: Int
    let tabs: [(icon: String, label: String)]

    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var animation

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs.indices, id: \.self) { index in
                let isSelected = selectedTab == index

                Button {
                    withAnimation(.howruSnappy) {
                        selectedTab = index
                    }
                    HowRUHaptics.selection()
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            if isSelected {
                                Circle()
                                    .fill(HowRUColors.coral.opacity(0.15))
                                    .frame(width: 56, height: 56)
                                    .matchedGeometryEffect(id: "tabBg", in: animation)
                            }

                            Image(systemName: isSelected ? tabs[index].icon + ".fill" : tabs[index].icon)
                                .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                                .foregroundColor(
                                    isSelected
                                        ? HowRUColors.coral
                                        : HowRUColors.textSecondary(colorScheme)
                                )
                        }
                        .frame(width: 56, height: 56)

                        Text(tabs[index].label)
                            .font(HowRUFont.caption(12))
                            .foregroundColor(
                                isSelected
                                    ? HowRUColors.textPrimary(colorScheme)
                                    : HowRUColors.textSecondary(colorScheme)
                            )
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, HowRUSpacing.md)
        .padding(.top, HowRUSpacing.sm)
        .padding(.bottom, HowRUSpacing.md)
        .background {
            // Liquid glass background
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Rectangle()
                        .fill(
                            colorScheme == .dark
                                ? Color.black.opacity(0.3)
                                : Color.white.opacity(0.7)
                        )
                }
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(HowRUColors.divider(colorScheme).opacity(0.5))
                        .frame(height: 0.5)
                }
                .ignoresSafeArea()
        }
    }
}
```

---

## 3. Screen-Specific UI Enhancements

### 3.1 Check-In Screen Flow

**Current:** Basic sliders with standard SwiftUI
**Enhanced:** Liquid glass cards with custom sliders, fluid state transitions

```
┌─────────────────────────────────────────┐
│      Animated Gradient Background       │
│                                         │
│   ┌─────────────────────────────────┐   │
│   │      Glass Card (Prompt)        │   │
│   │                                 │   │
│   │   "Good morning, Betty!"        │   │
│   │   "How are you feeling today?"  │   │
│   │                                 │   │
│   │   ┌─────────────────────────┐   │   │
│   │   │   Check In Now (FAB)    │   │   │
│   │   └─────────────────────────┘   │   │
│   │                                 │   │
│   │   🔥 7 day streak              │   │
│   │                                 │   │
│   └─────────────────────────────────┘   │
│                                         │
└─────────────────────────────────────────┘
```

**Check-In Form with Liquid Sliders:**

```
┌─────────────────────────────────────────┐
│                                         │
│   < Back                How You Feel    │
│                                         │
│   ┌─────────────────────────────────┐   │
│   │  Mind                      4    │   │
│   │  🧠━━━━━━━●━━━💡                │   │
│   │  [Liquid slider with ticks]     │   │
│   └─────────────────────────────────┘   │
│                                         │
│   ┌─────────────────────────────────┐   │
│   │  Body                      3    │   │
│   │  😴━━━━━●━━━━━💪                │   │
│   └─────────────────────────────────┘   │
│                                         │
│   ┌─────────────────────────────────┐   │
│   │  Mood                      5    │   │
│   │  😢━━━━━━━━━●😊                 │   │
│   └─────────────────────────────────┘   │
│                                         │
│   ┌─────────────────────────────────┐   │
│   │        ✓ Submit Check-In        │   │
│   └─────────────────────────────────┘   │
│                                         │
└─────────────────────────────────────────┘
```

### 3.2 Circle View Enhancement

**Hero Avatar Card:**

```swift
// Enhanced checker card with liquid glass
struct LiquidCheckerCard: View {
    let link: CircleLink
    let checkIn: CheckIn?

    var body: some View {
        GlassCard(intensity: .medium) {
            HStack(spacing: HowRUSpacing.md) {
                // Glowing avatar (existing component)
                GlowingAvatar(
                    image: profileImage,
                    name: link.checker?.name ?? "",
                    size: 64,
                    glowColor: statusColor,
                    showGlow: true
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(link.checker?.name ?? "")
                        .font(HowRUFont.headline3())

                    // Status with dot
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusLabel)
                            .font(HowRUFont.caption())
                            .foregroundColor(HowRUColors.textSecondary(colorScheme))
                    }
                }

                Spacer()

                // Scores (if checked in)
                if let checkIn = checkIn {
                    ScoreStack(checkIn: checkIn)
                }

                Image(systemName: "chevron.right")
                    .foregroundColor(HowRUColors.textSecondary(colorScheme))
            }
            .padding(HowRUSpacing.md)
        }
    }
}
```

### 3.3 Trends View Enhancement

**Animated Chart Cards:**

```swift
// Score card with animated number and breathing effect
struct TrendScoreCard: View {
    let title: String
    let score: Double
    let trend: TrendDirection
    let color: Color

    @State private var animatedScore: Double = 0

    var body: some View {
        GlassCard(intensity: .subtle) {
            VStack(spacing: HowRUSpacing.sm) {
                // Trend indicator
                HStack(spacing: 4) {
                    Image(systemName: trend.icon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(trend.label)
                        .font(HowRUFont.caption())
                }
                .foregroundColor(trend.color)

                // Animated score
                Text(String(format: "%.1f", animatedScore))
                    .font(HowRUFont.headline1(48))
                    .foregroundColor(color)
                    .contentTransition(.numericText())

                Text(title)
                    .font(HowRUFont.caption())
                    .foregroundColor(HowRUColors.textSecondary(colorScheme))
            }
            .padding(HowRUSpacing.lg)
        }
        .breathingCard(intensity: 0.015, duration: 5.0)
        .onAppear {
            withAnimation(.howruSmooth.delay(0.2)) {
                animatedScore = score
            }
        }
    }
}
```

### 3.4 Settings View Enhancement

**Grouped Glass Sections:**

```swift
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: HowRUSpacing.sm) {
            Text(title.uppercased())
                .font(HowRUFont.caption(12))
                .fontWeight(.semibold)
                .foregroundColor(HowRUColors.textSecondary(colorScheme))
                .tracking(HowRUTracking.wide)
                .padding(.horizontal, HowRUSpacing.md)

            GlassCard(intensity: .subtle) {
                VStack(spacing: 0) {
                    content()
                }
                .padding(.vertical, HowRUSpacing.xs)
            }
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String? = nil
    var showChevron: Bool = true
    var action: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: HowRUSpacing.md) {
                // Icon in colored circle
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 32, height: 32)

                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(iconColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(HowRUFont.bodyMedium())
                        .foregroundColor(HowRUColors.textPrimary(colorScheme))

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(HowRUFont.caption())
                            .foregroundColor(HowRUColors.textSecondary(colorScheme))
                    }
                }

                Spacer()

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(HowRUColors.textSecondary(colorScheme).opacity(0.5))
                }
            }
            .padding(.horizontal, HowRUSpacing.md)
            .padding(.vertical, HowRUSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

---

## 4. Animation Choreography

### 4.1 Check-In State Transitions

```swift
// State machine animation orchestration
enum CheckInTransition {
    static func prompt(to form: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    static func form(to complete: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .scale(scale: 1.1).combined(with: .opacity)
        )
    }

    static let success: AnyTransition = .scale(scale: 0.8)
        .combined(with: .opacity)
        .animation(.howruBouncy)
}

// Usage in CheckInView
Group {
    switch state {
    case .prompt:
        PromptView()
            .transition(CheckInTransition.prompt(to: false))
    case .form:
        FormView()
            .transition(CheckInTransition.form(to: false))
    case .complete:
        CompleteView()
            .transition(CheckInTransition.success)
    }
}
.animation(.howruSmooth, value: state)
```

### 4.2 Success Celebration

```swift
struct SuccessCelebration: View {
    @State private var showCheckmark = false
    @State private var ringScale: CGFloat = 0.5
    @State private var particleOpacity: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Expanding ring
            Circle()
                .stroke(HowRUColors.success(.light), lineWidth: 3)
                .frame(width: 120, height: 120)
                .scaleEffect(ringScale)
                .opacity(2 - Double(ringScale))

            // Checkmark
            if showCheckmark {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(HowRUGradients.coral)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .onAppear {
            if reduceMotion {
                showCheckmark = true
                ringScale = 1.5
            } else {
                withAnimation(.howruBouncy.delay(0.1)) {
                    showCheckmark = true
                }
                withAnimation(.easeOut(duration: 0.8)) {
                    ringScale = 1.5
                }
            }
            HowRUHaptics.success()
        }
    }
}
```

### 4.3 Micro-interactions

```swift
// Button press feedback
extension View {
    func liquidPress() -> some View {
        modifier(LiquidPressModifier())
    }
}

struct LiquidPressModifier: ViewModifier {
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .brightness(isPressed ? -0.05 : 0)
            .animation(reduceMotion ? nil : .howruSnappy, value: isPressed)
            .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                isPressed = pressing
                if pressing { HowRUHaptics.light() }
            }, perform: {})
    }
}

// Pull to refresh with custom animation
struct LiquidRefreshControl: View {
    @Binding var isRefreshing: Bool
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(HowRUColors.coral, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: 24, height: 24)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}
```

---

## 5. Accessibility Considerations

### 5.1 Reduce Motion Support

All animations must respect `accessibilityReduceMotion`:

```swift
struct ConditionalAnimation: ViewModifier {
    let animation: Animation
    let value: AnyHashable

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    func howruAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(ConditionalAnimation(animation: animation, value: AnyHashable(value)))
    }
}
```

### 5.2 VoiceOver Labels

```swift
// Example: Check-in slider
LiquidSlider(value: $moodScore, category: .mood)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Mood score")
    .accessibilityValue("\(moodScore) out of 5")
    .accessibilityAdjustableAction { direction in
        switch direction {
        case .increment:
            moodScore = min(5, moodScore + 1)
        case .decrement:
            moodScore = max(1, moodScore - 1)
        @unknown default:
            break
        }
    }
```

### 5.3 Dynamic Type Support

All text must use HowRUFont which scales appropriately:

```swift
// Ensure font scaling
Text("Check In")
    .font(HowRUFont.headline1()) // Uses .custom() which respects Dynamic Type
    .minimumScaleFactor(0.75)    // Allow shrinking if needed
    .lineLimit(2)
```

---

## 6. Implementation Checklist

### Phase 1: Core Components

- [ ] Create `GlassCard` component
- [ ] Create `LiquidButton` component
- [ ] Create `FloatingActionButton` component
- [ ] Create `LiquidSlider` component
- [ ] Create `LiquidTabBar` component

### Phase 2: Screen Updates

- [ ] Update `CheckInPromptView` with glass cards
- [ ] Update `CheckInFormView` with liquid sliders
- [ ] Update `CheckInCompleteView` with celebration animation
- [ ] Update `CircleView` with glass checker cards
- [ ] Update `TrendsView` with animated score cards
- [ ] Update `SettingsView` with glass sections

### Phase 3: Animation Polish

- [ ] Add state transition choreography
- [ ] Add micro-interaction feedback
- [ ] Add success celebrations
- [ ] Add pull-to-refresh styling
- [ ] Verify reduceMotion fallbacks

### Phase 4: Accessibility QA

- [ ] Test all VoiceOver labels
- [ ] Test Dynamic Type scaling
- [ ] Test with reduceMotion enabled
- [ ] Test contrast ratios

---

## 7. File Structure

```
Sources/Theme/
├── Theme.swift (existing - keep)
└── Components/
    ├── GlassCard.swift (new)
    ├── LiquidButton.swift (new)
    ├── FloatingActionButton.swift (new)
    ├── LiquidSlider.swift (new)
    ├── LiquidTabBar.swift (new)
    ├── SuccessCelebration.swift (new)
    └── LiquidModifiers.swift (new)
```

---

## Next Document

See existing plan at `~/.claude/plans/humming-stirring-donut.md` for implementation phases.
