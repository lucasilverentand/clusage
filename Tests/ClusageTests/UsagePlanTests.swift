import Testing
import Foundation
@testable import Clusage

@Suite("UsagePlan")
struct UsagePlanTests {

    // MARK: - DaySlot Active Hours

    @Test("Active hours for same-day slot")
    func sameDayActiveHours() {
        let slot = DaySlot(isActive: true, startHour: 9, endHour: 23)
        #expect(slot.activeHours == 14)
    }

    @Test("Active hours for midnight-wrapping slot")
    func midnightWrappingActiveHours() {
        let slot = DaySlot(isActive: true, startHour: 9, endHour: 1)
        #expect(slot.activeHours == 16) // 9 AM to 1 AM
    }

    @Test("Active hours is 24 when start equals end")
    func fullDayActiveHours() {
        let slot = DaySlot(isActive: true, startHour: 9, endHour: 9)
        #expect(slot.activeHours == 24)
    }

    @Test("Active hours is 0 when inactive")
    func inactiveSlotActiveHours() {
        let slot = DaySlot(isActive: false, startHour: 9, endHour: 23)
        #expect(slot.activeHours == 0)
    }

    // MARK: - Plan Calendar Day

    @Test("Plan day maps correctly after boundary")
    func planDayAfterBoundary() {
        let cal = Calendar.current
        // 10 AM on any day should be the same day
        let tenAM = cal.date(bySettingHour: 10, minute: 0, second: 0, of: .now)!
        let planDay = UsagePlan.planCalendarDay(for: tenAM)
        #expect(cal.isDate(planDay, inSameDayAs: tenAM))
    }

    @Test("Plan day maps to previous day before boundary")
    func planDayBeforeBoundary() {
        let cal = Calendar.current
        // 3 AM should map to yesterday's plan day
        let threeAM = cal.date(bySettingHour: 3, minute: 0, second: 0, of: .now)!
        let planDay = UsagePlan.planCalendarDay(for: threeAM)
        let yesterday = cal.date(byAdding: .day, value: -1, to: threeAM)!
        #expect(cal.isDate(planDay, inSameDayAs: yesterday))
    }

    // MARK: - Plan Weekday

    @Test("Plan weekday is correct for daytime")
    func planWeekdayDaytime() {
        let cal = Calendar.current
        let tenAM = cal.date(bySettingHour: 10, minute: 0, second: 0, of: .now)!
        let expected = cal.component(.weekday, from: tenAM)
        #expect(UsagePlan.planWeekday(for: tenAM) == expected)
    }

    @Test("Plan weekday shifts for early morning")
    func planWeekdayEarlyMorning() {
        let cal = Calendar.current
        let threeAM = cal.date(bySettingHour: 3, minute: 0, second: 0, of: .now)!
        let yesterday = cal.date(byAdding: .day, value: -1, to: threeAM)!
        let expected = cal.component(.weekday, from: yesterday)
        #expect(UsagePlan.planWeekday(for: threeAM) == expected)
    }

    // MARK: - isActiveTime

    @Test("Active during slot hours")
    func activeTimeDuringSlot() {
        var plan = UsagePlan(isEnabled: true)
        for day in 1...7 {
            plan.slots[day] = DaySlot(isActive: true, startHour: 9, endHour: 23)
        }

        let cal = Calendar.current
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
        #expect(plan.isActiveTime(noon))
    }

    @Test("Inactive outside slot hours")
    func inactiveTimeOutsideSlot() {
        var plan = UsagePlan(isEnabled: true)
        for day in 1...7 {
            plan.slots[day] = DaySlot(isActive: true, startHour: 9, endHour: 17)
        }

        let cal = Calendar.current
        let eightPM = cal.date(bySettingHour: 20, minute: 0, second: 0, of: .now)!
        #expect(!plan.isActiveTime(eightPM))
    }

    @Test("Always active when plan is disabled")
    func alwaysActiveWhenDisabled() {
        let plan = UsagePlan(isEnabled: false)
        let cal = Calendar.current
        let threeAM = cal.date(bySettingHour: 3, minute: 0, second: 0, of: .now)!
        #expect(plan.isActiveTime(threeAM))
    }

    @Test("24-hour slot is always active")
    func fullDaySlotAlwaysActive() {
        var plan = UsagePlan(isEnabled: true)
        for day in 1...7 {
            plan.slots[day] = DaySlot(isActive: true, startHour: 0, endHour: 0)
        }

        let cal = Calendar.current
        // Test various hours — all should be active
        for hour in [6, 12, 18, 23] {
            let date = cal.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!
            #expect(plan.isActiveTime(date))
        }
    }

    // MARK: - Bedtime

