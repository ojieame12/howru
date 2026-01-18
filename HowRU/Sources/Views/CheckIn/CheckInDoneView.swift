import SwiftUI

struct CheckInDoneView: View {
    let checkIn: CheckIn
    let streak: Int
    let onEdit: () -> Void
    let onViewTrends: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: checkIn.timestamp)
    }

    private var selfieExpiryText: String? {
        guard let expires = checkIn.selfieExpiresAt,
              let _ = checkIn.selfieData,
              expires > Date() else {
            return nil
        }

        let remaining = expires.timeIntervalSince(Date())
        let hours = Int(remaining / 3600)

        if hours > 0 {
            return "Expires in \(hours)h"
        } else {
            let minutes = Int(remaining / 60)
            return "Expires in \(minutes)m"
        }
    }

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            ScrollView {
                VStack(spacing: HowRUSpacing.lg) {
                    Spacer(minLength: HowRUSpacing.xxl)

                    // Success header
                    VStack(spacing: HowRUSpacing.sm) {
                        HStack(spacing: HowRUSpacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(HowRUColors.success(colorScheme))
                            Text("Checked in")
                                .font(HowRUFont.headline2())
                                .foregroundColor(HowRUColors.textPrimary(colorScheme))
                        }

                        Text(formattedTime)
                            .font(HowRUFont.caption())
                            .foregroundColor(HowRUColors.textSecondary(colorScheme))
                    }

                    // Scores card (tappable to edit)
                    Button(action: {
                        HowRUHaptics.light()
                        onEdit()
                    }) {
                        VStack(spacing: HowRUSpacing.md) {
                            HStack(spacing: HowRUSpacing.lg) {
                                ScoreDisplay(icon: "brain.head.profile", label: "Mind", score: checkIn.mentalScore, color: HowRUColors.moodMental(colorScheme))
                                ScoreDisplay(icon: "figure.walk", label: "Body", score: checkIn.bodyScore, color: HowRUColors.moodBody(colorScheme))
                                ScoreDisplay(icon: "heart.fill", label: "Mood", score: checkIn.moodScore, color: HowRUColors.moodEmotional(colorScheme))
                            }

                            HStack(spacing: HowRUSpacing.xs) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Tap to edit")
                                    .font(HowRUFont.caption())
                            }
                            .foregroundColor(HowRUColors.textSecondary(colorScheme))
                        }
                        .padding(HowRUSpacing.lg)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: HowRURadius.lg)
                                .fill(HowRUColors.surface(colorScheme))
                                .shadow(color: HowRUColors.shadow(colorScheme), radius: 8, x: 0, y: 2)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, HowRUSpacing.screenEdge)

                    // Snapshot card (if exists)
    if let expiryText = selfieExpiryText {
        SnapshotCard(
            imageData: checkIn.selfieData,
            expiresAt: checkIn.selfieExpiresAt,
            expiryText: expiryText
        )
            .padding(.horizontal, HowRUSpacing.screenEdge)
    }

                    // Trends preview card
                    Button(action: {
                        HowRUHaptics.light()
                        onViewTrends()
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: HowRUSpacing.xs) {
                                Text("Your Trends")
                                    .font(HowRUFont.bodyMedium())
                                    .foregroundColor(HowRUColors.textPrimary(colorScheme))

                                if streak > 1 {
                                    HStack(spacing: HowRUSpacing.xs) {
                                        Image(systemName: "flame.fill")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(HowRUColors.coral)
                                        Text("\(streak) day streak")
                                            .font(HowRUFont.caption())
                                            .foregroundColor(HowRUColors.textSecondary(colorScheme))
                                    }
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(HowRUColors.textSecondary(colorScheme))
                        }
                        .padding(HowRUSpacing.lg)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: HowRURadius.lg)
                                .fill(HowRUColors.surface(colorScheme))
                                .shadow(color: HowRUColors.shadow(colorScheme), radius: 8, x: 0, y: 2)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, HowRUSpacing.screenEdge)

                    Spacer(minLength: HowRUSpacing.xxl)
                }
            }
        }
    }
}

// MARK: - Score Display

private struct ScoreDisplay: View {
    let icon: String
    let label: String
    let score: Int
    let color: Color

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: HowRUSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(color)

            Text("\(score)")
                .font(HowRUFont.headline2())
                .foregroundColor(HowRUColors.textPrimary(colorScheme))

            Text(label)
                .font(HowRUFont.caption())
                .foregroundColor(HowRUColors.textSecondary(colorScheme))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Snapshot Card

private struct SnapshotCard: View {
    let imageData: Data?
    let expiresAt: Date?
    let expiryText: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: HowRUSpacing.md) {
            SnapshotThumbnail(imageData: imageData, expiresAt: expiresAt, size: 60)

            VStack(alignment: .leading, spacing: HowRUSpacing.xs) {
                Text("Snapshot added")
                    .font(HowRUFont.bodyMedium())
                    .foregroundColor(HowRUColors.textPrimary(colorScheme))

                HStack(spacing: HowRUSpacing.xs) {
                    Image(systemName: "clock")
                        .font(.system(size: 12, weight: .medium))
                    Text(expiryText)
                        .font(HowRUFont.caption())
                }
                .foregroundColor(HowRUColors.textSecondary(colorScheme))
            }

            Spacer()
        }
        .padding(HowRUSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: HowRURadius.lg)
                .fill(HowRUColors.surface(colorScheme))
                .shadow(color: HowRUColors.shadow(colorScheme), radius: 8, x: 0, y: 2)
        )
    }
}

// MARK: - Preview

#Preview("Done - With Streak") {
    let checkIn = CheckIn(
        timestamp: Date(),
        mentalScore: 4,
        bodyScore: 3,
        moodScore: 5
    )

    return CheckInDoneView(
        checkIn: checkIn,
        streak: 7,
        onEdit: { print("Edit") },
        onViewTrends: { print("View Trends") }
    )
}

#Preview("Done - No Streak") {
    let checkIn = CheckIn(
        timestamp: Date(),
        mentalScore: 3,
        bodyScore: 3,
        moodScore: 3
    )

    return CheckInDoneView(
        checkIn: checkIn,
        streak: 1,
        onEdit: { print("Edit") },
        onViewTrends: { print("View Trends") }
    )
}

#Preview("Dark Mode") {
    let checkIn = CheckIn(
        timestamp: Date(),
        mentalScore: 4,
        bodyScore: 5,
        moodScore: 4
    )

    return CheckInDoneView(
        checkIn: checkIn,
        streak: 14,
        onEdit: { print("Edit") },
        onViewTrends: { print("View Trends") }
    )
    .preferredColorScheme(.dark)
}
