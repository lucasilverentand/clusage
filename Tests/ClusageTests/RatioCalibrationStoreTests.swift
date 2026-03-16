import Testing
import Foundation
@testable import Clusage

@Suite("RatioCalibrationStore")
@MainActor
struct RatioCalibrationStoreTests {
    private let accountID = UUID()

    private func makeStore() -> RatioCalibrationStore {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clusage-test-\(UUID().uuidString).json")
        return RatioCalibrationStore(fileURL: tempURL)
    }

    private func makeSnapshot(
        minutesAgo: Double,
        fiveHour: Double,
        sevenDay: Double
    ) -> UsageSnapshot {
        let timestamp = Date().addingTimeInterval(-minutesAgo * 60)
        return UsageSnapshot(
            id: UUID(),
            accountID: accountID,
            timestamp: timestamp,
            fiveHourUtilization: fiveHour,
            sevenDayUtilization: sevenDay
        )
    }

    @Test("Returns default ratio when no observations exist")
    func defaultRatio() {
        let store = makeStore()
        let ratio = store.calibratedRatio(for: accountID)
        #expect(abs(ratio - RatioCalibrationStore.defaultRatio) < 0.001)
    }

    @Test("Calibrates from snapshots with 7-day tick")
    func calibratesFromTick() {
        let store = makeStore()

        // 5h went from 10 to 20 (+10), 7d went from 45 to 46 (+1)
        // ratio = 1/10 = 0.1
        let snapshots = [
            makeSnapshot(minutesAgo: 10, fiveHour: 10, sevenDay: 45),
            makeSnapshot(minutesAgo: 5, fiveHour: 20, sevenDay: 46),
        ]

        store.calibrate(from: snapshots, accountID: accountID)

        let ratio = store.calibratedRatio(for: accountID)
        #expect(abs(ratio - 0.1) < 0.01)
        #expect(store.observationCount(for: accountID) == 1)
    }

    @Test("Ignores intervals where 7-day didn't change")
    func ignoresFlat7Day() {
        let store = makeStore()

        let snapshots = [
            makeSnapshot(minutesAgo: 10, fiveHour: 10, sevenDay: 45),
            makeSnapshot(minutesAgo: 5, fiveHour: 20, sevenDay: 45), // no 7d tick
        ]

        store.calibrate(from: snapshots, accountID: accountID)
        #expect(store.observationCount(for: accountID) == 0)
    }

    @Test("Ignores intervals where 5-hour decreased (window reset)")
    func ignores5hReset() {
        let store = makeStore()

        let snapshots = [
            makeSnapshot(minutesAgo: 10, fiveHour: 80, sevenDay: 45),
            makeSnapshot(minutesAgo: 5, fiveHour: 5, sevenDay: 46), // 5h reset
        ]

        store.calibrate(from: snapshots, accountID: accountID)
        #expect(store.observationCount(for: accountID) == 0)
    }

    @Test("Multiple observations produce weighted average")
    func weightedAverage() {
        let store = makeStore()

        // Two ticks with different ratios (both within [0.005, 0.15] outlier bounds)
        let snapshots = [
            makeSnapshot(minutesAgo: 30, fiveHour: 10, sevenDay: 40),
            makeSnapshot(minutesAgo: 20, fiveHour: 30, sevenDay: 41),  // 5h delta=20, ratio=0.05
            makeSnapshot(minutesAgo: 10, fiveHour: 35, sevenDay: 41),  // no tick
            makeSnapshot(minutesAgo: 5, fiveHour: 45, sevenDay: 42),   // 5h delta=10, ratio=0.1
        ]

        store.calibrate(from: snapshots, accountID: accountID)
        #expect(store.observationCount(for: accountID) == 2)

        let ratio = store.calibratedRatio(for: accountID)
        // Weighted average of 0.05 and 0.1, with more recent having more weight
        #expect(ratio > 0.05)
        #expect(ratio < 0.1)
    }

    @Test("Doesn't re-record duplicate observations")
    func deduplication() {
        let store = makeStore()

        let snapshots = [
            makeSnapshot(minutesAgo: 10, fiveHour: 10, sevenDay: 45),
            makeSnapshot(minutesAgo: 5, fiveHour: 20, sevenDay: 46),
        ]

        // Calibrate twice with same snapshots
        store.calibrate(from: snapshots, accountID: accountID)
        store.calibrate(from: snapshots, accountID: accountID)

        #expect(store.observationCount(for: accountID) == 1)
    }

    @Test("hasCalibration requires at least 3 observations")
    func calibrationConfidence() {
        let store = makeStore()
        #expect(!store.hasCalibration(for: accountID))

        // Each pair needs: fiveDelta > 0.01, sevenDelta > 0, ratio in [0.005, 0.15],
        // and previous snapshot fiveHour >= 0.1
        let snapshots = [
            makeSnapshot(minutesAgo: 30, fiveHour: 10, sevenDay: 40),
            makeSnapshot(minutesAgo: 25, fiveHour: 30, sevenDay: 41),  // ratio=0.05
            makeSnapshot(minutesAgo: 20, fiveHour: 40, sevenDay: 42),  // ratio=0.1
            makeSnapshot(minutesAgo: 15, fiveHour: 60, sevenDay: 43),  // ratio=0.05
        ]

        store.calibrate(from: snapshots, accountID: accountID)
        #expect(store.hasCalibration(for: accountID))
    }
}
