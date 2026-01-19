import SwiftUI
import SwiftData
import UserNotifications
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(InviteManager.self) private var inviteManager: InviteManager?
    @Query private var users: [User]

    @State private var showOnboarding = false
    @State private var authManager = AuthManager.shared

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                // User is authenticated
                if let currentUser = users.first(where: { $0.isChecker }) {
                    MainTabView(user: currentUser)
                } else {
                    // Authenticated but no local user - continue onboarding
                    OnboardingView()
                }
            } else {
                // Not authenticated - show onboarding
                OnboardingView()
            }
        }
        .onAppear {
            // Check if we need onboarding
            showOnboarding = users.isEmpty || !authManager.isAuthenticated
        }
        .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
            if !isAuthenticated {
                // User logged out - will show onboarding
                showOnboarding = true
            }
        }
        .sheet(isPresented: Binding(
            get: { inviteManager?.pendingInviteCode != nil },
            set: { if !$0 { inviteManager?.clearPendingInvite() } }
        )) {
            if let manager = inviteManager {
                InviteAcceptSheet(inviteManager: manager)
            }
        }
    }
}

struct MainTabView: View {
    let user: User
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \CheckIn.timestamp, order: .reverse)
    private var allCheckIns: [CheckIn]

    @Query(sort: \AlertEvent.triggeredAt, order: .reverse)
    private var allAlerts: [AlertEvent]

    @Query(sort: \Poke.sentAt, order: .reverse)
    private var allPokes: [Poke]

    @Query private var circleLinks: [CircleLink]
    @Query private var schedules: [Schedule]

    @State private var selectedTab = 0
    @State private var notificationService = NotificationService()
    @State private var scheduleService: ScheduleService?
    @State private var alertService: AlertService?
    @State private var checkInSyncService = CheckInSyncService()
    @State private var pokeSyncService = PokeSyncService()

    @State private var activePoke: Poke?
    @State private var activeAlert: AlertEvent?
    @State private var pokeComposerLink: CircleLink?
    @State private var shouldStartCheckIn = false
    @State private var hasPerformedInitialSync = false

    private var userCheckIns: [CheckIn] {
        allCheckIns.filter { $0.user?.id == user.id }
    }

    private var pendingPokes: [Poke] {
        allPokes.filter { $0.toCheckerId == user.id && $0.seenAt == nil }
    }

    private var alertsForSupporter: [AlertEvent] {
        allAlerts.filter { $0.resolvedAt == nil && $0.notifiedSupporterIds.contains(user.id) }
    }

    private var activeSchedule: Schedule? {
        schedules.first { $0.user?.id == user.id && $0.isActive }
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                CheckInView(user: user, startCheckInTrigger: $shouldStartCheckIn, onViewTrends: {
                    selectedTab = 2
                })
                .tabItem {
                    Label("Check In", systemImage: "checkmark.circle.fill")
                }
                .tag(0)

            CircleView(user: user)
                .tabItem {
                    Label("Circle", systemImage: "person.2.fill")
                }
                .tag(1)

            TrendsView(user: user)
                .tabItem {
                    Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(2)

            SettingsView(user: user)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
        }
        .tint(.howruCoral)
        .onAppear {
            setupServices()
            updateActivePoke()
            updateActiveAlert()
            refreshAlerts()
            scheduleReminderIfNeeded()
            performInitialSync()
        }
        .onChange(of: pendingPokes.count) { _, _ in
            updateActivePoke()
        }
        .onChange(of: alertsForSupporter.count) { _, _ in
            updateActiveAlert()
        }
        .onChange(of: userCheckIns.count) { _, _ in
            refreshAlerts()
        }
        .onChange(of: circleLinks.count) { _, _ in
            refreshAlerts()
        }
        .onChange(of: activeSchedule?.id) { _, _ in
            scheduleReminderIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NotificationService.actionNotification)) { notification in
            guard let action = notification.object as? NotificationAction else { return }
            switch action {
            case .checkIn:
                selectedTab = 0
                shouldStartCheckIn = true
            case .openCircle, .sendPoke, .call:
                selectedTab = 1
            }
        }
        .sheet(item: $pokeComposerLink) { link in
            PokeComposerSheet(circleLink: link)
        }
        .overlay {
            if let poke = activePoke {
                PokeReceivedModal(
                    poke: poke,
                    onCheckIn: {
                        selectedTab = 0
                        shouldStartCheckIn = true
                        activePoke = nil
                        updateActivePoke()
                    },
                    onDismiss: {
                        activePoke = nil
                        updateActivePoke()
                    }
                )
            } else if let alert = activeAlert {
                AlertReceivedView(
                    alertEvent: alert,
                    checkerName: alert.checkerName,
                    onPoke: {
                        if let link = circleLink(for: alert) {
                            pokeComposerLink = link
                        }
                        alertService?.acknowledgeAlert(alert)
                        activeAlert = nil
                        updateActiveAlert()
                    },
                    onCall: callHandler(for: alert),
                    onDismiss: {
                        alertService?.acknowledgeAlert(alert)
                        activeAlert = nil
                        updateActiveAlert()
                    }
                )
            }
        }
    }

    private func setupServices() {
        // Note: UNUserNotificationCenter delegate is set once in AppDelegate
        // using NotificationHandler.shared - don't overwrite it here

        if scheduleService == nil {
            scheduleService = ScheduleService(modelContext: modelContext)
        }

        if alertService == nil, let scheduleService {
            alertService = AlertService(
                modelContext: modelContext,
                notificationService: notificationService,
                scheduleService: scheduleService
            )
        }

        notificationService.registerNotificationCategories()

        Task {
            await notificationService.checkAuthorizationStatus()
            if !notificationService.isAuthorized && !notificationService.authorizationDenied {
                _ = await notificationService.requestAuthorization()
            }
        }
    }

    private func refreshAlerts() {
        guard let alertService else { return }
        alertService.evaluateAlerts(for: user, checkIns: allCheckIns, circleLinks: circleLinks)

        if hasCheckedInToday {
            alertService.resolveAlerts(for: user.id)
        }
    }

    private func scheduleReminderIfNeeded() {
        guard let scheduleService else { return }

        if let schedule = activeSchedule, schedule.reminderEnabled,
           let reminderDate = scheduleService.nextReminderTime(for: user) {
            notificationService.scheduleCheckInReminder(at: reminderDate, userName: user.name)
        } else {
            notificationService.cancelCheckInReminder()
        }
    }

    private func updateActivePoke() {
        if pendingPokes.isEmpty {
            activePoke = nil
            return
        }

        if let current = activePoke, pendingPokes.contains(where: { $0.id == current.id }) {
            return
        }

        activePoke = pendingPokes.first
    }

    private func updateActiveAlert() {
        if alertsForSupporter.isEmpty {
            activeAlert = nil
            return
        }

        if let current = activeAlert, alertsForSupporter.contains(where: { $0.id == current.id }) {
            return
        }

        activeAlert = alertsForSupporter.first
    }

    private func circleLink(for alert: AlertEvent) -> CircleLink? {
        circleLinks.first { link in
            // For synced alerts, match on checkerServerId (the server user ID)
            // For local alerts, match on local checkerId
            if let checkerServerId = alert.checkerServerId {
                // Server-synced alert: match CircleLink's checkerServerId
                return link.checkerServerId == checkerServerId && link.supporter?.id == user.id
            } else {
                // Local alert: match on local UUID
                return link.checker?.id == alert.checkerId && link.supporter?.id == user.id
            }
        }
    }

    private func callHandler(for alert: AlertEvent) -> (() -> Void)? {
        // Try to get phone from CircleLink (for synced alerts)
        if let link = circleLink(for: alert) {
            // First try checkerPhone (synced from server)
            if let phone = link.checkerPhone, !phone.isEmpty {
                return {
                    if let url = URL(string: "tel://\(phone)") {
                        UIApplication.shared.open(url)
                    }
                }
            }
            // Fallback to local checker User's phone
            if let phone = link.checker?.phoneNumber, !phone.isEmpty {
                return {
                    if let url = URL(string: "tel://\(phone)") {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
        return nil
    }

    private var hasCheckedInToday: Bool {
        let calendar = Calendar.current
        return userCheckIns.contains { calendar.isDateInToday($0.timestamp) }
    }

    private func performInitialSync() {
        guard !hasPerformedInitialSync, AuthManager.shared.isAuthenticated else { return }
        hasPerformedInitialSync = true

        Task {
            // Sync check-ins in background
            await checkInSyncService.performFullSync(modelContext: modelContext)

            // Sync circle (people we support) to get checker server IDs for pokes
            let circleSyncService = CircleSyncService()
            _ = await circleSyncService.fetchSupporting(modelContext: modelContext)

            // Sync alerts from server
            if let alertService {
                _ = await alertService.syncAlerts()
            }

            // Sync pokes (received pokes from supporters)
            _ = await pokeSyncService.fetchPokes(modelContext: modelContext)

            // Fetch subscription entitlements from server
            await SubscriptionService.shared.fetchEntitlements()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [User.self, CheckIn.self, CircleLink.self, Poke.self, AlertEvent.self, Schedule.self], inMemory: true)
}
