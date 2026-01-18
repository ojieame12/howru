import Foundation
@testable import HowRU

/// Test data factories for creating model instances
@MainActor
enum Factories {

    // MARK: - User Factory

    static func user(
        id: UUID = UUID(),
        name: String = "Test User",
        phoneNumber: String? = "+1234567890",
        email: String? = "test@example.com",
        isChecker: Bool = true,
        address: String? = nil,
        lastKnownLatitude: Double? = nil,
        lastKnownLongitude: Double? = nil,
        lastKnownAddress: String? = nil,
        lastKnownLocationAt: Date? = nil
    ) -> User {
        User(
            id: id,
            phoneNumber: phoneNumber,
            email: email,
            name: name,
            isChecker: isChecker,
            address: address,
            lastKnownLatitude: lastKnownLatitude,
            lastKnownLongitude: lastKnownLongitude,
            lastKnownAddress: lastKnownAddress,
            lastKnownLocationAt: lastKnownLocationAt
        )
    }

    static func checker(name: String = "Mom") -> User {
        user(name: name, isChecker: true)
    }

    static func supporter(name: String = "Supporter") -> User {
        user(name: name, isChecker: false)
    }

    // MARK: - Schedule Factory

    static func schedule(
        user: User? = nil,
        windowStartHour: Int = 7,
        windowStartMinute: Int = 0,
        windowEndHour: Int = 10,
        windowEndMinute: Int = 0,
        timezone: TimeZone = .current,
        activeDays: [Int] = [0, 1, 2, 3, 4, 5, 6],
        gracePeriodMinutes: Int = 30,
        reminderEnabled: Bool = true,
        reminderMinutesBefore: Int = 30,
        isActive: Bool = true
    ) -> Schedule {
        Schedule(
            user: user,
            windowStartHour: windowStartHour,
            windowStartMinute: windowStartMinute,
            windowEndHour: windowEndHour,
            windowEndMinute: windowEndMinute,
            timezoneIdentifier: timezone.identifier,
            activeDays: activeDays,
            gracePeriodMinutes: gracePeriodMinutes,
            reminderEnabled: reminderEnabled,
            reminderMinutesBefore: reminderMinutesBefore,
            isActive: isActive
        )
    }

    /// Morning schedule: 7am-10am
    static func morningSchedule(user: User? = nil, timezone: TimeZone = .current) -> Schedule {
        schedule(user: user, windowStartHour: 7, windowEndHour: 10, timezone: timezone)
    }

    /// Weekday-only schedule (Mon-Fri)
    static func weekdaySchedule(user: User? = nil) -> Schedule {
        schedule(user: user, activeDays: [1, 2, 3, 4, 5])
    }

    // MARK: - CheckIn Factory

    static func checkIn(
        user: User? = nil,
        timestamp: Date = Date(),
        mentalScore: Int = 3,
        bodyScore: Int = 3,
        moodScore: Int = 3,
        latitude: Double? = nil,
        longitude: Double? = nil,
        locationName: String? = nil,
        address: String? = nil,
        isManualCheckIn: Bool = true
    ) -> CheckIn {
        CheckIn(
            user: user,
            timestamp: timestamp,
            mentalScore: mentalScore,
            bodyScore: bodyScore,
            moodScore: moodScore,
            latitude: latitude,
            longitude: longitude,
            locationName: locationName,
            address: address,
            isManualCheckIn: isManualCheckIn
        )
    }

    /// Check-in with location
    static func checkInWithLocation(
        user: User? = nil,
        timestamp: Date = Date(),
        latitude: Double = -33.9249,
        longitude: Double = 18.4241,
        locationName: String = "Near Cape Town",
        address: String = "123 Main St, Cape Town"
    ) -> CheckIn {
        checkIn(
            user: user,
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            locationName: locationName,
            address: address
        )
    }

    // MARK: - CircleLink Factory

    static func circleLink(
        checker: User? = nil,
        supporter: User? = nil,
        supporterName: String = "Supporter",
        supporterPhone: String? = "+1234567890",
        supporterEmail: String? = "supporter@example.com",
        canSeeMood: Bool = true,
        canSeeLocation: Bool = false,
        canSeeSelfie: Bool = true,
        canPoke: Bool = true,
        alertViaPush: Bool = true,
        alertViaSMS: Bool = false,
        alertViaEmail: Bool = false,
        isActive: Bool = true,
        acceptedAt: Date? = Date()
    ) -> CircleLink {
        CircleLink(
            checker: checker,
            supporter: supporter,
            supporterPhone: supporterPhone,
            supporterEmail: supporterEmail,
            supporterName: supporterName,
            canSeeMood: canSeeMood,
            canSeeLocation: canSeeLocation,
            canSeeSelfie: canSeeSelfie,
            canPoke: canPoke,
            alertViaPush: alertViaPush,
            alertViaSMS: alertViaSMS,
            alertViaEmail: alertViaEmail,
            isActive: isActive,
            acceptedAt: acceptedAt
        )
    }

    /// Link with all alerts enabled
    static func circleLinkAllAlerts(checker: User, supporter: User) -> CircleLink {
        circleLink(
            checker: checker,
            supporter: supporter,
            supporterName: supporter.name,
            alertViaPush: true,
            alertViaSMS: true,
            alertViaEmail: true
        )
    }

    /// Link with push-only (urgent only)
    static func circleLinkUrgentOnly(checker: User, supporter: User) -> CircleLink {
        circleLink(
            checker: checker,
            supporter: supporter,
            supporterName: supporter.name,
            alertViaPush: true,
            alertViaSMS: false,
            alertViaEmail: false
        )
    }

    // MARK: - AlertEvent Factory

    static func alertEvent(
        checkerId: UUID,
        checkerName: String = "Mom",
        level: AlertLevel = .softAlert,
        status: AlertStatus = .pending,
        triggeredAt: Date = Date(),
        lastCheckInAt: Date? = nil,
        lastKnownLocation: String? = nil,
        notifiedSupporterIds: [UUID] = []
    ) -> AlertEvent {
        AlertEvent(
            checkerId: checkerId,
            checkerName: checkerName,
            level: level,
            status: status,
            triggeredAt: triggeredAt,
            lastCheckInAt: lastCheckInAt,
            lastKnownLocation: lastKnownLocation,
            notifiedSupporterIds: notifiedSupporterIds
        )
    }

    // MARK: - Poke Factory

    static func poke(
        fromSupporterId: UUID = UUID(),
        fromName: String = "Supporter",
        toCheckerId: UUID = UUID(),
        sentAt: Date = Date(),
        seenAt: Date? = nil,
        respondedAt: Date? = nil,
        message: String? = nil
    ) -> Poke {
        Poke(
            fromSupporterId: fromSupporterId,
            fromName: fromName,
            toCheckerId: toCheckerId,
            sentAt: sentAt,
            seenAt: seenAt,
            respondedAt: respondedAt,
            message: message
        )
    }
}
