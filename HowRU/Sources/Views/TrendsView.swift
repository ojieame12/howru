import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @Environment(\.colorScheme) private var colorScheme
    let user: User
    @Query(sort: \CheckIn.timestamp, order: .reverse) private var allCheckIns: [CheckIn]

    @State private var selectedTimeRange: TimeRange = .week

    enum TimeRange: String, CaseIterable {
        case week = "7 Days"
        case month = "30 Days"
        case all = "All Time"

        var days: Int? {
            switch self {
            case .week: return 7
            case .month: return 30
            case .all: return nil
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Time range picker
                    Picker("Time Range", selection: $selectedTimeRange) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if filteredCheckIns.isEmpty {
                        ContentUnavailableView(
                            "No check-ins yet",
                            systemImage: "chart.line.uptrend.xyaxis",
                            description: Text("Your mood trends will appear here")
                        )
                        .frame(height: 300)
                    } else {
                        // Summary cards
                        HStack(spacing: 12) {
                            HowRUSummaryCard(
                                icon: "checkmark.circle.fill",
                                value: "\(filteredCheckIns.count)",
                                title: "Check-ins",
                                color: HowRUColors.success(colorScheme)
                            )
                            HowRUSummaryCard(
                                icon: "heart.fill",
                                value: String(format: "%.1f", averageMood),
                                title: "Avg Mood",
                                color: HowRUColors.moodEmotional(colorScheme)
                            )
                            HowRUSummaryCard(
                                icon: "flame.fill",
                                value: "\(currentStreak)",
                                title: "Streak",
                                color: HowRUColors.coral
                            )
                        }
                        .padding(.horizontal)

                        // Charts
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Mood Over Time")
                                .font(HowRUFont.bodyMedium())
                                .foregroundColor(HowRUColors.textPrimary(colorScheme))
                                .padding(.horizontal)

                            Chart(filteredCheckIns) { checkIn in
                                LineMark(
                                    x: .value("Date", checkIn.timestamp),
                                    y: .value("Mental", checkIn.mentalScore)
                                )
                                .foregroundStyle(HowRUColors.moodMental(colorScheme))
                                .symbol(Circle())

                                LineMark(
                                    x: .value("Date", checkIn.timestamp),
                                    y: .value("Body", checkIn.bodyScore)
                                )
                                .foregroundStyle(HowRUColors.moodBody(colorScheme))
                                .symbol(Circle())

                                LineMark(
                                    x: .value("Date", checkIn.timestamp),
                                    y: .value("Mood", checkIn.moodScore)
                                )
                                .foregroundStyle(HowRUColors.moodEmotional(colorScheme))
                                .symbol(Circle())
                            }
                            .chartYScale(domain: 1...5)
                            .chartYAxis {
                                AxisMarks(values: [1, 2, 3, 4, 5])
                            }
                            .frame(height: 200)
                            .padding(.horizontal)

                            // Legend
                            HStack(spacing: 16) {
                                HowRULegendItem(color: HowRUColors.moodMental(colorScheme), label: "Mental")
                                HowRULegendItem(color: HowRUColors.moodBody(colorScheme), label: "Body")
                                HowRULegendItem(color: HowRUColors.moodEmotional(colorScheme), label: "Mood")
                            }
                            .font(HowRUFont.caption())
                            .padding(.horizontal)
                        }
                        .padding(.vertical)
                        .background(HowRUColors.surface(colorScheme))
                        .cornerRadius(HowRURadius.md)
                        .shadow(color: HowRUColors.shadow(colorScheme), radius: 8)
                        .padding(.horizontal)

                        // Recent check-ins list
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent Check-ins")
                                .font(HowRUFont.bodyMedium())
                                .foregroundColor(HowRUColors.textPrimary(colorScheme))

                            ForEach(filteredCheckIns.prefix(5)) { checkIn in
                                CheckInHistoryRow(checkIn: checkIn)
                            }
                        }
                        .padding()
                        .background(HowRUColors.surface(colorScheme))
                        .cornerRadius(HowRURadius.md)
                        .shadow(color: HowRUColors.shadow(colorScheme), radius: 8)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .background(HowRUColors.background(colorScheme))
            .navigationTitle("Trends")
        }
    }

    private var filteredCheckIns: [CheckIn] {
        let userCheckIns = allCheckIns.filter { $0.user?.id == user.id }

        guard let days = selectedTimeRange.days else {
            return userCheckIns
        }

        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return userCheckIns.filter { $0.timestamp > cutoff }
    }

    private var averageMood: Double {
        guard !filteredCheckIns.isEmpty else { return 0 }
        let total = filteredCheckIns.reduce(0.0) { $0 + $1.averageScore }
        return total / Double(filteredCheckIns.count)
    }

    private var currentStreak: Int {
        // Calculate consecutive days with check-ins
        let calendar = Calendar.current
        var streak = 0
        var currentDate = calendar.startOfDay(for: Date())

        let sortedCheckIns = filteredCheckIns.sorted { $0.timestamp > $1.timestamp }

        for checkIn in sortedCheckIns {
            let checkInDate = calendar.startOfDay(for: checkIn.timestamp)
            if checkInDate == currentDate {
                streak += 1
                currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate) ?? currentDate
            } else if checkInDate < currentDate {
                break
            }
        }

        return streak
    }
}

struct CheckInHistoryRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let checkIn: CheckIn

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(checkIn.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(HowRUFont.caption())
                    .foregroundColor(HowRUColors.textPrimary(colorScheme))

                HStack(spacing: 8) {
                    HowRUScoreBadge(emoji: "🧠", score: checkIn.mentalScore, color: HowRUColors.moodMental(colorScheme))
                    HowRUScoreBadge(emoji: "💪", score: checkIn.bodyScore, color: HowRUColors.moodBody(colorScheme))
                    HowRUScoreBadge(emoji: "😊", score: checkIn.moodScore, color: HowRUColors.moodEmotional(colorScheme))
                }
            }

            Spacer()

            if checkIn.hasSelfie {
                Image(systemName: "camera.fill")
                    .foregroundStyle(HowRUColors.textSecondary(colorScheme))
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: User.self, CheckIn.self, configurations: config)

    let user = User(phoneNumber: "+1234567890", name: "Test User")
    container.mainContext.insert(user)

    // Add some sample check-ins
    for i in 0..<7 {
        let checkIn = CheckIn(
            user: user,
            timestamp: Calendar.current.date(byAdding: .day, value: -i, to: Date()) ?? Date(),
            mentalScore: Int.random(in: 2...5),
            bodyScore: Int.random(in: 2...5),
            moodScore: Int.random(in: 2...5)
        )
        container.mainContext.insert(checkIn)
    }

    return TrendsView(user: user)
        .modelContainer(container)
}
