import Testing
import Foundation
@testable import Clusage

@Suite("WidgetData")
struct WidgetDataTests {
    @Test("WidgetData encodes and decodes")
    func codable() throws {
        let data = WidgetData(
            accounts: [
                AccountSummary(
                    id: UUID(),
                    name: "Test",
                    fiveHourUtilization: 0.42,
                    fiveHourResetsAt: Date(),
                    sevenDayUtilization: 0.15,
                    sevenDayResetsAt: Date(),
                )
            ],
            lastUpdated: .now
        )

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(WidgetData.self, from: encoded)

        #expect(decoded.accounts.count == 1)
        #expect(decoded.accounts[0].name == "Test")
        #expect(decoded.accounts[0].fiveHourUtilization == 0.42)
    }

    @Test("AccountSummary has correct identity")
    func identity() {
        let id = UUID()
        let summary = AccountSummary(
            id: id,
            name: "Test",
            fiveHourUtilization: 0.5,
            fiveHourResetsAt: Date(),
            sevenDayUtilization: 0.2,
            sevenDayResetsAt: Date(),

        )

        #expect(summary.id == id)
    }
}
