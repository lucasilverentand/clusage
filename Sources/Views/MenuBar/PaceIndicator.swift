import SwiftUI

struct PaceIndicator: View {
    let window: UsageWindow

    private var pace: PaceCalculation {
        PaceCalculation(window: window)
    }

    private var accessibilityDescription: String {
        if abs(pace.delta) < 1 {
            return "On pace"
        } else if pace.isOverpacing {
            return String(format: "%.0f percent ahead of pace", pace.delta)
        } else {
            return String(format: "%.0f percent behind pace", abs(pace.delta))
        }
    }

    var body: some View {
        Image(systemName: iconName)
            .font(.caption2)
            .foregroundStyle(iconColor)
            .help(pace.description)
            .accessibilityLabel(accessibilityDescription)
    }

    private var iconName: String {
        if abs(pace.delta) < 1 {
            return "equal.circle.fill"
        } else if pace.isOverpacing {
            return "arrow.up.circle.fill"
        } else {
            return "arrow.down.circle.fill"
        }
    }

    private var iconColor: Color {
        if abs(pace.delta) < 1 {
            return .secondary
        } else if pace.isOverpacing {
            return .orange
        } else {
            return .green
        }
    }
}
