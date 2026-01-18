import Foundation
import SwiftData

/// Service for syncing check-ins with the server
@MainActor
@Observable
final class CheckInSyncService {
    // MARK: - Properties

    private let apiClient: APIClient
    private(set) var isSyncing = false
    private(set) var lastSyncedAt: Date?
    var syncError: String?

    // MARK: - Initialization

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    // MARK: - Upload Operations

    /// Upload a single check-in to the server
    /// - Parameters:
    ///   - checkIn: The check-in to upload
    ///   - modelContext: SwiftData context
    /// - Returns: True if upload was successful
    func uploadCheckIn(_ checkIn: CheckIn, modelContext: ModelContext) async -> Bool {
        guard AuthManager.shared.isAuthenticated else {
            syncError = "Not authenticated"
            return false
        }

        // Mark as syncing
        checkIn.syncStatus = .syncing

        do {
            let body = CreateCheckInBody(
                mentalScore: checkIn.mentalScore,
                bodyScore: checkIn.bodyScore,
                moodScore: checkIn.moodScore,
                latitude: checkIn.latitude,
                longitude: checkIn.longitude,
                locationName: checkIn.locationName,
                address: checkIn.address,
                isManual: checkIn.isManualCheckIn
            )

            let response: CheckInResponse = try await apiClient.post("/checkins", body: body)

            // Update local check-in with server data
            checkIn.syncId = response.checkIn.id
            checkIn.syncStatus = .synced
            checkIn.syncedAt = Date()

            try modelContext.save()

            if AppConfig.shared.isLoggingEnabled {
                print("Check-in uploaded successfully: \(response.checkIn.id)")
            }

            return true
        } catch {
            checkIn.syncStatus = .failed
            try? modelContext.save()

            if AppConfig.shared.isLoggingEnabled {
                print("Failed to upload check-in: \(error)")
            }
            syncError = error.localizedDescription
            return false
        }
    }

