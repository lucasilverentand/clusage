import Testing
import Foundation
@testable import Clusage

@Suite("BudgetEngine")
struct BudgetEngineTests {

    // MARK: - Helpers

    private func makeSevenDayWindow(
        utilization: Double,
        resetsInHours: Double = 168
    ) -> UsageWindow {
        UsageWindow(
            utilization: utilization,
            resetsAt: Date().addingTimeInterval(resetsInHours * 3600),
            duration: UsageWindow.sevenDayDuration
        )
    }

    private func makeWeekdayPlan(startHour: Int = 9, endHour: Int = 23) -> UsagePlan {
        var plan = UsagePlan(isEnabled: true)
        for day in 1...7 {
            let isWeekday = day >= 2 && day <= 6
            plan.slots[day] = DaySlot(isActive: isWeekday, startHour: startHour, endHour: endHour)
        }
        return plan
    }

    // MARK: - Disabled Plan

    @Test("Returns nil when plan is disabled")
    func disabledPlan() {
        let window = makeSevenDayWindow(utilization: 50)
        let plan = UsagePlan(isEnabled: false)

        let result = BudgetEngine.calculateTarget(sevenDayWindow: window, plan: plan)
        #expect(result == nil)
    }

    // MARK: - At 100% Utilization

    @Test("Returns zero budget when already at 100%")
    func fullUtilization() {
        let window = makeSevenDayWindow(utilization: 100)
        let plan = makeWeekdayPlan()

        let result = BudgetEngine.calculateTarget(sevenDayWindow: window, plan: plan)
        #expect(result != nil)
        #expect(result?.remainingBudget == 0)
        #expect(result?.suggestedPace == 0)
    }

    // MARK: - Day Off

    @Test("Day off returns dayOff status")
    func dayOff() {
        let window = makeSevenDayWindow(utilization: 30)

        // Create a plan where today is inactive
        var plan = UsagePlan(isEnabled: true)
        // Set all days as inactive
        for day in 1...7 {
            plan.slots[day] = DaySlot(isActive: false, startHour: 9, endHour: 23)
        }

        let result = BudgetEngine.calculateTarget(sevenDayWindow: window, plan: plan)
        #expect(result != nil)
        #expect(result?.status == .dayOff)
        #expect(result?.isActiveDay == false)
        #expect(result?.remainingBudget == 0)
    }

    // MARK: - Normal Active Day

    @Test("Calculates positive budget on an active day")
    func activeDayBudget() {
        let window = makeSevenDayWindow(utilization: 30)
        let plan = makeWeekdayPlan()

        // Use a time that's in a weekday, mid-day (after startHour, before endHour)
        let cal = Calendar.current
        // Find the next Monday at 14:00
        let monday = cal.nextDate(
            after: Date(),
            matching: DateComponents(hour: 14, weekday: 2),
            matchingPolicy: .nextTime
        )!

        let result = BudgetEngine.calculateTarget(
            sevenDayWindow: window, plan: plan, now: monday
        )
        #expect(result != nil)
        #expect(result!.isActiveDay == true)
        #expect(result!.targetUtilization > 30) // Should be above current
        #expect(result!.targetUtilization <= 100) // Capped
        #expect(result!.remainingBudget > 0)
        #expect(result!.hoursUntilBedtime > 0)
        #expect(result!.suggestedPace > 0)
    }

    // MARK: - Status Determination

    @Test("Status is ahead when velocity is high relative to pace")
    func statusAhead() {
        let window = makeSevenDayWindow(utilization: 30)
        let plan = makeWeekdayPlan()

        let cal = Calendar.current
        let monday = cal.nextDate(
            after: Date(),
            matching: DateComponents(hour: 14, weekday: 2),
            matchingPolicy: .nextTime
        )!

        let result = BudgetEngine.calculateTarget(
            sevenDayWindow: window, plan: plan, currentVelocity: 100, now: monday
        )
        #expect(result != nil)
        #expect(result?.status == .ahead)
    }

    @Test("Status is behind when velocity is low relative to pace")
    func statusBehind() {
        let window = makeSevenDayWindow(utilization: 30)
        let plan = makeWeekdayPlan()

        let cal = Calendar.current
        let monday = cal.nextDate(
            after: Date(),
            matching: DateComponents(hour: 14, weekday: 2),
            matchingPolicy: .nextTime
        )!

        let result = BudgetEngine.calculateTarget(
            sevenDayWindow: window, plan: plan, currentVelocity: 0.01, now: monday
        )
        #expect(result != nil)
        #expect(result?.status == .behind)
    }

    // MARK: - After Bedtime

    @Test("After bedtime returns zero remaining budget")
    func afterBedtime() {
        let window = makeSevenDayWindow(utilization: 30)
        let plan = makeWeekdayPlan(startHour: 9, endHour: 23)

        let cal = Calendar.current
        // 23:30 on a Monday — past bedtime
        let lateMonday = cal.nextDate(
            after: Date(),
            matching: DateComponents(hour: 23, minute: 30, weekday: 2),
            matchingPolicy: .nextTime
        )!

        let result = BudgetEngine.calculateTarget(
            sevenDayWindow: window, plan: plan, now: lateMonday
        )
        #expect(result != nil)
        #expect(result!.hoursUntilBedtime == 0)
        #expect(result!.remainingBudget == 0)
        #expect(result!.suggestedPace == 0)
    }

    // MARK: - Current Target Progress

    @Test("Current target increases as the day progresses")
    func currentTargetProgresses() {
        let window = makeSevenDayWindow(utilization: 30)
        let plan = makeWeekdayPlan(startHour: 9, endHour: 23)

        let cal = Calendar.current
        let monday9am = cal.nextDate(
            after: Date(),
            matching: DateComponents(hour: 9, weekday: 2),
            matchingPolicy: .nextTime
        )!
        let monday16pm = cal.nextDate(
            after: Date(),
            matching: DateComponents(hour: 16, weekday: 2),
            matchingPolicy: .nextTime
        )!

        let earlyResult = BudgetEngine.calculateTarget(
            sevenDayWindow: window, plan: plan, now: monday9am
        )
        let lateResult = BudgetEngine.calculateTarget(
            sevenDayWindow: window, plan: plan, now: monday16pm
        )

        #expect(earlyResult != nil)
        #expect(lateResult != nil)
        // Later in the day, the current target should be higher
        #expect(lateResult!.currentTarget > earlyResult!.currentTarget)
        // But the end-of-day target should be the same
        #expect(abs(lateResult!.targetUtilization - earlyResult!.targetUtilization) < 0.5)
    }
}
