import SwiftUI
import SwiftData

struct CheckInView: View {
    let user: User
    @Binding var startCheckInTrigger: Bool
    var onViewTrends: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \CheckIn.timestamp, order: .reverse)
    private var allCheckIns: [CheckIn]

    @State private var coordinator = CheckInCoordinator()

    private var userCheckIns: [CheckIn] {
        allCheckIns.filter { $0.user?.id == user.id }
    }

    var body: some View {
        Group {
            switch coordinator.state {
            case .notCheckedIn:
                CheckInPromptView(
                    streak: coordinator.currentStreak,
                    onCheckIn: {
                        withAnimation(.howruSmooth) {
                            coordinator.startCheckIn()
                        }
                    }
                )

            case .inProgress:
                CheckInFormView(
                    mentalScore: $coordinator.mentalScore,
                    bodyScore: $coordinator.bodyScore,
                    moodScore: $coordinator.moodScore,
                    isEditing: coordinator.canEditToday,
                    onSubmit: {
                        _ = coordinator.submitCheckIn(for: user, in: modelContext)
                        PokeService(modelContext: modelContext).markAllAsResponded(for: user.id)
                    },
                    onCancel: {
                        withAnimation(.howruSmooth) {
                            coordinator.cancelCheckIn()
                        }
                    }
                )
                .transition(.howruPush)

            case .complete(let checkIn):
                CheckInCompleteView(
                    checkIn: checkIn,
                    onAddSnapshot: {
                        withAnimation(.howruSmooth) {
                            coordinator.startAddingSnapshot()
                        }
                    },
                    onFinish: {
                        withAnimation(.howruSmooth) {
                            coordinator.finishCheckIn()
                        }
                    }
                )
                .transition(.howruScaleUp)

            case .addingSnapshot:
                SnapshotCaptureView(
                    onCapture: { imageData in
                        withAnimation(.howruSmooth) {
                            coordinator.previewSnapshot(imageData: imageData)
                        }
                    },
                    onCancel: {
                        withAnimation(.howruSmooth) {
                            coordinator.skipSnapshot()
                        }
                    }
                )
                .transition(.howruPush)

            case .previewSnapshot(_, let imageData):
                SnapshotPreviewView(
                    imageData: imageData,
                    onConfirm: {
                        withAnimation(.howruSmooth) {
                            coordinator.confirmSnapshot(in: modelContext)
                        }
                    },
                    onRetake: {
                        withAnimation(.howruSmooth) {
                            coordinator.retakeSnapshot()
                        }
                    }
                )
                .transition(.howruPush)

            case .done(let checkIn):
                CheckInDoneView(
                    checkIn: checkIn,
                    streak: coordinator.currentStreak,
                    onEdit: {
                        withAnimation(.howruSmooth) {
                            coordinator.editCheckIn()
                        }
                    },
                    onViewTrends: {
                        onViewTrends()
                    }
                )
            }
        }
        .animation(.howruSmooth, value: coordinator.state)
        .onAppear {
            coordinator.checkTodaysStatus(for: user, checkIns: userCheckIns)
            SnapshotService(modelContext: modelContext).cleanupExpiredSnapshots()
        }
        .onChange(of: startCheckInTrigger) { _, shouldStart in
            guard shouldStart else { return }
            if coordinator.state != .inProgress {
                withAnimation(.howruSmooth) {
                    coordinator.startCheckIn()
                }
            }
            startCheckInTrigger = false
        }
        .onChange(of: userCheckIns.count) { _, _ in
            // Refresh state if check-ins change externally
            coordinator.checkTodaysStatus(for: user, checkIns: userCheckIns)
        }
    }
}

// MARK: - Preview

#Preview("Not Checked In") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: User.self, CheckIn.self, Schedule.self, CircleLink.self, Poke.self, AlertEvent.self, configurations: config)

    let user = User(phoneNumber: "+1234567890", name: "Test User")
    container.mainContext.insert(user)

    return CheckInView(user: user, startCheckInTrigger: .constant(false))
        .modelContainer(container)
}

#Preview("With Streak") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: User.self, CheckIn.self, Schedule.self, CircleLink.self, Poke.self, AlertEvent.self, configurations: config)

    let user = User(phoneNumber: "+1234567890", name: "Test User")
    container.mainContext.insert(user)

    // Add some historical check-ins for streak
    let calendar = Calendar.current
    for dayOffset in 0..<7 {
        if let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) {
            // Skip today (dayOffset 0) to show "not checked in" state
            if dayOffset > 0 {
                let checkIn = CheckIn(
                    user: user,
                    timestamp: date,
                    mentalScore: Int.random(in: 3...5),
                    bodyScore: Int.random(in: 3...5),
                    moodScore: Int.random(in: 3...5)
                )
                container.mainContext.insert(checkIn)
            }
        }
    }

    return CheckInView(user: user, startCheckInTrigger: .constant(false))
        .modelContainer(container)
}

#Preview("Already Checked In") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: User.self, CheckIn.self, Schedule.self, CircleLink.self, Poke.self, AlertEvent.self, configurations: config)

    let user = User(phoneNumber: "+1234567890", name: "Test User")
    container.mainContext.insert(user)

    // Add today's check-in
    let checkIn = CheckIn(
        user: user,
        timestamp: Date(),
        mentalScore: 4,
        bodyScore: 3,
        moodScore: 5
    )
    container.mainContext.insert(checkIn)

    return CheckInView(user: user, startCheckInTrigger: .constant(false))
        .modelContainer(container)
}

#Preview("Dark Mode") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: User.self, CheckIn.self, Schedule.self, CircleLink.self, Poke.self, AlertEvent.self, configurations: config)

    let user = User(phoneNumber: "+1234567890", name: "Test User")
    container.mainContext.insert(user)

    return CheckInView(user: user, startCheckInTrigger: .constant(false))
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
