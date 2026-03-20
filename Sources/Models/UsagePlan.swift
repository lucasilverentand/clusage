import Foundation

struct DaySlot: Codable, Sendable, Equatable {
    var isActive: Bool = true
    var startHour: Int = 9
    var endHour: Int = 23

    /// Active hours in this slot.
    /// When `startHour == endHour`, this means a full 24-hour active day.
    var activeHours: Double {
        guard isActive else { return 0 }
        if endHour == startHour { return 24 }
        if endHour > startHour {
            return Double(endHour - startHour)
        } else {
            // Wraps past midnight (e.g. 9 AM to 1 AM = 16h)
            return Double(24 - startHour + endHour)
        }
    }
}

struct UsagePlan: Codable, Sendable {
    /// Day boundary hour — a new "plan day" starts at this hour (default 5 AM).
    static let dayBoundaryHour = 5

    var isEnabled: Bool = false
    /// Keyed by Calendar weekday (1 = Sunday, 2 = Monday, ... 7 = Saturday).
    var slots: [Int: DaySlot] = Self.defaultSlots
    /// Date-specific overrides, keyed by plan-day date string (yyyy-MM-dd).
    /// These take priority over the weekly slot for that day.
    var overrides: [String: DaySlot] = [:]

    static let defaultSlots: [Int: DaySlot] = {
        var dict: [Int: DaySlot] = [:]
        for day in 1...7 {
            // Weekend days (1 = Sunday, 7 = Saturday) off by default
            let isWeekday = day >= 2 && day <= 6
            dict[day] = DaySlot(isActive: isWeekday, startHour: 9, endHour: 23)
        }
        return dict
    }()

    // MARK: - Day Boundary

    /// Returns the calendar date for the plan day containing `date`.
    /// Before the day boundary hour, the date belongs to the previous plan day
    /// (e.g. 2 AM Tuesday = Monday's plan).
    static func planCalendarDay(for date: Date) -> Date {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        if hour < dayBoundaryHour {
            return cal.date(byAdding: .day, value: -1, to: date) ?? date
        }
        return date
    }

    /// Returns the "plan weekday" for the given date.
    static func planWeekday(for date: Date) -> Int {
        Calendar.current.component(.weekday, from: planCalendarDay(for: date))
    }

    /// Returns the plan-day date string (yyyy-MM-dd) for a given date.
    static func planDateKey(for date: Date) -> String {
        DateFormatting.formatDateDash(planCalendarDay(for: date))
    }

    /// Returns the slot for the current plan day, checking overrides first.
    func todaySlot(at date: Date = .now) -> DaySlot? {
        guard isEnabled else { return nil }
        let key = Self.planDateKey(for: date)
        if let override = overrides[key] {
            return override
        }
        let weekday = Self.planWeekday(for: date)
        return slots[weekday]
    }

    /// Whether the given date has an override.
    func hasOverride(for date: Date) -> Bool {
        overrides[Self.planDateKey(for: date)] != nil
    }

    /// Set a date-specific override.
    mutating func setOverride(_ slot: DaySlot, for date: Date) {
        overrides[Self.planDateKey(for: date)] = slot
    }

    /// Remove the override for a date.
    mutating func clearOverride(for date: Date) {
        overrides.removeValue(forKey: Self.planDateKey(for: date))
    }

