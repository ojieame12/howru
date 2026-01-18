import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    let user: User
    @Environment(\.modelContext) private var modelContext
    @Query private var schedules: [Schedule]

    @State private var showEditSchedule = false
    @State private var showDeleteConfirmation = false
    @State private var showEditProfile = false
    @State private var showExportData = false
    @State private var subscriptionService = SubscriptionService.shared

    var body: some View {
        NavigationStack {
            List {
                // Profile Section
                Section {
                    Button {
                        showEditProfile = true
                    } label: {
                        HStack(spacing: 16) {
                            profileImage

                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.name)
                                    .font(HowRUFont.bodyMedium())
                                    .foregroundColor(HowRUColors.textPrimary(colorScheme))
                                Text(user.email ?? user.phoneNumber ?? "")
                                    .font(HowRUFont.caption())
                                    .foregroundStyle(HowRUColors.textSecondary(colorScheme))
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(HowRUColors.textSecondary(colorScheme))
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }

                // Schedule Section
                Section("Check-in Schedule") {
                    if let schedule = userSchedule {
                        HStack {
                            Label("Window", systemImage: "clock")
                            Spacer()
                            Text("\(formatHour(schedule.windowStartHour)) - \(formatHour(schedule.windowEndHour))")
                                .foregroundStyle(HowRUColors.textSecondary(colorScheme))
                        }

                        HStack {
                            Label("Grace Period", systemImage: "timer")
                            Spacer()
                            Text("\(schedule.gracePeriodMinutes) min")
                                .foregroundStyle(HowRUColors.textSecondary(colorScheme))
                        }

                        HStack {
                            Label("Reminders", systemImage: "bell")
                            Spacer()
                            Text(schedule.reminderEnabled ? "On" : "Off")
                                .foregroundStyle(HowRUColors.textSecondary(colorScheme))
                        }

                        Button("Edit Schedule") {
                            showEditSchedule = true
                        }
                        .foregroundColor(.howruCoral)
                    } else {
                        Button("Set Up Schedule") {
                            showEditSchedule = true
                        }
                        .foregroundColor(.howruCoral)
                    }
                }

                // Notifications Section
                Section("Notifications") {
                    NavigationLink {
                        EnhancedNotificationSettingsView()
                    } label: {
                        Label("Notification Preferences", systemImage: "bell.badge")
                    }
                }

                // Data Section
                Section("Data") {
                    Button {
                        showExportData = true
                    } label: {
                        Label("Export My Data", systemImage: "square.and.arrow.up")
                    }
                }

                // Widget Section
                Section("Widget") {
                    HStack {
                        Label("Home Screen Widget", systemImage: "square.grid.2x2")
                        Spacer()
                        Text("Add from home screen")
                            .font(HowRUFont.caption())
                            .foregroundStyle(HowRUColors.textSecondary(colorScheme))
                    }
                }

                // Premium Section
                Section {
                    NavigationLink {
                        PremiumView()
                    } label: {
                        HStack {
                            Label(subscriptionService.currentTier == .free ? "HowRU Plus" : subscriptionService.currentTier.displayName, systemImage: "star.fill")
                                .foregroundStyle(Color.howruCoral)
                            Spacer()
                            if subscriptionService.currentTier == .free {
                                Text("Upgrade")
                                    .font(HowRUFont.caption())
                                    .foregroundStyle(Color.howruCoral)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                } footer: {
                    if subscriptionService.currentTier == .free {
                        Text("Unlock SMS alerts, unlimited supporters, and more")
                    } else {
                        Text("You're subscribed to \(subscriptionService.currentTier.displayName)")
                    }
                }

                // Support Section
                Section("Support") {
                    Link(destination: URL(string: "https://howru.app/help")!) {
                        Label("Help Center", systemImage: "questionmark.circle")
                    }
                    Link(destination: URL(string: "https://howru.app/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    Link(destination: URL(string: "https://howru.app/terms")!) {
                        Label("Terms of Service", systemImage: "doc.text")
                    }
                }

                // Account Section
                Section("Account") {
                    Button {
                        signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(HowRUColors.textPrimary(colorScheme))
                    }
                }

                // Danger Zone
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Account", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showEditSchedule) {
                if let schedule = userSchedule {
                    EditScheduleSheet(schedule: schedule)
                } else {
                    CreateScheduleSheet(user: user)
                }
            }
            .sheet(isPresented: $showEditProfile) {
                ProfileEditView(user: user)
            }
            .sheet(isPresented: $showExportData) {
                ExportDataSheet(user: user)
            }
            .alert("Delete Account?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteAccount()
                }
            } message: {
                Text("This will permanently delete your account and all data. This cannot be undone.")
            }
        }
    }

    private var userSchedule: Schedule? {
        schedules.first { $0.user?.id == user.id }
    }

    @ViewBuilder
    private var profileImage: some View {
        if let data = user.profileImageData,
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .clipShape(Circle())
        } else {
            HowRUAvatar(name: user.name, size: 60)
        }
    }

    private func formatHour(_ hour: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
        return "\(displayHour) \(period)"
    }

    private func signOut() {
        Task {
            await AuthManager.shared.logout(modelContext: modelContext)
        }
    }

    private func deleteAccount() {
        Task {
            try? await AuthManager.shared.deleteAccount(modelContext: modelContext)
        }
    }
}

// MARK: - Sub Views

struct NotificationSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("notifyOnCheckIn") private var notifyOnCheckIn = true
    @AppStorage("notifyOnPoke") private var notifyOnPoke = true
    @AppStorage("notifyReminders") private var notifyReminders = true

    var body: some View {
        List {
            Section {
                Toggle("Check-in Reminders", isOn: $notifyReminders)
                    .tint(.howruCoral)
                Toggle("Poke Notifications", isOn: $notifyOnPoke)
                    .tint(.howruCoral)
                Toggle("Circle Check-ins", isOn: $notifyOnCheckIn)
                    .tint(.howruCoral)
            } footer: {
                Text("Control which notifications you receive")
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PremiumView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var subscriptionService = SubscriptionService.shared
    @State private var selectedTier: SubscriptionTier = .plus
    @State private var isYearly = true
    @State private var showRestoreAlert = false
    @State private var restoreMessage = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Current status badge if subscribed
                if subscriptionService.currentTier != .free {
                    currentSubscriptionBadge
                }

                // Header
                Image(systemName: subscriptionService.currentTier == .free ? "star.circle.fill" : "star.circle")
                    .font(.system(size: 80))
                    .foregroundStyle(HowRUGradients.coral)

                Text(subscriptionService.currentTier == .free ? "Upgrade to HowRU Plus" : "Manage Subscription")
                    .font(HowRUFont.headline1())
                    .foregroundColor(HowRUColors.textPrimary(colorScheme))
                    .multilineTextAlignment(.center)

                // Tier Selection
                if subscriptionService.currentTier == .free {
                    tierPicker
                }

                // Features
                featuresList

                // Pricing
                if subscriptionService.currentTier == .free {
                    pricingSection
                }

                // Error message
                if let error = subscriptionService.purchaseError {
                    Text(error)
                        .font(HowRUFont.caption())
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                // Purchase Button
                if subscriptionService.currentTier == .free {
                    purchaseButton
                }

                // Restore Purchases
                Button {
                    restorePurchases()
                } label: {
                    Text("Restore Purchases")
                        .font(HowRUFont.caption())
                        .foregroundStyle(HowRUColors.textSecondary(colorScheme))
                }
                .padding(.top, 8)

                Spacer(minLength: 40)
            }
            .padding(.top, 40)
        }
        .navigationTitle("Premium")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Restore Purchases", isPresented: $showRestoreAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreMessage)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var currentSubscriptionBadge: some View {
        HStack {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            Text("You're subscribed to \(subscriptionService.currentTier.displayName)")
                .font(HowRUFont.bodyMedium())
                .foregroundColor(HowRUColors.textPrimary(colorScheme))
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(HowRURadius.md)
        .padding(.horizontal)
    }

    @ViewBuilder
    private var tierPicker: some View {
        Picker("Tier", selection: $selectedTier) {
            Text("Plus").tag(SubscriptionTier.plus)
            Text("Family").tag(SubscriptionTier.family)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 32)
    }

    @ViewBuilder
    private var featuresList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if selectedTier == .plus || subscriptionService.currentTier == .plus {
                FeatureRow(icon: "message.fill", text: "SMS Alerts")
                FeatureRow(icon: "person.2.fill", text: "Up to 5 Supporters")
                FeatureRow(icon: "chart.bar.fill", text: "Advanced Trends")
                FeatureRow(icon: "bell.slash.fill", text: "No Sponsor Cards")
            } else {
                // Family tier
                FeatureRow(icon: "message.fill", text: "SMS Alerts")
                FeatureRow(icon: "person.3.fill", text: "Up to 15 Supporters")
                FeatureRow(icon: "chart.bar.fill", text: "Advanced Trends")
                FeatureRow(icon: "bell.slash.fill", text: "No Sponsor Cards")
                FeatureRow(icon: "star.fill", text: "Priority Support")
            }
        }
        .padding()
    }

    @ViewBuilder
    private var pricingSection: some View {
        VStack(spacing: 16) {
            // Billing toggle
            Picker("Billing", selection: $isYearly) {
                Text("Monthly").tag(false)
                Text("Yearly").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 60)

            // Price display
            VStack(spacing: 4) {
                Text(currentPrice)
                    .font(HowRUFont.headline2())
                    .foregroundColor(HowRUColors.textPrimary(colorScheme))

                if isYearly {
                    Text("Save \(subscriptionService.yearlySavingsPercent(for: selectedTier))% vs monthly")
                        .font(HowRUFont.caption())
                        .foregroundStyle(Color.green)
                }
            }
        }
    }

    @ViewBuilder
    private var purchaseButton: some View {
        Button {
            purchase()
        } label: {
            HStack {
                if subscriptionService.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Subscribe Now")
                }
            }
            .font(HowRUFont.button())
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.howruCoral)
            .foregroundStyle(.white)
            .cornerRadius(HowRURadius.md)
        }
        .disabled(subscriptionService.isLoading)
        .padding(.horizontal, 32)
    }

    // MARK: - Computed Properties

    private var currentPrice: String {
        if selectedTier == .plus {
            return isYearly ? subscriptionService.yearlyPlusPrice + "/year" : subscriptionService.monthlyPlusPrice + "/month"
        } else {
            return isYearly ? subscriptionService.yearlyFamilyPrice + "/year" : subscriptionService.monthlyFamilyPrice + "/month"
        }
    }

    private var selectedProductID: ProductID {
        switch (selectedTier, isYearly) {
        case (.plus, false): return .monthlyPlus
        case (.plus, true): return .yearlyPlus
        case (.family, false): return .monthlyFamily
        case (.family, true): return .yearlyFamily
        default: return .monthlyPlus
        }
    }

    // MARK: - Actions

    private func purchase() {
        Task {
            let success = await subscriptionService.purchase(selectedProductID)
            if success {
                // Purchase successful - UI will update via Observable
            }
        }
    }

    private func restorePurchases() {
        Task {
            await subscriptionService.restorePurchases()
            if subscriptionService.currentTier != .free {
                restoreMessage = "Your \(subscriptionService.currentTier.displayName) subscription has been restored!"
            } else {
                restoreMessage = "No previous purchases found."
            }
            showRestoreAlert = true
        }
    }
}

