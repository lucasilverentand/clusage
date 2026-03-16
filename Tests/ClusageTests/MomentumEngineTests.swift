import Testing
import Foundation
@testable import Clusage

@Suite("MomentumEngine")
struct MomentumEngineTests {
    private let accountID = UUID()

    private func makeSnapshot(
        minutesAgo: Double,
        fiveHour: Double,
        sevenDay: Double = 0
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

    // MARK: - Velocity

    @Test("Computes velocity from snapshots")
    func velocityFromSnapshots() {
        // 10 pp over 30 minutes = 20 pp/hr
        let snapshots = [
            makeSnapshot(minutesAgo: 30, fiveHour: 10),
            makeSnapshot(minutesAgo: 25, fiveHour: 12),
            makeSnapshot(minutesAgo: 20, fiveHour: 14),
            makeSnapshot(minutesAgo: 15, fiveHour: 16),
            makeSnapshot(minutesAgo: 10, fiveHour: 18),
            makeSnapshot(minutesAgo: 0, fiveHour: 20),
        ]

        let velocity = MomentumEngine.computeVelocity(snapshots: snapshots)
        // Weighted regression biases toward recent data; on linear input it's close to 20
        #expect(abs(velocity - 20) < 3)
    }

    @Test("Zero velocity when utilization unchanged")
    func zeroVelocity() {
        let snapshots = [
            makeSnapshot(minutesAgo: 30, fiveHour: 50),
            makeSnapshot(minutesAgo: 15, fiveHour: 50),
            makeSnapshot(minutesAgo: 0, fiveHour: 50),
        ]

        let velocity = MomentumEngine.computeVelocity(snapshots: snapshots)
        #expect(velocity == 0)
    }

    @Test("No velocity with insufficient snapshots")
    func insufficientSnapshots() {
        let snapshots = [makeSnapshot(minutesAgo: 0, fiveHour: 50)]
        let velocity = MomentumEngine.computeVelocity(snapshots: snapshots)
        #expect(velocity == 0)
    }

    @Test("Negative utilization delta returns zero velocity")
    func negativeUtilizationDelta() {
        let snapshots = [
            makeSnapshot(minutesAgo: 30, fiveHour: 50),
            makeSnapshot(minutesAgo: 0, fiveHour: 40),
        ]

        let velocity = MomentumEngine.computeVelocity(snapshots: snapshots)
        #expect(velocity == 0)
    }

    // MARK: - ETA

    @Test("ETA to ceiling calculated correctly")
    func etaToCeiling() {
        // 20 pp/hr velocity, at 60% → 40% remaining → 2 hours = 7200s
        let snapshots = [
            makeSnapshot(minutesAgo: 30, fiveHour: 50),
            makeSnapshot(minutesAgo: 0, fiveHour: 60),
        ]

        let window = UsageWindow(
            utilization: 60,
            resetsAt: Date().addingTimeInterval(4 * 3600),
            duration: UsageWindow.fiveHourDuration
        )

        let result = MomentumEngine.calculate(snapshots: snapshots, window: window)
        #expect(result != nil)
        if let eta = result?.etaToCeiling {
            #expect(abs(eta - 7200) < 60) // within a minute tolerance
        }
    }

    @Test("Sleep-adjusted ETA stretches the projection")
    func sleepAdjustedETA() {
        let snapshots = [
            makeSnapshot(minutesAgo: 30, fiveHour: 50),
            makeSnapshot(minutesAgo: 0, fiveHour: 60),
        ]

        // Reset far enough out (7 days) so inactive hours accumulate across multiple days.
        // With 16h active / 24h per day, wall-clock / active ≈ 1.5.
        let window = UsageWindow(
            utilization: 60,
            resetsAt: Date().addingTimeInterval(7 * 86400),
            duration: UsageWindow.fiveHourDuration
        )

        // 16 active hours/day (7 AM to 11 PM) → stretch ≈ 24/16 = 1.5
        var plan = UsagePlan(isEnabled: true)
        for day in 1...7 {
            plan.slots[day] = DaySlot(isActive: true, startHour: 7, endHour: 23)
        }

        let result = MomentumEngine.calculate(snapshots: snapshots, window: window, usagePlan: plan)
        let noSleepResult = MomentumEngine.calculate(snapshots: snapshots, window: window)

        #expect(result != nil)
        #expect(noSleepResult != nil)
        if let sleepETA = result?.etaToCeiling, let rawETA = noSleepResult?.etaToCeiling {
            #expect(sleepETA > rawETA)
            // Over 7 full days the ratio should converge to ~1.5
            let ratio = sleepETA / rawETA
            #expect(ratio > 1.3)
            #expect(ratio < 1.7)
        }
    }

    @Test("Resets-first flag when window resets before ceiling")
    func resetsFirstFlag() {
        // High velocity but window resets soon
        let snapshots = [
            makeSnapshot(minutesAgo: 29, fiveHour: 0),
            makeSnapshot(minutesAgo: 0, fiveHour: 5),
        ]

        let window = UsageWindow(
            utilization: 5,
            resetsAt: Date().addingTimeInterval(3600), // resets in 1 hour
            duration: UsageWindow.fiveHourDuration
        )

        let result = MomentumEngine.calculate(snapshots: snapshots, window: window)
        #expect(result?.resetsFirst == true)
    }

    // MARK: - Intensity

    @Test("Intensity thresholds map correctly")
    func intensityThresholds() {
        #expect(MomentumCalculation.Intensity(velocity: 0) == .idle)
        #expect(MomentumCalculation.Intensity(velocity: 0.5) == .idle)
        #expect(MomentumCalculation.Intensity(velocity: 1) == .steady)
        #expect(MomentumCalculation.Intensity(velocity: 3) == .steady)
        #expect(MomentumCalculation.Intensity(velocity: 5) == .moderate)
        #expect(MomentumCalculation.Intensity(velocity: 10) == .moderate)
        #expect(MomentumCalculation.Intensity(velocity: 15) == .high)
        #expect(MomentumCalculation.Intensity(velocity: 25) == .high)
        #expect(MomentumCalculation.Intensity(velocity: 30) == .burning)
        #expect(MomentumCalculation.Intensity(velocity: 50) == .burning)
    }

    // MARK: - Burst Detection

    @Test("Detects a burst in usage")
    func detectsBurst() {
        // Steady low usage, then a spike
        var snapshots: [UsageSnapshot] = []
        // Low velocity for 2 hours (24 snapshots at 5-min intervals)
        for i in 0..<24 {
            snapshots.append(makeSnapshot(
                minutesAgo: Double(150 - i * 5),
                fiveHour: Double(i) * 0.5 // 6 pp/hr
            ))
        }
        // Then a sharp burst
        snapshots.append(makeSnapshot(minutesAgo: 25, fiveHour: 20))
        snapshots.append(makeSnapshot(minutesAgo: 20, fiveHour: 30))
        snapshots.append(makeSnapshot(minutesAgo: 15, fiveHour: 40))
        snapshots.append(makeSnapshot(minutesAgo: 10, fiveHour: 50))
        // Then back to normal
        snapshots.append(makeSnapshot(minutesAgo: 5, fiveHour: 51))
        snapshots.append(makeSnapshot(minutesAgo: 0, fiveHour: 52))

        let summary = MomentumEngine.detectBursts(snapshots: snapshots)
        let totalBursts = summary.recentBursts.count + (summary.activeBurst != nil ? 1 : 0)
        #expect(totalBursts >= 1)
    }

    @Test("No false bursts on steady usage")
    func noFalseBursts() {
        // Perfectly linear usage
        var snapshots: [UsageSnapshot] = []
        for i in 0..<12 {
            snapshots.append(makeSnapshot(
                minutesAgo: Double(55 - i * 5),
                fiveHour: Double(i) * 2
            ))
        }

        let summary = MomentumEngine.detectBursts(snapshots: snapshots)
        let totalBursts = summary.recentBursts.count + (summary.activeBurst != nil ? 1 : 0)
        #expect(totalBursts == 0)
        #expect(summary.pattern == .steady)
    }

    // MARK: - Streaks

    @Test("Streak increments on active day")
    func streakIncrements() {
        let streak = UsageStreak()
        let today = UsageStreak.dayKey()
        let snapshot = makeSnapshot(minutesAgo: 5, fiveHour: 20)

        let updated = MomentumEngine.updateStreak(streak, snapshots: [snapshot])
        #expect(updated.currentStreak == 1)
        #expect(updated.activeDays.contains(today))
    }

    @Test("Streak resets when no activity")
    func streakResets() {
        var streak = UsageStreak()
        // Mark yesterday as active
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now)!
        streak.markActive(date: yesterday)
        #expect(streak.currentStreak == 1)

        // No activity today → streak breaks
        let updated = MomentumEngine.updateStreak(streak, snapshots: [])
        #expect(updated.currentStreak == 0)
    }

