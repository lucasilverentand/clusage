import Foundation

enum BudgetEngine {
    struct DailyTarget: Sendable {
        /// The 7-day utilization % to reach by bedtime tonight.
        let targetUtilization: Double
        /// The 7-day utilization % you should be at right now for a consistent pace.
        let currentTarget: Double
        /// Percentage points of budget allocated for today.
        let remainingBudget: Double
        /// Hours until bedtime.
        let hoursUntilBedtime: Double
        /// Suggested pace (pp/hr) to hit the target evenly.
        let suggestedPace: Double
        /// Whether the user is ahead, on track, or behind.
        let status: Status
        /// Bedtime as a displayable date.
        let bedtime: Date
        /// Whether today is an active day.
        let isActiveDay: Bool
        /// The slot used for today (for exception editing).
        let slot: DaySlot

        enum Status: Sendable {
            case ahead
            case onTrack
            case behind
            case dayOff

            var label: String {
                switch self {
                case .ahead: "Ahead"
                case .onTrack: "On Track"
                case .behind: "Behind"
                case .dayOff: "Day Off"
                }
            }
        }
    }

    /// Calculate today's usage target based on the 7-day window and the usage plan.
    ///
    /// Targets are cycle-aware: the window start is derived from `resetsAt - duration`,
    /// and ideal utilisation at any moment equals the fraction of active hours elapsed
    /// within the full 7-day cycle. This means the target starts near 0% right after a
    /// reset instead of jumping to the current 7-day utilisation.
    static func calculateTarget(
        sevenDayWindow: UsageWindow,
        plan: UsagePlan,
        currentVelocity: Double = 0,
        now: Date = .now
    ) -> DailyTarget? {
        guard plan.isEnabled else { return nil }

        let current7Day = sevenDayWindow.utilization
        let resetDate = sevenDayWindow.resetsAt
        let windowStart = resetDate.addingTimeInterval(-sevenDayWindow.duration)

        // Already at or above 100% — nothing left to budget
        if current7Day >= 100 {
            let slot = plan.todaySlot(at: now) ?? DaySlot()
            return DailyTarget(
                targetUtilization: current7Day,
                currentTarget: current7Day,
                remainingBudget: 0,
                hoursUntilBedtime: 0,
                suggestedPace: 0,
                status: .onTrack,
                bedtime: now,
                isActiveDay: true,
                slot: slot
            )
        }

        // Check if today is an active day
        guard let slot = plan.todaySlot(at: now), slot.isActive else {
            // Day off — target is to not use anything
            return DailyTarget(
                targetUtilization: current7Day,
                currentTarget: current7Day,
                remainingBudget: 0,
                hoursUntilBedtime: 0,
                suggestedPace: 0,
                status: .dayOff,
                bedtime: now,
                isActiveDay: false,
                slot: plan.todaySlot(at: now) ?? DaySlot(isActive: false)
            )
        }

        guard let bedtime = plan.bedtime(for: now) else { return nil }
        let hoursUntilBedtime = max(bedtime.timeIntervalSince(now) / TimeConstants.hour, 0)

        // Total active hours across the full 7-day cycle
        let totalCycleActiveHours = plan.activeHoursRemaining(until: resetDate, from: windowStart)
        guard totalCycleActiveHours > 0 else { return nil }

        let budgetPerActiveHour = 100.0 / totalCycleActiveHours

        // Ideal utilisation right now based on cycle position
        let elapsedActiveHours = plan.activeHoursRemaining(until: now, from: windowStart)
        let currentTarget = min(budgetPerActiveHour * elapsedActiveHours, 100)

        // Ideal utilisation at bedtime tonight
        let activeHoursAtBedtime = plan.activeHoursRemaining(until: bedtime, from: windowStart)
        let targetUtilization = min(budgetPerActiveHour * activeHoursAtBedtime, 100)

        // After bedtime — cap at end-of-schedule target
        guard hoursUntilBedtime > 0.1 else {
            return DailyTarget(
                targetUtilization: targetUtilization,
                currentTarget: targetUtilization,
                remainingBudget: 0,
                hoursUntilBedtime: 0,
                suggestedPace: 0,
                status: .onTrack,
                bedtime: bedtime,
                isActiveDay: true,
                slot: slot
            )
        }

        // Remaining budget: how much more can be used to reach tonight's target
        let remainingBudget = max(targetUtilization - current7Day, 0)

        // Suggested pace to spread remaining budget evenly until bedtime
        let suggestedPace = hoursUntilBedtime > 0 ? remainingBudget / hoursUntilBedtime : 0

        // Determine status by comparing current velocity to the suggested pace.
        // "Ahead" means consuming faster than planned (bad), "behind" means conserving (good).
        let status: DailyTarget.Status
        if suggestedPace > 0, currentVelocity > 0 {
            let paceRatio = currentVelocity / suggestedPace
            if paceRatio > 1.3 {
                status = .ahead
            } else if paceRatio < 0.7 {
                status = .behind
            } else {
                status = .onTrack
            }
        } else {
            status = .onTrack
        }

        return DailyTarget(
            targetUtilization: targetUtilization,
            currentTarget: currentTarget,
            remainingBudget: remainingBudget,
            hoursUntilBedtime: hoursUntilBedtime,
            suggestedPace: suggestedPace,
            status: status,
            bedtime: bedtime,
            isActiveDay: true,
            slot: slot
        )
    }
}
