import SwiftUI

struct DailyTargetCard: View {
    let target: BudgetEngine.DailyTarget
    let currentUtilization: Double
    var streak: UsageStreak?
    var currentVelocity: Double = 0
    var hasOverride: Bool = false
    var onOverride: ((DaySlot?) -> Void)?

    @State private var showExceptionPopover = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Daily Target", systemImage: "target")
                        .font(.headline)

                    if hasOverride {
                        Text("Exception")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }

                    Spacer()

                    if let streak, streak.currentStreak > 0 {
                        streakBadge(streak)
                    }

                    exceptionButton
                }

                if !target.isActiveDay {
                    dayOffSection
                } else {
                    targetSection
                    progressSection
                    if target.hoursUntilBedtime > 0 {
                        paceSection
                    }
                }
            }
        }
    }

    // MARK: - Exception Button

    private var exceptionButton: some View {
        Button {
            showExceptionPopover = true
        } label: {
            Image(systemName: hasOverride ? "calendar.badge.minus" : "calendar.badge.plus")
                .font(.caption)
                .foregroundStyle(hasOverride ? .orange : .secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(hasOverride ? "Remove today's schedule exception" : "Add schedule exception for today")
        .help(hasOverride ? "Remove today's exception" : "Add exception for today")
        .popover(isPresented: $showExceptionPopover) {
            ScheduleExceptionPopover(
                target: target,
                hasOverride: hasOverride,
                onApply: { slot in
                    onOverride?(slot)
                    showExceptionPopover = false
                },
                onClear: {
                    onOverride?(nil)
                    showExceptionPopover = false
                }
            )
        }
    }

    // MARK: - Streak

    private func streakBadge(_ streak: UsageStreak) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("\(streak.currentStreak)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
            if streak.currentStreak == streak.longestStreak && streak.longestStreak > 1 {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(streak.currentStreak) day streak\(streak.currentStreak == streak.longestStreak && streak.longestStreak > 1 ? ", personal best" : "")")
    }

    // MARK: - States

    private var dayOffSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.fill")
                .foregroundStyle(.indigo)
                .accessibilityHidden(true)
            Text("Day off — no usage planned")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Active Day

    private var targetSection: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Target now")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Formatting.percent(target.currentTarget))
                    .font(.system(.title, design: .rounded, weight: .bold).monospacedDigit())
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("end of day")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Formatting.percent(target.targetUtilization))
                    .font(.title3.weight(.semibold).monospacedDigit())
            }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let totalWidth = geo.size.width
                let targetNorm = min(target.currentTarget / 100, 1)
                let endOfDayNorm = min(target.targetUtilization / 100, 1)
                let currentNorm = min(currentUtilization / 100, 1)

                ZStack(alignment: .leading) {
                    // Background
                    Capsule()
                        .fill(.quaternary.opacity(0.3))

                    // End-of-day target (faint)
                    Capsule()
                        .fill(.blue.opacity(0.08))
                        .frame(width: totalWidth * endOfDayNorm)

                    // Current moment target
                    Capsule()
                        .fill(.blue.opacity(0.2))
                        .frame(width: totalWidth * targetNorm)

                    // Actual utilization
                    Capsule()
                        .fill(progressGradient)
                        .frame(width: max(0, totalWidth * currentNorm))
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)

            HStack {
                Text("\(Formatting.percent(currentUtilization)) of \(Formatting.percent(target.currentTarget)) target")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                statusBadge
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily target progress")
        .accessibilityValue("\(Int(currentUtilization)) percent of \(Int(target.currentTarget)) percent target, \(target.status.label)")
    }

    private var paceSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current pace")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(Formatting.pace(currentVelocity))
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(paceColor)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Target pace")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(Formatting.pace(target.suggestedPace))
                        .font(.callout.weight(.semibold).monospacedDigit())
                }
            }

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.1f", target.hoursUntilBedtime))h left")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("+\(String(format: "%.1f", target.remainingBudget)) pp budget")
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(.blue)
            }
        }
    }

    private var paceColor: Color {
        guard target.suggestedPace > 0 else { return .secondary }
        let ratio = currentVelocity / target.suggestedPace
        if ratio > 1.3 { return .orange }
        if ratio < 0.7 { return .green }
        return .blue
    }

    // MARK: - Helpers

    private var statusBadge: some View {
        Text(target.status.label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.15), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        ThemeColors.targetStatusColor(target.status)
    }

    private var progressGradient: some ShapeStyle {
        let progress = currentUtilization / max(target.currentTarget, 1)
        if progress > 1.1 { return AnyShapeStyle(.orange.gradient) }
        return AnyShapeStyle(.blue.gradient)
    }
}

// MARK: - Schedule Exception Popover

private struct ScheduleExceptionPopover: View {
    let target: BudgetEngine.DailyTarget
    let hasOverride: Bool
    let onApply: (DaySlot) -> Void
    let onClear: () -> Void

    @State private var isActive: Bool = true
    @State private var startHour: Int = 9
    @State private var endHour: Int = 23

    private var presetEndHours: [Int] {
        // Offer +1h, +2h, +3h from current end hour
        return (1...3).map { offset in (target.slot.endHour + offset) % 24 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Today's Exception")
                .font(.headline)

            // Quick actions
            if target.isActiveDay {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Extend bedtime")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(presetEndHours, id: \.self) { hour in
                            Button {
                                endHour = hour
                                onApply(DaySlot(isActive: true, startHour: startHour, endHour: hour))
                            } label: {
                                Text(formatHour(hour))
                                    .font(.caption.weight(.medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    Divider()
                }
            }

            // Toggle day on/off
            Toggle(isOn: $isActive) {
                Text(isActive ? "Active day" : "Day off")
                    .font(.callout)
            }
            .toggleStyle(.switch)

            if isActive {
                // Custom hours
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Picker("Start", selection: $startHour) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(formatHour(hour)).tag(hour)
                            }
                        }
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("End")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Picker("End", selection: $endHour) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(formatHour(hour)).tag(hour)
                            }
                        }
                        .labelsHidden()
                    }
                }

                let slot = DaySlot(isActive: true, startHour: startHour, endHour: endHour)
                Text("\(Int(slot.activeHours))h active")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if hasOverride {
                    Button("Reset to Schedule") {
                        onClear()
                    }
                    .controlSize(.small)
                }

                Spacer()

                Button("Apply") {
                    onApply(DaySlot(isActive: isActive, startHour: startHour, endHour: endHour))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 260)
        .onAppear {
            isActive = target.slot.isActive
            startHour = target.slot.startHour
            endHour = target.slot.endHour
        }
    }

    private func formatHour(_ hour: Int) -> String {
        DateFormatting.formatHourAmPm(hour)
    }
}
