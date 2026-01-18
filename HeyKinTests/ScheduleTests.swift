import XCTest
import SwiftData
@testable import HowRU

/// Tests for Schedule model and ScheduleService
@MainActor
final class ScheduleTests: XCTestCase {

    var container: TestContainer!
    var scheduleService: ScheduleService!

    override func setUp() async throws {
        container = try TestContainer()
        scheduleService = ScheduleService(modelContext: container.context)
    }

    override func tearDown() async throws {
        try container.reset()
        container = nil
        scheduleService = nil
    }

    // MARK: - Schedule.isWithinWindow Tests

    func testIsWithinWindow_insideWindow_returnsTrue() throws {
        // Given: Schedule 7am-10am, current time is 8:30am
        let timezone = TimeZone(identifier: "America/New_York")!
        let schedule = Factories.morningSchedule(timezone: timezone)

        var calendar = Calendar.current
        calendar.timeZone = timezone
        let testDate = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: Date())!

        // When
        let result = schedule.isWithinWindow(date: testDate)

        // Then
        XCTAssertTrue(result, "8:30am should be within 7am-10am window")
    }

    func testIsWithinWindow_beforeWindow_returnsFalse() throws {
        // Given: Schedule 7am-10am, current time is 6:30am
        let timezone = TimeZone(identifier: "America/New_York")!
        let schedule = Factories.morningSchedule(timezone: timezone)

        var calendar = Calendar.current
        calendar.timeZone = timezone
        let testDate = calendar.date(bySettingHour: 6, minute: 30, second: 0, of: Date())!

        // When
        let result = schedule.isWithinWindow(date: testDate)

        // Then
        XCTAssertFalse(result, "6:30am should be before 7am-10am window")
    }

    func testIsWithinWindow_afterWindow_returnsFalse() throws {
        // Given: Schedule 7am-10am, current time is 11:00am
        let timezone = TimeZone(identifier: "America/New_York")!
        let schedule = Factories.morningSchedule(timezone: timezone)

        var calendar = Calendar.current
        calendar.timeZone = timezone
        let testDate = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: Date())!

        // When
        let result = schedule.isWithinWindow(date: testDate)

        // Then
        XCTAssertFalse(result, "11:00am should be after 7am-10am window")
    }

    func testIsWithinWindow_exactWindowStart_returnsTrue() throws {
        // Given: Schedule 7am-10am, current time is exactly 7:00am
        let timezone = TimeZone.current
        let schedule = Factories.morningSchedule(timezone: timezone)

        var calendar = Calendar.current
        calendar.timeZone = timezone
        let testDate = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: Date())!

        // When
        let result = schedule.isWithinWindow(date: testDate)

        // Then
        XCTAssertTrue(result, "Exactly 7:00am should be within window (inclusive start)")
    }

    func testIsWithinWindow_exactWindowEnd_returnsTrue() throws {
        // Given: Schedule 7am-10am, current time is exactly 10:00am
        let timezone = TimeZone.current
        let schedule = Factories.morningSchedule(timezone: timezone)

        var calendar = Calendar.current
        calendar.timeZone = timezone
        let testDate = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!

        // When
        let result = schedule.isWithinWindow(date: testDate)

        // Then
        XCTAssertTrue(result, "Exactly 10:00am should be within window (inclusive end)")
    }

    // MARK: - Active Days Tests

    func testIsWithinWindow_onInactiveDay_returnsFalse() throws {
        // Given: Weekday-only schedule (Mon-Fri), tested on Sunday
        let schedule = Factories.weekdaySchedule()

        // Find next Sunday
        var calendar = Calendar.current
        let today = Date()
        var sundayDate = today
        while calendar.component(.weekday, from: sundayDate) != 1 { // 1 = Sunday
            sundayDate = calendar.date(byAdding: .day, value: 1, to: sundayDate)!
        }

        // Set time to 8:30am (within window)
        let testDate = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: sundayDate)!

        // When
        let result = schedule.isWithinWindow(date: testDate)

        // Then
        XCTAssertFalse(result, "Sunday should not be active for weekday-only schedule")
    }

    func testIsWithinWindow_onActiveDay_returnsTrue() throws {
        // Given: Weekday-only schedule (Mon-Fri), tested on Monday
        let schedule = Factories.weekdaySchedule()

        // Find next Monday
        var calendar = Calendar.current
        let today = Date()
        var mondayDate = today
        while calendar.component(.weekday, from: mondayDate) != 2 { // 2 = Monday
            mondayDate = calendar.date(byAdding: .day, value: 1, to: mondayDate)!
        }

        // Set time to 8:30am (within window)
        let testDate = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: mondayDate)!

        // When
        let result = schedule.isWithinWindow(date: testDate)

        // Then
        XCTAssertTrue(result, "Monday 8:30am should be within weekday schedule window")
    }

    // MARK: - Timezone Tests

    func testIsWithinWindow_respectsTimezone() throws {
        // Given: Schedule 7am-10am in New York timezone
        let nyTimezone = TimeZone(identifier: "America/New_York")!
        let schedule = Factories.morningSchedule(timezone: nyTimezone)

        // Create a date that's 8:30am in New York
        var nyCalendar = Calendar.current
        nyCalendar.timeZone = nyTimezone
        let testDate = nyCalendar.date(bySettingHour: 8, minute: 30, second: 0, of: Date())!

        // When
        let result = schedule.isWithinWindow(date: testDate)

        // Then
        XCTAssertTrue(result, "8:30am New York time should be within window")
    }

    // MARK: - Grace Period Tests

    func testIsInGracePeriod_withinGracePeriod_returnsTrue() throws {
        // Given: Schedule ends at 10am with 30 min grace, time is 10:15am
        let timezone = TimeZone.current
        let schedule = Factories.schedule(
            windowEndHour: 10,
            windowEndMinute: 0,
            timezone: timezone,
            gracePeriodMinutes: 30
        )

        var calendar = Calendar.current
        calendar.timeZone = timezone
        let testDate = calendar.date(bySettingHour: 10, minute: 15, second: 0, of: Date())!

        // When
        let result = schedule.isInGracePeriod(at: testDate)

        // Then
        XCTAssertTrue(result, "10:15am should be in grace period (10:00-10:30)")
    }

    func testIsInGracePeriod_afterGracePeriod_returnsFalse() throws {
        // Given: Schedule ends at 10am with 30 min grace, time is 10:45am
        let timezone = TimeZone.current
        let schedule = Factories.schedule(
            windowEndHour: 10,
            windowEndMinute: 0,
            timezone: timezone,
            gracePeriodMinutes: 30
        )

        var calendar = Calendar.current
        calendar.timeZone = timezone
        let testDate = calendar.date(bySettingHour: 10, minute: 45, second: 0, of: Date())!

        // When
        let result = schedule.isInGracePeriod(at: testDate)

        // Then
        XCTAssertFalse(result, "10:45am should be after grace period")
    }

    func testIsInGracePeriod_beforeWindowEnd_returnsFalse() throws {
        // Given: Schedule ends at 10am with 30 min grace, time is 9:45am
        let timezone = TimeZone.current
        let schedule = Factories.schedule(
            windowEndHour: 10,
            windowEndMinute: 0,
            timezone: timezone,
            gracePeriodMinutes: 30
        )

        var calendar = Calendar.current
        calendar.timeZone = timezone
        let testDate = calendar.date(bySettingHour: 9, minute: 45, second: 0, of: Date())!

        // When
        let result = schedule.isInGracePeriod(at: testDate)

        // Then
        XCTAssertFalse(result, "9:45am is still in window, not grace period")
    }

    // MARK: - ScheduleService.missedWindowTime Tests

    func testMissedWindowTime_notMissed_returnsNil() async throws {
        // Given: User with check-in today
        let user = container.insert(Factories.checker())
        let schedule = container.insert(Factories.morningSchedule(user: user))
        user.schedules = [schedule]

        let todayCheckIn = Factories.checkIn(user: user, timestamp: Date())
        container.insert(todayCheckIn)

        // When
        let missedTime = scheduleService.missedWindowTime(for: user, lastCheckIn: todayCheckIn)

        // Then
        XCTAssertNil(missedTime, "Should not be missed when checked in today")
    }

    func testMissedWindowTime_missedWindow_returnsEndPlusGrace() async throws {
        // Given: User with no check-in, past window end + grace
        let user = container.insert(Factories.checker())

        // Create schedule that ended hours ago
        var calendar = Calendar.current
        let now = Date()
        let windowEndHour = calendar.component(.hour, from: now) - 2 // 2 hours ago
        let schedule = container.insert(Factories.schedule(
            user: user,
            windowStartHour: max(0, windowEndHour - 3),
            windowEndHour: max(0, windowEndHour),
            gracePeriodMinutes: 30
        ))
        user.schedules = [schedule]

        // When
        let missedTime = scheduleService.missedWindowTime(for: user, lastCheckIn: nil)

        // Then
        XCTAssertNotNil(missedTime, "Should return missed time when window + grace has passed")
    }

    // MARK: - Escalation Timeline Tests

    func testEscalationTimes_calculatesCorrectIntervals() {
        // Given
        let user = Factories.checker()
        let missedTime = Date()

        // When
        let timeline = scheduleService.escalationTimes(for: user, from: missedTime)

        // Then
        XCTAssertEqual(
            timeline.reminder.timeIntervalSince(missedTime),
            3600, // 1 hour
            accuracy: 1,
            "Reminder should be 1 hour after missed time"
        )
        XCTAssertEqual(
            timeline.softAlert.timeIntervalSince(missedTime),
            24 * 3600, // 24 hours
            accuracy: 1,
            "Soft alert should be 24 hours after missed time"
        )
        XCTAssertEqual(
            timeline.hardAlert.timeIntervalSince(missedTime),
            36 * 3600, // 36 hours
            accuracy: 1,
            "Hard alert should be 36 hours after missed time"
        )
        XCTAssertEqual(
            timeline.escalation.timeIntervalSince(missedTime),
            48 * 3600, // 48 hours
            accuracy: 1,
            "Escalation should be 48 hours after missed time"
        )
    }
}
