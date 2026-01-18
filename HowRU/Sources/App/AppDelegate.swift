import UIKit
import UserNotifications

/// AppDelegate for handling push notifications and device token registration
class AppDelegate: NSObject, UIApplicationDelegate {
    // MARK: - UIApplicationDelegate

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Configure notification handling
        UNUserNotificationCenter.current().delegate = NotificationHandler.shared
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Convert token to string
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()

        if AppConfig.shared.isLoggingEnabled {
            print("[Push] Device token received: \(token)")
        }

        // Register token with server
        Task { @MainActor in
            await NotificationService.shared.registerPushToken(token)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        if AppConfig.shared.isLoggingEnabled {
            print("[Push] Failed to register for remote notifications: \(error)")
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Handle background push notification
        handleRemoteNotification(userInfo)
        completionHandler(.newData)
    }

    // MARK: - Push Notification Handling

    private func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        if AppConfig.shared.isLoggingEnabled {
            print("[Push] Received remote notification: \(userInfo)")
        }

        // Parse notification type
        guard let typeString = userInfo["type"] as? String,
              let notificationType = PushNotificationType(rawValue: typeString) else {
            return
        }

        Task { @MainActor in
            NotificationHandler.shared.handlePushNotification(
                type: notificationType,
                userInfo: userInfo
            )
        }
    }
}

// MARK: - Notification Handler

/// Singleton for handling push notification events
@MainActor
final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationHandler()

    /// Notification posted when a poke is received
    static let pokeReceivedNotification = Notification.Name("HowRU.PokeReceived")

    /// Notification posted when an alert is received
    static let alertReceivedNotification = Notification.Name("HowRU.AlertReceived")

    /// Notification posted when user should navigate to a screen
    static let navigateNotification = Notification.Name("HowRU.Navigate")

    private override init() {
        super.init()
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .badge, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            await self.handleNotificationResponse(response)
        }
        completionHandler()
    }

    // MARK: - Notification Response Handling

    private func handleNotificationResponse(_ response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier

        if AppConfig.shared.isLoggingEnabled {
            print("[Push] Notification response: \(actionIdentifier), userInfo: \(userInfo)")
        }

        // Get notification type
        if let typeString = userInfo["type"] as? String,
           let notificationType = PushNotificationType(rawValue: typeString) {

            switch notificationType {
            case .poke:
                // Post notification for poke received
                NotificationCenter.default.post(
                    name: NotificationHandler.pokeReceivedNotification,
                    object: nil,
                    userInfo: userInfo
                )

                // Navigate to check-in if user tapped the notification
                if actionIdentifier == UNNotificationDefaultActionIdentifier ||
                   actionIdentifier == "RESPOND_CHECK_IN" {
                    NotificationCenter.default.post(
                        name: NotificationHandler.navigateNotification,
                        object: NavigationDestination.checkIn
                    )
                }

            case .alert:
                // Post notification for alert received
                NotificationCenter.default.post(
                    name: NotificationHandler.alertReceivedNotification,
                    object: nil,
                    userInfo: userInfo
                )

                // Navigate to circle if user tapped
                if actionIdentifier == UNNotificationDefaultActionIdentifier {
                    NotificationCenter.default.post(
                        name: NotificationHandler.navigateNotification,
                        object: NavigationDestination.circle
                    )
                }

            case .reminder:
                // Navigate to check-in
                if actionIdentifier == UNNotificationDefaultActionIdentifier ||
                   actionIdentifier == "CHECK_IN_NOW" {
                    NotificationCenter.default.post(
                        name: NotificationHandler.navigateNotification,
                        object: NavigationDestination.checkIn
                    )
                }

            case .generic:
                break
            }
        }
    }

    // MARK: - Push Notification Handling

    func handlePushNotification(type: PushNotificationType, userInfo: [AnyHashable: Any]) {
        switch type {
        case .poke:
            // Sync pokes from server
            Task {
                // Trigger poke sync in background
                if let pokeId = userInfo["pokeId"] as? String {
                    if AppConfig.shared.isLoggingEnabled {
                        print("[Push] Poke received: \(pokeId)")
                    }
                }
            }

        case .alert:
            // Sync alerts from server
            if let alertId = userInfo["alertId"] as? String {
                if AppConfig.shared.isLoggingEnabled {
                    print("[Push] Alert received: \(alertId)")
                }
            }

        case .reminder:
            // Just show notification, no special handling
            break

        case .generic:
            break
        }
    }
}

// MARK: - Push Notification Types

enum PushNotificationType: String {
    case poke = "poke"
    case alert = "alert"
    case reminder = "reminder"
    case generic = "generic"
}

// MARK: - Navigation Destination

enum NavigationDestination {
    case checkIn
    case circle
    case trends
    case settings
}
