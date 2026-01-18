import SwiftUI
import SwiftData

/// View shown to supporters when they receive an alert about a checker
struct AlertReceivedView: View {
    let alertEvent: AlertEvent
    let checkerName: String
    let onPoke: () -> Void
    let onCall: (() -> Void)?
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isVisible = false

    private var alertTypeInfo: (icon: String, title: String, color: Color) {
        switch alertEvent.level {
        case .reminder:
            return ("bell.fill", "Reminder", HowRUColors.warning(colorScheme))
        case .softAlert:
            return ("exclamationmark.circle.fill", "Check-In Missed", HowRUColors.warning(colorScheme))
        case .hardAlert:
            return ("exclamationmark.triangle.fill", "Needs Attention", HowRUColors.error(colorScheme))
        case .escalation:
            return ("exclamationmark.octagon.fill", "Urgent", HowRUColors.error(colorScheme))
        }
    }

    private var timeSinceText: String {
        let interval = Date().timeIntervalSince(alertEvent.triggeredAt)
        let hours = Int(interval / 3600)

        if hours < 1 {
            let minutes = max(1, Int(interval / 60))
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if hours < 24 {
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = hours / 24
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissAlert()
                }

            // Alert card
            VStack(spacing: HowRUSpacing.lg) {
                // Icon
                ZStack {
                    Circle()
                        .fill(alertTypeInfo.color.opacity(0.2))
                        .frame(width: 80, height: 80)

                    Image(systemName: alertTypeInfo.icon)
                        .font(.system(size: 36, weight: .medium))
                        .foregroundColor(alertTypeInfo.color)
                }
                .scaleEffect(isVisible ? 1.0 : 0.5)
                .animation(.howruBouncy.delay(0.1), value: isVisible)

                // Header
                VStack(spacing: HowRUSpacing.sm) {
                    Text(alertTypeInfo.title)
                        .font(HowRUFont.headline2())
                        .foregroundColor(HowRUColors.textPrimary(colorScheme))

                    Text("\(checkerName) hasn't checked in")
                        .font(HowRUFont.body())
                        .foregroundColor(HowRUColors.textPrimary(colorScheme))

                    Text(timeSinceText)
                        .font(HowRUFont.caption())
                        .foregroundColor(HowRUColors.textSecondary(colorScheme))
                }

                // Urgency message
                if alertEvent.level == .hardAlert || alertEvent.level == .escalation {
                    HStack(spacing: HowRUSpacing.sm) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                        Text("Consider reaching out directly")
                            .font(HowRUFont.caption())
                    }
                    .foregroundColor(alertTypeInfo.color)
                    .padding(.horizontal, HowRUSpacing.md)
                    .padding(.vertical, HowRUSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: HowRURadius.sm)
                            .fill(alertTypeInfo.color.opacity(0.1))
                    )
                }

                // Actions
                VStack(spacing: HowRUSpacing.sm) {
                    // Primary action - Poke
                    Button(action: {
                        HowRUHaptics.medium()
                        onPoke()
                    }) {
                        HStack(spacing: HowRUSpacing.sm) {
                            Image(systemName: "hand.tap.fill")
                                .font(.system(size: 18, weight: .medium))
                            Text("Send a Poke")
                        }
                    }
                    .buttonStyle(HowRUPrimaryButtonStyle())
                    .accessibilityLabel("Send a poke to \(checkerName)")
                    .accessibilityHint("Double tap to send a gentle reminder")

                    // Secondary actions
                    HStack(spacing: HowRUSpacing.md) {
                        if let onCall = onCall {
                            Button(action: {
                                HowRUHaptics.light()
                                onCall()
                            }) {
                                HStack(spacing: HowRUSpacing.sm) {
                                    Image(systemName: "phone.fill")
                                        .font(.system(size: 16, weight: .medium))
                                    Text("Call")
                                }
                            }
                            .buttonStyle(HowRUSecondaryButtonStyle())
                            .accessibilityLabel("Call \(checkerName)")
                            .accessibilityHint("Double tap to start a phone call")
                        }

                        Button(action: {
                            dismissAlert()
                        }) {
                            Text("Later")
                        }
                        .buttonStyle(HowRUSecondaryButtonStyle())
                        .accessibilityLabel("Dismiss alert")
                        .accessibilityHint("Double tap to close this alert")
                    }
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
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(alertTypeInfo.title) alert for \(checkerName). \(checkerName) hasn't checked in \(timeSinceText)")
        }
        .onAppear {
            withAnimation(.howruSmooth) {
                isVisible = true
            }
        }
    }

    private func dismissAlert() {
        withAnimation(.howruSmooth) {
            isVisible = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
}

// MARK: - Alert Banner (Non-modal)

/// Compact alert banner for inline display
struct AlertBanner: View {
    let alertEvent: AlertEvent
    let checkerName: String
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var alertColor: Color {
        switch alertEvent.level {
        case .reminder, .softAlert:
            return HowRUColors.warning(colorScheme)
        case .hardAlert, .escalation:
            return HowRUColors.error(colorScheme)
        }
    }

    var body: some View {
        Button(action: {
            HowRUHaptics.light()
            onTap()
        }) {
            HStack(spacing: HowRUSpacing.md) {
                // Icon
                Image(systemName: alertEvent.level == .escalation ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(alertColor)
                    .accessibilityHidden(true)

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(checkerName) hasn't checked in")
                        .font(HowRUFont.bodyMedium())
                        .foregroundColor(HowRUColors.textPrimary(colorScheme))

                    Text("Tap to see options")
                        .font(HowRUFont.caption())
                        .foregroundColor(HowRUColors.textSecondary(colorScheme))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(HowRUColors.textSecondary(colorScheme))
                    .accessibilityHidden(true)
            }
            .padding(HowRUSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: HowRURadius.lg)
                    .fill(alertColor.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: HowRURadius.lg)
                            .stroke(alertColor.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Alert: \(checkerName) hasn't checked in")
        .accessibilityHint("Double tap to see response options")
    }
}

// MARK: - Preview

#Preview("Alert Received - Soft") {
    let alert = AlertEvent(
        checkerId: UUID(),
        checkerName: "Grandma Betty",
        level: .softAlert
    )

    return AlertReceivedView(
        alertEvent: alert,
        checkerName: "Grandma Betty",
        onPoke: { print("Poke") },
        onCall: { print("Call") },
        onDismiss: { print("Dismiss") }
    )
}

#Preview("Alert Received - Hard") {
    let alert = AlertEvent(
        checkerId: UUID(),
        checkerName: "Grandpa Joe",
        level: .hardAlert
    )

    return AlertReceivedView(
        alertEvent: alert,
        checkerName: "Grandpa Joe",
        onPoke: { print("Poke") },
        onCall: { print("Call") },
        onDismiss: { print("Dismiss") }
    )
}

#Preview("Alert Banner") {
    let alert = AlertEvent(
        checkerId: UUID(),
        checkerName: "Mom",
        level: .softAlert
    )

    return AlertBanner(
        alertEvent: alert,
        checkerName: "Mom",
        onTap: { print("Tapped") }
    )
    .padding()
}
