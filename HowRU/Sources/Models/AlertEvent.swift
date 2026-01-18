import Foundation
import SwiftData

enum AlertLevel: String, Codable {
    case reminder       // "Time to check in"
    case softAlert      // "Haven't heard from you"
    case hardAlert      // "Missed check-in - contacting supporters"
    case escalation     // "No response - emergency contacts notified"
}

extension AlertLevel {
    var rank: Int {
        switch self {
        case .reminder: return 0
        case .softAlert: return 1
        case .hardAlert: return 2
        case .escalation: return 3
        }
    }
}

enum AlertStatus: String, Codable {
    case pending
    case sent
    case acknowledged
    case resolved       // User checked in
    case cancelled      // Manually dismissed
}

@Model
final class AlertEvent {
    @Attribute(.unique) var id: UUID

    var checkerId: UUID
    var checkerName: String

    var level: AlertLevel
    var status: AlertStatus

    var triggeredAt: Date
    var resolvedAt: Date?

    // Context when alert was triggered
    var lastCheckInAt: Date?
    var lastKnownLocation: String?

    // Who was notified
    var notifiedSupporterIds: [UUID]

    // Sync fields
    var syncId: String?              // Server-assigned ID
    var checkerServerId: String?     // Server user ID of the checker (for poke/call actions)
    var syncStatusRaw: String        // Raw string for SyncStatus (SwiftData compatible)
    var syncedAt: Date?              // Last successful sync timestamp

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .new }
        set { syncStatusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        checkerId: UUID,
        checkerName: String,
        level: AlertLevel,
        status: AlertStatus = .pending,
        triggeredAt: Date = Date(),
        resolvedAt: Date? = nil,
        lastCheckInAt: Date? = nil,
        lastKnownLocation: String? = nil,
        notifiedSupporterIds: [UUID] = [],
        syncId: String? = nil,
        checkerServerId: String? = nil,
        syncStatus: SyncStatus = .new,
        syncedAt: Date? = nil
    ) {
        self.id = id
        self.checkerId = checkerId
        self.checkerName = checkerName
        self.level = level
        self.status = status
        self.triggeredAt = triggeredAt
        self.resolvedAt = resolvedAt
        self.lastCheckInAt = lastCheckInAt
        self.lastKnownLocation = lastKnownLocation
        self.notifiedSupporterIds = notifiedSupporterIds
        self.syncId = syncId
        self.checkerServerId = checkerServerId
        self.syncStatusRaw = syncStatus.rawValue
        self.syncedAt = syncedAt
    }
}

extension AlertEvent {
    var isActive: Bool {
        status == .pending || status == .sent
    }

    var timeSinceLastCheckIn: TimeInterval? {
        guard let last = lastCheckInAt else { return nil }
        return triggeredAt.timeIntervalSince(last)
    }
}
