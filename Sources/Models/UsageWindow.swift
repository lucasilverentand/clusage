import Foundation

struct UsageWindow: Codable, Sendable {
    let utilization: Double
    let resetsAt: Date
    let duration: TimeInterval

    var remainingTime: TimeInterval {
        max(resetsAt.timeIntervalSinceNow, 0)
    }

    var elapsedFraction: Double {
        min(max(1 - (remainingTime / duration), 0), 1)
    }

    /// Utilization as 0…1 for gauges and progress bars.
    var normalizedUtilization: Double {
        utilization / 100
    }

    /// Utilization as a percentage (already 0–100 from the API).
    var percentUsed: Double {
        utilization
    }

    static let fiveHourDuration: TimeInterval = 5 * 60 * 60
    static let sevenDayDuration: TimeInterval = 7 * 24 * 60 * 60
}
