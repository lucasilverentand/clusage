import Testing
import Foundation
@testable import Clusage

@Suite("UsageSnapshot")
struct UsageSnapshotTests {
    @Test("Snapshot captures utilization values")
    func capturesValues() {
        let accountID = UUID()
        let snapshot = UsageSnapshot(
            accountID: accountID,
            fiveHourUtilization: 0.42,
            sevenDayUtilization: 0.15
        )

        #expect(snapshot.accountID == accountID)
        #expect(snapshot.fiveHourUtilization == 0.42)
        #expect(snapshot.sevenDayUtilization == 0.15)
    }

    @Test("Snapshot encodes and decodes")
    func codable() throws {
        let snapshot = UsageSnapshot(
            accountID: UUID(),
            fiveHourUtilization: 0.5,
            sevenDayUtilization: 0.25
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: data)

        #expect(decoded.id == snapshot.id)
        #expect(decoded.accountID == snapshot.accountID)
        #expect(decoded.fiveHourUtilization == snapshot.fiveHourUtilization)
    }
}
