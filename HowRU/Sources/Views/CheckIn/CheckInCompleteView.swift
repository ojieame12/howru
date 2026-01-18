import SwiftUI

struct CheckInCompleteView: View {
    let checkIn: CheckIn
    let onAddSnapshot: () -> Void
    let onFinish: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var showCheckmark = false
    @State private var showScores = false
    @State private var showButtons = false

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            VStack(spacing: HowRUSpacing.xl) {
                Spacer()

                // Success checkmark
                VStack(spacing: HowRUSpacing.md) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64, weight: .medium))
                        .foregroundColor(HowRUColors.success(colorScheme))
                        .scaleEffect(showCheckmark ? 1 : 0)
                        .opacity(showCheckmark ? 1 : 0)

                    Text("All done")
                        .font(HowRUFont.headline1())
                        .foregroundColor(HowRUColors.textPrimary(colorScheme))
                        .opacity(showCheckmark ? 1 : 0)
                }

                // Score summary
                HStack(spacing: HowRUSpacing.lg) {
                    ScorePill(icon: "brain.head.profile", score: checkIn.mentalScore, color: HowRUColors.moodMental(colorScheme))
                    ScorePill(icon: "figure.walk", score: checkIn.bodyScore, color: HowRUColors.moodBody(colorScheme))
                    ScorePill(icon: "heart.fill", score: checkIn.moodScore, color: HowRUColors.moodEmotional(colorScheme))
                }
                .opacity(showScores ? 1 : 0)
                .offset(y: showScores ? 0 : 10)

                Spacer()

                // Buttons
                VStack(spacing: HowRUSpacing.md) {
                    // Add snapshot button (secondary)
                    Button(action: {
                        HowRUHaptics.light()
                        onAddSnapshot()
                    }) {
                        HStack(spacing: HowRUSpacing.sm) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 16, weight: .medium))
                            Text("Add a snapshot")
                        }
                    }
                    .buttonStyle(HowRUSecondaryButtonStyle())

                    // Finish button (primary)
                    Button(action: {
                        HowRUHaptics.light()
                        onFinish()
                    }) {
                        Text("Finish")
                    }
                    .buttonStyle(HowRUPrimaryButtonStyle())
                }
                .padding(.horizontal, HowRUSpacing.screenEdge)
                .padding(.bottom, HowRUSpacing.lg)
                .opacity(showButtons ? 1 : 0)
                .offset(y: showButtons ? 0 : 20)
            }
        }
        .onAppear {
            animateIn()
        }
    }

    private func animateIn() {
        // Trigger success haptic
        HowRUHaptics.success()

        // Animate checkmark
        withAnimation(.howruBouncy) {
            showCheckmark = true
        }

        // Animate scores with delay
        withAnimation(.howruSmooth.delay(0.2)) {
            showScores = true
        }

        // Animate buttons with delay
        withAnimation(.howruSmooth.delay(0.4)) {
            showButtons = true
        }
    }
}

// MARK: - Score Pill

private struct ScorePill: View {
    let icon: String
    let score: Int
    let color: Color

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: HowRUSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(color)

            Text("\(score)")
                .font(HowRUFont.bodyMedium())
                .foregroundColor(HowRUColors.textPrimary(colorScheme))
        }
        .padding(.horizontal, HowRUSpacing.md)
        .padding(.vertical, HowRUSpacing.sm)
        .background(
            Capsule()
                .fill(HowRUColors.surface(colorScheme))
                .shadow(color: HowRUColors.shadow(colorScheme), radius: 4, x: 0, y: 2)
        )
    }
}

// MARK: - Preview

#Preview("Complete") {
    let checkIn = CheckIn(
        mentalScore: 4,
        bodyScore: 3,
        moodScore: 5
    )

    return CheckInCompleteView(
        checkIn: checkIn,
        onAddSnapshot: { print("Add snapshot") },
        onFinish: { print("Finish") }
    )
}

#Preview("Dark Mode") {
    let checkIn = CheckIn(
        mentalScore: 2,
        bodyScore: 4,
        moodScore: 3
    )

    return CheckInCompleteView(
        checkIn: checkIn,
        onAddSnapshot: { print("Add snapshot") },
        onFinish: { print("Finish") }
    )
    .preferredColorScheme(.dark)
}
