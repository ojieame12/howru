import Foundation
import SwiftData

/// Service for managing check-in schedules and windows
@MainActor
@Observable
final class ScheduleService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Schedule Management

    /// Get active schedule for a user
    func activeSchedule(for user: User) -> Schedule? {
        user.schedules.first { $0.isActive }
    }

    /// Create default schedule for user
    func createDefaultSchedule(for user: User) -> Schedule {
        let schedule = Schedule(
            user: user,
            windowStartHour: 8,
            windowStartMinute: 0,
            windowEndHour: 20,
            windowEndMinute: 0,
            gracePeriodMinutes: 60
        )
        modelContext.insert(schedule)
        return schedule
    }

    /// Update schedule times
    func updateSchedule(_ schedule: Schedule, startHour: Int, startMinute: Int, endHour: Int, endMinute: Int, gracePeriod: Int) {
        schedule.windowStartHour = startHour
        schedule.windowStartMinute = startMinute
        schedule.windowEndHour = endHour
        schedule.windowEndMinute = endMinute
        schedule.gracePeriodMinutes = gracePeriod
    }

    // MARK: - Window Calculations

    /// Check if current time is within check-in window
    func isWithinCheckInWindow(for user: User) -> Bool {
        guard let schedule = activeSchedule(for: user) else { return true }
        return schedule.isWithinWindow()
    }

    /// Get time until check-in window opens
    func timeUntilWindowOpens(for user: User) -> TimeInterval? {
        guard let schedule = activeSchedule(for: user) else { return nil }
        let now = Date()
        let calendar = calendar(for: schedule)

        for dayOffset in 0..<7 {
            guard let candidateDate = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            guard isActiveDay(schedule, date: candidateDate, calendar: calendar) else { continue }

            guard let startDate = calendar.date(
                bySettingHour: schedule.windowStartHour,
                minute: schedule.windowStartMinute,
                second: 0,
                of: candidateDate
            ) else { continue }

            if startDate > now {
                return startDate.timeIntervalSince(now)
            }
        }

        return nil
    }

    /// Get time until check-in window closes (including grace period)
    func timeUntilWindowCloses(for user: User) -> TimeInterval? {
        guard let schedule = activeSchedule(for: user) else { return nil }
        let now = Date()
        let calendar = calendar(for: schedule)

        for dayOffset in 0..<7 {
            guard let candidateDate = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            guard isActiveDay(schedule, date: candidateDate, calendar: calendar) else { continue }

            guard let endDate = calendar.date(
                bySettingHour: schedule.windowEndHour,
                minute: schedule.windowEndMinute,
                second: 0,
                of: candidateDate
            ) else { continue }

            let endWithGrace = endDate.addingTimeInterval(TimeInterval(schedule.gracePeriodMinutes * 60))
            if endWithGrace > now {
                return endWithGrace.timeIntervalSince(now)
            }
        }

        return nil
    }

    /// Check if user missed their check-in window
    func hasMissedWindow(for user: User, lastCheckIn: CheckIn?) -> Bool {
        missedWindowTime(for: user, lastCheckIn: lastCheckIn) != nil
    }

    // MARK: - Reminder Scheduling

    /// Get optimal reminder time for user
    func nextReminderTime(for user: User) -> Date? {
        guard let schedule = activeSchedule(for: user), schedule.reminderEnabled else { return nil }

        let now = Date()
        let calendar = calendar(for: schedule)

        for dayOffset in 0..<7 {
            guard let candidateDate = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            guard isActiveDay(schedule, date: candidateDate, calendar: calendar) else { continue }

            guard let endDate = calendar.date(
                bySettingHour: schedule.windowEndHour,
                minute: schedule.windowEndMinute,
                second: 0,
                of: candidateDate
            ) else { continue }

            let reminderDate = endDate.addingTimeInterval(TimeInterval(-schedule.reminderMinutesBefore * 60))
            if reminderDate > now {
                return reminderDate
            }
        }

        return nil
    }

    /// Get escalation times based on schedule
    func escalationTimes(for user: User, from missedTime: Date) -> EscalationTimeline {
        let reminderTime = missedTime.addingTimeInterval(60 * 60) // 1 hour
        let softAlertTime = missedTime.addingTimeInterval(24 * 60 * 60) // 24 hours
        let hardAlertTime = missedTime.addingTimeInterval(36 * 60 * 60) // 36 hours
        let escalationTime = missedTime.addingTimeInterval(48 * 60 * 60) // 48 hours

        return EscalationTimeline(
            reminder: reminderTime,
            softAlert: softAlertTime,
            hardAlert: hardAlertTime,
            escalation: escalationTime
        )
    }

    // MARK: - Helpers

    private func totalMinutes(from components: DateComponents) -> Int? {
        guard let hour = components.hour, let minute = components.minute else { return nil }
        return hour * 60 + minute
    }

    private func calendar(for schedule: Schedule) -> Calendar {
        var calendar = Calendar.current
        calendar.timeZone = schedule.timezone
        return calendar
    }

    private func isActiveDay(_ schedule: Schedule, date: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date) // 1-7
        let dayIndex = weekday - 1
        return schedule.activeDays.contains(dayIndex)
    }
}

// MARK: - Escalation Timeline

struct EscalationTimeline {
    let reminder: Date      // +1h: Reminder to checker
    let softAlert: Date     // +24h: First supporter notified
    let hardAlert: Date     // +36h: More urgent notification
    let escalation: Date    // +48h: All contacts notified
}

// MARK: - Schedule Extensions

extension Schedule {
    /// Formatted window string for display
    var windowDescription: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short

        var calendar = Calendar.current
        calendar.timeZone = timezone
        let now = Date()

        let startDate = calendar.date(bySettingHour: windowStartHour, minute: windowStartMinute, second: 0, of: now) ?? now
        let endDate = calendar.date(bySettingHour: windowEndHour, minute: windowEndMinute, second: 0, of: now) ?? now

        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)

        return "\(start) - \(end)"
    }

    /// Whether the grace period is still active
    func isInGracePeriod(at date: Date = Date()) -> Bool {
        var calendar = Calendar.current
        calendar.timeZone = timezone

        let dateComponents = calendar.dateComponents([.hour, .minute], from: date)

        guard let dateMinutes = dateComponents.hour.map({ $0 * 60 + (dateComponents.minute ?? 0) }) else {
            return false
        }

        let endMinutes = windowEndHour * 60 + windowEndMinute

        let diff = dateMinutes - endMinutes
        return diff > 0 && diff <= gracePeriodMinutes
    }
}

// MARK: - Missed Window Helpers

extension ScheduleService {
    /// Returns the time the user missed the window (end + grace) if missed; otherwise nil.
    func missedWindowTime(for user: User, lastCheckIn: CheckIn?, date: Date = Date()) -> Date? {
        guard let schedule = activeSchedule(for: user) else { return nil }

        let calendar = calendar(for: schedule)
        guard isActiveDay(schedule, date: date, calendar: calendar) else { return nil }

        if let checkIn = lastCheckIn, calendar.isDate(checkIn.timestamp, inSameDayAs: date) {
            return nil
        }

        guard let endDate = calendar.date(
            bySettingHour: schedule.windowEndHour,
            minute: schedule.windowEndMinute,
            second: 0,
            of: date
        ) else { return nil }

        let endWithGrace = endDate.addingTimeInterval(TimeInterval(schedule.gracePeriodMinutes * 60))
        return date > endWithGrace ? endWithGrace : nil
    }
}
