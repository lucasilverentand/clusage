import Foundation

@Observable
@MainActor final class MomentumProvider {
    private let historyStore: UsageHistoryStore
    private let streakStore: StreakStore
    private let accountStore: AccountStore
    let ratioCalibrationStore: RatioCalibrationStore

    private(set) var momentumByAccount: [UUID: MomentumCalculation] = [:]
    private(set) var burstByAccount: [UUID: BurstSummary] = [:]
    private(set) var streakByAccount: [UUID: UsageStreak] = [:]
    private(set) var projectionByAccount: [UUID: WindowProjection] = [:]
    private(set) var targetByAccount: [UUID: BudgetEngine.DailyTarget] = [:]

    init(
        historyStore: UsageHistoryStore,
        streakStore: StreakStore,
        accountStore: AccountStore,
        ratioCalibrationStore: RatioCalibrationStore = RatioCalibrationStore()
    ) {
        self.historyStore = historyStore
        self.streakStore = streakStore
        self.accountStore = accountStore
        self.ratioCalibrationStore = ratioCalibrationStore
    }

    func refresh() {
        // Prune stale data for removed accounts
        let currentIDs = Set(accountStore.accounts.map(\.id))
        for id in momentumByAccount.keys where !currentIDs.contains(id) {
            momentumByAccount.removeValue(forKey: id)
            burstByAccount.removeValue(forKey: id)
            streakByAccount.removeValue(forKey: id)
            projectionByAccount.removeValue(forKey: id)
            targetByAccount.removeValue(forKey: id)
        }

        for account in accountStore.accounts {
            let snapshots = historyStore.snapshots(for: account.id)
            let plan = account.usagePlan

            // Momentum
            if let momentum = MomentumEngine.calculate(
                snapshots: snapshots,
                window: account.fiveHour,
                usagePlan: plan
            ) {
                momentumByAccount[account.id] = momentum
            }

            // Bursts
            burstByAccount[account.id] = MomentumEngine.detectBursts(snapshots: snapshots)

            // Calibrate 5h↔7d ratio from snapshot history, then use it for projection
            ratioCalibrationStore.calibrate(from: snapshots, accountID: account.id)
            let ratio = ratioCalibrationStore.calibratedRatio(for: account.id)

            // Projection
            if let projection = MomentumEngine.projectWindows(
                snapshots: snapshots,
                fiveHourWindow: account.fiveHour,
                sevenDayWindow: account.sevenDay,
                usagePlan: plan,
                calibratedRatio: ratio
            ) {
                projectionByAccount[account.id] = projection
            }

            // Daily target
            if let sevenDay = account.sevenDay {
                let velocity = projectionByAccount[account.id]?.sevenDayVelocity ?? 0
                targetByAccount[account.id] = BudgetEngine.calculateTarget(
                    sevenDayWindow: sevenDay,
                    plan: plan,
                    currentVelocity: velocity
                )
            }

            // Streaks — use daily target when the plan is active
            let currentStreak = streakStore.streak(for: account.id)
            let target = targetByAccount[account.id]
            let utilization = account.sevenDay?.utilization
            let updatedStreak = MomentumEngine.updateStreak(
                currentStreak,
                snapshots: snapshots,
                dailyTarget: target,
                currentUtilization: utilization
            )
            streakByAccount[account.id] = updatedStreak
            streakStore.update(updatedStreak, for: account.id)
        }

        streakStore.save()
        Log.momentum.debug("Momentum refreshed for \(self.accountStore.accounts.count) account(s)")
    }

    func clearCalculations() {
        momentumByAccount.removeAll()
        burstByAccount.removeAll()
        streakByAccount.removeAll()
        projectionByAccount.removeAll()
        targetByAccount.removeAll()
    }

    func momentum(for accountID: UUID) -> MomentumCalculation? {
        momentumByAccount[accountID]
    }

    func burstSummary(for accountID: UUID) -> BurstSummary? {
        burstByAccount[accountID]
    }

    func streak(for accountID: UUID) -> UsageStreak? {
        streakByAccount[accountID]
    }

    func projection(for accountID: UUID) -> WindowProjection? {
        projectionByAccount[accountID]
    }

    func dailyTarget(for accountID: UUID) -> BudgetEngine.DailyTarget? {
        targetByAccount[accountID]
    }
}
