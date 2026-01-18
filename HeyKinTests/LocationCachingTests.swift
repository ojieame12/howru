import XCTest
import SwiftData
@testable import HowRU

/// Tests for User location caching behavior
@MainActor
final class LocationCachingTests: XCTestCase {

    var container: TestContainer!

    override func setUp() async throws {
        container = try TestContainer()
    }

    override func tearDown() async throws {
        try container.reset()
        container = nil
    }

    // MARK: - updateLastKnownLocation Tests

    func testUpdateLastKnownLocation_copiesCheckInLocation() {
        // Given
        let user = Factories.user()
        let checkIn = Factories.checkInWithLocation(
            timestamp: Date(),
            latitude: -33.9249,
            longitude: 18.4241,
            locationName: "Near Cape Town",
            address: "123 Main St, Cape Town"
        )

        // When
        user.updateLastKnownLocation(from: checkIn)

        // Then
        XCTAssertEqual(user.lastKnownLatitude, -33.9249, accuracy: 0.0001)
        XCTAssertEqual(user.lastKnownLongitude, 18.4241, accuracy: 0.0001)
        XCTAssertEqual(user.lastKnownAddress, "123 Main St, Cape Town")
        XCTAssertEqual(user.lastKnownLocationAt, checkIn.timestamp)
    }

    func testUpdateLastKnownLocation_prefersAddressOverLocationName() {
        // Given: Check-in with both address and locationName
        let user = Factories.user()
        let checkIn = Factories.checkIn(
            latitude: -33.9249,
            longitude: 18.4241,
            locationName: "Near Cape Town",
            address: "123 Main St, Cape Town"
        )

        // When
        user.updateLastKnownLocation(from: checkIn)

        // Then
        XCTAssertEqual(user.lastKnownAddress, "123 Main St, Cape Town", "Should prefer address over locationName")
    }

    func testUpdateLastKnownLocation_fallsBackToLocationName() {
        // Given: Check-in with only locationName (no address)
        let user = Factories.user()
        let checkIn = Factories.checkIn(
            latitude: -33.9249,
            longitude: 18.4241,
            locationName: "Near Cape Town",
            address: nil
        )

        // When
        user.updateLastKnownLocation(from: checkIn)

        // Then
        XCTAssertEqual(user.lastKnownAddress, "Near Cape Town", "Should fall back to locationName")
    }

    func testUpdateLastKnownLocation_doesNotUpdateWithoutLocation() {
        // Given: User with existing location, check-in without location
        let user = Factories.user(
            lastKnownLatitude: -33.9249,
            lastKnownLongitude: 18.4241,
            lastKnownAddress: "Original Address",
            lastKnownLocationAt: Date().addingTimeInterval(-3600)
        )
        let originalAddress = user.lastKnownAddress
        let originalTimestamp = user.lastKnownLocationAt

        let checkInWithoutLocation = Factories.checkIn(
            latitude: nil,
            longitude: nil,
            locationName: nil,
            address: nil
        )

        // When
        user.updateLastKnownLocation(from: checkInWithoutLocation)

        // Then: Original location should be preserved
        XCTAssertEqual(user.lastKnownAddress, originalAddress)
        XCTAssertEqual(user.lastKnownLocationAt, originalTimestamp)
    }

    func testUpdateLastKnownLocation_usesCheckInTimestamp() {
        // Given: Check-in from 2 hours ago
        let user = Factories.user()
        let twoHoursAgo = Date().addingTimeInterval(-2 * 3600)
        let checkIn = Factories.checkInWithLocation(timestamp: twoHoursAgo)

        // When
        user.updateLastKnownLocation(from: checkIn)

        // Then: Should use check-in timestamp, not current time
        XCTAssertEqual(user.lastKnownLocationAt, twoHoursAgo, "Should use check-in timestamp, not NOW()")
    }

    // MARK: - hasRecentLocation Tests

    func testHasRecentLocation_within7Days_returnsTrue() {
        // Given: Location from 3 days ago
        let user = Factories.user(
            lastKnownLatitude: -33.9249,
            lastKnownLongitude: 18.4241,
            lastKnownLocationAt: Date().addingTimeInterval(-3 * 24 * 3600)
        )

        // When/Then
        XCTAssertTrue(user.hasRecentLocation, "3-day-old location should be considered recent")
    }

    func testHasRecentLocation_exactly7Days_returnsTrue() {
        // Given: Location from exactly 6 days, 23 hours ago (just under 7 days)
        let justUnder7Days = Date().addingTimeInterval(-((7 * 24 * 3600) - 3600))
        let user = Factories.user(
            lastKnownLatitude: -33.9249,
            lastKnownLongitude: 18.4241,
            lastKnownLocationAt: justUnder7Days
        )

        // When/Then
        XCTAssertTrue(user.hasRecentLocation, "Location just under 7 days should be recent")
    }

    func testHasRecentLocation_over7Days_returnsFalse() {
        // Given: Location from 8 days ago
        let user = Factories.user(
            lastKnownLatitude: -33.9249,
            lastKnownLongitude: 18.4241,
            lastKnownLocationAt: Date().addingTimeInterval(-8 * 24 * 3600)
        )

        // When/Then
        XCTAssertFalse(user.hasRecentLocation, "8-day-old location should not be recent")
    }

