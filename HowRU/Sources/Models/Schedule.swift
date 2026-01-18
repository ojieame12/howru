import Foundation
import SwiftData

@Model
final class Schedule {
    @Attribute(.unique) var id: UUID
    var user: User?

    // Check-in window
    var windowStartHour: Int   // 0-23
    var windowStartMinute: Int // 0-59
    var windowEndHour: Int
    var windowEndMinute: Int

    // Timezone
    var timezoneIdentifier: String

    // Active days (0 = Sunday, 6 = Saturday)
    var activeDays: [Int]

    // Grace period before alerts (minutes)
    var gracePeriodMinutes: Int

    // Reminder settings
    var reminderEnabled: Bool
    var reminderMinutesBefore: Int  // Minutes before window ends

    var isActive: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        user: User? = nil,
        windowStartHour: Int = 7,
        windowStartMinute: Int = 0,
        windowEndHour: Int = 10,
        windowEndMinute: Int = 0,
        timezoneIdentifier: String = TimeZone.current.identifier,
        activeDays: [Int] = [0, 1, 2, 3, 4, 5, 6],  // Every day
        gracePeriodMinutes: Int = 30,
        reminderEnabled: Bool = true,
        reminderMinutesBefore: Int = 30,
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.user = user
        self.windowStartHour = windowStartHour
        self.windowStartMinute = windowStartMinute
        self.windowEndHour = windowEndHour
        self.windowEndMinute = windowEndMinute
        self.timezoneIdentifier = timezoneIdentifier
        self.activeDays = activeDays
        self.gracePeriodMinutes = gracePeriodMinutes
        self.reminderEnabled = reminderEnabled
        self.reminderMinutesBefore = reminderMinutesBefore
        self.isActive = isActive
        self.createdAt = createdAt
    }
}

// MARK: - Convenience
extension Schedule {
    var timezone: TimeZone {
        TimeZone(identifier: timezoneIdentifier) ?? .current
    }

    var windowStartTime: DateComponents {
        DateComponents(hour: windowStartHour, minute: windowStartMinute)
    }

    var windowEndTime: DateComponents {
        DateComponents(hour: windowEndHour, minute: windowEndMinute)
    }

    /// Check if current time is within the check-in window
    func isWithinWindow(date: Date = Date()) -> Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents(in: timezone, from: date)

        guard let hour = components.hour,
              let minute = components.minute,
              let weekday = components.weekday else {
            return false
        }

        // Check if today is an active day (weekday is 1-7, we use 0-6)
        let dayIndex = weekday - 1
        guard activeDays.contains(dayIndex) else { return false }

        let currentMinutes = hour * 60 + minute
        let startMinutes = windowStartHour * 60 + windowStartMinute
        let endMinutes = windowEndHour * 60 + windowEndMinute

        return currentMinutes >= startMinutes && currentMinutes <= endMinutes
    }
}
