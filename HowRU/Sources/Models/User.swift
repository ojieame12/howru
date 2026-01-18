import Foundation
import SwiftData

@Model
final class User {
    @Attribute(.unique) var id: UUID
    var phoneNumber: String?
    var email: String?
    var name: String
    var isChecker: Bool  // true = checking in, false = supporter only
    var createdAt: Date
    var lastActiveAt: Date
    var profileImageData: Data?
    var address: String?

    // Last known location (cached from most recent check-in for quick alert lookup)
    var lastKnownLatitude: Double?
    var lastKnownLongitude: Double?
    var lastKnownAddress: String?
    var lastKnownLocationAt: Date?

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \CheckIn.user)
    var checkIns: [CheckIn] = []

    @Relationship(deleteRule: .cascade, inverse: \CircleLink.checker)
    var supportersLinks: [CircleLink] = []  // People watching this user

    @Relationship(deleteRule: .cascade, inverse: \CircleLink.supporter)
    var watchingLinks: [CircleLink] = []  // People this user watches

    @Relationship(deleteRule: .cascade, inverse: \Schedule.user)
    var schedules: [Schedule] = []

    init(
        id: UUID = UUID(),
        phoneNumber: String? = nil,
        email: String? = nil,
        name: String,
        isChecker: Bool = true,
        createdAt: Date = Date(),
        lastActiveAt: Date = Date(),
        profileImageData: Data? = nil,
        address: String? = nil,
        lastKnownLatitude: Double? = nil,
        lastKnownLongitude: Double? = nil,
        lastKnownAddress: String? = nil,
        lastKnownLocationAt: Date? = nil
    ) {
        self.id = id
        self.phoneNumber = phoneNumber
        self.email = email
        self.name = name
        self.isChecker = isChecker
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.profileImageData = profileImageData
        self.address = address
        self.lastKnownLatitude = lastKnownLatitude
        self.lastKnownLongitude = lastKnownLongitude
        self.lastKnownAddress = lastKnownAddress
        self.lastKnownLocationAt = lastKnownLocationAt
    }
}

// MARK: - Location Helpers
extension User {
    /// Updates last known location from a check-in (call after saving check-in)
    func updateLastKnownLocation(from checkIn: CheckIn) {
        if checkIn.hasLocation {
            lastKnownLatitude = checkIn.latitude
            lastKnownLongitude = checkIn.longitude
            lastKnownAddress = checkIn.address ?? checkIn.locationName
            lastKnownLocationAt = checkIn.timestamp
        }
    }

    /// Has a recent location (within last 7 days)
    var hasRecentLocation: Bool {
        guard let locationDate = lastKnownLocationAt else { return false }
        return Calendar.current.dateComponents([.day], from: locationDate, to: Date()).day ?? 8 < 7
    }

    /// Google Maps URL for last known location
    var lastKnownLocationMapURL: URL? {
        guard let lat = lastKnownLatitude, let lng = lastKnownLongitude else { return nil }
        return URL(string: "https://maps.google.com/maps?q=\(lat),\(lng)")
    }

    /// Apple Maps URL for last known location
    var lastKnownLocationAppleMapsURL: URL? {
        guard let lat = lastKnownLatitude, let lng = lastKnownLongitude else { return nil }
        return URL(string: "https://maps.apple.com/?ll=\(lat),\(lng)")
    }
}
