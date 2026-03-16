import Foundation

struct AccountSummary: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let fiveHourUtilization: Double
    let fiveHourResetsAt: Date
    let sevenDayUtilization: Double
    let sevenDayResetsAt: Date
}