    /// Upload selfie for a check-in
    /// - Parameters:
    ///   - checkIn: The check-in with selfie data
    ///   - modelContext: SwiftData context
    /// - Returns: True if upload was successful
    func uploadSelfie(for checkIn: CheckIn, modelContext: ModelContext) async -> Bool {
        guard AuthManager.shared.isAuthenticated else {
            syncError = "Not authenticated"
            return false
        }

        guard let selfieData = checkIn.selfieData,
              let syncId = checkIn.syncId else {
            syncError = "No selfie data or check-in not synced"
            return false
        }

        do {
            // Backend expects JSON with base64-encoded image data
            let base64Image = selfieData.base64EncodedString()
            let body = UploadSelfieBody(
                checkinId: syncId,
                imageData: base64Image,
                mimeType: "image/jpeg"
            )

            let _: UploadResponse = try await apiClient.post("/uploads/selfie", body: body)

            if AppConfig.shared.isLoggingEnabled {
                print("Selfie uploaded successfully for check-in: \(syncId)")
            }

            return true
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("Failed to upload selfie: \(error)")
            }
            syncError = error.localizedDescription
            return false
        }
    }

    // MARK: - Download Operations

    /// Download check-ins from server since a given date
    /// - Parameters:
    ///   - since: Only fetch check-ins after this date (nil for all)
    ///   - modelContext: SwiftData context
    /// - Returns: Number of new/updated check-ins
    func downloadCheckIns(since: Date? = nil, modelContext: ModelContext) async -> Int {
        guard AuthManager.shared.isAuthenticated else {
            syncError = "Not authenticated"
            return 0
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            var queryItems: [URLQueryItem]? = nil
            if let since = since {
                let formatter = ISO8601DateFormatter()
                queryItems = [URLQueryItem(name: "since", value: formatter.string(from: since))]
            }

            let response: CheckInsResponse = try await apiClient.get("/checkins", queryItems: queryItems)

            var syncedCount = 0

            for apiCheckIn in response.checkIns {
                // Check if we already have this check-in locally
                let fetchDescriptor = FetchDescriptor<CheckIn>(
                    predicate: #Predicate<CheckIn> { $0.syncId == apiCheckIn.id }
                )
                let existingCheckIns = try modelContext.fetch(fetchDescriptor)

                if existingCheckIns.isEmpty {
                    // Create new local check-in from server data
                    // Note: We need the user reference, which should come from UserSyncService
                    let userFetch = FetchDescriptor<User>(
                        predicate: #Predicate { $0.isChecker == true }
                    )
                    let users = try modelContext.fetch(userFetch)

                    if let user = users.first {
                        let checkIn = CheckIn(
                            user: user,
                            timestamp: apiCheckIn.timestamp,
                            mentalScore: apiCheckIn.mentalScore,
                            bodyScore: apiCheckIn.bodyScore,
                            moodScore: apiCheckIn.moodScore,
                            latitude: apiCheckIn.latitude,
                            longitude: apiCheckIn.longitude,
                            locationName: apiCheckIn.locationName,
                            address: apiCheckIn.address,
                            isManualCheckIn: apiCheckIn.isManual ?? true,
                            syncId: apiCheckIn.id,
                            syncStatus: .synced,
                            syncedAt: Date()
                        )
                        modelContext.insert(checkIn)
                        syncedCount += 1
                    }
                } else if let existingCheckIn = existingCheckIns.first {
                    // Update existing check-in if server has newer data
                    // For now, we assume server is authoritative
                    existingCheckIn.mentalScore = apiCheckIn.mentalScore
                    existingCheckIn.bodyScore = apiCheckIn.bodyScore
                    existingCheckIn.moodScore = apiCheckIn.moodScore
                    existingCheckIn.syncStatus = .synced
                    existingCheckIn.syncedAt = Date()
                    syncedCount += 1
                }
            }

            try modelContext.save()
            lastSyncedAt = Date()

            if AppConfig.shared.isLoggingEnabled {
                print("Downloaded \(syncedCount) check-ins from server")
            }

            return syncedCount
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("Failed to download check-ins: \(error)")
            }
            syncError = error.localizedDescription
            return 0
        }
    }

    // MARK: - Sync All Pending

    /// Sync all pending (unsynced) check-ins to server
    /// - Parameter modelContext: SwiftData context
    /// - Returns: Number of successfully synced check-ins
    func syncPendingCheckIns(modelContext: ModelContext) async -> Int {
        guard AuthManager.shared.isAuthenticated else {
            syncError = "Not authenticated"
            return 0
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            // Find all check-ins that need syncing
            let fetchDescriptor = FetchDescriptor<CheckIn>(
                predicate: #Predicate<CheckIn> { checkIn in
                    checkIn.syncStatusRaw == "new" ||
                    checkIn.syncStatusRaw == "modified" ||
                    checkIn.syncStatusRaw == "failed"
                },
                sortBy: [SortDescriptor(\.timestamp, order: .forward)]
            )

            let pendingCheckIns = try modelContext.fetch(fetchDescriptor)

            if AppConfig.shared.isLoggingEnabled {
                print("Found \(pendingCheckIns.count) pending check-ins to sync")
            }

            var successCount = 0

            for checkIn in pendingCheckIns {
                let success = await uploadCheckIn(checkIn, modelContext: modelContext)
                if success {
                    successCount += 1

                    // Upload selfie if present
                    if checkIn.selfieData != nil {
                        _ = await uploadSelfie(for: checkIn, modelContext: modelContext)
                    }
                }
            }

            lastSyncedAt = Date()
            return successCount
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("Failed to fetch pending check-ins: \(error)")
            }
            syncError = error.localizedDescription
            return 0
        }
    }

    // MARK: - Full Sync

    /// Perform a full sync: upload pending, then download new
    /// - Parameter modelContext: SwiftData context
    func performFullSync(modelContext: ModelContext) async {
        guard AuthManager.shared.isAuthenticated else {
            syncError = "Not authenticated"
            return
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        // First, upload any pending check-ins
        let uploaded = await syncPendingCheckIns(modelContext: modelContext)

        // Then download any new check-ins from server
        let downloaded = await downloadCheckIns(since: lastSyncedAt, modelContext: modelContext)

        if AppConfig.shared.isLoggingEnabled {
            print("Full sync complete: uploaded \(uploaded), downloaded \(downloaded)")
        }

        lastSyncedAt = Date()
    }
}
