import SwiftUI
import UserNotifications

/// Enhanced notification settings with granular controls
struct EnhancedNotificationSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme

    // Check-in reminders
    @AppStorage("notifyReminders") private var notifyReminders = true
    @AppStorage("reminderTime") private var reminderTime = 9 // Hour of day (0-23)
    @AppStorage("reminderAdvanceMinutes") private var reminderAdvanceMinutes = 30

    // Alert notifications
    @AppStorage("notifyOnMissedCheckIn") private var notifyOnMissedCheckIn = true
    @AppStorage("notifySoftAlerts") private var notifySoftAlerts = true
    @AppStorage("notifyHardAlerts") private var notifyHardAlerts = true
    @AppStorage("notifyEscalations") private var notifyEscalations = true

    // Social notifications
    @AppStorage("notifyOnPoke") private var notifyOnPoke = true
    @AppStorage("notifyCircleCheckIns") private var notifyCircleCheckIns = true
    @AppStorage("notifyNewSupporter") private var notifyNewSupporter = true

    // Sound settings
    @AppStorage("notificationSound") private var notificationSound = "default"
    @AppStorage("criticalAlertsEnabled") private var criticalAlertsEnabled = false

    @State private var systemNotificationsEnabled = false
    @State private var showingSystemSettings = false

    var body: some View {
        List {
            // System Status
            systemStatusSection

            // Check-in Reminders
            if systemNotificationsEnabled {
                reminderSection

                // Alert Notifications
                alertSection

                // Social Notifications
                socialSection

                // Sound Settings
                soundSection
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            checkNotificationStatus()
        }
    }

    // MARK: - System Status Section

    private var systemStatusSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notification Permission")
                        .font(HowRUFont.bodyMedium())
                        .foregroundColor(HowRUColors.textPrimary(colorScheme))

                    Text(systemNotificationsEnabled ? "Enabled" : "Disabled in Settings")
                        .font(HowRUFont.caption())
                        .foregroundColor(systemNotificationsEnabled
                            ? HowRUColors.success(colorScheme)
                            : HowRUColors.error(colorScheme))
                }

                Spacer()

                if !systemNotificationsEnabled {
                    Button("Enable") {
                        openSystemSettings()
                    }
                    .font(HowRUFont.bodyMedium())
                    .foregroundColor(.howruCoral)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(HowRUColors.success(colorScheme))
                }
            }
        } footer: {
            if !systemNotificationsEnabled {
                Text("Enable notifications in Settings to receive check-in reminders and alerts.")
            }
        }
    }

    // MARK: - Reminder Section

    private var reminderSection: some View {
        Section("Check-in Reminders") {
            Toggle(isOn: $notifyReminders) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily Reminders")
                            .font(HowRUFont.body())
                        Text("Remind me to check in")
                            .font(HowRUFont.caption())
                            .foregroundColor(HowRUColors.textSecondary(colorScheme))
                    }
                } icon: {
                    Image(systemName: "bell.badge")
                        .foregroundColor(.howruCoral)
                }
            }
            .tint(.howruCoral)

            if notifyReminders {
                Picker(selection: $reminderAdvanceMinutes) {
                    Text("15 minutes before").tag(15)
                    Text("30 minutes before").tag(30)
                    Text("1 hour before").tag(60)
                    Text("At window start").tag(0)
                } label: {
                    Label("Reminder Timing", systemImage: "clock")
                }
            }
        }
    }

    // MARK: - Alert Section

    private var alertSection: some View {
        Section {
            Toggle(isOn: $notifyOnMissedCheckIn) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Missed Check-in Alerts")
                            .font(HowRUFont.body())
                        Text("When someone you support misses their window")
                            .font(HowRUFont.caption())
                            .foregroundColor(HowRUColors.textSecondary(colorScheme))
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(HowRUColors.warning(colorScheme))
                }
            }
            .tint(.howruCoral)

            if notifyOnMissedCheckIn {
                Toggle(isOn: $notifySoftAlerts) {
                    HStack {
                        Text("First Alert")
                        Spacer()
                        Text("24h")
                            .font(HowRUFont.caption())
                            .foregroundColor(HowRUColors.textSecondary(colorScheme))
                    }
                }
                .tint(.howruCoral)
                .padding(.leading, HowRUSpacing.lg)

                Toggle(isOn: $notifyHardAlerts) {
                    HStack {
                        Text("Urgent Alert")
                        Spacer()
                        Text("36h")
                            .font(HowRUFont.caption())
                            .foregroundColor(HowRUColors.textSecondary(colorScheme))
                    }
                }
                .tint(.howruCoral)
                .padding(.leading, HowRUSpacing.lg)

                Toggle(isOn: $notifyEscalations) {
                    HStack {
                        Text("Escalation")
                        Spacer()
                        Text("48h")
                            .font(HowRUFont.caption())
                            .foregroundColor(HowRUColors.textSecondary(colorScheme))
                    }
                }
                .tint(.howruCoral)
                .padding(.leading, HowRUSpacing.lg)
            }
        } header: {
            Text("Supporter Alerts")
        } footer: {
            Text("Alerts are sent when people you support don't check in within their window.")
        }
    }

    // MARK: - Social Section

    private var socialSection: some View {
        Section("Social") {
            Toggle(isOn: $notifyOnPoke) {
                Label {
                    Text("Poke Notifications")
                        .font(HowRUFont.body())
                } icon: {
                    Image(systemName: "hand.tap")
                        .foregroundColor(.howruCoral)
                }
            }
            .tint(.howruCoral)

            Toggle(isOn: $notifyCircleCheckIns) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Circle Check-ins")
                            .font(HowRUFont.body())
                        Text("When people you support check in")
                            .font(HowRUFont.caption())
                            .foregroundColor(HowRUColors.textSecondary(colorScheme))
                    }
                } icon: {
                    Image(systemName: "person.2")
                        .foregroundColor(HowRUColors.success(colorScheme))
                }
            }
            .tint(.howruCoral)

            Toggle(isOn: $notifyNewSupporter) {
                Label {
                    Text("New Supporters")
                        .font(HowRUFont.body())
                } icon: {
                    Image(systemName: "person.badge.plus")
                        .foregroundColor(HowRUColors.info(colorScheme))
                }
            }
            .tint(.howruCoral)
        }
    }

    // MARK: - Sound Section

    private var soundSection: some View {
        Section {
            Picker(selection: $notificationSound) {
                Text("Default").tag("default")
                Text("Gentle Chime").tag("gentle")
                Text("Soft Bell").tag("bell")
                Text("None").tag("none")
            } label: {
                Label("Notification Sound", systemImage: "speaker.wave.2")
            }

            Toggle(isOn: $criticalAlertsEnabled) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Critical Alerts")
                            .font(HowRUFont.body())
                        Text("Play sound even in Do Not Disturb")
                            .font(HowRUFont.caption())
                            .foregroundColor(HowRUColors.textSecondary(colorScheme))
                    }
                } icon: {
                    Image(systemName: "bell.and.waves.left.and.right")
                        .foregroundColor(HowRUColors.error(colorScheme))
                }
            }
            .tint(.howruCoral)
        } header: {
            Text("Sound")
        } footer: {
            Text("Critical alerts will bypass Do Not Disturb mode for urgent escalations.")
        }
    }

    // MARK: - Actions

    private func checkNotificationStatus() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                systemNotificationsEnabled = settings.authorizationStatus == .authorized
            }
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        EnhancedNotificationSettingsView()
    }
}
