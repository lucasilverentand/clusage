import SwiftUI

struct SchedulePageView: View {
    var accountStore: AccountStore
    var momentumProvider: MomentumProvider?

    @State private var selectedAccountID: UUID?
    @State private var plan = UsagePlan()

    private let hourHeight: CGFloat = 3
    private let dayBoundary = UsagePlan.dayBoundaryHour

    private var selectedAccount: Account? {
        if let id = selectedAccountID {
            return accountStore.accounts.first { $0.id == id }
        }
        return accountStore.accounts.first
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if accountStore.accounts.count > 1 {
                    accountPicker
                }

                weekSummaryBar

                GlassCard {
                    VStack(alignment: .leading, spacing: 0) {
                        weekHeader
                        Divider().padding(.bottom, 4)
                        calendarGrid
                    }
                }

                if !plan.isEnabled {
                    enablePrompt
                }
            }
            .padding(24)
        }
        .navigationTitle("Schedule")
        .navigationSubtitle(plan.isEnabled ? weekSummaryText : "Plan not enabled")
        .toolbarTitleDisplayMode(.inline)
        .onAppear { loadPlanForSelectedAccount() }
        .onChange(of: selectedAccountID) { _, _ in loadPlanForSelectedAccount() }
    }

    // MARK: - Account Picker

    private var accountPicker: some View {
        HStack {
            Text("Account")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Picker("Account", selection: $selectedAccountID) {
                ForEach(accountStore.accounts) { account in
                    Text(account.displayName).tag(Optional(account.id))
                }
            }
            .labelsHidden()
            .frame(width: 200)
        }
    }

    // MARK: - Week Summary Bar

    private var weekSummaryBar: some View {
        HStack(spacing: 12) {
            summaryPill(
                icon: "calendar.badge.clock",
                label: "\(activeDayCount) active days",
                color: .blue
            )
            summaryPill(
                icon: "clock",
                label: "\(Int(totalWeeklyHours))h per week",
                color: .green
            )
            summaryPill(
                icon: "gauge.with.needle",
                label: String(format: "%.1fh avg/day", averageHoursPerActiveDay),
                color: .orange
            )

            Spacer()

            Toggle("Enabled", isOn: $plan.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("Usage plan enabled")
                .onChange(of: plan.isEnabled) { _, _ in savePlan() }
        }
    }

    private func summaryPill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(label)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.1), in: Capsule())
    }

    // MARK: - Week Header

    private var weekHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 36)

            ForEach(UsagePlan.orderedDays, id: \.weekday) { day in
                let slot = plan.slots[day.weekday] ?? DaySlot()
                VStack(spacing: 4) {
                    Text(day.short)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isToday(day.weekday) ? .primary : .secondary)

                    if isToday(day.weekday) && plan.hasOverride(for: .now) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 5, height: 5)
                            .accessibilityHidden(true)
                    } else if isToday(day.weekday) {
                        Circle()
                            .fill(.blue)
                            .frame(width: 5, height: 5)
                            .accessibilityHidden(true)
                    }

                    // Toggle button
                    if plan.isEnabled {
                        Button {
                            plan.slots[day.weekday]?.isActive.toggle()
                            savePlan()
                        } label: {
                            Image(systemName: slot.isActive ? "checkmark.circle.fill" : "circle.dashed")
                                .font(.caption)
                                .foregroundStyle(slot.isActive ? dayColor(weekday: day.weekday) : .gray.opacity(0.3))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("\(day.short) \(slot.isActive ? "active" : "day off")")
                        .accessibilityHint(slot.isActive ? "Mark as day off" : "Mark as active")
                        .help(slot.isActive ? "Mark as day off" : "Mark as active")
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 6)
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        let startHour = dayBoundary
        let totalHours = 24
        let gridHeight = CGFloat(totalHours) * hourHeight * 4

        return HStack(alignment: .top, spacing: 0) {
            // Time gutter
            VStack(spacing: 0) {
                ForEach(0..<totalHours, id: \.self) { offset in
                    let hour = (startHour + offset) % 24
                    Text(DateFormatting.formatHourShort(hour))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(height: hourHeight * 4, alignment: .top)
                }
            }
            .frame(width: 36)

            // Day columns
            ForEach(UsagePlan.orderedDays, id: \.weekday) { day in
                DayColumnView(
                    weekday: day.weekday,
                    slot: bindingForSlot(day.weekday),
                    isEnabled: plan.isEnabled,
                    isToday: isToday(day.weekday),
                    dayColor: dayColor(weekday: day.weekday),
                    dayBoundary: dayBoundary,
                    onChanged: savePlan
                )
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: gridHeight)
    }

    // MARK: - Enable Prompt

    private var enablePrompt: some View {
        GlassCard {
            VStack(spacing: 10) {
                Image(systemName: "calendar.badge.plus")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Enable your usage plan to see scheduled time slots")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Enable Plan") {
                    plan.isEnabled = true
                    savePlan()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Summary Computed

    private var activeDayCount: Int {
        plan.slots.values.filter(\.isActive).count
    }

    private var totalWeeklyHours: Double {
        plan.slots.values.filter(\.isActive).reduce(0.0) { $0 + $1.activeHours }
    }

    private var averageHoursPerActiveDay: Double {
        let count = activeDayCount
        guard count > 0 else { return 0 }
        return totalWeeklyHours / Double(count)
    }

    private var weekSummaryText: String {
        "\(activeDayCount) days, \(Int(totalWeeklyHours))h per week"
    }

    // MARK: - Helpers

    private func isToday(_ weekday: Int) -> Bool {
        UsagePlan.planWeekday(for: .now) == weekday
    }

    private func dayColor(weekday: Int) -> Color {
        if isToday(weekday) { return .blue }
        let slot = plan.slots[weekday] ?? DaySlot()
        if !slot.isActive { return .gray }
        if weekday == 1 || weekday == 7 { return .indigo }
        return .teal
    }

    private func bindingForSlot(_ weekday: Int) -> Binding<DaySlot> {
        Binding(
            get: { plan.slots[weekday] ?? DaySlot() },
            set: { plan.slots[weekday] = $0 }
        )
    }

    private func loadPlanForSelectedAccount() {
        if let account = selectedAccount {
            plan = account.usagePlan
            if selectedAccountID == nil {
                selectedAccountID = account.id
            }
        }
    }

    private func savePlan() {
        guard var account = selectedAccount else { return }
        account.usagePlan = plan
        accountStore.updateAccount(account)
        momentumProvider?.refresh()
    }

}
