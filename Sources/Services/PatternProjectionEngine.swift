import Foundation
import OSLog

/// Pattern-aware projection engine that builds hourly usage profiles from historical
/// data and walks forward hour-by-hour to produce time-of-day and day-of-week aware
/// projections. Blends recent momentum with historical patterns for accuracy.
enum PatternProjectionEngine {
    /// A projected usage curve from now to the window reset.
    struct Projection: Sendable {
        /// The projected 7-day utilization at window reset.
        let projectedAtReset: Double
        /// Optimistic projection (lower usage rate — 25th percentile of historical variance).
        let optimisticAtReset: Double
        /// Pessimistic projection (higher usage rate — 75th percentile of historical variance).
        let pessimisticAtReset: Double
        /// Hour-by-hour projected curve from now through reset.
        let curve: [CurvePoint]
        /// Whether there was enough historical data to be pattern-aware.
        /// When false, falls back to flat velocity projection.
        let isPatternAware: Bool
        /// Confidence: 0 (pure fallback) to 1 (rich historical data).
        let confidence: Double
    }

    struct CurvePoint: Sendable {
        let date: Date
        let projected: Double
        let optimistic: Double
        let pessimistic: Double
    }

    // MARK: - Hourly Profile

    /// Average usage velocity (pp/hr) for a specific (weekday, hour) slot,
    /// plus variance for confidence bands.
    struct HourlyBucket: Sendable {
        let weekday: Int  // Calendar weekday 1-7
        let hour: Int     // 0-23
        var totalVelocity: Double = 0
        var totalVelocitySquared: Double = 0
        var totalWeight: Double = 0
        var sampleCount: Int = 0

        var weightedMean: Double {
            guard totalWeight > 0 else { return 0 }
            return totalVelocity / totalWeight
        }

        /// Standard deviation of velocity in this bucket.
        var standardDeviation: Double {
            guard sampleCount >= 2, totalWeight > 0 else { return 0 }
            let mean = weightedMean
            let meanOfSquares = totalVelocitySquared / totalWeight
            let variance = max(meanOfSquares - mean * mean, 0)
            return sqrt(variance)
        }
    }

    /// Build an hourly usage profile from historical snapshots.
    /// Returns a 7×24 grid of (weekday, hour) → velocity stats, weighted by recency.
    static func buildProfile(
        snapshots: [UsageSnapshot],
        keyPath: KeyPath<UsageSnapshot, Double> = \.sevenDayUtilization,
        recencyHalfLife: TimeInterval = TimeConstants.week
    ) -> [Int: [Int: HourlyBucket]] {
        let sorted = snapshots.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 2 else { return [:] }

        let now = Date.now
        let cal = Calendar.current
        var profile: [Int: [Int: HourlyBucket]] = [:]

        // Initialize all buckets
        for weekday in 1...7 {
            profile[weekday] = [:]
            for hour in 0..<24 {
                profile[weekday]![hour] = HourlyBucket(weekday: weekday, hour: hour)
            }
        }

        // Walk consecutive snapshot pairs and compute instantaneous velocity
        for i in 1..<sorted.count {
            let dt = sorted[i].timestamp.timeIntervalSince(sorted[i - 1].timestamp)
            // Skip pairs with too little time (noise) or too much (gap)
            guard dt >= TimeConstants.minute, dt <= TimeConstants.hour else { continue }

            let delta = sorted[i][keyPath: keyPath] - sorted[i - 1][keyPath: keyPath]
            let velocity = delta / (dt / TimeConstants.hour) // pp/hr — can be negative for window resets

            // Assign to the bucket of the midpoint timestamp
            let midpoint = sorted[i - 1].timestamp.addingTimeInterval(dt / 2)
            let weekday = cal.component(.weekday, from: midpoint)
            let hour = cal.component(.hour, from: midpoint)

            // Recency weight: exponential decay from now
            let age = now.timeIntervalSince(midpoint)
            let weight = exp(-age / recencyHalfLife)

            // Only record non-negative velocities (negative = window reset, not usage)
            let clampedVelocity = max(velocity, 0)

            if var bucket = profile[weekday]?[hour] {
                bucket.totalVelocity += clampedVelocity * weight
                bucket.totalVelocitySquared += clampedVelocity * clampedVelocity * weight
                bucket.totalWeight += weight
                bucket.sampleCount += 1
                profile[weekday]![hour] = bucket
            }
        }

        return profile
    }

    /// Look up the expected velocity for a given date from the profile.
    /// Falls back to same-hour-any-day if specific weekday has no data,
    /// then to the overall average.
    static func velocity(
        for date: Date,
        from profile: [Int: [Int: HourlyBucket]],
        plan: UsagePlan
    ) -> (mean: Double, stddev: Double) {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        let hour = cal.component(.hour, from: date)

        // Check if this time is in an active slot
        if plan.isEnabled, !plan.isActiveTime(date) {
            return (0, 0)
        }

        // Try exact (weekday, hour) bucket
        if let bucket = profile[weekday]?[hour], bucket.sampleCount >= 3 {
            return (bucket.weightedMean, bucket.standardDeviation)
        }

        // Fallback: same hour across all days
        var totalVel = 0.0, totalWeight = 0.0, totalVelSq = 0.0, count = 0
        for wd in 1...7 {
            if let bucket = profile[wd]?[hour], bucket.sampleCount > 0 {
                totalVel += bucket.totalVelocity
                totalVelSq += bucket.totalVelocitySquared
                totalWeight += bucket.totalWeight
                count += bucket.sampleCount
            }
        }
        if count >= 3, totalWeight > 0 {
            let mean = totalVel / totalWeight
            let meanSq = totalVelSq / totalWeight
            let stddev = sqrt(max(meanSq - mean * mean, 0))
            return (mean, stddev)
        }

        // Not enough data
        return (0, 0)
    }

