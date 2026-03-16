import Foundation

struct UsageSnapshot: Codable, Identifiable, Sendable {
    let id: UUID
    let accountID: UUID
    let timestamp: Date
    let fiveHourUtilization: Double
    let sevenDayUtilization: Double

    init(accountID: UUID, fiveHourUtilization: Double, sevenDayUtilization: Double) {
        self.id = UUID()
        self.accountID = accountID
        self.timestamp = Date()
        self.fiveHourUtilization = fiveHourUtilization
        self.sevenDayUtilization = sevenDayUtilization
    }

    init(id: UUID, accountID: UUID, timestamp: Date, fiveHourUtilization: Double, sevenDayUtilization: Double) {
        self.id = id
        self.accountID = accountID
        self.timestamp = timestamp
        self.fiveHourUtilization = fiveHourUtilization
        self.sevenDayUtilization = sevenDayUtilization
    }
}