struct FeatureRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.howruCoral)
                .frame(width: 24)
            Text(text)
                .font(HowRUFont.body())
                .foregroundColor(HowRUColors.textPrimary(colorScheme))
            Spacer()
            Image(systemName: "checkmark")
                .foregroundStyle(HowRUColors.success(colorScheme))
        }
    }
}

struct EditScheduleSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var schedule: Schedule
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Check-in Window") {
                    Picker("Start Time", selection: $schedule.windowStartHour) {
                        ForEach(5..<12, id: \.self) { hour in
                            Text("\(hour):00 AM").tag(hour)
                        }
                    }

                    Picker("End Time", selection: $schedule.windowEndHour) {
                        ForEach((schedule.windowStartHour + 1)..<14, id: \.self) { hour in
                            Text("\(hour > 12 ? hour - 12 : hour):00 \(hour >= 12 ? "PM" : "AM")").tag(hour)
                        }
                    }
                }

                Section("Grace Period") {
                    Picker("After window ends", selection: $schedule.gracePeriodMinutes) {
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                    }
                }

                Section("Reminders") {
                    Toggle("Enable Reminders", isOn: $schedule.reminderEnabled)
                        .tint(.howruCoral)

                    if schedule.reminderEnabled {
                        Picker("Remind me", selection: $schedule.reminderMinutesBefore) {
                            Text("15 min before").tag(15)
                            Text("30 min before").tag(30)
                            Text("1 hour before").tag(60)
                        }
                    }
                }
            }
            .navigationTitle("Edit Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct CreateScheduleSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    let user: User
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var startHour = 7
    @State private var endHour = 10
    @State private var gracePeriod = 30
    @State private var reminderEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Check-in Window") {
                    Picker("Start Time", selection: $startHour) {
                        ForEach(5..<12, id: \.self) { hour in
                            Text("\(hour):00 AM").tag(hour)
                        }
                    }

                    Picker("End Time", selection: $endHour) {
                        ForEach((startHour + 1)..<14, id: \.self) { hour in
                            Text("\(hour > 12 ? hour - 12 : hour):00 \(hour >= 12 ? "PM" : "AM")").tag(hour)
                        }
                    }
                }

                Section("Grace Period") {
                    Picker("After window ends", selection: $gracePeriod) {
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                    }
                }

                Section("Reminders") {
                    Toggle("Enable Reminders", isOn: $reminderEnabled)
                        .tint(.howruCoral)
                }
            }
            .navigationTitle("Set Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        createSchedule()
                        dismiss()
                    }
                }
            }
        }
    }

    private func createSchedule() {
        let schedule = Schedule(
            user: user,
            windowStartHour: startHour,
            windowEndHour: endHour,
            gracePeriodMinutes: gracePeriod,
            reminderEnabled: reminderEnabled
        )
        modelContext.insert(schedule)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: User.self, Schedule.self, configurations: config)

    let user = User(phoneNumber: "+1234567890", name: "Test User")
    container.mainContext.insert(user)

    return SettingsView(user: user)
        .modelContainer(container)
}
