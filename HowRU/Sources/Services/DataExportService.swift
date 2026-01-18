import Foundation

/// Service for exporting user data in various formats
struct DataExportService {

    enum ExportError: LocalizedError {
        case encodingFailed
        case fileCreationFailed
        case noData

        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "Failed to encode data"
            case .fileCreationFailed:
                return "Failed to create export file"
            case .noData:
                return "No data to export"
            }
        }
    }

    // MARK: - JSON Export

    /// Export check-ins to JSON file
    func exportToJSON(checkIns: [CheckIn], user: User, includeSnapshots: Bool = false) throws -> URL {
        guard !checkIns.isEmpty else {
            throw ExportError.noData
        }

        let exportData = CheckInExportData(
            exportDate: Date(),
            userName: user.name,
            userEmail: user.email,
            checkIns: checkIns.map { checkIn in
                CheckInExportItem(
                    id: checkIn.id.uuidString,
                    timestamp: checkIn.timestamp,
                    mentalScore: checkIn.mentalScore,
                    bodyScore: checkIn.bodyScore,
                    moodScore: checkIn.moodScore,
                    location: checkIn.locationName,
                    selfieBase64: includeSnapshots ? checkIn.selfieData?.base64EncodedString() : nil
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let jsonData = try? encoder.encode(exportData) else {
            throw ExportError.encodingFailed
        }

        return try writeToFile(data: jsonData, extension: "json")
    }

    // MARK: - CSV Export

    /// Export check-ins to CSV file
    func exportToCSV(checkIns: [CheckIn], user: User) throws -> URL {
        guard !checkIns.isEmpty else {
            throw ExportError.noData
        }

        var csvContent = "Date,Time,Mental Score,Body Score,Mood Score,Location\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        for checkIn in checkIns.sorted(by: { $0.timestamp > $1.timestamp }) {
            let date = dateFormatter.string(from: checkIn.timestamp)
            let time = timeFormatter.string(from: checkIn.timestamp)
            let location = escapeCSV(checkIn.locationName ?? "")

            csvContent += "\(date),\(time),\(checkIn.mentalScore),\(checkIn.bodyScore),\(checkIn.moodScore),\(location)\n"
        }

        guard let csvData = csvContent.data(using: .utf8) else {
            throw ExportError.encodingFailed
        }

        return try writeToFile(data: csvData, extension: "csv")
    }

    // MARK: - Helpers

    private func writeToFile(data: Data, extension ext: String) throws -> URL {
        let fileName = "HowRU_Export_\(formattedDate()).\(ext)"
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            throw ExportError.fileCreationFailed
        }
    }

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: Date())
    }

    private func escapeCSV(_ string: String) -> String {
        // Escape quotes and wrap in quotes if contains comma, quote, or newline
        let escaped = string.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            return "\"\(escaped)\""
        }
        return escaped
    }
}

// MARK: - Export Data Structures

struct CheckInExportData: Codable {
    let exportDate: Date
    let userName: String
    let userEmail: String?
    let checkIns: [CheckInExportItem]
}

struct CheckInExportItem: Codable {
    let id: String
    let timestamp: Date
    let mentalScore: Int
    let bodyScore: Int
    let moodScore: Int
    let location: String?
    let selfieBase64: String?
}
