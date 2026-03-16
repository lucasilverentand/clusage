import SwiftUI

enum ThemeColors {
    // MARK: - Momentum Intensity

    static func intensityColor(_ intensity: MomentumCalculation.Intensity) -> Color {
        switch intensity {
        case .idle: .secondary
        case .steady: .green
        case .moderate: .blue
        case .high: .orange
        case .burning: .red
        }
    }

    static func intensityGradient(_ intensity: MomentumCalculation.Intensity) -> AnyShapeStyle {
        switch intensity {
        case .idle: AnyShapeStyle(Color.secondary)
        case .steady: AnyShapeStyle(Color.green.gradient)
        case .moderate: AnyShapeStyle(Color.blue.gradient)
        case .high: AnyShapeStyle(Color.orange.gradient)
        case .burning: AnyShapeStyle(Color.red.gradient)
        }
    }

    // MARK: - Window Projection Status

    static func projectionColor(_ status: WindowProjection.Status) -> Color {
        switch status {
        case .underBudget: .green
        case .onTrack: .blue
        case .atRisk: .orange
        case .overBudget: .red
        }
    }

    static func projectionGradient(_ status: WindowProjection.Status) -> AnyShapeStyle {
        switch status {
        case .underBudget: AnyShapeStyle(Color.green.gradient)
        case .onTrack: AnyShapeStyle(Color.blue.gradient)
        case .atRisk: AnyShapeStyle(Color.orange.gradient)
        case .overBudget: AnyShapeStyle(Color.red.gradient)
        }
    }

    // MARK: - Burst Pattern

    static func burstColor(_ pattern: BurstSummary.Pattern) -> Color {
        switch pattern {
        case .steady: .green
        case .bursty: .orange
        case .spiky: .red
        }
    }

    // MARK: - Daily Target Status

    static func targetStatusColor(_ status: BudgetEngine.DailyTarget.Status) -> Color {
        switch status {
        case .ahead: .orange   // consuming fast — warning
        case .onTrack: .blue
        case .behind: .green   // conserving budget — good
        case .dayOff: .indigo
        }
    }
}