    func testHasRecentLocation_noLocation_returnsFalse() {
        // Given: User with no location
        let user = Factories.user(
            lastKnownLatitude: nil,
            lastKnownLongitude: nil,
            lastKnownLocationAt: nil
        )

        // When/Then
        XCTAssertFalse(user.hasRecentLocation, "No location should return false")
    }

    func testHasRecentLocation_locationWithoutTimestamp_returnsFalse() {
        // Given: User with coordinates but no timestamp (edge case)
        let user = Factories.user(
            lastKnownLatitude: -33.9249,
            lastKnownLongitude: 18.4241,
            lastKnownLocationAt: nil
        )

        // When/Then
        XCTAssertFalse(user.hasRecentLocation, "Location without timestamp should return false")
    }

    // MARK: - Map URL Tests

    func testLastKnownLocationMapURL_generatesValidGoogleMapsURL() {
        // Given
        let user = Factories.user(
            lastKnownLatitude: -33.9249,
            lastKnownLongitude: 18.4241
        )

        // When
        let url = user.lastKnownLocationMapURL

        // Then
        XCTAssertNotNil(url)
        XCTAssertTrue(url?.absoluteString.contains("maps.google.com") ?? false)
        XCTAssertTrue(url?.absoluteString.contains("-33.9249") ?? false)
        XCTAssertTrue(url?.absoluteString.contains("18.4241") ?? false)
    }

    func testLastKnownLocationMapURL_noLocation_returnsNil() {
        // Given
        let user = Factories.user(
            lastKnownLatitude: nil,
            lastKnownLongitude: nil
        )

        // When/Then
        XCTAssertNil(user.lastKnownLocationMapURL)
    }

    func testLastKnownLocationAppleMapsURL_generatesValidAppleMapsURL() {
        // Given
        let user = Factories.user(
            lastKnownLatitude: -33.9249,
            lastKnownLongitude: 18.4241
        )

        // When
        let url = user.lastKnownLocationAppleMapsURL

        // Then
        XCTAssertNotNil(url)
        XCTAssertTrue(url?.absoluteString.contains("maps.apple.com") ?? false)
    }

    // MARK: - CheckIn.hasLocation Tests

    func testCheckInHasLocation_withBothCoordinates_returnsTrue() {
        let checkIn = Factories.checkIn(
            latitude: -33.9249,
            longitude: 18.4241
        )
        XCTAssertTrue(checkIn.hasLocation)
    }

    func testCheckInHasLocation_missingLatitude_returnsFalse() {
        let checkIn = Factories.checkIn(
            latitude: nil,
            longitude: 18.4241
        )
        XCTAssertFalse(checkIn.hasLocation)
    }

    func testCheckInHasLocation_missingLongitude_returnsFalse() {
        let checkIn = Factories.checkIn(
            latitude: -33.9249,
            longitude: nil
        )
        XCTAssertFalse(checkIn.hasLocation)
    }

    func testCheckInHasLocation_bothMissing_returnsFalse() {
        let checkIn = Factories.checkIn(
            latitude: nil,
            longitude: nil
        )
        XCTAssertFalse(checkIn.hasLocation)
    }

    // MARK: - Integration: CheckIn → User Location Update Flow

    func testFullLocationCachingFlow() async throws {
        // Given: User with no location
        let user = container.insert(Factories.checker())
        XCTAssertNil(user.lastKnownLatitude)
        XCTAssertNil(user.lastKnownLocationAt)

        // When: User checks in with location
        let checkIn = container.insert(Factories.checkInWithLocation(
            user: user,
            timestamp: Date(),
            latitude: -33.9249,
            longitude: 18.4241,
            locationName: "Near Cape Town",
            address: "123 Main St, Cape Town"
        ))
        user.updateLastKnownLocation(from: checkIn)

        // Then: User's cached location is updated
        XCTAssertEqual(user.lastKnownLatitude, -33.9249, accuracy: 0.0001)
        XCTAssertEqual(user.lastKnownLongitude, 18.4241, accuracy: 0.0001)
        XCTAssertEqual(user.lastKnownAddress, "123 Main St, Cape Town")
        XCTAssertTrue(user.hasRecentLocation)
        XCTAssertNotNil(user.lastKnownLocationMapURL)

        // When: User checks in again from new location
        let newCheckIn = container.insert(Factories.checkInWithLocation(
            user: user,
            timestamp: Date().addingTimeInterval(3600), // 1 hour later
            latitude: 40.7128,
            longitude: -74.0060,
            address: "New York, NY"
        ))
        user.updateLastKnownLocation(from: newCheckIn)

        // Then: Location is updated to new position
        XCTAssertEqual(user.lastKnownLatitude, 40.7128, accuracy: 0.0001)
        XCTAssertEqual(user.lastKnownLongitude, -74.0060, accuracy: 0.0001)
        XCTAssertEqual(user.lastKnownAddress, "New York, NY")
    }
}
