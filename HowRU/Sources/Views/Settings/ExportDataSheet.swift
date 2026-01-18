import SwiftUI
import SwiftData

/// Sheet for exporting user data in various formats
struct ExportDataSheet: View {
    let user: User
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \CheckIn.timestamp, order: .reverse)
    private var allCheckIns: [CheckIn]

    @State private var selectedFormat: ExportFormat = .json
    @State private var dateRange: DateRange = .allTime
    @State private var includeSnapshots = false
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var showShareSheet = false
    @State private var exportedFileURL: URL?

    enum ExportFormat: String, CaseIterable {
        case json = "JSON"
        case csv = "CSV"

        var fileExtension: String {
            switch self {
            case .json: return "json"
            case .csv: return "csv"
            }
        }

        var mimeType: String {
            switch self {
            case .json: return "application/json"
            case .csv: return "text/csv"
            }
        }
    }

    enum DateRange: String, CaseIterable {
        case lastWeek = "Last 7 Days"
        case lastMonth = "Last 30 Days"
        case lastYear = "Last Year"
        case allTime = "All Time"

        var startDate: Date? {
            let calendar = Calendar.current
            switch self {
            case .lastWeek:
                return calendar.date(byAdding: .day, value: -7, to: Date())
            case .lastMonth:
                return calendar.date(byAdding: .day, value: -30, to: Date())
            case .lastYear:
                return calendar.date(byAdding: .year, value: -1, to: Date())
            case .allTime:
                return nil
            }
        }
    }

    private var userCheckIns: [CheckIn] {
        allCheckIns.filter { $0.user?.id == user.id }
    }

    private var filteredCheckIns: [CheckIn] {
        guard let startDate = dateRange.startDate else {
            return userCheckIns
        }
        return userCheckIns.filter { $0.timestamp >= startDate }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Summary
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(filteredCheckIns.count) Check-ins")
                                .font(HowRUFont.headline2())
                                .foregroundColor(HowRUColors.textPrimary(colorScheme))

                            Text(dateRangeDescription)
                                .font(HowRUFont.caption())
                                .foregroundColor(HowRUColors.textSecondary(colorScheme))
                        }

                        Spacer()

                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 32))
                            .foregroundColor(.howruCoral)
                    }
                    .padding(.vertical, HowRUSpacing.sm)
                }

                // Format Selection
                Section("Export Format") {
                    Picker("Format", selection: $selectedFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Date Range
                Section("Date Range") {
                    Picker("Time Period", selection: $dateRange) {
                        ForEach(DateRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                }

                // Options
                Section {
                    Toggle(isOn: $includeSnapshots) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Include Snapshots")
                                .font(HowRUFont.body())
                            Text("Photos will be embedded as base64")
                                .font(HowRUFont.caption())
                                .foregroundColor(HowRUColors.textSecondary(colorScheme))
                        }
                    }
                    .tint(.howruCoral)
                } header: {
                    Text("Options")
                } footer: {
                    Text("Snapshots increase file size significantly. Only available for JSON export.")
                }

                // Error Display
                if let error = exportError {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(HowRUColors.error(colorScheme))
                            Text(error)
                                .font(HowRUFont.caption())
                                .foregroundColor(HowRUColors.error(colorScheme))
                        }
                    }
                }

                // Export Button
                Section {
                    Button(action: exportData) {
                        HStack {
                            Spacer()
                            if isExporting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .padding(.trailing, HowRUSpacing.sm)
                                Text("Exporting...")
                            } else {
                                Image(systemName: "arrow.down.doc")
                                Text("Export \(selectedFormat.rawValue)")
                            }
                            Spacer()
                        }
                        .font(HowRUFont.button())
                    }
                    .disabled(isExporting || filteredCheckIns.isEmpty)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: HowRURadius.md)
                            .fill(filteredCheckIns.isEmpty ? Color.gray : Color.howruCoral)
                    )
                    .foregroundColor(.white)
                }
            }
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedFileURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var dateRangeDescription: String {
        if let startDate = dateRange.startDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return "From \(formatter.string(from: startDate))"
        }
        return "All check-in history"
    }

    // MARK: - Export Actions

    private func exportData() {
        isExporting = true
        exportError = nil

        Task {
            do {
                let fileURL = try await performExport()
                await MainActor.run {
                    isExporting = false
                    exportedFileURL = fileURL
                    showShareSheet = true
                    HowRUHaptics.success()
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportError = error.localizedDescription
                    HowRUHaptics.error()
                }
            }
        }
    }

    private func performExport() async throws -> URL {
        let exportService = DataExportService()

        switch selectedFormat {
        case .json:
            return try exportService.exportToJSON(
                checkIns: filteredCheckIns,
                user: user,
                includeSnapshots: includeSnapshots
            )
        case .csv:
            return try exportService.exportToCSV(
                checkIns: filteredCheckIns,
                user: user
            )
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

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: User.self, CheckIn.self, configurations: config)

    let user = User(phoneNumber: "+1234567890", name: "Test User")
    container.mainContext.insert(user)

    // Add some sample check-ins
    for i in 0..<30 {
        let date = Calendar.current.date(byAdding: .day, value: -i, to: Date())!
        let checkIn = CheckIn(
            user: user,
            timestamp: date,
            mentalScore: Int.random(in: 1...5),
            bodyScore: Int.random(in: 1...5),
            moodScore: Int.random(in: 1...5)
        )
        container.mainContext.insert(checkIn)
    }

    return ExportDataSheet(user: user)
        .modelContainer(container)
}
