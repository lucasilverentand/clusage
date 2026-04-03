import Foundation

enum MomentumEngine {
    /// Window of snapshots to consider for velocity calculation.
    private static let velocityWindow: TimeInterval = 30 * 60 // 30 minutes

    /// Minimum snapshots needed for velocity calculation.
    private static let minimumSnapshots = 2

    /// How quickly stale data decays. After this many seconds with no new data,
    /// velocity is halved. At 2× this interval, it's quartered, etc.
    private static let stalenessHalfLife: TimeInterval = 10 * 60 // 10 minutes

    // MARK: - Momentum Calculation

    static func calculate(
        snapshots: [UsageSnapshot],
        window: UsageWindow?,
        usagePlan: UsagePlan = UsagePlan()
    ) -> MomentumCalculation? {
        let rawVelocity = computeVelocity(snapshots: snapshots)
        let velocity = decayIfStale(rawVelocity, snapshots: snapshots)
        let rawAcceleration = computeAcceleration(snapshots: snapshots)
        let acceleration = decayIfStale(rawAcceleration, snapshots: snapshots)
        let intensity = MomentumCalculation.Intensity(velocity: velocity)

        let (eta, resetsFirst) = computeETA(
            velocity: velocity,
            currentUtilization: window?.utilization ?? 0,
            window: window,
            usagePlan: usagePlan
        )

        return MomentumCalculation(
            velocity: velocity,
            acceleration: acceleration,
            etaToCeiling: eta,
            resetsFirst: resetsFirst,
            intensity: intensity
        )
    }

    /// Compute velocity in percentage points per hour from recent snapshots.
    static func computeVelocity(snapshots: [UsageSnapshot]) -> Double {
        computeVelocity(snapshots: snapshots, keyPath: \.fiveHourUtilization)
    }

    /// Compute velocity for any utilization key path, using recency-weighted regression.
    static func computeVelocity(
        snapshots: [UsageSnapshot],
        keyPath: KeyPath<UsageSnapshot, Double>
    ) -> Double {
        let recent = recentSnapshots(snapshots, window: velocityWindow)
        let slope = regressionSlope(recent, keyPath: keyPath)
        // Clamp floating-point noise to zero
        return slope < 1e-9 ? 0 : slope
    }

    /// Compute acceleration by comparing regression slopes of the current and previous velocity windows.
    /// This makes acceleration the derivative of the same regression used by `computeVelocity`.
    static func computeAcceleration(snapshots: [UsageSnapshot]) -> Double {
        let now = Date.now

        let currentWindowStart = now.addingTimeInterval(-velocityWindow)
        let previousWindowEnd = currentWindowStart
        let previousWindowStart = previousWindowEnd.addingTimeInterval(-velocityWindow)

        let currentSnapshots = snapshots.filter {
            $0.timestamp >= currentWindowStart && $0.timestamp <= now
        }
        let previousSnapshots = snapshots.filter {
            $0.timestamp >= previousWindowStart && $0.timestamp <= previousWindowEnd
        }

        let currentVelocity = regressionSlope(currentSnapshots, keyPath: \.fiveHourUtilization)
        let previousVelocity = regressionSlope(previousSnapshots, keyPath: \.fiveHourUtilization)

        return currentVelocity - previousVelocity
    }

    /// Raw recency-weighted regression slope (pp/hr) without clamping.
    /// Shared by `computeVelocity` (which clamps) and `computeAcceleration` (which doesn't).
    private static func regressionSlope(
        _ snapshots: [UsageSnapshot],
        keyPath: KeyPath<UsageSnapshot, Double>
    ) -> Double {
        guard snapshots.count >= minimumSnapshots else { return 0 }

        let now = Date.now
        let halfLife = velocityWindow / 2

        var sumW: Double = 0
        var sumWt: Double = 0
        var sumWv: Double = 0
        var sumWtt: Double = 0
        var sumWtv: Double = 0

        for s in snapshots {
            let t = s.timestamp.timeIntervalSince(now) / TimeConstants.hour
            let v = s[keyPath: keyPath]
            let age = now.timeIntervalSince(s.timestamp)
            let w = exp(-age / halfLife)

            sumW += w
            sumWt += w * t
            sumWv += w * v
            sumWtt += w * t * t
            sumWtv += w * t * v
        }

        let denom = sumW * sumWtt - sumWt * sumWt
        guard abs(denom) > 1e-12 else { return 0 }

        return (sumW * sumWtv - sumWt * sumWv) / denom
    }

