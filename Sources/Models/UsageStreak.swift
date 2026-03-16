import Foundation

struct UsageStreak: Codable, Sendable {
    /// Set of active days as "yyyy-MM-dd" strings.
    var activeDays: Set<String> = []
    var currentStreak: Int = 0
    var longestStreak: Int = 0

    private static let maxRetentionDays = 90

    /// Compute the day key shifted by the plan day boundary hour so that
    /// e.g. 2 AM Tuesday maps to Monday's key (consistent with UsagePlan).
    static func dayKey(for date: Date = .now) -> String {
        let cal = Calendar.current
        // Shift back by dayBoundaryHour so pre-boundary hours belong to the previous day
        let shifted = cal.date(byAdding: .hour, value: -UsagePlan.dayBoundaryHour, to: date)!
        let comps = cal.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", comps.year!, comps.month!, comps.day!)
    }

    /// Mark a day as active.
    mutating func markActive(date: Date = .now) {
        activeDays.insert(Self.dayKey(for: date))
        pruneOldDays(from: date)
        recalculateStreak(from: date)
    }

    /// Recalculate current streak by walking backward from the given date.
    mutating func recalculateStreak(from date: Date = .now) {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = date

        while activeDays.contains(Self.dayKey(for: checkDate)) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = previous
        }

        currentStreak = streak
        longestStreak = max(longestStreak, streak)
    }

    /// Remove days older than 90 days.
    mutating func pruneOldDays(from date: Date = .now) {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.maxRetentionDays, to: date) else { return }
        let cutoffKey = Self.dayKey(for: cutoff)
        activeDays = activeDays.filter { $0 >= cutoffKey }
    }
}
