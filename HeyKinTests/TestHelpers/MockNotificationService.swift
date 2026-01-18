import Foundation
@testable import HowRU

/// Mock notification service that records calls for verification
/// Note: Since NotificationService is final, this is a standalone mock.
/// For AlertService tests that need to verify notifications, we track calls
/// made to the real NotificationService by using this as a spy/recorder.
@MainActor
final class MockNotificationService {
    // Track all scheduled notifications
    private(set) var scheduledReminders: [(date: Date, userName: String)] = []
    private(set) var scheduledSoftAlerts: [(checkerName: String, delayMinutes: Int)] = []
    private(set) var scheduledHardAlerts: [(checkerName: String, missedHours: Int)] = []
    private(set) var scheduledPokes: [(fromName: String, message: String?)] = []

    // Track cancellations
    private(set) var cancelledNotificationIds: [String] = []
    private(set) var cancelAllCalled = false

    // Stub authorization status
    var isAuthorized: Bool = true
    var authorizationDenied: Bool = false

    func scheduleCheckInReminder(at date: Date, userName: String) {
        scheduledReminders.append((date, userName))
    }

    func scheduleSoftAlert(checkerName: String, delayMinutes: Int = 0) {
        scheduledSoftAlerts.append((checkerName, delayMinutes))
    }

    func scheduleHardAlert(checkerName: String, missedHours: Int) {
        scheduledHardAlerts.append((checkerName, missedHours))
    }

    func sendPokeNotification(fromName: String, message: String?) {
        scheduledPokes.append((fromName, message))
    }

    // MARK: - Verification Helpers

    func reset() {
        scheduledReminders.removeAll()
        scheduledSoftAlerts.removeAll()
        scheduledHardAlerts.removeAll()
        scheduledPokes.removeAll()
        cancelledNotificationIds.removeAll()
        cancelAllCalled = false
    }

    var softAlertCount: Int { scheduledSoftAlerts.count }
    var hardAlertCount: Int { scheduledHardAlerts.count }
    var totalAlertCount: Int { softAlertCount + hardAlertCount }

    func softAlertScheduled(for checkerName: String) -> Bool {
        scheduledSoftAlerts.contains { $0.checkerName == checkerName }
    }

    func hardAlertScheduled(for checkerName: String) -> Bool {
        scheduledHardAlerts.contains { $0.checkerName == checkerName }
    }
}
