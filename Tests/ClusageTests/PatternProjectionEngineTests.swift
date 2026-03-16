import Testing
import Foundation
@testable import Clusage

@Suite("PatternProjectionEngine")
struct PatternProjectionEngineTests {
    private let accountID = UUID()

    private func makeSnapshot(
        hoursAgo: Double,
        fiveHour: Double,
        sevenDay: Double
    ) -> UsageSnapshot {
        let timestamp = Date().addingTimeInterval(-hoursAgo * 3600)
        return UsageSnapshot(
            id: UUID(),
            accountID: accountID,
            timestamp: timestamp,
            fiveHourUtilization: fiveHour,
            sevenDayUtilization: sevenDay
        )
    }

    /// Generate a week of synthetic snapshots at 5-minute intervals
    /// with a time-of-day pattern: higher velocity during work hours.
    private func generateWeekOfSnapshots() -> [UsageSnapshot] {
        var snapshots: [UsageSnapshot] = []
        let cal = Calendar.current
        let now = Date()

        // Go back 7 days, 5-minute intervals
        var fiveHour = 0.0
        var sevenDay = 20.0
        let totalSteps = 7 * 24 * 12 // 7 days × 24 hours × 12 five-minute steps

        for i in 0..<totalSteps {
            let hoursAgo = Double(totalSteps - i) * (5.0 / 60.0)
            let date = now.addingTimeInterval(-hoursAgo * 3600)
            let hour = cal.component(.hour, from: date)

            // Simulate work hours pattern: active 9-17, idle otherwise
            let velocity: Double
            if hour >= 9 && hour < 17 {
                velocity = 3.0 + Double.random(in: -0.5...0.5) // ~3 pp/hr during work
            } else if hour >= 17 && hour < 23 {
                velocity = 1.0 + Double.random(in: -0.3...0.3) // ~1 pp/hr evening
            } else {
                velocity = 0 // sleeping
            }

            let delta5min = velocity * (5.0 / 60.0) // velocity × hours per step
            fiveHour += delta5min
            sevenDay += delta5min * 0.03 // small fraction goes to 7-day

            // Reset 5-hour periodically to keep it realistic
            if fiveHour > 80 { fiveHour = 5 }

            snapshots.append(UsageSnapshot(
                id: UUID(),
                accountID: accountID,
                timestamp: date,
                fiveHourUtilization: fiveHour,
                sevenDayUtilization: min(sevenDay, 100)
            ))
        }

        return snapshots
    }

    // MARK: - Profile Building

    @Test("Builds hourly profile from snapshots")
    func buildProfile() {
        let snapshots = generateWeekOfSnapshots()
        let profile = PatternProjectionEngine.buildProfile(snapshots: snapshots)

        // Should have entries for all 7 weekdays
        #expect(profile.count == 7)

        // Each weekday should have 24 hour buckets
        for (_, hours) in profile {
            #expect(hours.count == 24)
        }

        let (filled, samples) = PatternProjectionEngine.profileCoverage(profile)
        // With a full week, most buckets should have data
        #expect(filled > 100)
        #expect(samples > 1000)
    }

    @Test("Work hours have higher velocity than night hours")
    func workHoursPattern() {
        let snapshots = generateWeekOfSnapshots()
        let profile = PatternProjectionEngine.buildProfile(snapshots: snapshots)

        let plan = UsagePlan() // default plan (disabled = all hours active)

        // Pick a Monday (weekday 2) at 10 AM vs 3 AM
        let cal = Calendar.current
        let today = Date()
        let monday = cal.nextDate(
            after: today.addingTimeInterval(-8 * 86400),
            matching: DateComponents(hour: 10, weekday: 2),
            matchingPolicy: .nextTime
        )!
        let mondayNight = cal.nextDate(
            after: today.addingTimeInterval(-8 * 86400),
            matching: DateComponents(hour: 3, weekday: 2),
            matchingPolicy: .nextTime
        )!

        let (dayVel, _) = PatternProjectionEngine.velocity(for: monday, from: profile, plan: plan)
        let (nightVel, _) = PatternProjectionEngine.velocity(for: mondayNight, from: profile, plan: plan)

        // Daytime velocity should be notably higher than nighttime
        #expect(dayVel > nightVel)
    }

