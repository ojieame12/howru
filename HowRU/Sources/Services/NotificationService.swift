import Foundation
import UserNotifications
import SwiftData
import UIKit

/// Service for managing local notifications
@MainActor
@Observable
final class NotificationService {
    // Singleton for push token registration
    static let shared = NotificationService()

    private(set) var isAuthorized = false
    private(set) var authorizationDenied = false
    private(set) var pushToken: String?
    private(set) var isPushRegistered = false

    private let apiClient: APIClient

    // Notification identifiers
    private enum NotificationID {
        static let checkInReminder = "com.howru.checkin.reminder"
        static let softAlert = "com.howru.alert.soft"
        static let hardAlert = "com.howru.alert.hard"
        static let pokeReceived = "com.howru.poke.received"
    }

    static let actionNotification = Notification.Name("HowRU.NotificationAction")

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            isAuthorized = granted
            authorizationDenied = !granted
            return granted
        } catch {
            print("Notification authorization error: \(error)")
            authorizationDenied = true
            return false
        }
    }

    func checkAuthorizationStatus() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            isAuthorized = true
            authorizationDenied = false
        case .denied:
            isAuthorized = false
            authorizationDenied = true
        case .notDetermined:
            isAuthorized = false
            authorizationDenied = false
        @unknown default:
            isAuthorized = false
        }
    }

    // MARK: - Push Token Registration

    /// Trigger APNs registration - call this after login
    /// This requests permission and registers for remote notifications
    static func registerForPushNotifications() {
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                if granted {
                    await MainActor.run {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
                if AppConfig.shared.isLoggingEnabled {
                    print("[Push] Authorization granted: \(granted), registering for remote notifications")
                }
            } catch {
                if AppConfig.shared.isLoggingEnabled {
                    print("[Push] Authorization error: \(error)")
                }
            }
        }
    }

    /// Register push token with the server
    /// - Parameter token: The device push token
    /// - Returns: True if registration was successful
    func registerPushToken(_ token: String) async -> Bool {
        guard AuthManager.shared.isAuthenticated else {
            if AppConfig.shared.isLoggingEnabled {
                print("[Push] Cannot register token: not authenticated")
            }
            return false
        }

        // Store token locally
        pushToken = token

        do {
            let body = RegisterPushTokenBody(
                token: token,
                platform: "ios",
                deviceId: getDeviceId()
            )

            let _: SuccessResponse = try await apiClient.post("/users/me/push-token", body: body)

            isPushRegistered = true

            if AppConfig.shared.isLoggingEnabled {
                print("[Push] Token registered successfully")
            }

            return true
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("[Push] Failed to register token: \(error)")
            }
            return false
        }
    }

    /// Unregister push token from the server (on logout)
    func unregisterPushToken() async {
        guard let token = pushToken else { return }

        do {
            // Backend expects token in body, not path
            let body = ["token": token]
            try await apiClient.delete("/users/me/push-token", body: body)
            isPushRegistered = false
            pushToken = nil

            if AppConfig.shared.isLoggingEnabled {
                print("[Push] Token unregistered successfully")
            }
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("[Push] Failed to unregister token: \(error)")
            }
        }
    }

    /// Get a unique device identifier
    private func getDeviceId() -> String {
        // Use UserDefaults to store a consistent device ID
        let key = "howru_device_id"
        if let existingId = UserDefaults.standard.string(forKey: key) {
            return existingId
        }

        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }

    // MARK: - Check-In Reminders

    /// Schedule a check-in reminder notification
    func scheduleCheckInReminder(at date: Date, userName: String) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time to check in"
        content.body = "How are you feeling today, \(userName)?"
        content.sound = .default
        content.categoryIdentifier = "CHECK_IN_REMINDER"
        content.userInfo = ["userName": userName]

        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(
            identifier: NotificationID.checkInReminder,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule check-in reminder: \(error)")
            }
        }
    }

    /// Cancel check-in reminder
    func cancelCheckInReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [NotificationID.checkInReminder]
        )
    }

    // MARK: - Alert Notifications (For Supporters)

    /// Schedule a soft alert notification for supporter
    func scheduleSoftAlert(checkerName: String, delayMinutes: Int = 0) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(checkerName) hasn't checked in"
        content.body = "They might need a gentle reminder. Tap to send a poke."
        content.sound = .default
        content.categoryIdentifier = "SUPPORTER_ALERT"
        content.userInfo = ["alertType": "soft", "checkerName": checkerName]

        let trigger: UNNotificationTrigger?
        if delayMinutes > 0 {
            trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval(delayMinutes * 60),
                repeats: false
            )
        } else {
            trigger = nil // Deliver immediately
        }

        let request = UNNotificationRequest(
            identifier: "\(NotificationID.softAlert).\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Schedule a hard alert notification for supporter
    func scheduleHardAlert(checkerName: String, missedHours: Int) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Check on \(checkerName)"
        content.body = "It's been \(missedHours) hours since their last check-in."
        content.sound = UNNotificationSound.defaultCritical
        content.categoryIdentifier = "SUPPORTER_ALERT_URGENT"
        content.userInfo = ["alertType": "hard", "checkerName": checkerName]
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: "\(NotificationID.hardAlert).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Poke Notifications

    /// Send poke received notification to checker
    func sendPokeNotification(fromName: String, message: String?) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(fromName) poked you"
        content.body = message ?? "Someone wants to know how you're doing"
        content.sound = .default
        content.categoryIdentifier = "POKE_RECEIVED"

        let request = UNNotificationRequest(
            identifier: "\(NotificationID.pokeReceived).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Category Registration

    /// Register notification categories with actions
    func registerNotificationCategories() {
        // Check-in reminder category
        let checkInAction = UNNotificationAction(
            identifier: "CHECK_IN_NOW",
            title: "Check In",
            options: [.foreground]
        )
        let remindLaterAction = UNNotificationAction(
            identifier: "REMIND_LATER",
            title: "Remind in 1 hour",
            options: []
        )
        let reminderCategory = UNNotificationCategory(
            identifier: "CHECK_IN_REMINDER",
            actions: [checkInAction, remindLaterAction],
            intentIdentifiers: [],
            options: []
        )

        // Supporter alert category
        let pokeAction = UNNotificationAction(
            identifier: "SEND_POKE",
            title: "Send Poke",
            options: [.foreground]
        )
        let callAction = UNNotificationAction(
            identifier: "CALL_NOW",
            title: "Call",
            options: [.foreground]
        )
        let alertCategory = UNNotificationCategory(
            identifier: "SUPPORTER_ALERT",
            actions: [pokeAction, callAction],
            intentIdentifiers: [],
            options: []
        )

        // Urgent alert category
        let urgentCategory = UNNotificationCategory(
            identifier: "SUPPORTER_ALERT_URGENT",
            actions: [callAction, pokeAction],
            intentIdentifiers: [],
            options: [.allowInCarPlay]
        )

        // Poke received category
        let respondAction = UNNotificationAction(
            identifier: "RESPOND_CHECK_IN",
            title: "Check In Now",
            options: [.foreground]
        )
        let pokeCategory = UNNotificationCategory(
            identifier: "POKE_RECEIVED",
            actions: [respondAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            reminderCategory,
            alertCategory,
            urgentCategory,
            pokeCategory
        ])
    }

    // MARK: - Cleanup

    /// Remove all pending notifications
    func removeAllPendingNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// Remove all delivered notifications
    func removeAllDeliveredNotifications() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    /// Clear badge count
    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }
}