    @Test("Old streak days get pruned")
    func streakPruning() {
        var streak = UsageStreak()
        let calendar = Calendar.current

        // Add a day from 100 days ago (beyond 90-day retention)
        let oldDate = calendar.date(byAdding: .day, value: -100, to: .now)!
        streak.activeDays.insert(UsageStreak.dayKey(for: oldDate))

        // Add today
        streak.markActive()

        // Old day should be pruned
        let oldKey = UsageStreak.dayKey(for: oldDate)
        #expect(!streak.activeDays.contains(oldKey))
    }

    @Test("Streak increments when utilization meets daily target")
    func streakWithDailyTarget() {
        let streak = UsageStreak()
        let target = BudgetEngine.DailyTarget(
            targetUtilization: 30,
            currentTarget: 20,
            remainingBudget: 10,
            hoursUntilBedtime: 5,
            suggestedPace: 2,
            status: .onTrack,
            bedtime: .now.addingTimeInterval(5 * 3600),
            isActiveDay: true,
            slot: DaySlot()
        )
        // Utilization at 25% exceeds currentTarget of 20%
        let updated = MomentumEngine.updateStreak(
            streak, snapshots: [], dailyTarget: target, currentUtilization: 25
        )
        #expect(updated.currentStreak == 1)
    }

