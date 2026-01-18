import Foundation
import SwiftData

/// Service for syncing alerts with the server
@MainActor
@Observable
final class AlertSyncService {
    // MARK: - Type Mapping

    /// Map backend alert type strings to iOS AlertLevel
    private static func alertLevel(from backendType: String) -> AlertLevel {
        switch backendType {
        case "soft": return .softAlert
        case "hard": return .hardAlert
        case "reminder": return .reminder
        case "escalation": return .escalation
        default: return .softAlert
        }
    }
    // MARK: - Properties

    private let apiClient: APIClient
    private(set) var isSyncing = false
    private(set) var lastSyncedAt: Date?
    var syncError: String?

    // MARK: - Initialization

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    // MARK: - Fetch Alerts

    /// Fetch alerts from server (alerts where current user is a supporter)
    /// - Parameter modelContext: SwiftData context
    /// - Returns: Number of alerts fetched/updated
    func fetchAlerts(modelContext: ModelContext) async -> Int {
        guard AuthManager.shared.isAuthenticated else {
            syncError = "Not authenticated"
            return 0
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            let response: AlertsResponse = try await apiClient.get("/alerts")

            // Get current user to set as notified supporter
            let userFetch = FetchDescriptor<User>(
                predicate: #Predicate { $0.isChecker == true }
            )
            let users = try modelContext.fetch(userFetch)
            let currentUserId = users.first?.id ?? UUID()

            var syncedCount = 0

            for apiAlert in response.alerts {
                // Check if we already have this alert locally
                let existingAlerts = try modelContext.fetch(FetchDescriptor<AlertEvent>())
                let existingAlert = existingAlerts.first { $0.syncId == apiAlert.id }

                if let alert = existingAlert {
                    // Update existing alert - including level for escalation changes
                    alert.level = Self.alertLevel(from: apiAlert.type)
                    alert.status = AlertStatus(rawValue: apiAlert.status) ?? .pending
                    alert.resolvedAt = apiAlert.resolvedAt
                    alert.syncStatus = .synced
                    alert.syncedAt = Date()
                    // Ensure current user is in notified list
                    if !alert.notifiedSupporterIds.contains(currentUserId) {
                        alert.notifiedSupporterIds.append(currentUserId)
                    }
                    syncedCount += 1
                } else {
                    // Create new local alert from server data
                    // Store checker server ID for follow-up actions
                    // Set current user as notified supporter (since we're fetching alerts for supporters)
                    let newAlert = AlertEvent(
                        checkerId: UUID(), // Local UUID (we track server ID via checkerServerId)
                        checkerName: apiAlert.checkerName ?? "Unknown",
                        level: Self.alertLevel(from: apiAlert.type),
                        status: AlertStatus(rawValue: apiAlert.status) ?? .pending,
                        triggeredAt: apiAlert.triggeredAt,
                        resolvedAt: apiAlert.resolvedAt,
                        lastCheckInAt: apiAlert.lastCheckInAt,
                        lastKnownLocation: apiAlert.lastKnownLocation,
                        notifiedSupporterIds: [currentUserId],
                        syncId: apiAlert.id,
                        checkerServerId: apiAlert.checkerId,
                        syncStatus: .synced,
                        syncedAt: Date()
                    )
                    modelContext.insert(newAlert)
                    syncedCount += 1
                }
            }

            try modelContext.save()
            lastSyncedAt = Date()

            if AppConfig.shared.isLoggingEnabled {
                print("Synced \(syncedCount) alerts from server")
            }

            return syncedCount
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("Failed to fetch alerts: \(error)")
            }
            syncError = error.localizedDescription
            return 0
        }
    }

    // MARK: - Resolve Alert

    /// Mark an alert as resolved on the server
    /// - Parameters:
    ///   - alert: The alert to resolve
    ///   - resolution: How the alert was resolved (checked_in, contacted, safe_confirmed, false_alarm, other)
    ///   - notes: Optional notes about the resolution
    ///   - modelContext: SwiftData context
    /// - Returns: True if successful
    func resolveAlert(
        _ alert: AlertEvent,
        resolution: String = "safe_confirmed",
        notes: String? = nil,
        modelContext: ModelContext
    ) async -> Bool {
        guard AuthManager.shared.isAuthenticated else {
            syncError = "Not authenticated"
            return false
        }

        guard let syncId = alert.syncId else {
            // Not synced to server, just resolve locally
            alert.status = .resolved
            alert.resolvedAt = Date()
            try? modelContext.save()
            return true
        }

        do {
            // Backend requires resolution field (checked_in, contacted, safe_confirmed, false_alarm, other)
            let body = ResolveAlertBody(resolvedAt: Date(), resolution: resolution, notes: notes)
            let _: SuccessResponse = try await apiClient.post("/alerts/\(syncId)/resolve", body: body)

            alert.status = .resolved
            alert.resolvedAt = Date()
            alert.syncStatus = .synced
            alert.syncedAt = Date()

            try modelContext.save()

            if AppConfig.shared.isLoggingEnabled {
                print("Alert resolved: \(syncId)")
            }

            return true
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("Failed to resolve alert: \(error)")
            }
            syncError = error.localizedDescription
            return false
        }
    }

    // MARK: - Acknowledge Alert

    /// Mark an alert as acknowledged on the server (supporter saw it)
    /// - Parameters:
    ///   - alert: The alert to acknowledge
    ///   - modelContext: SwiftData context
    /// - Returns: True if successful
    func acknowledgeAlert(_ alert: AlertEvent, modelContext: ModelContext) async -> Bool {
        guard AuthManager.shared.isAuthenticated else {
            syncError = "Not authenticated"
            return false
        }

        guard let syncId = alert.syncId else {
            // Not synced to server, just acknowledge locally
            alert.status = .acknowledged
            try? modelContext.save()
            return true
        }

        do {
            let _: SuccessResponse = try await apiClient.post("/alerts/\(syncId)/acknowledge")

            alert.status = .acknowledged
            alert.syncStatus = .synced
            alert.syncedAt = Date()

            try modelContext.save()

            if AppConfig.shared.isLoggingEnabled {
                print("Alert acknowledged: \(syncId)")
            }

            return true
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("Failed to acknowledge alert: \(error)")
            }
            syncError = error.localizedDescription
            return false
        }
    }

    // MARK: - Get Active Alert Count

    /// Get count of active alerts for the current user
    /// - Returns: Number of active alerts, or nil if failed
    func getActiveAlertCount() async -> Int? {
        guard AuthManager.shared.isAuthenticated else {
            syncError = "Not authenticated"
            return nil
        }

        do {
            // Backend uses /alerts - filter by pending/sent status for active alerts
            let response: AlertsResponse = try await apiClient.get("/alerts")
            let activeAlerts = response.alerts.filter { alert in
                alert.status == "pending" || alert.status == "sent"
            }
            return activeAlerts.count
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("Failed to get active alert count: \(error)")
            }
            syncError = error.localizedDescription
            return nil
        }
    }
}
