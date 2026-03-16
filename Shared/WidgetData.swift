import Foundation

struct WidgetData: Codable, Sendable {
    let accounts: [AccountSummary]
    let lastUpdated: Date
}
