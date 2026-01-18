import SwiftUI

struct CheckInPromptView: View {
    let streak: Int
    let onCheckIn: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        case 17..<22:
            return "Good evening"
        default:
            return "Hey there"
        }
    }

    private var greetingIcon: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "sun.max.fill"
        case 12..<17:
            return "sun.min.fill"
        case 17..<22:
            return "moon.fill"
        default:
            return "sparkles"
        }
    }

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            VStack(spacing: HowRUSpacing.xl) {
                Spacer()

                // Greeting
                VStack(spacing: HowRUSpacing.sm) {
                    HStack(spacing: HowRUSpacing.sm) {
                        Text(greeting)
                            .font(HowRUFont.headline1())
                            .foregroundColor(HowRUColors.textPrimary(colorScheme))

                        Image(systemName: greetingIcon)
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(HowRUColors.warning(colorScheme))
                            .accessibilityHidden(true)
                    }
                    .multilineTextAlignment(.center)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(greeting)

                    // Streak badge (only show if > 1)
                    if streak > 1 {
                        StreakBadge(streak: streak)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                Spacer()

                // Check In button
                Button(action: {
                    HowRUHaptics.light()
                    onCheckIn()
                }) {
                    Text("Check In")
                }
                .buttonStyle(HowRUCoralButtonStyle())
                .padding(.horizontal, HowRUSpacing.screenEdge)
                .padding(.bottom, HowRUSpacing.xxl)
                .accessibilityLabel("Check In")
                .accessibilityHint("Double tap to start your daily wellness check-in")
            }
        }
    }
}

// MARK: - Streak Badge

private struct StreakBadge: View {
    let streak: Int

    @Environment(\.colorScheme) private var colorScheme
    @State private var hasAppeared = false

    var body: some View {
        HStack(spacing: HowRUSpacing.xs) {
            Image(systemName: "flame.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(HowRUColors.coral)
                .accessibilityHidden(true)
            Text("\(streak) day streak")
                .font(HowRUFont.bodyMedium())
                .foregroundColor(HowRUColors.coral)
        }
        .padding(.horizontal, HowRUSpacing.md)
        .padding(.vertical, HowRUSpacing.sm)
        .background(
            Capsule()
                .fill(HowRUColors.coralGlow(colorScheme))
        )
        .scaleEffect(hasAppeared ? 1 : 0.8)
        .opacity(hasAppeared ? 1 : 0)
        .onAppear {
            withAnimation(.howruBouncy.delay(0.2)) {
                hasAppeared = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You're on a \(streak) day check-in streak")
    }
}

// MARK: - Preview

#Preview("Morning") {
    CheckInPromptView(streak: 7) {
        print("Check in tapped")
    }
}

#Preview("No Streak") {
    CheckInPromptView(streak: 0) {
        print("Check in tapped")
    }
}

#Preview("Dark Mode") {
    CheckInPromptView(streak: 14) {
        print("Check in tapped")
    }
    .preferredColorScheme(.dark)
}
