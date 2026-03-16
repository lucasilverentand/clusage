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
    static func calculateTarget(
        sevenDayWindow: UsageWindow,
        plan: UsagePlan,
        currentVelocity: Double = 0,
        now: Date = .now
    ) -> DailyTarget? {
        guard plan.isEnabled else { return nil }

        let current7Day = sevenDayWindow.utilization
        let totalBudget = max(100 - current7Day, 0)
        let resetDate = sevenDayWindow.resetsAt

        // Already at or above 100% — nothing left to budget
        if totalBudget <= 0 {
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

        // After bedtime — cap at end-of-schedule target
        guard hoursUntilBedtime > 0.1 else {
            // Calculate what the end-of-day target would have been
            let totalActiveHoursForCap = plan.activeHoursRemaining(until: resetDate, from: now)
            let budgetPerHourCap = totalActiveHoursForCap > 0 ? totalBudget / totalActiveHoursForCap : totalBudget
            let slotHours = Double(slot.activeHours)
            let endOfDayTarget = min(current7Day + budgetPerHourCap * slotHours, 100)

            return DailyTarget(
                targetUtilization: endOfDayTarget,
                currentTarget: endOfDayTarget,
                remainingBudget: 0,
                hoursUntilBedtime: 0,
                suggestedPace: 0,
                status: .onTrack,
                bedtime: bedtime,
                isActiveDay: true,
                slot: slot
            )
        }

        // Calculate total active hours from now until the 7-day window resets
        let totalActiveHours = plan.activeHoursRemaining(until: resetDate, from: now)
        guard totalActiveHours > 0 else { return nil }

        // Budget per active hour
        let budgetPerHour = totalBudget / totalActiveHours

        // Full-day allocation = budget rate * total active hours in today's slot
        let todayFullBudget = min(budgetPerHour * Double(slot.activeHours), totalBudget)
        let targetUtilization = min(current7Day + todayFullBudget, 100)

        // How far through the slot we are
        let hoursIntoSlot = max(Double(slot.activeHours) - hoursUntilBedtime, 0)
        let currentTarget = min(current7Day + budgetPerHour * hoursIntoSlot, 100)

        // Remaining budget from now until bedtime
        let remainingBudget = min(budgetPerHour * hoursUntilBedtime, totalBudget)

        // Suggested pace
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