    // MARK: - Projection

    @Test("Projects forward with enough data")
    func projectWithPattern() {
        let snapshots = generateWeekOfSnapshots()
        let plan = UsagePlan()
        let resetDate = Date().addingTimeInterval(3 * 86400) // resets in 3 days

        let result = PatternProjectionEngine.project(
            snapshots: snapshots,
            currentSevenDay: 40.0,
            sevenDayVelocity: 0.5,
            resetDate: resetDate,
            plan: plan
        )

        #expect(result != nil)
        let projection = result!

        #expect(projection.isPatternAware)
        #expect(projection.confidence > 0.5)
        #expect(projection.projectedAtReset >= 40) // Should project higher
        #expect(projection.projectedAtReset <= 100) // Capped
        #expect(projection.curve.count > 10) // Multiple steps
        #expect(projection.pessimisticAtReset >= projection.projectedAtReset) // More usage = worse
        #expect(projection.optimisticAtReset <= projection.projectedAtReset) // Less usage = better
    }

    @Test("Falls back to flat projection with insufficient data")
    func flatFallback() {
        // Only 2 snapshots — not enough for patterns
        let snapshots = [
            makeSnapshot(hoursAgo: 1, fiveHour: 10, sevenDay: 30),
            makeSnapshot(hoursAgo: 0, fiveHour: 15, sevenDay: 30.5),
        ]
        let plan = UsagePlan()
        let resetDate = Date().addingTimeInterval(86400)

        let result = PatternProjectionEngine.project(
            snapshots: snapshots,
            currentSevenDay: 30.0,
            sevenDayVelocity: 0.5,
            resetDate: resetDate,
            plan: plan
        )

        #expect(result != nil)
        #expect(!result!.isPatternAware) // Not enough data for pattern awareness
        #expect(result!.projectedAtReset > 30) // Still projects forward using flat velocity
    }

    @Test("Returns nil when no velocity and no pattern")
    func nilWithNoData() {
        let snapshots: [UsageSnapshot] = []
        let plan = UsagePlan()
        let resetDate = Date().addingTimeInterval(86400)

        let result = PatternProjectionEngine.project(
            snapshots: snapshots,
            currentSevenDay: 30.0,
            sevenDayVelocity: 0,
            resetDate: resetDate,
            plan: plan
        )

        #expect(result == nil)
    }

    @Test("Respects usage plan inactive hours")
    func respectsInactiveHours() {
        let snapshots = generateWeekOfSnapshots()
        var plan = UsagePlan()
        plan.isEnabled = true
        // Only active 9-17 on weekdays, weekends off

        let profile = PatternProjectionEngine.buildProfile(snapshots: snapshots)

        // Saturday (weekday 7) at noon — should return 0 velocity because plan says day off
        let cal = Calendar.current
        let saturday = cal.nextDate(
            after: Date().addingTimeInterval(-8 * 86400),
            matching: DateComponents(hour: 12, weekday: 7),
            matchingPolicy: .nextTime
        )!

        let (vel, _) = PatternProjectionEngine.velocity(for: saturday, from: profile, plan: plan)
        #expect(vel == 0)
    }

    // MARK: - Confidence Band

    @Test("Confidence band is ordered correctly")
    func confidenceBandOrdering() {
        let snapshots = generateWeekOfSnapshots()
        let plan = UsagePlan()
        let resetDate = Date().addingTimeInterval(2 * 86400)

        let result = PatternProjectionEngine.project(
            snapshots: snapshots,
            currentSevenDay: 40.0,
            sevenDayVelocity: 0.5,
            resetDate: resetDate,
            plan: plan
        )!

        // For each curve point, optimistic ≤ projected ≤ pessimistic
        for point in result.curve {
            #expect(point.optimistic <= point.projected + 0.01) // small float tolerance
            #expect(point.projected <= point.pessimistic + 0.01)
        }
    }
}
