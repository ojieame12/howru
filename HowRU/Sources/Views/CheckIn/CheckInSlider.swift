import SwiftUI

// MARK: - Check-In Category

enum CheckInCategory: CaseIterable {
    case mind
    case body
    case mood

    var icon: String {
        switch self {
        case .mind: return "brain.head.profile"
        case .body: return "figure.walk"
        case .mood: return "heart.fill"
        }
    }

    var label: String {
        switch self {
        case .mind: return "Mind"
        case .body: return "Body"
        case .mood: return "Mood"
        }
    }

    var lowIcon: String {
        switch self {
        case .mind: return "cloud.fog"
        case .body: return "bed.double"
        case .mood: return "cloud.rain"
        }
    }

    var highIcon: String {
        switch self {
        case .mind: return "sparkles"
        case .body: return "bolt.fill"
        case .mood: return "sun.max.fill"
        }
    }

    func color(_ scheme: ColorScheme) -> Color {
        switch self {
        case .mind: return HowRUColors.moodMental(scheme)
        case .body: return HowRUColors.moodBody(scheme)
        case .mood: return HowRUColors.moodEmotional(scheme)
        }
    }
}

// MARK: - Check-In Slider

struct CheckInSlider: View {
    let category: CheckInCategory
    @Binding var value: Int

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var lowEmojiScale: CGFloat = 1.0
    @State private var highEmojiScale: CGFloat = 1.0
    @GestureState private var isDragging = false

    private let thumbSize: CGFloat = 28
    private let trackHeight: CGFloat = 4
    private let iconSize: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: HowRUSpacing.sm) {
            // Label
            HStack(spacing: HowRUSpacing.xs) {
                Image(systemName: category.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(category.color(colorScheme))
                Text(category.label)
                    .font(HowRUFont.bodyMedium())
                    .foregroundColor(HowRUColors.textPrimary(colorScheme))
            }

            // Slider
            HStack(spacing: HowRUSpacing.md) {
                // Low icon
                Image(systemName: category.lowIcon)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundColor(HowRUColors.textSecondary(colorScheme))
                    .scaleEffect(lowEmojiScale)

                // Custom track
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background track
                        Capsule()
                            .fill(HowRUColors.divider(colorScheme))
                            .frame(height: trackHeight)

                        // Active track
                        Capsule()
                            .fill(category.color(colorScheme))
                            .frame(width: thumbPosition(in: geometry.size.width) + thumbSize / 2, height: trackHeight)

                        // Thumb
                        Circle()
                            .fill(HowRUColors.surface(colorScheme))
                            .frame(width: thumbSize, height: thumbSize)
                            .shadow(color: HowRUColors.shadow(colorScheme), radius: 4, x: 0, y: 2)
                            .overlay(
                                Circle()
                                    .stroke(category.color(colorScheme).opacity(0.3), lineWidth: 2)
                            )
                            .offset(x: thumbPosition(in: geometry.size.width))
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .updating($isDragging) { _, state, _ in
                                        state = true
                                    }
                                    .onChanged { gesture in
                                        let newValue = valueFromPosition(gesture.location.x, width: geometry.size.width)
                                        if newValue != value {
                                            value = newValue
                                            HowRUHaptics.selection()
                                            triggerEmojiPulse(for: newValue)
                                        }
                                    }
                            )
                            .animation(.howruInteractive, value: value)
                    }
                    .frame(height: thumbSize)
                }
                .frame(height: thumbSize)

                // High icon
                Image(systemName: category.highIcon)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundColor(category.color(colorScheme))
                    .scaleEffect(highEmojiScale)
            }
        }
        .padding(HowRUSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: HowRURadius.lg)
                .fill(HowRUColors.surface(colorScheme))
                .shadow(color: HowRUColors.shadow(colorScheme), radius: 8, x: 0, y: 2)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.label) score")
        .accessibilityValue("\(value) out of 5")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                if value < 5 {
                    value += 1
                    HowRUHaptics.selection()
                }
            case .decrement:
                if value > 1 {
                    value -= 1
                    HowRUHaptics.selection()
                }
            @unknown default:
                break
            }
        }
    }

    // MARK: - Position Calculations

    private func thumbPosition(in width: CGFloat) -> CGFloat {
        let usableWidth = width - thumbSize
        let normalizedValue = CGFloat(value - 1) / 4.0 // 1-5 -> 0-1
        return normalizedValue * usableWidth
    }

    private func valueFromPosition(_ x: CGFloat, width: CGFloat) -> Int {
        let usableWidth = width - thumbSize
        let clampedX = max(0, min(x - thumbSize / 2, usableWidth))
        let normalizedValue = clampedX / usableWidth
        let rawValue = Int(round(normalizedValue * 4)) + 1 // 0-1 -> 1-5
        return max(1, min(5, rawValue))
    }

    // MARK: - Emoji Pulse Animation

    private func triggerEmojiPulse(for newValue: Int) {
        guard !reduceMotion else { return }

        if newValue == 1 {
            withAnimation(.howruBouncy) {
                lowEmojiScale = 1.3
            }
            withAnimation(.howruBouncy.delay(0.1)) {
                lowEmojiScale = 1.0
            }
        } else if newValue == 5 {
            withAnimation(.howruBouncy) {
                highEmojiScale = 1.3
            }
            withAnimation(.howruBouncy.delay(0.1)) {
                highEmojiScale = 1.0
            }
        }
    }
}

// MARK: - Preview

#Preview("Check-In Sliders") {
    @Previewable @State var mind = 3
    @Previewable @State var bodyScore = 3
    @Previewable @State var mood = 3

    ZStack {
        WarmBackground()

        VStack(spacing: HowRUSpacing.md) {
            CheckInSlider(category: .mind, value: $mind)
            CheckInSlider(category: .body, value: $bodyScore)
            CheckInSlider(category: .mood, value: $mood)

            Text("Mind: \(mind), Body: \(bodyScore), Mood: \(mood)")
                .font(HowRUFont.caption())
                .foregroundColor(.secondary)
        }
        .padding(HowRUSpacing.screenEdge)
    }
}

#Preview("Dark Mode") {
    @Previewable @State var value = 4

    ZStack {
        WarmBackground()
        CheckInSlider(category: .mood, value: $value)
            .padding(HowRUSpacing.screenEdge)
    }
    .preferredColorScheme(.dark)
}
