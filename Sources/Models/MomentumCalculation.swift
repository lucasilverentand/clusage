import Foundation

struct MomentumCalculation: Sendable {
    enum Intensity: String, Sendable, CaseIterable {
        case idle, steady, moderate, high, burning

        init(velocity: Double) {
            switch velocity {
            case ..<1: self = .idle
            case 1..<5: self = .steady
            case 5..<15: self = .moderate
            case 15..<30: self = .high
            default: self = .burning
            }
        }

        var label: String { rawValue.capitalized }
    }

    /// Percentage points per hour.
    let velocity: Double

    /// Change in velocity (positive = accelerating, negative = decelerating).
    let acceleration: Double

    /// Seconds until utilization reaches 100%, adjusted for sleep if enabled.
    let etaToCeiling: TimeInterval?

    /// Whether the rate-limit window resets before the projected ceiling hit.
    let resetsFirst: Bool

    let intensity: Intensity
}
