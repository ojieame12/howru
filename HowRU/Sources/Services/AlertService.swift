import Foundation
import SwiftData

/// Service for managing alert escalation logic
@MainActor
@Observable
final class AlertService {
    private let modelContext: ModelContext
    private let notificationService: NotificationService
    private let scheduleService: ScheduleService
    private let alertSyncService: AlertSyncService

    init(modelContext: ModelContext, notificationService: NotificationService, scheduleService: ScheduleService, alertSyncService: AlertSyncService = AlertSyncService()) {
        self.modelContext = modelContext
        self.notificationService = notificationService
        self.scheduleService = scheduleService
        self.alertSyncService = alertSyncService
    }

    // MARK: - Sync

    /// Fetch alerts from server
    func syncAlerts() async -> Int {
        return await alertSyncService.fetchAlerts(modelContext: modelContext)
    }

    // MARK: - Alert Evaluation

    /// Check and process alerts for a user
    func evaluateAlerts(for user: User, checkIns: [CheckIn], circleLinks: [CircleLink]) {
        // Get user's latest check-in
        let userCheckIns = checkIns
            .filter { $0.user?.id == user.id }
            .sorted { $0.timestamp > $1.timestamp }
        let lastCheckIn = userCheckIns.first

        // Check if window missed
        guard let missedTime = scheduleService.missedWindowTime(for: user, lastCheckIn: lastCheckIn) else {
            return // Not missed, no alerts needed
        }

        // Calculate escalation level
        let level = calculateAlertLevel(since: missedTime)

        // Get supporters for this user
        let supporters = circleLinks.filter { $0.checker?.id == user.id && $0.isActive }
        let supporterIds = supporters.compactMap { $0.supporter?.id }

        // Create or update alert events
        processEscalation(level: level, for: user, supporters: supporters, supporterIds: supporterIds, lastCheckIn: lastCheckIn)
    }

    /// Determine alert level based on time since last check-in
    func calculateAlertLevel(since lastCheckIn: Date) -> AlertLevel {
        let hoursSince = Date().timeIntervalSince(lastCheckIn) / 3600

        switch hoursSince {
        case ..<24:
            return .reminder
        case 24..<36:
            return .softAlert
        case 36..<48:
            return .hardAlert
        default:
            return .escalation
        }
    }

    // MARK: - Alert Processing

    private func processEscalation(level: AlertLevel, for user: User, supporters: [CircleLink], supporterIds: [UUID], lastCheckIn: CheckIn?) {
        // Check for existing active alert
        let existingAlert = findActiveAlert(for: user.id)

        if let alert = existingAlert {
            // Update existing alert if level increased
            if level.rank > alert.level.rank {
                updateAlert(alert, to: level, supporterIds: supporterIds)
            }
        } else {
            // Create new alert
            createAlert(
                for: user,
                level: level,
                supporterIds: supporterIds,
                lastCheckIn: lastCheckIn
            )
        }

        // Send notifications based on level
        sendNotifications(level: level, for: user, supporters: supporters, lastCheckIn: lastCheckIn)
    }

    private func createAlert(for user: User, level: AlertLevel, supporterIds: [UUID], lastCheckIn: CheckIn?) {
        let alert = AlertEvent(
            checkerId: user.id,
            checkerName: user.name,
            level: level,
            lastCheckInAt: lastCheckIn?.timestamp,
            notifiedSupporterIds: level == .reminder ? [] : supporterIds
        )
        modelContext.insert(alert)
    }

    private func updateAlert(_ alert: AlertEvent, to level: AlertLevel, supporterIds: [UUID]) {
        alert.level = level
        alert.status = .pending

        // Add new supporter IDs if escalating
        let newIds = supporterIds.filter { !alert.notifiedSupporterIds.contains($0) }
        alert.notifiedSupporterIds.append(contentsOf: newIds)
    }

