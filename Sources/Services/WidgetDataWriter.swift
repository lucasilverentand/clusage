import Foundation
import WidgetKit

struct WidgetDataWriter {
    func write(accounts: [Account]) {
        let summaries = accounts.compactMap { account -> AccountSummary? in
            guard let fiveHour = account.fiveHour, let sevenDay = account.sevenDay else {
                return nil
            }
            return AccountSummary(
                id: account.id,
                name: account.displayName,
                fiveHourUtilization: fiveHour.utilization,
                fiveHourResetsAt: fiveHour.resetsAt,
                sevenDayUtilization: sevenDay.utilization,
                sevenDayResetsAt: sevenDay.resetsAt
            )
        }

        let widgetData = WidgetData(accounts: summaries, lastUpdated: .now)

        guard let data = try? JSONEncoder().encode(widgetData) else {
            Log.widget.error("Failed to encode widget data")
            return
        }

        guard let url = SharedConstants.widgetDataURL else {
            Log.widget.error("App group container unavailable — cannot write widget data")
            return
        }

        do {
            try data.write(to: url, options: .atomic)
            Log.widget.debug("Widget data written (\(summaries.count) account(s), \(data.count) bytes)")
        } catch {
            Log.widget.error("Failed to write widget data: \(error.localizedDescription)")
        }

        WidgetCenter.shared.reloadAllTimelines()
    }
}