    @Test("Streak does not increment when utilization below daily target")
    func streakBelowDailyTarget() {
        var streak = UsageStreak()
        streak.markActive(date: Calendar.current.date(byAdding: .day, value: -1, to: .now)!)

        let target = BudgetEngine.DailyTarget(
            targetUtilization: 30,
            currentTarget: 20,
            remainingBudget: 10,
            hoursUntilBedtime: 5,
            suggestedPace: 2,
            status: .behind,
            bedtime: .now.addingTimeInterval(5 * 3600),
            isActiveDay: true,
            slot: DaySlot()
        )
        // Utilization at 15% is below currentTarget of 20%
        let updated = MomentumEngine.updateStreak(
            streak, snapshots: [], dailyTarget: target, currentUtilization: 15
        )
        #expect(updated.currentStreak == 0)
    }

    @Test("Day off leaves streak unchanged (doesn't mark or break)")
    func streakDayOff() {
        var streak = UsageStreak()
        // Build a 2-day streak first
        let cal = Calendar.current
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: .now)!
        let yesterday = cal.date(byAdding: .day, value: -1, to: .now)!
        streak.markActive(date: twoDaysAgo)
        streak.markActive(date: yesterday)
        #expect(streak.currentStreak == 2)

        let target = BudgetEngine.DailyTarget(
            targetUtilization: 20,
            currentTarget: 20,
            remainingBudget: 0,
            hoursUntilBedtime: 0,
            suggestedPace: 0,
            status: .dayOff,
            bedtime: .now,
            isActiveDay: false,
            slot: DaySlot()
        )
        let updated = MomentumEngine.updateStreak(
            streak, snapshots: [], dailyTarget: target, currentUtilization: 0
        )
        // Day off should preserve existing streak, not increment or break it
        #expect(updated.currentStreak == 2)
    }

    // MARK: - Window Projection

    private func makeProjectionSnapshot(
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

    @Test("7-day velocity computed from sevenDayUtilization snapshots")
    func sevenDayVelocity() {
        // 6 pp over 30 minutes = 12 pp/hr on the 7-day metric
        let snapshots = [
            makeProjectionSnapshot(minutesAgo: 30, fiveHour: 10, sevenDay: 20),
            makeProjectionSnapshot(minutesAgo: 15, fiveHour: 15, sevenDay: 23),
            makeProjectionSnapshot(minutesAgo: 0, fiveHour: 20, sevenDay: 26),
        ]

        let velocity = MomentumEngine.computeVelocity(
            snapshots: snapshots,
            keyPath: \.sevenDayUtilization
        )
        #expect(abs(velocity - 12) < 1.5)
    }

    @Test("Projection at reset uses linear extrapolation")
    func projectionAtReset() {
        // 7-day at 40%, velocity ~12 pp/hr, 3 days remaining = 72 hours
        let snapshots = [
            makeProjectionSnapshot(minutesAgo: 30, fiveHour: 10, sevenDay: 34),
            makeProjectionSnapshot(minutesAgo: 15, fiveHour: 15, sevenDay: 37),
            makeProjectionSnapshot(minutesAgo: 0, fiveHour: 20, sevenDay: 40),
        ]

        let sevenDayWindow = UsageWindow(
            utilization: 40,
            resetsAt: Date().addingTimeInterval(3 * 86400),
            duration: UsageWindow.sevenDayDuration
        )

        let result = MomentumEngine.projectWindows(
            snapshots: snapshots,
            fiveHourWindow: nil,
            sevenDayWindow: sevenDayWindow,
            usagePlan: UsagePlan()
        )

        #expect(result != nil)
        // 12 pp/hr * 72h = 864 → capped at 100
        #expect(result!.projectedAtReset == 100)
    }

    @Test("Daily budget = remaining headroom / remaining days")
    func dailyBudget() {
        let snapshots = [
            makeProjectionSnapshot(minutesAgo: 30, fiveHour: 10, sevenDay: 30),
            makeProjectionSnapshot(minutesAgo: 15, fiveHour: 12, sevenDay: 31),
            makeProjectionSnapshot(minutesAgo: 0, fiveHour: 14, sevenDay: 32),
        ]

        let sevenDayWindow = UsageWindow(
            utilization: 32,
            resetsAt: Date().addingTimeInterval(4 * 86400), // 4 days remaining
            duration: UsageWindow.sevenDayDuration
        )

        let result = MomentumEngine.projectWindows(
            snapshots: snapshots,
            fiveHourWindow: nil,
            sevenDayWindow: sevenDayWindow,
            usagePlan: UsagePlan()
        )

        #expect(result != nil)
        // Budget = (100 - 32) / 4 = 17 pp/day
        #expect(abs(result!.dailyBudget - 17) < 0.5)
    }

    @Test("Status thresholds: under/on/at risk/over")
    func statusThresholds() {
        // Under budget: dailyProjected < 80% of dailyBudget
        #expect(WindowProjection.Status(dailyProjected: 7, dailyBudget: 10) == .underBudget)

        // On track: dailyProjected < 100% of dailyBudget
        #expect(WindowProjection.Status(dailyProjected: 9, dailyBudget: 10) == .onTrack)

        // At risk: dailyProjected < 120% of dailyBudget
        #expect(WindowProjection.Status(dailyProjected: 11, dailyBudget: 10) == .atRisk)

        // Over budget: dailyProjected >= 120% of dailyBudget
        #expect(WindowProjection.Status(dailyProjected: 13, dailyBudget: 10) == .overBudget)
    }

    @Test("Granular 7-day interpolates above integer tick using velocity × time-since-tick")
    func granular7DayInterpolation() {
        // 7-day ticked from 45 → 46 at 15 min ago, 5-hour rose alongside it.
        // After the tick, 7-day stays flat but velocity ~2 pp/hr means
        // granular should be 46 + 2 * 0.25 ≈ 46.5 — above 46 but below 47.
        let snapshots = [
            makeProjectionSnapshot(minutesAgo: 30, fiveHour: 8, sevenDay: 45),
            makeProjectionSnapshot(minutesAgo: 15, fiveHour: 15, sevenDay: 46), // tick here
            makeProjectionSnapshot(minutesAgo: 0, fiveHour: 18, sevenDay: 46),  // 7-day flat
        ]

        let sevenDayWindow = UsageWindow(
            utilization: 46,
            resetsAt: Date().addingTimeInterval(4 * 86400),
            duration: UsageWindow.sevenDayDuration
        )

        let result = MomentumEngine.projectWindows(
            snapshots: snapshots,
            fiveHourWindow: nil,
            sevenDayWindow: sevenDayWindow,
            usagePlan: UsagePlan()
        )

        #expect(result != nil)
        #expect(result?.lastTickTimestamp != nil)
        if let granular = result?.currentGranularUtilization() {
            #expect(granular > 46)
            #expect(granular < 47)
        }
    }

    @Test("Zero velocity returns nil projection")
    func zeroVelocityNilProjection() {
        let snapshots = [
            makeProjectionSnapshot(minutesAgo: 30, fiveHour: 50, sevenDay: 30),
            makeProjectionSnapshot(minutesAgo: 15, fiveHour: 50, sevenDay: 30),
            makeProjectionSnapshot(minutesAgo: 0, fiveHour: 50, sevenDay: 30),
        ]

        let sevenDayWindow = UsageWindow(
            utilization: 30,
            resetsAt: Date().addingTimeInterval(5 * 86400),
            duration: UsageWindow.sevenDayDuration
        )

        let result = MomentumEngine.projectWindows(
            snapshots: snapshots,
            fiveHourWindow: nil,
            sevenDayWindow: sevenDayWindow,
            usagePlan: UsagePlan()
        )

        #expect(result == nil)
    }

    @Test("5-hour fallback when 7-day data is flat but 5h is active")
    func fiveHourFallback() {
        // 7-day utilization flat, but 5-hour is active → should estimate
        let snapshots = [
            makeProjectionSnapshot(minutesAgo: 30, fiveHour: 10, sevenDay: 30),
            makeProjectionSnapshot(minutesAgo: 15, fiveHour: 15, sevenDay: 30),
            makeProjectionSnapshot(minutesAgo: 0, fiveHour: 20, sevenDay: 30),
        ]

        let sevenDayWindow = UsageWindow(
            utilization: 30,
            resetsAt: Date().addingTimeInterval(5 * 86400),
            duration: UsageWindow.sevenDayDuration
        )

        let result = MomentumEngine.projectWindows(
            snapshots: snapshots,
            fiveHourWindow: nil,
            sevenDayWindow: sevenDayWindow,
            usagePlan: UsagePlan()
        )

        // Should produce a projection using the 5h→7d ratio estimate
        #expect(result != nil)
        #expect(result!.sevenDayVelocity > 0)
    }
}
