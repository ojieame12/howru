import Foundation
import SwiftData

@Model
final class Poke {
    @Attribute(.unique) var id: UUID

    // Who sent the poke
    var fromSupporterId: UUID
    var fromName: String

    // Who received the poke
    var toCheckerId: UUID

    // Status
    var sentAt: Date
    var seenAt: Date?
    var respondedAt: Date?  // When they checked in after poke

    // Optional message
    var message: String?

    // Sync fields
    var syncId: String?              // Server-assigned ID
    var fromSupporterServerId: String?  // Server user ID of the sender (for matching to CircleLink)
    var syncStatusRaw: String        // Raw string for SyncStatus (SwiftData compatible)
    var syncedAt: Date?              // Last successful sync timestamp

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .new }
        set { syncStatusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        fromSupporterId: UUID,
        fromName: String,
        toCheckerId: UUID,
        sentAt: Date = Date(),
        seenAt: Date? = nil,
        respondedAt: Date? = nil,
        message: String? = nil,
        syncId: String? = nil,
        fromSupporterServerId: String? = nil,
        syncStatus: SyncStatus = .new,
        syncedAt: Date? = nil
    ) {
        self.id = id
        self.fromSupporterId = fromSupporterId
        self.fromName = fromName
        self.toCheckerId = toCheckerId
        self.sentAt = sentAt
        self.seenAt = seenAt
        self.respondedAt = respondedAt
        self.message = message
        self.syncId = syncId
        self.fromSupporterServerId = fromSupporterServerId
        self.syncStatusRaw = syncStatus.rawValue
        self.syncedAt = syncedAt
    }
}

extension Poke {
    var isPending: Bool {
        respondedAt == nil
    }

    var wasAcknowledged: Bool {
        seenAt != nil
    }
}
