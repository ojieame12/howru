import Foundation

/// Injectable clock for deterministic time-based testing
final class MockClock {
    private var _now: Date

    init(now: Date = Date()) {
        self._now = now
    }

    var now: Date {
        _now
    }

    /// Set the current time
    func set(_ date: Date) {
        _now = date
    }

    /// Advance time by interval
    func advance(by interval: TimeInterval) {
        _now = _now.addingTimeInterval(interval)
    }

    /// Advance by hours
    func advanceHours(_ hours: Double) {
        advance(by: hours * 3600)
    }

    /// Advance by days
    func advanceDays(_ days: Double) {
        advance(by: days * 24 * 3600)
    }

    /// Create a date relative to now
    func date(hoursAgo: Double) -> Date {
        _now.addingTimeInterval(-hoursAgo * 3600)
    }

    func date(daysAgo: Double) -> Date {
        _now.addingTimeInterval(-daysAgo * 24 * 3600)
    }

    func date(hoursFromNow: Double) -> Date {
        _now.addingTimeInterval(hoursFromNow * 3600)
    }
}

// MARK: - Date Creation Helpers

extension MockClock {
    /// Create a date at specific time today (in given timezone)
    func today(hour: Int, minute: Int = 0, timezone: TimeZone = .current) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = timezone
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: _now) ?? _now
    }

    /// Create a date at specific time on a specific weekday (0 = Sunday)
    func nextWeekday(_ weekday: Int, hour: Int, minute: Int = 0, timezone: TimeZone = .current) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = timezone

        let currentWeekday = calendar.component(.weekday, from: _now) - 1 // Convert to 0-indexed
        var daysToAdd = weekday - currentWeekday
        if daysToAdd <= 0 {
            daysToAdd += 7
        }

        guard let targetDay = calendar.date(byAdding: .day, value: daysToAdd, to: _now),
              let targetDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: targetDay) else {
            return _now
        }

        return targetDate
    }
}
