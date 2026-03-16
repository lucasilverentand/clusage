import SwiftUI
import WidgetKit

struct UsageGaugeWidgetView: View {
    let entry: UsageEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let data = entry.data, let primary = data.accounts.first {
            switch family {
            case .systemSmall:
                smallView(account: primary)
            case .systemMedium:
                mediumView(accounts: data.accounts)
            default:
                smallView(account: primary)
            }
        } else {
            ContentUnavailableView("No Data", systemImage: "chart.bar.xaxis")
        }
    }

    private func smallView(account: AccountSummary) -> some View {
        VStack(spacing: 10) {
            Text(account.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)

            Gauge(value: account.fiveHourUtilization / 100) {
                EmptyView()
            } currentValueLabel: {
                Text("\(Int(account.fiveHourUtilization))%")
                    .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Gradient(colors: [.green, .orange, .red]))
            .scaleEffect(1.2)

            Text("5h window")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func mediumView(accounts: [AccountSummary]) -> some View {
        HStack(spacing: 16) {
            ForEach(accounts.prefix(3)) { account in
                VStack(spacing: 6) {
                    Text(account.name)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)

                    Gauge(value: account.fiveHourUtilization / 100) {
                        EmptyView()
                    } currentValueLabel: {
                        Text("\(Int(account.fiveHourUtilization))%")
                            .font(.system(.caption, design: .rounded, weight: .bold).monospacedDigit())
                    }
                    .gaugeStyle(.accessoryCircular)
                    .tint(Gradient(colors: [.green, .orange, .red]))

                    Text("\(Int(account.sevenDayUtilization))% 7d")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
    }
}
