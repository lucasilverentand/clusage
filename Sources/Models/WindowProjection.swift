import Foundation

struct WindowProjection: Sendable {
    enum Status: String, Sendable {
        case underBudget  // dailyProjected < 80% of budget
        case onTrack      // dailyProjected < 100% of budget
        case atRisk       // dailyProjected < 120% of budget
        case overBudget   // dailyProjected >= 120% of budget

        init(dailyProjected: Double, dailyBudget: Double) {
            guard dailyBudget > 0 else {
                self = .overBudget
                return
            }
            let ratio = dailyProjected / dailyBudget
            switch ratio {
            case ..<0.8: self = .underBudget
            case ..<1.0: self = .onTrack
            case ..<1.2: self = .atRisk
            default: self = .overBudget
            }
        }

        var label: String {
            switch self {
            case .underBudget: "Under Budget"
            case .onTrack: "On Track"
            case .atRisk: "At Risk"
            case .overBudget: "Over Budget"
            }
        }
    }

    let sevenDayVelocity: Double           // pp/hr from sevenDayUtilization snapshots
    let projectedAtReset: Double           // projected 7-day % at window end
    let dailyBudget: Double                // max pp/day to stay under 100%
    let dailyProjected: Double             // actual pp/day at current rate
    let remainingDays: Double
    let status: Status

    // Ingredients for live granular 7-day interpolation
    let sevenDayBase: Double               // 7-day utilization at the last tick
    let lastTickTimestamp: Date?           // when 7-day utilization last changed

    /// Whether the calibrated ratio was used (vs observed or default).
    let usedCalibratedRatio: Bool

    /// Pattern-aware projection with confidence bands (nil when insufficient history).
    let patternProjection: PatternProjectionEngine.Projection?

    /// Live sub-integer 7-day utilization interpolated from velocity and time since last tick.
    /// Always returns a value so the UI can show a decimal readout (e.g. "46.3%").
    /// Clamped to at most 1 pp above the API-reported base so the interpolation only
    /// smooths the decimals rather than projecting far ahead of reality.
    func currentGranularUtilization() -> Double {
        guard let tickTime = lastTickTimestamp, sevenDayVelocity > 0 else { return sevenDayBase }
        let hoursSinceTick = Date().timeIntervalSince(tickTime) / 3600
        guard hoursSinceTick > 0 else { return sevenDayBase }
        let estimated = sevenDayBase + sevenDayVelocity * hoursSinceTick
        let ceiling = sevenDayBase + 1.0
        return min(estimated, ceiling, 100)
    }
}
