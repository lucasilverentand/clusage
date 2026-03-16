import Foundation

@Observable
@MainActor final class RatioCalibrationStore {
    struct RatioObservation: Codable, Sendable {
        let timestamp: Date
        let fiveHourDelta: Double
        let sevenDayDelta: Double
        let accountID: UUID

        var ratio: Double {
            guard fiveHourDelta > 0 else { return 0 }
            return sevenDayDelta / fiveHourDelta
        }
    }

    private(set) var observations: [RatioObservation] = []

    private let fileURL: URL
    /// Keep observations for 30 days for robust calibration.
    private let maxAge: TimeInterval = 30 * 24 * 60 * 60
    /// Exponential decay half-life: 3 days.
    private let decayHalfLife: TimeInterval = 3 * 24 * 60 * 60

    /// Fallback ratio when no observations exist (5h / 168h).
    nonisolated static let defaultRatio: Double = 5.0 / 168.0

    /// In-memory tracker to avoid re-scanning already-processed snapshots.
    private var lastCalibratedTimestamp: [UUID: Date] = [:]

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let directory = appSupport.appendingPathComponent("Clusage", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.fileURL = directory.appendingPathComponent("ratio-calibration.json")
        }
        load()
    }

    // MARK: - Calibration from Snapshots

    /// Scan snapshots for 7-day ticks and record observed ratios.
    func calibrate(from snapshots: [UsageSnapshot], accountID: UUID) {
        let sorted = snapshots
            .filter { $0.accountID == accountID }
            .sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 2 else { return }

        let cutoff = lastCalibratedTimestamp[accountID] ?? .distantPast
        var newCount = 0

        for i in 1..<sorted.count {
            guard sorted[i].timestamp > cutoff else { continue }

            let sevenDelta = sorted[i].sevenDayUtilization - sorted[i - 1].sevenDayUtilization
            let fiveDelta = sorted[i].fiveHourUtilization - sorted[i - 1].fiveHourUtilization

            // Skip observations right after a window reset (near-zero utilization)
            guard sorted[i - 1].fiveHourUtilization >= 0.1 else { continue }

            // Only record when both are positive (real usage, not window resets)
            if sevenDelta > 0 && fiveDelta > 0.01 {
                record(
                    accountID: accountID,
                    fiveHourDelta: fiveDelta,
                    sevenDayDelta: sevenDelta,
                    timestamp: sorted[i].timestamp
                )
                newCount += 1
            }
        }

        if let last = sorted.last {
            lastCalibratedTimestamp[accountID] = last.timestamp
        }

        if newCount > 0 {
            prune()
            save()
            Log.momentum.info("Calibrated \(newCount) new ratio observation(s), total: \(self.observations.count)")
        }
    }

    // MARK: - Recording

    /// Bounds for per-observation outlier rejection.
    private let minRatio = 0.005
    private let maxRatio = 0.15

    private func record(accountID: UUID, fiveHourDelta: Double, sevenDayDelta: Double, timestamp: Date) {
        guard fiveHourDelta > 0.01, sevenDayDelta > 0 else { return }

        // Reject outlier ratios that would skew the weighted average
        let ratio = sevenDayDelta / fiveHourDelta
        guard ratio >= minRatio && ratio <= maxRatio else { return }

        // Dedup: skip if we already have an observation within 2 minutes
        let isDuplicate = observations.contains { obs in
            obs.accountID == accountID
                && abs(obs.timestamp.timeIntervalSince(timestamp)) < 120
        }
        guard !isDuplicate else { return }

        let obs = RatioObservation(
            timestamp: timestamp,
            fiveHourDelta: fiveHourDelta,
            sevenDayDelta: sevenDayDelta,
            accountID: accountID
        )
        observations.append(obs)

        Log.momentum.debug("Ratio observed: 5h=\(fiveHourDelta, privacy: .public) 7d=\(sevenDayDelta, privacy: .public) ratio=\(obs.ratio, privacy: .public)")
    }

    // MARK: - Querying

    /// Exponentially-weighted calibrated ratio for an account.
    /// Falls back to global average across accounts, then to the default ratio.
    func calibratedRatio(for accountID: UUID) -> Double {
        let accountObs = observations.filter { $0.accountID == accountID && $0.ratio > 0 }

        if let accountRatio = weightedAverageRatio(accountObs) {
            return accountRatio
        }

        // Fall back to global average across all accounts
        let allObs = observations.filter { $0.ratio > 0 }
        return weightedAverageRatio(allObs) ?? Self.defaultRatio
    }

    /// Whether we have enough observations for a confident estimate.
    func hasCalibration(for accountID: UUID) -> Bool {
        observations.filter { $0.accountID == accountID }.count >= 3
    }

    /// Number of observations for an account.
    func observationCount(for accountID: UUID) -> Int {
        observations.filter { $0.accountID == accountID }.count
    }

    private func weightedAverageRatio(_ observations: [RatioObservation]) -> Double? {
        guard !observations.isEmpty else { return nil }

        let now = Date()
        var weightedSum = 0.0
        var totalWeight = 0.0

        for obs in observations {
            let age = now.timeIntervalSince(obs.timestamp)
            let weight = exp(-age * log(2) / decayHalfLife)
            weightedSum += obs.ratio * weight
            totalWeight += weight
        }

        return totalWeight > 0 ? weightedSum / totalWeight : nil
    }

    func clearAll() {
        observations.removeAll()
        lastCalibratedTimestamp.removeAll()
        save()
    }

    // MARK: - Persistence

    private func prune() {
        let cutoff = Date().addingTimeInterval(-maxAge)
        observations.removeAll { $0.timestamp < cutoff }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        observations = (try? JSONDecoder().decode([RatioObservation].self, from: data)) ?? []
        prune()
        Log.momentum.info("Loaded \(self.observations.count) ratio calibration observation(s)")
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(observations) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
