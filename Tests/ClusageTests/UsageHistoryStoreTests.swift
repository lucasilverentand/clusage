import Testing
import Foundation
@testable import Clusage

@Suite("UsageHistoryStore")
@MainActor
struct UsageHistoryStoreTests {
    @Test("Adds and retrieves snapshots by account")
    func addAndRetrieve() {
        let store = UsageHistoryStore()
        let accountID = UUID()
        let otherID = UUID()

        store.addSnapshot(UsageSnapshot(accountID: accountID, fiveHourUtilization: 0.5, sevenDayUtilization: 0.2))
        store.addSnapshot(UsageSnapshot(accountID: otherID, fiveHourUtilization: 0.3, sevenDayUtilization: 0.1))
        store.addSnapshot(UsageSnapshot(accountID: accountID, fiveHourUtilization: 0.6, sevenDayUtilization: 0.25))

        let filtered = store.snapshots(for: accountID)
        #expect(filtered.count == 2)
    }
}
