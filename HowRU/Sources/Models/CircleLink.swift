import Foundation
import SwiftData

/// Represents the relationship between a checker and their supporter
@Model
final class CircleLink {
    @Attribute(.unique) var id: UUID

    // The person checking in
    var checker: User?

    // The person watching/supporting
    var supporter: User?

    // Supporter contact info (for non-app users)
    var supporterPhone: String?
    var supporterEmail: String?
    var supporterName: String

    // Permissions
    var canSeeMood: Bool
    var canSeeLocation: Bool
    var canSeeSelfie: Bool
    var canPoke: Bool

    // Alert preferences
    var alertViaPush: Bool
    var alertViaSMS: Bool
    var alertViaEmail: Bool

    // Status
    var isActive: Bool
    var invitedAt: Date
    var acceptedAt: Date?

    // Sync fields
    var syncId: String?              // Server-assigned ID for this circle link
    var checkerServerId: String?     // Server user ID of the checker (for pokes)
    var supporterServerId: String?   // Server user ID of the supporter (for pokes)
    var syncStatusRaw: String        // Raw string for SyncStatus (SwiftData compatible)
    var syncedAt: Date?              // Last successful sync timestamp

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .new }
        set { syncStatusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        checker: User? = nil,
        supporter: User? = nil,
        supporterPhone: String? = nil,
        supporterEmail: String? = nil,
        supporterName: String,
        canSeeMood: Bool = true,
        canSeeLocation: Bool = false,
        canSeeSelfie: Bool = true,
        canPoke: Bool = true,
        alertViaPush: Bool = true,
        alertViaSMS: Bool = false,
        alertViaEmail: Bool = false,
        isActive: Bool = true,
        invitedAt: Date = Date(),
        acceptedAt: Date? = nil,
        syncId: String? = nil,
        checkerServerId: String? = nil,
        supporterServerId: String? = nil,
        syncStatus: SyncStatus = .new,
        syncedAt: Date? = nil
    ) {
        self.id = id
        self.checker = checker
        self.supporter = supporter
        self.supporterPhone = supporterPhone
        self.supporterEmail = supporterEmail
        self.supporterName = supporterName
        self.canSeeMood = canSeeMood
        self.canSeeLocation = canSeeLocation
        self.canSeeSelfie = canSeeSelfie
        self.canPoke = canPoke
        self.alertViaPush = alertViaPush
        self.alertViaSMS = alertViaSMS
        self.alertViaEmail = alertViaEmail
        self.isActive = isActive
        self.invitedAt = invitedAt
        self.acceptedAt = acceptedAt
        self.syncId = syncId
        self.checkerServerId = checkerServerId
        self.supporterServerId = supporterServerId
        self.syncStatusRaw = syncStatus.rawValue
        self.syncedAt = syncedAt
    }
}

extension CircleLink {
    var isPending: Bool {
        acceptedAt == nil
    }

    var hasAppUser: Bool {
        supporter != nil
    }
}
