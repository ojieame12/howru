import Foundation
import SwiftData
import CoreLocation

@Model
final class CheckIn {
    @Attribute(.unique) var id: UUID
    var user: User?
    var timestamp: Date

    // The three sliders (1-5 scale)
    var mentalScore: Int
    var bodyScore: Int
    var moodScore: Int

    // Optional selfie (stored as data, ephemeral)
    @Attribute(.externalStorage) var selfieData: Data?
    var selfieExpiresAt: Date?

    // Location (optional)
    var latitude: Double?
    var longitude: Double?
    var locationName: String?  // "Near Cape Town" - city level
    var address: String?       // Full street address for alerts

    // Status
    var isManualCheckIn: Bool  // true = user initiated, false = poke response

    // Sync fields
    var syncId: String?              // Server-assigned ID
    var syncStatusRaw: String        // Raw string for SyncStatus (SwiftData compatible)
    var syncedAt: Date?              // Last successful sync timestamp

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .new }
        set { syncStatusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        user: User? = nil,
        timestamp: Date = Date(),
        mentalScore: Int = 3,
        bodyScore: Int = 3,
        moodScore: Int = 3,
        selfieData: Data? = nil,
        selfieExpiresAt: Date? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        locationName: String? = nil,
        address: String? = nil,
        isManualCheckIn: Bool = true,
        syncId: String? = nil,
        syncStatus: SyncStatus = .new,
        syncedAt: Date? = nil
    ) {
        self.id = id
        self.user = user
        self.timestamp = timestamp
        self.mentalScore = mentalScore
        self.bodyScore = bodyScore
        self.moodScore = moodScore
        self.selfieData = selfieData
        self.selfieExpiresAt = selfieExpiresAt
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
        self.address = address
        self.isManualCheckIn = isManualCheckIn
        self.syncId = syncId
        self.syncStatusRaw = syncStatus.rawValue
        self.syncedAt = syncedAt
    }
}

// MARK: - Convenience
extension CheckIn {
    var hasLocation: Bool {
        latitude != nil && longitude != nil
    }

    var hasSelfie: Bool {
        guard let data = selfieData, let expires = selfieExpiresAt else { return false }
        return !data.isEmpty && expires > Date()
    }

    var averageScore: Double {
        Double(mentalScore + bodyScore + moodScore) / 3.0
    }
}