    /// Remove overrides older than 8 days.
    mutating func pruneOldOverrides() {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -8, to: .now) else { return }
        let cutoffKey = DateFormatting.formatDateDash(cutoff)
        overrides = overrides.filter { $0.key >= cutoffKey }
    }

    /// Whether the given time falls within an active slot.
    func isActiveTime(_ date: Date) -> Bool {
        guard isEnabled else { return true }
        guard let slot = todaySlot(at: date), slot.isActive else { return false }
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)

        // Full 24-hour slot — always active
        if slot.startHour == slot.endHour { return true }

        if hour < Self.dayBoundaryHour {
            // Before day boundary — check if previous day's slot extends past midnight
            if slot.endHour <= slot.startHour {
                // Slot wraps midnight, we're in the wrap portion
                return hour < slot.endHour
            }
            return false
        }

        if slot.endHour > slot.startHour {
            return hour >= slot.startHour && hour < slot.endHour
        } else {
            // Wraps past midnight
            return hour >= slot.startHour || hour < slot.endHour
        }
    }

    /// The bedtime for the current plan day — when today's slot ends.
    func bedtime(for date: Date = .now) -> Date? {
        guard isEnabled else { return nil }
        guard let slot = todaySlot(at: date), slot.isActive else { return nil }
        let cal = Calendar.current

        let planDate = Self.planCalendarDay(for: date)

        // Bedtime is endHour on the plan day (or next calendar day if wraps past midnight)
        guard var bedtime = cal.date(bySettingHour: slot.endHour, minute: 0, second: 0, of: planDate) else {
            return nil
        }
        if slot.endHour <= slot.startHour {
            // End wraps to next calendar day
            guard let nextDay = cal.date(byAdding: .day, value: 1, to: bedtime) else { return nil }
            bedtime = nextDay
        }

        return bedtime
    }

    /// Total active hours remaining from `now` until `deadline`, respecting per-day slots.
    func activeHoursRemaining(until deadline: Date, from now: Date = .now) -> Double {
        guard isEnabled else {
            return max(deadline.timeIntervalSince(now) / 3600, 0)
        }

        let cal = Calendar.current
        var total: Double = 0
        var cursor = now

        // Walk day by day until we pass the deadline
        while cursor < deadline {
            let key = Self.planDateKey(for: cursor)
            let weekday = Self.planWeekday(for: cursor)
            let slot = overrides[key] ?? slots[weekday]
            guard let slot, slot.isActive else {
                // Skip to next day boundary
                cursor = nextDayBoundary(after: cursor)
                continue
            }

            // Find the active window for this plan day
            let dayStart = dayBoundaryDate(for: cursor)
            guard let slotStart = cal.date(bySettingHour: slot.startHour, minute: 0, second: 0, of: dayStart) else {
                cursor = nextDayBoundary(after: cursor)
                continue
            }
            var slotEnd = cal.date(bySettingHour: slot.endHour, minute: 0, second: 0, of: dayStart) ?? slotStart
            if slot.endHour <= slot.startHour {
                slotEnd = cal.date(byAdding: .day, value: 1, to: slotEnd) ?? slotEnd
            }

            // Clamp to [now, deadline]
            let effectiveStart = max(slotStart, cursor)
            let effectiveEnd = min(slotEnd, deadline)
            if effectiveEnd > effectiveStart {
                total += effectiveEnd.timeIntervalSince(effectiveStart) / 3600
            }

            cursor = nextDayBoundary(after: cursor)
        }

        return total
    }

    // MARK: - Helpers

    /// Returns the date of the day boundary (5 AM) for the plan day containing `date`.
    private func dayBoundaryDate(for date: Date) -> Date {
        let cal = Calendar.current
        let planDate = Self.planCalendarDay(for: date)
        return cal.date(bySettingHour: Self.dayBoundaryHour, minute: 0, second: 0, of: planDate) ?? planDate
    }

    /// Returns the next day boundary (5 AM) after the plan day containing `date`.
    private func nextDayBoundary(after date: Date) -> Date {
        let boundary = dayBoundaryDate(for: date)
        return Calendar.current.date(byAdding: .day, value: 1, to: boundary) ?? boundary.addingTimeInterval(86400)
    }

    // MARK: - Ordered Days

    /// Days of the week starting from Monday, with their Calendar weekday numbers.
    static let orderedDays: [(weekday: Int, name: String, short: String)] = [
        (2, "Monday", "Mon"),
        (3, "Tuesday", "Tue"),
        (4, "Wednesday", "Wed"),
        (5, "Thursday", "Thu"),
        (6, "Friday", "Fri"),
        (7, "Saturday", "Sat"),
        (1, "Sunday", "Sun"),
    ]
}
