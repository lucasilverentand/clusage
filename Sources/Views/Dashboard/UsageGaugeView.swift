import SwiftUI

struct UsageGaugeView: View {
    let title: String
    let window: UsageWindow
    var granularPercent: Double? = nil
    var momentum: MomentumCalculation? = nil

    private var displayPercent: Double {
        granularPercent ?? window.percentUsed
    }

    /// Where you'd be if usage were spread linearly across the entire window.
    private var linearTarget: Double {
        window.elapsedFraction * 100
    }

    /// Color based on utilization level.
    private var gaugeColor: Color {
        if displayPercent > 80 { return .red }
        if displayPercent > 60 { return .orange }
        if displayPercent > 40 { return .blue }
        return .teal
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Gauge(value: displayPercent / 100) {
                EmptyView()
            } currentValueLabel: {
                if granularPercent != nil {
                    Text(Formatting.percent(displayPercent))
                        .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
                } else {
                    Text("\(Int(displayPercent))%")
                        .font(.system(.title, design: .rounded, weight: .bold).monospacedDigit())
                }
            }
            .gaugeStyle(.accessoryCircular)
            .tint(gaugeColor.gradient)
            .scaleEffect(1.6)
            .frame(width: 88, height: 88)

            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Text("Linear")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(Formatting.percent(linearTarget, decimals: 0))
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text("Resets \(DateFormatting.resetCountdown(from: window.resetsAt))")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) gauge")
        .accessibilityValue("\(Int(displayPercent)) percent used, linear target \(Int(linearTarget)) percent")
    }
}
