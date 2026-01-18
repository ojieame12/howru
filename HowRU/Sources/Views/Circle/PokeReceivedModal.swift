import SwiftUI
import SwiftData

/// Modal shown when a checker receives a poke from a supporter
struct PokeReceivedModal: View {
    let poke: Poke
    let onCheckIn: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    @State private var isVisible = false

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissModal()
                }

            // Modal card
            VStack(spacing: HowRUSpacing.lg) {
                // Poke icon with animation
                ZStack {
                    Circle()
                        .fill(HowRUColors.coral.opacity(0.2))
                        .frame(width: 80, height: 80)
                        .scaleEffect(isVisible ? 1.0 : 0.5)

                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundColor(HowRUColors.coral)
                        .scaleEffect(isVisible ? 1.0 : 0.5)
                }
                .animation(.howruBouncy.delay(0.1), value: isVisible)

                // Header
                VStack(spacing: HowRUSpacing.sm) {
                    Text("\(poke.fromName) poked you")
                        .font(HowRUFont.headline2())
                        .foregroundColor(HowRUColors.textPrimary(colorScheme))

                    Text(timeAgoText)
                        .font(HowRUFont.caption())
                        .foregroundColor(HowRUColors.textSecondary(colorScheme))
                }

                // Message (if any)
                if let message = poke.message, !message.isEmpty {
                    VStack(spacing: HowRUSpacing.xs) {
                        Image(systemName: "quote.opening")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(HowRUColors.textSecondary(colorScheme))

                        Text(message)
                            .font(HowRUFont.body())
                            .foregroundColor(HowRUColors.textPrimary(colorScheme))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, HowRUSpacing.md)
                    }
                    .padding(HowRUSpacing.md)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: HowRURadius.md)
                            .fill(HowRUColors.divider(colorScheme).opacity(0.5))
                    )
                }

                // Actions
                VStack(spacing: HowRUSpacing.sm) {
                    Button(action: {
                        HowRUHaptics.medium()
                        markAsSeen()
                        onCheckIn()
                    }) {
                        HStack(spacing: HowRUSpacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .medium))
                            Text("Check In Now")
                        }
                    }
                    .buttonStyle(HowRUPrimaryButtonStyle())

                    Button(action: {
                        dismissModal()
                    }) {
                        Text("Later")
                    }
                    .buttonStyle(HowRUSecondaryButtonStyle())
                }
            }
            .padding(HowRUSpacing.xl)
            .background(
                RoundedRectangle(cornerRadius: HowRURadius.xl)
                    .fill(HowRUColors.surface(colorScheme))
                    .shadow(color: HowRUColors.shadow(colorScheme).opacity(0.3), radius: 24, x: 0, y: 8)
            )
            .padding(.horizontal, HowRUSpacing.xl)
            .scaleEffect(isVisible ? 1.0 : 0.9)
            .opacity(isVisible ? 1.0 : 0.0)
        }
        .onAppear {
            withAnimation(.howruSmooth) {
                isVisible = true
            }
        }
    }

    // MARK: - Helpers

    private var timeAgoText: String {
        let interval = Date().timeIntervalSince(poke.sentAt)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            return poke.sentAt.formatted(date: .abbreviated, time: .shortened)
        }
    }

    private func markAsSeen() {
        poke.seenAt = Date()
    }

    private func dismissModal() {
        markAsSeen()
        withAnimation(.howruSmooth) {
            isVisible = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
}

// MARK: - Preview

#Preview("Poke Received - With Message") {
    let poke = Poke(
        fromSupporterId: UUID(),
        fromName: "Sarah",
        toCheckerId: UUID(),
        message: "Hope you're doing well today! Just wanted to check on you."
    )

    return PokeReceivedModal(
        poke: poke,
        onCheckIn: { print("Check in tapped") },
        onDismiss: { print("Dismissed") }
    )
}

#Preview("Poke Received - No Message") {
    let poke = Poke(
        fromSupporterId: UUID(),
        fromName: "Mike",
        toCheckerId: UUID(),
        message: nil
    )

    return PokeReceivedModal(
        poke: poke,
        onCheckIn: { print("Check in tapped") },
        onDismiss: { print("Dismissed") }
    )
}

#Preview("Poke Received - Dark") {
    let poke = Poke(
        fromSupporterId: UUID(),
        fromName: "Grandma Betty",
        toCheckerId: UUID(),
        message: "Thinking of you"
    )

    return PokeReceivedModal(
        poke: poke,
        onCheckIn: { print("Check in tapped") },
        onDismiss: { print("Dismissed") }
    )
    .preferredColorScheme(.dark)
}