    /// Count how many distinct (weekday, hour) buckets have meaningful data.
    static func profileCoverage(_ profile: [Int: [Int: HourlyBucket]]) -> (filledBuckets: Int, totalSamples: Int) {
        var filled = 0, samples = 0
        for (_, hours) in profile {
            for (_, bucket) in hours {
                if bucket.sampleCount >= 2 {
                    filled += 1
                }
                samples += bucket.sampleCount
            }
        }
        return (filled, samples)
    }

    // MARK: - Projection

    /// Project 7-day utilization from now to the window reset using historical patterns.
    ///
    /// The algorithm:
    /// 1. Builds an hourly (weekday × hour) velocity profile from all historical snapshots
    /// 2. For the next ~2 hours, blends current real-time momentum with the historical profile
    /// 3. Beyond 2 hours, relies entirely on the historical pattern
    /// 4. Walks hour-by-hour from now to reset, summing projected velocity × 1 hour
    /// 5. Produces optimistic/pessimistic bands using ±0.675σ (25th/75th percentiles)
    static func project(
        snapshots: [UsageSnapshot],
        currentSevenDay: Double,
        sevenDayVelocity: Double,
        resetDate: Date,
        plan: UsagePlan,
        now: Date = .now
    ) -> Projection? {
        let remaining = resetDate.timeIntervalSince(now)
        guard remaining > 0 else { return nil }

        let profile = buildProfile(snapshots: snapshots)
        let (filled, totalSamples) = profileCoverage(profile)

        // Need at least ~20 filled hourly buckets and 50 samples for meaningful patterns
        let isPatternAware = filled >= 20 && totalSamples >= 50
        let confidence = min(Double(filled) / 80.0, 1.0) // 80+ filled = full confidence

        Log.pattern.debug("Profile: \(filled) buckets, \(totalSamples) samples, pattern-aware: \(isPatternAware), confidence: \(String(format: "%.0f%%", confidence * 100))")

        // If no pattern data, fall back to flat velocity
        guard isPatternAware || sevenDayVelocity > 0 else { return nil }

        // Walk forward hour-by-hour
        let stepSize: TimeInterval = TimeConstants.hour
        let stepCount = max(Int(ceil(remaining / stepSize)), 1)

        var projected = currentSevenDay
        var optimistic = currentSevenDay
        var pessimistic = currentSevenDay
        var curve: [CurvePoint] = [CurvePoint(
            date: now, projected: projected, optimistic: optimistic, pessimistic: pessimistic
        )]

        // Blend window: current momentum dominates the first 2 hours, then fades
        let blendHalfLife: TimeInterval = 2 * TimeConstants.hour

        for step in 1...stepCount {
            let stepDate = now.addingTimeInterval(Double(step) * stepSize)
            let capped = min(stepDate, resetDate)
            let dt = capped.timeIntervalSince(now.addingTimeInterval(Double(step - 1) * stepSize))
            let hours = dt / TimeConstants.hour
            guard hours > 0 else { break }

            let elapsed = Double(step) * stepSize
            let blendFactor = isPatternAware ? exp(-elapsed / blendHalfLife) : 1.0

            // Historical velocity for this (weekday, hour)
            let (histMean, histStddev) = velocity(for: stepDate, from: profile, plan: plan)

            // Blend: near-term uses current momentum, far-term uses historical
            let blendedMean: Double
            if isPatternAware {
                blendedMean = sevenDayVelocity * blendFactor + histMean * (1 - blendFactor)
            } else {
                blendedMean = sevenDayVelocity
            }

            // Confidence band: ±0.675σ = 25th/75th percentile of normal distribution
            let bandWidth = isPatternAware ? histStddev * 0.675 : blendedMean * 0.3

            let mainDelta = max(blendedMean * hours, 0)
            let optDelta = max((blendedMean - bandWidth) * hours, 0)
            let pessDelta = max((blendedMean + bandWidth) * hours, 0)

            projected = min(projected + mainDelta, 100)
            optimistic = min(optimistic + optDelta, 100)
            pessimistic = min(pessimistic + pessDelta, 100)

            curve.append(CurvePoint(
                date: capped, projected: projected, optimistic: optimistic, pessimistic: pessimistic
            ))

            if capped >= resetDate { break }
        }

        Log.pattern.info("Projection: \(String(format: "%.1f%%", projected)) (\(String(format: "%.1f–%.1f%%", optimistic, pessimistic)), \(curve.count) steps, \(isPatternAware ? "pattern-aware" : "flat fallback"))")

        return Projection(
            projectedAtReset: projected,
            optimisticAtReset: optimistic,
            pessimisticAtReset: pessimistic,
            curve: curve,
            isPatternAware: isPatternAware,
            confidence: confidence
        )
    }
}
