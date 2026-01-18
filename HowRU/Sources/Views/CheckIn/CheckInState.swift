import SwiftUI
import SwiftData

// MARK: - Check-In State

enum CheckInState: Equatable {
    case notCheckedIn
    case inProgress
    case complete(CheckIn)
    case addingSnapshot(CheckIn)
    case previewSnapshot(CheckIn, Data) // Data is the image data
    case done(CheckIn)

    static func == (lhs: CheckInState, rhs: CheckInState) -> Bool {
        switch (lhs, rhs) {
        case (.notCheckedIn, .notCheckedIn):
            return true
        case (.inProgress, .inProgress):
            return true
        case (.complete(let a), .complete(let b)):
            return a.id == b.id
        case (.addingSnapshot(let a), .addingSnapshot(let b)):
            return a.id == b.id
        case (.previewSnapshot(let a, _), .previewSnapshot(let b, _)):
            return a.id == b.id
        case (.done(let a), .done(let b)):
            return a.id == b.id
        default:
            return false
        }
    }
}

// MARK: - Check-In Coordinator

@MainActor
@Observable
final class CheckInCoordinator {
    var state: CheckInState = .notCheckedIn

    private(set) var currentStreak: Int = 0
    private(set) var todaysCheckIn: CheckIn?

    // Form values (preserved during flow)
    var mentalScore: Int = 3
    var bodyScore: Int = 3
    var moodScore: Int = 3

    // MARK: - Initialization

    func checkTodaysStatus(for user: User, checkIns: [CheckIn]) {
        // Find today's check-in for this user
        let userCheckIns = checkIns.filter { $0.user?.id == user.id }
        let calendar = Calendar.current

        todaysCheckIn = userCheckIns.first { checkIn in
            calendar.isDateInToday(checkIn.timestamp)
        }

        // Calculate streak
        currentStreak = calculateStreak(from: userCheckIns)

        // Set state based on whether user has checked in today
        if let existingCheckIn = todaysCheckIn {
            state = .done(existingCheckIn)
            // Load existing values for potential editing
            mentalScore = existingCheckIn.mentalScore
            bodyScore = existingCheckIn.bodyScore
            moodScore = existingCheckIn.moodScore
        } else {
            state = .notCheckedIn
            // Reset to defaults
            mentalScore = 3
            bodyScore = 3
            moodScore = 3
        }
    }

    // MARK: - State Transitions

    func startCheckIn() {
        state = .inProgress
    }

    func cancelCheckIn() {
        if todaysCheckIn != nil {
            state = .done(todaysCheckIn!)
        } else {
            state = .notCheckedIn
        }
    }

    func submitCheckIn(for user: User, in context: ModelContext) -> CheckIn {
        let checkIn: CheckIn
        let isNewCheckIn: Bool

        if let existing = todaysCheckIn {
            // Update existing check-in
            existing.mentalScore = mentalScore
            existing.bodyScore = bodyScore
            existing.moodScore = moodScore
            // Mark as modified if it was already synced
            if existing.syncStatus == .synced {
                existing.syncStatus = .modified
            }
            checkIn = existing
            isNewCheckIn = false
        } else {
            // Create new check-in
            checkIn = CheckIn(
                user: user,
                timestamp: Date(),
                mentalScore: mentalScore,
                bodyScore: bodyScore,
                moodScore: moodScore,
                isManualCheckIn: true,
                syncStatus: .new
            )
            context.insert(checkIn)
            todaysCheckIn = checkIn
            isNewCheckIn = true
        }

        // Update user's last active time
        user.lastActiveAt = Date()

        // Trigger success haptic
        HowRUHaptics.success()

        // Move to complete state
        state = .complete(checkIn)

        // Queue for sync if authenticated
        if AuthManager.shared.isAuthenticated {
            Task {
                let syncService = CheckInSyncService()
                _ = await syncService.uploadCheckIn(checkIn, modelContext: context)
            }
        }

        return checkIn
    }

    func startAddingSnapshot() {
        guard case .complete(let checkIn) = state else { return }
        state = .addingSnapshot(checkIn)
    }

    func previewSnapshot(imageData: Data) {
        guard case .addingSnapshot(let checkIn) = state else { return }
        state = .previewSnapshot(checkIn, imageData)
    }

    func confirmSnapshot(in context: ModelContext) {
        guard case .previewSnapshot(let checkIn, let imageData) = state else { return }

        // Save snapshot to check-in
        let snapshotService = SnapshotService(modelContext: context)
        if snapshotService.saveSnapshot(imageData: imageData, to: checkIn) {
            HowRUHaptics.success()
        } else {
            HowRUHaptics.error()
        }
        state = .done(checkIn)
    }

    func retakeSnapshot() {
        guard case .previewSnapshot(let checkIn, _) = state else { return }
        state = .addingSnapshot(checkIn)
    }

    func skipSnapshot() {
        guard case .complete(let checkIn) = state else {
            if case .addingSnapshot(let checkIn) = state {
                state = .done(checkIn)
                return
            }
            if case .previewSnapshot(let checkIn, _) = state {
                state = .done(checkIn)
                return
            }
            return
        }
        state = .done(checkIn)
    }

    func finishCheckIn() {
        guard case .complete(let checkIn) = state else { return }
        state = .done(checkIn)
    }

    func editCheckIn() {
        guard case .done = state else { return }
        state = .inProgress
    }

    // MARK: - Streak Calculation

    private func calculateStreak(from checkIns: [CheckIn]) -> Int {
        guard !checkIns.isEmpty else { return 0 }

        let calendar = Calendar.current
        let sortedCheckIns = checkIns.sorted { $0.timestamp > $1.timestamp }

        var streak = 0
        var expectedDate = calendar.startOfDay(for: Date())

        for checkIn in sortedCheckIns {
            let checkInDay = calendar.startOfDay(for: checkIn.timestamp)

            if checkInDay == expectedDate {
                streak += 1
                expectedDate = calendar.date(byAdding: .day, value: -1, to: expectedDate) ?? expectedDate
            } else if checkInDay < expectedDate {
                // Gap in check-ins - streak broken
                break
            }
            // If checkInDay > expectedDate, skip (multiple check-ins same day)
        }

        return streak
    }
}

// MARK: - Helper Extensions

extension CheckInCoordinator {
    /// Returns true if the user can still edit today's check-in
    var canEditToday: Bool {
        todaysCheckIn != nil
    }

    /// Returns the time of today's check-in, if any
    var checkInTime: Date? {
        todaysCheckIn?.timestamp
    }

    /// Returns true if today's check-in has a valid (non-expired) selfie
    var hasSelfie: Bool {
        guard let checkIn = todaysCheckIn,
              let data = checkIn.selfieData,
              let expires = checkIn.selfieExpiresAt else {
            return false
        }
        return !data.isEmpty && expires > Date()
    }

    /// Returns the selfie expiry time remaining
    var selfieExpiresIn: TimeInterval? {
        guard let expires = todaysCheckIn?.selfieExpiresAt else { return nil }
        let remaining = expires.timeIntervalSince(Date())
        return remaining > 0 ? remaining : nil
    }
}
