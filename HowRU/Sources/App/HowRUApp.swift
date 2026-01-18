import SwiftUI
import SwiftData
import UserNotifications
import UIKit

@main
struct HowRUApp: App {
    // Connect AppDelegate for push notification handling
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var inviteManager = InviteManager()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            User.self,
            CheckIn.self,
            CircleLink.self,
            Poke.self,
            AlertEvent.self,
            Schedule.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(inviteManager)
                .onOpenURL { url in
                    inviteManager.handleURL(url)
                }
                .onAppear {
                    // Register categories on launch
                    NotificationService.shared.registerNotificationCategories()
                    // Register for push if already authenticated
                    if AuthManager.shared.isAuthenticated {
                        NotificationService.registerForPushNotifications()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NotificationHandler.navigateNotification)) { notification in
                    // Handle navigation from push notifications
                    if let destination = notification.object as? NavigationDestination {
                        handleNavigationDestination(destination)
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }

    // MARK: - Navigation Handling

    private func handleNavigationDestination(_ destination: NavigationDestination) {
        // Post notification for MainTabView to handle navigation
        NotificationCenter.default.post(
            name: NotificationService.actionNotification,
            object: destination.toNotificationAction
        )
    }
}

// MARK: - Navigation Destination Extension

extension NavigationDestination {
    var toNotificationAction: NotificationAction {
        switch self {
        case .checkIn:
            return .checkIn
        case .circle:
            return .openCircle
        case .trends:
            return .checkIn // No trends action, fallback to checkIn
        case .settings:
            return .checkIn // No settings action, fallback to checkIn
        }
    }
}