    /// Decay a value toward zero based on how stale the latest snapshot is.
    private static func decayIfStale(_ value: Double, snapshots: [UsageSnapshot]) -> Double {
        guard let latest = snapshots.max(by: { $0.timestamp < $1.timestamp }) else { return 0 }
        let age = Date.now.timeIntervalSince(latest.timestamp)
        guard age > 0 else { return value }
        // Exponential decay: halves every `stalenessHalfLife` seconds
        let factor = pow(0.5, age / stalenessHalfLife)
        return value * factor
    }

    /// Compute ETA to 100% utilization, optionally adjusted for inactive hours.
    private static func computeETA(
        velocity: Double,
        currentUtilization: Double,
        window: UsageWindow?,
        usagePlan: UsagePlan
    ) -> (eta: TimeInterval?, resetsFirst: Bool) {
        guard velocity > 0 else { return (nil, false) }

        let remaining = 100 - currentUtilization
        guard remaining > 0 else { return (0, false) }

        // Active hours needed at this velocity
        let activeHoursNeeded = remaining / velocity

        // Convert active hours to wall-clock time using the plan
        let adjustedETA: TimeInterval
        if usagePlan.isEnabled, let resetDate = window?.resetsAt {
            // Calculate how many active hours exist between now and the reset
            let activeHoursToReset = usagePlan.activeHoursRemaining(until: resetDate, from: .now)
            let wallHoursToReset = resetDate.timeIntervalSince(.now) / TimeConstants.hour

            if activeHoursToReset > 0 && wallHoursToReset > 0 {
                // Ratio of wall-clock to active hours in the remaining window
                let stretchRatio = wallHoursToReset / activeHoursToReset
                adjustedETA = activeHoursNeeded * stretchRatio * TimeConstants.hour
            } else {
                adjustedETA = activeHoursNeeded * TimeConstants.hour
            }
        } else {
            adjustedETA = activeHoursNeeded * TimeConstants.hour
        }

        let resetsFirst = (window?.remainingTime ?? 0) < adjustedETA

        return (adjustedETA, resetsFirst)
    }

