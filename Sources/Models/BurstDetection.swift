import Foundation

struct UsageBurst: Codable, Sendable {
    let start: Date
    var end: Date?
    var peakVelocity: Double
    var utilizationConsumed: Double
}

struct BurstSummary: Sendable {
    enum Pattern: String, Sendable {
        case steady, bursty, spiky

        init(burstRatio: Double) {
            switch burstRatio {
            case ..<0.2: self = .steady
            case 0.2..<0.6: self = .bursty
            default: self = .spiky
            }
        }

        var label: String { rawValue.capitalized }
    }

    /// Currently active burst, if any.
    let activeBurst: UsageBurst?
    /// Recent completed bursts.
    let recentBursts: [UsageBurst]
    /// Fraction of time spent in bursts (0-1).
    let burstRatio: Double
    let pattern: Pattern
}