    private func sendNotifications(level: AlertLevel, for user: User, supporters: [CircleLink], lastCheckIn: CheckIn?) {
        switch level {
        case .reminder:
            // Only local notification (handled elsewhere)
            break

        case .softAlert:
            // Notify first supporter
            if let firstSupporter = supporters.first,
               shouldSendPush(for: firstSupporter, level: level) {
                notificationService.scheduleSoftAlert(checkerName: user.name)
            }

        case .hardAlert:
            // Notify multiple supporters with urgency
            let hoursSince = Int(Date().timeIntervalSince(lastCheckIn?.timestamp ?? user.createdAt) / 3600)
            for supporter in supporters.prefix(3) {
                if shouldSendPush(for: supporter, level: level) {
                    notificationService.scheduleHardAlert(checkerName: user.name, missedHours: hoursSince)
                }
            }

        case .escalation:
            // Notify all supporters
            let hoursSince = Int(Date().timeIntervalSince(lastCheckIn?.timestamp ?? user.createdAt) / 3600)
            for supporter in supporters {
                if shouldSendPush(for: supporter, level: level) {
                    notificationService.scheduleHardAlert(checkerName: user.name, missedHours: hoursSince)
                }
            }
        }
    }

    private func shouldSendPush(for supporter: CircleLink, level: AlertLevel) -> Bool {
        if !supporter.alertViaPush && !supporter.alertViaSMS && !supporter.alertViaEmail {
            return false
        }

        let urgentOnly = supporter.alertViaPush && !supporter.alertViaSMS && !supporter.alertViaEmail
        if urgentOnly {
            return level == .hardAlert || level == .escalation
        }

        return supporter.alertViaPush
    }

    // MARK: - Alert Resolution

    /// Mark alerts as resolved when user checks in
    func resolveAlerts(for userId: UUID) {
        let descriptor = FetchDescriptor<AlertEvent>(
            predicate: #Predicate { alert in
                alert.checkerId == userId && alert.resolvedAt == nil
            }
        )

        guard let alerts = try? modelContext.fetch(descriptor) else { return }

        for alert in alerts {
            alert.status = .resolved
            alert.resolvedAt = Date()

            // Sync resolution to server
            if AuthManager.shared.isAuthenticated {
                Task {
                    _ = await alertSyncService.resolveAlert(
                        alert,
                        resolution: "checked_in",
                        modelContext: modelContext
                    )
                }
            }
        }
    }

    /// Acknowledge an alert (supporter saw it)
    func acknowledgeAlert(_ alert: AlertEvent) {
        alert.status = .acknowledged

        // Sync acknowledgment to server
        if AuthManager.shared.isAuthenticated {
            Task {
                _ = await alertSyncService.acknowledgeAlert(alert, modelContext: modelContext)
            }
        }
    }

    /// Cancel an alert manually
    func cancelAlert(_ alert: AlertEvent) {
        alert.status = .cancelled
        alert.resolvedAt = Date()

        // Sync cancellation to server (uses resolve endpoint)
        if AuthManager.shared.isAuthenticated {
            Task {
                _ = await alertSyncService.resolveAlert(
                    alert,
                    resolution: "false_alarm",
                    modelContext: modelContext
                )
            }
        }
    }

    // MARK: - Alert Queries

    func activeAlerts(for userId: UUID) -> [AlertEvent] {
        let descriptor = FetchDescriptor<AlertEvent>(
            predicate: #Predicate { alert in
                alert.checkerId == userId && alert.resolvedAt == nil
            },
            sortBy: [SortDescriptor(\.triggeredAt, order: .reverse)]
        )

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func alertsNeedingAttention(for supporterId: UUID) -> [AlertEvent] {
        // Find alerts where this supporter is in the notified list
        let descriptor = FetchDescriptor<AlertEvent>(
            predicate: #Predicate { alert in
                alert.resolvedAt == nil
            },
            sortBy: [SortDescriptor(\.triggeredAt, order: .reverse)]
        )

        guard let alerts = try? modelContext.fetch(descriptor) else { return [] }

        return alerts.filter { $0.notifiedSupporterIds.contains(supporterId) }
    }

    // MARK: - Helpers

    private func findActiveAlert(for checkerId: UUID) -> AlertEvent? {
        let descriptor = FetchDescriptor<AlertEvent>(
            predicate: #Predicate { alert in
                alert.checkerId == checkerId && alert.resolvedAt == nil
            }
        )

        return try? modelContext.fetch(descriptor).first
    }
}