    /// Returns snapshots within `window` seconds of now (not of the latest snapshot).
    private static func recentSnapshots(_ snapshots: [UsageSnapshot], window: TimeInterval) -> [UsageSnapshot] {
        let cutoff = Date.now.addingTimeInterval(-window)
        return snapshots
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Window Projection

    static func projectWindows(
        snapshots: [UsageSnapshot],
        fiveHourWindow: UsageWindow?,
        sevenDayWindow: UsageWindow?,
        usagePlan: UsagePlan,
        calibratedRatio: Double? = nil
    ) -> WindowProjection? {
        guard let sevenDayWindow else { return nil }

        let current7Day = sevenDayWindow.utilization

        // Try computing 7-day velocity directly from recent snapshots
        var sevenDayVelocity = computeVelocity(snapshots: snapshots, keyPath: \.sevenDayUtilization)
        sevenDayVelocity = decayIfStale(sevenDayVelocity, snapshots: snapshots)
        var usedCalibratedRatio = false

        // If 7-day snapshots are flat but 5-hour velocity is nonzero,
        // estimate from the observed ratio or calibrated ratio.
        // The ratio maps 5h pp/hr → 7d pp/hr. Because the 5h window is small
        // relative to the 7d window, the theoretical ratio is 5/168 ≈ 0.03.
        // Clamp to a reasonable range to avoid wild extrapolation from bursts.
        let maxRatio = 0.15  // generous upper bound (5× theoretical)
        let minRatio = 0.005

        if sevenDayVelocity < 0.01 {
            var fiveHourVelocity = computeVelocity(snapshots: snapshots, keyPath: \.fiveHourUtilization)
            fiveHourVelocity = decayIfStale(fiveHourVelocity, snapshots: snapshots)
            guard fiveHourVelocity > 0 else { return nil }

            let recent = recentSnapshots(snapshots, window: velocityWindow)
            if recent.count >= minimumSnapshots, let first = recent.first, let last = recent.last {
                let fiveDelta = last.fiveHourUtilization - first.fiveHourUtilization
                let sevenDelta = last.sevenDayUtilization - first.sevenDayUtilization
                if fiveDelta > 0 && sevenDelta > 0 {
                    // Direct observation in current window — best source, but clamp
                    let observedRatio = min(max(sevenDelta / fiveDelta, minRatio), maxRatio)
                    sevenDayVelocity = fiveHourVelocity * observedRatio
                } else if fiveDelta > 0 {
                    // Use calibrated ratio (persisted from historical observations)
                    let raw = calibratedRatio ?? RatioCalibrationStore.defaultRatio
                    let ratio = min(max(raw, minRatio), maxRatio)
                    sevenDayVelocity = fiveHourVelocity * ratio
                    usedCalibratedRatio = calibratedRatio != nil
                }
            }

            guard sevenDayVelocity > 0 else { return nil }
        }

        let remainingSeconds = sevenDayWindow.remainingTime
        let remainingDays = remainingSeconds / TimeConstants.day
        guard remainingDays > 0 else { return nil }

        // Find the timestamp of the most recent 7-day tick (when sevenDayUtilization last changed).
        // We check for any change (not just increases) because the rolling 7-day window can also
        // decrease as old usage falls off the trailing edge.
        let sorted = snapshots.sorted { $0.timestamp < $1.timestamp }
        var lastTickTimestamp: Date? = nil
        for i in 1..<sorted.count {
            if sorted[i].sevenDayUtilization != sorted[i - 1].sevenDayUtilization {
                lastTickTimestamp = sorted[i].timestamp
            }
        }

        // Compute initial granular value for the projection base.
        // Clamp to at most 1 pp above the API-reported value so the interpolation
        // only smooths decimals, not drifts far ahead of reality.
        let granularSevenDay: Double?
        if let tickTime = lastTickTimestamp {
            let hoursSinceLastTick = Date().timeIntervalSince(tickTime) / TimeConstants.hour
            let estimated = current7Day + sevenDayVelocity * hoursSinceLastTick
            granularSevenDay = min(estimated, current7Day + 1.0, 100)
        } else {
            granularSevenDay = nil
        }

        let projectionBase = granularSevenDay ?? current7Day

        // Project using only active hours (when the user is actually working)
        let activeHoursToReset: Double
        if usagePlan.isEnabled {
            activeHoursToReset = usagePlan.activeHoursRemaining(until: sevenDayWindow.resetsAt, from: .now)
        } else {
            activeHoursToReset = remainingSeconds / TimeConstants.hour
        }
        let projectedAtReset = min(projectionBase + sevenDayVelocity * activeHoursToReset, 100)

        let safeDays = max(remainingDays, 0.01) // floor at ~15 min to avoid explosion near reset
        let dailyBudget = (100 - current7Day) / safeDays

        // Daily projected usage: velocity × active hours per day
        let dailyProjected: Double
        if usagePlan.isEnabled {
            let activeDays = usagePlan.slots.values.filter(\.isActive)
            let avgActiveHours = activeDays.isEmpty ? 16.0 : activeDays.reduce(0.0) { $0 + $1.activeHours } / Double(activeDays.count)
            dailyProjected = sevenDayVelocity * avgActiveHours
        } else {
            dailyProjected = sevenDayVelocity * 16 // assume ~16 waking hours
        }

        let status = WindowProjection.Status(dailyProjected: dailyProjected, dailyBudget: dailyBudget)

        // Pattern-aware projection: uses historical (weekday, hour) velocity profiles
        let patternProjection = PatternProjectionEngine.project(
            snapshots: snapshots,
            currentSevenDay: projectionBase,
            sevenDayVelocity: sevenDayVelocity,
            resetDate: sevenDayWindow.resetsAt,
            plan: usagePlan
        )

        // Use pattern projection for projectedAtReset when confident enough
        let finalProjectedAtReset: Double
        if let pattern = patternProjection, pattern.isPatternAware {
            finalProjectedAtReset = pattern.projectedAtReset
        } else {
            finalProjectedAtReset = projectedAtReset
        }

        return WindowProjection(
            sevenDayVelocity: sevenDayVelocity,
            projectedAtReset: finalProjectedAtReset,
            dailyBudget: dailyBudget,
            dailyProjected: dailyProjected,
            remainingDays: remainingDays,
            status: status,
            sevenDayBase: current7Day,
            lastTickTimestamp: lastTickTimestamp,
            usedCalibratedRatio: usedCalibratedRatio,
            patternProjection: patternProjection
        )
    }

    // MARK: - Burst Detection

    /// Rolling average window for burst thresholds.
    private static let rollingAverageWindow: TimeInterval = 2 * 60 * 60 // 2 hours

    /// Minimum velocity to start a burst.
    private static let burstStartMinimum: Double = 5 // pp/hr

    /// Minimum velocity to sustain a burst (hysteresis).
    private static let burstSustainMinimum: Double = 3 // pp/hr

    static func detectBursts(snapshots: [UsageSnapshot]) -> BurstSummary {
        guard snapshots.count >= minimumSnapshots else {
            return BurstSummary(activeBurst: nil, recentBursts: [], burstRatio: 0, pattern: .steady)
        }

        let sorted = snapshots.sorted { $0.timestamp < $1.timestamp }
        let rollingAvg = computeRollingAverageVelocity(sorted)

        var bursts: [UsageBurst] = []
        var activeBurst: UsageBurst?
        var burstTimeTotal: TimeInterval = 0

        for i in 1..<sorted.count {
            let timeDelta = sorted[i].timestamp.timeIntervalSince(sorted[i - 1].timestamp)
            guard timeDelta > 0 else { continue }

            let utilizationDelta = sorted[i].fiveHourUtilization - sorted[i - 1].fiveHourUtilization
            let instantVelocity = max(0, (utilizationDelta / timeDelta) * TimeConstants.hour)

            let startThreshold = max(2 * rollingAvg, burstStartMinimum)
            let sustainThreshold = max(1.5 * rollingAvg, burstSustainMinimum)

            if var burst = activeBurst {
                if instantVelocity < sustainThreshold {
                    // Burst ended
                    burst.end = sorted[i].timestamp
                    bursts.append(burst)
                    burstTimeTotal += (burst.end ?? sorted[i].timestamp).timeIntervalSince(burst.start)
                    activeBurst = nil
                } else {
                    burst.peakVelocity = max(burst.peakVelocity, instantVelocity)
                    burst.utilizationConsumed += max(0, utilizationDelta)
                    activeBurst = burst
                }
            } else if instantVelocity >= startThreshold {
                // Burst started
                activeBurst = UsageBurst(
                    start: sorted[i - 1].timestamp,
                    peakVelocity: instantVelocity,
                    utilizationConsumed: max(0, utilizationDelta)
                )
            }
        }

        if let active = activeBurst {
            burstTimeTotal += (sorted.last?.timestamp ?? .now).timeIntervalSince(active.start)
        }

        guard let first = sorted.first, let last = sorted.last else {
            return BurstSummary(activeBurst: nil, recentBursts: [], burstRatio: 0, pattern: .steady)
        }
        let totalTime = last.timestamp.timeIntervalSince(first.timestamp)
        let burstRatio = totalTime > 0 ? burstTimeTotal / totalTime : 0
        let pattern = BurstSummary.Pattern(burstRatio: burstRatio)

        return BurstSummary(
            activeBurst: activeBurst,
            recentBursts: bursts,
            burstRatio: burstRatio,
            pattern: pattern
        )
    }

    private static func computeRollingAverageVelocity(_ snapshots: [UsageSnapshot]) -> Double {
        guard snapshots.count >= minimumSnapshots,
              let first = snapshots.first,
              let last = snapshots.last
        else { return 0 }

        // Use up to the last 2 hours of data
        let cutoff = last.timestamp.addingTimeInterval(-rollingAverageWindow)
        let window = snapshots.filter { $0.timestamp >= cutoff }

        guard window.count >= minimumSnapshots,
              let wFirst = window.first,
              let wLast = window.last
        else {
            let timeDelta = last.timestamp.timeIntervalSince(first.timestamp)
            guard timeDelta > 0 else { return 0 }
            return max(0, (last.fiveHourUtilization - first.fiveHourUtilization) / timeDelta * TimeConstants.hour)
        }

        let timeDelta = wLast.timestamp.timeIntervalSince(wFirst.timestamp)
        guard timeDelta > 0 else { return 0 }
        return max(0, (wLast.fiveHourUtilization - wFirst.fiveHourUtilization) / timeDelta * TimeConstants.hour)
    }

    // MARK: - Streaks

    /// Expected daily utilization for the 7-day window (100% / 7 days ≈ 14.3%).
    private static let dailyUtilizationTarget: Double = 100.0 / 7.0

    /// Update streak using the daily target from the budget engine when available.
    /// A streak day is earned when actual 7-day utilization meets or exceeds the
    /// current target for this moment. Falls back to the fixed 5-hour threshold
    /// when no plan is active.
    static func updateStreak(
        _ streak: UsageStreak,
        snapshots: [UsageSnapshot],
        dailyTarget: BudgetEngine.DailyTarget? = nil,
        currentUtilization: Double? = nil
    ) -> UsageStreak {
        var updated = streak

        let meetsTarget: Bool
        if let dailyTarget, let currentUtilization {
            // Plan-aware: earned when actual utilization ≥ current moment target
            // Day-off days leave the streak unchanged (don't mark, don't break)
            if !dailyTarget.isActiveDay {
                return streak
            } else {
                meetsTarget = currentUtilization >= dailyTarget.currentTarget
            }
        } else {
            // Fallback: fixed 5-hour threshold
            let todayKey = UsageStreak.dayKey()
            let todaySnapshots = snapshots.filter {
                UsageStreak.dayKey(for: $0.timestamp) == todayKey
            }
            let peakToday = todaySnapshots.map(\.fiveHourUtilization).max() ?? 0
            meetsTarget = peakToday >= dailyUtilizationTarget
        }

        if meetsTarget {
            updated.markActive()
        } else {
            updated.recalculateStreak()
        }

        return updated
    }
}
