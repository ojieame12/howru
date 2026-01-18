import SwiftUI
import SwiftData
import UIKit

struct CircleView: View {
    @Environment(\.colorScheme) private var colorScheme
    let user: User
    @Environment(\.modelContext) private var modelContext

    @Query private var circleLinks: [CircleLink]
    @Query(sort: \CheckIn.timestamp, order: .reverse) private var allCheckIns: [CheckIn]
    @Query private var allSchedules: [Schedule]

    @State private var showAddSupporter = false
    @State private var circleSyncService = CircleSyncService()

    // Links where this user is the checker (their supporters)
    private var supporterLinks: [CircleLink] {
        circleLinks.filter { $0.checker?.id == user.id }
    }

    // Links where this user is the supporter (people they support)
    private var supportingLinks: [CircleLink] {
        circleLinks.filter { $0.supporter?.id == user.id }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HowRUColors.background(colorScheme)
                    .ignoresSafeArea()

                if supporterLinks.isEmpty && supportingLinks.isEmpty {
                    emptyStateView
                } else {
                    List {
                        // People you support (as a supporter)
                        if !supportingLinks.isEmpty {
                            Section {
                                ForEach(supportingLinks) { link in
                                    NavigationLink(destination: CheckerDetailView(circleLink: link)) {
                                        CheckerRow(
                                            link: link,
                                            checkIns: allCheckIns,
                                            schedule: activeSchedule(for: link.checker?.id)
                                        )
                                    }
                                }
                            } header: {
                                SectionHeader(
                                    title: "People You Support",
                                    icon: "eye.fill"
                                )
                            }
                        }

                        // Your supporters (as a checker)
                        if !supporterLinks.isEmpty {
                            Section {
                                ForEach(supporterLinks) { link in
                                    SupporterRow(link: link)
                                }
                                .onDelete(perform: deleteSupporterLinks)
                            } header: {
                                SectionHeader(
                                    title: "Your Supporters",
                                    icon: "person.2.fill"
                                )
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Your Circle")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showAddSupporter = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSupporter) {
                AddSupporterSheet(user: user)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: HowRUSpacing.lg) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 48, weight: .medium))
                .foregroundColor(HowRUColors.textSecondary(colorScheme))

            VStack(spacing: HowRUSpacing.sm) {
                Text("No one in your circle yet")
                    .font(HowRUFont.headline2())
                    .foregroundColor(HowRUColors.textPrimary(colorScheme))

                Text("Add someone who cares about you, or ask someone to add you to their circle.")
                    .font(HowRUFont.body())
                    .foregroundColor(HowRUColors.textSecondary(colorScheme))
                    .multilineTextAlignment(.center)
            }

            Button(action: { showAddSupporter = true }) {
                HStack(spacing: HowRUSpacing.sm) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                    Text("Add to Circle")
                }
            }
            .buttonStyle(HowRUPrimaryButtonStyle())
        }
        .padding(HowRUSpacing.xl)
    }

    private func deleteSupporterLinks(at offsets: IndexSet) {
        for index in offsets {
            let link = supporterLinks[index]
            // Delete via sync service if authenticated
            if AuthManager.shared.isAuthenticated {
                Task {
                    _ = await circleSyncService.deleteMember(link, modelContext: modelContext)
                }
            } else {
                modelContext.delete(link)
            }
        }
    }

    private func activeSchedule(for checkerId: UUID?) -> Schedule? {
        guard let checkerId else { return nil }
        return allSchedules.first { $0.user?.id == checkerId && $0.isActive }
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String
    let icon: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: HowRUSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(HowRUColors.coral)
            Text(title)
                .font(HowRUFont.bodyMedium())
                .foregroundColor(HowRUColors.textPrimary(colorScheme))
        }
        .textCase(nil)
        .listRowInsets(EdgeInsets(top: HowRUSpacing.md, leading: 0, bottom: HowRUSpacing.sm, trailing: 0))
    }
}

// MARK: - Checker Row (for supporters viewing checkers)

private struct CheckerRow: View {
    let link: CircleLink
    let checkIns: [CheckIn]
    let schedule: Schedule?

    @Environment(\.colorScheme) private var colorScheme

    private var checkerName: String {
        link.checker?.name ?? "Unknown"
    }

    private var todaysCheckIn: CheckIn? {
        guard let checkerId = link.checker?.id else { return nil }
        var calendar = Calendar.current
        if let schedule = schedule {
            calendar.timeZone = schedule.timezone
        }

        let todayStart = calendar.startOfDay(for: Date())
        guard let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) else {
            return nil
        }