// MARK: - Notification Response Handler

extension NotificationService {
    /// Handle notification action responses
    func handleNotificationResponse(_ response: UNNotificationResponse) -> NotificationAction? {
        let actionIdentifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        let action: NotificationAction?

        switch actionIdentifier {
        case "CHECK_IN_NOW", "RESPOND_CHECK_IN":
            action = .checkIn

        case "REMIND_LATER":
            // Reschedule for 1 hour later
            if let userName = userInfo["userName"] as? String {
                let reminderDate = Date().addingTimeInterval(3600)
                scheduleCheckInReminder(at: reminderDate, userName: userName)
            }
            action = nil

        case "SEND_POKE":
            if let checkerName = userInfo["checkerName"] as? String {
                action = .sendPoke(to: checkerName)
            } else {
                action = nil
            }

        case "CALL_NOW":
            if let checkerName = userInfo["checkerName"] as? String {
                action = .call(to: checkerName)
            } else {
                action = nil
            }

        case UNNotificationDefaultActionIdentifier:
            // User tapped notification
            let category = response.notification.request.content.categoryIdentifier
            if category == "CHECK_IN_REMINDER" || category == "POKE_RECEIVED" {
                action = .checkIn
            } else if category.contains("SUPPORTER") {
                action = .openCircle
            } else {
                action = nil
            }

        default:
            action = nil
        }
        
        if let action {
            NotificationCenter.default.post(name: Self.actionNotification, object: action)
        }

        return action
    }
}

// MARK: - Notification Action

enum NotificationAction {
    case checkIn
    case sendPoke(to: String)
    case call(to: String)
    case openCircle
}
