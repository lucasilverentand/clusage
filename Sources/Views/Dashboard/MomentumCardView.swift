import SwiftUI

// MARK: - 5-Hour Momentum Card

struct FiveHourMomentumCard: View {
    let momentum: MomentumCalculation
    let burstSummary: BurstSummary?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("5-Hour Momentum", systemImage: "speedometer")
                    .font(.headline)

                velocitySection

                if momentum.etaToCeiling != nil {
                    etaSection
                }

                if let burst = burstSummary {
                    burstBadge(burst)
                }
            }
        }
    }

    // MARK: - Velocity

    private var velocitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Burn Rate")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(momentum.intensity.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(intensityColor)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary.opacity(0.3))

                    Capsule()
                        .fill(intensityGradient)
                        .frame(width: max(0, geo.size.width * velocityFraction))
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)

            HStack {
                Text(Formatting.pace(momentum.velocity))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if momentum.acceleration != 0 {
                    HStack(spacing: 2) {
                        Image(systemName: momentum.acceleration > 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2)
                            .accessibilityHidden(true)
                        Text(momentum.acceleration > 0 ? "Accelerating" : "Decelerating")
                            .font(.caption2)
                    }
                    .foregroundStyle(momentum.acceleration > 0 ? .orange : .green)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Burn rate")
        .accessibilityValue("\(momentum.intensity.label), \(momentum.acceleration > 0 ? "accelerating" : momentum.acceleration < 0 ? "decelerating" : "steady")")
    }

    private var velocityFraction: Double {
        min(momentum.velocity / 50, 1)
    }

    private var intensityColor: Color {
        ThemeColors.intensityColor(momentum.intensity)
    }

    private var intensityGradient: some ShapeStyle {
        ThemeColors.intensityGradient(momentum.intensity)
    }

    // MARK: - ETA

    private var etaSection: some View {
        HStack(spacing: 8) {
            Image(systemName: momentum.resetsFirst ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(momentum.resetsFirst ? .green : .orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                if momentum.resetsFirst {
                    Text("Window resets before cap")
                        .font(.subheadline.weight(.medium))
                } else if let eta = momentum.etaToCeiling {
                    Text(formatETA(eta))
                        .font(.subheadline.weight(.medium))
                    Text("May hit rate limit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private func formatETA(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 24 {
            return "\(hours / 24)d \(hours % 24)h to cap"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m to cap"
        }
        return "\(minutes)m to cap"
    }

    // MARK: - Burst

    private func burstBadge(_ summary: BurstSummary) -> some View {
        HStack(spacing: 4) {
            Image(systemName: burstIcon(summary.pattern))
                .font(.caption)
                .accessibilityHidden(true)
            Text(summary.pattern.label)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(burstColor(summary.pattern).opacity(0.15), in: Capsule())
        .foregroundStyle(burstColor(summary.pattern))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Usage pattern: \(summary.pattern.label)")
    }

    private func burstIcon(_ pattern: BurstSummary.Pattern) -> String {
        switch pattern {
        case .steady: "waveform.path"
        case .bursty: "waveform.badge.magnifyingglass"
        case .spiky: "bolt.fill"
        }
    }

    private func burstColor(_ pattern: BurstSummary.Pattern) -> Color {
        ThemeColors.burstColor(pattern)
    }
}

// MARK: - 7-Day Projection Card

struct SevenDayProjectionCard: View {
    let projection: WindowProjection

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("7-Day Projection", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.quaternary.opacity(0.3))

                        Capsule()
                            .fill(projectionGradient(projection.status))
                            .frame(width: max(0, geo.size.width * min(projection.projectedAtReset / 100, 1)))
                    }
                }
                .frame(height: 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Projected usage at reset")
                .accessibilityValue("\(Int(projection.projectedAtReset)) percent, \(projection.status.label)")

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily budget: \(String(format: "%.1f", projection.dailyBudget)) pp/day")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("Current pace: \(String(format: "%.1f", projection.dailyProjected)) pp/day")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("→ \(Formatting.percent(projection.projectedAtReset, decimals: 0))")
                            .font(.callout.monospacedDigit().weight(.semibold))
                            .foregroundStyle(ThemeColors.projectionColor(projection.status))
                        TimelineView(.periodic(from: .now, by: 30)) { _ in
                            Text("~\(Formatting.percent(projection.currentGranularUtilization())) now")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                HStack {
                    Text(projection.status.label)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(ThemeColors.projectionColor(projection.status).opacity(0.15), in: Capsule())
                        .foregroundStyle(ThemeColors.projectionColor(projection.status))

                    if let pattern = projection.patternProjection, pattern.isPatternAware {
                        Text(Formatting.percentRange(pattern.optimisticAtReset, pattern.pessimisticAtReset))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(String(format: "%.1f", projection.remainingDays)) days remaining")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func projectionGradient(_ status: WindowProjection.Status) -> some ShapeStyle {
        ThemeColors.projectionGradient(status)
    }
}

// MARK: - Streak Card

struct StreakCard: View {
    let streak: UsageStreak

    private var streakDescription: String {
        var desc = "\(streak.currentStreak) day streak"
        if streak.currentStreak == streak.longestStreak && streak.longestStreak > 1 {
            desc += ", personal best"
        } else if streak.longestStreak > streak.currentStreak {
            desc += ", best is \(streak.longestStreak) days"
        }
        return desc
    }

    var body: some View {
        GlassCard {
            HStack(spacing: 10) {
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(streak.currentStreak) day streak")
                        .font(.subheadline.weight(.semibold))

                    if streak.currentStreak == streak.longestStreak && streak.longestStreak > 1 {
                        Text("Personal best!")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if streak.longestStreak > streak.currentStreak {
                        Text("Best: \(streak.longestStreak) days")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(streakDescription)
        }
    }
}