    @Test("Bedtime is at the slot end hour")
    func bedtimeAtEndHour() {
        var plan = UsagePlan(isEnabled: true)
        for day in 1...7 {
            plan.slots[day] = DaySlot(isActive: true, startHour: 9, endHour: 23)
        }

        let cal = Calendar.current
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
        guard let bedtime = plan.bedtime(for: noon) else {
            Issue.record("Expected bedtime to be non-nil")
            return
        }
        #expect(cal.component(.hour, from: bedtime) == 23)
    }

    @Test("Bedtime wraps to next day for overnight slot")
    func bedtimeWrapsOvernight() {
        var plan = UsagePlan(isEnabled: true)
        for day in 1...7 {
            plan.slots[day] = DaySlot(isActive: true, startHour: 9, endHour: 1)
        }

        let cal = Calendar.current
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
        guard let bedtime = plan.bedtime(for: noon) else {
            Issue.record("Expected bedtime to be non-nil")
            return
        }
        #expect(cal.component(.hour, from: bedtime) == 1)
        // Bedtime should be tomorrow
        #expect(bedtime > noon)
    }

    @Test("Bedtime is nil when plan is disabled")
    func bedtimeNilWhenDisabled() {
        let plan = UsagePlan(isEnabled: false)
        #expect(plan.bedtime() == nil)
    }

    // MARK: - Active Hours Remaining

    @Test("Active hours match wall clock when plan is disabled")
    func activeHoursDisabled() {
        let plan = UsagePlan(isEnabled: false)
        let now = Date()
        let deadline = now.addingTimeInterval(10 * 3600) // 10 hours
        let hours = plan.activeHoursRemaining(until: deadline, from: now)
        #expect(abs(hours - 10) < 0.01)
    }

    @Test("Active hours are less than wall clock when plan has inactive days")
    func activeHoursLessThanWallClock() {
        var plan = UsagePlan(isEnabled: true)
        // Only weekdays active, 9-23
        for day in 1...7 {
            let isWeekday = day >= 2 && day <= 6
            plan.slots[day] = DaySlot(isActive: isWeekday, startHour: 9, endHour: 23)
        }

        let now = Date()
        let deadline = now.addingTimeInterval(7 * 24 * 3600) // 1 week
        let wallHours = 7.0 * 24.0
        let activeHours = plan.activeHoursRemaining(until: deadline, from: now)

        // With weekends off and limited hours, active hours should be much less
        #expect(activeHours < wallHours)
        #expect(activeHours > 0)
    }

    // MARK: - Overrides

    @Test("Override takes precedence over weekly slot")
    func overrideTakesPrecedence() {
        var plan = UsagePlan(isEnabled: true)
        // All days active
        for day in 1...7 {
            plan.slots[day] = DaySlot(isActive: true, startHour: 9, endHour: 23)
        }

        let now = Date()
        // Set today as inactive via override
        plan.setOverride(DaySlot(isActive: false), for: now)

        let slot = plan.todaySlot(at: now)
        #expect(slot?.isActive == false)
        #expect(plan.hasOverride(for: now))
    }

    @Test("Clearing override restores weekly slot")
    func clearOverride() {
        var plan = UsagePlan(isEnabled: true)
        for day in 1...7 {
            plan.slots[day] = DaySlot(isActive: true, startHour: 9, endHour: 23)
        }

        let now = Date()
        plan.setOverride(DaySlot(isActive: false), for: now)
        plan.clearOverride(for: now)

        #expect(!plan.hasOverride(for: now))
        let slot = plan.todaySlot(at: now)
        #expect(slot?.isActive == true)
    }

    // MARK: - Prune Old Overrides

    @Test("Old overrides are pruned")
    func pruneOldOverrides() {
        var plan = UsagePlan(isEnabled: true)
        for day in 1...7 {
            plan.slots[day] = DaySlot(isActive: true, startHour: 9, endHour: 23)
        }

        // Add an override for 10 days ago
        let cal = Calendar.current
        let tenDaysAgo = cal.date(byAdding: .day, value: -10, to: .now)!
        plan.setOverride(DaySlot(isActive: false), for: tenDaysAgo)

        // Add one for today
        plan.setOverride(DaySlot(isActive: false), for: .now)

        plan.pruneOldOverrides()

        // Old override should be gone, today's should remain
        #expect(!plan.hasOverride(for: tenDaysAgo))
        #expect(plan.hasOverride(for: .now))
    }

    // MARK: - Codable

    @Test("UsagePlan encodes and decodes")
    func codable() throws {
        var plan = UsagePlan(isEnabled: true)
        plan.slots[2] = DaySlot(isActive: true, startHour: 8, endHour: 22)

        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(UsagePlan.self, from: data)

        #expect(decoded.isEnabled == true)
        #expect(decoded.slots[2]?.startHour == 8)
        #expect(decoded.slots[2]?.endHour == 22)
    }
}
