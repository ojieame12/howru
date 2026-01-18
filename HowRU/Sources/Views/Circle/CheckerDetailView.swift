import SwiftUI
import SwiftData

/// Notification preference for this checker
enum NotificationPreference: String, CaseIterable {
    case all = "All"
    case urgent = "Urgent"
    case off = "Off"
}

/// View for supporters to see checker's details, scores, and actions
struct CheckerDetailView: View {
    @Bindable var circleLink: CircleLink

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \CheckIn.timestamp, order: .reverse)
    private var allCheckIns: [CheckIn]

    @Query private var allSchedules: [Schedule]

    @State private var showPokeSheet = false

    // Notification preference derived from CircleLink
    private var notificationPref: Binding<NotificationPreference> {
        Binding(
            get: {
                if !circleLink.alertViaPush && !circleLink.alertViaSMS && !circleLink.alertViaEmail {
                    return .off
                } else if circleLink.alertViaPush && !circleLink.alertViaSMS && !circleLink.alertViaEmail {
                    return .urgent
                }
                return .all
            },
            set: { newValue in
                switch newValue {
                case .all:
                    circleLink.alertViaPush = true
                    circleLink.alertViaSMS = true
                    circleLink.alertViaEmail = true
                case .urgent:
                    circleLink.alertViaPush = true
                    circleLink.alertViaSMS = false
                    circleLink.alertViaEmail = false
                case .off:
                    circleLink.alertViaPush = false
                    circleLink.alertViaSMS = false
                    circleLink.alertViaEmail = false
                }
            }
        )
    }

    // Get checker's check-ins
    private var checkerCheckIns: [CheckIn] {
        guard let checkerId = circleLink.checker?.id else { return [] }
        return allCheckIns.filter { $0.user?.id == checkerId }
    }

    // Get checker's schedule
    private var checkerSchedule: Schedule? {
        guard let checkerId = circleLink.checker?.id else { return nil }
        return allSchedules.first { $0.user?.id == checkerId && $0.isActive }
    }

    // Get today's check-in (timezone-aware using checker's schedule)
    private var todaysCheckIn: CheckIn? {
        let timezone = checkerSchedule?.timezone ?? .current
        var calendar = Calendar.current
        calendar.timeZone = timezone

        let todayStart = calendar.startOfDay(for: Date())
        guard let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) else {
            return nil
        }

        return checkerCheckIns.first {
            $0.timestamp >= todayStart && $0.timestamp < todayEnd
        }
    }

    // Get last 7 days of check-ins for mini chart
    private var weekCheckIns: [CheckIn] {
        let calendar = Calendar.current
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return checkerCheckIns.filter { $0.timestamp >= sevenDaysAgo }
    }

    // Check-in status (schedule-aware)
    private var checkInStatus: CheckInStatusType {
        // If checked in today, always show as checked in
        if todaysCheckIn != nil {
            return .checkedIn
        }

        // Check schedule-based status
        if let schedule = checkerSchedule {
            let timezone = schedule.timezone
            var calendar = Calendar.current
            calendar.timeZone = timezone

            let now = Date()
            let components = calendar.dateComponents(in: timezone, from: now)

            guard let hour = components.hour,
                  let minute = components.minute,
                  let weekday = components.weekday else {
                return .pending
            }

            // Check if today is an active day (weekday is 1-7, we use 0-6)
            let dayIndex = weekday - 1
            guard schedule.activeDays.contains(dayIndex) else {
                // Not an active day - show as pending (no check-in expected)
                return .pending
            }

            let currentMinutes = hour * 60 + minute
            let windowEndMinutes = schedule.windowEndHour * 60 + schedule.windowEndMinute
            let graceEndMinutes = windowEndMinutes + schedule.gracePeriodMinutes

            // After window ends + grace: missed
            if currentMinutes > graceEndMinutes {
                return .missed
            }
        } else {
            // No schedule - fall back to 24h rule
            if let lastCheckIn = checkerCheckIns.first {
                let hoursSinceCheckIn = Date().timeIntervalSince(lastCheckIn.timestamp) / 3600
                if hoursSinceCheckIn >= 24 {
                    return .missed
                }
            }
        }

        return .pending
    }

    // Glow color based on status
    private var glowColor: Color {
        checkInStatus.color(colorScheme)
    }

    // Status subtitle with time info
    private var statusSubtitle: String? {
        if let checkIn = todaysCheckIn {
            let timeAgo = checkIn.timestamp.formatted(.relative(presentation: .named))
            if let location = checkIn.locationName, !location.isEmpty {
                return "\(timeAgo) \u{00B7} \(location)"
            }
            return timeAgo
        } else if let lastCheckIn = checkerCheckIns.first {
            return "Last: \(lastCheckIn.timestamp.formatted(.relative(presentation: .named)))"
        }
        return nil
    }

    var body: some View {
        ZStack {
            HowRUColors.background(colorScheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: HowRUSpacing.xl) {
                    // Status pill at top
                    statusPill

                    // Glowing avatar with name
                    headerSection

                    // Status info card
                    StatusInfoCard(
                        icon: checkInStatus.icon,
                        iconColor: checkInStatus.color(colorScheme),
                        title: checkInStatus.label,
                        subtitle: statusSubtitle,
                        subtitleDotColor: checkInStatus == .checkedIn ? checkInStatus.color(colorScheme) : nil
                    )

                    // Today's scores (if checked in and canSeeMood)
                    if let checkIn = todaysCheckIn, circleLink.canSeeMood {
                        todayScoresSection(checkIn: checkIn)
                    }

                    // Selfie thumbnail (if canSeeSelfie and exists)
                    if circleLink.canSeeSelfie, let checkIn = todaysCheckIn, checkIn.hasSelfie {
                        selfieSection(checkIn: checkIn)
                    }

                    // 7-day mini chart (if canSeeMood)
                    if circleLink.canSeeMood && !weekCheckIns.isEmpty {
                        weekChartSection
                    }

                    // Notification preference
                    notificationSection

                    // Compact action buttons
                    actionsSection

                    Spacer(minLength: HowRUSpacing.xxl)
                }
                .padding(.horizontal, HowRUSpacing.screenEdge)
                .padding(.top, HowRUSpacing.md)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPokeSheet) {
            PokeComposerSheet(circleLink: circleLink)
        }
    }

    // MARK: - Status Pill

    private var statusPill: some View {
        HStack(spacing: HowRUSpacing.xs) {
            Image(systemName: checkInStatus.pillIcon)
                .font(.system(size: 12, weight: .semibold))

            Text(checkInStatus.pillLabel)
                .font(HowRUFont.caption())
                .fontWeight(.medium)
        }
        .foregroundColor(checkInStatus.color(colorScheme))
        .padding(.horizontal, HowRUSpacing.md)
        .padding(.vertical, HowRUSpacing.xs)
        .background(
            Capsule()
                .fill(checkInStatus.color(colorScheme).opacity(0.15))
        )
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: HowRUSpacing.md) {
            // Glowing avatar - always show glow with status color
            GlowingAvatar(
                image: checkerProfileImage,
                name: circleLink.checker?.name ?? "Unknown",
                size: 120,
                glowColor: glowColor,
                showGlow: true
            )

            // Name
            Text(circleLink.checker?.name ?? "Unknown")
                .font(HowRUFont.headline1())
                .foregroundColor(HowRUColors.textPrimary(colorScheme))

            // Phone number
            if let phone = circleLink.checker?.phoneNumber, !phone.isEmpty {
                Text(formatPhoneNumber(phone))
                    .font(HowRUFont.body())
                    .foregroundColor(HowRUColors.textSecondary(colorScheme))
            }
        }
    }

    // MARK: - Today's Scores Section

    private func todayScoresSection(checkIn: CheckIn) -> some View {
        VStack(alignment: .leading, spacing: HowRUSpacing.md) {
            Text("Today's Check-In")
                .font(HowRUFont.bodyMedium())
                .foregroundColor(HowRUColors.textPrimary(colorScheme))

            HStack(spacing: HowRUSpacing.lg) {
                ScoreItem(
                    icon: "brain.head.profile",
                    label: "Mind",
                    score: checkIn.mentalScore,
                    color: HowRUColors.moodMental(colorScheme)
                )

                ScoreItem(
                    icon: "figure.walk",
                    label: "Body",
                    score: checkIn.bodyScore,
                    color: HowRUColors.moodBody(colorScheme)
                )

                ScoreItem(
                    icon: "heart.fill",
                    label: "Mood",
                    score: checkIn.moodScore,
                    color: HowRUColors.moodEmotional(colorScheme)
                )
            }
        }
        .padding(HowRUSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: HowRURadius.lg)
                .fill(HowRUColors.surface(colorScheme))
                .shadow(color: HowRUColors.shadow(colorScheme), radius: 8, x: 0, y: 2)
        )
    }

    // MARK: - Selfie Section

    private func selfieSection(checkIn: CheckIn) -> some View {
        VStack(alignment: .leading, spacing: HowRUSpacing.md) {
            HStack {
                Text("Today's Snapshot")
                    .font(HowRUFont.bodyMedium())
                    .foregroundColor(HowRUColors.textPrimary(colorScheme))

                Spacer()

                if let expires = checkIn.selfieExpiresAt {
                    HStack(spacing: HowRUSpacing.xs) {
                        Image(systemName: "clock")
                            .font(.system(size: 12, weight: .medium))
                        Text(expiryText(for: expires))
                            .font(HowRUFont.caption())
                    }
                    .foregroundColor(HowRUColors.textSecondary(colorScheme))
                }
            }

            if let data = checkIn.selfieData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: HowRURadius.md))
            }
        }
        .padding(HowRUSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: HowRURadius.lg)
                .fill(HowRUColors.surface(colorScheme))
                .shadow(color: HowRUColors.shadow(colorScheme), radius: 8, x: 0, y: 2)
        )
    }

    // MARK: - Week Chart Section

    private var weekChartSection: some View {
        VStack(alignment: .leading, spacing: HowRUSpacing.md) {
            Text("Past 7 Days")
                .font(HowRUFont.bodyMedium())
                .foregroundColor(HowRUColors.textPrimary(colorScheme))

            MiniWeekChart(checkIns: weekCheckIns)
        }
        .padding(HowRUSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: HowRURadius.lg)
                .fill(HowRUColors.surface(colorScheme))
                .shadow(color: HowRUColors.shadow(colorScheme), radius: 8, x: 0, y: 2)
        )
    }

    // MARK: - Notification Section

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: HowRUSpacing.md) {
            Text("Notifications")
                .font(HowRUFont.bodyMedium())
                .foregroundColor(HowRUColors.textPrimary(colorScheme))

            PillPicker(
                selection: notificationPref,
                options: NotificationPreference.allCases,
                label: { $0.rawValue }
            )
        }
        .padding(HowRUSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: HowRURadius.lg)
                .fill(HowRUColors.surface(colorScheme))
                .shadow(color: HowRUColors.shadow(colorScheme), radius: 8, x: 0, y: 2)
        )
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        HStack(spacing: HowRUSpacing.md) {
            if let phone = circleLink.checker?.phoneNumber, !phone.isEmpty {
                CompactActionButton(
                    icon: "phone.fill",
                    label: "Call",
                    color: HowRUColors.success(colorScheme)
                ) {
                    HowRUHaptics.light()
                    callNumber(phone)
                }

                CompactActionButton(
                    icon: "message.fill",
                    label: "Message",
                    color: HowRUColors.info(colorScheme)
                ) {
                    HowRUHaptics.light()
                    sendMessage(phone)
                }
            }

            if circleLink.canPoke {
                CompactActionButton(
                    icon: "hand.tap.fill",
                    label: "Poke",
                    color: .howruCoral
                ) {
                    HowRUHaptics.light()
                    showPokeSheet = true
                }
            }
        }
    }

    // MARK: - Helpers

    private var checkerProfileImage: UIImage? {
        guard let data = circleLink.checker?.profileImageData else { return nil }
        return UIImage(data: data)
    }

    private func formatPhoneNumber(_ number: String) -> String {
        // Simple formatting for display
        let digits = number.filter { $0.isNumber }
        if digits.count == 10 {
            let area = digits.prefix(3)
            let middle = digits.dropFirst(3).prefix(3)
            let last = digits.suffix(4)
            return "(\(area)) \(middle)-\(last)"
        } else if digits.count == 11 && digits.first == "1" {
            let area = digits.dropFirst().prefix(3)
            let middle = digits.dropFirst(4).prefix(3)
            let last = digits.suffix(4)
            return "+1 (\(area)) \(middle)-\(last)"
        }
        return number
    }

    private func expiryText(for date: Date) -> String {
        let remaining = date.timeIntervalSince(Date())
        let hours = Int(remaining / 3600)

        if hours > 0 {
            return "Expires in \(hours)h"
        } else {
            let minutes = max(1, Int(remaining / 60))
            return "Expires in \(minutes)m"
        }
    }

    private func callNumber(_ number: String) {
        if let url = URL(string: "tel://\(number)") {
            UIApplication.shared.open(url)
        }
    }

    private func sendMessage(_ number: String) {
        if let url = URL(string: "sms://\(number)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Check-In Status Type

private enum CheckInStatusType {
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

    /// Label for status info card
    var label: String {
        switch self {
        case .checkedIn: return "Checked in today"
        case .pending: return "Hasn't checked in yet"
        case .missed: return "Missed check-in"
        }
    }

    /// Icon for status info card (filled version)
    var icon: String {
        switch self {
        case .checkedIn: return "checkmark.circle.fill"
        case .pending: return "clock.fill"
        case .missed: return "exclamationmark.triangle.fill"
        }
    }

    /// Short label for status pill
    var pillLabel: String {
        switch self {
        case .checkedIn: return "Checked In"
        case .pending: return "Pending"
        case .missed: return "Missed"
        }
    }

    /// Icon for status pill (compact version)
    var pillIcon: String {
        switch self {
        case .checkedIn: return "checkmark"
        case .pending: return "clock"
        case .missed: return "exclamationmark.triangle"
        }
    }
}

// MARK: - Score Item

private struct ScoreItem: View {
    let icon: String
    let label: String
    let score: Int
    let color: Color

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: HowRUSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(color)

            Text("\(score)")
                .font(HowRUFont.headline2())
                .foregroundColor(HowRUColors.textPrimary(colorScheme))

            Text(label)
                .font(HowRUFont.caption())
                .foregroundColor(HowRUColors.textSecondary(colorScheme))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Mini Week Chart

private struct MiniWeekChart: View {
    let checkIns: [CheckIn]

    @Environment(\.colorScheme) private var colorScheme

    private var dayData: [(date: Date, avgScore: Double?)] {
        let calendar = Calendar.current
        var result: [(Date, Double?)] = []

        for dayOffset in (0..<7).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let dayStart = calendar.startOfDay(for: date)

            let dayCheckIn = checkIns.first { calendar.isDate($0.timestamp, inSameDayAs: dayStart) }
            result.append((dayStart, dayCheckIn?.averageScore))
        }

        return result
    }

    var body: some View {
        HStack(spacing: HowRUSpacing.sm) {
            ForEach(dayData, id: \.date) { day in
                VStack(spacing: HowRUSpacing.xs) {
                    // Bar
                    RoundedRectangle(cornerRadius: 4)
                        .fill(day.avgScore != nil ? HowRUColors.coral : HowRUColors.divider(colorScheme))
                        .frame(width: 32, height: barHeight(for: day.avgScore))

                    // Day label
                    Text(dayLabel(for: day.date))
                        .font(HowRUFont.caption())
                        .foregroundColor(HowRUColors.textSecondary(colorScheme))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 80)
    }

    private func barHeight(for score: Double?) -> CGFloat {
        guard let score = score else { return 8 }
        let minHeight: CGFloat = 16
        let maxHeight: CGFloat = 60
        let normalized = (score - 1) / 4 // 1-5 -> 0-1
        return minHeight + (maxHeight - minHeight) * normalized
    }

    private func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return String(formatter.string(from: date).prefix(1))
    }
}

// MARK: - Preview

#Preview("Checker Detail - Checked In") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: User.self, CheckIn.self, CircleLink.self, Schedule.self, Poke.self, AlertEvent.self, configurations: config)

    let checker = User(phoneNumber: "+1234567890", name: "Grandma Betty")
    let supporter = User(phoneNumber: "+0987654321", name: "Sarah")
    container.mainContext.insert(checker)
    container.mainContext.insert(supporter)

    let link = CircleLink(
        checker: checker,
        supporter: supporter,
        supporterName: "Sarah"
    )
    container.mainContext.insert(link)

    // Add today's check-in
    let checkIn = CheckIn(
        user: checker,
        timestamp: Date(),
        mentalScore: 4,
        bodyScore: 3,
        moodScore: 5
    )
    container.mainContext.insert(checkIn)

    return NavigationStack {
        CheckerDetailView(circleLink: link)
    }
    .modelContainer(container)
}

#Preview("Checker Detail - Not Checked In") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: User.self, CheckIn.self, CircleLink.self, Schedule.self, Poke.self, AlertEvent.self, configurations: config)

    let checker = User(phoneNumber: "+1234567890", name: "Grandpa Joe")
    let supporter = User(phoneNumber: "+0987654321", name: "Mike")
    container.mainContext.insert(checker)
    container.mainContext.insert(supporter)

    let link = CircleLink(
        checker: checker,
        supporter: supporter,
        supporterName: "Mike"
    )
    container.mainContext.insert(link)

    return NavigationStack {
        CheckerDetailView(circleLink: link)
    }
    .modelContainer(container)
}