        return checkIns.first { checkIn in
            checkIn.user?.id == checkerId && checkIn.timestamp >= todayStart && checkIn.timestamp < todayEnd
        }
    }

    private var lastCheckIn: CheckIn? {
        guard let checkerId = link.checker?.id else { return nil }
        return checkIns.first { $0.user?.id == checkerId }
    }

    private var status: CheckerStatus {
        if todaysCheckIn != nil {
            return .checkedIn
        }

        if let schedule = schedule {
            if isMissed(using: schedule) {
                return .missed
            }
            return .pending
        }

        if let last = lastCheckIn {
            let hours = Date().timeIntervalSince(last.timestamp) / 3600
            if hours >= 24 {
                return .missed
            }
        }

        return .pending
    }

    private func isMissed(using schedule: Schedule) -> Bool {
        let timezone = schedule.timezone
        var calendar = Calendar.current
        calendar.timeZone = timezone

        let now = Date()
        let components = calendar.dateComponents(in: timezone, from: now)

        guard let hour = components.hour,
              let minute = components.minute,
              let weekday = components.weekday else {
            return false
        }

        let dayIndex = weekday - 1
        guard schedule.activeDays.contains(dayIndex) else {
            return false
        }

        let currentMinutes = hour * 60 + minute
        let windowEndMinutes = schedule.windowEndHour * 60 + schedule.windowEndMinute
        let graceEndMinutes = windowEndMinutes + schedule.gracePeriodMinutes

        return currentMinutes > graceEndMinutes
    }

    var body: some View {
        HStack(spacing: HowRUSpacing.md) {
            // Avatar with status indicator
            ZStack(alignment: .bottomTrailing) {
                HowRUAvatar(name: checkerName, size: 44)

                Circle()
                    .fill(status.color(colorScheme))
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .stroke(HowRUColors.surface(colorScheme), lineWidth: 2)
                    )
                    .offset(x: 2, y: 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(checkerName)
                    .font(HowRUFont.bodyMedium())
                    .foregroundColor(HowRUColors.textPrimary(colorScheme))

                Text(status.label)
                    .font(HowRUFont.caption())
                    .foregroundColor(status.labelColor(colorScheme))
            }

            Spacer()

            // Show scores if checked in and canSeeMood
            if let checkIn = todaysCheckIn, link.canSeeMood {
                HStack(spacing: HowRUSpacing.sm) {
                    MiniScorePill(icon: "brain.head.profile", score: checkIn.mentalScore, color: HowRUColors.moodMental(colorScheme))
                    MiniScorePill(icon: "figure.walk", score: checkIn.bodyScore, color: HowRUColors.moodBody(colorScheme))
                    MiniScorePill(icon: "heart.fill", score: checkIn.moodScore, color: HowRUColors.moodEmotional(colorScheme))
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Mini Score Pill

private struct MiniScorePill: View {
    let icon: String
    let score: Int
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
            Text("\(score)")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(color)
    }
}

// MARK: - Checker Status

private enum CheckerStatus {
    case checkedIn
    case pending
    case missed

    func color(_ scheme: ColorScheme) -> Color {
        switch self {
        case .checkedIn: return HowRUColors.success(scheme)
        case .pending: return HowRUColors.warning(scheme)
        case .missed: return HowRUColors.error(scheme)
        }
    }

    var label: String {
        switch self {
        case .checkedIn: return "Checked in today"
        case .pending: return "Hasn't checked in yet"
        case .missed: return "Missed check-in"
        }
    }

    func labelColor(_ scheme: ColorScheme) -> Color {
        switch self {
        case .checkedIn: return HowRUColors.textSecondary(scheme)
        case .pending: return HowRUColors.warning(scheme)
        case .missed: return HowRUColors.error(scheme)
        }
    }
}

struct SupporterRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let link: CircleLink

    var body: some View {
        HStack(spacing: 12) {
            // Use the reusable avatar component
            HowRUAvatar(name: link.supporterName, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(link.supporterName)
                    .font(HowRUFont.bodyMedium())
                    .foregroundColor(HowRUColors.textPrimary(colorScheme))

                HStack(spacing: 8) {
                    if link.canSeeMood {
                        Label("Mood", systemImage: "heart.fill")
                    }
                    if link.canSeeLocation {
                        Label("Location", systemImage: "location.fill")
                    }
                }
                .font(HowRUFont.caption())
                .foregroundStyle(HowRUColors.textSecondary(colorScheme))
            }

            Spacer()

            if link.isPending {
                HowRUStatusBadge(text: "Pending", style: .warning)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddSupporterSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    let user: User
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMethod: AddMethod = .direct
    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var canSeeMood = true
    @State private var canSeeLocation = false
    @State private var canPoke = true
    @State private var isAdding = false
    @State private var circleSyncService = CircleSyncService()
    @State private var inviteManager = InviteManager()
    @State private var showShareSheet = false
    @State private var inviteLinkToShare: String?

    enum AddMethod: String, CaseIterable {
        case direct = "Add Directly"
        case inviteLink = "Share Invite Link"
        case sendEmail = "Send Email Invite"
    }

    var body: some View {
        NavigationStack {
            Form {
                // Method selection
                Section {
                    Picker("How to add", selection: $selectedMethod) {
                        ForEach(AddMethod.allCases, id: \.self) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Method-specific fields
                switch selectedMethod {
                case .direct:
                    directAddSection
                case .inviteLink:
                    inviteLinkSection
                case .sendEmail:
                    sendEmailSection
                }

                // Permissions (shared for all methods)
                Section("Permissions") {
                    Toggle("Can see mood scores", isOn: $canSeeMood)
                        .tint(.howruCoral)
                    Toggle("Can see location", isOn: $canSeeLocation)
                        .tint(.howruCoral)
                    Toggle("Can send pokes", isOn: $canPoke)
                        .tint(.howruCoral)
                }

                // Error display
                if let error = inviteManager.error {
                    Section {
                        Text(error)
                            .font(HowRUFont.caption())
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add to Circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(actionButtonTitle) {
                        performAction()
                    }
                    .disabled(isActionDisabled)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let link = inviteLinkToShare {
                    ShareSheet(items: [link])
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var directAddSection: some View {
        Section("Contact Info") {
            TextField("Name", text: $name)
                .textContentType(.name)
            TextField("Phone number (optional)", text: $phone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
        }

        Section {
            Text("Add them directly to your circle. They'll be notified if they have the app.")
                .font(HowRUFont.caption())
                .foregroundStyle(HowRUColors.textSecondary(colorScheme))
        }
    }

    @ViewBuilder
    private var inviteLinkSection: some View {
        Section {
            Text("Generate a link that anyone can use to join your circle as a supporter.")
                .font(HowRUFont.caption())
                .foregroundStyle(HowRUColors.textSecondary(colorScheme))
        }

        if inviteManager.isLoading {
            Section {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private var sendEmailSection: some View {
        Section("Recipient") {
            TextField("Email address", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
        }

        Section {
            Text("We'll send them an email with a link to join your circle.")
                .font(HowRUFont.caption())
                .foregroundStyle(HowRUColors.textSecondary(colorScheme))
        }
    }

    // MARK: - Computed Properties

    private var actionButtonTitle: String {
        switch selectedMethod {
        case .direct: return "Add"
        case .inviteLink: return "Create Link"
        case .sendEmail: return "Send"
        }
    }

    private var isActionDisabled: Bool {
        if isAdding || inviteManager.isLoading { return true }

        switch selectedMethod {
        case .direct: return name.isEmpty
        case .inviteLink: return false
        case .sendEmail: return email.isEmpty || !email.contains("@")
        }
    }

    // MARK: - Actions

    private func performAction() {
        switch selectedMethod {
        case .direct:
            addSupporterDirectly()
        case .inviteLink:
            createInviteLink()
        case .sendEmail:
            sendEmailInvite()
        }
    }

    private func addSupporterDirectly() {
        isAdding = true
        let link = CircleLink(
            checker: user,
            supporterPhone: phone.isEmpty ? nil : phone,
            supporterName: name,
            canSeeMood: canSeeMood,
            canSeeLocation: canSeeLocation,
            canPoke: canPoke,
            syncStatus: .new
        )
        modelContext.insert(link)

        // Sync to server if authenticated
        if AuthManager.shared.isAuthenticated {
            Task {
                _ = await circleSyncService.createMember(link, modelContext: modelContext)
                dismiss()
            }
        } else {
            dismiss()
        }
    }

    private func createInviteLink() {
        Task {
            if let link = await inviteManager.createInvite(
                role: "supporter",
                canSeeMood: canSeeMood,
                canSeeLocation: canSeeLocation,
                canSeeSelfie: false,
                canPoke: canPoke
            ) {
                inviteLinkToShare = link
                showShareSheet = true
            }
        }
    }

    private func sendEmailInvite() {
        Task {
            let success = await inviteManager.sendInviteViaEmail(
                email: email,
                role: "supporter",
                canSeeMood: canSeeMood,
                canSeeLocation: canSeeLocation,
                canSeeSelfie: false,
                canPoke: canPoke
            )

            if success {
                dismiss()
            }
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: User.self, CircleLink.self, configurations: config)

    let user = User(phoneNumber: "+1234567890", name: "Test User")
    container.mainContext.insert(user)

    return CircleView(user: user)
        .modelContainer(container)
}
